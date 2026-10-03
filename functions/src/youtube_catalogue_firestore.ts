import * as admin from "firebase-admin";
import {
  CatalogueManifest,
  CataloguePage,
  PublicChannel,
  YoutubeCatalogueStore,
  YoutubeCatalogueCleanupStore,
  YoutubePublicError,
  youtubeCataloguePolicy,
  youtubeQuotaDay,
  assertYoutubeBudget,
} from "./youtube_public";

export class FirestoreYoutubeCatalogueStore implements
  YoutubeCatalogueStore, YoutubeCatalogueCleanupStore {
  constructor(private readonly db: admin.firestore.Firestore) {}

  async getManifest(channelId: string): Promise<CatalogueManifest | null> {
    const snapshot = await this.manifest(channelId).get();
    return snapshot.exists ? snapshot.data() as CatalogueManifest : null;
  }

  async acquireLease(
    channel: PublicChannel,
    owner: string,
    generation: string,
    now: number,
    leaseMs: number,
  ): Promise<boolean> {
    return this.db.runTransaction(async (transaction) => {
      const reference = this.manifest(channel.id);
      const snapshot = await transaction.get(reference);
      const existing = snapshot.data() as CatalogueManifest | undefined;
      if (
        existing?.leaseOwner &&
        existing.leaseExpiresAt !== null &&
        existing.leaseExpiresAt > now
      ) {
        return false;
      }
      transaction.set(reference, {
        ...channel,
        status: "indexing",
        activeGeneration: existing?.activeGeneration ?? null,
        previousGeneration: existing?.previousGeneration ?? null,
        buildingGeneration: generation,
        pageCount: existing?.pageCount ?? 0,
        videoCount: existing?.videoCount ?? 0,
        indexedCount: 0,
        lastRefreshedAt: existing?.lastRefreshedAt ?? null,
        lastFullRefreshAt: existing?.lastFullRefreshAt ?? null,
        refreshAfter: existing?.refreshAfter ?? null,
        staleAfter: existing?.staleAfter ?? null,
        leaseOwner: owner,
        leaseExpiresAt: now + leaseMs,
        lastError: null,
        updatedAt: now,
      }, {merge: false});
      return true;
    });
  }

  async writePage(
    channelId: string,
    owner: string,
    page: CataloguePage,
    indexedCount: number,
    now: number,
  ): Promise<void> {
    if (page.videos.length > youtubeCataloguePolicy.pageSize) {
      throw new YoutubePublicError(
        "internal",
        "Catalogue page exceeds the configured page size.",
      );
    }
    await this.db.runTransaction(async (transaction) => {
      const manifest = this.manifest(channelId);
      const snapshot = await transaction.get(manifest);
      const data = snapshot.data() as CatalogueManifest | undefined;
      if (
        data?.leaseOwner !== owner ||
        data.buildingGeneration !== page.generation
      ) {
        throw new YoutubePublicError(
          "unavailable",
          "Catalogue indexing lease was lost.",
        );
      }
      const pageId =
        `${page.generation}-${String(page.pageIndex).padStart(6, "0")}`;
      transaction.set(manifest.collection("pages").doc(pageId), page);
      transaction.update(manifest, {
        indexedCount,
        leaseExpiresAt: now + youtubeCataloguePolicy.leaseMs,
        updatedAt: now,
      });
    });
  }

  async publish(
    channelId: string,
    owner: string,
    generation: string,
    pageCount: number,
    videoCount: number,
    fullRefresh: boolean,
    now: number,
  ): Promise<void> {
    await this.db.runTransaction(async (transaction) => {
      const reference = this.manifest(channelId);
      const snapshot = await transaction.get(reference);
      const data = snapshot.data() as CatalogueManifest | undefined;
      if (
        data?.leaseOwner !== owner ||
        data.buildingGeneration !== generation
      ) {
        throw new YoutubePublicError(
          "unavailable",
          "Catalogue indexing lease was lost before publication.",
        );
      }
      transaction.update(reference, {
        status: "ready",
        previousGeneration: data.activeGeneration,
        activeGeneration: generation,
        buildingGeneration: null,
        pageCount,
        videoCount,
        indexedCount: videoCount,
        lastRefreshedAt: now,
        lastFullRefreshAt: fullRefresh ? now : data.lastFullRefreshAt,
        refreshAfter: now + youtubeCataloguePolicy.refreshMs,
        staleAfter: now + youtubeCataloguePolicy.staleMs,
        leaseOwner: null,
        leaseExpiresAt: null,
        lastError: null,
        updatedAt: now,
      });
    });
  }

  async fail(
    channelId: string,
    owner: string,
    message: string,
    now: number,
  ): Promise<void> {
    await this.db.runTransaction(async (transaction) => {
      const reference = this.manifest(channelId);
      const snapshot = await transaction.get(reference);
      const data = snapshot.data() as CatalogueManifest | undefined;
      if (!data || data.leaseOwner !== owner) return;
      transaction.update(reference, {
        status: "error",
        buildingGeneration: null,
        indexedCount: data.videoCount,
        refreshAfter: now + 15 * 60 * 1000,
        leaseOwner: null,
        leaseExpiresAt: null,
        lastError: message.slice(0, 300),
        updatedAt: now,
      });
    });
  }

  async readPages(
    channelId: string,
    generation: string,
  ): Promise<CataloguePage[]> {
    const snapshot = await this.manifest(channelId)
      .collection("pages")
      .where("generation", "==", generation)
      .get();
    return snapshot.docs.map((document) => document.data() as CataloguePage);
  }

  async deleteGeneration(
    channelId: string,
    generation: string,
  ): Promise<void> {
    const snapshot = await this.manifest(channelId)
      .collection("pages")
      .where("generation", "==", generation)
      .get();
    for (let offset = 0; offset < snapshot.docs.length; offset += 400) {
      const batch = this.db.batch();
      for (const document of snapshot.docs.slice(offset, offset + 400)) {
        batch.delete(document.ref);
      }
      await batch.commit();
    }
  }

  async consumeBudget(uid: string, units: number, now: number): Promise<void> {
    const day = youtubeQuotaDay(now);
    const global = this.db.collection("_youtubeQuotaBudgets").doc(day);
    const user = global.collection("users").doc(uid);
    await this.db.runTransaction(async (transaction) => {
      const [globalSnapshot, userSnapshot] = await Promise.all([
        transaction.get(global),
        transaction.get(user),
      ]);
      const globalUsed = numberValue(globalSnapshot.data()?.units);
      const userUsed = numberValue(userSnapshot.data()?.units);
      assertYoutubeBudget(globalUsed, userUsed, units);
      transaction.set(global, {
        day,
        units: globalUsed + units,
        updatedAt: now,
      });
      transaction.set(user, {
        uid,
        day,
        units: userUsed + units,
        updatedAt: now,
      });
    });
  }

  async listExpiredCatalogues(
    cutoff: number,
    limit: number,
  ): Promise<string[]> {
    const collection = this.db.collection("youtubeChannelCatalogs");
    const refreshed = await collection
      .where("lastRefreshedAt", "<=", cutoff)
      .limit(limit)
      .get();
    const remaining = limit - refreshed.size;
    const neverPublished = remaining > 0 ?
      await collection
        .where("updatedAt", "<=", cutoff)
        .limit(Math.min(remaining * 5, 500))
        .get() :
      null;
    const ids = refreshed.docs.map((document) => document.id);
    for (const document of neverPublished?.docs ?? []) {
      if (ids.length >= limit) break;
      if (document.data().lastRefreshedAt === null) ids.push(document.id);
    }
    return ids;
  }

  async deleteCatalogue(channelId: string): Promise<void> {
    await this.db.recursiveDelete(this.manifest(channelId));
  }

  private manifest(channelId: string) {
    return this.db.collection("youtubeChannelCatalogs").doc(channelId);
  }
}

function numberValue(value: unknown): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ?
    value :
    0;
}
