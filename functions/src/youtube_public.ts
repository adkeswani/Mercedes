export type YoutubeErrorCode =
  "invalid-argument" |
  "unauthenticated" |
  "failed-precondition" |
  "not-found" |
  "resource-exhausted" |
  "deadline-exceeded" |
  "unavailable" |
  "internal";

export class YoutubePublicError extends Error {
  constructor(readonly code: YoutubeErrorCode, message: string) {
    super(message);
  }
}

type FetchLike = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

type ChannelReference = {
  kind: "id" | "handle" | "username" | "custom";
  value: string;
};

export type PublicChannel = {
  id: string;
  title: string;
  avatarUrl: string | null;
  uploadsPlaylistId: string;
};

export type PublicVideo = {
  id: string;
  title: string;
  thumbnailUrl: string;
  thumbnailWidth?: number;
  thumbnailHeight?: number;
  channelId: string;
  channelTitle: string;
  publishedAt: string;
  viewCount: number | null;
};

export type YoutubeSort = "newest" | "oldest" | "title" | "viewCount";
export type CatalogueStatus = "indexing" | "ready" | "error";

export type CatalogueManifest = PublicChannel & {
  status: CatalogueStatus;
  activeGeneration: string | null;
  previousGeneration: string | null;
  buildingGeneration: string | null;
  pageCount: number;
  videoCount: number;
  indexedCount: number;
  lastRefreshedAt: number | null;
  lastFullRefreshAt: number | null;
  refreshAfter: number | null;
  staleAfter: number | null;
  leaseOwner: string | null;
  leaseExpiresAt: number | null;
  lastError: string | null;
  updatedAt: number;
};

export type CataloguePage = {
  generation: string;
  pageIndex: number;
  videos: PublicVideo[];
};

export type CatalogueQueryResult = {
  videos: PublicVideo[];
  nextPageToken: string | null;
  status: CatalogueStatus;
  indexedCount: number;
  videoCount: number;
  complete: boolean;
  stale: boolean;
  lastRefreshedAt: string | null;
  refreshAfter: string | null;
};

export interface YoutubeCatalogueStore {
  getManifest(channelId: string): Promise<CatalogueManifest | null>;
  acquireLease(
    channel: PublicChannel,
    owner: string,
    generation: string,
    now: number,
    leaseMs: number,
  ): Promise<boolean>;
  writePage(
    channelId: string,
    owner: string,
    page: CataloguePage,
    indexedCount: number,
    now: number,
  ): Promise<void>;
  publish(
    channelId: string,
    owner: string,
    generation: string,
    pageCount: number,
    videoCount: number,
    fullRefresh: boolean,
    now: number,
  ): Promise<void>;
  fail(
    channelId: string,
    owner: string,
    message: string,
    now: number,
  ): Promise<void>;
  readPages(channelId: string, generation: string): Promise<CataloguePage[]>;
  deleteGeneration(channelId: string, generation: string): Promise<void>;
  consumeBudget(uid: string, units: number, now: number): Promise<void>;
}

export interface YoutubeCatalogueCleanupStore {
  listExpiredCatalogues(cutoff: number, limit: number): Promise<string[]>;
  deleteCatalogue(channelId: string): Promise<void>;
}

const CHANNEL_ID = /^UC[A-Za-z0-9_-]{22}$/;
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
const HANDLE = /^[A-Za-z0-9._-]{3,30}$/;
const USERNAME = /^[A-Za-z0-9._-]{1,100}$/;
const PAGE_TOKEN = /^[A-Za-z0-9_-]{1,512}$/;
const YOUTUBE_HOSTS = new Set([
  "youtube.com",
  "www.youtube.com",
  "m.youtube.com",
]);
const PAGE_SIZE = 50;
const LEASE_MS = 2 * 60 * 1000;
const REFRESH_MS = 6 * 60 * 60 * 1000;
const STALE_MS = 24 * 60 * 60 * 1000;
const FULL_REFRESH_MS = 25 * 24 * 60 * 60 * 1000;
const RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
const GLOBAL_DAILY_BUDGET = 8000;
const USER_DAILY_BUDGET = 200;
// Loose per-UID backstop against a runaway/abusive client hammering the
// callable. This predates the shared Firestore catalogue cache, when every
// invocation meant a live YouTube API hit; most invocations are now served
// from the cache for free, so the unit-based budgets above are the real
// quota guardrail and this count no longer approximates actual quota usage.
const CALLABLE_RATE_LIMIT_PER_HOUR = 300;

