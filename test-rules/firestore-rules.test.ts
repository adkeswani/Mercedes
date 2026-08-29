import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { deleteField, serverTimestamp, setLogLevel } from 'firebase/firestore';

setLogLevel('error');

const RULES_PATH = resolve(__dirname, '..', 'firestore.rules');

// Test user IDs
const OWNER = 'owner-uid';
const ATHLETE = 'athlete-uid';
const STRANGER = 'stranger-uid';
const PROGRAM_ID = 'program-1';
const FOLDER_ID = 'folder-1';
const ENROLLMENT_ID = `${PROGRAM_ID}_${ATHLETE}`;
const RELATIONSHIP_ID = `${OWNER}_${ATHLETE}`;

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-mercedes-rules-test',
    firestore: {
      rules: readFileSync(RULES_PATH, 'utf8'),
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

async function seedActiveRelationship() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore()
      .collection('trainerClientRelationships')
      .doc(RELATIONSHIP_ID)
      .set({
        trainerId: OWNER,
        athleteId: ATHLETE,
        status: 'active',
        startedAt: new Date(),
        endedAt: null,
        createdAt: new Date(),
        createdBy: OWNER,
        updatedAt: new Date(),
        updatedBy: OWNER,
        deletedAt: null,
        deletedBy: null,
      });
  });
}

/** Seed a standard relationship, program, and enrollment. */
async function seedProgramWithEnrollment() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('trainerClientRelationships').doc(RELATIONSHIP_ID).set({
      trainerId: OWNER,
      athleteId: ATHLETE,
      status: 'active',
    });
    await db.collection('programs').doc(PROGRAM_ID).set({
      ownerId: OWNER,
      name: 'Test Program',
      type: 'assignable',
      status: 'published',
      currentVersion: 1,
      createdBy: OWNER,
    });
    await db.collection('enrollments').doc(ENROLLMENT_ID).set({
      programId: PROGRAM_ID,
      athleteId: ATHLETE,
      addedBy: OWNER,
      status: 'active',
    });
  });
}

// ─── Anonymous access denied ───

describe('anonymous access', () => {
  it('denies all reads to unauthenticated users', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('users').doc('u1').set({ name: 'A' });
    });
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.collection('users').doc('u1').get());
  });

  it('denies writes to unauthenticated users', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.collection('users').doc('u1').set({ name: 'A' }));
  });
});

// ─── Users collection ───

describe('users', () => {
  it('allows any signed-in user to read any profile', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('users').doc(OWNER).set({ name: 'Owner' });
    });
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertSucceeds(db.collection('users').doc(OWNER).get());
  });

  it('allows user to write own profile', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(db.collection('users').doc(OWNER).set({ name: 'Me' }));
  });

  it('denies writing another user profile', async () => {
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(db.collection('users').doc(OWNER).set({ name: 'Hacked' }));
  });
});

// ─── Trainer-client relationships ───

describe('trainerClientRelationships', () => {
  function activeRelationship(trainerId = OWNER, athleteId = ATHLETE) {
    return {
      trainerId,
      athleteId,
      status: 'active',
      startedAt: serverTimestamp(),
      endedAt: null,
      createdAt: serverTimestamp(),
      createdBy: trainerId,
      updatedAt: serverTimestamp(),
      updatedBy: trainerId,
      deletedAt: null,
      deletedBy: null,
    };
  }

  it('allows a trainer to create their relationship', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('trainerClientRelationships')
        .doc(RELATIONSHIP_ID)
        .set(activeRelationship())
    );
  });

  it('denies athlete-created and self relationships', async () => {
    const athleteDb = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      athleteDb.collection('trainerClientRelationships')
        .doc(RELATIONSHIP_ID)
        .set(activeRelationship())
    );

    const ownerDb = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      ownerDb.collection('trainerClientRelationships')
        .doc(`${OWNER}_${OWNER}`)
        .set(activeRelationship(OWNER, OWNER))
    );
  });

  it('allows only participants to read a relationship', async () => {
    await seedActiveRelationship();
    const ownerDb = testEnv.authenticatedContext(OWNER).firestore();
    const athleteDb = testEnv.authenticatedContext(ATHLETE).firestore();
    const strangerDb = testEnv.authenticatedContext(STRANGER).firestore();
    const ref = (db) => db.collection('trainerClientRelationships')
      .doc(RELATIONSHIP_ID);

    await assertSucceeds(ref(ownerDb).get());
    await assertSucceeds(ref(athleteDb).get());
    await assertFails(ref(strangerDb).get());
  });

  it('allows participants to query only their relationships', async () => {
    await seedActiveRelationship();
    const ownerDb = testEnv.authenticatedContext(OWNER).firestore();
    const athleteDb = testEnv.authenticatedContext(ATHLETE).firestore();
    const strangerDb = testEnv.authenticatedContext(STRANGER).firestore();

    await assertSucceeds(
      ownerDb.collection('trainerClientRelationships')
        .where('trainerId', '==', OWNER)
        .where('status', '==', 'active')
        .get()
    );
    await assertSucceeds(
      athleteDb.collection('trainerClientRelationships')
        .where('athleteId', '==', ATHLETE)
        .where('status', '==', 'active')
        .get()
    );
    await assertFails(
      strangerDb.collection('trainerClientRelationships')
        .where('trainerId', '==', OWNER)
        .where('status', '==', 'active')
        .get()
    );
  });

  it('allows the trainer to end but not reassign a relationship', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await db.collection('trainerClientRelationships')
      .doc(RELATIONSHIP_ID)
      .set(activeRelationship());
    const ref = db.collection('trainerClientRelationships').doc(RELATIONSHIP_ID);

    await assertSucceeds(ref.update({
      status: 'ended',
      endedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
    }));
    await assertFails(ref.update({
      athleteId: STRANGER,
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
    }));
  });

  it('denies athlete lifecycle updates and all hard deletes', async () => {
    await seedActiveRelationship();
    const athleteDb = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      athleteDb.collection('trainerClientRelationships')
        .doc(RELATIONSHIP_ID)
        .update({
          status: 'ended',
          endedAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
          updatedBy: ATHLETE,
        })
    );

    const ownerDb = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      ownerDb.collection('trainerClientRelationships')
        .doc(RELATIONSHIP_ID)
        .delete()
    );
  });
});

