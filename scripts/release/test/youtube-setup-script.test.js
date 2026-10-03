"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..", "..", "..");
const source = fs.readFileSync(
  path.join(root, "scripts", "setup-youtube-production.ps1"),
  "utf8",
);
const releaseProcess = fs.readFileSync(
  path.join(root, "docs", "release-process.md"),
  "utf8",
);
const stageReadme = fs.readFileSync(
  path.join(root, "stage5", "README.md"),
  "utf8",
);

test("YouTube setup script defaults safely and supports check-only mode", () => {
  assert.match(source, /\[string\]\$Environment = 'prod'/);
  assert.match(source, /\[string\]\$Project = 'mercedes-app-11ce2'/);
  assert.match(source, /\[switch\]\$CheckOnly/);
  assert.match(source, /No cloud or repository mutation was attempted/);
  assert.match(source, /Test-FunctionsBuildPrerequisites/);
  assert.match(source, /npm --prefix \$functionsPath ci --no-audit --no-fund/);
  assert.match(source, /Phrase 'INSTALL FUNCTIONS DEPENDENCIES'/);
  assert.match(source, /npm --prefix \$functionsPath run build/);
});

test("secret value stays exclusively inside Firebase secure prompting", () => {
  assert.match(
    source,
    /firebase functions:secrets:set YOUTUBE_API_KEY/,
  );
  assert.match(
    source,
    /firebase functions:secrets:get YOUTUBE_API_KEY/,
  );
  assert.doesNotMatch(source, /functions:secrets:access/);
  assert.doesNotMatch(source, /YOUTUBE_API_KEY\s*=/);
  assert.doesNotMatch(source, /Read-Host[^]*API key value/i);
});

test("every cloud mutation and production deployment needs an exact phrase", () => {
  assert.match(source, /Phrase 'ENABLE YOUTUBE API'/);
  assert.match(source, /Phrase 'SET YOUTUBE SECRET'/);
  assert.match(source, /"DRY RUN \$confirmationEnvironment"/);
  assert.match(source, /"DEPLOY \$confirmationEnvironment"/);
  assert.match(source, /cloud-preparation mutation/);
  assert.match(source, /does not release Functions or Firestore revisions/);
  assert.match(source, /enable required service APIs[^]*create service/);
  assert.match(source, /identities, or prepare IAM/);
  assert.doesNotMatch(source, /non-mutating backend dry run/i);
  assert.match(source, /if \(-not \$dryRunPassed\)/);
  assert.match(source, /git merge --ff-only/);
  assert.doesNotMatch(source, /git (?:merge|rebase|push)(?! --ff-only)/);
});

test("operator docs describe dry run cloud preparation accurately", () => {
  for (const document of [releaseProcess, stageReadme]) {
    assert.match(document, /does not release[^.]*Functions[^.]*Firestore/i);
    assert.match(document, /service APIs/i);
    assert.match(document, /service identities/i);
    assert.match(document, /IAM/);
    assert.match(document, /cloud-preparation mutation/i);
  }
  assert.doesNotMatch(
    releaseProcess,
    /validate the backend configuration without mutation/i,
  );
});
