import {FieldPath, FieldValue} from "firebase-admin/firestore";
import type {DocumentData, Firestore, QueryDocumentSnapshot, Transaction} from "firebase-admin/firestore";
import {logger} from "firebase-functions";

export async function latestPublishedWorkout(
  db: Firestore,
  templateId: string,
  ownerId: string,
  transaction?: Transaction,
): Promise<{version: number; workoutType: string}> {
  const templateRef = db.collection("workoutTemplates").doc(templateId);
  const template = transaction ?
    await transaction.get(templateRef) : await templateRef.get();
  const data = template.data();
  verifyOwnership(data, ownerId, templateId);
  if (data?.deletedAt != null) {
    throw new Error(`Workout template ${templateId} is deleted`);
  }
  const version = positiveInteger(data?.currentVersion, "currentVersion");
  const versionRef = templateRef.collection("workoutTemplateVersions")
    .doc(String(version));
  const published = transaction ?
    await transaction.get(versionRef) : await versionRef.get();
  if (!published.exists ||
      published.data()?.versionNumber !== version ||
      (published.data()?.publishState != null &&
       published.data()?.publishState !== "published")) {
    throw new Error(`Workout ${templateId} version ${version} is not published`);
  }
  if (published.data()?.ownerId != null && published.data()?.ownerId !== ownerId) {
    throw new Error(`Ownership mismatch for workout ${templateId} version ${version}`);
  }
  const workoutType = data?.workoutType ?? "fullBody";
  if (typeof workoutType !== "string" || !workoutType) {
    throw new Error(`Workout template ${templateId} has an invalid workout type`);
  }
  return {version, workoutType};
}

export function hasWorkoutProgress(data: DocumentData): boolean {
  return data.freeClimbingSeal != null ||
    (Array.isArray(data.actualSlotIds) && data.actualSlotIds.length > 0) ||
    (Array.isArray(data.actuals) && data.actuals.length > 0) ||
    (data.actualsBySlot != null && typeof data.actualsBySlot === "object" &&
     Object.keys(data.actualsBySlot).length > 0) ||
    data.completedAt != null || data.rpe != null || data.durationMinutes != null;
}

