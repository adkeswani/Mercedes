"use strict";

const CANARY_SURFACES = Object.freeze({
  calendar: "athlete-calendar",
  programs: "athlete-programs",
  history: "athlete-history",
});

const CANARY_CONTENT = Object.freeze({
  program: "Release Canary Program",
  workout: "Release Canary Workout",
});

const EXPECTED_SURFACES = Object.freeze([
  Object.freeze({
    label: "Athlete Calendar",
    marker: CANARY_SURFACES.calendar,
    expectedContent: CANARY_CONTENT.workout,
    route: "/athlete/calendar",
    screenshot: "athlete-calendar.png",
  }),
  Object.freeze({
    label: "My Programs",
    marker: CANARY_SURFACES.programs,
    expectedContent: CANARY_CONTENT.program,
    route: "/athlete/programs",
    screenshot: "athlete-my-programs.png",
  }),
  Object.freeze({
    label: "Workout History",
    marker: CANARY_SURFACES.history,
    expectedContent: CANARY_CONTENT.workout,
    route: "/athlete/history",
    screenshot: "athlete-workout-history.png",
  }),
]);

const EXPECTED_QUERY_LABELS = Object.freeze([
  Object.freeze({
    label: "Athlete Calendar: athlete/date ascending",
    collectionGroup: "workoutInstances",
    queryScope: "COLLECTION",
    fields: Object.freeze([
      Object.freeze({ fieldPath: "athleteId", order: "ASCENDING" }),
      Object.freeze({ fieldPath: "scheduledDate", order: "ASCENDING" }),
    ]),
  }),
  Object.freeze({
    label: "Workout History: athlete/date descending",
    collectionGroup: "workoutInstances",
    queryScope: "COLLECTION",
    fields: Object.freeze([
      Object.freeze({ fieldPath: "athleteId", order: "ASCENDING" }),
      Object.freeze({ fieldPath: "scheduledDate", order: "DESCENDING" }),
    ]),
  }),
  Object.freeze({
    label: "My Programs: athlete/start descending",
    collectionGroup: "athleteProgramInstances",
    queryScope: "COLLECTION",
    fields: Object.freeze([
      Object.freeze({ fieldPath: "athleteOwnerId", order: "ASCENDING" }),
      Object.freeze({ fieldPath: "startDate", order: "DESCENDING" }),
    ]),
  }),
]);

module.exports = {
  CANARY_CONTENT,
  CANARY_SURFACES,
  EXPECTED_QUERY_LABELS,
  EXPECTED_SURFACES,
};
