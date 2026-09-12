"use strict";

const fs = require("node:fs");

const ENVIRONMENT_NAMES = Object.freeze(["dev", "staging", "prod"]);
const FIREBASE_PROJECT_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;

function readJson(path, label) {
  try {
    return JSON.parse(fs.readFileSync(path, "utf8"));
  } catch (error) {
    throw new Error(`Unable to read ${label} at ${path}: ${error.message}`);
  }
}

function validateManifest(manifest) {
  if (!manifest || manifest.schemaVersion !== 1) {
    throw new Error("Firebase environment manifest schemaVersion must be 1");
  }
  if (!FIREBASE_PROJECT_PATTERN.test(manifest.productionProjectId || "")) {
    throw new Error("Manifest productionProjectId is missing or invalid");
  }
  const environments = manifest.environments;
  if (!environments || typeof environments !== "object") {
    throw new Error("Manifest environments object is required");
  }
  const unknownEnvironments = Object.keys(environments)
    .filter((name) => !ENVIRONMENT_NAMES.includes(name));
  if (unknownEnvironments.length > 0) {
    throw new Error(
      `Manifest has unsupported environments: ${unknownEnvironments.join(", ")}`,
    );
  }
  const seenAliases = new Set();
  for (const name of ENVIRONMENT_NAMES) {
    const entry = environments[name];
    if (!entry) {
      throw new Error(`Manifest environment '${name}' is missing or invalid`);
    }
    if (entry.projectId !== null &&
        !FIREBASE_PROJECT_PATTERN.test(entry.projectId || "")) {
      throw new Error(`Manifest projectId for '${name}' is invalid`);
    }
    if (typeof entry.alias !== "string" || !entry.alias) {
      throw new Error(`Manifest alias for '${name}' is invalid`);
    }
    if (entry.alias === "default") {
      throw new Error("Manifest cannot declare the forbidden 'default' alias");
    }
    if (seenAliases.has(entry.alias)) {
      throw new Error(`Manifest alias '${entry.alias}' is assigned more than once`);
    }
    seenAliases.add(entry.alias);
    if (entry.hostingUrl !== null && typeof entry.hostingUrl !== "string") {
      throw new Error(`Manifest hostingUrl for '${name}' is invalid`);
    }
    if ((entry.projectId === null) !== (entry.hostingUrl === null)) {
      throw new Error(
        `Manifest projectId and hostingUrl for '${name}' must be configured together`,
      );
    }
  }
  if (environments.prod.projectId !== manifest.productionProjectId) {
    throw new Error("Production environment must use productionProjectId");
  }
  if (environments.prod.hostingUrl !==
      `https://${manifest.productionProjectId}.web.app`) {
    throw new Error("Production environment must use its standard Hosting URL");
  }
  for (const name of ["dev", "staging"]) {
    if (environments[name].projectId === manifest.productionProjectId) {
      throw new Error(`${name} cannot target the production project`);
    }
  }
  return manifest;
}

function validateFirebaseRc(firebaseRc, productionProjectId) {
  const projects = firebaseRc?.projects || {};
  if (Object.hasOwn(projects, "default")) {
    const target = projects.default;
    const suffix = target === productionProjectId ? " production" : "";
    throw new Error(
      `Firebase 'default' alias is forbidden; it could silently target${suffix} project '${target}'`,
    );
  }
  return projects;
}

function resolveProjectAlias(project, firebaseRc, productionProjectId) {
  const aliases = validateFirebaseRc(firebaseRc, productionProjectId);
  if (typeof project !== "string" || project.trim() === "") {
    throw new Error("An explicit Firebase project ID or alias is required");
  }
  const selected = project.trim();
  const resolvedProjectId = aliases[selected] || selected;
  if (!FIREBASE_PROJECT_PATTERN.test(resolvedProjectId)) {
    throw new Error(`Resolved Firebase project ID '${resolvedProjectId}' is invalid`);
  }
  return resolvedProjectId;
}