export async function cleanupExpiredYoutubeCatalogues(
  store: YoutubeCatalogueCleanupStore,
  now: number,
  limit = 100,
): Promise<number> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 500) {
    throw new YoutubePublicError(
      "invalid-argument",
      "Cleanup limit must be between 1 and 500.",
    );
  }

  const channelIds = await store.listExpiredCatalogues(
    now - RETENTION_MS,
    limit,
  );
  for (const channelId of channelIds) {
    await store.deleteCatalogue(channelId);
  }
  return channelIds.length;
}

export function youtubeQuotaDay(now: number): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Los_Angeles",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(now));
  const value = (type: string) =>
    parts.find((part) => part.type === type)?.value ?? "";
  return `${value("year")}-${value("month")}-${value("day")}`;
}

export function assertYoutubeBudget(
  globalUsed: number,
  userUsed: number,
  units: number,
): void {
  if (
    ![globalUsed, userUsed, units].every(Number.isSafeInteger) ||
    globalUsed < 0 ||
    userUsed < 0 ||
    units < 1 ||
    units > 2
  ) {
    throw new YoutubePublicError("internal", "Invalid quota budget charge.");
  }
  if (globalUsed + units > GLOBAL_DAILY_BUDGET) {
    throw new YoutubePublicError(
      "resource-exhausted",
      "The shared daily YouTube quota budget is exhausted.",
    );
  }
  if (userUsed + units > USER_DAILY_BUDGET) {
    throw new YoutubePublicError(
      "resource-exhausted",
      "Your daily YouTube catalogue budget is exhausted.",
    );
  }
}

export function assertYoutubeCallableRateLimit(count: number): void {
  if (!Number.isSafeInteger(count) || count < 0) {
    throw new YoutubePublicError("internal", "Invalid rate limit count.");
  }
  if (count >= CALLABLE_RATE_LIMIT_PER_HOUR) {
    throw new YoutubePublicError(
      "resource-exhausted",
      `Public YouTube browsing is limited to ` +
        `${CALLABLE_RATE_LIMIT_PER_HOUR} requests per hour.`,
    );
  }
}

export function parseChannelReference(input: unknown): ChannelReference {
  if (typeof input !== "string" || input.length > 300) {
    throw new YoutubePublicError(
      "invalid-argument",
      "Channel reference must be a string of at most 300 characters.",
    );
  }
  const value = input.trim();
  if (CHANNEL_ID.test(value)) return {kind: "id", value};
  if (value.startsWith("@") && HANDLE.test(value.slice(1))) {
    return {kind: "handle", value: value.slice(1)};
  }
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new YoutubePublicError(
      "invalid-argument",
      "Use a YouTube channel URL, @handle, custom URL, or channel ID.",
    );
  }
  if (
    !["https:", "http:"].includes(url.protocol) ||
    !YOUTUBE_HOSTS.has(url.hostname.toLowerCase()) ||
    url.username ||
    url.password
  ) {
    throw new YoutubePublicError(
      "invalid-argument",
      "Only public youtube.com channel URLs are supported.",
    );
  }
  const segments = url.pathname.split("/").filter(Boolean);
  if (
    segments.length === 2 &&
    segments[0] === "channel" &&
    CHANNEL_ID.test(segments[1])
  ) {
    return {kind: "id", value: segments[1]};
  }
  if (
    segments.length === 1 &&
    segments[0].startsWith("@") &&
    HANDLE.test(segments[0].slice(1))
  ) {
    return {kind: "handle", value: segments[0].slice(1)};
  }
  if (
    segments.length === 2 &&
    (segments[0] === "user" || segments[0] === "c") &&
    USERNAME.test(segments[1])
  ) {
    return {
      kind: segments[0] === "c" ? "custom" : "username",
      value: segments[1],
    };
  }
  throw new YoutubePublicError(
    "invalid-argument",
    "The URL is not a supported YouTube channel URL.",
  );
}

