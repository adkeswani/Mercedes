import * as admin from "firebase-admin";
import {logger} from "firebase-functions";

import {
  buildReconciliationPlan,
  DesiredWorkout,
  ExistingWorkout,
  ReconciliationOperation,
} from "./reconciliation_plan";

type Firestore = admin.firestore.Firestore;
type DocumentData = admin.firestore.DocumentData;
type DocumentReference = admin.firestore.DocumentReference<DocumentData>;
type QueryDocumentSnapshot =
  admin.firestore.QueryDocumentSnapshot<DocumentData>;

interface PropagationResult {
  state: "applied" | "alreadyApplied" | "skipped";
  created: number;
  updated: number;
  cancelled: number;
}

interface ProgramVersionEntry {
  entryId: string;
  workoutTemplateId: string;
  workoutTemplateVersion: number;
  dayOffset: number;
  sortOrder: number;
}

const serverTimestamp = admin.firestore.FieldValue.serverTimestamp;
const leaseDurationMs = 9 * 60 * 1000;

export async function propagateProgramVersion(
  db: Firestore,
  programId: string,
  versionNumber: number,
  eventId: string,
  now: Date = new Date(),
): Promise<void> {
  if (!programId || versionNumber < 1 || !eventId) {
    throw new Error("Program propagation requires a valid program, version, and event");
  }
  const programRef = db.collection("programs").doc(programId);
  const versionRef = programRef
    .collection("programVersions")
    .doc(versionNumber.toString());
  const [programSnapshot, versionSnapshot] = await Promise.all([
    programRef.get(),
    versionRef.get(),
  ]);
  if (!programSnapshot.exists || !versionSnapshot.exists) {
    throw new Error(`Program ${programId} version ${versionNumber} not found`);
  }
  const ownerId = requiredString(programSnapshot.data(), "ownerId");
  const versionData = versionSnapshot.data() ?? {};
  if (requiredNumber(versionData, "versionNumber") !== versionNumber) {
    throw new Error(`Program version path does not match ${versionNumber}`);
  }
  if (versionData.propagationState === "complete") {
    return;
  }

  await versionRef.update({
    propagationState: "running",
    propagationAttempt: admin.firestore.FieldValue.increment(1),
    propagationStartedAt: serverTimestamp(),
    propagationCompletedAt: null,
    propagationFailedAt: null,
    propagationError: null,
  });

  const entries = parseProgramEntries(versionData.entries);
  const desired = await hydrateDesiredWorkouts(
    db,
    entries,
    ownerId,
    now,
  );
  const instances = await db.collection("athleteProgramInstances")
    .where("sourceProgramId", "==", programId)
    .where("status", "==", "active")
    .where("relationshipMode", "==", "subscribed")
    .get();

  const totals = {
    matchedInstances: instances.size,
    appliedInstances: 0,
    skippedInstances: 0,
    createdWorkouts: 0,
    updatedWorkouts: 0,
    cancelledWorkouts: 0,
  };
  const failures: Error[] = [];
  for (const instance of instances.docs) {
    try {
      const result = await propagateInstance({
        db,
        instance,
        programId,
        ownerId,
        versionNumber,
        desired,
        eventId,
        now,
      });
      if (result.state === "applied") {
        totals.appliedInstances++;
      } else {
        totals.skippedInstances++;
      }
      totals.createdWorkouts += result.created;
      totals.updatedWorkouts += result.updated;
      totals.cancelledWorkouts += result.cancelled;
    } catch (error: unknown) {
      const failure = asError(error);
      failures.push(failure);
      await recordInstanceFailure(
        db,
        instance.ref,
        ownerId,
        versionNumber,
        `${eventId}:${instance.id}`,
        failure,
      );
      logger.error("Program subscription propagation failed", {
        programId,
        versionNumber,
        athleteProgramInstanceId: instance.id,
        error: failure.message,
      });
    }
  }

  if (failures.length > 0) {
    const message = failures.map((failure) => failure.message).join("; ");
    await versionRef.update({
      propagationState: "failed",
      propagationFailedAt: serverTimestamp(),
      propagationError: truncate(message),
      propagationSummary: totals,
    });
    throw new Error(
      `Program ${programId} version ${versionNumber} propagation failed: ${message}`,
    );
  }

  await versionRef.update({
    propagationState: "complete",
    propagationCompletedAt: serverTimestamp(),
    propagationFailedAt: null,
    propagationError: null,
    propagationSummary: totals,
  });
  logger.info("Program subscription propagation complete", {
    programId,
    versionNumber,
    ...totals,
  });
}

