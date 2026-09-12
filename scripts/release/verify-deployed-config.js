#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { parseArguments, requireArgument } = require("./arguments.js");
const { loadReleaseContext } = require("./context.js");
const { EXPECTED_QUERY_LABELS } = require("./expectations.js");
const {
  assertExpectedQueriesConfigured,
} = require("./firestore-indexes.js");
const {
  compareFirestoreConfiguration,
} = require("./firestore-parity.js");
const {
  authenticateFirebaseCli,
  getActiveFirestoreRules,
  listCompositeIndexes,
  loadFirebaseCli,
} = require("./firebase-cli.js");

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const context = loadReleaseContext({
    environment: requireArgument(args, "environment"),
    project: requireArgument(args, "project"),
  });
  const rulesPath = path.join(context.root, "firestore.rules");
  const indexesPath = path.join(context.root, "firestore.indexes.json");
  const expectedRules = fs.readFileSync(rulesPath, "utf8");
  const indexConfig = JSON.parse(fs.readFileSync(indexesPath, "utf8"));
  if (!Array.isArray(indexConfig.indexes)) {
    throw new Error("firestore.indexes.json must contain an indexes array");
  }
  if ((indexConfig.fieldOverrides || []).length !== 0) {
    throw new Error(
      "Parity currently requires repository fieldOverrides to remain empty",
    );
  }
  assertExpectedQueriesConfigured(EXPECTED_QUERY_LABELS, indexConfig.indexes);

  const cli = loadFirebaseCli(process.env.RELEASE_FIREBASE_TOOLS_LIB);
  await authenticateFirebaseCli(cli, context.projectId, context.root);
  const [deployedRules, deployedIndexes] = await Promise.all([
    getActiveFirestoreRules(cli, context.projectId),
    listCompositeIndexes(cli, context.projectId),
  ]);
  const result = compareFirestoreConfiguration({
    expectedRules,
    deployedRules,
    expectedIndexes: indexConfig.indexes,
    deployedIndexes,
  });
  if (!result.equal) {
    throw new Error(
      `Deployed Firestore configuration differs from the repository:\n\n` +
      result.failures.join("\n\n"),
    );
  }
  console.log(
    `Firestore rules and ${indexConfig.indexes.length} composite indexes ` +
    `match ${context.environment}/${context.projectId}.`,
  );
}

main().catch((error) => {
  console.error(`Release parity check failed: ${error.message}`);
  process.exitCode = 1;
});