export async function refreshWorkoutVersion(
  db: Firestore,
  instanceId: string,
  now: Date = new Date(),
): Promise<boolean> {
  const ref = db.collection("workoutInstances").doc(instanceId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return false;
    const workout = snapshot.data()!;
    if (workout.status !== "scheduled" || hasWorkoutProgress(workout)) return false;
    const date = requiredString(workout.scheduledDate, "scheduledDate");
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) ||
        new Date(`${date}T00:00:00Z`).toISOString().slice(0, 10) !== date) {
      throw new Error(`Workout ${instanceId} has an invalid scheduled date`);
    }
    if (date < now.toISOString().slice(0, 10)) return false;
    const templateId = requiredString(workout.workoutTemplateId, "workoutTemplateId");
    const template = await transaction.get(db.collection("workoutTemplates").doc(templateId));
    if (!template.exists) throw new Error(`Workout template ${templateId} not found`);
    const ownerId = requiredString(
      template.data()?.ownerId ?? template.data()?.createdBy, "ownerId",
    );
    const latest = await latestPublishedWorkout(db, templateId, ownerId, transaction);
    const current = positiveInteger(workout.workoutTemplateVersion, "workoutTemplateVersion");
    if (current >= latest.version) return false;
    const draft = await transaction.get(ref.collection("completionDrafts").doc("current"));
    if (draft.exists) return false;
    const athleteId = requiredString(workout.athleteId, "athleteId");
    const programId = requiredString(workout.programId, "programId");
    const program = await transaction.get(db.collection("programs").doc(programId));
    verifyOwnership(program.data(), ownerId, programId);
    if (program.data()?.deletedAt != null) return false;
    if (program.data()?.type === "personal" && athleteId !== ownerId) {
      throw new Error(`Personal program ${programId} only permits self-assignment`);
    }
    if ((workout.programOwnerId != null && workout.programOwnerId !== ownerId) ||
        (workout.assignedBy !== ownerId && workout.assignedBy !== athleteId)) {
      throw new Error(`Workout ${instanceId} assignment ownership mismatch`);
    }
    if (athleteId !== ownerId) {
      const relationship = await transaction.get(
        db.collection("trainerClientRelationships").doc(`${ownerId}_${athleteId}`),
      );
      const data = relationship.data();
      if (data?.status !== "active" || data.trainerId !== ownerId ||
          data.athleteId !== athleteId || data.deletedAt != null) return false;
    }
    const groupId = workout.athleteProgramInstanceId ?? workout.programAssignmentId;
    if (groupId != null) {
      const group = await transaction.get(
        db.collection("athleteProgramInstances").doc(requiredString(groupId, "program instance")),
      );
      if (!group.exists && workout.athleteProgramInstanceId != null) {
        throw new Error(`Program instance ${groupId} not found`);
      }
      if (group.exists) {
        const data = group.data()!;
        if (data.athleteOwnerId !== athleteId || data.assigningTrainerId !== ownerId ||
            data.sourceProgramId !== programId) {
          throw new Error(`Workout ${instanceId} program instance ownership mismatch`);
        }
        if (data.status !== "active") return false;
      }
    }
    transaction.update(ref, {
      workoutTemplateVersion: latest.version,
      workoutType: latest.workoutType,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

export async function propagateWorkoutVersion(
  db: Firestore,
  templateId: string,
  version: number,
  now: Date = new Date(),
): Promise<void> {
  positiveInteger(version, "version");
  const templateRef = db.collection("workoutTemplates").doc(templateId);
  const template = await templateRef.get();
  const ownerId = requiredString(
    template.data()?.ownerId ?? template.data()?.createdBy, "ownerId",
  );
  await latestPublishedWorkout(db, templateId, ownerId);
  const auditRef = templateRef.collection("workoutTemplateVersions").doc(String(version));
  const updateAudit = (state: string, values: DocumentData) =>
    db.runTransaction(async (transaction) => {
      const header = await transaction.get(templateRef);
      verifyOwnership(header.data(), ownerId, templateId);
      const published = await transaction.get(auditRef);
      if (!published.exists || published.data()?.versionNumber !== version ||
          (published.data()?.publishState != null &&
           published.data()?.publishState !== "published")) {
        throw new Error(`Workout ${templateId} version ${version} is not published`);
      }
      if (published.data()?.ownerId != null && published.data()?.ownerId !== ownerId) {
        throw new Error(`Ownership mismatch for workout ${templateId} version ${version}`);
      }
      transaction.update(auditRef, {
        propagationState: state,
        ...values,
      });
    });
  await updateAudit("running", {
    propagationAttempt: FieldValue.increment(1),
    propagationStartedAt: FieldValue.serverTimestamp(),
    propagationError: null,
  });
  const query = db.collection("workoutInstances")
    .where("workoutTemplateId", "==", templateId)
    .where("status", "==", "scheduled")
    .where("scheduledDate", ">=", now.toISOString().slice(0, 10))
    .orderBy("scheduledDate")
    .orderBy(FieldPath.documentId())
    .limit(200);
  let cursor: QueryDocumentSnapshot | undefined;
  let matched = 0;
  let updated = 0;
  try {
    while (true) {
      const page = await (cursor ? query.startAfter(cursor) : query).get();
      if (page.empty) break;
      for (let offset = 0; offset < page.docs.length; offset += 10) {
        const results = await Promise.all(page.docs.slice(offset, offset + 10)
          .map((workout) => refreshWorkoutVersion(db, workout.id, now)));
        matched += results.length;
        updated += results.filter(Boolean).length;
      }
      cursor = page.docs[page.docs.length - 1];
    }
    await updateAudit("complete", {
      propagationCompletedAt: FieldValue.serverTimestamp(),
      propagationFailedAt: null,
      propagationError: null,
      propagationSummary: {matched, updated, skipped: matched - updated},
    });
    logger.info("Workout version propagation complete", {templateId, version, matched, updated});
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await updateAudit("failed", {
      propagationFailedAt: FieldValue.serverTimestamp(),
      propagationError: message.slice(0, 4000),
    });
    logger.error("Workout version propagation failed", {templateId, version, error});
    throw error;
  }
}

function verifyOwnership(data: DocumentData | undefined, ownerId: string, id: string): void {
  if (!data || (data.ownerId ?? data.createdBy) !== ownerId) {
    throw new Error(`Ownership mismatch for ${id}`);
  }
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || !value || value.includes("/")) {
    throw new Error(`${field} must be a non-empty identifier or date`);
  }
  return value;
}

function positiveInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw new Error(`${field} must be a positive integer`);
  }
  return value;
}