export function validatePageToken(value: unknown): string | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string" || !PAGE_TOKEN.test(value)) {
    throw new YoutubePublicError("invalid-argument", "Invalid page token.");
  }
  return value;
}

export function validateMaxResults(value: unknown): number {
  if (value === undefined || value === null) return 25;
  if (!Number.isInteger(value) || (value as number) < 1 || (value as number) > 50) {
    throw new YoutubePublicError(
      "invalid-argument",
      "maxResults must be an integer between 1 and 50.",
    );
  }
  return value as number;
}

function validateQuery(value: unknown): string {
  if (value === undefined || value === null) return "";
  if (typeof value !== "string" || value.length > 100) {
    throw new YoutubePublicError(
      "invalid-argument",
      "query must be a string of at most 100 characters.",
    );
  }
  return value.trim().toLocaleLowerCase();
}

function validateSort(value: unknown): YoutubeSort {
  if (value === undefined || value === null) return "newest";
  if (
    value === "newest" ||
    value === "oldest" ||
    value === "title" ||
    value === "viewCount"
  ) {
    return value;
  }
  throw new YoutubePublicError(
    "invalid-argument",
    "sort must be newest, oldest, title, or viewCount.",
  );
}

export class YoutubePublicService {
  private readonly channelCache = new Map<
    string,
    {expiresAt: number; value: PublicChannel}
  >();

  constructor(
    private readonly apiKey: string,
    private readonly fetchImpl: FetchLike = fetch,
    private readonly now: () => number = Date.now,
  ) {
    if (!apiKey) {
      throw new YoutubePublicError(
        "failed-precondition",
        "Public YouTube browsing is not configured.",
      );
    }
  }

  async resolveChannel(
    input: unknown,
    consume: (units: number) => Promise<void> = async () => {},
  ): Promise<PublicChannel> {
    const reference = parseChannelReference(input);
    const cacheKey = `${reference.kind}:${reference.value}`;
    const cached = this.channelCache.get(cacheKey);
    if (cached && cached.expiresAt > this.now()) return cached.value;
    const lookups: Record<string, string>[] = reference.kind === "custom" ?
      [{forHandle: reference.value}, {forUsername: reference.value}] :
      [reference.kind === "id" ?
        {id: reference.value} :
        reference.kind === "handle" ?
          {forHandle: reference.value} :
          {forUsername: reference.value}];
    let first: unknown;
    for (const lookup of lookups) {
      const response = await this.request("channels", {
        part: "snippet,contentDetails",
        maxResults: "1",
        ...lookup,
      }, consume);
      first = arrayValue(response.items)[0];
      if (first) break;
    }
    if (!first) {
      throw new YoutubePublicError(
        "not-found",
        "Public YouTube channel was not found.",
      );
    }
    const item = objectValue(first);
    const id = stringValue(item.id);
    const snippet = objectValue(item.snippet);
    const contentDetails = objectValue(item.contentDetails);
    const relatedPlaylists = objectValue(contentDetails.relatedPlaylists);
    const uploadsPlaylistId = stringValue(relatedPlaylists.uploads);
    if (!CHANNEL_ID.test(id) || !uploadsPlaylistId) {
      throw new YoutubePublicError(
        "unavailable",
        "YouTube returned malformed channel metadata.",
      );
    }
    const thumbnails = objectValue(snippet.thumbnails);
    const channel: PublicChannel = {
      id,
      title: requiredText(snippet.title, "channel title"),
      avatarUrl: youtubeImageUrl(objectValue(thumbnails.high).url, true) ||
        youtubeImageUrl(objectValue(thumbnails.default).url, true) ||
        null,
      uploadsPlaylistId,
    };
    for (const key of [cacheKey, `id:${id}`]) {
      this.channelCache.set(key, {
        expiresAt: this.now() + 10 * 60 * 1000,
        value: channel,
      });
    }
    return channel;
  }

