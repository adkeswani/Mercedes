"use strict";

const path = require("node:path");

function loadFirebaseCli(firebaseToolsLib) {
  if (!firebaseToolsLib) {
    throw new Error("Firebase CLI library path was not provided");
  }
  const load = (modulePath) => require(path.join(firebaseToolsLib, modulePath));
  return {
    auth: load("auth.js"),
    requireAuth: load("requireAuth.js").requireAuth,
    Client: load("apiv2.js").Client,
    firestoreOrigin: load("api.js").firestoreOrigin,
    rules: load(path.join("gcp", "rules.js")),
  };
}

async function authenticateFirebaseCli(cli, projectId, cwd = process.cwd()) {
  const account =
    cli.auth.getProjectDefaultAccount(cwd) ||
    cli.auth.getGlobalDefaultAccount();
  if (!account) {
    throw new Error("Firebase CLI account is not authenticated");
  }
  await cli.requireAuth({
    project: projectId,
    user: account.user,
    tokens: account.tokens,
    nonInteractive: true,
  });
}

async function listCompositeIndexes(cli, projectId) {
  const client = new cli.Client({
    urlPrefix: cli.firestoreOrigin(),
    apiVersion: "v1",
  });
  const indexes = [];
  let pageToken;
  do {
    const options = pageToken ? { queryParams: { pageToken } } : {};
    const response = await client.get(
      `/projects/${projectId}/databases/(default)/collectionGroups/-/indexes`,
      options,
    );
    indexes.push(...(response.body.indexes || []));
    pageToken = response.body.nextPageToken;
  } while (pageToken);
  return indexes;
}

async function getActiveFirestoreRules(cli, projectId) {
  const rulesetName = await cli.rules.getLatestRulesetName(
    projectId,
    "cloud.firestore",
  );
  if (!rulesetName) {
    throw new Error(`No active Cloud Firestore rules release for '${projectId}'`);
  }
  const files = await cli.rules.getRulesetContent(rulesetName);
  const named = files.find((file) =>
    (file.name || "").replaceAll("\\", "/").endsWith("/firestore.rules") ||
    file.name === "firestore.rules");
  const selected = named || (files.length === 1 ? files[0] : null);
  if (!selected || typeof selected.content !== "string") {
    throw new Error(
      "Active Firestore ruleset does not contain an unambiguous firestore.rules source",
    );
  }
  return selected.content;
}

module.exports = {
  authenticateFirebaseCli,
  getActiveFirestoreRules,
  listCompositeIndexes,
  loadFirebaseCli,
};
