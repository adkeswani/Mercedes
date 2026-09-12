"use strict";

function parseArguments(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith("--")) {
      throw new Error(`Unexpected positional argument: ${argument}`);
    }
    const name = argument.slice(2);
    if (name === "allow-production" || name === "emulator") {
      result[name] = true;
      continue;
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for --${name}`);
    }
    result[name] = value;
    index += 1;
  }
  return result;
}

function requireArgument(argumentsMap, name) {
  const value = argumentsMap[name];
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`--${name} is required`);
  }
  return value.trim();
}

module.exports = { parseArguments, requireArgument };
