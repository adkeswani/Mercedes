const assert = require("node:assert/strict");
const test = require("node:test");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {propagateWorkoutVersion, refreshWorkoutVersion} =
  require("../lib/workout_version_propagation");
const {propagateProgramVersion} = require("../lib/subscription_propagation");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("Workout propagation tests require the Firestore emulator.");
}
const app = initializeApp({projectId: "demo-mercedes-workout-updates"});
const db = getFirestore(app);
const now = new Date("2026-01-01T12:00:00Z");
const template = db.collection("workoutTemplates").doc("template");
const program = db.collection("programs").doc("program");

async function reset() {
  for (const name of ["workoutTemplates", "programs", "workoutInstances",
    "athleteProgramInstances", "trainerClientRelationships"]) {
    await db.recursiveDelete(db.collection(name));
  }
  await program.set({ownerId: "owner", type: "assignable", currentVersion: 1});
  await publish(1);
}
async function publish(version, publishState = "published") {
  await template.set({ownerId: "owner", currentVersion: version, workoutType: "limit"});
  await template.collection("workoutTemplateVersions").doc(String(version))
    .set({versionNumber: version, ownerId: "owner", publishState});
}
async function workout(id, overrides = {}) {
  const ref = db.collection("workoutInstances").doc(id);
  await ref.set({
    programId: "program", programOwnerId: "owner", assignedBy: "owner",
    athleteId: "owner", workoutTemplateId: "template", workoutTemplateVersion: 1,
    scheduledDate: "2026-01-02", status: "scheduled", workoutType: "fullBody",
    actualSlotIds: [], actuals: [], rpe: null, durationMinutes: null,
    athleteNotes: "keep notes", ...overrides,
  });
  return ref;
}
async function group(id, mode = "subscribed", overrides = {}) {
  const ref = db.collection("athleteProgramInstances").doc(id);
  await ref.set({
    athleteOwnerId: "owner", assigningTrainerId: "owner", sourceProgramId: "program",
    sourceProgramVersion: 1, relationshipMode: mode, status: "active",
    startDate: "2026-01-02", unlinkedAt: null, ...overrides,
  });
  return ref;
}
test.beforeEach(reset);

test("updates self-assigned and recurring workouts without changing scheduling or notes", async () => {
  const refs = [
    await workout("single"),
    await workout("root", {isRecurrenceRoot: true, recurrence: {pattern: "weekly"}}),
    await workout("child", {recurrenceRootId: "root", scheduledDate: "2026-01-09"}),
  ];
  await publish(2);
  await propagateWorkoutVersion(db, "template", 2, now);
  for (const ref of refs) {
    const data = (await ref.get()).data();
    assert.equal(data.workoutTemplateVersion, 2);
    assert.equal(data.workoutType, "limit");
    assert.equal(data.athleteNotes, "keep notes");
  }
  assert.equal((await refs[1].get()).data().isRecurrenceRoot, true);
  assert.equal((await refs[2].get()).data().recurrenceRootId, "root");
  assert.equal((await refs[2].get()).data().scheduledDate, "2026-01-09");
});

test("copied and subscribed program workouts track contents but not schedule or program version", async () => {
  for (const mode of ["copied", "subscribed"]) {
    const parent = await group(mode, mode);
    const before = (await parent.get()).data();
    const ref = await workout(mode, {
      athleteProgramInstanceId: mode, programAssignmentId: mode, relationshipMode: mode,
      programVersion: 1, programEntryId: "entry", scheduledDate: "2026-01-08",
    });
    await publish(2);
    assert.equal(await refreshWorkoutVersion(db, mode, now), true);
    const after = (await ref.get()).data();
    assert.equal(after.workoutTemplateVersion, 2);
    assert.equal(after.programVersion, 1);
    assert.equal(after.programEntryId, "entry");
    assert.equal(after.scheduledDate, "2026-01-08");
    assert.deepEqual((await parent.get()).data(), before);
  }
});

test("publishing a template does not touch another template with the same workout type", async () => {
  await workout("target");
  const other = await workout("other", {workoutTemplateId: "cloned-template"});
  await publish(2);
  await propagateWorkoutVersion(db, "template", 2, now);
  assert.equal((await other.get()).data().workoutTemplateVersion, 1);
});