// ─── Feedback (authenticated create, client write-only) ───

describe('feedback', () => {
  function validFeedback(userId = OWNER) {
    return {
      userId,
      type: 'bug',
      body: 'The calendar did not advance.',
      appVersion: '0.1.0',
      platform: 'web',
      deviceModel: 'web-browser',
      screenName: 'HomeScreen',
      status: 'new',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    };
  }

  it('allows an authenticated user to submit feedback for self', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('feedback').doc('feedback-1').set(validFeedback())
    );
  });

  it('denies anonymous feedback', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db.collection('feedback').doc('feedback-1').set(validFeedback())
    );
  });

  it('denies submitting feedback for another user', async () => {
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('feedback').doc('feedback-1').set(validFeedback(OWNER))
    );
  });

  it('denies client reads, updates, and deletes', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('feedback').doc('feedback-1')
        .set({ ...validFeedback(), createdAt: new Date(), updatedAt: new Date() });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = db.collection('feedback').doc('feedback-1');
    await assertFails(ref.get());
    await assertFails(ref.update({ status: 'reviewed' }));
    await assertFails(ref.delete());
  });

  it('denies malformed feedback', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('feedback').doc('feedback-1').set({
        ...validFeedback(),
        type: 'other',
      })
    );
    await assertFails(
      db.collection('feedback').doc('feedback-2').set({
        ...validFeedback(),
        extraField: 'unexpected',
      })
    );
  });
});

// ─── Exercise notes (private subcollection) ───

describe('exerciseNotes', () => {
  it('allows user to read/write own notes', async () => {
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    const ref = db.collection('users').doc(ATHLETE)
      .collection('exerciseNotes').doc('squat-1');
    await assertSucceeds(ref.set({ note: 'Keep back straight' }));
    await assertSucceeds(ref.get());
  });

  it('denies reading another user notes', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('users').doc(ATHLETE)
        .collection('exerciseNotes').doc('squat-1')
        .set({ note: 'Private' });
    });
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('users').doc(ATHLETE)
        .collection('exerciseNotes').doc('squat-1').get()
    );
  });

  it('denies writing another user notes', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('users').doc(ATHLETE)
        .collection('exerciseNotes').doc('squat-1')
        .set({ note: 'Coach override' })
    );
  });
});

// ─── Usernames ───

describe('usernames', () => {
  it('allows creating a username for self', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('usernames').doc('myname').set({ uid: OWNER })
    );
  });

  it('denies creating a username for another user', async () => {
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('usernames').doc('stolen').set({ uid: OWNER })
    );
  });

  it('denies updating an existing username', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('usernames').doc('taken').set({ uid: OWNER });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('usernames').doc('taken').update({ uid: STRANGER })
    );
  });

  it('denies deleting a username', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('usernames').doc('perm').set({ uid: OWNER });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(db.collection('usernames').doc('perm').delete());
  });
});

// ─── Exercise Templates ───

