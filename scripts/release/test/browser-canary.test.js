"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  invokeReleaseCanaryAuthBridge,
} = require("../browser-canary.js");

test("auth bridge removes credentials after invoking normal app sign-in", async () => {
  const originalFetch = global.fetch;
  let request;
  global.fetch = async (url, options) => {
    request = {
      url,
      body: JSON.parse(options.body),
    };
    return {
      ok: true,
      json: async () => ({
        value: { available: true, result: "accepted" },
      }),
    };
  };

  try {
    await invokeReleaseCanaryAuthBridge(
      "http://127.0.0.1:9515",
      "session-id",
      "release-canary-trainer@example.invalid",
      "not-a-real-password",
    );
  } finally {
    global.fetch = originalFetch;
  }

  assert.equal(
    request.url,
    "http://127.0.0.1:9515/session/session-id/execute/sync",
  );
  assert.deepEqual(request.body.args, [
    "release-canary-trainer@example.invalid",
    "not-a-real-password",
  ]);
  assert.match(
    request.body.script,
    /dispatchEvent\(new Event\("mercedes-release-canary-authenticate"\)\)/,
  );
  assert.match(
    request.body.script,
    /removeAttribute\("data-release-canary-auth-password"\)/,
  );
  assert.doesNotMatch(request.body.script, /not-a-real-password/);
});
