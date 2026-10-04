const assert = require("node:assert/strict");
const test = require("node:test");

const {
  YoutubeCatalogueService,
  assertYoutubeBudget,
  assertYoutubeCallableRateLimit,
  cleanupExpiredYoutubeCatalogues,
  YoutubePublicError,
  youtubeCataloguePolicy,
  youtubeQuotaDay,
} = require("../lib/youtube_public");

const channel = {
  id: "UCaaaaaaaaaaaaaaaaaaaaaa",
  title: "Public Training",
  avatarUrl: null,
  uploadsPlaylistId: "UUaaaaaaaaaaaaaaaaaaaaaa",
};

function video(number, overrides = {}) {
  const id = `video${String(number).padStart(6, "0")}`;
  return {
    id,
    title: `Training ${String(number).padStart(3, "0")}`,
    thumbnailUrl: `https://i.ytimg.com/vi/${id}/hqdefault.jpg`,
    channelId: channel.id,
    channelTitle: channel.title,
    publishedAt: new Date(Date.UTC(2026, 0, number + 1)).toISOString(),
    viewCount: number,
    ...overrides,
  };
}

class MemoryStore {
  constructor() {
    this.manifests = new Map();
    this.pages = new Map();
    this.charges = new Map();
  }

  async getManifest(channelId) {
    return structuredClone(this.manifests.get(channelId) ?? null);
  }

  async acquireLease(value, owner, generation, now, leaseMs) {
    const existing = this.manifests.get(value.id);
    if (existing?.leaseOwner && existing.leaseExpiresAt > now) return false;
    this.manifests.set(value.id, {
      ...value,
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
    });
    return true;
  }

  async writePage(channelId, owner, page, indexedCount, now) {
    assert.ok(page.videos.length <= youtubeCataloguePolicy.pageSize);
    const manifest = this.manifests.get(channelId);
    if (manifest.leaseOwner !== owner ||
        manifest.buildingGeneration !== page.generation) {
      throw new YoutubePublicError("unavailable", "lease lost");
    }
    this.pages.set(`${channelId}:${page.generation}:${page.pageIndex}`, {
      ...structuredClone(page),
    });
    Object.assign(manifest, {
      indexedCount,
      leaseExpiresAt: now + youtubeCataloguePolicy.leaseMs,
      updatedAt: now,
    });
  }

  async publish(
    channelId,
    owner,
    generation,
    pageCount,
    videoCount,
    fullRefresh,
    now,
  ) {
    const manifest = this.manifests.get(channelId);
    if (manifest.leaseOwner !== owner ||
        manifest.buildingGeneration !== generation) {
      throw new YoutubePublicError("unavailable", "lease lost");
    }
    Object.assign(manifest, {
      status: "ready",
      previousGeneration: manifest.activeGeneration,
      activeGeneration: generation,
      buildingGeneration: null,
      pageCount,
      videoCount,
      indexedCount: videoCount,
      lastRefreshedAt: now,
      lastFullRefreshAt: fullRefresh ? now : manifest.lastFullRefreshAt,
      refreshAfter: now + youtubeCataloguePolicy.refreshMs,
      staleAfter: now + youtubeCataloguePolicy.staleMs,
      leaseOwner: null,
      leaseExpiresAt: null,
      lastError: null,
      updatedAt: now,
    });
  }

  async fail(channelId, owner, message, now) {
    const manifest = this.manifests.get(channelId);
    if (manifest?.leaseOwner !== owner) return;
    Object.assign(manifest, {
      status: "error",
      buildingGeneration: null,
      indexedCount: manifest.videoCount,
      refreshAfter: now + 900000,
      leaseOwner: null,
      leaseExpiresAt: null,
      lastError: message,
      updatedAt: now,
    });
  }

  async readPages(channelId, generation) {
    return [...this.pages.entries()]
      .filter(([key]) => key.startsWith(`${channelId}:${generation}:`))
      .map(([, value]) => structuredClone(value));
  }

  async deleteGeneration(channelId, generation) {
    for (const key of this.pages.keys()) {
      if (key.startsWith(`${channelId}:${generation}:`)) {
        this.pages.delete(key);
      }
    }
  }

  async consumeBudget(uid, units) {
    const used = this.charges.get(uid) ?? 0;
    if (used + units > 200) {
      throw new YoutubePublicError("resource-exhausted", "budget exhausted");
    }
    this.charges.set(uid, used + units);
  }