describe('exerciseTemplates', () => {
  async function seedVersionedExercise() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('exerciseTemplates').doc('e1').set({
        ownerId: OWNER, currentVersion: 1, createdBy: OWNER,
        createdAt: new Date(), updatedAt: new Date(), updatedBy: OWNER,
        deletedAt: null, deletedBy: null,
      });
      await db.collection('exerciseTemplates').doc('e1')
        .collection('exerciseVersions').doc('1').set({
          versionNumber: 1,
          name: 'Squat',
          description: 'Barbell squat',
          instructions: 'Brace and squat',
          videoUrl: null,
          mediaUrls: [],
          exerciseType: 'strength',
          measurementConfiguration: {
            primary: 'weight',
            secondary: ['repetitions'],
          },
          gradingConfiguration: null,
          publishedAt: new Date(),
          publishedBy: OWNER,
        });
    });
  }

  async function seedLegacyExercise() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('exerciseTemplates').doc('legacy').set({
        name: 'Legacy Squat',
        description: 'Legacy description',
        instructions: 'Legacy instructions',
        ownerId: OWNER,
        createdBy: OWNER,
        createdAt: new Date(),
        updatedAt: new Date(),
        updatedBy: OWNER,
        deletedAt: null,
        deletedBy: null,
      });
    });
  }

  it('allows signed-in reads during the Stage 4 compatibility window', async () => {
    await seedVersionedExercise();
    const ownerDb = testEnv.authenticatedContext(OWNER).firestore();
    const strangerDb = testEnv.authenticatedContext(STRANGER).firestore();
    await assertSucceeds(ownerDb.collection('exerciseTemplates').doc('e1').get());
    await assertSucceeds(
      strangerDb.collection('exerciseTemplates').doc('e1').get()
    );
    await assertSucceeds(
      strangerDb.collection('exerciseTemplates').doc('e1')
        .collection('exerciseVersions').doc('1').get()
    );
  });

  it('allows atomically creating an owned header and version 1', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const header = db.collection('exerciseTemplates').doc('e2');
    const batch = db.batch();
    batch.set(header, {
      ownerId: OWNER,
      currentVersion: 1,
      createdBy: OWNER,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
      deletedAt: null,
      deletedBy: null,
    });
    batch.set(header.collection('exerciseVersions').doc('1'), {
      versionNumber: 1,
      name: 'Bench',
      description: 'Flat bench',
      instructions: 'Press the bar',
      videoUrl: null,
      mediaUrls: [],
      exerciseType: 'strength',
      measurementConfiguration: {
        primary: 'weight',
        secondary: ['repetitions'],
      },
      gradingConfiguration: null,
      publishedAt: serverTimestamp(),
      publishedBy: OWNER,
    });
    await assertSucceeds(batch.commit());
  });

  it('denies creating without version 1 or with someone else as owner', async () => {
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('exerciseTemplates').doc('e3').set({
        ownerId: OWNER,
        currentVersion: 1,
        createdBy: STRANGER,
      })
    );
    const ownerDb = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      ownerDb.collection('exerciseTemplates').doc('missing-version').set({
        ownerId: OWNER,
        currentVersion: 1,
        tags: [],
        folderId: null,
        provenance: null,
        createdBy: OWNER,
        updatedBy: OWNER,
      })
    );
  });

  it('denies header and version mutations by a non-owner', async () => {
    await seedVersionedExercise();
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('exerciseTemplates').doc('e1').update({
        updatedBy: STRANGER,
        deletedAt: serverTimestamp(),
      })
    );
    await assertFails(
      db.collection('exerciseTemplates').doc('e1')
        .collection('exerciseVersions').doc('2').set({
          versionNumber: 2,
          name: 'Hacked',
          publishedBy: STRANGER,
        })
    );
  });

  it('allows owner organization updates with an owned typed folder', async () => {
    await seedVersionedExercise();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('programFolders').doc('exercise-folder').set({
        ownerId: OWNER, itemType: 'exercise', name: 'Strength',
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('exerciseTemplates').doc('e1').update({
        tags: ['Strength'],
        folderId: 'exercise-folder',
        updatedAt: serverTimestamp(),
        updatedBy: OWNER,
      })
    );
  });

  it('denies foreign, wrong-type, and provenance-changing exercise updates', async () => {
    await seedVersionedExercise();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('programFolders').doc('foreign').set({
        ownerId: STRANGER, itemType: 'exercise', name: 'Foreign',
      });
      await db.collection('programFolders').doc('wrong-type').set({
        ownerId: OWNER, itemType: 'workout', name: 'Workout',
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    for (const folderId of ['foreign', 'wrong-type']) {
      await assertFails(
        db.collection('exerciseTemplates').doc('e1').update({
          folderId,
          updatedAt: serverTimestamp(),
          updatedBy: OWNER,
        })
      );
    }
    await assertFails(
      db.collection('exerciseTemplates').doc('e1').update({
        provenance: {
          sourceTemplateId: 'source',
          sourceOwnerId: OWNER,
          sourceVersion: 1,
          copiedAt: serverTimestamp(),
          copiedBy: OWNER,
        },
        updatedAt: serverTimestamp(),
        updatedBy: OWNER,
      })
    );
  });

  it('allows owner soft-delete but preserves logical ownership', async () => {
    await seedVersionedExercise();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = db.collection('exerciseTemplates').doc('e1');
    await assertSucceeds(ref.update({
      deletedAt: serverTimestamp(),
      deletedBy: OWNER,
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
    }));
    await assertFails(ref.update({ ownerId: STRANGER }));
    await assertFails(ref.delete());
  });

  it('allows owner to atomically backfill legacy content as version 1', async () => {
    await seedLegacyExercise();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const header = db.collection('exerciseTemplates').doc('legacy');
    const batch = db.batch();
    batch.update(header, {
      currentVersion: 1,
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
      name: deleteField(),
      description: deleteField(),
      instructions: deleteField(),
    });
    batch.set(header.collection('exerciseVersions').doc('1'), {
      versionNumber: 1,
      name: 'Legacy Squat',
      description: 'Legacy description',
      instructions: 'Legacy instructions',
      videoUrl: null,
      mediaUrls: [],
      exerciseType: 'other',
      measurementConfiguration: {
        primary: 'repetitions',
        secondary: [],
      },
      gradingConfiguration: null,
      publishedAt: new Date(),
      publishedBy: OWNER,
    });
    await assertSucceeds(batch.commit());
  });

  it('denies changing legacy execution content without publishing versions', async () => {
    await seedLegacyExercise();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('exerciseTemplates').doc('legacy').update({
        name: 'Destructive rename',
        updatedAt: serverTimestamp(),
        updatedBy: OWNER,
      })
    );
  });

  it('denies backfill that rewrites the legacy version 1 payload', async () => {
    await seedLegacyExercise();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const header = db.collection('exerciseTemplates').doc('legacy');
    const batch = db.batch();
    batch.update(header, {
      currentVersion: 1,
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
      name: deleteField(),
      description: deleteField(),
      instructions: deleteField(),
    });
    batch.set(header.collection('exerciseVersions').doc('1'), {
      versionNumber: 1,
      name: 'Rewritten history',
      description: 'Legacy description',
      instructions: 'Legacy instructions',
      videoUrl: null,
      mediaUrls: [],
      exerciseType: 'other',
      measurementConfiguration: {
        primary: 'repetitions',
        secondary: [],
      },
      gradingConfiguration: null,
      publishedAt: new Date(),
      publishedBy: OWNER,
    });
    await assertFails(batch.commit());
  });

  it('prevents immutable exercise versions from update or delete', async () => {
    await seedVersionedExercise();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const version = db.collection('exerciseTemplates').doc('e1')
      .collection('exerciseVersions').doc('1');
    await assertFails(version.update({ name: 'Changed in place' }));
    await assertFails(version.delete());
  });
});

