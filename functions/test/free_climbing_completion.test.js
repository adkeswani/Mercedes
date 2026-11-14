const assert = require("node:assert/strict");
const test = require("node:test");
const admin = require("firebase-admin");
const {
  prepareFreeClimbingCompletion, validateFreeClimb, summarizeFreeClimbs,
} = require("../lib/free_climbing_completion");

const app = admin.initializeApp(
  {projectId: "demo-mercedes-free-climbs"}, "free-climbs-test",
);
const db = app.firestore();
test.after(() => app.delete());
const ref = db.collection("workoutInstances").doc("workout");

const row = (i) => ({
  rowId: `climb-${i}`, gradingSystem: "vScale", grade: "V2",
  attempts: 2, sent: i % 2 === 0, notes: `Climb ${i}`,
});
function request(count = 20) {
  return {
    instanceId: "workout", revision: 1, clientId: "tab",
    completionToken: "operation",
    actuals: {free: {
      exerciseId: "builtin-free-climbing", mode: "reps",
      climbingType: "freeClimbing", notes: "Session", rpe: 7,
      freeRows: Array.from({length: count}, (_, i) => row(i)),
    }},
  };
}
async function seed() {
  await db.recursiveDelete(ref);
  await ref.set({
    athleteId: "athlete", status: "scheduled",
    workoutTemplateId: "template", workoutTemplateVersion: 1,
  });
  await db.collection("workoutTemplates").doc("template")
    .collection("workoutTemplateVersions").doc("1").set({
      storageFormat: "typedWorkoutBlocksV1", publishState: "published",
      slots: [{slotId: "free", exerciseId: "builtin-free-climbing", blockSortOrder: 0}],
      blocks: [{type: "freeClimbing"}],
    });
  await ref.collection("completionDrafts").doc("current").set({
    revision: 1, clientId: "tab",
  });
}

for (const count of [20, 50, 100]) {
  test(`seals ${count} climbs, summarizes exactly and repeats safely`, async () => {
    await seed();
    await prepareFreeClimbingCompletion(db, "athlete", request(count));
    const slot = ref.collection("slotResults").doc("free");
    const header = (await slot.get()).data();
    assert.equal(header.rowCount, count);
    assert.equal(header.freeRows, undefined);
    assert.equal(header.gradeSummary.reduce((sum, item) => sum + item.count, 0), count);
    assert.equal(header.gradeSummary.filter((item) => item.sent)
      .reduce((sum, item) => sum + item.count, 0), count / 2);
    assert.equal((await slot.collection("climbs").get()).size, count);
    assert.equal((await ref.get()).data().status, "scheduled",
      "Workout status changes only in the rules-validated final transaction");
    await prepareFreeClimbingCompletion(db, "athlete", request(count));
    assert.equal((await slot.collection("climbs").get()).size, count);
  });
}

for (const [uid, code] of [["", "unauthenticated"], ["stranger", "permission-denied"]]) {
  test(`rejects caller ${uid || "anonymous"}`, async () => {
    await seed();
    await assert.rejects(prepareFreeClimbingCompletion(db, uid, request()), {code});
    assert.equal((await ref.collection("slotResults").get()).size, 0);
  });
}
test("rejects newer draft without publishing partial results", async () => {
  await seed();
  await ref.collection("completionDrafts").doc("current").update({revision: 2});
  await assert.rejects(prepareFreeClimbingCompletion(db, "athlete", request()),
    {code: "aborted"});
  assert.equal((await ref.collection("slotResults").get()).size, 0);
});
test("rejects duplicate rows, invalid actuals and incorrect exercise", async () => {
  for (const mutate of [
    (r) => r.actuals.free.freeRows.push(row(0)),
    (r) => r.actuals.free.freeRows[0].attempts = 0,
    (r) => r.actuals.free.freeRows[0].grade = "purple",
    (r) => r.actuals.free.exerciseId = "wrong",
    (r) => r.actuals.free.rpe = 11,
  ]) {
    await seed();
    const r = request();
    mutate(r);
    await assert.rejects(prepareFreeClimbingCompletion(db, "athlete", r),
      {code: "invalid-argument"});
    assert.equal((await ref.collection("slotResults").get()).size, 0);
  }
});
test("completed workout is never modified by a retry", async () => {
  await seed();
  await ref.update({status: "completed"});
  await prepareFreeClimbingCompletion(db, "athlete", request());
  assert.equal((await ref.collection("slotResults").get()).size, 0);
});
test("summary retains sent state and attempts without guessing", () => {
  assert.deepEqual(summarizeFreeClimbs([validateFreeClimb(row(0)), row(2)]),
    [{gradingSystem: "vScale", grade: "V2", attempts: 2, sent: true, count: 2}]);
});
