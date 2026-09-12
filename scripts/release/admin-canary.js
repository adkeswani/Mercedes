"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {
  CANARY_IDS,
  OWNERSHIP_FIELDS,
  REFERENCE_FIELDS,
  assertCanaryEmail,
  assertCanaryMutation,
  assertCanaryToken,
  buildCanaryFixture,
  expectedMutationPaths,
} = require("./canary-fixture.js");
const {
  validateAppUrl,
  validateCredentialDocument,
  validateLoopbackEmulatorHost,
} = require("./environment.js");

function localIsoDate(now = new Date()) {
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function requireCanaryCredentials({ emulator, environment = process.env }) {
  const trainerEmail = environment.RELEASE_CANARY_TRAINER_EMAIL ||
    (emulator ? "release-canary-trainer@example.invalid" : "");
  const athleteEmail = environment.RELEASE_CANARY_ATHLETE_EMAIL ||
    (emulator ? "release-canary-athlete@example.invalid" : "");
  const trainerPassword = environment.RELEASE_CANARY_TRAINER_PASSWORD ||
    (emulator ? "release-canary-local-trainer" : "");
  const athletePassword = environment.RELEASE_CANARY_ATHLETE_PASSWORD ||
    (emulator ? "release-canary-local-athlete" : "");
  assertCanaryEmail(trainerEmail, "RELEASE_CANARY_TRAINER_EMAIL");
  assertCanaryEmail(athleteEmail, "RELEASE_CANARY_ATHLETE_EMAIL");
  if (trainerPassword.length < 12 || athletePassword.length < 12) {
    throw new Error("Release canary passwords must contain at least 12 characters");
  }
  return { trainerEmail, athleteEmail, trainerPassword, athletePassword };
}

function configureEmulators(environment = process.env) {
  environment.FIRESTORE_EMULATOR_HOST = validateLoopbackEmulatorHost(
    environment.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080",
    "FIRESTORE_EMULATOR_HOST",
  );
  environment.FIREBASE_AUTH_EMULATOR_HOST = validateLoopbackEmulatorHost(
    environment.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099",
    "FIREBASE_AUTH_EMULATOR_HOST",
  );
}

function loadAdmin(root) {
  const modulePath = path.join(
    root,
    "functions",
    "node_modules",
    "firebase-admin",
  );
  if (!fs.existsSync(modulePath)) {
    throw new Error(
      "firebase-admin is unavailable; restore the existing functions dependencies first",
    );
  }
  return require(modulePath);
}

function loadServiceAccountCredentials(
  environment,
  projectId,
  readFile = fs.readFileSync,
) {
  const credentialsPath = environment.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credentialsPath) {
    throw new Error(
      "GOOGLE_APPLICATION_CREDENTIALS is required for deployed targets",
    );
  }
  let credentials;
  try {
    credentials = JSON.parse(readFile(credentialsPath, "utf8"));
  } catch {
    throw new Error("Unable to read GOOGLE_APPLICATION_CREDENTIALS");
  }
  validateCredentialDocument(credentials, projectId);
  return credentials;
}

function createAdminContext({
  root,
  projectId,
  hostingUrl,
  appUrl,
  emulator,
  processEnvironment = process.env,
}) {
  validateAppUrl(appUrl, projectId, { emulator, hostingUrl });
  const admin = loadAdmin(root);
  let options;
  if (emulator) {
    configureEmulators(processEnvironment);
    options = { projectId };
  } else {
    loadServiceAccountCredentials(processEnvironment, projectId);
    options = {
      projectId,
      credential: admin.credential.applicationDefault(),
    };
  }
  const app = admin.initializeApp(
    options,
    `release-canary-${process.pid}-${Date.now()}`,
  );
  return {
    admin,
    app,
    auth: app.auth(),
    firestore: app.firestore(),
  };
}

function isMissingAuthUser(error) {
  return error?.code === "auth/user-not-found";
}

async function inspectAuthUser(auth, expected) {
  assertCanaryToken(expected.uid, "Auth UID");
  assertCanaryEmail(expected.email, "Auth email");
  let byUid;
  try {
    byUid = await auth.getUser(expected.uid);
  } catch (error) {
    if (!isMissingAuthUser(error)) {
      throw error;
    }
  }
  if (byUid && byUid.email?.toLowerCase() !== expected.email) {
    throw new Error(`Canary UID '${expected.uid}' is owned by another email`);
  }
  if (!byUid) {
    try {
      const byEmail = await auth.getUserByEmail(expected.email);
      if (byEmail.uid !== expected.uid) {
        throw new Error(`Canary email is owned by another UID`);
      }
      byUid = byEmail;
    } catch (error) {
      if (!isMissingAuthUser(error)) {
        throw error;
      }
    }
  }
  return byUid;
}