test("protects history, terminal workouts, saved drafts and prepared or recorded actuals", async () => {
  const protectedData = [
    {scheduledDate: "2025-12-31"}, {status: "completed"}, {status: "missed"},
    {status: "cancelled"}, {actualSlotIds: ["slot"]}, {actuals: [{reps: 2}]},
    {actualsBySlot: {slot: {reps: 2}}},
    {freeClimbingSeal: {completionToken: "prepared"}}, {rpe: 7}, {durationMinutes: 40},
  ];
  const refs = [];
  for (let i = 0; i < protectedData.length; i++) {
    refs.push(await workout(`protected-${i}`, protectedData[i]));
  }
  const draft = await workout("draft");
  await draft.collection("completionDrafts").doc("current").set({revision: 1});
  refs.push(draft);
  const before = await Promise.all(refs.map(async (ref) => (await ref.get()).data()));
  await publish(2);
  await propagateWorkoutVersion(db, "template", 2, now);
  assert.deepEqual(
    await Promise.all(refs.map(async (ref) => (await ref.get()).data())), before,
  );
  assert.equal((await draft.collection("completionDrafts").doc("current").get()).exists, true);
});

test("ended trainer relationships and inactive program instances do not permit updates", async () => {
  const client = await workout("client", {athleteId: "athlete"});
  await db.collection("trainerClientRelationships").doc("owner_athlete")
    .set({trainerId: "owner", athleteId: "athlete", status: "ended"});
  await group("cancelled", "copied", {status: "cancelled"});
  const cancelled = await workout("cancelled", {athleteProgramInstanceId: "cancelled"});
  await publish(2);
  assert.equal(await refreshWorkoutVersion(db, client.id, now), false);
  assert.equal(await refreshWorkoutVersion(db, cancelled.id, now), false);
  await db.collection("trainerClientRelationships").doc("owner_athlete")
    .update({status: "active"});
  assert.equal(await refreshWorkoutVersion(db, client.id, now), true);
});

test("ownership mismatches fail explicitly without modifying the workout", async () => {
  const ref = await workout("wrong", {programOwnerId: "stranger"});
  await publish(2);
  await assert.rejects(refreshWorkoutVersion(db, ref.id, now), /ownership mismatch/);
  assert.equal((await ref.get()).data().workoutTemplateVersion, 1);
  await assert.rejects(propagateWorkoutVersion(db, "template", 2, now), /ownership mismatch/);
  const audit = (await template.collection("workoutTemplateVersions").doc("2").get()).data();
  assert.equal(audit.propagationState, "failed");
});

test("partial propagation failure is recoverable by an idempotent retry", async () => {
  const valid = await workout("valid");
  const invalid = await workout("invalid", {programOwnerId: "stranger"});
  await publish(2);
  await assert.rejects(propagateWorkoutVersion(db, "template", 2, now),
    /ownership mismatch/);
  assert.equal((await invalid.get()).data().workoutTemplateVersion, 1);
  await invalid.update({programOwnerId: "owner"});
  await propagateWorkoutVersion(db, "template", 2, now);
  assert.equal((await valid.get()).data().workoutTemplateVersion, 2);
  assert.equal((await invalid.get()).data().workoutTemplateVersion, 2);
  const audit = (await template.collection("workoutTemplateVersions").doc("2").get()).data();
  assert.equal(audit.propagationState, "complete");
  assert.equal(audit.propagationError, null);
});

test("a concurrent first draft save and refresh agree on one workout version", async () => {
  const ref = await workout("race");
  await publish(2);
  await Promise.all([
    refreshWorkoutVersion(db, ref.id, now),
    db.runTransaction(async (transaction) => {
      const instance = await transaction.get(ref);
      transaction.set(ref.collection("completionDrafts").doc("current"), {
        revision: 1, workoutTemplateVersion: instance.data().workoutTemplateVersion,
      });
    }),
  ]);
  const current = (await ref.get()).data().workoutTemplateVersion;
  assert.equal((await ref.collection("completionDrafts").doc("current").get())
    .data().workoutTemplateVersion, current);
  assert.equal(await refreshWorkoutVersion(db, ref.id, now), false);
});

test("late events and duplicate retries converge to latest without rewriting instances", async () => {
  const ref = await workout("late");
  await publish(2);
  await publish(3);
  await propagateWorkoutVersion(db, "template", 2, now);
  const before = (await ref.get()).data();
  assert.equal(before.workoutTemplateVersion, 3);
  await propagateWorkoutVersion(db, "template", 2, now);
  await propagateWorkoutVersion(db, "template", 3, now);
  assert.deepEqual((await ref.get()).data(), before);
});

