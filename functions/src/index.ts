import {auth} from "firebase-functions/v1";
import {logger} from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();

/**
 * Triggered when a new user is created in Firebase Auth.
 * Creates the initial `users/{uid}` Firestore document with
 * profile data from the auth record.
 *
 * - Username is null until the user completes onboarding.
 * - Uses create-only semantics: if the doc already exists
 *   (e.g. retry / duplicate trigger), it logs and exits
 *   without overwriting.
 */
export const onUserCreated = auth.user().onCreate(
  async (user: admin.auth.UserRecord) => {
    const {uid, displayName, email, photoURL} = user;

    const userData = {
      uid,
      displayName: displayName || "New User",
      username: null,
      email: email || "",
      photoUrl: photoURL || null,
      discoverable: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: "system",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: "system",
      deletedAt: null,
      deletedBy: null,
    };

    const userRef = db.collection("users").doc(uid);

    try {
      await userRef.create(userData);
      logger.info(`Created user doc for ${uid}`, {uid});
    } catch (error: unknown) {
      if (
        error instanceof Error &&
        "code" in error &&
        (error as {code: number}).code === 6
      ) {
        // ALREADY_EXISTS — doc was already created (duplicate trigger)
        logger.warn(
          `User doc already exists for ${uid}, skipping.`,
          {uid},
        );
        return;
      }
      logger.error(
        `Failed to create user doc for ${uid}`,
        {uid, error},
      );
      throw error;
    }
  },
);
