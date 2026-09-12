"use strict";

const { compareIndexes } = require("./firestore-indexes.js");

function normalizeRules(source) {
  if (typeof source !== "string") {
    throw new Error("Firestore rules source must be a string");
  }
  return source.replace(/^\uFEFF/, "").replace(/\r\n/g, "\n").trimEnd() + "\n";
}

function rulesDifference(expectedSource, deployedSource) {
  const expected = normalizeRules(expectedSource);
  const deployed = normalizeRules(deployedSource);
  if (expected === deployed) {
    return null;
  }
  const expectedLines = expected.split("\n");
  const deployedLines = deployed.split("\n");
  const length = Math.max(expectedLines.length, deployedLines.length);
  for (let index = 0; index < length; index += 1) {
    if (expectedLines[index] !== deployedLines[index]) {
      return {
        line: index + 1,
        expected: expectedLines[index] ?? "<end of file>",
        deployed: deployedLines[index] ?? "<end of file>",
      };
    }
  }
  throw new Error("Unable to locate Firestore rules difference");
}

function compareFirestoreConfiguration({
  expectedRules,
  deployedRules,
  expectedIndexes,
  deployedIndexes,
}) {
  const rules = rulesDifference(expectedRules, deployedRules);
  const indexes = compareIndexes(expectedIndexes, deployedIndexes);
  const failures = [];
  if (rules) {
    failures.push(
      `Firestore rules differ at line ${rules.line}\n` +
      `  repository: ${rules.expected}\n` +
      `  deployed:   ${rules.deployed}`,
    );
  }
  if (indexes.missing.length > 0) {
    failures.push(
      `Missing deployed composite indexes:\n- ${indexes.missing.join("\n- ")}`,
    );
  }
  if (indexes.unexpected.length > 0) {
    failures.push(
      `Unexpected deployed composite indexes:\n- ${indexes.unexpected.join("\n- ")}`,
    );
  }
  if (indexes.notReady.length > 0) {
    failures.push(
      `Configured composite indexes are not READY:\n- ${indexes.notReady.join("\n- ")}`,
    );
  }
  return {
    equal: failures.length === 0,
    failures,
    rules,
    indexes,
  };
}

module.exports = {
  compareFirestoreConfiguration,
  normalizeRules,
  rulesDifference,
};
