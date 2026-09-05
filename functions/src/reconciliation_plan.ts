export interface DesiredWorkout {
  entryId: string;
  dayOffset: number;
  workoutTemplateId: string;
  workoutTemplateVersion: number;
  scheduledDate: string;
  sortOrder: number;
  workoutType: string;
}

export interface ExistingWorkout {
  id: string;
  programEntryId?: string;
  legacyEntryId?: string;
  programVersion: number;
  workoutTemplateId: string;
  workoutTemplateVersion: number;
  scheduledDate: string;
  sortOrder?: number;
  workoutType: string;
  status: string;
  relationshipMode?: string;
}

export interface UpdateOperation {
  kind: "update";
  existingId: string;
  desired: DesiredWorkout;
}

export interface CancelOperation {
  kind: "cancel";
  existingId: string;
  entryId: string;
}

export interface CreateOperation {
  kind: "create";
  desired: DesiredWorkout;
}

export type ReconciliationOperation =
  UpdateOperation | CancelOperation | CreateOperation;

export function buildReconciliationPlan(
  existing: ExistingWorkout[],
  desired: DesiredWorkout[],
  targetVersion: number,
  today: string,
): ReconciliationOperation[] {
  if (targetVersion < 1) {
    throw new Error("targetVersion must be at least 1");
  }
  validateDate(today, "today");

  const desiredById = new Map<string, DesiredWorkout>();
  for (const workout of desired) {
    validateDesired(workout);
    if (desiredById.has(workout.entryId)) {
      throw new Error(`Duplicate desired entry ID ${workout.entryId}`);
    }
    desiredById.set(workout.entryId, workout);
  }

  const eligibleById = new Map<string, ExistingWorkout>();
  for (const workout of existing) {
    if (
      workout.status !== "scheduled" ||
      workout.relationshipMode !== "subscribed" ||
      workout.scheduledDate < today
    ) {
      continue;
    }
    const entryId = workout.programEntryId ?? workout.legacyEntryId;
    if (!entryId) {
      throw new Error(`Workout ${workout.id} has no source entry identity`);
    }
    if (eligibleById.has(entryId)) {
      throw new Error(`Duplicate eligible workout for entry ${entryId}`);
    }
    eligibleById.set(entryId, workout);
  }

  const operations: ReconciliationOperation[] = [];
  const matched = new Set<string>();
  for (const [entryId, workout] of eligibleById) {
    const target = desiredById.get(entryId);
    if (!target || target.scheduledDate < today) {
      operations.push({kind: "cancel", existingId: workout.id, entryId});
      continue;
    }
    matched.add(entryId);
    if (!matchesTarget(workout, target, targetVersion)) {
      operations.push({
        kind: "update",
        existingId: workout.id,
        desired: target,
      });
    }
  }

  for (const workout of desired) {
    if (workout.scheduledDate >= today && !matched.has(workout.entryId)) {
      operations.push({kind: "create", desired: workout});
    }
  }
  return operations;
}

function matchesTarget(
  existing: ExistingWorkout,
  desired: DesiredWorkout,
  targetVersion: number,
): boolean {
  return existing.programEntryId === desired.entryId &&
    existing.programVersion === targetVersion &&
    existing.workoutTemplateId === desired.workoutTemplateId &&
    existing.workoutTemplateVersion === desired.workoutTemplateVersion &&
    existing.scheduledDate === desired.scheduledDate &&
    existing.sortOrder === desired.sortOrder &&
    existing.workoutType === desired.workoutType;
}

function validateDesired(workout: DesiredWorkout): void {
  if (
    workout.entryId.length === 0 ||
    workout.entryId.length > 200 ||
    workout.entryId.includes("/")
  ) {
    throw new Error("Program entry IDs must be 1-200 characters without '/'");
  }
  if (!workout.workoutTemplateId || workout.workoutTemplateVersion < 1) {
    throw new Error(`Invalid workout reference for ${workout.entryId}`);
  }
  if (workout.sortOrder < 0) {
    throw new Error(`Invalid sort order for ${workout.entryId}`);
  }
  if (workout.dayOffset < 0) {
    throw new Error(`Invalid day offset for ${workout.entryId}`);
  }
  validateDate(workout.scheduledDate, "scheduledDate");
}

function validateDate(value: string, field: string): void {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`${field} must use YYYY-MM-DD`);
  }
  const date = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(date.valueOf()) || date.toISOString().slice(0, 10) !== value) {
    throw new Error(`${field} must be a valid date`);
  }
}
