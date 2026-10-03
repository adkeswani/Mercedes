"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
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

test("sign-in reactivates Flutter semantics after authentication", () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, "..", "browser-canary.js"),
    "utf8",
  );
  const signInStart = source.indexOf("async function signIn({");
  const signInEnd = source.indexOf("\nasync function runIdentity(", signInStart);
  const signInSource = source.slice(signInStart, signInEnd);
  const authenticationWait = signInSource.indexOf(
    "authentication and header identity",
  );
  const semanticsActivation = signInSource.indexOf(
    "await activateFlutterSemantics",
  );

  assert.ok(authenticationWait >= 0);
  assert.ok(semanticsActivation > authenticationWait);
});

test("YouTube assertions use Flutter semantics instead of painted DOM text", () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, "..", "browser-canary.js"),
    "utf8",
  );

  assert.doesNotMatch(source, /\bstate\.value\.includes\(/);
  assert.match(
    source,
    /findByAriaLabel\(baseUrl, sessionId, "3 videos indexed"\)/,
  );
  assert.match(
    source,
    /findByAriaLabel\(baseUrl, sessionId, "Catalogue is fresh\."\)/,
  );
  assert.match(
    source,
    /"Attached YouTube video Release Canary Squat"/,
  );
  assert.match(
    source,
    /type: "wheel"/,
  );
  assert.match(source, /"trainer-exercise-youtube-reopened\.png"/);
});

test("reopened catalogue replaces the restored channel value", () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, "..", "browser-canary.js"),
    "utf8",
  );

  assert.match(source, /text: "\\uE009a\\uE000\\uE003"/);
  assert.match(source, /\{ replace: true, submit: true \}/);
  assert.match(source, /await reopenYoutubeEditor\(baseUrl, sessionId\)/);
});
