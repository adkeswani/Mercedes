"use strict";

const CANARY_SURFACES = Object.freeze({
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

const CANARY_CONTENT = Object.freeze({
  program: "Release Canary Program",
  workout: "Release Canary Workout",
  exercise: "Release Canary Exercise",
  athlete: "Release Canary Athlete",
  dashboardComment: "Release Canary dashboard comment",
  dashboardReaction: "\u{1F389} 1",
});

const TRAINER_DASHBOARD_FILTERS = Object.freeze([
  Object.freeze({ label: "All filter", disabled: false }),
  Object.freeze({ label: "Completions filter", disabled: false }),
  Object.freeze({ label: "Comments filter", disabled: false }),
  Object.freeze({ label: "Reactions filter", disabled: false }),
  Object.freeze({ label: "Programs filter", disabled: false }),
  Object.freeze({
    label: "Personal bests \u2014 Coming later filter",
    disabled: true,
  }),
]);

const EXPECTED_ATHLETE_SURFACES = Object.freeze([
  Object.freeze({
    label: "Athlete Calendar",
    marker: CANARY_SURFACES.athleteCalendar,
    expectedContent: CANARY_CONTENT.workout,
    route: "/athlete/calendar",
    screenshot: "athlete-calendar.png",
  }),
  Object.freeze({
    label: "My Programs",
    marker: CANARY_SURFACES.athletePrograms,
    expectedContent: CANARY_CONTENT.program,
    route: "/athlete/programs",
    screenshot: "athlete-my-programs.png",
  }),
  Object.freeze({
    label: "Workout History",
    marker: CANARY_SURFACES.athleteHistory,
    expectedContent: CANARY_CONTENT.workout,
    route: "/athlete/history",
    screenshot: "athlete-workout-history.png",
  }),
]);

const EXPECTED_TRAINER_SURFACES = Object.freeze([
  Object.freeze({
    label: "Trainer Dashboard",
    marker: CANARY_SURFACES.trainerDashboard,
    expectedContent: [
      `Program ending soon: ${CANARY_CONTENT.program} (7 days)`,
      `Reaction: ${CANARY_CONTENT.dashboardReaction}`,
      `Comment: ${CANARY_CONTENT.dashboardComment}`,
      `Completion: ${CANARY_CONTENT.workout}`,
    ].join(" | "),
    route: "/trainer/dashboard",
    screenshot: "trainer-dashboard.png",
    expectedControls: TRAINER_DASHBOARD_FILTERS,
  }),
  Object.freeze({
    label: "Trainer Clients",
    marker: CANARY_SURFACES.trainerClients,
    expectedContent: CANARY_CONTENT.athlete,
    route: "/trainer/clients",
    screenshot: "trainer-clients.png",
  }),
  Object.freeze({
    label: "Exercise Library",
    marker: CANARY_SURFACES.trainerExercises,
    expectedContent: CANARY_CONTENT.exercise,
    route: "/trainer/exercises",
    screenshot: "trainer-exercise-library.png",
  }),
  Object.freeze({
    label: "Workout Library",
    marker: CANARY_SURFACES.trainerWorkouts,
    expectedContent: CANARY_CONTENT.workout,
    route: "/trainer/workouts",
    screenshot: "trainer-workout-library.png",
  }),
  Object.freeze({
    label: "Program Library",
    marker: CANARY_SURFACES.trainerPrograms,
    expectedContent: CANARY_CONTENT.program,
    route: "/trainer/programs",
    screenshot: "trainer-program-library.png",
  }),
  Object.freeze({
    label: "Trainer Calendar",
    marker: CANARY_SURFACES.trainerCalendar,
    expectedContent: [
      CANARY_CONTENT.athlete,
      CANARY_CONTENT.program,
      CANARY_CONTENT.workout,
    ].join(" | "),
    route: "/trainer/calendar",
    screenshot: "trainer-calendar-assignments.png",
  }),
]);

const EXPECTED_SURFACES = EXPECTED_ATHLETE_SURFACES;

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
  EXPECTED_ATHLETE_SURFACES,
  EXPECTED_QUERY_LABELS,
  EXPECTED_SURFACES,
  EXPECTED_TRAINER_SURFACES,
  TRAINER_DASHBOARD_FILTERS,
};
