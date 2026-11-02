const assert = require("node:assert/strict");
const test = require("node:test");
const admin = require("firebase-admin");
const {repairWorkoutLocalDay} = require("../lib/workout_local_day");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("Run local-day tests under firebase emulators:exec.");
}
const app = admin.initializeApp(
  {projectId: "demo-mercedes-local-day-test"},
  "local-day-test",
);
const db = app.firestore();
const now = new Date("2026-11-02T04:30:00Z");
const ref = db.collection("workoutInstances").doc("today");
test.after(() => app.delete());

async function seed(overrides = {}) {
  await ref.set({
    athleteId: "athlete",
    programOwnerId: "trainer",
    assignedBy: "trainer",
    scheduledDate: "2026-11-01",
    scheduledAt: admin.firestore.Timestamp.fromDate(
      new Date("2026-11-01T00:00:00Z"),
    ),
    status: "scheduled",
    relationshipMode: "subscribed",
    athleteNotes: "Keep my notes",
    ...overrides,
  });
  await db.collection("trainerClientRelationships").doc("trainer_athlete").set({
    trainerId: "trainer",
    athleteId: "athlete",
    status: "active",
  });
}

for (const uid of ["athlete", "trainer"]) {
  test(`repairs local today after UTC rollover for ${uid}`, async () => {
    await seed();
    const before = (await ref.get()).data();
    await repairWorkoutLocalDay(
      db, uid, {instanceId: "today", utcOffsetMinutes: -480}, now,
    );
    const after = (await ref.get()).data();
    assert.equal(after.scheduledAt.toDate().toISOString(),
      "2026-11-01T08:00:00.000Z");
    delete before.scheduledAt;
    delete after.scheduledAt;
    delete after.updatedAt;
    assert.deepEqual(after, before);
    // Repeating the request must not keep extending the timestamp.
    await repairWorkoutLocalDay(
      db, uid, {instanceId: "today", utcOffsetMinutes: -480}, now,
    );
    assert.equal((await ref.get()).data().scheduledAt.toDate().toISOString(),
      "2026-11-01T08:00:00.000Z");
  });
}

for (const overrides of [
  {scheduledDate: "2026-10-31"},
  {scheduledDate: "2026-11-02"},
  {status: "completed"},
  {status: "missed"},
  {status: "cancelled"},
  {scheduledAt: null},
]) {
  test(`refuses nonmutable/legacy workout ${JSON.stringify(overrides)}`,
    async () => {
      await seed(overrides);
      const before = (await ref.get()).data();
      await assert.rejects(repairWorkoutLocalDay(
        db, "athlete", {instanceId: "today", utcOffsetMinutes: -480}, now,
      ), {code: "failed-precondition"});
      assert.deepEqual((await ref.get()).data(), before);
    });
}

for (const uid of ["", "stranger"]) {
  test(`requires authenticated ownership: ${uid || "anonymous"}`, async () => {
    await seed();
    await assert.rejects(repairWorkoutLocalDay(
      db, uid, {instanceId: "today", utcOffsetMinutes: -480}, now,
    ), {code: uid ? "permission-denied" : "unauthenticated"});
  });
}

test("requires active relationship for trainer, not for athlete", async () => {
  await seed();
  await db.collection("trainerClientRelationships").doc("trainer_athlete")
    .update({status: "ended"});
  await assert.rejects(repairWorkoutLocalDay(
    db, "trainer", {instanceId: "today", utcOffsetMinutes: -480}, now,
  ), {code: "permission-denied"});
  await repairWorkoutLocalDay(
    db, "athlete", {instanceId: "today", utcOffsetMinutes: -480}, now,
  );
});

test("validates timezone and document ID rather than accepting a device date",
  async () => {
    for (const data of [
      null, {}, {instanceId: "workouts/today", utcOffsetMinutes: -480},
      ...[-721, 841, 1.5, "yesterday"].map((offset) => ({
        instanceId: "today", utcOffsetMinutes: offset,
      })),
    ]) {
      await assert.rejects(
        repairWorkoutLocalDay(db, "athlete", data, now),
        {code: "invalid-argument"},
      );
    }
    await seed();
    await assert.rejects(repairWorkoutLocalDay(
      db, "athlete", {
        instanceId: "today", utcOffsetMinutes: 0, today: "2026-11-01",
      }, now,
    ), {code: "failed-precondition"});
  });

test("uses the current DST offset to cover the last hour of a fall-back day",
  async () => {
    await seed({
      scheduledAt: admin.firestore.Timestamp.fromDate(
        new Date("2026-11-01T07:00:00Z"),
      ),
    });

test("today's repair cannot be repeated after the local midnight boundary",
    async () => {
      await seed();
      const request = {instanceId: "today", utcOffsetMinutes: -480};
      await repairWorkoutLocalDay(
        db, "athlete", request, new Date("2026-11-02T07:59:59Z"),
      );
      const before = (await ref.get()).data();
      await assert.rejects(repairWorkoutLocalDay(
        db, "athlete", request, new Date("2026-11-02T08:00:00Z"),
      ), {code: "failed-precondition"});
      assert.deepEqual((await ref.get()).data(), before);
    });
    await repairWorkoutLocalDay(
      db, "athlete", {instanceId: "today", utcOffsetMinutes: -480},
      new Date("2026-11-02T07:30:00Z"),
    );
    assert.equal((await ref.get()).data().scheduledAt.toDate().toISOString(),
      "2026-11-01T08:00:00.000Z");
  });
