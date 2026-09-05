const assert = require("node:assert/strict");
const test = require("node:test");

const {
  buildReconciliationPlan,
} = require("../lib/reconciliation_plan");

const today = "2026-09-05";

function desired(overrides = {}) {
  return {
    entryId: "entry-a",
    dayOffset: 9,
    workoutTemplateId: "workout-a",
    workoutTemplateVersion: 2,
    scheduledDate: "2026-09-10",
    sortOrder: 0,
    workoutType: "strength",
    ...overrides,
  };
}

function existing(overrides = {}) {
  return {
    id: "instance-workout-a",
    programEntryId: "entry-a",
    programVersion: 1,
    workoutTemplateId: "workout-a",
    workoutTemplateVersion: 1,
    scheduledDate: "2026-09-08",
    sortOrder: 0,
    workoutType: "strength",
    status: "scheduled",
    relationshipMode: "subscribed",
    ...overrides,
  };
}

test("plans additions, removals, substitutions, ordering, and rescheduling", () => {
  const plan = buildReconciliationPlan(
    [
      existing(),
      existing({
        id: "removed",
        programEntryId: "entry-removed",
      }),
    ],
    [
      desired({
        workoutTemplateId: "workout-substitute",
        scheduledDate: "2026-09-12",
        sortOrder: 1,
      }),
      desired({
        entryId: "entry-added",
        workoutTemplateId: "workout-new",
        sortOrder: 0,
      }),
    ],
    2,
    today,
  );

  assert.deepEqual(plan.map((operation) => operation.kind), [
    "update",
    "cancel",
    "create",
  ]);
  assert.equal(plan[0].desired.workoutTemplateVersion, 2);
  assert.equal(plan[0].desired.sortOrder, 1);
});

test("never changes past, completed, missed, copied, or unlinked workouts", () => {
  const protectedWorkouts = [
    existing({id: "past", scheduledDate: "2026-09-04"}),
    existing({id: "complete", status: "completed"}),
    existing({id: "missed", status: "missed"}),
    existing({id: "copied", relationshipMode: "copied"}),
    existing({id: "unlinked", relationshipMode: undefined}),
  ];

  const plan = buildReconciliationPlan(
    protectedWorkouts,
    [desired({scheduledDate: "2026-09-04"})],
    2,
    today,
  );
  assert.deepEqual(plan, []);
});

test("retries are idempotent after the target version is already applied", () => {
  const target = desired();
  const plan = buildReconciliationPlan(
    [
      existing({
        programVersion: 2,
        workoutTemplateVersion: 2,
        scheduledDate: target.scheduledDate,
      }),
    ],
    [target],
    2,
    today,
  );
  assert.deepEqual(plan, []);
});

test("legacy entry identities reconcile without rewriting history", () => {
  const plan = buildReconciliationPlan(
    [
      existing({
        programEntryId: undefined,
        legacyEntryId: "legacy-0",
      }),
    ],
    [desired({entryId: "legacy-0"})],
    2,
    today,
  );
  assert.equal(plan.length, 1);
  assert.equal(plan[0].kind, "update");
});

test("a desired date in the past cancels only the mutable future occurrence", () => {
  const plan = buildReconciliationPlan(
    [existing()],
    [desired({scheduledDate: "2026-09-01"})],
    2,
    today,
  );
  assert.deepEqual(plan, [
    {kind: "cancel", existingId: "instance-workout-a", entryId: "entry-a"},
  ]);
});

test("rejects duplicate desired and materialized entry identities", () => {
  assert.throws(
    () => buildReconciliationPlan([], [desired(), desired()], 2, today),
    /Duplicate desired entry ID/,
  );
  assert.throws(
    () => buildReconciliationPlan(
      [existing(), existing({id: "duplicate"})],
      [desired()],
      2,
      today,
    ),
    /Duplicate eligible workout/,
  );
});