// ─── Workout Templates ───

describe('workoutTemplates', () => {
  it('allows signed-in reads during the Stage 4 compatibility window', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutTemplates').doc('w1').set({
        name: 'Full Body', ownerId: OWNER, createdBy: OWNER,
      });
    });
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(db.collection('workoutTemplates').doc('w1').get());
  });

  it('allows reading workout template versions by any signed-in user', async () => {
    await seedActiveRelationship();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('workoutTemplates').doc('w1').set({
        name: 'Full Body', ownerId: OWNER, createdBy: OWNER,
      });
      await db.collection('workoutTemplates').doc('w1')
        .collection('workoutTemplateVersions').doc('1').set({
          exercises: [], publishedAt: new Date(),
        });
    });
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(
      db.collection('workoutTemplates').doc('w1')
        .collection('workoutTemplateVersions').doc('1').get()
    );
  });

  it('allows the owner to atomically publish a pinned workout version', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adminDb = ctx.firestore();
      await adminDb.collection('workoutTemplates').doc('publish').set({
        name: 'Full Body',
        ownerId: OWNER,
        createdBy: OWNER,
        currentVersion: 0,
      });
      await adminDb.collection('exerciseTemplates').doc('e1').set({
        ownerId: OWNER,
        createdBy: OWNER,
        currentVersion: 1,
      });
      await adminDb.collection('exerciseTemplates').doc('e1')
        .collection('exerciseVersions').doc('1').set({
          versionNumber: 1,
        });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const header = db.collection('workoutTemplates').doc('publish');
    const batch = db.batch();
    batch.update(header, { currentVersion: 1, updatedBy: OWNER });
    batch.set(
      header.collection('workoutTemplateVersions').doc('1'),
      {
        versionNumber: 1,
        storageFormat: 'exercisePrescriptionSubcollection',
        prescriptionCount: 1,
      }
    );
    batch.set(
      header.collection('workoutTemplateVersions').doc('1')
        .collection('exercisePrescriptions').doc('0'),
      {
        exerciseId: 'e1',
        exerciseVersion: 1,
        sortOrder: 0,
        exerciseName: 'Squat',
        prescription: { mode: 'reps' },
      }
    );
    await assertSucceeds(batch.commit());
  });

  it('allows nine exercise pins on a foldered workout', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adminDb = ctx.firestore();
      await adminDb.collection('programFolders').doc('workout-folder').set({
        ownerId: OWNER,
        itemType: 'workout',
        deletedAt: null,
      });
      await adminDb.collection('workoutTemplates').doc('foldered-nine').set({
        name: 'Nine',
        ownerId: OWNER,
        createdBy: OWNER,
        updatedBy: OWNER,
        currentVersion: 0,
        tags: [],
        folderId: 'workout-folder',
        provenance: null,
      });
      for (let index = 0; index < 9; index++) {
        const exerciseId = `limit-exercise-${index}`;
        const exercise = adminDb.collection('exerciseTemplates').doc(exerciseId);
        await exercise.set({
          ownerId: OWNER,
          createdBy: OWNER,
          currentVersion: 1,
        });
        await exercise.collection('exerciseVersions').doc('1').set({
          versionNumber: 1,
        });
      }
    });

    const db = testEnv.authenticatedContext(OWNER).firestore();
    const header = db.collection('workoutTemplates').doc('foldered-nine');
    const version = header.collection('workoutTemplateVersions').doc('1');
    const batch = db.batch();
    batch.update(header, { currentVersion: 1, updatedBy: OWNER });
    batch.set(version, {
      versionNumber: 1,
      storageFormat: 'exercisePrescriptionSubcollection',
      prescriptionCount: 9,
    });
    for (let index = 0; index < 9; index++) {
      batch.set(version.collection('exercisePrescriptions').doc(`${index}`), {
        exerciseId: `limit-exercise-${index}`,
        exerciseVersion: 1,
        sortOrder: index,
        exerciseName: `Exercise ${index}`,
        prescription: { mode: 'reps' },
      });
    }
    await assertSucceeds(batch.commit());
  });

  it('denies publishing a foreign exercise pin', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adminDb = ctx.firestore();
      await adminDb.collection('workoutTemplates').doc('foreign-pin').set({
        ownerId: OWNER,
        createdBy: OWNER,
        currentVersion: 0,
      });
      await adminDb.collection('exerciseTemplates').doc('foreign').set({
        ownerId: STRANGER,
        createdBy: STRANGER,
        currentVersion: 1,
      });
      await adminDb.collection('exerciseTemplates').doc('foreign')
        .collection('exerciseVersions').doc('1').set({ versionNumber: 1 });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const header = db.collection('workoutTemplates').doc('foreign-pin');
    const batch = db.batch();
    batch.update(header, { currentVersion: 1, updatedBy: OWNER });
    batch.set(header.collection('workoutTemplateVersions').doc('1'), {
      versionNumber: 1,
      storageFormat: 'exercisePrescriptionSubcollection',
      prescriptionCount: 1,
    });
    batch.set(
      header.collection('workoutTemplateVersions').doc('1')
        .collection('exercisePrescriptions').doc('0'),
      {
        exerciseId: 'foreign',
        exerciseVersion: 1,
        sortOrder: 0,
        exerciseName: 'Foreign',
        prescription: { mode: 'reps' },
      }
    );
    await assertFails(batch.commit());
  });

  it('denies workout versions above the rule-supported prescription limit', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutTemplates').doc('too-many').set({
        ownerId: OWNER,
        createdBy: OWNER,
        currentVersion: 0,
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const header = db.collection('workoutTemplates').doc('too-many');
    const batch = db.batch();
    batch.update(header, { currentVersion: 1, updatedBy: OWNER });
    batch.set(header.collection('workoutTemplateVersions').doc('1'), {
      versionNumber: 1,
      storageFormat: 'exercisePrescriptionSubcollection',
      prescriptionCount: 10,
    });
    await assertFails(batch.commit());
  });

  it('denies update by non-creator', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutTemplates').doc('w2').set({
        name: 'Upper', ownerId: OWNER, createdBy: OWNER,
      });
    });
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('workoutTemplates').doc('w2').update({ name: 'Hacked' })
    );
  });

  it('denies version write by non-creator', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutTemplates').doc('w3').set({
        name: 'Lower', ownerId: OWNER, createdBy: OWNER,
      });
    });
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('workoutTemplates').doc('w3')
        .collection('workoutTemplateVersions').doc('1')
        .set({ versionNumber: 1, exercises: [] })
    );
  });

  it('prevents published workout versions from update or delete', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('workoutTemplates').doc('immutable').set({
        name: 'Upper', ownerId: OWNER, createdBy: OWNER,
      });
      await db.collection('workoutTemplates').doc('immutable')
        .collection('workoutTemplateVersions').doc('1').set({
          versionNumber: 1,
          exercises: [{
            exerciseId: 'e1',
            exerciseVersion: 1,
            sortOrder: 0,
          }],
        });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const version = db.collection('workoutTemplates').doc('immutable')
      .collection('workoutTemplateVersions').doc('1');
    await assertFails(version.update({ exercises: [] }));
    await assertFails(version.delete());
  });

  it('allows the owner to update without changing ownership', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutTemplates').doc('w4').set({
        name: 'Upper', ownerId: OWNER, createdBy: OWNER,
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = db.collection('workoutTemplates').doc('w4');
    await assertSucceeds(
      ref.update({ name: 'Upper Strength', updatedBy: OWNER })
    );
    await assertFails(ref.update({ ownerId: STRANGER }));
  });

  it('allows workout metadata at create and rejects later provenance changes', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const source = ctx.firestore()
        .collection('workoutTemplates').doc('source');
      await source.set({
        ownerId: OWNER,
        createdBy: OWNER,
        currentVersion: 2,
      });
      await source.collection('workoutTemplateVersions').doc('2').set({
        versionNumber: 2,
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = db.collection('workoutTemplates').doc('copied-workout');
    await assertSucceeds(ref.set({
      name: 'Copy',
      workoutType: 'pull',
      currentVersion: 0,
      ownerId: OWNER,
      tags: ['Pull'],
      folderId: null,
      provenance: {
        sourceTemplateId: 'source',
        sourceOwnerId: OWNER,
        sourceVersion: 2,
        copiedAt: serverTimestamp(),
        copiedBy: OWNER,
      },
      createdBy: OWNER,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
      deletedAt: null,
      deletedBy: null,
    }));
    await assertFails(ref.update({
      provenance: null,
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
    }));
  });

  it('rejects forged copy provenance', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('workoutTemplates').doc('forged-copy').set({
        name: 'Forged',
        workoutType: 'pull',
        currentVersion: 0,
        ownerId: OWNER,
        tags: [],
        folderId: null,
        provenance: {
          sourceTemplateId: 'missing-source',
          sourceOwnerId: OWNER,
          sourceVersion: 1,
          copiedAt: serverTimestamp(),
          copiedBy: OWNER,
        },
        createdBy: OWNER,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
        updatedBy: OWNER,
        deletedAt: null,
        deletedBy: null,
      })
    );
  });
});