  async listUploadPage(
    channel: PublicChannel,
    pageToken: string | null,
    consume: (units: number) => Promise<void> = async () => {},
  ): Promise<{videos: PublicVideo[]; nextPageToken: string | null}> {
    const playlist = await this.request("playlistItems", {
      part: "contentDetails",
      playlistId: channel.uploadsPlaylistId,
      maxResults: String(PAGE_SIZE),
      ...(pageToken ? {pageToken} : {}),
    }, consume);
    const orderedIds = arrayValue(playlist.items)
      .map((item) => objectValue(objectValue(item).contentDetails).videoId)
      .filter((id): id is string => typeof id === "string" && VIDEO_ID.test(id));
    const videos = orderedIds.length === 0 ?
      [] :
      await this.videoDetails(orderedIds, consume);
    const byId = new Map(videos.map((video) => [video.id, video]));
    return {
      videos: orderedIds
        .map((id) => byId.get(id))
        .filter((video): video is PublicVideo => video !== undefined),
      nextPageToken: validatePageToken(playlist.nextPageToken),
    };
  }

  async listVideos(
    channelIdValue: unknown,
    pageTokenValue: unknown,
    maxResultsValue: unknown,
  ): Promise<{videos: PublicVideo[]; nextPageToken: string | null}> {
    if (typeof channelIdValue !== "string" || !CHANNEL_ID.test(channelIdValue)) {
      throw new YoutubePublicError("invalid-argument", "Invalid YouTube channel ID.");
    }
    const channel = await this.resolveChannel(channelIdValue);
    const page = await this.listUploadPage(
      channel,
      validatePageToken(pageTokenValue),
    );
    const maxResults = validateMaxResults(maxResultsValue);
    return {
      videos: page.videos.slice(0, maxResults),
      nextPageToken: page.nextPageToken,
    };
  }

  private async videoDetails(
    orderedIds: string[],
    consume: (units: number) => Promise<void>,
  ): Promise<PublicVideo[]> {
    const details = await this.request("videos", {
      part: "snippet,statistics",
      id: orderedIds.join(","),
      maxResults: String(orderedIds.length),
    }, consume);
    return arrayValue(details.items).map((rawItem) => {
      const item = objectValue(rawItem);
      const id = stringValue(item.id);
      const snippet = objectValue(item.snippet);
      const channelId = stringValue(snippet.channelId);
      const publishedAt = stringValue(snippet.publishedAt);
      if (
        !VIDEO_ID.test(id) ||
        !CHANNEL_ID.test(channelId) ||
        Number.isNaN(Date.parse(publishedAt))
      ) {
        throw new YoutubePublicError(
          "unavailable",
          "YouTube returned malformed video metadata.",
        );
      }
      const thumbnail = selectYoutubeThumbnail(snippet.thumbnails, id);
      const rawViews = objectValue(item.statistics).viewCount;
      const viewCount = typeof rawViews === "string" && /^\d+$/.test(rawViews) ?
        Number(rawViews) :
        null;
      return {
        id,
        title: requiredText(snippet.title, "video title"),
        thumbnailUrl: thumbnail.url,
        thumbnailWidth: thumbnail.width,
        thumbnailHeight: thumbnail.height,
        channelId,
        channelTitle: requiredText(snippet.channelTitle, "channel title"),
        publishedAt: new Date(publishedAt).toISOString(),
        viewCount: Number.isSafeInteger(viewCount) ? viewCount : null,
      };
    });
  }