  seed(videos, now, options = {}) {
    const generation = options.generation ?? "active";
    this.manifests.set(channel.id, {
      ...channel,
      status: options.status ?? "ready",
      activeGeneration: generation,
      previousGeneration: options.previousGeneration ?? null,
      buildingGeneration: options.buildingGeneration ?? null,
      pageCount: Math.ceil(videos.length / 50),
      videoCount: videos.length,
      indexedCount: options.indexedCount ?? videos.length,
      lastRefreshedAt: options.lastRefreshedAt ?? now,
      lastFullRefreshAt: options.lastFullRefreshAt ?? now,
      refreshAfter: options.refreshAfter ?? now + 1000,
      staleAfter: options.staleAfter ?? now + 1000,
      leaseOwner: options.leaseOwner ?? null,
      leaseExpiresAt: options.leaseExpiresAt ?? null,
      lastError: options.lastError ?? null,
      updatedAt: now,
    });
    for (let index = 0; index < videos.length; index += 50) {
      this.pages.set(`${channel.id}:${generation}:${index / 50}`, {
        generation,
        pageIndex: index / 50,
        videos: videos.slice(index, index + 50),
      });
    }
  }
}

class FakeUpstream {
  constructor(pages) {
    this.pages = pages;
    this.listCalls = 0;
    this.failure = null;
  }

  async resolveChannel() {
    return channel;
  }

  async listUploadPage(_channel, token, consume) {
    await consume(1);
    if (this.failure) throw this.failure;
    const index = token ? Number(token) : 0;
    this.listCalls += 1;
    return {
      videos: this.pages[index] ?? [],
      nextPageToken: index + 1 < this.pages.length ? String(index + 1) : null,
    };
  }
}

test("indexes complete catalogues into bounded deterministic pages", async () => {
  const now = Date.UTC(2026, 9, 1);
  const all = Array.from({length: 120}, (_, index) => video(index));
  const upstream = new FakeUpstream([
    all.slice(0, 50),
    all.slice(50, 100),
    all.slice(100),
  ]);
  const store = new MemoryStore();
  const service = new YoutubeCatalogueService(
    upstream,
    store,
    () => now,
    () => "fixed",
  );

  const resolved = await service.resolve("@trainer", "trainer");
  const manifest = await store.getManifest(channel.id);
  const pages = await store.readPages(channel.id, manifest.activeGeneration);

  assert.equal(resolved.catalogue.complete, true);
  assert.equal(manifest.videoCount, 120);
  assert.deepEqual(pages.map((page) => page.videos.length).sort(), [20, 50, 50]);
  assert.equal(upstream.listCalls, 3);
  assert.equal(store.charges.get("trainer"), 3);
});

test("searches and sorts the complete cache before response pagination", async () => {
  const now = Date.UTC(2026, 9, 1);
  const store = new MemoryStore();
  const all = Array.from({length: 80}, (_, index) => video(index));
  all[70] = video(70, {title: "Needle Result", viewCount: 9999});
  store.seed(all, now);
  const service = new YoutubeCatalogueService(
    new FakeUpstream([]),
    store,
    () => now,
  );

  const searched = await service.videos({
    channelId: channel.id,
    query: "needle",
    sort: "title",
    maxResults: 10,
  }, "trainer");
  const first = await service.videos({
    channelId: channel.id,
    sort: "viewCount",
    maxResults: 25,
  }, "trainer");
  const second = await service.videos({
    channelId: channel.id,
    sort: "viewCount",
    maxResults: 25,
    pageToken: first.nextPageToken,
  }, "trainer");

  assert.deepEqual(searched.videos.map((item) => item.title), ["Needle Result"]);
  assert.equal(first.videos[0].title, "Needle Result");
  assert.equal(new Set([...first.videos, ...second.videos].map((item) => item.id)).size, 50);
  assert.equal(first.complete, true);
  assert.equal(first.stale, false);
  await assert.rejects(
    () => service.videos({
      channelId: channel.id,
      sort: "title",
      maxResults: 25,
      pageToken: first.nextPageToken,
    }, "trainer"),
    {code: "invalid-argument"},
  );
});

