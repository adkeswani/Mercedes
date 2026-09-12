"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  requireProductionOptIn,
  resolveEnvironmentProject,
  validateAppUrl,
  validateCredentialDocument,
  validateManifest,
} = require("../environment.js");

const root = path.resolve(__dirname, "..", "..", "..");
const manifest = JSON.parse(
  fs.readFileSync(
    path.join(root, "config", "firebase-environments.json"),
    "utf8",
  ),
);
const firebaseRc = JSON.parse(
  fs.readFileSync(path.join(root, ".firebaserc"), "utf8"),
);

test("repository manifest is explicit and has no dangerous default alias", () => {
  assert.equal(validateManifest(manifest), manifest);
  assert.deepEqual(Object.keys(manifest.environments), [
    "dev",
    "staging",
    "prod",
  ]);
  assert.equal(manifest.environments.dev.projectId, null);
  assert.equal(manifest.environments.dev.hostingUrl, null);
  assert.equal(manifest.environments.dev.alias, "dev");
  assert.equal(manifest.environments.staging.projectId, null);
  assert.equal(manifest.environments.staging.hostingUrl, null);
  assert.equal(manifest.environments.staging.alias, "staging");
  assert.equal(manifest.environments.prod.projectId, "mercedes-app-11ce2");
  assert.equal(
    manifest.environments.prod.hostingUrl,
    "https://mercedes-app-11ce2.web.app",
  );
  assert.equal(manifest.environments.prod.alias, "prod");
  assert.equal(Object.hasOwn(firebaseRc.projects, "default"), false);
});

test("project resolution matches aliases and fails closed when unprovisioned", () => {
  const production = resolveEnvironmentProject({
    environment: "prod",
    project: "prod",
    manifest,
    firebaseRc,
  });
  assert.deepEqual(production, {
    environment: "prod",
    projectId: "mercedes-app-11ce2",
    alias: "prod",
    hostingUrl: "https://mercedes-app-11ce2.web.app",
    production: true,
  });
  assert.throws(
    () => resolveEnvironmentProject({
      environment: "staging",
      project: "staging-project-123",
      manifest,
      firebaseRc,
    }),
    /not provisioned/,
  );
  assert.throws(
    () => resolveEnvironmentProject({
      environment: "dev",
      project: "mercedes-app-11ce2",
      manifest,
      firebaseRc,
      emulator: true,
    }),
    /cannot target production/,
  );
  assert.throws(
    () => resolveEnvironmentProject({
      environment: "prod",
      project: "default",
      manifest,
      firebaseRc: {
        projects: { default: "mercedes-app-11ce2" },
      },
    }),
    /default.*forbidden/,
  );
});

test("production mutation requires a separate explicit opt-in", () => {
  const selection = {
    environment: "prod",
    projectId: "mercedes-app-11ce2",
    production: true,
  };
  assert.throws(
    () => requireProductionOptIn(selection, false),
    /explicit --allow-production/,
  );
  assert.doesNotThrow(() => requireProductionOptIn(selection, true));
});

test("App URL and credential project must match the selected target", () => {
  assert.equal(
    validateAppUrl(
      "https://mercedes-app-11ce2.web.app/release?release-canary=1",
      "mercedes-app-11ce2",
    ).hostname,
    "mercedes-app-11ce2.web.app",
  );
  assert.throws(
    () => validateAppUrl(
      "https://other-project.web.app",
      "mercedes-app-11ce2",
    ),
    /does not match/,
  );
  assert.doesNotThrow(() =>
    validateCredentialDocument(
      { type: "service_account", project_id: "mercedes-app-11ce2" },
      "mercedes-app-11ce2",
    ));
  assert.throws(
    () => validateCredentialDocument(
      { type: "service_account", project_id: "other-project" },
      "mercedes-app-11ce2",
    ),
    /does not match/,
  );
  assert.doesNotThrow(() =>
    validateAppUrl("http://127.0.0.1:5000", "demo-mercedes", {
      emulator: true,
    }));
  assert.throws(
    () => validateAppUrl("http://192.0.2.1:5000", "demo-mercedes", {
      emulator: true,
    }),
    /loopback/,
  );
});
