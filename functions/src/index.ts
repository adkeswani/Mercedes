import {auth, runWith} from "firebase-functions/v1";
import {logger} from "firebase-functions";
import {defineSecret} from "firebase-functions/params";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {propagateProgramVersion} from "./subscription_propagation";
import {
  assertYoutubeCallableRateLimit,
  handleYoutubePublicRequest,
  cleanupExpiredYoutubeCatalogues,
  YoutubeCatalogueService,
  YoutubePublicError,
  YoutubePublicService,
} from "./youtube_public";
import {
  FirestoreYoutubeCatalogueStore,
} from "./youtube_catalogue_firestore";

admin.initializeApp();

const db = admin.firestore();
const youtubeApiKey = defineSecret("YOUTUBE_API_KEY");
let youtubeService: YoutubePublicService | undefined;
const youtubeCatalogueStore = new FirestoreYoutubeCatalogueStore(db);

function publicYoutubeService(): YoutubePublicService {
  youtubeService ??= new YoutubePublicService(youtubeApiKey.value());
  return youtubeService;
}

function publicYoutubeCatalogueService(): YoutubeCatalogueService {
  return new YoutubeCatalogueService(
    publicYoutubeService(),
    youtubeCatalogueStore,
  );
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
    // This call-count limiter predates the shared Firestore catalogue cache
    // (every callable invocation used to mean a live YouTube API hit). Most
    // invocations are now served from the cache for free, so the real quota
    // protection is the unit-based budget in youtube_public.ts; this stays
    // only as a loose backstop against a runaway/abusive client.
    assertYoutubeCallableRateLimit(count);
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
    region: "us-central1",
    timeoutSeconds: 300,
    memory: "512MiB",
    maxInstances: 10,
    cors: true,
    enforceAppCheck: false,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Sign in to browse public YouTube channels.",
      );
    }
    try {
      return await handleYoutubePublicRequest(
        request.data,
        request.auth.uid,
        consumeYoutubeRateLimit,
        publicYoutubeCatalogueService(),
      );
    } catch (error) {
      if (error instanceof YoutubePublicError) {
        throw new HttpsError(error.code, error.message);
      }
      logger.error("Public YouTube request failed", {
        uid: request.auth?.uid,
        errorName: error instanceof Error ? error.name : "UnknownError",
      });
      throw new HttpsError(
        "internal",
        "Public YouTube request failed.",
      );
    }
  },
);

export const cleanupYoutubeCatalogues = onSchedule(
  {
    schedule: "17 3 * * *",
    timeZone: "America/Los_Angeles",
    region: "us-central1",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const deleted = await cleanupExpiredYoutubeCatalogues(
      youtubeCatalogueStore,
      Date.now(),
    );
    logger.info("Expired YouTube catalogues cleaned", {deleted});
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
