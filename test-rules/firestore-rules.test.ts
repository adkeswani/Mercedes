import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { setLogLevel } from 'firebase/firestore';

setLogLevel('error');

const RULES_PATH = resolve(__dirname, '..', 'firestore.rules');

// Test user IDs
const OWNER = 'owner-uid';
const ATHLETE = 'athlete-uid';
const STRANGER = 'stranger-uid';
const PROGRAM_ID = 'program-1';
const FOLDER_ID = 'folder-1';
const ENROLLMENT_ID = `${PROGRAM_ID}_${ATHLETE}`;

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

/** Seed a standard program + enrollment for cross-collection rule tests. */
async function seedProgramWithEnrollment() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
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
  it('allows any signed-in user to read', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('exerciseTemplates').doc('e1').set({
        name: 'Squat', createdBy: OWNER,
      });
    });
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertSucceeds(db.collection('exerciseTemplates').doc('e1').get());
  });

  it('allows creating with own createdBy', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      db.collection('exerciseTemplates').doc('e2').set({
        name: 'Bench', createdBy: OWNER,
      })
    );
  });

  it('denies creating with someone else as createdBy', async () => {
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('exerciseTemplates').doc('e3').set({
        name: 'Fake', createdBy: OWNER,
      })
    );
  });

  it('denies update by non-creator', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('exerciseTemplates').doc('e4').set({
        name: 'Deadlift', createdBy: OWNER,
      });
    });
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('exerciseTemplates').doc('e4').update({ name: 'Hacked' })
    );
  });
});

// ─── Workout Templates ───

describe('workoutTemplates', () => {
  it('allows any signed-in user to read (athletes need exercises)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutTemplates').doc('w1').set({
        name: 'Full Body', createdBy: OWNER,
      });
    });
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertSucceeds(db.collection('workoutTemplates').doc('w1').get());
  });

  it('allows reading workout template versions by any signed-in user', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('workoutTemplates').doc('w1').set({
        name: 'Full Body', createdBy: OWNER,
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

  it('denies update by non-creator', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('workoutTemplates').doc('w2').set({
        name: 'Upper', createdBy: OWNER,
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
        name: 'Lower', createdBy: OWNER,
      });
    });
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('workoutTemplates').doc('w3')
        .collection('workoutTemplateVersions').doc('1')
        .set({ exercises: [] })
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
        ownerId: OWNER, name: 'New', type: 'personal',
      })
    );
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
        ownerId: OWNER, name: 'New Folder',
      })
    );
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
      db.collection('programFolders').doc(FOLDER_ID).update({ name: 'Power' })
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

  it('denies non-owner from deleting folder', async () => {
    await seedFolder();
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      db.collection('programFolders').doc(FOLDER_ID).delete()
    );
  });
});

// ─── Enrollments ───

describe('enrollments', () => {
  it('allows program owner to create enrollment', async () => {
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
        athleteId: ATHLETE,
        assignedBy: OWNER,
        status: 'scheduled',
      })
    );
  });

  it('denies athlete from creating workout instance for others program', async () => {
    await seedProgramWithEnrollment();
    const db = testEnv.authenticatedContext(ATHLETE).firestore();
    await assertFails(
      db.collection('workoutInstances').doc('inst-fake').set({
        programId: PROGRAM_ID,
        athleteId: ATHLETE,
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