  private async request(
    resource: "channels" | "playlistItems" | "videos",
    parameters: Record<string, string>,
    consume: (units: number) => Promise<void>,
  ): Promise<Record<string, unknown>> {
    await consume(1);
    const url = new URL(`https://www.googleapis.com/youtube/v3/${resource}`);
    for (const [key, value] of Object.entries(parameters)) {
      url.searchParams.set(key, value);
    }
    url.searchParams.set("key", this.apiKey);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    let response: Response;
    try {
      response = await this.fetchImpl(url, {signal: controller.signal});
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") {
        throw new YoutubePublicError(
          "deadline-exceeded",
          "YouTube did not respond in time.",
        );
      }
      throw new YoutubePublicError("unavailable", "Could not reach YouTube.");
    } finally {
      clearTimeout(timeout);
    }
    const payload = await response.json().catch(() => null);
    if (!response.ok) throw mapUpstreamError(response.status, payload);
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      throw new YoutubePublicError(
        "unavailable",
        "YouTube returned a malformed response.",
      );
    }
    return payload as Record<string, unknown>;
  }
}

export class YoutubeCatalogueService {
  constructor(
    private readonly upstream: YoutubePublicService,
    private readonly store: YoutubeCatalogueStore,
    private readonly now: () => number = Date.now,
    private readonly randomId: () => string =
      () => Math.random().toString(36).slice(2, 14),
  ) {}

  async resolve(input: unknown, uid: string): Promise<{
    channel: PublicChannel;
    catalogue: CatalogueQueryResult;
  }> {
    const consume = (units: number) =>
      this.store.consumeBudget(uid, units, this.now());
    const channel = await this.upstream.resolveChannel(input, consume);
    await this.refreshIfNeeded(channel, uid, consume);
    return {
      channel,
      catalogue: await this.query(channel.id, "", "newest", 1, null),
    };
  }

  async videos(
    request: Record<string, unknown>,
    uid: string,
  ): Promise<CatalogueQueryResult> {
    const channelId = request.channelId;
    if (typeof channelId !== "string" || !CHANNEL_ID.test(channelId)) {
      throw new YoutubePublicError("invalid-argument", "Invalid YouTube channel ID.");
    }
    const query = validateQuery(request.query);
    const sort = validateSort(request.sort);
    const maxResults = validateMaxResults(request.maxResults);
    const token = validatePageToken(request.pageToken);
    const consume = (units: number) =>
      this.store.consumeBudget(uid, units, this.now());
    let manifest = await this.store.getManifest(channelId);
    if (!manifest || manifest.refreshAfter === null ||
      manifest.refreshAfter <= this.now()) {
      const channel = await this.upstream.resolveChannel(channelId, consume);
      await this.refreshIfNeeded(channel, uid, consume);
      manifest = await this.store.getManifest(channelId);
    }
    if (!manifest) {
      throw new YoutubePublicError("unavailable", "Catalogue is not available.");
    }
    return this.query(channelId, query, sort, maxResults, token);
  }

