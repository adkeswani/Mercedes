import {Firestore, FieldValue} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

type Data = Record<string, unknown>;

function object(value: unknown): Data {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "Invalid climb data.");
  }
  return value as Data;
}

function id(value: unknown): string {
  if (typeof value !== "string" || !value || value.includes("/") ||
      Buffer.byteLength(value, "utf8") > 1500) {
    throw new HttpsError("invalid-argument", "Invalid climb identity.");
  }
  return value;
}

export function validateFreeClimb(value: unknown): Data {
  const row = object(value);
  const allowed = ["rowId", "gradingSystem", "grade", "attempts", "sent", "notes"];
  if (Object.keys(row).some((key) => !allowed.includes(key))) {
    throw new HttpsError("invalid-argument", "Unknown climb field.");
  }
  id(row.rowId);
  const pattern = row.gradingSystem === "vScale" ? /^(VB|V[0-9]|V1[0-7])$/ :
    row.gradingSystem === "yds" ? /^5\.([0-9]|1[0-5][a-d])$/ : null;
  if (!pattern || typeof row.grade !== "string" ||
      !pattern.test(row.grade) ||
      !Number.isSafeInteger(row.attempts) || (row.attempts as number) < 1 ||
      typeof row.sent !== "boolean" ||
      (row.notes != null && (typeof row.notes !== "string" ||
        row.notes.length > 4000))) {
    throw new HttpsError("invalid-argument", "Invalid grade, attempts or notes.");
  }
  return row;
}

export function summarizeFreeClimbs(rows: Data[]): Data[] {
  const grades = new Map<string, Data>();
  for (const row of rows) {
    const key = `${row.gradingSystem}/${row.grade}/${row.sent}/${row.attempts}`;
    const entry = grades.get(key);
    if (entry) entry.count = (entry.count as number) + 1;
    else grades.set(key, {
      gradingSystem: row.gradingSystem, grade: row.grade,
      sent: row.sent, attempts: row.attempts, count: 1,
    });
  }
  return [...grades.values()];
}

// Rules validate the remaining workout fields in the final client transaction.
// Only this trusted function may seal an arbitrarily sized climb collection.
export async function prepareFreeClimbingCompletion(
  db: Firestore, uid: string, input: unknown,
): Promise<void> {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to complete a workout.");
  const request = object(input);
  const instanceId = id(request.instanceId);
  const completionToken = id(request.completionToken);
  const actuals = object(request.actuals);
  const instanceRef = db.collection("workoutInstances").doc(instanceId);
  await db.runTransaction(async (transaction) => {
    const instance = (await transaction.get(instanceRef)).data();
    if (!instance) throw new HttpsError("not-found", "Workout not found.");
    if (instance.athleteId !== uid) {
      throw new HttpsError("permission-denied", "You do not own this workout.");
    }
    if (instance.status === "completed") return;
    if (instance.status !== "scheduled") {
      throw new HttpsError("failed-precondition", "Workout is not scheduled.");
    }
    const versionRef = db.collection("workoutTemplates")
      .doc(instance.workoutTemplateId).collection("workoutTemplateVersions")
      .doc(String(instance.workoutTemplateVersion));
    const version = (await transaction.get(versionRef)).data();
    if (!version || version.storageFormat !== "typedWorkoutBlocksV1" ||
        version.publishState !== "published") {
      throw new HttpsError("failed-precondition", "Pinned workout is unavailable.");
    }
    const draftRef = instanceRef.collection("completionDrafts").doc("current");
    const draft = (await transaction.get(draftRef)).data();
    if ((draft?.revision ?? null) !== (request.revision ?? null) ||
        (draft?.clientId ?? null) !== (request.clientId ?? null)) {
      throw new HttpsError("aborted", "Another tab saved progress. Reload before completing.");
    }
    const writes: Array<{slotId: string; header: Data; rows: Data[]}> = [];
    const oldRows = [];
    for (const [slotId, value] of Object.entries(actuals)) {
      id(slotId);
      const actual = object(value);
      const slotOrder = version.slots.findIndex((slot: Data) => slot.slotId === slotId);
      const slot = version.slots[slotOrder];
      const block = slot && version.blocks[slot.blockSortOrder];
      if (!block || block.type !== "freeClimbing" ||
          actual.exerciseId !== slot.exerciseId ||
          actual.climbingType !== "freeClimbing" || actual.mode !== "reps" ||
          !Array.isArray(actual.freeRows) ||
          Object.keys(actual).some((key) => ![
            "exerciseId", "mode", "climbingType", "notes", "rpe",
            "freeRows", "rowIds", "slotOrder",
          ].includes(key)) ||
          (actual.notes != null && (typeof actual.notes !== "string" ||
            actual.notes.length > 4000)) ||
          (actual.rpe != null && (!Number.isInteger(actual.rpe) ||
            (actual.rpe as number) < 1 || (actual.rpe as number) > 10))) {
        throw new HttpsError("invalid-argument", "Climbs do not match the pinned exercise.");
      }
      const rows = actual.freeRows.map(validateFreeClimb);
      if (new Set(rows.map((row) => row.rowId)).size !== rows.length) {
        throw new HttpsError("invalid-argument", "Duplicate climb identity.");
      }
      const ref = instanceRef.collection("slotResults").doc(slotId);
      oldRows.push(...(await transaction.get(ref.collection("climbs"))).docs);
      writes.push({slotId, rows, header: {
        exerciseId: slot.exerciseId, slotOrder, mode: "reps",
        climbingType: "freeClimbing", notes: actual.notes ?? null,
        rpe: actual.rpe ?? null, rowsStorageFormat: "climbDocumentsV1",
        rowCount: rows.length, gradeSummary: summarizeFreeClimbs(rows),
        draftRevision: draft?.revision ?? null,
        draftClientId: draft?.clientId ?? null,
        completionToken,
      }});
    }
    if (!writes.length) throw new HttpsError("invalid-argument", "No free climbs supplied.");
    for (const old of oldRows) transaction.delete(old.ref);
    for (const {slotId, rows, header} of writes) {
      const ref = instanceRef.collection("slotResults").doc(slotId);
      transaction.set(ref, header);
      rows.forEach((row, order) => {
        transaction.set(ref.collection("climbs").doc(row.rowId as string), {
          ...row, order,
        });
      });
    }
    transaction.update(instanceRef, {
      updatedAt: FieldValue.serverTimestamp(),
      freeClimbingSeal: {
        revision: draft?.revision ?? null, clientId: draft?.clientId ?? null,
        completionToken, slotIds: writes.map((write) => write.slotId),
      },
    });
  });
}
