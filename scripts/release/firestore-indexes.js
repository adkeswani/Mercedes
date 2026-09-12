"use strict";

function collectionGroupOf(index) {
  if (index.collectionGroup) {
    return index.collectionGroup;
  }
  const match = /\/collectionGroups\/([^/]+)\/indexes\//.exec(index.name || "");
  return match ? decodeURIComponent(match[1]) : undefined;
}

function canonicalField(field) {
  if (!field || typeof field.fieldPath !== "string") {
    throw new Error("Firestore index fieldPath is required");
  }
  if (field.order) {
    return { fieldPath: field.fieldPath, order: field.order };
  }
  if (field.arrayConfig) {
    return { fieldPath: field.fieldPath, arrayConfig: field.arrayConfig };
  }
  throw new Error(`Firestore index field '${field.fieldPath}' has no mode`);
}

function canonicalIndex(index) {
  const collectionGroup = collectionGroupOf(index);
  if (!collectionGroup) {
    throw new Error("Firestore index collectionGroup is required");
  }
  return {
    collectionGroup,
    queryScope: index.queryScope || "COLLECTION",
    fields: (index.fields || [])
      .filter((field) => field.fieldPath !== "__name__")
      .map(canonicalField),
  };
}

function indexSignature(index) {
  return JSON.stringify(canonicalIndex(index));
}

function indexLabel(index) {
  const canonical = canonicalIndex(index);
  const fields = canonical.fields.map((field) =>
    `${field.fieldPath} ${field.order || field.arrayConfig}`).join(", ");
  return `${canonical.collectionGroup} [${canonical.queryScope}] (${fields})`;
}

function compareIndexes(expectedIndexes, deployedIndexes) {
  const expected = new Map(
    expectedIndexes.map((index) => [indexSignature(index), indexLabel(index)]),
  );
  const deployed = new Map(
    deployedIndexes
      .filter((index) => index.state !== "DELETING")
      .map((index) => [indexSignature(index), indexLabel(index)]),
  );
  const missing = [...expected]
    .filter(([signature]) => !deployed.has(signature))
    .map(([, label]) => label)
    .sort();
  const unexpected = [...deployed]
    .filter(([signature]) => !expected.has(signature))
    .map(([, label]) => label)
    .sort();
  const notReady = deployedIndexes
    .filter((index) =>
      index.state &&
      index.state !== "READY" &&
      index.state !== "DELETING" &&
      expected.has(indexSignature(index)))
    .map((index) => `${indexLabel(index)}: ${index.state}`)
    .sort();
  return {
    equal: missing.length === 0 &&
      unexpected.length === 0 &&
      notReady.length === 0,
    missing,
    unexpected,
    notReady,
  };
}

function pendingExpectedIndexes(expectedIndexes, deployedIndexes) {
  const bySignature = new Map(
    deployedIndexes
      .filter((index) => index.state !== "DELETING")
      .map((index) => [indexSignature(index), index]),
  );
  return expectedIndexes.map((expected) => {
    const actual = bySignature.get(indexSignature(expected));
    if (!actual) {
      return { label: indexLabel(expected), state: "NOT_LISTED" };
    }
    if (actual.state === "NEEDS_REPAIR") {
      throw new Error(`${indexLabel(expected)} requires repair`);
    }
    return actual.state === "READY"
      ? null
      : { label: indexLabel(expected), state: actual.state || "UNKNOWN" };
  }).filter(Boolean);
}

function assertExpectedQueriesConfigured(expectedQueries, configuredIndexes) {
  const configured = new Set(configuredIndexes.map(indexSignature));
  const missing = expectedQueries
    .filter((query) => !configured.has(indexSignature(query)))
    .map((query) => query.label || indexLabel(query));
  if (missing.length > 0) {
    throw new Error(
      `Repository indexes do not cover release surfaces:\n- ${missing.join("\n- ")}`,
    );
  }
}

module.exports = {
  assertExpectedQueriesConfigured,
  canonicalIndex,
  compareIndexes,
  indexLabel,
  indexSignature,
  pendingExpectedIndexes,
};
