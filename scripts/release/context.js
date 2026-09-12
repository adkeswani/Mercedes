"use strict";

const path = require("node:path");
const {
  readJson,
  resolveEnvironmentProject,
  resolveProjectAlias,
  validateManifest,
} = require("./environment.js");

const REPOSITORY_ROOT = path.resolve(__dirname, "..", "..");
const MANIFEST_PATH = path.join(
  REPOSITORY_ROOT,
  "config",
  "firebase-environments.json",
);
const FIREBASE_RC_PATH = path.join(REPOSITORY_ROOT, ".firebaserc");

function loadConfiguration() {
  return {
    manifest: validateManifest(readJson(MANIFEST_PATH, "environment manifest")),
    firebaseRc: readJson(FIREBASE_RC_PATH, "Firebase aliases"),
  };
}

function loadReleaseContext({ environment, project, emulator = false }) {
  const configuration = loadConfiguration();
  return {
    root: REPOSITORY_ROOT,
    ...resolveEnvironmentProject({
      environment,
      project,
      emulator,
      ...configuration,
    }),
  };
}

function loadProjectContext(project) {
  const configuration = loadConfiguration();
  return {
    root: REPOSITORY_ROOT,
    projectId: resolveProjectAlias(
      project,
      configuration.firebaseRc,
      configuration.manifest.productionProjectId,
    ),
  };
}

module.exports = {
  FIREBASE_RC_PATH,
  MANIFEST_PATH,
  REPOSITORY_ROOT,
  loadConfiguration,
  loadProjectContext,
  loadReleaseContext,
};