async function propagateInstance(args: {
  db: Firestore;
  instance: QueryDocumentSnapshot;
  programId: string;
  ownerId: string;
  versionNumber: number;
  desired: DesiredWorkout[];
  eventId: string;
  now: Date;
}): Promise<PropagationResult> {
  const {
    db,
    instance,
    programId,
    ownerId,
    versionNumber,
    desired,
    eventId,
    now,
  } = args;
  const operationId = `${eventId}:${instance.id}`;
  const claim = await claimInstance(
    db,
    instance.ref,
    programId,
    ownerId,
    versionNumber,
    operationId,
    now,
  );
  if (claim !== "claimed") {
    return {
      state: claim,
      created: 0,
      updated: 0,
      cancelled: 0,
    };
  }

  const current = (await instance.ref.get()).data();
  if (!current) {
    throw new Error(`Athlete program instance ${instance.id} disappeared`);
  }
  const athleteId = requiredString(current, "athleteOwnerId");
  const previousVersion =
    optionalNumber(current, "sourceProgramVersion") ?? versionNumber;
  const previousEntries = await loadProgramEntries(
    db,
    programId,
    previousVersion,
  );
  const workouts = await db.collection("workoutInstances")
    .where("athleteProgramInstanceId", "==", instance.id)
    .get();
  const existing = workouts.docs.map((workout) =>
    existingWorkoutFromSnapshot(workout, instance.id, previousEntries)
  );
  const today = isoDate(now);
  const plan = buildReconciliationPlan(
    existing,
    desired.map((workout) => ({
      ...workout,
      scheduledDate: addDays(
        requiredString(current, "startDate"),
        workout.dayOffset,
      ),
    })),
    versionNumber,
    today,
  );

  const applied = {created: 0, updated: 0, cancelled: 0};
  for (const operation of plan) {
    const changed = await executeOperation({
      db,
      operation,
      instanceRef: instance.ref,
      programId,
      ownerId,
      athleteId,
      versionNumber,
      operationId,
      today,
    });
    if (changed) {
      applied[operation.kind === "create" ? "created" :
        operation.kind === "update" ? "updated" : "cancelled"]++;
    }
  }

  const desiredDates = desired.map((workout) =>
    addDays(
      requiredString(current, "startDate"),
      workout.dayOffset,
    )
  );
  const completed = await db.runTransaction(async (transaction) => {
    const latest = await transaction.get(instance.ref);
    if (!latest.exists || !holdsPropagationLease(
      latest.data() ?? {},
      programId,
      ownerId,
      versionNumber,
      operationId,
    )) {
      return false;
    }
    const relationshipRef = relationshipReference(
      db,
      ownerId,
      athleteId,
    );
    const relationship = await transaction.get(relationshipRef);
    if (relationship.data()?.status !== "active") {
      return false;
    }
    transaction.update(instance.ref, {
      sourceProgramVersion: versionNumber,
      expectedEndDate: desiredDates.length === 0 ?
        requiredString(current, "startDate") :
        desiredDates.reduce((latest, value) => value > latest ? value : latest),
      workoutCount: desired.length,
      propagationState: "complete",
      propagationTargetVersion: versionNumber,
      propagationOperationId: operationId,
      propagationLeaseExpiresAt: null,
      propagationCompletedAt: serverTimestamp(),
      propagationFailedAt: null,
      propagationError: null,
      propagationCreatedCount: applied.created,
      propagationUpdatedCount: applied.updated,
      propagationCancelledCount: applied.cancelled,
      updatedAt: serverTimestamp(),
      updatedBy: "system",
    });
    return true;
  });
  return {
    state: completed ? "applied" : "skipped",
    ...applied,
  };
}

