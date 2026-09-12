#!/usr/bin/env node
"use strict";

const { parseArguments, requireArgument } = require("./arguments.js");
const {
  createAdminContext,
  localIsoDate,
  requireCanaryCredentials,
  seedFixture,
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
    const result = await seedFixture(adminContext, fixture, credentials);
    console.log(
      `Seeded ${result.documentsWritten} release-canary documents and ` +
      `${result.authCreated + result.authUpdated} Auth users in ` +
      `${context.environment}/${context.projectId}.`,
    );
  } finally {
    await adminContext.app.delete();
  }
}

main().catch((error) => {
  console.error(`Release canary seed failed: ${error.message}`);
  process.exitCode = 1;
});
