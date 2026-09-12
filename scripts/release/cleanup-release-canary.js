#!/usr/bin/env node
"use strict";

const { parseArguments, requireArgument } = require("./arguments.js");
const {
  cleanupFixture,
  createAdminContext,
  localIsoDate,
  requireCanaryCredentials,
} = require("./admin-canary.js");
const { buildCanaryFixture } = require("./canary-fixture.js");
const { loadReleaseContext } = require("./context.js");
const { requireProductionOptIn } = require("./environment.js");

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const emulator = args.emulator === true;
  const context = loadReleaseContext({
    environment: requireArgument(args, "environment"),
    project: requireArgument(args, "project"),
    emulator,
  });
  requireProductionOptIn(context, args["allow-production"]);
  const credentials = requireCanaryCredentials({ emulator });
  const fixture = buildCanaryFixture({
    trainerEmail: credentials.trainerEmail,
    athleteEmail: credentials.athleteEmail,
    today: args.date || localIsoDate(),
  });
  const adminContext = createAdminContext({
    ...context,
    appUrl: requireArgument(args, "app-url"),
    emulator,
  });
  try {
    const result = await cleanupFixture(adminContext, fixture);
    console.log(
      `Removed ${result.documentsDeleted} release-canary documents and ` +
      `${result.usersDeleted} Auth users from ` +
      `${context.environment}/${context.projectId}.`,
    );
  } finally {
    await adminContext.app.delete();
  }
}

main().catch((error) => {
  console.error(`Release canary cleanup failed: ${error.message}`);
  process.exitCode = 1;
});