async function claimInstance(
  db: Firestore,
  instanceRef: DocumentReference,
  programId: string,
  ownerId: string,
  versionNumber: number,
  operationId: string,
  now: Date,
): Promise<"claimed" | "alreadyApplied" | "skipped"> {
  return db.runTransaction(async (transaction) => {
    const instance = await transaction.get(instanceRef);
    if (!instance.exists) {
      return "skipped";
    }
    const data = instance.data() ?? {};
    if (data.sourceProgramId !== programId) {
      throw new Error(`Program instance ${instanceRef.id} source mismatch`);
    }
    if (data.assigningTrainerId !== ownerId) {
      throw new Error(`Program instance ${instanceRef.id} owner mismatch`);
    }
    if ((optionalNumber(data, "sourceProgramVersion") ?? 0) >= versionNumber) {
      return "alreadyApplied";
    }
    if (
      data.status !== "active" ||
      data.relationshipMode !== "subscribed" ||
      data.unlinkedAt != null
    ) {
      return "skipped";
    }
    const athleteId = requiredString(data, "athleteOwnerId");
    const relationship = await transaction.get(
      relationshipReference(db, ownerId, athleteId),
    );
    if (relationship.data()?.status !== "active") {
      return "skipped";
    }
    const activeOperation = optionalString(data, "propagationOperationId");
    const lease = data.propagationLeaseExpiresAt;
    if (
      data.propagationState === "running" &&
      activeOperation !== operationId &&
      lease instanceof admin.firestore.Timestamp &&
      lease.toDate() > now
    ) {
      throw new Error(`Program instance ${instanceRef.id} is already reconciling`);
    }
    transaction.update(instanceRef, {
      propagationState: "running",
      propagationTargetVersion: versionNumber,
      propagationAttempt: admin.firestore.FieldValue.increment(1),
      propagationOperationId: operationId,
      propagationLeaseExpiresAt: admin.firestore.Timestamp.fromDate(
        new Date(now.valueOf() + leaseDurationMs),
      ),
      propagationStartedAt: serverTimestamp(),
      propagationCompletedAt: null,
      propagationFailedAt: null,
      propagationError: null,
      updatedAt: serverTimestamp(),
      updatedBy: "system",
    });
    return "claimed";
  });
}