  private async refreshIfNeeded(
    channel: PublicChannel,
    uid: string,
    consume: (units: number) => Promise<void>,
  ): Promise<void> {
    const before = await this.store.getManifest(channel.id);
    if (before?.refreshAfter !== null &&
      before?.refreshAfter !== undefined &&
      before.refreshAfter > this.now()) {
      return;
    }
    const owner = `${uid}:${this.randomId()}`;
    const generation = `${this.now()}-${this.randomId()}`;
    const acquired = await this.store.acquireLease(
      channel,
      owner,
      generation,
      this.now(),
      LEASE_MS,
    );
    if (!acquired) return;
    const oldGeneration = before?.activeGeneration ?? null;
    try {
      if (
        before?.buildingGeneration &&
        before.buildingGeneration !== generation
      ) {
        await this.store.deleteGeneration(
          channel.id,
          before.buildingGeneration,
        );
      }
      if (
        before?.previousGeneration &&
        before.previousGeneration !== generation
      ) {
        await this.store.deleteGeneration(
          channel.id,
          before.previousGeneration,
        );
      }
      const oldVideos = oldGeneration ?
        flatten(await this.store.readPages(channel.id, oldGeneration)) :
        [];
      const oldIds = new Set(oldVideos.map((video) => video.id));
      const fullRefresh = !oldGeneration ||
        !before?.lastFullRefreshAt ||
        this.now() - before.lastFullRefreshAt >= FULL_REFRESH_MS;
      const fresh: PublicVideo[] = [];
      let pageToken: string | null = null;
      let overlap = false;
      let uploadPageIndex = 0;
      do {
        const page = await this.upstream.listUploadPage(
          channel,
          pageToken,
          consume,
        );
        for (const video of page.videos) {
          if (oldIds.has(video.id)) overlap = true;
          fresh.push(video);
        }
        pageToken = page.nextPageToken;
        if (page.videos.length > 0) {
          await this.store.writePage(
            channel.id,
            owner,
            {
              generation,
              pageIndex: uploadPageIndex,
              videos: page.videos,
            },
            fresh.length,
            this.now(),
          );
        }
        uploadPageIndex += 1;
      } while (pageToken && (fullRefresh || !overlap));

      const merged = deduplicate(fullRefresh ?
        fresh :
        [...fresh, ...oldVideos]);
      await this.store.deleteGeneration(channel.id, generation);
      for (let index = 0; index < merged.length; index += PAGE_SIZE) {
        await this.store.writePage(
          channel.id,
          owner,
          {
            generation,
            pageIndex: index / PAGE_SIZE,
            videos: merged.slice(index, index + PAGE_SIZE),
          },
          Math.min(index + PAGE_SIZE, merged.length),
          this.now(),
        );
      }
      const pageCount = Math.ceil(merged.length / PAGE_SIZE);
      await this.store.publish(
        channel.id,
        owner,
        generation,
        pageCount,
        merged.length,
        fullRefresh,
        this.now(),
      );
    } catch (error) {
      await this.store.deleteGeneration(channel.id, generation);
      await this.store.fail(
        channel.id,
        owner,
        publicErrorMessage(error),
        this.now(),
      );
      if (!oldGeneration) throw error;
    }
  }

  private async query(
    channelId: string,
    query: string,
    sort: YoutubeSort,
    maxResults: number,
    token: string | null,
  ): Promise<CatalogueQueryResult> {
    const manifest = await this.store.getManifest(channelId);
    if (!manifest) {
      throw new YoutubePublicError("not-found", "Catalogue was not found.");
    }
    const generation = manifest.activeGeneration ?? manifest.buildingGeneration;
    if (!generation) {
      throw new YoutubePublicError(
        "unavailable",
        "Catalogue indexing has not completed.",
      );
    }
    const videos = flatten(await this.store.readPages(channelId, generation));
    const filtered = videos.filter((video) =>
      !query ||
      video.title.toLocaleLowerCase().includes(query) ||
      video.channelTitle.toLocaleLowerCase().includes(query)
    );
    filtered.sort(videoComparator(sort));
    const offset = token ?
      decodeCursor(token, generation, query, sort) :
      0;
    if (offset > filtered.length) {
      throw new YoutubePublicError("invalid-argument", "Invalid page token.");
    }
    const page = filtered
      .slice(offset, offset + maxResults)
      .map(normalizeCachedVideoThumbnail);
    const nextOffset = offset + page.length;
    return {
      videos: page,
      nextPageToken: nextOffset < filtered.length ?
        encodeCursor(generation, nextOffset, query, sort) :
        null,
      status: manifest.status,
      indexedCount: manifest.indexedCount,
      videoCount: manifest.videoCount,
      complete: manifest.status !== "indexing",
      stale: manifest.status === "error" ||
        manifest.staleAfter === null ||
        manifest.staleAfter <= this.now(),
      lastRefreshedAt: isoOrNull(manifest.lastRefreshedAt),
      refreshAfter: isoOrNull(manifest.refreshAfter),
    };
  }
}

