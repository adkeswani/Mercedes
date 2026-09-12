#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const net = require("node:net");
const path = require("node:path");
const { spawn } = require("node:child_process");
const { parseArguments, requireArgument } = require("./arguments.js");
const { requireCanaryCredentials } = require("./admin-canary.js");
const { loadReleaseContext } = require("./context.js");
const {
  requireProductionOptIn,
  validateAppUrl,
} = require("./environment.js");
const { EXPECTED_SURFACES } = require("./expectations.js");

const WEB_DRIVER_ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf";

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      server.close(() => resolve(address.port));
    });
  });
}

async function waitFor(action, description, timeoutMilliseconds = 60000) {
  const deadline = Date.now() + timeoutMilliseconds;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const result = await action();
      if (result) {
        return result;
      }
    } catch (error) {
      lastError = error;
    }
    await delay(250);
  }
  const suffix = lastError ? ` Last error: ${lastError.message}` : "";
  throw new Error(`Timed out waiting for ${description}.${suffix}`);
}

async function webdriverRequest(baseUrl, pathname, {
  method = "GET",
  body,
} = {}) {
  const response = await fetch(`${baseUrl}${pathname}`, {
    method,
    headers: body === undefined ? undefined : {
      "content-type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.value?.error) {
    const message = payload.value?.message ||
      `${response.status} ${response.statusText}`;
    throw new Error(`ChromeDriver request failed: ${message}`);
  }
  return payload.value;
}

function sessionPath(sessionId, suffix) {
  return `/session/${sessionId}${suffix}`;
}

async function execute(baseUrl, sessionId, script, args = []) {
  return webdriverRequest(
    baseUrl,
    sessionPath(sessionId, "/execute/sync"),
    { method: "POST", body: { script, args } },
  );
}

async function navigate(baseUrl, sessionId, url) {
  await webdriverRequest(baseUrl, sessionPath(sessionId, "/url"), {
    method: "POST",
    body: { url },
  });
}

async function currentUrl(baseUrl, sessionId) {
  return webdriverRequest(baseUrl, sessionPath(sessionId, "/url"));
}

async function findByAriaLabel(baseUrl, sessionId, label) {
  return execute(
    baseUrl,
    sessionId,
    `
const expected = arguments[0];
return Array.from(document.querySelectorAll("[aria-label]"))
  .find((element) => {
    const label = element.getAttribute("aria-label") || "";
    return label === expected || label.includes(expected);
  }) || null;
`,
    [label],
  );
}

async function clickElement(baseUrl, sessionId, element) {
  const elementId = element?.[WEB_DRIVER_ELEMENT_KEY];
  if (!elementId) {
    throw new Error("ChromeDriver did not return a valid element");
  }
  await webdriverRequest(
    baseUrl,
    sessionPath(sessionId, `/element/${elementId}/click`),
    { method: "POST", body: {} },
  );
}

async function typeIntoElement(
  baseUrl,
  sessionId,
  element,
  value,
  { submit = false } = {},
) {
  await clickElement(baseUrl, sessionId, element);
  const active = await webdriverRequest(
    baseUrl,
    sessionPath(sessionId, "/element/active"),
  );
  const activeId = active?.[WEB_DRIVER_ELEMENT_KEY];
  if (!activeId) {
    throw new Error("Release canary field did not receive browser focus");
  }
  await webdriverRequest(
    baseUrl,
    sessionPath(sessionId, `/element/${activeId}/value`),
    {
      method: "POST",
      body: { text: value, value: [...value] },
    },
  );
  if (submit) {
    await webdriverRequest(
      baseUrl,
      sessionPath(sessionId, `/element/${activeId}/value`),
      {
        method: "POST",
        body: { text: "\uE007", value: ["\uE007"] },
      },
    );
  }
}

async function activateFlutterSemantics(baseUrl, sessionId) {
  await execute(
    baseUrl,
    sessionId,
    `
const placeholder = document.querySelector("flt-semantics-placeholder");
if (placeholder) {
  placeholder.click();
}
return true;
`,
  );
}

async function saveScreenshot(baseUrl, sessionId, artifactDirectory, name) {
  const encoded = await webdriverRequest(
    baseUrl,
    sessionPath(sessionId, "/screenshot"),
  );
  const bytes = Buffer.from(encoded, "base64");
  if (bytes.length === 0) {
    throw new Error(`ChromeDriver returned an empty screenshot for ${name}`);
  }
  const output = path.join(artifactDirectory, name);
  fs.writeFileSync(output, bytes);
  console.log(`Canary artifact: ${output}`);
}

function canaryUrl(appUrl, route) {
  const url = new URL(appUrl);
  url.searchParams.set("release-canary", "1");
  url.hash = route;
  return url.toString();
}

async function assertRoute(baseUrl, sessionId, route) {
  const actual = new URL(await currentUrl(baseUrl, sessionId));
  if (actual.hash !== `#${route}`) {
    throw new Error(`Expected route '${route}', reached '${actual.hash}'`);
  }
}

async function signIn({
  baseUrl,
  sessionId,
  appUrl,
  projectId,
  route,
  role,
  email,
  password,
  displayName,
}) {
  await navigate(baseUrl, sessionId, canaryUrl(appUrl, route));
  await waitFor(async () => {
    const selectedProject = await execute(
      baseUrl,
      sessionId,
      "return document.body?.getAttribute(" +
        "'data-browser-smoke-firebase-project') || null;",
    );
    if (selectedProject && selectedProject !== projectId) {
      throw new Error(
        `Deployed app targets '${selectedProject}', expected '${projectId}'`,
      );
    }
    return selectedProject === projectId;
  }, "deployed app Firebase project marker");

  await activateFlutterSemantics(baseUrl, sessionId);
  const emailField = await waitFor(
    () => findByAriaLabel(baseUrl, sessionId, "Release canary email"),
    "release canary email field",
  );
  await typeIntoElement(baseUrl, sessionId, emailField, email);
  const passwordField = await waitFor(
    () => findByAriaLabel(baseUrl, sessionId, "Release canary password"),
    "release canary password field",
  );
  await typeIntoElement(
    baseUrl,
    sessionId,
    passwordField,
    password,
    { submit: true },
  );

  await waitFor(async () => {
    const state = await execute(
      baseUrl,
      sessionId,
      `
return document.body ? {
  email: document.body.getAttribute("data-browser-smoke-authenticated"),
  workspace: document.body.getAttribute("data-browser-smoke-workspace"),
  identity: document.body.getAttribute("data-browser-smoke-account-identity")
} : null;
`,
    );
    return state?.email === email &&
      state?.workspace === role &&
      state?.identity === displayName;
  }, `${role} authentication and header identity`);
  await assertRoute(baseUrl, sessionId, route);
}

async function runIdentity({
  baseUrl,
  appUrl,
  projectId,
  role,
  email,
  password,
  displayName,
  artifactDirectory,
}) {
  const session = await webdriverRequest(baseUrl, "/session", {
    method: "POST",
    body: {
      capabilities: {
        alwaysMatch: {
          browserName: "chrome",
          "goog:chromeOptions": {
            args: [
              "--headless=new",
              "--window-size=1280,800",
              "--disable-gpu",
              "--no-sandbox",
            ],
          },
        },
      },
    },
  });
  const sessionId = session.sessionId;
  if (!sessionId) {
    throw new Error("ChromeDriver did not return a browser session ID");
  }
  try {
    const route = role === "trainer"
      ? "/trainer/dashboard"
      : "/athlete/today";
    await signIn({
      baseUrl,
      sessionId,
      appUrl,
      projectId,
      route,
      role,
      email,
      password,
      displayName,
    });
    await saveScreenshot(
      baseUrl,
      sessionId,
      artifactDirectory,
      `${role}-header-identity.png`,
    );
    if (role === "trainer") {
      return;
    }
    for (const surface of EXPECTED_SURFACES) {
      await execute(
        baseUrl,
        sessionId,
        "window.location.hash = arguments[0]; return true;",
        [surface.route],
      );
      await waitFor(async () => {
        const state = await execute(
          baseUrl,
          sessionId,
          `
const marker = arguments[0];
return document.body ? {
  state: document.body.getAttribute("data-browser-smoke-surface-" + marker),
  content: document.body.getAttribute(
    "data-browser-smoke-surface-" + marker + "-content"
  ),
  text: document.body.innerText || ""
} : null;
`,
          [surface.marker],
        );
        if (state?.state && state.state !== "ready") {
          throw new Error(
            `${surface.label} reported '${state.state}' instead of populated`,
          );
        }
        if (state?.state === "ready" &&
            state.content !== surface.expectedContent) {
          throw new Error(
            `${surface.label} loaded '${state.content}', expected ` +
            `'${surface.expectedContent}'`,
          );
        }
        if (/permission-denied|something went wrong|unable to load|error:/i
          .test(state?.text || "")) {
          throw new Error(`${surface.label} rendered an error state`);
        }
        return state?.state === "ready";
      }, `${surface.label} populated backend state`);
      await assertRoute(baseUrl, sessionId, surface.route);
      await saveScreenshot(
        baseUrl,
        sessionId,
        artifactDirectory,
        surface.screenshot,
      );
    }
  } catch (error) {
    try {
      await saveScreenshot(
        baseUrl,
        sessionId,
        artifactDirectory,
        `${role}-failure.png`,
      );
    } catch {
      // Preserve the functional failure when screenshot capture also fails.
    }
    throw error;
  } finally {
    await webdriverRequest(baseUrl, `/session/${sessionId}`, {
      method: "DELETE",
    }).catch(() => {});
  }
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const emulator = args.emulator === true;
  const context = loadReleaseContext({
    environment: requireArgument(args, "environment"),
    project: requireArgument(args, "project"),
    emulator,
  });
  requireProductionOptIn(context, args["allow-production"]);
  const appUrl = validateAppUrl(
    requireArgument(args, "app-url"),
    context.projectId,
    { emulator, hostingUrl: context.hostingUrl },
  );
  const credentials = requireCanaryCredentials({ emulator });
  const chromeDriver = path.resolve(requireArgument(args, "chrome-driver"));
  if (!fs.existsSync(chromeDriver)) {
    throw new Error(`ChromeDriver not found: ${chromeDriver}`);
  }
  const artifactDirectory = path.resolve(
    requireArgument(args, "artifact-dir"),
  );
  fs.mkdirSync(artifactDirectory, { recursive: true });

  const port = await freePort();
  const driver = spawn(chromeDriver, [`--port=${port}`], {
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
  let driverError = "";
  driver.stderr.on("data", (chunk) => {
    driverError += chunk.toString();
  });
  const baseUrl = `http://127.0.0.1:${port}`;
  try {
    await waitFor(async () => {
      const response = await fetch(`${baseUrl}/status`);
      return response.ok;
    }, "ChromeDriver startup", 15000);
    await runIdentity({
      baseUrl,
      appUrl,
      projectId: context.projectId,
      role: "trainer",
      email: credentials.trainerEmail,
      password: credentials.trainerPassword,
      displayName: "Release Canary Trainer",
      artifactDirectory,
    });
    await runIdentity({
      baseUrl,
      appUrl,
      projectId: context.projectId,
      role: "athlete",
      email: credentials.athleteEmail,
      password: credentials.athletePassword,
      displayName: "Release Canary Athlete",
      artifactDirectory,
    });
    console.log(
      `Deployed release canary passed for ` +
      `${context.environment}/${context.projectId}.`,
    );
  } finally {
    if (!driver.killed) {
      driver.kill();
    }
    if (driver.exitCode && driver.exitCode !== 0 && driverError) {
      console.error(driverError.trim());
    }
  }
}

main().catch((error) => {
  console.error(`Deployed release canary failed: ${error.message}`);
  process.exitCode = 1;
});