// ─── Programs ───

describe('programs', () => {
  it('allows owner to read own program', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(db.collection('programs').doc(PROGRAM_ID).get());
  });

  it('allows enrolled athlete to read program', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(db.collection('programs').doc(PROGRAM_ID).get());
  });

  it('denies stranger from reading program', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(db.collection('programs').doc(PROGRAM_ID).get());
  });

  it('allows creating program with own ownerId', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('programs').doc('p-new').set({
        ownerId: OWNER,
        name: 'New',
        type: 'personal',
        tags: [],
        folderId: null,
        provenance: null,
        createdBy: OWNER,
        updatedBy: OWNER,
      })
    );
  });

  it('keeps Stage 4 program create and update shapes compatible', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = db.collection('programs').doc('legacy-program-write');
    await assertSucceeds(ref.set({
      ownerId: OWNER,
      name: 'Legacy',
      type: 'personal',
      status: 'draft',
      currentVersion: 0,
      folderId: null,
      createdBy: OWNER,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      deletedAt: null,
      deletedBy: null,
    }));
    await assertSucceeds(ref.update({
      name: 'Legacy Updated',
      updatedAt: serverTimestamp(),
    }));
  });

  it('denies creating program with someone else as owner', async () => {
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('programs').doc('p-fake').set({
        ownerId: OWNER, name: 'Fake',
      })
    );
  });

  it('denies update by non-owner', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      db.collection('programs').doc(PROGRAM_ID).update({ name: 'Hacked' })
    );
  });

  it('rejects foreign folders and provenance changes on programs', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('programs').doc('organized').set({
        ownerId: OWNER,
        name: 'Organized',
        type: 'personal',
        tags: [],
        folderId: null,
        provenance: null,
        createdBy: OWNER,
        updatedBy: OWNER,
      });
      await db.collection('programFolders').doc('foreign-program-folder').set({
        ownerId: STRANGER,
        itemType: 'program',
        name: 'Foreign',
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = db.collection('programs').doc('organized');
    await assertFails(ref.update({
      folderId: 'foreign-program-folder',
      updatedBy: OWNER,
    }));
    await assertFails(ref.update({
      provenance: {
        sourceTemplateId: 'source',
        sourceOwnerId: OWNER,
        sourceVersion: 1,
        copiedAt: serverTimestamp(),
        copiedBy: OWNER,
      },
      updatedBy: OWNER,
    }));
  });

  it('denies advancing a program header without its next version', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('programs').doc('version-gap').set({
        ownerId: OWNER,
        createdBy: OWNER,
        updatedBy: OWNER,
        currentVersion: 0,
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('programs').doc('version-gap').update({
        currentVersion: 2,
        updatedBy: OWNER,
      })
    );
  });

  it('allows enrolled athlete to read program versions', async () => {
    await seedProgramWithEnrollment();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('programs').doc(PROGRAM_ID)
        .collection('programVersions').doc('1').set({ workouts: [] });
    });

    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(
      db.collection('programs').doc(PROGRAM_ID)
        .collection('programVersions').doc('1').get()
    );
  });

  it('allows sequential program version creation and keeps it immutable', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('programs').doc('versioned-program').set({
        ownerId: OWNER,
        createdBy: OWNER,
        updatedBy: OWNER,
        currentVersion: 0,
        tags: [],
        folderId: null,
        provenance: null,
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const header = db.collection('programs').doc('versioned-program');
    const version = header.collection('programVersions').doc('1');
    const batch = db.batch();
    batch.set(version, {
      versionNumber: 1,
      publishedAt: serverTimestamp(),
      entries: [],
      changeNote: null,
    });
    batch.update(header, {
      currentVersion: 1,
      updatedBy: OWNER,
    });
    await assertSucceeds(batch.commit());
    await assertFails(version.update({ changeNote: 'rewritten' }));
    await assertFails(version.delete());
  });

  it('denies stranger from reading program versions', async () => {
    await seedProgramWithEnrollment();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('programs').doc(PROGRAM_ID)
        .collection('programVersions').doc('1').set({ workouts: [] });
    });
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('programs').doc(PROGRAM_ID)
        .collection('programVersions').doc('1').get()
    );
  });
});