test("serializes old cached records with a deterministic thumbnail", async () => {
  const now = Date.UTC(2026, 9, 1);
  const store = new MemoryStore();
  store.seed([video(1, {thumbnailUrl: ""})], now);
  const service = new YoutubeCatalogueService(
    new FakeUpstream([]),
    store,
    () => now,
  );

  const result = await service.videos({
    channelId: channel.id,
    maxResults: 10,
  }, "trainer");

  assert.equal(
    result.videos[0].thumbnailUrl,
    `https://i.ytimg.com/vi/${video(1).id}/mqdefault.jpg`,
  );
  assert.equal(result.videos[0].thumbnailWidth, 320);
  assert.equal(result.videos[0].thumbnailHeight, 180);
});

test("keeps the active generation visible until publication", async () => {
  const now = Date.UTC(2026, 9, 1);
  const store = new MemoryStore();
  store.seed([video(1)], now, {
    status: "indexing",
    buildingGeneration: "building",
    indexedCount: 1,
    leaseOwner: "other",
    leaseExpiresAt: now + 1000,
  });
  await store.writePage(
    channel.id,
    "other",
    {generation: "building", pageIndex: 0, videos: [video(2)]},
    1,
    now,
  );
  const service = new YoutubeCatalogueService(
    new FakeUpstream([]),
    store,
    () => now,
  );

  const result = await service.videos({
    channelId: channel.id,
    maxResults: 10,
  }, "trainer");

  assert.deepEqual(result.videos.map((item) => item.id), [video(1).id]);
  assert.equal(result.status, "indexing");
  assert.equal(result.complete, false);
  assert.equal(result.indexedCount, 1);
});

test("deduplicates a concurrent refresh with the active lease", async () => {
  const now = Date.UTC(2026, 9, 1);
  const store = new MemoryStore();
  store.seed([video(1)], now, {
    status: "indexing",
    buildingGeneration: "building",
    refreshAfter: now - 1,
    leaseOwner: "other",
    leaseExpiresAt: now + 1000,
  });
  const upstream = new FakeUpstream([[video(2)]]);
  const service = new YoutubeCatalogueService(upstream, store, () => now);

  const result = await service.videos({
    channelId: channel.id,
    maxResults: 10,
  }, "trainer");

  assert.equal(upstream.listCalls, 0);
  assert.deepEqual(result.videos.map((item) => item.id), [video(1).id]);
  assert.equal(result.complete, false);
});

test("incremental refresh stops at overlap and retains the prior tail", async () => {
  const now = Date.UTC(2026, 9, 1);
  const store = new MemoryStore();
  store.seed([video(2), video(1), video(0)], now, {
    refreshAfter: now - 1,
  });
  const upstream = new FakeUpstream([[video(3), video(2)]]);
  const service = new YoutubeCatalogueService(
    upstream,
    store,
    () => now,
    () => "incremental",
  );

  const result = await service.videos({
    channelId: channel.id,
    sort: "newest",
    maxResults: 10,
  }, "trainer");

  assert.equal(upstream.listCalls, 1);
  assert.deepEqual(result.videos.map((item) => item.id), [
    video(3).id,
    video(2).id,
    video(1).id,
    video(0).id,
  ]);
  const manifest = await store.getManifest(channel.id);
  assert.equal(manifest.previousGeneration, "active");
  assert.equal((await store.readPages(channel.id, "active")).length, 1);
});

test("full revalidation removes videos deleted or made private", async () => {
  const now = Date.UTC(2026, 9, 1);
  const store = new MemoryStore();
  store.seed([video(2), video(1), video(0)], now, {
    refreshAfter: now - 1,
    lastFullRefreshAt: now - youtubeCataloguePolicy.fullRefreshMs - 1,
  });
  const upstream = new FakeUpstream([[video(2), video(0)]]);
  const service = new YoutubeCatalogueService(
    upstream,
    store,
    () => now,
    () => "full",
  );

  const result = await service.videos({
    channelId: channel.id,
    maxResults: 10,
  }, "trainer");

  assert.deepEqual(result.videos.map((item) => item.id), [
    video(2).id,
    video(0).id,
  ]);
  assert.equal(result.videoCount, 2);
});

test("returns an explicit stale cache when refresh fails", async () => {
  const now = Date.UTC(2026, 9, 1);
  const store = new MemoryStore();
  store.seed([video(1)], now, {
    refreshAfter: now - 1,
    staleAfter: now - 1,
  });

  const upstream = new FakeUpstream([]);
  upstream.failure = new YoutubePublicError(
    "resource-exhausted",
    "quota exhausted",
  );
  const service = new YoutubeCatalogueService(
    upstream,
    store,
    () => now,
    () => "failed",
  );

  const result = await service.videos({
    channelId: channel.id,
    maxResults: 10,
  }, "trainer");

  assert.deepEqual(result.videos.map((item) => item.id), [video(1).id]);
  assert.equal(result.status, "error");
  assert.equal(result.stale, true);
  assert.equal(result.complete, true);
});

