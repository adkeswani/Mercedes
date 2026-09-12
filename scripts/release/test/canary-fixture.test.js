"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  CANARY_IDS,
  assertCanaryEmail,
  assertCanaryMutation,
  buildCanaryFixture,
  expectedMutationPaths,
} = require("../canary-fixture.js");
const {
  loadServiceAccountCredentials,
  seedFixture,
} = require("../admin-canary.js");

const options = {
  trainerEmail: "release-canary-trainer@example.invalid",
  athleteEmail: "release-canary-athlete@example.invalid",
  today: "2026-09-12",
};

test("fixture is deterministic, idempotent, and limited to exact paths", () => {
  const first = buildCanaryFixture(options);
  const second = buildCanaryFixture(options);
  assert.deepEqual(first, second);
  assert.deepEqual(
    first.documents.map((document) => document.path),
    expectedMutationPaths(),
  );
  assert.equal(new Set(first.documents.map((item) => item.path)).size, 9);
  assert.equal(
    first.documents.find(
      (item) => item.path.endsWith(CANARY_IDS.currentWorkout),
    ).data.scheduledDate,
    options.today,
  );
  assert.equal(
    first.documents.find(
      (item) => item.path.endsWith(CANARY_IDS.historyWorkout),
    ).data.status,
    "completed",
  );
  assert.equal(
    first.documents.find(
      (item) => item.path === `users/${CANARY_IDS.athlete}`,
    ).data.username,
    "release_canary_athlete",
  );
  assert.equal(
    first.documents.find(
      (item) => item.path ===
        `workoutTemplates/${CANARY_IDS.workoutTemplate}`,
    ).data.workoutType,
    "fullBody",
  );
});

test("namespace guard rejects arbitrary paths, owners, and emails", () => {
  assert.throws(
    () => assertCanaryMutation("users/ordinary-user", {
      uid: "ordinary-user",
    }),
    /exact release-canary fixture path/,
  );
  assert.throws(
    () => assertCanaryMutation(`programs/${CANARY_IDS.program}`, {
      ownerId: "ordinary-user",
    }),
    /namespace/,
  );
  assert.throws(
    () => assertCanaryEmail("person@example.com", "email"),
    /namespace/,
  );
});

test("all fixture ownership and reference fields pass the namespace guard", () => {
  const fixture = buildCanaryFixture(options);
  for (const document of fixture.documents) {
    assert.equal(assertCanaryMutation(document.path, document.data), true);
  }
});

test("deployed credentials are loaded from the injected process environment", () => {
  const credential = {
    type: "service_account",
    project_id: "staging-project-123",
  };
  assert.deepEqual(
    loadServiceAccountCredentials(
      { GOOGLE_APPLICATION_CREDENTIALS: "credential.json" },
      "staging-project-123",
      () => JSON.stringify(credential),
    ),
    credential,
  );
});

test("Firestore fixture commit precedes Auth user creation", async () => {
  const fixture = buildCanaryFixture(options);
  const events = [];
  const notFound = () => {
    const error = new Error("missing");
    error.code = "auth/user-not-found";
    throw error;
  };
  const context = {
    admin: {
      firestore: {
        Timestamp: {
          fromDate: (value) => value,
        },
      },
    },
    auth: {
      getUser: async () => notFound(),
      getUserByEmail: async () => notFound(),
      createUser: async ({ uid }) => events.push(`create:${uid}`),
    },
    firestore: {
      doc: (pathName) => ({
        path: pathName,
        get: async () => ({ exists: false }),
      }),
      batch: () => ({
        set: () => {},
        commit: async () => events.push("commit"),
      }),
    },
  };
  await seedFixture(context, fixture, {
    trainerPassword: "release-canary-local-trainer",
    athletePassword: "release-canary-local-athlete",
  });
  assert.equal(events[0], "commit");
  assert.deepEqual(events.slice(1), [
    `create:${CANARY_IDS.trainer}`,
    `create:${CANARY_IDS.athlete}`,
  ]);
});
