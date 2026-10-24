const assert = require("node:assert/strict");
const test = require("node:test");
const admin = require("firebase-admin");

const {propagateProgramVersion} = require("../lib/subscription_propagation");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error(
    "subscription_propagation.test.js requires the Firestore emulator; " +
    "run it via `npm test` under `firebase emulators:exec`.",
  );
}

const app = admin.initializeApp({projectId: "demo-mercedes-functions-test"});
const db = app.firestore();

const OWNER = "owner-uid";
const ATHLETE = "athlete-uid";
const PROGRAM_ID = "program-1";
const TEMPLATE_ID = "template-1";

async function clearFirestore() {
  const collections = [
    "programs",
    "workoutTemplates",
    "athleteProgramInstances",
    "workoutInstances",
    "trainerClientRelationships",
  ];
  for (const name of collections) {
    const snapshot = await db.collection(name).get();
    await Promise.all(snapshot.docs.map((doc) => doc.ref.delete()));
  }
}

async function seedWorkoutTemplate(ownerId) {
  await db.collection("workoutTemplates").doc(TEMPLATE_ID).set({
    ownerId,
    createdBy: ownerId,
    currentVersion: 1,
    workoutType: "fullBody",
  });
  await db.collection("workoutTemplates").doc(TEMPLATE_ID)
    .collection("workoutTemplateVersions").doc("1").set({
      versionNumber: 1,
      publishState: "published",
    });
}

async function seedProgramVersion(versionNumber, entries) {
  await db.collection("programs").doc(PROGRAM_ID)
    .collection("programVersions").doc(versionNumber.toString()).set({
      versionNumber,
      entries,
    });
}

async function seedProgram(ownerId) {
  await db.collection("programs").doc(PROGRAM_ID).set({
    ownerId,
    name: "Test Program",
    type: "assignable",
    status: "published",
    currentVersion: 1,
  });
}

function baseEntry(overrides = {}) {
  return {
    entryId: "entry-0",
    workoutTemplateId: TEMPLATE_ID,
    workoutTemplateVersion: 1,
    dayOffset: 0,
    sortOrder: 0,
    ...overrides,
  };
}

async function seedProgramInstance({
  instanceId,
  ownerId,
  athleteId,
  version = 1,
}) {
  await db.collection("athleteProgramInstances").doc(instanceId).set({
    athleteOwnerId: athleteId,
    assigningTrainerId: ownerId,
    sourceProgramId: PROGRAM_ID,
    sourceProgramVersion: version,
    relationshipMode: "subscribed",
    startDate: "2026-01-01",
    expectedEndDate: "2026-01-01",
    workoutCount: 1,
    status: "active",
    linkedAt: admin.firestore.FieldValue.serverTimestamp(),
    unlinkedAt: null,
    propagationState: "complete",
    propagationTargetVersion: version,
  });
}

test(
  "propagates a new version to a self-subscribed program instance " +
  "without requiring a trainerClientRelationships document",
  async (t) => {
    t.after(clearFirestore);
    await clearFirestore();
    await seedProgram(OWNER);
    await seedWorkoutTemplate(OWNER);
    await seedProgramVersion(1, [baseEntry()]);
    await seedProgramVersion(2, [
      baseEntry(),
      baseEntry({entryId: "entry-1", dayOffset: 3, sortOrder: 1}),
    ]);
    const instanceId = "self-instance-1";
    await seedProgramInstance({
      instanceId,
      ownerId: OWNER,
      athleteId: OWNER,
    });

    // No trainerClientRelationships document exists between OWNER and OWNER;
    // propagation must still succeed for a self-assigned subscription. Use a
    // fixed "now" that matches the seeded 2026-01-01 instance start date so
    // reconciliation treats the new entries as current/future, not past.
    await propagateProgramVersion(
      db, PROGRAM_ID, 2, "event-self-1", new Date("2026-01-01T00:00:00Z"),
    );

    const instance = await db.collection("athleteProgramInstances")
      .doc(instanceId).get();
    assert.equal(instance.data().sourceProgramVersion, 2);
    assert.equal(instance.data().propagationState, "complete");

    const workouts = await db.collection("workoutInstances")
      .where("athleteProgramInstanceId", "==", instanceId)
      .get();
    assert.equal(workouts.size, 2);
  },
);

test(
  "skips propagation for a non-self subscribed instance when the " +
  "trainer-client relationship is not active",
  async (t) => {
    t.after(clearFirestore);
    await clearFirestore();
    await seedProgram(OWNER);
    await seedWorkoutTemplate(OWNER);
    await seedProgramVersion(1, [baseEntry()]);
    await seedProgramVersion(2, [
      baseEntry(),
      baseEntry({entryId: "entry-1", dayOffset: 3, sortOrder: 1}),
    ]);
    const instanceId = "non-self-instance-1";
    await seedProgramInstance({
      instanceId,
      ownerId: OWNER,
      athleteId: ATHLETE,
    });
    // Deliberately no trainerClientRelationships/owner-uid_athlete-uid doc.

    await propagateProgramVersion(
      db, PROGRAM_ID, 2, "event-non-self-1", new Date("2026-01-01T00:00:00Z"),
    );

    const instance = await db.collection("athleteProgramInstances")
      .doc(instanceId).get();
    // Propagation must not advance the version when the relationship is
    // missing/inactive; the instance stays on its prior applied version.
    assert.equal(instance.data().sourceProgramVersion, 1);

    const workouts = await db.collection("workoutInstances")
      .where("athleteProgramInstanceId", "==", instanceId)
      .get();
    assert.equal(workouts.size, 0);
  },
);

test(
  "propagates a non-self subscribed instance once the trainer-client " +
  "relationship is active",
  async (t) => {
    t.after(clearFirestore);
    await clearFirestore();
    await seedProgram(OWNER);
    await seedWorkoutTemplate(OWNER);
    await seedProgramVersion(1, [baseEntry()]);
    await seedProgramVersion(2, [
      baseEntry(),
      baseEntry({entryId: "entry-1", dayOffset: 3, sortOrder: 1}),
    ]);
    const instanceId = "non-self-instance-2";
    await seedProgramInstance({
      instanceId,
      ownerId: OWNER,
      athleteId: ATHLETE,
    });
    await db.collection("trainerClientRelationships")
      .doc(`${OWNER}_${ATHLETE}`).set({
        trainerId: OWNER,
        athleteId: ATHLETE,
        status: "active",
      });

    await propagateProgramVersion(
      db, PROGRAM_ID, 2, "event-non-self-2", new Date("2026-01-01T00:00:00Z"),
    );

    const instance = await db.collection("athleteProgramInstances")
      .doc(instanceId).get();
    assert.equal(instance.data().sourceProgramVersion, 2);

    const workouts = await db.collection("workoutInstances")
      .where("athleteProgramInstanceId", "==", instanceId)
      .get();
    assert.equal(workouts.size, 2);
  },
);