async function ensureAuthUser(auth, expected, password, existingUser) {
  const properties = {
    email: expected.email,
    password,
    displayName: expected.displayName,
    disabled: false,
    emailVerified: true,
  };
  if (existingUser) {
    await auth.updateUser(expected.uid, properties);
    return "updated";
  }
  await auth.createUser({ uid: expected.uid, ...properties });
  return "created";
}

function materializeTimestamps(value, admin, key = "") {
  if (Array.isArray(value)) {
    return value.map((item) => materializeTimestamps(item, admin));
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([childKey, childValue]) => [
        childKey,
        materializeTimestamps(childValue, admin, childKey),
      ]),
    );
  }
  if (typeof value === "string" &&
      key.endsWith("At") &&
      /^\d{4}-\d{2}-\d{2}T/.test(value)) {
    return admin.firestore.Timestamp.fromDate(new Date(value));
  }
  return value;
}

function assertExistingDocument(pathName, existing, expected) {
  assertCanaryMutation(pathName, existing);
  const guardedKeys = new Set([
    ...OWNERSHIP_FIELDS,
    ...REFERENCE_FIELDS,
    "email",
  ]);
  function compare(actual, intended) {
    if (Array.isArray(actual)) {
      actual.forEach((item, index) => compare(item, intended?.[index]));
      return;
    }
    if (!actual || typeof actual !== "object") {
      return;
    }
    for (const [key, value] of Object.entries(actual)) {
      if (guardedKeys.has(key) && value !== intended?.[key]) {
        throw new Error(
          `Existing '${pathName}' has unexpected protected field '${key}'`,
        );
      }
      compare(value, intended?.[key]);
    }
  }
  compare(existing, expected);
}

async function seedFixture(context, fixture, passwords) {
  const existingAuthUsers = new Map();
  for (const user of fixture.authUsers) {
    existingAuthUsers.set(
      user.uid,
      await inspectAuthUser(context.auth, user),
    );
  }
  const batch = context.firestore.batch();
  for (const document of fixture.documents) {
    assertCanaryMutation(document.path, document.data);
    const reference = context.firestore.doc(document.path);
    const existing = await reference.get();
    if (existing.exists) {
      assertExistingDocument(document.path, existing.data(), document.data);
    }
    batch.set(
      reference,
      materializeTimestamps(document.data, context.admin),
      { merge: false },
    );
  }
  await batch.commit();
  const states = [];
  for (const user of fixture.authUsers) {
    const password = user.uid === CANARY_IDS.trainer
      ? passwords.trainerPassword
      : passwords.athletePassword;
    states.push(await ensureAuthUser(
      context.auth,
      user,
      password,
      existingAuthUsers.get(user.uid),
    ));
  }
  return {
    authCreated: states.filter((state) => state === "created").length,
    authUpdated: states.filter((state) => state === "updated").length,
    documentsWritten: fixture.documents.length,
  };
}

async function cleanupFixture(context, fixture) {
  const paths = expectedMutationPaths();
  const existingDocuments = [];
  let documentsDeleted = 0;
  for (const pathName of paths) {
    const expected = fixture.documents.find((item) => item.path === pathName);
    if (!expected) {
      throw new Error(`Missing expected fixture definition for '${pathName}'`);
    }
    assertCanaryMutation(pathName, expected.data);
    const reference = context.firestore.doc(pathName);
    const existing = await reference.get();
    if (!existing.exists) {
      continue;
    }
    assertExistingDocument(pathName, existing.data(), expected.data);
    existingDocuments.push(reference);
    documentsDeleted += 1;
  }
  const existingUsers = [];
  for (const expected of fixture.authUsers) {
    assertCanaryToken(expected.uid, "Auth UID");
    let user;
    try {
      user = await context.auth.getUser(expected.uid);
    } catch (error) {
      if (isMissingAuthUser(error)) {
        continue;
      }
      throw error;
    }
    if (user.email?.toLowerCase() !== expected.email) {
      throw new Error(`Refusing to delete Auth UID '${expected.uid}': email mismatch`);
    }
    existingUsers.push(user);
  }

  const batch = context.firestore.batch();
  for (const reference of existingDocuments) {
    batch.delete(reference);
  }
  await batch.commit();
  for (const user of existingUsers) {
    await context.auth.deleteUser(user.uid);
  }
  return { documentsDeleted, usersDeleted: existingUsers.length };
}

module.exports = {
  cleanupFixture,
  configureEmulators,
  createAdminContext,
  localIsoDate,
  loadServiceAccountCredentials,
  materializeTimestamps,
  requireCanaryCredentials,
  seedFixture,
};