// ─── Program Folders ───

describe('programFolders', () => {
  async function seedFolder() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('programFolders').doc(FOLDER_ID).set({
        ownerId: OWNER,
        name: 'Strength',
        createdBy: OWNER,
      });
    });
  }

  it('allows owner to create folder with own ownerId', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('programFolders').doc('f-new').set({
        ownerId: OWNER,
        itemType: 'program',
        name: 'New Folder',
        createdBy: OWNER,
        updatedBy: OWNER,
      })
    );
  });

  it('keeps untyped Stage 4 folder writes compatible', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = db.collection('programFolders').doc('legacy-folder-write');
    await assertSucceeds(ref.set({
      ownerId: OWNER,
      name: 'Legacy',
      createdBy: OWNER,
      createdAt: serverTimestamp(),
      updatedBy: OWNER,
      updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(ref.update({
      name: 'Legacy Updated',
      updatedBy: OWNER,
      updatedAt: serverTimestamp(),
    }));
  });

  it('denies creating folder with someone else as owner', async () => {
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('programFolders').doc('f-fake').set({
        ownerId: OWNER, name: 'Fake',
      })
    );
  });

  it('allows owner to read own folder', async () => {
    await seedFolder();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(db.collection('programFolders').doc(FOLDER_ID).get());
  });

  it('denies stranger from reading folder', async () => {
    await seedFolder();
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(db.collection('programFolders').doc(FOLDER_ID).get());
  });

  it('allows owner to rename own folder', async () => {
    await seedFolder();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('programFolders').doc(FOLDER_ID).update({
        itemType: 'program',
        name: 'Power',
        updatedBy: OWNER,
      })
    );
  });

  it('denies non-owner from updating folder', async () => {
    await seedFolder();
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('programFolders').doc(FOLDER_ID).update({ name: 'Hacked' })
    );
  });

  it('allows owner to delete own folder', async () => {
    await seedFolder();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('programFolders').doc(FOLDER_ID).delete()
    );
  });

  it('requires typed folders to be tombstoned before hard deletion', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('programFolders').doc('typed-folder').set({
        ownerId: OWNER,
        itemType: 'exercise',
        name: 'Exercises',
        createdBy: OWNER,
        updatedBy: OWNER,
        deletedAt: null,
        deletedBy: null,
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = db.collection('programFolders').doc('typed-folder');
    await assertFails(ref.delete());
    await assertSucceeds(ref.update({
      deletedAt: serverTimestamp(),
      deletedBy: OWNER,
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
    }));
    await assertSucceeds(ref.delete());
  });

  it('denies non-owner from deleting folder', async () => {
    await seedFolder();
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('programFolders').doc(FOLDER_ID).delete()
    );
  });

  it('denies assigning a tombstoned folder', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('programFolders').doc('deleted-folder').set({
        ownerId: OWNER,
        itemType: 'program',
        name: 'Deleted',
        deletedAt: new Date(),
        deletedBy: OWNER,
      });
      await db.collection('programs').doc('folder-target').set({
        ownerId: OWNER,
        createdBy: OWNER,
        updatedBy: OWNER,
        folderId: null,
        tags: [],
        provenance: null,
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('programs').doc('folder-target').update({
        folderId: 'deleted-folder',
        updatedBy: OWNER,
      })
    );
  });
});

// ─── Enrollments ───