export async function handleYoutubePublicRequest(
  data: unknown,
  uid: string | null,
  consumeRateLimit: (uid: string) => Promise<void>,
  service: YoutubeCatalogueService | YoutubePublicService,
): Promise<Record<string, unknown>> {
  if (!uid) {
    throw new YoutubePublicError(
      "unauthenticated",
      "Sign in to browse public YouTube channels.",
    );
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new YoutubePublicError("invalid-argument", "Invalid request.");
  }
  await consumeRateLimit(uid);
  const request = data as Record<string, unknown>;
  if (service instanceof YoutubeCatalogueService) {
    if (request.action === "resolve") return service.resolve(request.channel, uid);
    if (request.action === "videos") return service.videos(request, uid);
  } else {
    if (request.action === "resolve") {
      return {channel: await service.resolveChannel(request.channel)};
    }
    if (request.action === "videos") {
      return service.listVideos(
        request.channelId,
        request.pageToken,
        request.maxResults,
      );
    }
  }
  throw new YoutubePublicError(
    "invalid-argument",
    "action must be 'resolve' or 'videos'.",
  );
}

function videoComparator(sort: YoutubeSort) {
  return (left: PublicVideo, right: PublicVideo): number => {
    const tie = left.id.localeCompare(right.id);
    switch (sort) {
    case "oldest":
      return left.publishedAt.localeCompare(right.publishedAt) || tie;
    case "title":
      return left.title.localeCompare(right.title, undefined, {
        sensitivity: "base",
      }) || tie;
    case "viewCount":
      return (right.viewCount ?? -1) - (left.viewCount ?? -1) || tie;
    case "newest":
      return right.publishedAt.localeCompare(left.publishedAt) || tie;
    }
  };
}

function deduplicate(videos: PublicVideo[]): PublicVideo[] {
  const result: PublicVideo[] = [];
  const seen = new Set<string>();
  for (const video of videos) {
    if (!seen.has(video.id)) {
      seen.add(video.id);
      result.push(video);
    }
  }
  return result;
}

function flatten(pages: CataloguePage[]): PublicVideo[] {
  return pages
    .slice()
    .sort((left, right) => left.pageIndex - right.pageIndex)
    .flatMap((page) => page.videos);
}

function encodeCursor(
  generation: string,
  offset: number,
  query: string,
  sort: YoutubeSort,
): string {
  return Buffer.from(JSON.stringify({
    generation,
    offset,
    query,
    sort,
  }), "utf8").toString("base64url");
}

function decodeCursor(
  token: string,
  generation: string,
  query: string,
  sort: YoutubeSort,
): number {
  let decoded: unknown;
  try {
    decoded = JSON.parse(Buffer.from(token, "base64url").toString("utf8"));
  } catch {
    throw new YoutubePublicError("invalid-argument", "Invalid page token.");
  }
  const cursor = objectValue(decoded);
  const offset = cursor.offset;
  if (
    cursor.generation !== generation ||
    cursor.query !== query ||
    cursor.sort !== sort ||
    !Number.isSafeInteger(offset) ||
    (offset as number) < 0
  ) {
    throw new YoutubePublicError("invalid-argument", "Invalid page token.");
  }
  return offset as number;
}

function isoOrNull(value: number | null): string | null {
  return value === null ? null : new Date(value).toISOString();
}