async function executeOperation(args: {
  db: Firestore;
  operation: ReconciliationOperation;
  instanceRef: DocumentReference;
  programId: string;
  ownerId: string;
  athleteId: string;
  versionNumber: number;
  operationId: string;
  today: string;
}): Promise<boolean> {
  const {
    db,
    operation,
    instanceRef,
    programId,
    ownerId,
    athleteId,
    versionNumber,
    operationId,
    today,
  } = args;
  const workoutRef = operation.kind === "create" ?
    db.collection("workoutInstances").doc(
      `${instanceRef.id}-propagated-${operation.desired.entryId}`,
    ) :
    db.collection("workoutInstances").doc(operation.existingId);

  return db.runTransaction(async (transaction) => {
    const instance = await transaction.get(instanceRef);
    const relationship = await transaction.get(
      relationshipReference(db, ownerId, athleteId),
    );
    const workout = await transaction.get(workoutRef);
    if (
      !instance.exists ||
      !holdsPropagationLease(
        instance.data() ?? {},
        programId,
        ownerId,
        versionNumber,
        operationId,
      ) ||
      relationship.data()?.status !== "active"
    ) {
      return false;
    }

    if (operation.kind === "create") {
      if (workout.exists) {
        verifyWorkoutScope(workout.data() ?? {}, instanceRef.id, ownerId, athleteId);
        return false;
      }
      transaction.create(workoutRef, newWorkoutData(
        operation.desired,
        instanceRef.id,
        programId,
        ownerId,
        athleteId,
        versionNumber,
      ));
      return true;
    }

    if (!workout.exists) {
      return false;
    }
    const data = workout.data() ?? {};
    verifyWorkoutScope(data, instanceRef.id, ownerId, athleteId);
    if (
      data.status !== "scheduled" ||
      data.relationshipMode !== "subscribed" ||
      requiredString(data, "scheduledDate") < today
    ) {
      return false;
    }
    if (operation.kind === "cancel") {
      transaction.update(workoutRef, {
        status: "cancelled",
        propagationAppliedVersion: versionNumber,
        propagationAction: "cancelled",
        updatedAt: serverTimestamp(),
      });
      return true;
    }
    transaction.update(workoutRef, {
      programVersion: versionNumber,
      programEntryId: operation.desired.entryId,
      programEntrySortOrder: operation.desired.sortOrder,
      workoutTemplateId: operation.desired.workoutTemplateId,
      workoutTemplateVersion: operation.desired.workoutTemplateVersion,
      workoutType: operation.desired.workoutType,
      scheduledDate: operation.desired.scheduledDate,
      scheduledAt: admin.firestore.Timestamp.fromDate(
        new Date(`${operation.desired.scheduledDate}T00:00:00.000Z`),
      ),
      propagationAppliedVersion: versionNumber,
      propagationAction: "updated",
      updatedAt: serverTimestamp(),
    });
    return true;
  });
}