describe('enrollments', () => {
  it('allows program owner to create enrollment', async () => {
    await seedActiveRelationship();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('programs').doc(PROGRAM_ID).set({
        ownerId: OWNER, type: 'assignable',
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('enrollments').doc(ENROLLMENT_ID).set({
        programId: PROGRAM_ID,
        athleteId: ATHLETE,
        addedBy: OWNER,
        status: 'active',
      })
    );
  });

  it('denies enrollment without an active relationship', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('programs').doc(PROGRAM_ID).set({
        ownerId: OWNER, type: 'assignable',
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('enrollments').doc(ENROLLMENT_ID).set({
        programId: PROGRAM_ID,
        athleteId: ATHLETE,
        addedBy: OWNER,
        status: 'active',
      })
    );
  });

  it('denies enrollment in a personal program', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('programs').doc(PROGRAM_ID).set({
        ownerId: OWNER, type: 'personal',
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('enrollments').doc(`${PROGRAM_ID}_${OWNER}`).set({
        programId: PROGRAM_ID,
        athleteId: OWNER,
        addedBy: OWNER,
        status: 'active',
      })
    );
  });

  it('denies athlete from creating enrollment', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('programs').doc(PROGRAM_ID).set({
        ownerId: OWNER, type: 'assignable',
      });
    });
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      db.collection('enrollments').doc(ENROLLMENT_ID).set({
        programId: PROGRAM_ID,
        athleteId: ATHLETE,
        addedBy: ATHLETE,
        status: 'active',
      })
    );
  });

  it('allows athlete to read own enrollment', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(
      db.collection('enrollments').doc(ENROLLMENT_ID).get()
    );
  });

  it('allows owner to read enrollment', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('enrollments').doc(ENROLLMENT_ID).get()
    );
  });

  it('allows get of a non-existent enrollment (isEnrolled check)', async () => {
    // No seed: the enrollment doc does not exist. A get() must return
    // "not found" rather than permission-denied so that searching for a
    // not-yet-enrolled athlete works.
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('enrollments').doc(`${PROGRAM_ID}_${STRANGER}`).get()
    );
  });

  it('denies stranger from reading enrollment', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('enrollments').doc(ENROLLMENT_ID).get()
    );
  });

  it('allows owner to query enrollments by programId', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('enrollments')
        .where('programId', '==', PROGRAM_ID)
        .where('addedBy', '==', OWNER)
        .where('status', '==', 'active')
        .get()
    );
  });

  it('allows athlete to query own enrollments', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(
      db.collection('enrollments')
        .where('athleteId', '==', ATHLETE)
        .where('status', '==', 'active')
        .get()
    );
  });

  it('denies athlete from querying all enrollments for a program', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      db.collection('enrollments')
        .where('programId', '==', PROGRAM_ID)
        .where('status', '==', 'active')
        .get()
    );
  });

  it('allows owner to update enrollment (remove athlete)', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('enrollments').doc(ENROLLMENT_ID).update({
        status: 'removed',
      })
    );
  });

  it('denies athlete from updating enrollment', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      db.collection('enrollments').doc(ENROLLMENT_ID).update({
        status: 'removed',
      })
    );
  });

  it('denies changing enrollment ownership fields', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = db.collection('enrollments').doc(ENROLLMENT_ID);
    await assertFails(ref.update({ athleteId: STRANGER }));
    await assertFails(ref.update({ programId: 'another-program' }));
    await assertFails(ref.update({ addedBy: STRANGER }));
  });

  it('denies reactivating an enrollment after the relationship ends', async () => {
    await seedProgramWithEnrollment();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('enrollments').doc(ENROLLMENT_ID).update({
        status: 'removed',
      });
      await db.collection('trainerClientRelationships')
        .doc(RELATIONSHIP_ID).update({ status: 'ended' });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('enrollments').doc(ENROLLMENT_ID).update({
        status: 'active',
      })
    );
  });

  it('removed athlete cannot read program', async () => {
    await seedProgramWithEnrollment();
    // Remove the enrollment
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('enrollments').doc(ENROLLMENT_ID).update({
        status: 'removed',
      });
    });
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(db.collection('programs').doc(PROGRAM_ID).get());
  });
});

// ─── Workout Instances ───

