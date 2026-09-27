export type YoutubeErrorCode =
  "invalid-argument" |
  "unauthenticated" |
  "not-found" |
  "resource-exhausted" |
  "deadline-exceeded" |
  "unavailable" |
  "internal";

export class YoutubePublicError extends Error {
  constructor(
    readonly code: YoutubeErrorCode,
    message: string,
  ) {
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
  channelId: string;
  channelTitle: string;
  publishedAt: string;
  viewCount: number | null;
};

export type PublicVideoPage = {
  videos: PublicVideo[];
  nextPageToken: string | null;
};

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

export class YoutubePublicService {
  private readonly channelCache = new Map<
    string,
    {expiresAt: number; value: PublicChannel}
  >();
  private readonly pageCache = new Map<
    string,
    {expiresAt: number; value: PublicVideoPage}
  >();

  constructor(
    private readonly apiKey: string,
    private readonly fetchImpl: FetchLike = fetch,
    private readonly now: () => number = Date.now,
  ) {
    if (!apiKey) {
      throw new YoutubePublicError(
        "internal",
        "YouTube API is not configured.",
      );
    }
  }

  async resolveChannel(input: unknown): Promise<PublicChannel> {
    const reference = parseChannelReference(input);
    return this.resolveReference(reference);
  }

  async listVideos(
    channelIdValue: unknown,
    pageTokenValue: unknown,
    maxResultsValue: unknown,
  ): Promise<PublicVideoPage> {
    if (typeof channelIdValue !== "string" || !CHANNEL_ID.test(channelIdValue)) {
      throw new YoutubePublicError(
        "invalid-argument",
        "Invalid YouTube channel ID.",
      );
    }
    const pageToken = validatePageToken(pageTokenValue);
    const maxResults = validateMaxResults(maxResultsValue);
    const cacheKey = `${channelIdValue}:${pageToken ?? ""}:${maxResults}`;
    const cached = this.pageCache.get(cacheKey);
    if (cached && cached.expiresAt > this.now()) return cached.value;

    const channel = await this.resolveReference({
      kind: "id",
      value: channelIdValue,
    });
    const playlist = await this.request("playlistItems", {
      part: "contentDetails,snippet",
      playlistId: channel.uploadsPlaylistId,
      maxResults: String(maxResults),
      ...(pageToken ? {pageToken} : {}),
    });
    const playlistItems = arrayValue(playlist.items);
    const orderedIds = playlistItems
      .map((item) => objectValue(item).contentDetails)
      .map((details) => objectValue(details).videoId)
      .filter((id): id is string => typeof id === "string" && VIDEO_ID.test(id));

    let videos: PublicVideo[] = [];
    if (orderedIds.length > 0) {
      const details = await this.request("videos", {
        part: "snippet,statistics",
        id: orderedIds.join(","),
        maxResults: String(orderedIds.length),
      });
      const byId = new Map<string, PublicVideo>();
      for (const rawItem of arrayValue(details.items)) {
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
        const thumbnails = objectValue(snippet.thumbnails);
        const medium = objectValue(thumbnails.medium);
        const high = objectValue(thumbnails.high);
        const defaults = objectValue(thumbnails.default);
        const statistics = objectValue(item.statistics);
        const rawViews = statistics.viewCount;
        const viewCount = typeof rawViews === "string" &&
          /^\d+$/.test(rawViews) ?
          Number(rawViews) :
          null;
        byId.set(id, {
          id,
          title: requiredText(snippet.title, "video title"),
          thumbnailUrl: optionalText(high.url) ||
            optionalText(medium.url) ||
            optionalText(defaults.url) ||
            "",
          channelId,
          channelTitle: requiredText(snippet.channelTitle, "channel title"),
          publishedAt: new Date(publishedAt).toISOString(),
          viewCount: Number.isSafeInteger(viewCount) ? viewCount : null,
        });
      }
      videos = orderedIds
        .map((id) => byId.get(id))
        .filter((video): video is PublicVideo => video !== undefined);
    }

    const rawNextPageToken = playlist.nextPageToken;
    const nextPageToken = rawNextPageToken === undefined ?
      null :
      validatePageToken(rawNextPageToken);
    const value = {videos, nextPageToken};
    this.pageCache.set(cacheKey, {
      expiresAt: this.now() + 5 * 60 * 1000,
      value,
    });
    return value;
  }

  private async resolveReference(
    reference: ChannelReference,
  ): Promise<PublicChannel> {
    const cacheKey = `${reference.kind}:${reference.value}`;
    const cached = this.channelCache.get(cacheKey);
    if (cached && cached.expiresAt > this.now()) return cached.value;

    const lookups: Record<string, string>[] = reference.kind === "custom" ?
      [
        {forHandle: reference.value},
        {forUsername: reference.value},
      ] :
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
      });
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
    const high = objectValue(thumbnails.high);
    const defaults = objectValue(thumbnails.default);
    const channel: PublicChannel = {
      id,
      title: requiredText(snippet.title, "channel title"),
      avatarUrl: optionalText(high.url) || optionalText(defaults.url) || null,
      uploadsPlaylistId,
    };
    this.channelCache.set(cacheKey, {
      expiresAt: this.now() + 10 * 60 * 1000,
      value: channel,
    });
    this.channelCache.set(`id:${id}`, {
      expiresAt: this.now() + 10 * 60 * 1000,
      value: channel,
    });
    return channel;
  }

  private async request(
    resource: "channels" | "playlistItems" | "videos",
    parameters: Record<string, string>,
  ): Promise<Record<string, unknown>> {
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
      throw new YoutubePublicError(
        "unavailable",
        "Could not reach YouTube.",
      );
    } finally {
      clearTimeout(timeout);
    }
    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      throw mapUpstreamError(response.status, payload);
    }
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      throw new YoutubePublicError(
        "unavailable",
        "YouTube returned a malformed response.",
      );
    }
    return payload as Record<string, unknown>;
  }
}

export async function handleYoutubePublicRequest(
  data: unknown,
  uid: string | null,
  consumeRateLimit: (uid: string) => Promise<void>,
  service: YoutubePublicService,
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
  if (request.action === "resolve") {
    return {channel: await service.resolveChannel(request.channel)};
  }
  if (request.action === "videos") {
    const page = await service.listVideos(
      request.channelId,
      request.pageToken,
      request.maxResults,
    );
    return {...page};
  }
  throw new YoutubePublicError(
    "invalid-argument",
    "action must be 'resolve' or 'videos'.",
  );
}

function mapUpstreamError(status: number, payload: unknown): YoutubePublicError {
  const root = objectValue(payload);
  const error = objectValue(root.error);
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
  return Array.isArray(value) ? value.slice(0, 50) : [];
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