test("late publication audit updates never change immutable workout contents", async () => {
  const version = template.collection("workoutTemplateVersions").doc("1");
  await version.update({blocks: [{blockId: "block", notes: "Keep prescription"}]});
  const before = (await version.get()).data();
  await publish(2);
  await propagateWorkoutVersion(db, "template", 1, now);
  const after = (await version.get()).data();
  for (const [key, value] of Object.entries(before)) {
    assert.deepEqual(after[key], value);
  }
  assert.equal(after.propagationState, "complete");
});

test("assignments created after a publish scan still converge from old program entries", async () => {
  await publish(2);
  await propagateWorkoutVersion(db, "template", 2, now);
  const ref = await workout("assigned-later");
  assert.equal(await refreshWorkoutVersion(db, ref.id, now), true);
  assert.equal((await ref.get()).data().workoutTemplateVersion, 2);
});

test("rescheduled workouts converge when they become eligible", async () => {
  const ref = await workout("rescheduled", {scheduledDate: "2025-12-31"});
  await publish(2);
  await propagateWorkoutVersion(db, "template", 2, now);
  assert.equal((await ref.get()).data().workoutTemplateVersion, 1);
  await ref.update({scheduledDate: "2026-01-03"});
  assert.equal(await refreshWorkoutVersion(db, ref.id, now), true);
  assert.equal((await ref.get()).data().workoutTemplateVersion, 2);
});

test("draft and deleting versions are never propagated", async () => {
  const ref = await workout("staged");
  for (const state of ["draft", "deleting"]) {
    await publish(2, state);
    await assert.rejects(refreshWorkoutVersion(db, ref.id, now), /not published/);
    assert.equal((await ref.get()).data().workoutTemplateVersion, 1);
  }
});

test("paginated publication updates more than one page", async () => {
  const batch = db.batch();
  const sample = (await (await workout("sample")).get()).data();
  for (let i = 0; i < 205; i++) {
    batch.set(db.collection("workoutInstances").doc(`page-${i}`), sample);
  }
  await batch.commit();
  await publish(2);
  await propagateWorkoutVersion(db, "template", 2, now);
  const all = await db.collection("workoutInstances").get();
  assert.equal(all.size, 206);
  assert.ok(all.docs.every((doc) => doc.data().workoutTemplateVersion === 2));
  const audit = (await template.collection("workoutTemplateVersions").doc("2").get()).data();
  assert.equal(audit.propagationState, "complete");
  assert.equal(audit.propagationSummary.updated, 206);
});

test("program reconciliation cannot roll back a newer workout version or rebase a draft", async () => {
  const entries = [{
    entryId: "entry", workoutTemplateId: "template", workoutTemplateVersion: 1,
    dayOffset: 0, sortOrder: 0,
  }];
  await program.collection("programVersions").doc("1").set({versionNumber: 1, entries});
  await program.collection("programVersions").doc("2").set({
    versionNumber: 2,
    entries: [...entries, {...entries[0], entryId: "new", sortOrder: 1, dayOffset: 2}],
  });
  await group("subscription");
  const existing = await workout("existing", {
    athleteProgramInstanceId: "subscription", programAssignmentId: "subscription",
    relationshipMode: "subscribed", programEntryId: "entry", programVersion: 1,
  });
  await publish(3);
  await propagateProgramVersion(db, "program", 2, "program-event", now);
  assert.equal((await existing.get()).data().workoutTemplateVersion, 3);
  const created = await db.collection("workoutInstances").doc("subscription-propagated-new").get();
  assert.equal(created.data().workoutTemplateVersion, 3);
  const draftParent = await group("started");
  const started = await workout("started-workout", {
    athleteProgramInstanceId: draftParent.id, programAssignmentId: draftParent.id,
    relationshipMode: "subscribed", programEntryId: "entry", programVersion: 1,
  });
  await started.collection("completionDrafts").doc("current").set({revision: 1});
  await program.collection("programVersions").doc("2").update({propagationState: "pending"});
  await propagateProgramVersion(db, "program", 2, "program-draft-event", now);
  assert.equal((await started.get()).data().workoutTemplateVersion, 1);
});
