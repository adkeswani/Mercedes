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

  it('allows an owner to read a legacy enrollment and backfill its relationship',
      async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('enrollments').doc(ENROLLMENT_ID).set({
        programId: PROGRAM_ID,
        athleteId: ATHLETE,
        addedBy: OWNER,
        status: 'active',
      });
    });

    const db = testEnv.authenticatedContext(OWNER).firestore();
    const enrollments = await assertSucceeds(
      db.collection('enrollments')
        .where('addedBy', '==', OWNER)
        .where('status', '==', 'active')
        .get()
    );
    expect(enrollments.docs).toHaveLength(1);
    await assertSucceeds(
      db.runTransaction(async (transaction) => {
        const relationship = db.collection('trainerClientRelationships')
          .doc(RELATIONSHIP_ID);
        const enrollment = db.collection('enrollments').doc(ENROLLMENT_ID);
        const existing = await transaction.get(relationship);
        expect(existing.exists).toBe(false);
        expect((await transaction.get(enrollment)).exists).toBe(true);
        transaction.set(relationship, activeRelationship());
      })
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
      status: 'ending',
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
    }));
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

  it('allows the owner to atomically publish typed blocks and stable slots', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adminDb = ctx.firestore();
      await adminDb.collection('workoutTemplates').doc('typed').set({
        ownerId: OWNER,
        createdBy: OWNER,
        currentVersion: 0,
      });
      for (const exerciseId of ['e1', 'e2']) {
        await adminDb.collection('exerciseTemplates').doc(exerciseId).set({
          ownerId: OWNER,
          createdBy: OWNER,
          currentVersion: 1,
        });
        await adminDb.collection('exerciseTemplates').doc(exerciseId)
          .collection('exerciseVersions').doc('1').set({ versionNumber: 1 });
      }
    });

    const db = testEnv.authenticatedContext(OWNER).firestore();
    const header = db.collection('workoutTemplates').doc('typed');
    const version = header.collection('workoutTemplateVersions').doc('1');
    const batch = db.batch();
    const block = {
      blockId: 'circuit-1',
      type: 'circuit',
      sortOrder: 0,
      slotIds: ['slot-1', 'slot-2'],
      slotStartOrder: 0,
      slotCount: 2,
      rounds: 4,
      restBetweenRoundsSeconds: 60,
    };
    const slots = [{
      slotId: 'slot-1',
      blockId: 'circuit-1',
      blockSortOrder: 0,
      slotOrder: 0,
      exerciseId: 'e1',
      exerciseVersion: 1,
      sortOrder: 0,
      exerciseName: 'Squat',
      prescription: { mode: 'reps', sets: 5, reps: '5' },
    }, {
      slotId: 'slot-2',
      blockId: 'circuit-1',
      blockSortOrder: 0,
      slotOrder: 1,
      exerciseId: 'e2',
      exerciseVersion: 1,
      sortOrder: 1,
      exerciseName: 'Pull-up',
      prescription: { mode: 'amrap' },
    }];
    batch.set(version, {
      versionNumber: 1,
      storageFormat: 'typedWorkoutBlocksV1',
      publishState: 'draft',
      ownerId: OWNER,
      blockCount: 1,
      slotCount: 2,
      blockIds: ['circuit-1'],
      slotIds: ['slot-1', 'slot-2'],
      blocks: [block],
      slots,
    });
    batch.set(version.collection('workoutBlocks').doc('circuit-1'), block);
    batch.set(version.collection('exerciseSlots').doc('slot-1'), slots[0]);
    batch.set(version.collection('exerciseSlots').doc('slot-2'), slots[1]);
    await assertSucceeds(batch.commit());
    const seal = db.batch();
    seal.update(version, { publishState: 'published' });
    seal.update(header, { currentVersion: 1, updatedBy: OWNER });
    await assertSucceeds(seal.commit());
  });

  it('allows nine typed slots with distinct blocks and exercises', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adminDb = ctx.firestore();
      await adminDb.collection('workoutTemplates').doc('typed-nine').set({
        ownerId: OWNER,
        createdBy: OWNER,
        currentVersion: 0,
      });
      for (let index = 0; index < 9; index++) {
        const exercise = adminDb.collection('exerciseTemplates')
          .doc(`typed-exercise-${index}`);
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
    const header = db.collection('workoutTemplates').doc('typed-nine');
    const version = header.collection('workoutTemplateVersions').doc('1');
    const batch = db.batch();
    const blocks = Array.from({ length: 9 }, (_, index) => ({
      blockId: `block-${index}`,
      type: 'standardExercise',
      sortOrder: index,
      slotIds: [`slot-${index}`],
      slotStartOrder: index,
      slotCount: 1,
    }));
    const slots = Array.from({ length: 9 }, (_, index) => ({
      slotId: `slot-${index}`,
      blockId: `block-${index}`,
      blockSortOrder: index,
      slotOrder: index,
      exerciseId: `typed-exercise-${index}`,
      exerciseVersion: 1,
      sortOrder: 0,
      prescription: { mode: 'reps' },
    }));
    batch.set(version, {
      versionNumber: 1,
      storageFormat: 'typedWorkoutBlocksV1',
      publishState: 'draft',
      ownerId: OWNER,
      blockCount: 9,
      slotCount: 9,
      blockIds: blocks.map((block) => block.blockId),
      slotIds: slots.map((slot) => slot.slotId),
      blocks,
      slots,
    });
    for (let index = 0; index < 9; index++) {
      batch.set(
        version.collection('workoutBlocks').doc(`block-${index}`),
        blocks[index]
      );
      batch.set(
        version.collection('exerciseSlots').doc(`slot-${index}`),
        slots[index]
      );
    }
    await assertSucceeds(batch.commit());
    const seal = db.batch();
    seal.update(version, { publishState: 'published' });
    seal.update(header, { currentVersion: 1, updatedBy: OWNER });
    await assertSucceeds(seal.commit());
  });

  it('denies a valid typed block with a foreign exercise slot', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adminDb = ctx.firestore();
      await adminDb.collection('workoutTemplates').doc('invalid-typed').set({
        ownerId: OWNER,
        createdBy: OWNER,
        currentVersion: 0,
      });
      await adminDb.collection('exerciseTemplates').doc('foreign-typed').set({
        ownerId: STRANGER,
        createdBy: STRANGER,
        currentVersion: 1,
      });
      await adminDb.collection('exerciseTemplates').doc('foreign-typed')
        .collection('exerciseVersions').doc('1').set({ versionNumber: 1 });
    });

    const db = testEnv.authenticatedContext(OWNER).firestore();
    const header = db.collection('workoutTemplates').doc('invalid-typed');
    const version = header.collection('workoutTemplateVersions').doc('1');
    const batch = db.batch();
    const block = {
      blockId: 'interval',
      type: 'timedInterval',
      sortOrder: 0,
      slotIds: ['slot-foreign'],
      slotStartOrder: 0,
      slotCount: 1,
      rounds: 5,
      workSeconds: 30,
      restSeconds: 30,
    };
    const slot = {
      slotId: 'slot-foreign',
      blockId: 'interval',
      blockSortOrder: 0,
      slotOrder: 0,
      exerciseId: 'foreign-typed',
      exerciseVersion: 1,
      sortOrder: 0,
      prescription: { mode: 'time' },
    };
    batch.set(version, {
      versionNumber: 1,
      storageFormat: 'typedWorkoutBlocksV1',
      publishState: 'draft',
      ownerId: OWNER,
      blockCount: 1,
      slotCount: 1,
      blockIds: ['interval'],
      slotIds: ['slot-foreign'],
      blocks: [block],
      slots: [slot],
    });
    batch.set(version.collection('workoutBlocks').doc('interval'), block);
    batch.set(version.collection('exerciseSlots').doc('slot-foreign'), slot);
    await assertFails(batch.commit());
  });

  it('denies a typed manifest with a nonexistent exercise pin', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutTemplates').doc('missing-pin')
        .set({ ownerId: OWNER, createdBy: OWNER, currentVersion: 0 });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const header = db.collection('workoutTemplates').doc('missing-pin');
    const version = header.collection('workoutTemplateVersions').doc('1');
    const block = {
      blockId: 'standard',
      type: 'standardExercise',
      sortOrder: 0,
      slotIds: ['missing-slot'],
      slotStartOrder: 0,
      slotCount: 1,
    };
    const slot = {
      slotId: 'missing-slot',
      blockId: 'standard',
      blockSortOrder: 0,
      slotOrder: 0,
      exerciseId: 'does-not-exist',
      exerciseVersion: 1,
      sortOrder: 0,
      prescription: { mode: 'reps' },
    };
    const batch = db.batch();
    batch.set(version, {
      versionNumber: 1,
      storageFormat: 'typedWorkoutBlocksV1',
      publishState: 'draft',
      ownerId: OWNER,
      blockCount: 1,
      slotCount: 1,
      blockIds: ['standard'],
      slotIds: ['missing-slot'],
      blocks: [block],
      slots: [slot],
    });
    batch.set(version.collection('workoutBlocks').doc('standard'), block);
    batch.set(version.collection('exerciseSlots').doc('missing-slot'), slot);
    await assertFails(batch.commit());
  });

  it('denies duplicate stable IDs in a typed workout manifest', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutTemplates').doc('duplicates')
        .set({ ownerId: OWNER, createdBy: OWNER, currentVersion: 0 });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const header = db.collection('workoutTemplates').doc('duplicates');
    const version = header.collection('workoutTemplateVersions').doc('1');
    const batch = db.batch();
    batch.set(version, {
      versionNumber: 1,
      storageFormat: 'typedWorkoutBlocksV1',
      publishState: 'draft',
      ownerId: OWNER,
      blockCount: 2,
      slotCount: 2,
      blockIds: ['duplicate-block', 'duplicate-block'],
      slotIds: ['duplicate-slot', 'duplicate-slot'],
      blocks: [{}, {}],
      slots: [{}, {}],
    });
    await assertFails(batch.commit());
  });

  it('keeps incomplete typed drafts private and prevents sealing', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutTemplates').doc('incomplete')
        .set({ ownerId: OWNER, createdBy: OWNER, currentVersion: 0 });
    });
    const ownerDb = testEnv.authenticatedContext(OWNER).firestore();
    const header = ownerDb.collection('workoutTemplates').doc('incomplete');
    const version = header.collection('workoutTemplateVersions').doc('1');
    const block = {
      blockId: 'standard',
      type: 'standardExercise',
      sortOrder: 0,
      slotIds: ['slot-1'],
      slotStartOrder: 0,
      slotCount: 1,
    };
    const slot = {
      slotId: 'slot-1',
      blockId: 'standard',
      blockSortOrder: 0,
      slotOrder: 0,
      exerciseId: 'e1',
      exerciseVersion: 1,
      sortOrder: 0,
      prescription: { mode: 'reps' },
    };
    const draft = ownerDb.batch();
    draft.set(version, {
      versionNumber: 1,
      storageFormat: 'typedWorkoutBlocksV1',
      publishState: 'draft',
      ownerId: OWNER,
      blockCount: 1,
      slotCount: 1,
      blockIds: ['standard'],
      slotIds: ['slot-1'],
      blocks: [block],
      slots: [slot],
    });
    draft.set(version.collection('workoutBlocks').doc('standard'), block);
    await assertSucceeds(draft.commit());
    await assertSucceeds(version.get());
    const strangerVersion = testEnv.authenticatedContext(STRANGER)
      .firestore().collection('workoutTemplates').doc('incomplete')
      .collection('workoutTemplateVersions').doc('1');
    await assertFails(strangerVersion.get());
    await assertFails(
      strangerVersion.collection('workoutBlocks').doc('standard').get()
    );
    await assertFails(
      strangerVersion.collection('workoutBlocks').doc('standard').delete()
    );

    const seal = ownerDb.batch();
    seal.update(version, { publishState: 'published' });
    seal.update(header, { currentVersion: 1, updatedBy: OWNER });
    await assertFails(seal.commit());

    await assertFails(
      version.collection('workoutBlocks').doc('standard').delete()
    );
    await assertFails(version.delete());
    await assertSucceeds(version.update({ publishState: 'deleting' }));
    await assertSucceeds(
      version.collection('workoutBlocks').doc('standard').delete()
    );
    await assertSucceeds(version.update({ blocksCleared: true }));
    await assertSucceeds(version.update({ slotsCleared: true }));
    await assertSucceeds(version.delete());
  });

  it('denies overlapping block slot ranges in a typed draft', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutTemplates').doc('overlap')
        .set({ ownerId: OWNER, createdBy: OWNER, currentVersion: 0 });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const version = db.collection('workoutTemplates').doc('overlap')
      .collection('workoutTemplateVersions').doc('1');
    const firstBlock = {
      blockId: 'first',
      type: 'standardExercise',
      sortOrder: 0,
      slotIds: ['slot-1'],
      slotStartOrder: 0,
      slotCount: 1,
    };
    const secondBlock = {
      blockId: 'second',
      type: 'standardExercise',
      sortOrder: 1,
      slotIds: ['slot-1'],
      slotStartOrder: 0,
      slotCount: 1,
    };
    const slot = {
      slotId: 'slot-1',
      blockId: 'first',
      blockSortOrder: 0,
      slotOrder: 0,
      exerciseId: 'e1',
      exerciseVersion: 1,
      sortOrder: 0,
      prescription: { mode: 'reps' },
    };
    const batch = db.batch();
    batch.set(version, {
      versionNumber: 1,
      storageFormat: 'typedWorkoutBlocksV1',
      publishState: 'draft',
      ownerId: OWNER,
      blockCount: 2,
      slotCount: 1,
      blockIds: ['first', 'second'],
      slotIds: ['slot-1'],
      blocks: [firstBlock, secondBlock],
      slots: [slot],
    });
    batch.set(version.collection('workoutBlocks').doc('first'), firstBlock);
    batch.set(version.collection('workoutBlocks').doc('second'), secondBlock);
    batch.set(version.collection('exerciseSlots').doc('slot-1'), slot);
    await assertFails(batch.commit());
  });

  it('denies implicit version 1 for an explicit zero-version exercise', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adminDb = ctx.firestore();
      await adminDb.collection('exerciseTemplates').doc('zero-version').set({
        ownerId: OWNER,
        createdBy: OWNER,
        currentVersion: 0,
      });
      await adminDb.collection('workoutTemplates').doc('zero-pin').set({
        ownerId: OWNER,
        createdBy: OWNER,
        currentVersion: 0,
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const header = db.collection('workoutTemplates').doc('zero-pin');
    const version = header.collection('workoutTemplateVersions').doc('1');
    const batch = db.batch();
    batch.update(header, { currentVersion: 1, updatedBy: OWNER });
    batch.set(version, {
      versionNumber: 1,
      storageFormat: 'exercisePrescriptionSubcollection',
      prescriptionCount: 1,
    });
    batch.set(version.collection('exercisePrescriptions').doc('0'), {
      exerciseId: 'zero-version',
      exerciseVersion: 1,
      sortOrder: 0,
      prescription: { mode: 'reps' },
    });
    await assertFails(batch.commit());
  });

  it('prevents typed workout blocks and slots from update or delete', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const version = ctx.firestore().collection('workoutTemplates')
        .doc('immutable-typed').collection('workoutTemplateVersions').doc('1');
      await version.collection('workoutBlocks').doc('block-1').set({
        blockId: 'block-1', type: 'standardExercise', sortOrder: 0,
      });
      await version.collection('exerciseSlots').doc('slot-1').set({
        slotId: 'slot-1', blockId: 'block-1', exerciseId: 'e1',
        exerciseVersion: 1, sortOrder: 0, prescription: { mode: 'reps' },
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const version = db.collection('workoutTemplates').doc('immutable-typed')
      .collection('workoutTemplateVersions').doc('1');
    await assertFails(
      version.collection('workoutBlocks').doc('block-1').update({ rounds: 2 })
    );
    await assertFails(
      version.collection('exerciseSlots').doc('slot-1').delete()
    );
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
      propagationState: 'pending',
      propagationRequestedAt: serverTimestamp(),
      propagationAttempt: 0,
      propagationStartedAt: null,
      propagationCompletedAt: null,
      propagationFailedAt: null,
      propagationError: null,
    });
    batch.update(header, {
      currentVersion: 1,
      updatedBy: OWNER,
    });
    await assertSucceeds(batch.commit());
    await assertFails(version.update({ changeNote: 'rewritten' }));
    await assertFails(version.delete());
  });

  it('denies client-forged completed propagation state', async () => {
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
    const batch = db.batch();
    batch.set(header.collection('programVersions').doc('1'), {
      versionNumber: 1,
      publishedAt: serverTimestamp(),
      entries: [],
      changeNote: null,
      propagationState: 'complete',
      propagationRequestedAt: serverTimestamp(),
      propagationAttempt: 0,
      propagationStartedAt: null,
      propagationCompletedAt: serverTimestamp(),
      propagationFailedAt: null,
      propagationError: null,
    });
    batch.update(header, {
      currentVersion: 1,
      updatedBy: OWNER,
    });
    await assertFails(batch.commit());
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

// ─── Athlete Program Instances ───

describe('athleteProgramInstances', () => {
  const INSTANCE_ID = 'athlete-program-1';

  function instanceData(mode = 'subscribed') {
    return {
      athleteOwnerId: ATHLETE,
      assigningTrainerId: OWNER,
      sourceProgramId: PROGRAM_ID,
      sourceProgramVersion: 1,
      relationshipMode: mode,
      startDate: '2027-01-01',
      expectedEndDate: '2027-02-01',
      workoutCount: 1,
      status: 'active',
      linkedAt: mode === 'subscribed' ? serverTimestamp() : null,
      unlinkedAt: null,
      unlinkReason: null,
      materializationKey: 'request-1',
      propagationState: 'complete',
      propagationTargetVersion: 1,
      propagationAttempt: 0,
      propagationStartedAt: null,
      propagationCompletedAt: serverTimestamp(),
      propagationFailedAt: null,
      propagationError: null,
      createdAt: serverTimestamp(),
      createdBy: OWNER,
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
      deletedAt: null,
      deletedBy: null,
    };
  }

  it('allows trainer to create subscribed or copied athlete instances', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('athleteProgramInstances').doc(INSTANCE_ID)
        .set(instanceData())
    );
    await assertSucceeds(
      db.collection('athleteProgramInstances').doc('athlete-program-copy')
        .set(instanceData('copied'))
    );
  });

  it('denies a stranger from creating or reading an athlete instance', async () => {
    await seedProgramWithEnrollment();
    const ownerDb = testEnv.authenticatedContext(OWNER).firestore();
    await ownerDb.collection('athleteProgramInstances').doc(INSTANCE_ID)
      .set(instanceData());
    const strangerDb = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      strangerDb.collection('athleteProgramInstances').doc('forged')
        .set({ ...instanceData(), createdBy: STRANGER, updatedBy: STRANGER })
    );
    await assertFails(
      strangerDb.collection('athleteProgramInstances').doc(INSTANCE_ID).get()
    );
  });

  it('allows athlete-confirmed subscription conversion but not identity edits', async () => {
    await seedProgramWithEnrollment();
    const ownerDb = testEnv.authenticatedContext(OWNER).firestore();
    await ownerDb.collection('athleteProgramInstances').doc(INSTANCE_ID)
      .set(instanceData());
    const athleteDb = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(
      athleteDb.collection('athleteProgramInstances').doc(INSTANCE_ID).update({
        relationshipMode: 'copied',
        unlinkedAt: serverTimestamp(),
        unlinkReason: 'structuralCustomization',
        updatedAt: serverTimestamp(),
        updatedBy: ATHLETE,
      })
    );
    await assertFails(
      athleteDb.collection('athleteProgramInstances').doc(INSTANCE_ID).update({
        sourceProgramVersion: 99,
        updatedAt: serverTimestamp(),
        updatedBy: ATHLETE,
      })
    );
    await assertFails(
      athleteDb.collection('athleteProgramInstances').doc(INSTANCE_ID).update({
        propagationState: 'complete',
        propagationTargetVersion: 99,
        updatedAt: serverTimestamp(),
        updatedBy: ATHLETE,
      })
    );
  });

  it('allows only one-way athlete program lifecycle transitions', async () => {
    await seedProgramWithEnrollment();
    const ownerDb = testEnv.authenticatedContext(OWNER).firestore();
    await ownerDb.collection('athleteProgramInstances').doc(INSTANCE_ID)
      .set(instanceData());
    const athleteDb = testEnv.authenticatedContext(ATHLETE).firestore();
    const instance =
      athleteDb.collection('athleteProgramInstances').doc(INSTANCE_ID);
    await assertSucceeds(instance.update({
      status: 'completed',
      updatedAt: serverTimestamp(),
      updatedBy: ATHLETE,
    }));
    await assertFails(instance.update({
      status: 'active',
      updatedAt: serverTimestamp(),
      updatedBy: ATHLETE,
    }));
  });

  it('allows recoverable relationship ending to unlink children and parent', async () => {
    await seedProgramWithEnrollment();
    await seedActiveRelationship();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const instance = db.collection('athleteProgramInstances').doc(INSTANCE_ID);
    await instance.set(instanceData());
    const workout = db.collection('workoutInstances').doc('unlink-workout');
    await workout.set({
      programId: PROGRAM_ID,
      programOwnerId: OWNER,
      programVersion: 1,
      athleteProgramInstanceId: INSTANCE_ID,
      programAssignmentId: INSTANCE_ID,
      relationshipMode: 'subscribed',
      athleteId: ATHLETE,
      assignedBy: OWNER,
      status: 'scheduled',
      scheduledDate: '2099-01-01',
      scheduledAt: new Date('2099-01-01T00:00:00Z'),
    });
    await db.collection('trainerClientRelationships').doc(RELATIONSHIP_ID).update({
      status: 'ending',
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
    });
    await assertSucceeds(
      db.collection('workoutInstances')
        .where('athleteProgramInstanceId', '==', INSTANCE_ID)
        .where('athleteId', '==', ATHLETE)
        .where('programOwnerId', '==', OWNER)
        .get()
    );
    await assertSucceeds(workout.update({
      relationshipMode: 'copied',
      updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(instance.update({
      relationshipMode: 'copied',
      unlinkedAt: serverTimestamp(),
      unlinkReason: 'relationshipEnded',
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
    }));
    await assertSucceeds(
      db.collection('trainerClientRelationships').doc(RELATIONSHIP_ID).update({
        status: 'ended',
        endedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
        updatedBy: OWNER,
      })
    );
  });

  it('allows athlete to backfill a copied legacy assignment without owner field',
      async () => {
    await seedProgramWithEnrollment();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('enrollments').doc(ENROLLMENT_ID)
        .update({ status: 'removed' });
      await db.collection('workoutInstances').doc('legacy-workout').set({
        programId: PROGRAM_ID,
        programVersion: 1,
        programAssignmentId: 'legacy-assignment',
        athleteId: ATHLETE,
        assignedBy: OWNER,
        status: 'completed',
        scheduledDate: '2025-01-01',
      });
    });
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    const batch = db.batch();
    batch.set(
      db.collection('athleteProgramInstances').doc('legacy-assignment'),
      {
        athleteOwnerId: ATHLETE,
        assigningTrainerId: OWNER,
        sourceProgramId: PROGRAM_ID,
        sourceProgramVersion: 1,
        relationshipMode: 'copied',
        startDate: '2025-01-01',
        expectedEndDate: '2025-01-01',
        workoutCount: 1,
        status: 'completed',
        linkedAt: null,
        unlinkedAt: null,
        unlinkReason: null,
        materializationKey: null,
        propagationState: 'complete',
        propagationTargetVersion: 1,
        propagationAttempt: 0,
        propagationStartedAt: null,
        propagationCompletedAt: serverTimestamp(),
        propagationFailedAt: null,
        propagationError: null,
        createdAt: serverTimestamp(),
        createdBy: ATHLETE,
        updatedAt: serverTimestamp(),
        updatedBy: ATHLETE,
        deletedAt: null,
        deletedBy: null,
      }
    );
    batch.update(db.collection('workoutInstances').doc('legacy-workout'), {
      athleteProgramInstanceId: 'legacy-assignment',
      relationshipMode: 'copied',
    });
    await assertSucceeds(batch.commit());
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
        scheduledAt: new Date('2099-06-15T00:00:00Z'),
        workoutTemplateId: 'w1',
        workoutTemplateVersion: 1,
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
    await assertFails(
      db.collection('workoutInstances').doc('inst-with-results').set({
        programId: PROGRAM_ID,
        programOwnerId: OWNER,
        athleteId: ATHLETE,
        assignedBy: OWNER,
        status: 'scheduled',
        actualSlotIds: ['forged-slot'],
      })
    );
  });

  it('allows atomic materialization against a first-class program instance',
      async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const programInstance =
      db.collection('athleteProgramInstances').doc('materialized-1');
    const workout = db.collection('workoutInstances').doc('materialized-w1');
    const batch = db.batch();
    batch.set(programInstance, {
      athleteOwnerId: ATHLETE,
      assigningTrainerId: OWNER,
      sourceProgramId: PROGRAM_ID,
      sourceProgramVersion: 1,
      relationshipMode: 'subscribed',
      startDate: '2027-01-01',
      expectedEndDate: '2027-01-01',
      workoutCount: 1,
      status: 'active',
      linkedAt: serverTimestamp(),
      unlinkedAt: null,
      unlinkReason: null,
      materializationKey: 'atomic-1',
      propagationState: 'complete',
      propagationTargetVersion: 1,
      propagationAttempt: 0,
      propagationStartedAt: null,
      propagationCompletedAt: serverTimestamp(),
      propagationFailedAt: null,
      propagationError: null,
      createdAt: serverTimestamp(),
      createdBy: OWNER,
      updatedAt: serverTimestamp(),
      updatedBy: OWNER,
      deletedAt: null,
      deletedBy: null,
    });
    batch.set(workout, {
      programId: PROGRAM_ID,
      programOwnerId: OWNER,
      programVersion: 1,
      athleteProgramInstanceId: 'materialized-1',
      programAssignmentId: 'materialized-1',
      relationshipMode: 'subscribed',
      athleteId: ATHLETE,
      assignedBy: OWNER,
      status: 'scheduled',
      scheduledAt: new Date('2027-01-01T00:00:00Z'),
    });
    await assertSucceeds(batch.commit());
  });

  it('denies a mismatched first-class program reference', async () => {
    await seedProgramWithEnrollment();
    const ownerDb = testEnv.authenticatedContext(OWNER).firestore();
    await ownerDb.collection('athleteProgramInstances').doc('materialized-1')
      .set({
        athleteOwnerId: ATHLETE,
        assigningTrainerId: OWNER,
        sourceProgramId: PROGRAM_ID,
        sourceProgramVersion: 1,
        relationshipMode: 'copied',
        startDate: '2027-01-01',
        expectedEndDate: '2027-01-01',
        workoutCount: 1,
        status: 'active',
        linkedAt: null,
        unlinkedAt: null,
        unlinkReason: null,
        materializationKey: null,
        propagationState: 'complete',
        propagationTargetVersion: 1,
        propagationAttempt: 0,
        propagationStartedAt: null,
        propagationCompletedAt: serverTimestamp(),
        propagationFailedAt: null,
        propagationError: null,
        createdAt: serverTimestamp(),
        createdBy: OWNER,
        updatedAt: serverTimestamp(),
        updatedBy: OWNER,
        deletedAt: null,
        deletedBy: null,
      });
    await assertFails(
      ownerDb.collection('workoutInstances').doc('mismatch').set({
        programId: PROGRAM_ID,
        programOwnerId: OWNER,
        programVersion: 1,
        athleteProgramInstanceId: 'materialized-1',
        programAssignmentId: 'different-id',
        relationshipMode: 'copied',
        athleteId: ATHLETE,
        assignedBy: OWNER,
        status: 'scheduled',
        scheduledAt: new Date('2027-01-01T00:00:00Z'),
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

  it('allows owner to query a program assignment by immutable owner', async () => {
    await seedProgramWithEnrollment();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutInstances').doc('assignment-owned').set({
        programId: PROGRAM_ID,
        programOwnerId: OWNER,
        programAssignmentId: 'assignment-1',
        athleteId: ATHLETE,
        assignedBy: ATHLETE,
        status: 'scheduled',
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('workoutInstances')
        .where('programAssignmentId', '==', 'assignment-1')
        .where('programOwnerId', '==', OWNER)
        .get()
    );
  });

  it('allows an owner-scoped program and athlete query', async () => {
    await seedProgramWithEnrollment();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutInstances').doc('program-owned').set({
        programId: PROGRAM_ID,
        programOwnerId: OWNER,
        athleteId: ATHLETE,
        assignedBy: OWNER,
        status: 'scheduled',
        scheduledDate: '2026-06-16',
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('workoutInstances')
        .where('programId', '==', PROGRAM_ID)
        .where('athleteId', '==', ATHLETE)
        .where('programOwnerId', '==', OWNER)
        .orderBy('scheduledDate', 'desc')
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

  it('allows only the athlete-scoped calendar range query', async () => {
    await seedInstance();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutInstances').doc('other').set({
        programId: PROGRAM_ID,
        athleteId: STRANGER,
        assignedBy: OWNER,
        status: 'scheduled',
        scheduledDate: '2026-06-16',
      });
    });
    const athleteDb = testEnv.authenticatedContext(ATHLETE).firestore();
    const ownCalendar = await assertSucceeds(
      athleteDb.collection('workoutInstances')
        .where('athleteId', '==', ATHLETE)
        .where('scheduledDate', '>=', '2026-06-01')
        .where('scheduledDate', '<=', '2026-06-30')
        .orderBy('scheduledDate')
        .get()
    );
    expect(ownCalendar.docs.map((doc) => doc.id)).toEqual([INSTANCE_ID]);
    await assertFails(
      athleteDb.collection('workoutInstances')
        .where('athleteId', '==', STRANGER)
        .where('scheduledDate', '>=', '2026-06-01')
        .where('scheduledDate', '<=', '2026-06-30')
        .orderBy('scheduledDate')
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

  it('allows a Stage 4 client to complete a newly shaped instance', async () => {
    await seedInstance();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutInstances').doc(INSTANCE_ID)
        .update({
          actualsStorageFormat: 'slotResultsSubcollection',
          actualSlotIds: [],
          actuals: [],
        });
    });
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(
      db.collection('workoutInstances').doc(INSTANCE_ID).update({
        status: 'completed',
        rpe: 7,
        durationMinutes: 60,
        actuals: [{
          exerciseId: 'e1',
          mode: 'reps',
          sets: 5,
          reps: '5',
        }],
      })
    );
  });

  it('allows athlete completion actuals keyed by stable slot ID', async () => {
    await seedInstance();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const version = ctx.firestore().collection('workoutTemplates').doc('w1')
        .collection('workoutTemplateVersions').doc('1');
      await version.set({
        versionNumber: 1,
        storageFormat: 'typedWorkoutBlocksV1',
        blockCount: 1,
        slotCount: 1,
        slots: [{
          slotId: 'slot-1',
          exerciseId: 'e1',
        }],
      });
      await version.collection('exerciseSlots').doc('0').set({
        slotId: 'slot-1',
        blockId: 'block-1',
        blockSortOrder: 0,
        slotOrder: 0,
        exerciseId: 'e1',
        exerciseVersion: 1,
        sortOrder: 0,
        prescription: { mode: 'reps' },
      });
    });
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    const instance = db.collection('workoutInstances').doc(INSTANCE_ID);
    const batch = db.batch();
    batch.update(instance, {
      status: 'completed',
      rpe: 7,
      durationMinutes: 60,
      actualsStorageFormat: 'slotResultsSubcollection',
      actualSlotIds: ['slot-1'],
      actuals: deleteField(),
      updatedAt: serverTimestamp(),
    });
    batch.set(instance.collection('slotResults').doc('slot-1'), {
      exerciseId: 'e1', slotOrder: 0, mode: 'reps', sets: 5, reps: '5',
    });
    await assertSucceeds(batch.commit());
    const rewrite = db.batch();
    rewrite.update(instance, { updatedAt: serverTimestamp() });
    rewrite.update(instance.collection('slotResults').doc('slot-1'), {
      sets: 99,
    });
    await assertFails(rewrite.commit());
    await assertFails(
      instance.collection('slotResults').doc('legacy-slot-0').set({
        exerciseId: 'arbitrary',
        slotOrder: 0,
        mode: 'reps',
      })
    );
    await assertFails(
      instance.collection('slotResults').doc('slot-1').delete()
    );
    await assertFails(instance.update({ actualSlotIds: [] }));
  });

  it('requires parent and slot results to be updated atomically', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    const instance = db.collection('workoutInstances').doc(INSTANCE_ID);
    await assertFails(
      instance.collection('slotResults').doc('legacy-slot-0').set({
        exerciseId: 'e1',
        slotOrder: 0,
        mode: 'reps',
      })
    );
    await assertFails(
      instance.update({
        status: 'completed',
        actualsStorageFormat: 'slotResultsSubcollection',
        actualSlotIds: ['legacy-slot-0'],
      })
    );
  });

  it('rejects a malformed slot result payload', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      db.collection('workoutInstances').doc(INSTANCE_ID)
        .collection('slotResults').doc('legacy-slot-0').set({
        exerciseId: 'e1',
        slotOrder: 0,
        mode: 'unsupported',
      })
    );
  });

  it('prevents a typed instance from reverting to legacy list actuals', async () => {
    await seedInstance();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutInstances').doc(INSTANCE_ID)
        .update({ actualsBySlot: {} });
    });
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      db.collection('workoutInstances').doc(INSTANCE_ID).update({
        actuals: [{ exerciseId: 'e1', mode: 'reps' }],
      })
    );
  });

  it('denies a stranger from writing an athlete slot result', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('workoutInstances').doc(INSTANCE_ID)
        .collection('slotResults').doc('legacy-slot-0').set({
        exerciseId: 'e1',
        slotOrder: 0,
        mode: 'reps',
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

  it('denies athlete changes to immutable assignment and workout pins', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    const instance = db.collection('workoutInstances').doc(INSTANCE_ID);
    await assertFails(instance.update({ athleteId: STRANGER }));
    await assertFails(instance.update({
      workoutTemplateId: 'forged',
      workoutTemplateVersion: 99,
    }));
    await assertFails(instance.update({ programId: 'forged-program' }));
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

  it('denies athlete edits after completion', async () => {
    await seedInstance();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    const instance = db.collection('workoutInstances').doc(INSTANCE_ID);
    await instance.update({
      status: 'completed', rpe: 7, durationMinutes: 60,
    });
    await assertFails(instance.update({ rpe: 9 }));
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

  it('denies owner scheduling changes after completion', async () => {
    await seedInstance();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutInstances').doc(INSTANCE_ID)
        .update({ status: 'completed' });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      db.collection('workoutInstances').doc(INSTANCE_ID).update({
        scheduledDate: '2026-06-20',
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
