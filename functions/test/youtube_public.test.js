const assert = require("node:assert/strict");
const test = require("node:test");

const {
  handleYoutubePublicRequest,
  parseChannelReference,
  validateMaxResults,
  validatePageToken,
  YoutubePublicError,
  YoutubePublicService,
} = require("../lib/youtube_public");

const channelId = "UCaaaaaaaaaaaaaaaaaaaaaa";

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {"content-type": "application/json"},
  });
}

function channelPayload() {
  return {
    items: [{
      id: channelId,
      snippet: {
        title: "Public Training",
        thumbnails: {high: {url: "https://img.example/channel.jpg"}},
      },
      contentDetails: {
        relatedPlaylists: {uploads: "UUaaaaaaaaaaaaaaaaaaaaaa"},
      },
    }],
  };
}

test("parses IDs, handles, and supported channel URLs", () => {
  assert.deepEqual(parseChannelReference(channelId), {
    kind: "id",
    value: channelId,
  });
  assert.deepEqual(parseChannelReference("@public.training"), {
    kind: "handle",
    value: "public.training",
  });
  assert.deepEqual(
    parseChannelReference("https://www.youtube.com/channel/" + channelId),
    {kind: "id", value: channelId},
  );
  assert.deepEqual(
    parseChannelReference("https://youtube.com/c/LegacyTrainer"),
    {kind: "custom", value: "LegacyTrainer"},
  );
});

test("resolves custom URLs by handle with a legacy username fallback", async () => {
  const parameters = [];
  const service = new YoutubePublicService("secret", async (url) => {
    const request = new URL(url);
    parameters.push({
      handle: request.searchParams.get("forHandle"),
      username: request.searchParams.get("forUsername"),
    });
    return parameters.length === 1 ?
      jsonResponse({items: []}) :
      jsonResponse(channelPayload());
  });
  const channel = await service.resolveChannel(
    "https://youtube.com/c/LegacyTrainer",
  );
  assert.equal(channel.id, channelId);
  assert.equal(channel.avatarUrl, null);
  assert.deepEqual(parameters, [
    {handle: "LegacyTrainer", username: null},
    {handle: null, username: "LegacyTrainer"},
  ]);
});

test("rejects arbitrary hosts, malformed references, tokens, and bounds", () => {
  for (const input of [
    "https://example.com/channel/" + channelId,
    "https://youtube.example.com/@" + "trainer",
    "not a channel",
  ]) {
    assert.throws(() => parseChannelReference(input), {
      code: "invalid-argument",
    });
  }
  assert.throws(() => validatePageToken("../secret"), {
    code: "invalid-argument",
  });
  assert.throws(() => validateMaxResults(51), {code: "invalid-argument"});
});

test("fails closed with a sanitized error when the API key is absent", () => {
  assert.throws(
    () => new YoutubePublicService(""),
    {
      code: "failed-precondition",
      message: "Public YouTube browsing is not configured.",
    },
  );
});

test("resolves handles without exposing the API key in results", async () => {
  let requestedUrl;
  const service = new YoutubePublicService("super-secret", async (url) => {
    requestedUrl = new URL(url);
    return jsonResponse(channelPayload());
  });
  const channel = await service.resolveChannel("@public.training");
  assert.equal(requestedUrl.searchParams.get("forHandle"), "public.training");
  assert.equal(requestedUrl.searchParams.get("key"), "super-secret");
  assert.equal(channel.id, channelId);
  assert.equal(JSON.stringify(channel).includes("super-secret"), false);
});

test("pages uploads and batches video details in playlist order", async () => {
  const calls = [];
  const service = new YoutubePublicService("secret", async (url) => {
    const request = new URL(url);
    calls.push(request);
    if (request.pathname.endsWith("/channels")) {
      return jsonResponse(channelPayload());
    }
    if (request.pathname.endsWith("/playlistItems")) {
      return jsonResponse({
        nextPageToken: "NEXT_token",
        items: [
          {contentDetails: {videoId: "videoId0001"}},
          {contentDetails: {videoId: "videoId0002"}},
        ],
      });
    }
    return jsonResponse({
      items: [
        {
          id: "videoId0002",
          snippet: {
            title: "Second",
            channelId,
            channelTitle: "Public Training",
            publishedAt: "2026-09-02T00:00:00Z",
            thumbnails: {medium: {url: "https://img.example/2.jpg"}},
          },
          statistics: {viewCount: "20"},
        },
        {
          id: "videoId0001",
          snippet: {
            title: "First",
            channelId,
            channelTitle: "Public Training",
            publishedAt: "2026-09-01T00:00:00Z",
            thumbnails: {default: {url: "https://img.example/1.jpg"}},
          },
          statistics: {viewCount: "10"},
        },
      ],
    });
  });

  const page = await service.listVideos(channelId, "PAGE_token", 25);
  assert.deepEqual(page.videos.map((video) => video.id), [
    "videoId0001",
    "videoId0002",
  ]);
  assert.equal(page.nextPageToken, "NEXT_token");
  assert.equal(calls[1].searchParams.get("pageToken"), "PAGE_token");
  assert.equal(calls[2].searchParams.get("id"), "videoId0001,videoId0002");
  assert.equal(calls.some((call) => call.pathname.endsWith("/search")), false);
  assert.deepEqual(page.videos.map((video) => video.thumbnailUrl), ["", ""]);
});

test("maps not found, quota, network, and malformed responses", async () => {
  const cases = [
    [
      async () => jsonResponse({items: []}),
      "not-found",
    ],
    [
      async () => jsonResponse({
        error: {errors: [{reason: "quotaExceeded"}]},
      }, 403),
      "resource-exhausted",
    ],
    [
      async () => {
        throw new Error("offline");
      },
      "unavailable",
    ],
    [
      async () => jsonResponse({items: [{id: "bad"}]}),
      "unavailable",
    ],
  ];
  for (const [fetchImpl, code] of cases) {
    const service = new YoutubePublicService("secret", fetchImpl);
    await assert.rejects(() => service.resolveChannel(channelId), {code});
  }
});

test("requires auth, applies the rate limiter, and validates actions", async () => {
  const service = new YoutubePublicService(
    "secret",
    async () => jsonResponse(channelPayload()),
  );
  let consumedBy;
  const consume = async (uid) => {
    consumedBy = uid;
  };
  await assert.rejects(
    () => handleYoutubePublicRequest(
      {action: "resolve", channel: channelId},
      null,
      consume,
      service,
    ),
    {code: "unauthenticated"},
  );
  const result = await handleYoutubePublicRequest(
    {action: "resolve", channel: channelId},
    "trainer",
    consume,
    service,
  );
  assert.equal(consumedBy, "trainer");
  assert.equal(result.channel.id, channelId);
  await assert.rejects(
    () => handleYoutubePublicRequest(
      {action: "proxy", url: "https://example.com"},
      "trainer",
      consume,
      service,
    ),
    YoutubePublicError,
  );
});
