#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { parseArguments, requireArgument } = require("./arguments.js");
const { loadProjectContext } = require("./context.js");
const {
  pendingExpectedIndexes,
} = require("./firestore-indexes.js");
const {
  authenticateFirebaseCli,
  listCompositeIndexes,
  loadFirebaseCli,
} = require("./firebase-cli.js");

function positiveInteger(value, name) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) {
    throw new Error(`--${name} must be a positive integer`);
  }
  return parsed;
}

const sleep = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const context = loadProjectContext(requireArgument(args, "project"));
  const timeoutSeconds = positiveInteger(args.timeout || "1800", "timeout");
  const pollSeconds = positiveInteger(args.poll || "15", "poll");
  const indexConfig = JSON.parse(
    fs.readFileSync(path.join(context.root, "firestore.indexes.json"), "utf8"),
  );
  if (!Array.isArray(indexConfig.indexes)) {
    throw new Error("firestore.indexes.json must contain an indexes array");
  }

  const cli = loadFirebaseCli(process.env.RELEASE_FIREBASE_TOOLS_LIB);
  await authenticateFirebaseCli(cli, context.projectId, context.root);
  const deadline = Date.now() + timeoutSeconds * 1000;
  while (true) {
    const deployed = await listCompositeIndexes(cli, context.projectId);
    const pending = pendingExpectedIndexes(indexConfig.indexes, deployed);
    if (pending.length === 0) {
      console.log("All configured Firestore composite indexes are READY.");
      return;
    }
    if (Date.now() >= deadline) {
      const detail = pending
        .map((index) => `${index.label}: ${index.state}`)
        .join("\n- ");
      throw new Error(`Timed out waiting for Firestore indexes:\n- ${detail}`);
    }
    console.log(
      `Waiting for ${pending.length} Firestore index(es): ` +
      pending.map((index) => `${index.label}: ${index.state}`).join("; "),
    );
    await sleep(pollSeconds * 1000);
  }
}

main().catch((error) => {
  console.error(`Firestore index readiness check failed: ${error.message}`);
  process.exitCode = 1;
});
