"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  CANARY_CONTENT,
  CANARY_SURFACES,
  EXPECTED_ATHLETE_SURFACES,
  EXPECTED_QUERY_LABELS,
  EXPECTED_SURFACES,
  EXPECTED_TRAINER_SURFACES,
  TRAINER_DASHBOARD_FILTERS,
} = require("../expectations.js");
const {
  assertExpectedQueriesConfigured,
} = require("../firestore-indexes.js");

test("release canary exposes exact athlete surface expectations", () => {
  assert.deepEqual(CANARY_SURFACES, {
    athleteCalendar: "athlete-calendar",
    athletePrograms: "athlete-programs",
    athleteHistory: "athlete-history",
    trainerClients: "trainer-clients",
    trainerExercises: "trainer-exercises",
    trainerWorkouts: "trainer-workouts",
    trainerPrograms: "trainer-programs",
    trainerCalendar: "trainer-calendar",
    trainerDashboard: "trainer-dashboard",
  });
  assert.deepEqual(CANARY_CONTENT, {
    program: "Release Canary Program",
    workout: "Release Canary Workout",
    exercise: "Release Canary Exercise",
    athlete: "Release Canary Athlete",
    dashboardComment: "Release Canary dashboard comment",
    dashboardReaction: "\u{1F389} 1",
  });
  assert.equal(EXPECTED_SURFACES, EXPECTED_ATHLETE_SURFACES);
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

test("release canary exposes exact trainer surface expectations", () => {
  assert.deepEqual(
    EXPECTED_TRAINER_SURFACES.map((surface) => surface.marker),
    [
      "trainer-dashboard",
      "trainer-clients",
      "trainer-exercises",
      "trainer-workouts",
      "trainer-programs",
      "trainer-calendar",
    ],
  );
  assert.deepEqual(
    EXPECTED_TRAINER_SURFACES.map((surface) => surface.expectedContent),
    [
      "Program ending soon: Release Canary Program (7 days) | " +
        "Reaction: \u{1F389} 1 | " +
        "Comment: Release Canary dashboard comment | " +
        "Completion: Release Canary Workout",
      "Release Canary Athlete",
      "Release Canary Exercise",
      "Release Canary Workout",
      "Release Canary Program",
      "Release Canary Athlete | Release Canary Program | " +
        "Release Canary Workout",
    ],
  );
  assert.deepEqual(
    EXPECTED_TRAINER_SURFACES.map((surface) => surface.route),
    [
      "/trainer/dashboard",
      "/trainer/clients",
      "/trainer/exercises",
      "/trainer/workouts",
      "/trainer/programs",
      "/trainer/calendar",
    ],
  );
  assert.equal(
    new Set(
      EXPECTED_TRAINER_SURFACES.map((surface) => surface.screenshot),
    ).size,
    EXPECTED_TRAINER_SURFACES.length,
  );
  assert.equal(
    EXPECTED_TRAINER_SURFACES[0].screenshot,
    "trainer-dashboard.png",
  );
  assert.deepEqual(TRAINER_DASHBOARD_FILTERS, [
    { label: "All filter", disabled: false },
    { label: "Completions filter", disabled: false },
    { label: "Comments filter", disabled: false },
    { label: "Reactions filter", disabled: false },
    { label: "Programs filter", disabled: false },
    {
      label: "Personal bests \u2014 Coming later filter",
      disabled: true,
    },
  ]);
  assert.equal(
    EXPECTED_TRAINER_SURFACES[0].expectedControls,
    TRAINER_DASHBOARD_FILTERS,
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