describe('workoutInstances', () => {
  const INSTANCE_ID = 'instance-1';

  async function seedInstance() {
    await seedProgramWithEnrollment();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutInstances').doc(INSTANCE_ID).set({
        programId: PROGRAM_ID,
        athleteId: ATHLETE,
        assignedBy: OWNER,
        status: 'scheduled',
        scheduledDate: '2026-06-15',
        workoutTemplateId: 'w1',
      });
    });
  }

  it('allows owner to create workout instance', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('workoutInstances').doc('inst-new').set({
        programId: PROGRAM_ID,
        programOwnerId: OWNER,
        athleteId: ATHLETE,
        assignedBy: OWNER,
        status: 'scheduled',
      })
    );
  });

  it('allows an enrolled athlete to assign a workout to themselves', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(
      db.collection('workoutInstances').doc('inst-self-enrolled').set({
        programId: PROGRAM_ID,
        programOwnerId: OWNER,
        athleteId: ATHLETE,
        assignedBy: ATHLETE,
        status: 'scheduled',
      })
    );
  });

  it('denies an unenrolled athlete from assigning a workout to themselves', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('programs').doc(PROGRAM_ID).set({
        ownerId: OWNER,
        name: 'Test Program',
        type: 'assignable',
        status: 'published',
        currentVersion: 1,
      });
    });
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      db.collection('workoutInstances').doc('inst-unenrolled').set({
        programId: PROGRAM_ID,
        programOwnerId: OWNER,
        athleteId: ATHLETE,
        assignedBy: ATHLETE,
        status: 'scheduled',
      })
    );
  });

  it('denies an enrolled athlete from assigning to another athlete', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      db.collection('workoutInstances').doc('inst-other-athlete').set({
        programId: PROGRAM_ID,
        programOwnerId: OWNER,
        athleteId: STRANGER,
        assignedBy: ATHLETE,
        status: 'scheduled',
      })
    );
  });

  it('allows self-assignment for personal programs', async () => {
    // Athlete owns their own personal program
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('programs').doc('personal-1').set({
        ownerId: ATHLETE, type: 'personal',
      });
    });
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(
      db.collection('workoutInstances').doc('inst-self').set({
        programId: 'personal-1',
        programOwnerId: ATHLETE,
        athleteId: ATHLETE,
        assignedBy: ATHLETE,
        status: 'scheduled',
      })
    );
  });

  it('allows athlete to read own instance', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(
      db.collection('workoutInstances').doc(INSTANCE_ID).get()
    );
  });

  it('allows owner to read instance', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('workoutInstances').doc(INSTANCE_ID).get()
    );
  });

  it('allows program owner to read an athlete self-assigned instance', async () => {
    await seedProgramWithEnrollment();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutInstances').doc('self-new').set({
        programId: PROGRAM_ID,
        programOwnerId: OWNER,
        athleteId: ATHLETE,
        assignedBy: ATHLETE,
        status: 'scheduled',
        scheduledDate: '2026-06-16',
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('workoutInstances').doc('self-new').get()
    );
  });

  it('allows owner to query self-assigned workouts by programOwnerId', async () => {
    await seedProgramWithEnrollment();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutInstances').doc('self-new').set({
        programId: PROGRAM_ID,
        programOwnerId: OWNER,
        athleteId: ATHLETE,
        assignedBy: ATHLETE,
        status: 'scheduled',
        scheduledDate: '2026-06-16',
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('workoutInstances')
        .where('programOwnerId', '==', OWNER)
        .where('athleteId', '==', ATHLETE)
        .where('scheduledDate', '>=', '2026-06-01')
        .where('scheduledDate', '<=', '2026-06-30')
        .orderBy('scheduledDate')
        .get()
    );
  });

  it('denies creating an instance with the wrong programOwnerId', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      db.collection('workoutInstances').doc('wrong-owner').set({
        programId: PROGRAM_ID,
        programOwnerId: STRANGER,
        athleteId: ATHLETE,
        assignedBy: ATHLETE,
        status: 'scheduled',
      })
    );
  });

  it('denies stranger from reading instance', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('workoutInstances').doc(INSTANCE_ID).get()
    );
  });

  it('allows owner to query an athletes calendar by assignedBy', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('workoutInstances')
        .where('assignedBy', '==', OWNER)
        .where('athleteId', '==', ATHLETE)
        .where('scheduledDate', '>=', '2026-06-01')
        .where('scheduledDate', '<=', '2026-06-30')
        .orderBy('scheduledDate')
        .get()
    );
  });

  it('allows athlete to query own calendar by athleteId', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(
      db.collection('workoutInstances')
        .where('athleteId', '==', ATHLETE)
        .get()
    );
  });

  it('denies stranger from querying an athletes calendar', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('workoutInstances')
        .where('athleteId', '==', ATHLETE)
        .get()
    );
  });

  it('allows athlete to complete own instance', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(
      db.collection('workoutInstances').doc(INSTANCE_ID).update({
        status: 'completed', rpe: 7, durationMinutes: 60,
      })
    );
  });

  it('allows athlete to backfill the verified owner on a legacy instance', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(
      db.collection('workoutInstances').doc(INSTANCE_ID).update({
        programOwnerId: OWNER,
      })
    );
  });

  it('denies athlete from backfilling an incorrect program owner', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      db.collection('workoutInstances').doc(INSTANCE_ID).update({
        programOwnerId: STRANGER,
      })
    );
  });

  it('denies changing programOwnerId after it is set', async () => {
    await seedProgramWithEnrollment();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutInstances').doc('new-owner').set({
        programId: PROGRAM_ID,
        programOwnerId: OWNER,
        athleteId: ATHLETE,
        assignedBy: ATHLETE,
        status: 'scheduled',
      });
    });
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      db.collection('workoutInstances').doc('new-owner').update({
        programOwnerId: STRANGER,
      })
    );
  });

  it('allows owner to cancel instance', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('workoutInstances').doc(INSTANCE_ID).update({
        status: 'cancelled',
      })
    );
  });

  it('denies owner from completing instance', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('workoutInstances').doc(INSTANCE_ID).update({
        status: 'completed', rpe: 7, durationMinutes: 60,
      })
    );
  });

  it('allows owner to reschedule instance', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('workoutInstances').doc(INSTANCE_ID).update({
        scheduledDate: '2026-06-20', updatedAt: new Date(),
      })
    );
  });

  it('allows owner to swap the workout on an instance', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('workoutInstances').doc(INSTANCE_ID).update({
        workoutTemplateId: 'w2', workoutTemplateVersion: 2,
        workoutType: 'pull', updatedAt: new Date(),
      })
    );
  });

  it('denies trainer scheduling changes after relationship ends', async () => {
    await seedInstance();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('trainerClientRelationships')
        .doc(RELATIONSHIP_ID).update({ status: 'ended' });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('workoutInstances').doc(INSTANCE_ID).update({
        scheduledDate: '2026-06-20',
      })
    );
  });

  it('denies owner from editing athlete completion notes', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('workoutInstances').doc(INSTANCE_ID).update({
        athleteNotes: 'owner trying to edit notes',
      })
    );
  });

  it('denies stranger from updating instance', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('workoutInstances').doc(INSTANCE_ID).update({
        status: 'cancelled',
      })
    );
  });
});