function newWorkoutData(
  desired: DesiredWorkout,
  instanceId: string,
  programId: string,
  ownerId: string,
  athleteId: string,
  versionNumber: number,
): DocumentData {
  return {
    programId,
    programOwnerId: ownerId,
    programVersion: versionNumber,
    programEntryId: desired.entryId,
    programEntrySortOrder: desired.sortOrder,
    athleteProgramInstanceId: instanceId,
    programAssignmentId: instanceId,
    relationshipMode: "subscribed",
    athleteId,
    workoutTemplateId: desired.workoutTemplateId,
    workoutTemplateVersion: desired.workoutTemplateVersion,
    scheduledDate: desired.scheduledDate,
    scheduledAt: admin.firestore.Timestamp.fromDate(
      new Date(`${desired.scheduledDate}T00:00:00.000Z`),
    ),
    workoutType: desired.workoutType,
    assignedBy: ownerId,
    assignedAt: serverTimestamp(),
    status: "scheduled",
    completedAt: null,
    missedAt: null,
    rpe: null,
    durationMinutes: null,
    loadPoints: null,
    loadPointsOverride: null,
    loadPointsOverriddenBy: null,
    loadPointsOverriddenAt: null,
    loadModelVersion: 1,
    loadStrategyId: null,
    recurrence: null,
    isRecurrenceRoot: false,
    recurrenceRootId: null,
    actualsStorageFormat: "slotResultsSubcollection",
    actualSlotIds: [],
    actuals: [],
    athleteNotes: null,
    propagationAppliedVersion: versionNumber,
    propagationAction: "created",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

async function hydrateDesiredWorkouts(
  db: Firestore,
  entries: ProgramVersionEntry[],
  ownerId: string,
  now: Date,
): Promise<DesiredWorkout[]> {
  const templateIds = [...new Set(entries.map((entry) =>
    entry.workoutTemplateId
  ))];
  const headers = new Map<string, DocumentData>();
  await Promise.all(templateIds.map(async (templateId) => {
    const header = await db.collection("workoutTemplates").doc(templateId).get();
    if (!header.exists) {
      throw new Error(`Workout template ${templateId} not found`);
    }
    const data = header.data() ?? {};
    const templateOwner = optionalString(data, "ownerId") ??
      requiredString(data, "createdBy");
    if (templateOwner !== ownerId) {
      throw new Error(`Workout template ${templateId} is not owned by ${ownerId}`);
    }
    headers.set(templateId, data);
  }));
  await Promise.all(entries.map(async (entry) => {
    const version = await db.collection("workoutTemplates")
      .doc(entry.workoutTemplateId)
      .collection("workoutTemplateVersions")
      .doc(entry.workoutTemplateVersion.toString())
      .get();
    const publishState = version.data()?.publishState;
    if (!version.exists || publishState === "draft" || publishState === "deleting") {
      throw new Error(
        `Workout ${entry.workoutTemplateId} version ` +
        `${entry.workoutTemplateVersion} is not published`,
      );
    }
  }));
  const anchor = isoDate(now);
  return entries.map((entry) => ({
    entryId: entry.entryId,
    dayOffset: entry.dayOffset,
    workoutTemplateId: entry.workoutTemplateId,
    workoutTemplateVersion: entry.workoutTemplateVersion,
    scheduledDate: addDays(anchor, entry.dayOffset),
    sortOrder: entry.sortOrder,
    workoutType: optionalString(
      headers.get(entry.workoutTemplateId),
      "workoutType",
    ) ?? "fullBody",
  }));
}

async function loadProgramEntries(
  db: Firestore,
  programId: string,
  versionNumber: number,
): Promise<ProgramVersionEntry[]> {
  const snapshot = await db.collection("programs").doc(programId)
    .collection("programVersions").doc(versionNumber.toString()).get();
  return snapshot.exists ? parseProgramEntries(snapshot.data()?.entries) : [];
}

function parseProgramEntries(value: unknown): ProgramVersionEntry[] {
  if (!Array.isArray(value)) {
    throw new Error("Program version entries must be a list");
  }
  const entries = value.map((raw, index) => {
    if (!isRecord(raw)) {
      throw new Error(`Program entry ${index} must be a map`);
    }
    const sortOrder = optionalNumber(raw, "sortOrder") ?? index;
    const entry: ProgramVersionEntry = {
      entryId: optionalString(raw, "entryId") ?? `legacy-${sortOrder}`,
      workoutTemplateId: requiredString(raw, "workoutTemplateId"),
      workoutTemplateVersion: requiredNumber(raw, "workoutTemplateVersion"),
      dayOffset: optionalNumber(raw, "dayOffset") ?? 0,
      sortOrder,
    };
    if (
      entry.entryId.includes("/") ||
      entry.entryId.length > 200 ||
      entry.workoutTemplateVersion < 1 ||
      entry.dayOffset < 0 ||
      entry.sortOrder < 0
    ) {
      throw new Error(`Program entry ${index} is invalid`);
    }
    return entry;
  });
  if (new Set(entries.map((entry) => entry.entryId)).size !== entries.length) {
    throw new Error("Program version contains duplicate entry IDs");
  }
  return entries;
}

function existingWorkoutFromSnapshot(
  workout: QueryDocumentSnapshot,
  instanceId: string,
  previousEntries: ProgramVersionEntry[],
): ExistingWorkout {
  const data = workout.data();
  const indexPrefix = `${instanceId}-`;
  const suffix = workout.id.startsWith(indexPrefix) ?
    workout.id.slice(indexPrefix.length) :
    "";
  const legacyIndex = /^\d+$/.test(suffix) ? Number(suffix) : undefined;
  return {
    id: workout.id,
    programEntryId: optionalString(data, "programEntryId"),
    legacyEntryId: legacyIndex == null ?
      undefined :
      previousEntries[legacyIndex]?.entryId,
    programVersion: optionalNumber(data, "programVersion") ?? 0,
    workoutTemplateId: optionalString(data, "workoutTemplateId") ?? "",
    workoutTemplateVersion:
      optionalNumber(data, "workoutTemplateVersion") ?? 1,
    scheduledDate: optionalString(data, "scheduledDate") ?? "",
    sortOrder: optionalNumber(data, "programEntrySortOrder"),
    workoutType: optionalString(data, "workoutType") ?? "fullBody",
    status: optionalString(data, "status") ?? "scheduled",
    relationshipMode: optionalString(data, "relationshipMode"),
  };
}

function holdsPropagationLease(
  data: DocumentData,
  programId: string,
  ownerId: string,
  versionNumber: number,
  operationId: string,
): boolean {
  return data.sourceProgramId === programId &&
    data.assigningTrainerId === ownerId &&
    data.status === "active" &&
    data.relationshipMode === "subscribed" &&
    data.unlinkedAt == null &&
    data.propagationState === "running" &&
    data.propagationTargetVersion === versionNumber &&
    data.propagationOperationId === operationId;
}

function verifyWorkoutScope(
  data: DocumentData,
  instanceId: string,
  ownerId: string,
  athleteId: string,
): void {
  if (
    data.athleteProgramInstanceId !== instanceId ||
    data.programAssignmentId !== instanceId ||
    data.programOwnerId !== ownerId ||
    data.athleteId !== athleteId
  ) {
    throw new Error(`Workout ownership mismatch for program instance ${instanceId}`);
  }
}

async function recordInstanceFailure(
  db: Firestore,
  instanceRef: DocumentReference,
  ownerId: string,
  versionNumber: number,
  operationId: string,
  error: Error,
): Promise<void> {
  await db.runTransaction(async (transaction) => {
    const instance = await transaction.get(instanceRef);
    if (!instance.exists) return;
    const data = instance.data() ?? {};
    const athleteId = optionalString(data, "athleteOwnerId");
    if (
      data.assigningTrainerId !== ownerId ||
      data.relationshipMode !== "subscribed" ||
      !athleteId
    ) {
      return;
    }
    const relationship = await transaction.get(
      relationshipReference(db, ownerId, athleteId),
    );
    if (relationship.data()?.status !== "active") {
      return;
    }
    if (
      data.propagationTargetVersion !== versionNumber ||
      data.propagationOperationId !== operationId
    ) {
      return;
    }
    transaction.update(instanceRef, {
      propagationState: "failed",
      propagationLeaseExpiresAt: null,
      propagationFailedAt: serverTimestamp(),
      propagationError: truncate(error.message),
      updatedAt: serverTimestamp(),
      updatedBy: "system",
    });
  });
}

function relationshipReference(
  db: Firestore,
  trainerId: string,
  athleteId: string,
): DocumentReference {
  return db.collection("trainerClientRelationships")
    .doc(`${trainerId}_${athleteId}`);
}

function addDays(date: string, days: number): string {
  const value = new Date(`${date}T00:00:00.000Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

function isoDate(value: Date): string {
  return value.toISOString().slice(0, 10);
}

function requiredString(
  data: DocumentData | undefined,
  field: string,
): string {
  const value = data?.[field];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${field} must be a non-empty string`);
  }
  return value;
}

function optionalString(
  data: DocumentData | undefined,
  field: string,
): string | undefined {
  const value = data?.[field];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function requiredNumber(data: DocumentData, field: string): number {
  const value = data[field];
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new Error(`${field} must be an integer`);
  }
  return value;
}

function optionalNumber(
  data: DocumentData,
  field: string,
): number | undefined {
  const value = data[field];
  return typeof value === "number" && Number.isInteger(value) ?
    value :
    undefined;
}

function isRecord(value: unknown): value is DocumentData {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asError(value: unknown): Error {
  return value instanceof Error ? value : new Error(String(value));
}

function truncate(value: string): string {
  return value.length <= 1000 ? value : value.slice(0, 1000);
}
