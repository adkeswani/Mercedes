"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  CANARY_CONTENT,
  CANARY_SURFACES,
  EXPECTED_QUERY_LABELS,
  EXPECTED_SURFACES,
} = require("../expectations.js");
const {
  assertExpectedQueriesConfigured,
} = require("../firestore-indexes.js");

test("release canary exposes exact athlete surface expectations", () => {
  assert.deepEqual(CANARY_SURFACES, {
    calendar: "athlete-calendar",
    programs: "athlete-programs",
    history: "athlete-history",
  });
  assert.deepEqual(CANARY_CONTENT, {
    program: "Release Canary Program",
    workout: "Release Canary Workout",
  });
  assert.deepEqual(
    EXPECTED_SURFACES.map((surface) => surface.marker),
    ["athlete-calendar", "athlete-programs", "athlete-history"],
  );
  assert.deepEqual(
    EXPECTED_SURFACES.map((surface) => surface.expectedContent),
    [
      "Release Canary Workout",
      "Release Canary Program",
      "Release Canary Workout",
    ],
  );
  assert.deepEqual(
    EXPECTED_SURFACES.map((surface) => surface.route),
    ["/athlete/calendar", "/athlete/programs", "/athlete/history"],
  );
  assert.equal(
    new Set(EXPECTED_SURFACES.map((surface) => surface.screenshot)).size,
    EXPECTED_SURFACES.length,
  );
});

test("repository indexes cover every labeled release query", () => {
  const root = path.resolve(__dirname, "..", "..", "..");
  const config = JSON.parse(
    fs.readFileSync(path.join(root, "firestore.indexes.json"), "utf8"),
  );
  assert.equal(EXPECTED_QUERY_LABELS.length, 3);
  assert.ok(EXPECTED_QUERY_LABELS.every((query) => query.label.length > 0));
  assert.doesNotThrow(() =>
    assertExpectedQueriesConfigured(EXPECTED_QUERY_LABELS, config.indexes));
  assert.throws(
    () => assertExpectedQueriesConfigured(EXPECTED_QUERY_LABELS, []),
    /Athlete Calendar.*Workout History.*My Programs/s,
  );
});
