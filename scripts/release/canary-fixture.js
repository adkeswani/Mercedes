"use strict";

const { CANARY_CONTENT } = require("./expectations.js");

const CANARY_PREFIX = "release-canary-";

const CANARY_IDS = Object.freeze({
  trainer: "release-canary-trainer",
  athlete: "release-canary-athlete",
  relationship: "release-canary-trainer_release-canary-athlete",
  exerciseTemplate: "release-canary-exercise-template",
  program: "release-canary-program",
  enrollment: "release-canary-program_release-canary-athlete",
  programInstance: "release-canary-program-instance",
  workoutTemplate: "release-canary-workout-template",
  currentWorkout: "release-canary-current-workout",
  historyWorkout: "release-canary-history-workout",
});

const OWNERSHIP_FIELDS = new Set([
  "uid",
  "userId",
  "ownerId",
  "trainerId",
  "athleteId",
  "athleteOwnerId",
  "assigningTrainerId",
  "programOwnerId",
  "assignedBy",
  "addedBy",
  "createdBy",
  "updatedBy",
  "deletedBy",
  "removedBy",
  "publishedBy",
  "loadPointsOverriddenBy",
]);

const REFERENCE_FIELDS = new Set([
  "programId",
  "sourceProgramId",
  "athleteProgramInstanceId",
  "programAssignmentId",
  "workoutTemplateId",
  "materializationKey",
  "programEntryId",
  "exerciseId",
]);

function assertCanaryToken(value, label) {
  if (typeof value !== "string" ||
      !value.startsWith(CANARY_PREFIX) ||
      value.includes("/") ||
      value.length <= CANARY_PREFIX.length) {
    throw new Error(`${label} must be in the '${CANARY_PREFIX}' namespace`);
  }
  return value;
}

function assertCanaryEmail(email, label) {
  if (typeof email !== "string") {
    throw new Error(`${label} must be a string`);
  }
  const normalized = email.trim().toLowerCase();
  const separator = normalized.indexOf("@");
  if (separator <= 0 ||
      !normalized.slice(0, separator).startsWith(CANARY_PREFIX)) {
    throw new Error(`${label} must use the '${CANARY_PREFIX}' email namespace`);
  }
  return normalized;
}

function assertIsoDate(value, label) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) ||
      new Date(`${value}T00:00:00.000Z`).toISOString().slice(0, 10) !== value) {
    throw new Error(`${label} must be a valid YYYY-MM-DD date`);
  }
}

