import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";

export async function repairWorkoutLocalDay(
  db: admin.firestore.Firestore,
  uid: string,
  input: unknown,
  now: Date = new Date(),
): Promise<void> {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to manage workouts.");
  }
  if (!input || typeof input !== "object") {
    throw new HttpsError("invalid-argument", "A workout and UTC offset are required.");
  }
  const {instanceId, utcOffsetMinutes} = input as Record<string, unknown>;
  if (typeof instanceId !== "string" || !instanceId ||
      instanceId.includes("/") ||
      typeof utcOffsetMinutes !== "number" ||
      !Number.isInteger(utcOffsetMinutes) ||
      utcOffsetMinutes < -720 || utcOffsetMinutes > 840) {
    throw new HttpsError("invalid-argument", "Invalid workout or UTC offset.");
  }
  // Only the timezone is supplied by the device; the date comes from our clock.
  const localToday = new Date(
    now.getTime() + utcOffsetMinutes * 60_000,
  ).toISOString().slice(0, 10);
  const ref = db.collection("workoutInstances").doc(instanceId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Workout not found.");
    }
    const workout = snapshot.data()!;
    const athleteId = workout.athleteId;
    const trainerId = workout.programOwnerId ?? workout.assignedBy;
    if (athleteId !== uid && trainerId !== uid) {
      throw new HttpsError("permission-denied", "You do not own this workout.");
    }
    if (athleteId !== uid) {
      const relationship = await transaction.get(
        db.collection("trainerClientRelationships").doc(`${uid}_${athleteId}`),
      );
      if (relationship.data()?.status !== "active" ||
          relationship.data()?.trainerId !== uid ||
          relationship.data()?.athleteId !== athleteId ||
          relationship.data()?.deletedAt != null) {
        throw new HttpsError("permission-denied", "An active client relationship is required.");
      }
    }
    if (workout.status !== "scheduled" ||
        workout.scheduledDate !== localToday ||
        !(workout.scheduledAt instanceof admin.firestore.Timestamp)) {
      throw new HttpsError("failed-precondition", "Only today's scheduled workouts can be repaired.");
    }
    if (workout.scheduledAt.toMillis() + 86_400_000 > now.getTime()) {
      return;
    }
    const localStart = new Date(
      Date.parse(`${localToday}T00:00:00.000Z`) -
      utcOffsetMinutes * 60_000,
    );
    transaction.update(ref, {
      scheduledAt: admin.firestore.Timestamp.fromDate(localStart),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}
