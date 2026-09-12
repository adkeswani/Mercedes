#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory)]
    [string]$Project,

    [ValidateRange(1, 7200)]
    [int]$TimeoutSeconds = 1800,

    [ValidateRange(1, 300)]
    [int]$PollSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$indexConfig = Join-Path $repoRoot 'firestore.indexes.json'
$projectId = $Project
$firebaseRcPath = Join-Path $repoRoot '.firebaserc'
if (Test-Path -LiteralPath $firebaseRcPath -PathType Leaf) {
    $firebaseRc =
        Get-Content -LiteralPath $firebaseRcPath -Raw | ConvertFrom-Json
    $alias = $firebaseRc.projects.PSObject.Properties |
        Where-Object Name -EQ $Project |
        Select-Object -First 1
    if ($alias) {
        $projectId = $alias.Value
    }
}
$npmRoot = (& npm root -g).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($npmRoot)) {
    throw 'Unable to locate the global npm package directory.'
}
$firebaseToolsLib = Join-Path $npmRoot 'firebase-tools\lib'
if (-not (Test-Path -LiteralPath $firebaseToolsLib -PathType Container)) {
    throw 'firebase-tools must be installed globally before deployment.'
}

$env:FIREBASE_INDEX_PROJECT = $projectId
$env:FIREBASE_INDEX_CONFIG = $indexConfig
$env:FIREBASE_TOOLS_LIB = $firebaseToolsLib
$env:FIREBASE_INDEX_TIMEOUT_SECONDS = $TimeoutSeconds.ToString()
$env:FIREBASE_INDEX_POLL_SECONDS = $PollSeconds.ToString()
try {
    # Reuse the authenticated, pinned Firebase CLI because its public index
    # listing omits build state.
    @'
const fs = require("fs");
const path = require("path");

const lib = process.env.FIREBASE_TOOLS_LIB;
const auth = require(path.join(lib, "auth.js"));
const { requireAuth } = require(path.join(lib, "requireAuth.js"));
const { Client } = require(path.join(lib, "apiv2.js"));
const { firestoreOrigin } = require(path.join(lib, "api.js"));

const project = process.env.FIREBASE_INDEX_PROJECT;
const required = JSON.parse(
  fs.readFileSync(process.env.FIREBASE_INDEX_CONFIG, "utf8"),
).indexes;
const timeoutMs =
  Number(process.env.FIREBASE_INDEX_TIMEOUT_SECONDS) * 1000;
const pollMs = Number(process.env.FIREBASE_INDEX_POLL_SECONDS) * 1000;
const sleep = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

function fieldMatches(requiredField, deployedField) {
  return requiredField.fieldPath === deployedField.fieldPath &&
    (requiredField.order === undefined ||
      requiredField.order === deployedField.order) &&
    (requiredField.arrayConfig === undefined ||
      requiredField.arrayConfig === deployedField.arrayConfig);
}

function indexMatches(requiredIndex, deployedIndex) {
  const nameMatch = /\/collectionGroups\/([^/]+)\/indexes\//.exec(
    deployedIndex.name || "",
  );
  const collectionGroup = deployedIndex.collectionGroup ||
    (nameMatch ? decodeURIComponent(nameMatch[1]) : undefined);
  if (requiredIndex.collectionGroup !== collectionGroup ||
      requiredIndex.queryScope !== deployedIndex.queryScope) {
    return false;
  }
  const deployedFields = deployedIndex.fields.filter(
    (field) => field.fieldPath !== "__name__",
  );
  return requiredIndex.fields.length === deployedFields.length &&
    requiredIndex.fields.every(
      (field, index) => fieldMatches(field, deployedFields[index]),
    );
}

function label(index) {
  const fields = index.fields
    .filter((field) => field.fieldPath !== "__name__")
    .map((field) =>
      `${field.fieldPath} ${field.order || field.arrayConfig}`,
    )
    .join(", ");
  return `${index.collectionGroup} (${fields})`;
}

async function listIndexes(client) {
  let pageToken;
  const indexes = [];
  do {
    const options = pageToken ? { queryParams: { pageToken } } : {};
    const response = await client.get(
      `/projects/${project}/databases/(default)/collectionGroups/-/indexes`,
      options,
    );
    indexes.push(...(response.body.indexes || []));
    pageToken = response.body.nextPageToken;
  } while (pageToken);
  return indexes;
}

(async () => {
  const account =
    auth.getProjectDefaultAccount(process.cwd()) ||
    auth.getGlobalDefaultAccount();
  if (!account) {
    throw new Error("Firebase CLI account is not authenticated");
  }
  await requireAuth({
    project,
    user: account.user,
    tokens: account.tokens,
    nonInteractive: true,
  });
  const client = new Client({
    urlPrefix: firestoreOrigin(),
    apiVersion: "v1",
  });
  const deadline = Date.now() + timeoutMs;
  while (true) {
    const deployed = await listIndexes(client);
    const pending = [];
    for (const expected of required) {
      const actual = deployed.find((index) => indexMatches(expected, index));
      if (!actual) {
        pending.push(`${label(expected)}: not listed yet`);
      } else if (actual.state === "NEEDS_REPAIR") {
        throw new Error(`${label(expected)} requires repair`);
      } else if (actual.state !== "READY") {
        pending.push(`${label(expected)}: ${actual.state || "UNKNOWN"}`);
      }
    }
    if (pending.length === 0) {
      console.log("All configured Firestore composite indexes are READY.");
      return;
    }
    if (Date.now() >= deadline) {
      throw new Error(
        `Timed out waiting for Firestore indexes:\n${pending.join("\n")}`,
      );
    }
    console.log(
      `Waiting for ${pending.length} Firestore index(es): ` +
      pending.join("; "),
    );
    await sleep(pollMs);
  }
})().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
'@ | node -
    if ($LASTEXITCODE -ne 0) {
        throw 'Firestore index readiness check failed.'
    }
}
finally {
    $env:FIREBASE_INDEX_PROJECT = $null
    $env:FIREBASE_INDEX_CONFIG = $null
    $env:FIREBASE_TOOLS_LIB = $null
    $env:FIREBASE_INDEX_TIMEOUT_SECONDS = $null
    $env:FIREBASE_INDEX_POLL_SECONDS = $null
}
