"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  compareIndexes,
  pendingExpectedIndexes,
} = require("../firestore-indexes.js");
const {
  compareFirestoreConfiguration,
  normalizeRules,
  rulesDifference,
} = require("../firestore-parity.js");

const expectedIndex = {
  collectionGroup: "workoutInstances",
  queryScope: "COLLECTION",
  fields: [
    { fieldPath: "athleteId", order: "ASCENDING" },
    { fieldPath: "scheduledDate", order: "DESCENDING" },
  ],
};
const deployedIndex = {
  name: "projects/example/databases/(default)/collectionGroups/workoutInstances/indexes/abc",
  queryScope: "COLLECTION",
  state: "READY",
  fields: [
    { fieldPath: "athleteId", order: "ASCENDING" },
    { fieldPath: "scheduledDate", order: "DESCENDING" },
    { fieldPath: "__name__", order: "DESCENDING" },
  ],
};

test("rules parity normalizes line endings but reports actionable line details", () => {
  assert.equal(normalizeRules("rules\r\n"), "rules\n");
  assert.equal(rulesDifference("line 1\nline 2\n", "line 1\r\nline 2"), null);
  assert.deepEqual(rulesDifference("same\nexpected\n", "same\nactual\n"), {
    line: 2,
    expected: "expected",
    deployed: "actual",
  });
});

test("index parity ignores API name fields and reports missing and unexpected", () => {
  assert.deepEqual(compareIndexes([expectedIndex], [deployedIndex]), {
    equal: true,
    missing: [],
    unexpected: [],
    notReady: [],
  });
  const result = compareIndexes([expectedIndex], [{
    ...deployedIndex,
    name: deployedIndex.name.replace("workoutInstances", "enrollments"),
  }]);
  assert.equal(result.equal, false);
  assert.equal(result.missing.length, 1);
  assert.equal(result.unexpected.length, 1);
});

test("readiness and combined parity fail until matching indexes are READY", () => {
  assert.deepEqual(
    pendingExpectedIndexes([expectedIndex], [{ ...deployedIndex, state: "CREATING" }]),
    [{
      label: "workoutInstances [COLLECTION] (athleteId ASCENDING, scheduledDate DESCENDING)",
      state: "CREATING",
    }],
  );
  assert.throws(
    () => pendingExpectedIndexes(
      [expectedIndex],
      [{ ...deployedIndex, state: "NEEDS_REPAIR" }],
    ),
    /requires repair/,
  );
  const result = compareFirestoreConfiguration({
    expectedRules: "rules_version = '2';\n",
    deployedRules: "rules_version = '1';\n",
    expectedIndexes: [expectedIndex],
    deployedIndexes: [],
  });
  assert.equal(result.equal, false);
  assert.match(result.failures.join("\n"), /rules differ at line 1/);
  assert.match(result.failures.join("\n"), /Missing deployed composite indexes/);
});
