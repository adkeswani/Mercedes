import {auth, runWith} from "firebase-functions/v1";
import {logger} from "firebase-functions";
import {defineSecret} from "firebase-functions/params";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {propagateProgramVersion} from "./subscription_propagation";
import {
  handleYoutubePublicRequest,
  YoutubePublicError,
  YoutubePublicService,
} from "./youtube_public";

admin.initializeApp();

const db = admin.firestore();
const youtubeApiKey = defineSecret("YOUTUBE_API_KEY");
let youtubeService: YoutubePublicService | undefined;

function publicYoutubeService(): YoutubePublicService {
  youtubeService ??= new YoutubePublicService(youtubeApiKey.value());
  return youtubeService;
}

async function consumeYoutubeRateLimit(uid: string): Promise<void> {
  const reference = db.collection("_youtubePublicRateLimits").doc(uid);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const now = Date.now();
    const data = snapshot.data();
    const windowStart = data?.windowStart?.toMillis?.() as number | undefined;
    const activeWindow = windowStart !== undefined &&
      now - windowStart < 60 * 60 * 1000;
    const count = activeWindow && typeof data?.count === "number" ?
      data.count :
      0;
    if (count >= 30) {
      throw new YoutubePublicError(
        "resource-exhausted",
        "Public YouTube browsing is limited to 30 requests per hour.",
      );
    }
    transaction.set(reference, {
      windowStart: activeWindow ?
        data?.windowStart :
        admin.firestore.Timestamp.fromMillis(now),
      count: count + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

export const youtubePublicLibrary = onCall(
  {
    secrets: [youtubeApiKey],
    timeoutSeconds: 15,
    memory: "256MiB",
    maxInstances: 10,
  },
  async (request) => {
    try {
      return await handleYoutubePublicRequest(
        request.data,
        request.auth?.uid ?? null,
        consumeYoutubeRateLimit,
        publicYoutubeService(),
      );
    } catch (error) {
      if (error instanceof YoutubePublicError) {
        throw new HttpsError(error.code, error.message);
      }
      logger.error("Public YouTube request failed", {
        uid: request.auth?.uid,
        error,
      });
      throw new HttpsError(
        "internal",
        "Public YouTube request failed.",
      );
    }
  },
);

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

export const onProgramVersionPublished = runWith({
  failurePolicy: true,
  timeoutSeconds: 540,
}).firestore
  .document("programs/{programId}/programVersions/{versionNumber}")
  .onCreate(async (_snapshot, context) => {
    const versionNumber = Number(context.params.versionNumber);
    await propagateProgramVersion(
      db,
      context.params.programId,
      versionNumber,
      context.eventId,
    );
  });