function resolveEnvironmentProject({
  environment,
  project,
  manifest,
  firebaseRc = {},
  emulator = false,
}) {
  validateManifest(manifest);
  validateFirebaseRc(firebaseRc, manifest.productionProjectId);
  if (!ENVIRONMENT_NAMES.includes(environment)) {
    throw new Error(
      `Environment must be one of: ${ENVIRONMENT_NAMES.join(", ")}`,
    );
  }
  const resolvedProjectId = resolveProjectAlias(
    project,
    firebaseRc,
    manifest.productionProjectId,
  );

  const config = manifest.environments[environment];
  if (!emulator && config.projectId === null) {
    throw new Error(
      `Environment '${environment}' is not provisioned in the manifest`,
    );
  }
  if (!emulator && resolvedProjectId !== config.projectId) {
    throw new Error(
      `Environment '${environment}' expects project '${config.projectId}', not '${resolvedProjectId}'`,
    );
  }
  if (environment === "prod" &&
      resolvedProjectId !== manifest.productionProjectId) {
    throw new Error(
      `Production must target '${manifest.productionProjectId}'`,
    );
  }
  if (environment !== "prod" &&
      resolvedProjectId === manifest.productionProjectId) {
    throw new Error(
      `Environment '${environment}' cannot target production project '${resolvedProjectId}'`,
    );
  }
  if (emulator && environment === "prod") {
    throw new Error("The production environment cannot be used in emulator mode");
  }
  return {
    environment,
    projectId: resolvedProjectId,
    alias: config.alias,
    hostingUrl: config.hostingUrl,
    production: environment === "prod",
  };
}

function requireProductionOptIn(selection, allowProduction) {
  if (selection.production && allowProduction !== true) {
    throw new Error(
      "Production canary mutation requires explicit --allow-production opt-in",
    );
  }
}

function isLoopbackHostname(hostname) {
  return hostname === "localhost" ||
    hostname === "127.0.0.1" ||
    hostname === "[::1]" ||
    hostname === "::1";
}

function validateAppUrl(
  appUrl,
  projectId,
  { emulator = false, hostingUrl = null } = {},
) {
  let url;
  try {
    url = new URL(appUrl);
  } catch {
    throw new Error("App URL must be an absolute URL");
  }
  if (emulator) {
    if (!["http:", "https:"].includes(url.protocol) ||
        !isLoopbackHostname(url.hostname)) {
      throw new Error("Emulator App URL must use an HTTP(S) loopback host");
    }
    return url;
  }
  if (url.protocol !== "https:") {
    throw new Error("Deployed App URL must use HTTPS");
  }
  const expectedHosts = hostingUrl
    ? new Set([new URL(hostingUrl).hostname])
    : new Set([
      `${projectId}.web.app`,
      `${projectId}.firebaseapp.com`,
    ]);
  if (!expectedHosts.has(url.hostname)) {
    throw new Error(
      `App URL host '${url.hostname}' does not match project '${projectId}'`,
    );
  }
  return url;
}

function validateCredentialDocument(document, projectId) {
  if (!document || document.type !== "service_account") {
    throw new Error("Application credentials must be a service-account JSON file");
  }
  if (document.project_id !== projectId) {
    throw new Error(
      `Credential project_id does not match selected project '${projectId}'`,
    );
  }
}

function validateLoopbackEmulatorHost(value, variableName) {
  const candidate = value || "";
  let url;
  try {
    url = new URL(`http://${candidate}`);
  } catch {
    throw new Error(`${variableName} must be a host:port value`);
  }
  if (!candidate || !url.port || !isLoopbackHostname(url.hostname)) {
    throw new Error(`${variableName} must target a loopback host and port`);
  }
  return candidate;
}

module.exports = {
  ENVIRONMENT_NAMES,
  readJson,
  requireProductionOptIn,
  resolveProjectAlias,
  resolveEnvironmentProject,
  validateAppUrl,
  validateCredentialDocument,
  validateFirebaseRc,
  validateLoopbackEmulatorHost,
  validateManifest,
};