test("does not return a success-shaped result when initial indexing fails",
  async () => {
    const now = Date.UTC(2026, 9, 1);
    const store = new MemoryStore();
    const upstream = new FakeUpstream([]);
    upstream.failure = new YoutubePublicError("unavailable", "offline");
    const service = new YoutubeCatalogueService(
      upstream,
      store,
      () => now,
      () => "failed-initial",
    );

    await assert.rejects(
      () => service.resolve("@trainer", "trainer"),
      {code: "unavailable"},
    );
    await assert.rejects(
      () => service.videos({
        channelId: channel.id,
        maxResults: 10,
      }, "trainer"),
      {
        code: "unavailable",
        message: "Catalogue indexing has not completed.",
      },
    );
  });

test("fails closed when a user budget is exhausted", async () => {
  const now = Date.UTC(2026, 9, 1);
  const store = new MemoryStore();
  store.charges.set("trainer", 200);
  const service = new YoutubeCatalogueService(
    new FakeUpstream([[video(1)]]),
    store,
    () => now,
  );

  await assert.rejects(
    () => service.resolve("@trainer", "trainer"),
    {code: "resource-exhausted"},
  );
});

test("enforces shared and per-user daily quota budgets", () => {
  assert.doesNotThrow(() => assertYoutubeBudget(7999, 199, 1));
  assert.throws(
    () => assertYoutubeBudget(8000, 10, 1),
    {
      code: "resource-exhausted",
      message: "The shared daily YouTube quota budget is exhausted.",
    },
  );
  assert.throws(
    () => assertYoutubeBudget(10, 200, 1),
    {
      code: "resource-exhausted",
      message: "Your daily YouTube catalogue budget is exhausted.",
    },
  );
});

test("allows a realistic multi-channel exercise-creation session under the callable rate limit", () => {
  // Creating ~10 exercises each browsing a distinct channel (resolve + load
  // + a couple of searches/pagination) is comfortably under the raised
  // per-hour callable limit, even though it would have tripped the old
  // pre-cache limit of 30.
  const callsForTenExercises = 10 * 8;
  assert.ok(callsForTenExercises < youtubeCataloguePolicy.callableRateLimitPerHour);
  assert.doesNotThrow(
    () => assertYoutubeCallableRateLimit(callsForTenExercises),
  );
});

test("still fails closed once the callable rate limit is reached", () => {
  assert.doesNotThrow(
    () => assertYoutubeCallableRateLimit(
      youtubeCataloguePolicy.callableRateLimitPerHour - 1,
    ),
  );
  assert.throws(
    () => assertYoutubeCallableRateLimit(
      youtubeCataloguePolicy.callableRateLimitPerHour,
    ),
    {
      code: "resource-exhausted",
      message: "Public YouTube browsing is limited to " +
        `${youtubeCataloguePolicy.callableRateLimitPerHour} requests per hour.`,
    },
  );
});

test("cleans only the bounded set of catalogues expired by policy", async () => {
  const deleted = [];
  const store = {
    async listExpiredCatalogues(cutoff, limit) {
      assert.equal(
        cutoff,
        Date.UTC(2026, 9, 31) - youtubeCataloguePolicy.retentionMs,
      );
      assert.equal(limit, 2);
      return ["expired-a", "expired-b"];
    },
    async deleteCatalogue(channelId) {
      deleted.push(channelId);
    },
  };

  const count = await cleanupExpiredYoutubeCatalogues(
    store,
    Date.UTC(2026, 9, 31),
    2,
  );

  assert.equal(count, 2);
  assert.deepEqual(deleted, ["expired-a", "expired-b"]);
  await assert.rejects(
    () => cleanupExpiredYoutubeCatalogues(store, Date.now(), 501),
    {code: "invalid-argument"},
  );
});

test("accounts daily quota in the YouTube Pacific reset window", () => {
  assert.equal(
    youtubeQuotaDay(Date.parse("2026-10-03T06:59:59Z")),
    "2026-10-02",
  );
  assert.equal(
    youtubeQuotaDay(Date.parse("2026-10-03T07:00:00Z")),
    "2026-10-03",
  );
});
