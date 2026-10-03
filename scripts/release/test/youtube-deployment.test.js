"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..", "..", "..");
const read = (...segments) =>
  fs.readFileSync(path.join(root, ...segments), "utf8");

test("Firebase configuration includes every YouTube release surface", () => {
  const config = JSON.parse(read("firebase.json"));
  assert.equal(config.functions[0].source, "functions");
  assert.ok(config.functions[0].predeploy.includes(
    "npm --prefix \"$RESOURCE_DIR\" run build",
  ));
  assert.equal(config.firestore.rules, "firestore.rules");
  assert.equal(config.firestore.indexes, "firestore.indexes.json");
  assert.equal(config.hosting.public, "stage5/build/web");
});

test("callable binds its secret and bounded runtime security options", () => {
  const source = read("functions", "src", "index.ts");
  assert.match(source, /defineSecret\("YOUTUBE_API_KEY"\)/);
  assert.match(source, /secrets: \[youtubeApiKey\]/);
  assert.match(source, /region: "us-central1"/);
  assert.match(source, /maxInstances: 10/);
  assert.match(source, /timeoutSeconds: 300/);
  assert.match(source, /memory: "512MiB"/);
  assert.match(source, /enforceAppCheck: false/);
  assert.match(source, /if \(!request\.auth\?\.uid\)/);
  assert.doesNotMatch(source, /logger\.error\([^]*\berror,\s*\n/);
});

test("catalogue storage is server-owned and needs no composite index", () => {
  const rules = read("firestore.rules");
  const indexes = JSON.parse(read("firestore.indexes.json"));
  assert.match(rules, /match \/youtubeChannelCatalogs\/\{channelId\}/);
  assert.match(rules, /allow create, update, delete: if false/);
  assert.equal(
    indexes.indexes.some(
      (index) => index.collectionGroup === "youtubeChannelCatalogs" ||
        index.collectionGroup === "pages",
    ),
    false,
  );
});

test("web release fails closed on a missing secret and deploys in order", () => {
  const deploy = read("deploy.ps1");
  const secretCheck = deploy.indexOf(
    "firebase functions:secrets:get YOUTUBE_API_KEY",
  );
  const backendDeploy = deploy.indexOf(
    'firebase deploy --only "functions,firestore:rules,firestore:indexes"',
  );
  const indexWait = deploy.indexOf("scripts\\wait-firestore-indexes.ps1");
  const hostingDeploy = deploy.indexOf(
    "firebase deploy --only hosting",
  );
  const parityCheck = deploy.indexOf("scripts\\verify-deployed-config.ps1");

  assert.ok(secretCheck >= 0);
  assert.ok(backendDeploy > secretCheck);
  assert.ok(indexWait > backendDeploy);
  assert.ok(hostingDeploy > indexWait);
  assert.ok(parityCheck > hostingDeploy);
});

test("Windows Developer Mode reminder follows only complete deployments", () => {
  const deploy = read("deploy.ps1");
  const completionAssignment = deploy.indexOf("$deploymentCompleted =");
  const completionGuard = deploy.indexOf("if ($deploymentCompleted)");
  const reminderCall = deploy.indexOf("Write-DeveloperModeReminder");
  const reminderCommand = deploy.indexOf("start ms-settings:developers");

  assert.ok(completionAssignment >= 0);
  assert.ok(completionGuard > completionAssignment);
  assert.ok(reminderCall >= 0);
  assert.ok(reminderCommand > reminderCall);
  assert.match(
    deploy,
    /\$deploymentCompleted\s*=\s*\r?\n\s*\(-not \$deploysWeb -or \$webDeploymentCompleted\) -and\s*\r?\n\s*\(-not \$deploysAndroid -or \$androidBuildCompleted\)/,
  );
  assert.match(
    deploy,
    /if \(\$deploymentCompleted\)[^]*if \(\$IsWindows\)[^]*Write-DeveloperModeReminder/,
  );
  assert.match(
    deploy,
    /Turn off only Developer Mode; leave normal Windows security [^]*protections enabled\./,
  );
  assert.doesNotMatch(
    deploy,
    /Start-Process\s+['"]ms-settings:developers['"]/i,
  );
  assert.doesNotMatch(deploy, /Set-ItemProperty|reg(?:\.exe)?\s+add/i);
});