function publicErrorMessage(error: unknown): string {
  return error instanceof YoutubePublicError ?
    error.message :
    "YouTube catalogue refresh failed.";
}

function mapUpstreamError(status: number, payload: unknown): YoutubePublicError {
  const error = objectValue(objectValue(payload).error);
  const reasons = arrayValue(error.errors)
    .map((item) => optionalText(objectValue(item).reason))
    .filter(Boolean);
  if (
    status === 429 ||
    reasons.some((reason) =>
      ["quotaExceeded", "dailyLimitExceeded", "rateLimitExceeded"]
        .includes(reason)
    )
  ) {
    return new YoutubePublicError(
      "resource-exhausted",
      "YouTube quota is currently exhausted.",
    );
  }
  if (status === 404) {
    return new YoutubePublicError(
      "not-found",
      "Public YouTube channel was not found.",
    );
  }
  return new YoutubePublicError(
    "unavailable",
    "YouTube could not complete the request.",
  );
}

function objectValue(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> :
    {};
}

function arrayValue(value: unknown): unknown[] {
  return Array.isArray(value) ? value.slice(0, PAGE_SIZE) : [];
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function requiredText(value: unknown, label: string): string {
  const text = optionalText(value);
  if (!text) {
    throw new YoutubePublicError(
      "unavailable",
      `YouTube returned a malformed ${label}.`,
    );
  }
  return text;
}

function optionalText(value: unknown): string {
  return typeof value === "string" ? value.trim().slice(0, 500) : "";
}

function youtubeImageUrl(value: unknown, allowAvatar = false): string {
  const text = optionalText(value);
  if (!text) return "";
  let url: URL;
  try {
    url = new URL(text);
  } catch {
    return "";
  }
  const host = url.hostname.toLowerCase();
  if (
    url.protocol !== "https:" ||
    (host !== "i.ytimg.com" &&
      !(allowAvatar && (host === "yt3.ggpht.com" ||
        host.endsWith(".googleusercontent.com"))))
  ) {
    return "";
  }
  return url.toString();
}

export function selectYoutubeThumbnail(
  value: unknown,
  videoId: string,
): {url: string; width?: number; height?: number} {
  const thumbnails = objectValue(value);
  for (const quality of ["maxres", "standard", "high", "medium", "default"]) {
    const candidate = objectValue(thumbnails[quality]);
    const url = youtubeImageUrl(candidate.url);
    if (!url) continue;
    const width = positiveInteger(candidate.width);
    const height = positiveInteger(candidate.height);
    return {
      url,
      ...(width === undefined ? {} : {width}),
      ...(height === undefined ? {} : {height}),
    };
  }
  return {
    url: VIDEO_ID.test(videoId) ?
      `https://i.ytimg.com/vi/${videoId}/mqdefault.jpg` :
      "",
    width: 320,
    height: 180,
  };
}

function normalizeCachedVideoThumbnail(video: PublicVideo): PublicVideo {
  const url = youtubeImageUrl(video.thumbnailUrl);
  if (url) return video;
  return {
    ...video,
    thumbnailUrl: VIDEO_ID.test(video.id) ?
      `https://i.ytimg.com/vi/${video.id}/mqdefault.jpg` :
      "",
    thumbnailWidth: 320,
    thumbnailHeight: 180,
  };
}

function positiveInteger(value: unknown): number | undefined {
  return typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value > 0 ?
    value :
    undefined;
}

export const youtubeCataloguePolicy = {
  pageSize: PAGE_SIZE,
  leaseMs: LEASE_MS,
  refreshMs: REFRESH_MS,
  staleMs: STALE_MS,
  fullRefreshMs: FULL_REFRESH_MS,
  retentionMs: RETENTION_MS,
  globalDailyBudget: GLOBAL_DAILY_BUDGET,
  userDailyBudget: USER_DAILY_BUDGET,
  callableRateLimitPerHour: CALLABLE_RATE_LIMIT_PER_HOUR,
};