function previousIsoDate(today) {
  const date = new Date(`${today}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() - 1);
  return date.toISOString().slice(0, 10);
}

function expectedMutationPaths() {
  return Object.freeze([
    `users/${CANARY_IDS.trainer}`,
    `users/${CANARY_IDS.athlete}`,
    `trainerClientRelationships/${CANARY_IDS.relationship}`,
    `exerciseTemplates/${CANARY_IDS.exerciseTemplate}`,
    `exerciseTemplates/${CANARY_IDS.exerciseTemplate}/exerciseVersions/1`,
    `programs/${CANARY_IDS.program}`,
    `programs/${CANARY_IDS.program}/programVersions/1`,
    `enrollments/${CANARY_IDS.enrollment}`,
    `athleteProgramInstances/${CANARY_IDS.programInstance}`,
    `workoutTemplates/${CANARY_IDS.workoutTemplate}`,
    `workoutTemplates/${CANARY_IDS.workoutTemplate}/workoutTemplateVersions/1`,
    `workoutInstances/${CANARY_IDS.currentWorkout}`,
    `workoutInstances/${CANARY_IDS.historyWorkout}`,
  ]);
}

function assertCanaryMutation(path, data, allowedPaths = expectedMutationPaths()) {
  if (!allowedPaths.includes(path)) {
    throw new Error(`Mutation path is not an exact release-canary fixture path: ${path}`);
  }
  const segments = path.split("/");
  if (segments.length !== 2 && segments.length !== 4) {
    throw new Error(`Mutation path must address one exact document: ${path}`);
  }
  assertCanaryToken(segments[1], "Mutation document ID");
  if (segments.length === 4) {
    const versionCollections = new Set([
      "exerciseVersions",
      "programVersions",
      "workoutTemplateVersions",
    ]);
    if (!versionCollections.has(segments[2]) || segments[3] !== "1") {
      throw new Error(`Mutation version path is not allowlisted: ${path}`);
    }
  }
  function inspect(value) {
    if (Array.isArray(value)) {
      value.forEach(inspect);
      return;
    }
    if (!value || typeof value !== "object") {
      return;
    }
    for (const [key, nestedValue] of Object.entries(value)) {
      if (nestedValue === null || nestedValue === undefined) {
        continue;
      }
      if (OWNERSHIP_FIELDS.has(key) || REFERENCE_FIELDS.has(key)) {
        assertCanaryToken(nestedValue, `Field '${key}'`);
      }
      if (key === "email") {
        assertCanaryEmail(nestedValue, "Profile email");
      }
      inspect(nestedValue);
    }
  }
  inspect(data);
  return true;
}

function buildCanaryFixture({ trainerEmail, athleteEmail, today }) {
  assertIsoDate(today, "today");
  const normalizedTrainerEmail = assertCanaryEmail(
    trainerEmail,
    "Trainer email",
  );
  const normalizedAthleteEmail = assertCanaryEmail(
    athleteEmail,
    "Athlete email",
  );
  if (normalizedTrainerEmail === normalizedAthleteEmail) {
    throw new Error("Trainer and athlete canary emails must be different");
  }

  const historyDate = previousIsoDate(today);
  const timestamp = `${today}T12:00:00.000Z`;
  const audit = (actor) => ({
    createdAt: timestamp,
    createdBy: actor,
    updatedAt: timestamp,
    updatedBy: actor,
    deletedAt: null,
    deletedBy: null,
  });
  const workout = (id, scheduledDate, status) => ({
    path: `workoutInstances/${id}`,
    data: {
      programId: CANARY_IDS.program,
      programOwnerId: CANARY_IDS.trainer,
      programVersion: 1,
      programEntryId: CANARY_IDS.workoutTemplate,
      programEntrySortOrder: status === "scheduled" ? 0 : 1,
      athleteProgramInstanceId: CANARY_IDS.programInstance,
      programAssignmentId: CANARY_IDS.programInstance,
      relationshipMode: "subscribed",
      athleteId: CANARY_IDS.athlete,
      workoutTemplateId: CANARY_IDS.workoutTemplate,
      workoutTemplateVersion: 1,
      scheduledDate,
      assignedBy: CANARY_IDS.trainer,
      assignedAt: timestamp,
      status,
      completedAt: status === "completed" ? timestamp : null,
      missedAt: null,
      rpe: status === "completed" ? 7 : null,
      durationMinutes: status === "completed" ? 45 : null,
      loadPoints: status === "completed" ? 315 : null,
      loadPointsOverride: null,
      loadPointsOverriddenBy: null,
      loadPointsOverriddenAt: null,
      loadModelVersion: 1,
      loadStrategyId: null,
      workoutType: "fullBody",
      recurrence: null,
      isRecurrenceRoot: false,
      recurrenceRootId: null,
      actuals: [],
      athleteNotes: null,
      createdAt: timestamp,
      updatedAt: timestamp,
    },
  });

  const documents = [
    {
      path: `users/${CANARY_IDS.trainer}`,
      data: {
        uid: CANARY_IDS.trainer,
        displayName: "Release Canary Trainer",
        email: normalizedTrainerEmail,
        username: "release_canary_trainer",
        photoUrl: null,
        discoverable: false,
        ...audit(CANARY_IDS.trainer),
      },
    },
    {
      path: `users/${CANARY_IDS.athlete}`,
      data: {
        uid: CANARY_IDS.athlete,
        displayName: "Release Canary Athlete",
        email: normalizedAthleteEmail,
        username: "release_canary_athlete",
        photoUrl: null,
        discoverable: false,
        ...audit(CANARY_IDS.athlete),
      },
    },
    {
      path: `trainerClientRelationships/${CANARY_IDS.relationship}`,
      data: {
        trainerId: CANARY_IDS.trainer,
        athleteId: CANARY_IDS.athlete,
        status: "active",
        startedAt: timestamp,
        endedAt: null,
        ...audit(CANARY_IDS.trainer),
      },
    },
    {
      path: `exerciseTemplates/${CANARY_IDS.exerciseTemplate}`,
      data: {
        ownerId: CANARY_IDS.trainer,
        currentVersion: 1,
        tags: [],
        folderId: null,
        provenance: null,
        ...audit(CANARY_IDS.trainer),
      },
    },
    {
      path:
        `exerciseTemplates/${CANARY_IDS.exerciseTemplate}/exerciseVersions/1`,
      data: {
        versionNumber: 1,
        name: CANARY_CONTENT.exercise,
        description: "Synthetic release verification exercise",
        instructions: "Controlled canary movement",
        videoUrl: null,
        mediaUrls: [],
        exerciseType: "strength",
        measurementConfiguration: {
          primary: "repetitions",
          secondary: [],
        },
        gradingConfiguration: null,
        publishedAt: timestamp,
        publishedBy: CANARY_IDS.trainer,
      },
    },
    {
      path: `programs/${CANARY_IDS.program}`,
      data: {
        name: CANARY_CONTENT.program,
        description: "Synthetic release verification fixture",
        ownerId: CANARY_IDS.trainer,
        type: "assignable",
        status: "published",
        currentVersion: 1,
        tags: [],
        folderId: null,
        provenance: null,
        ...audit(CANARY_IDS.trainer),
      },
    },
    {
      path: `programs/${CANARY_IDS.program}/programVersions/1`,
      data: {
        versionNumber: 1,
        publishedAt: timestamp,
        entries: [
          {
            entryId: CANARY_IDS.workoutTemplate,
            workoutTemplateId: CANARY_IDS.workoutTemplate,
            workoutTemplateVersion: 1,
            dayOffset: 0,
            sortOrder: 0,
            workoutName: CANARY_CONTENT.workout,
          },
        ],
        changeNote: "Synthetic release verification version",
        propagationState: "complete",
        propagationAttempt: 0,
        propagationStartedAt: null,
        propagationCompletedAt: timestamp,
        propagationFailedAt: null,
        propagationError: null,
      },
    },
    {
      path: `enrollments/${CANARY_IDS.enrollment}`,
      data: {
        programId: CANARY_IDS.program,
        athleteId: CANARY_IDS.athlete,
        addedAt: timestamp,
        addedBy: CANARY_IDS.trainer,
        removedAt: null,
        removedBy: null,
        status: "active",
        ...audit(CANARY_IDS.trainer),
      },
    },
    {
      path: `athleteProgramInstances/${CANARY_IDS.programInstance}`,
      data: {
        athleteOwnerId: CANARY_IDS.athlete,
        assigningTrainerId: CANARY_IDS.trainer,
        sourceProgramId: CANARY_IDS.program,
        sourceProgramVersion: 1,
        relationshipMode: "subscribed",
        startDate: historyDate,
        expectedEndDate: today,
        workoutCount: 2,
        status: "active",
        linkedAt: timestamp,
        unlinkedAt: null,
        unlinkReason: null,
        materializationKey: CANARY_IDS.programInstance,
        propagationState: "complete",
        propagationTargetVersion: 1,
        propagationAttempt: 0,
        propagationStartedAt: null,
        propagationCompletedAt: timestamp,
        propagationFailedAt: null,
        propagationError: null,
        ...audit(CANARY_IDS.trainer),
      },
    },
    {
      path: `workoutTemplates/${CANARY_IDS.workoutTemplate}`,
      data: {
        ownerId: CANARY_IDS.trainer,
        name: CANARY_CONTENT.workout,
        workoutType: "fullBody",
        currentVersion: 1,
        tags: [],
        folderId: null,
        provenance: null,
        ...audit(CANARY_IDS.trainer),
      },
    },
    {
      path:
        `workoutTemplates/${CANARY_IDS.workoutTemplate}/` +
        "workoutTemplateVersions/1",
      data: {
        versionNumber: 1,
        publishedAt: timestamp,
        exercises: [
          {
            exerciseId: CANARY_IDS.exerciseTemplate,
            exerciseVersion: 1,
            exerciseName: CANARY_CONTENT.exercise,
            mode: "reps",
            sets: 3,
            reps: "8",
            sortOrder: 0,
          },
        ],
      },
    },
    workout(CANARY_IDS.currentWorkout, today, "scheduled"),
    workout(CANARY_IDS.historyWorkout, historyDate, "completed"),
  ];
  for (const document of documents) {
    assertCanaryMutation(document.path, document.data);
  }
  return Object.freeze({
    ids: CANARY_IDS,
    authUsers: Object.freeze([
      Object.freeze({
        uid: CANARY_IDS.trainer,
        email: normalizedTrainerEmail,
        displayName: "Release Canary Trainer",
      }),
      Object.freeze({
        uid: CANARY_IDS.athlete,
        email: normalizedAthleteEmail,
        displayName: "Release Canary Athlete",
      }),
    ]),
    documents: Object.freeze(documents),
  });
}

module.exports = {
  CANARY_IDS,
  CANARY_PREFIX,
  OWNERSHIP_FIELDS,
  REFERENCE_FIELDS,
  assertCanaryEmail,
  assertCanaryMutation,
  assertCanaryToken,
  buildCanaryFixture,
  expectedMutationPaths,
};
