#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const net = require("node:net");
const path = require("node:path");
const { spawn } = require("node:child_process");
const { parseArguments, requireArgument } = require("./arguments.js");
const {
  createAdminContext,
  requireCanaryCredentials,
} = require("./admin-canary.js");
const { CANARY_IDS } = require("./canary-fixture.js");
const { loadReleaseContext } = require("./context.js");
const {
  requireProductionOptIn,
  validateAppUrl,
} = require("./environment.js");
const {
  EXPECTED_ATHLETE_SURFACES,
  EXPECTED_TRAINER_SURFACES,
} = require("./expectations.js");

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

async function elementRect(baseUrl, sessionId, element) {
  const elementId = element?.[WEB_DRIVER_ELEMENT_KEY];
  if (!elementId) {
    throw new Error("ChromeDriver did not return a valid element");
  }
  return webdriverRequest(
    baseUrl,
    sessionPath(sessionId, `/element/${elementId}/rect`),
  );
}

async function clickAtOffset(baseUrl, sessionId, element, xOffset, yOffset) {
  const rect = await elementRect(baseUrl, sessionId, element);
  await webdriverRequest(baseUrl, sessionPath(sessionId, "/actions"), {
    method: "POST",
    body: {
      actions: [{
        type: "pointer",
        id: "offset-click",
        parameters: { pointerType: "mouse" },
        actions: [
          {
            type: "pointerMove",
            duration: 0,
            origin: "viewport",
            x: Math.round(rect.x + xOffset),
            y: Math.round(rect.y + yOffset),
          },
          { type: "pointerDown", button: 0 },
          { type: "pointerUp", button: 0 },
        ],
      }],
    },
  });
}

async function scrollViewport(baseUrl, sessionId, deltaY) {
  await webdriverRequest(baseUrl, sessionPath(sessionId, "/actions"), {
    method: "POST",
    body: {
      actions: [{
        type: "wheel",
        id: "viewport-scroll",
        actions: [{
          type: "scroll",
          duration: 0,
          origin: "viewport",
          x: 1000,
          y: 1200,
          deltaX: 0,
          deltaY,
        }],
      }],
    },
  });
}

async function invokeYoutubeCanaryBridge(
  baseUrl,
  sessionId,
  action,
  videoId = "",
) {
  const result = await execute(
    baseUrl,
    sessionId,
    `
const body = document.body;
if (!body ||
    body.getAttribute("data-release-canary-youtube-bridge") !== "ready") {
  return { available: false, result: null };
}
body.setAttribute("data-release-canary-youtube-action", arguments[0]);
body.setAttribute("data-release-canary-youtube-video-id", arguments[1]);
body.setAttribute("data-release-canary-youtube-action-result", "pending");
window.dispatchEvent(
  new Event("mercedes-release-canary-youtube-action")
);
return {
  available: true,
  result: body.getAttribute("data-release-canary-youtube-action-result")
};
`,
    [action, videoId],
  );
  if (!result?.available) {
    throw new Error("Emulator-only YouTube action bridge was unavailable");
  }
  if (result.result !== "accepted") {
    throw new Error(
      `YouTube action bridge rejected ${action} for ${videoId}`,
    );
  }
}

async function waitForYoutubeBridgeAttachment(
  baseUrl,
  sessionId,
  expectedVideoId,
) {
  let lastState;
  await waitFor(
    async () => {
      lastState = await execute(
        baseUrl,
        sessionId,
        `
const body = document.body;
return body ? {
  bridge: body.getAttribute("data-release-canary-youtube-bridge"),
  result: body.getAttribute("data-release-canary-youtube-action-result"),
  attachedVideoId: body.getAttribute(
    "data-release-canary-youtube-attached-video-id"
  )
} : null;
`,
      );
      return lastState?.bridge === "ready" &&
        lastState?.result === "accepted" &&
        lastState?.attachedVideoId === expectedVideoId;
    },
    `bridge-attached YouTube video ${expectedVideoId}`,
    30000,
  ).catch((error) => {
    throw new Error(
      `${error.message} Last bridge state: ${JSON.stringify(lastState)}`,
    );
  });
  console.log(
    `YouTube bridge attached state: ${JSON.stringify(lastState)}`,
  );
}

async function typeIntoElement(
  baseUrl,
  sessionId,
  element,
  value,
  { replace = false, submit = false } = {},
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
  if (replace) {
    await webdriverRequest(
      baseUrl,
      sessionPath(sessionId, `/element/${activeId}/value`),
      {
        method: "POST",
        body: {
          text: "\uE009a\uE000\uE003",
          value: ["\uE009", "a", "\uE000", "\uE003"],
        },
      },
    );
  }
  if (value) {
    await webdriverRequest(
      baseUrl,
      sessionPath(sessionId, `/element/${activeId}/value`),
      {
        method: "POST",
        body: { text: value, value: [...value] },
      },
    );
  }
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

async function waitForReleaseCanaryAuthBridge(baseUrl, sessionId) {
  await waitFor(
    () => execute(
      baseUrl,
      sessionId,
      `return document.body?.getAttribute(
        "data-release-canary-auth-bridge"
      ) === "ready";`,
    ),
    "release canary authentication bridge",
  );
}

async function invokeReleaseCanaryAuthBridge(
  baseUrl,
  sessionId,
  email,
  password,
) {
  const result = await execute(
    baseUrl,
    sessionId,
    `
const body = document.body;
if (!body ||
    body.getAttribute("data-release-canary-auth-bridge") !== "ready") {
  return { available: false, result: null };
}
body.setAttribute("data-release-canary-auth-email", arguments[0]);
body.setAttribute("data-release-canary-auth-password", arguments[1]);
body.setAttribute("data-release-canary-auth-result", "pending");
try {
  window.dispatchEvent(new Event("mercedes-release-canary-authenticate"));
  return {
    available: true,
    result: body.getAttribute("data-release-canary-auth-result")
  };
} finally {
  body.removeAttribute("data-release-canary-auth-email");
  body.removeAttribute("data-release-canary-auth-password");
}
`,
    [email, password],
  );
  if (!result?.available) {
    throw new Error("Release canary authentication bridge was unavailable");
  }
  if (result.result !== "accepted") {
    throw new Error("Release canary authentication bridge rejected sign-in");
  }
}

async function authenticationDiagnostics(baseUrl, sessionId) {
  const url = await currentUrl(baseUrl, sessionId).catch(() => "unavailable");
  const state = await execute(
    baseUrl,
    sessionId,
    `
const body = document.body;
return body ? {
  bridge: body.getAttribute("data-release-canary-auth-bridge"),
  bridgeResult: body.getAttribute("data-release-canary-auth-result"),
  signInState: body.getAttribute("data-release-canary-auth-state"),
  email: body.getAttribute("data-browser-smoke-authenticated"),
  workspace: body.getAttribute("data-browser-smoke-workspace"),
  identity: body.getAttribute("data-browser-smoke-account-identity"),
  visibleError: Array.from(
    body.querySelectorAll('[role="alert"], [aria-live="polite"]')
  ).map((element) => element.textContent || "")
    .find((text) => /sign-in failed/i.test(text)) || null
} : null;
`,
  ).catch(() => null);
  return { url, state };
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

async function assertAccessibleControls(baseUrl, sessionId, surface) {
  for (const expected of surface.expectedControls || []) {
    const element = await waitFor(
      () => findByAriaLabel(baseUrl, sessionId, expected.label),
      `${surface.label} '${expected.label}' control`,
    );
    const state = await execute(
      baseUrl,
      sessionId,
      `
const element = arguments[0];
return {
  disabled: element.getAttribute("aria-disabled") === "true" ||
    element.hasAttribute("disabled")
};
`,
      [element],
    );
    if (state?.disabled !== expected.disabled) {
      throw new Error(
        `${surface.label} '${expected.label}' disabled state was ` +
        `'${state?.disabled}', expected '${expected.disabled}'`,
      );
    }
  }
}

async function waitForExerciseVersion(
  firestore,
  versionNumber,
  expectedVideo,
) {
  return waitFor(async () => {
    const header = await firestore
      .collection("exerciseTemplates")
      .doc(CANARY_IDS.exerciseTemplate)
      .get();
    if (header.data()?.currentVersion !== versionNumber) {
      return false;
    }
    const version = await header.ref
      .collection("exerciseVersions")
      .doc(String(versionNumber))
      .get();
    const data = version.data();
    if (!data) {
      return false;
    }
    const expectedUrl =
      `https://www.youtube.com/watch?v=${expectedVideo.videoId}`;
    if (data.videoUrl !== expectedUrl ||
        data.youtubeMetadata?.videoId !== expectedVideo.videoId ||
        data.youtubeMetadata?.title !== expectedVideo.title ||
        data.youtubeMetadata?.thumbnailUrl !== "" ||
        data.youtubeMetadata?.channelId !== "UCaaaaaaaaaaaaaaaaaaaaaa" ||
        data.youtubeMetadata?.channelTitle !==
          "Release Canary Public Channel" ||
        data.youtubeMetadata?.canonicalUrl !== expectedUrl) {
      throw new Error(
        `Exercise version ${versionNumber} did not persist equivalent ` +
        "canonical YouTube metadata",
      );
    }
    return true;
  }, `exercise version ${versionNumber} YouTube metadata`, 30000);
}

async function openYoutubeEditor(baseUrl, sessionId) {
  await execute(
    baseUrl,
    sessionId,
    "window.location.hash = arguments[0]; return true;",
    [`/exercises/${CANARY_IDS.exerciseTemplate}/edit`],
  );
  await activateFlutterSemantics(baseUrl, sessionId);
  return waitFor(
    () => findByAriaLabel(baseUrl, sessionId, "Public channel"),
    "public YouTube channel field",
  );
}

async function reopenYoutubeEditor(baseUrl, sessionId) {
  await execute(
    baseUrl,
    sessionId,
    "window.location.hash = arguments[0]; return true;",
    ["/trainer/exercises"],
  );
  await waitFor(
    async () =>
      !(await findByAriaLabel(baseUrl, sessionId, "Public channel")),
    "exercise editor to close before reopen",
  );
  return openYoutubeEditor(baseUrl, sessionId);
}

async function loadFakeYoutubeChannel(
  baseUrl,
  sessionId,
  channelField,
  search,
) {
  await typeIntoElement(
    baseUrl,
    sessionId,
    channelField,
    "@release.canary",
    { replace: true, submit: true },
  );
  const searchField = await waitFor(
    () => findByAriaLabel(baseUrl, sessionId, "Search complete catalogue"),
    "complete-catalogue YouTube video search",
  );
  await waitFor(async () => {
    const [progress, freshness] = await Promise.all([
      findByAriaLabel(baseUrl, sessionId, "3 videos indexed"),
      findByAriaLabel(baseUrl, sessionId, "Catalogue is fresh."),
    ]);
    return Boolean(progress && freshness);
  }, "completed and fresh fake YouTube catalogue");
  if (search) {
    await invokeYoutubeCanaryBridge(
      baseUrl,
      sessionId,
      "clear-search",
    );
    await typeIntoElement(baseUrl, sessionId, searchField, search);
  }
  return searchField;
}

async function runYoutubeExerciseFlow({
  baseUrl,
  sessionId,
  firestore,
  artifactDirectory,
}) {
  let channelField = await openYoutubeEditor(baseUrl, sessionId);
  const searchField = await loadFakeYoutubeChannel(
    baseUrl,
    sessionId,
    channelField,
    "",
  );
  const squatBeforeSort = await waitFor(
    () => findByAriaLabel(
      baseUrl,
      sessionId,
      "YouTube video Release Canary Squat",
    ),
    "public YouTube squat video",
  );
  const deadliftBeforeSort = await waitFor(
    () => findByAriaLabel(
      baseUrl,
      sessionId,
      "YouTube video Release Canary Deadlift",
    ),
    "public YouTube deadlift video",
  );
  const squatBeforeRect = await elementRect(baseUrl, sessionId, squatBeforeSort);
  const deadliftBeforeRect = await elementRect(
    baseUrl,
    sessionId,
    deadliftBeforeSort,
  );
  if (squatBeforeRect.y <= deadliftBeforeRect.y) {
    throw new Error("Newest sort did not place the newer video first");
  }
  await clickAtOffset(
    baseUrl,
    sessionId,
    searchField,
    searchField ? 660 : 0,
    20,
  );
  await waitFor(async () => {
    const squat = await findByAriaLabel(
      baseUrl,
      sessionId,
      "YouTube video Release Canary Squat",
    );
    const deadlift = await findByAriaLabel(
      baseUrl,
      sessionId,
      "YouTube video Release Canary Deadlift",
    );
    if (!squat || !deadlift) return false;
    const squatRect = await elementRect(baseUrl, sessionId, squat);
    const deadliftRect = await elementRect(baseUrl, sessionId, deadlift);
    return squatRect.y < deadliftRect.y;
  }, "view-count sorted complete catalogue");
  await typeIntoElement(baseUrl, sessionId, searchField, "Squat");
  await waitFor(
    () => findByAriaLabel(
      baseUrl,
      sessionId,
      "YouTube video Release Canary Squat",
    ),
    "draggable public YouTube video",
  );
  await invokeYoutubeCanaryBridge(
    baseUrl,
    sessionId,
    "drag-attach",
    "canaryVid02",
  );
  await waitForYoutubeBridgeAttachment(
    baseUrl,
    sessionId,
    "canaryVid02",
  );
  await saveScreenshot(
    baseUrl,
    sessionId,
    artifactDirectory,
    "trainer-exercise-youtube-drag.png",
  );
  await invokeYoutubeCanaryBridge(baseUrl, sessionId, "save");
  await waitForExerciseVersion(firestore, 2, {
    videoId: "canaryVid02",
    title: "Release Canary Squat",
  });

  channelField = await reopenYoutubeEditor(baseUrl, sessionId);
  await loadFakeYoutubeChannel(baseUrl, sessionId, channelField, "");
  await waitFor(
    () => findByAriaLabel(
      baseUrl,
      sessionId,
      "Attached YouTube video Release Canary Squat",
    ),
    "reopened persisted YouTube thumbnail metadata",
  );
  await scrollViewport(baseUrl, sessionId, 600);
  await saveScreenshot(
    baseUrl,
    sessionId,
    artifactDirectory,
    "trainer-exercise-youtube-reopened.png",
  );

  await invokeYoutubeCanaryBridge(
    baseUrl,
    sessionId,
    "clear-search",
  );
  await invokeYoutubeCanaryBridge(
    baseUrl,
    sessionId,
    "select-attach",
    "canaryVid03",
  );
  await waitForYoutubeBridgeAttachment(
    baseUrl,
    sessionId,
    "canaryVid03",
  );
  await saveScreenshot(
    baseUrl,
    sessionId,
    artifactDirectory,
    "trainer-exercise-youtube-select.png",
  );
  await invokeYoutubeCanaryBridge(baseUrl, sessionId, "save");
  await waitForExerciseVersion(firestore, 3, {
    videoId: "canaryVid03",
    title: "Release Canary Press",
  });
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

  await waitForReleaseCanaryAuthBridge(baseUrl, sessionId);
  await invokeReleaseCanaryAuthBridge(
    baseUrl,
    sessionId,
    email,
    password,
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
  }, `${role} authentication and header identity`).catch(async (error) => {
    const diagnostics = await authenticationDiagnostics(baseUrl, sessionId);
    throw new Error(
      `${error.message} Authentication diagnostics: ` +
      JSON.stringify(diagnostics),
    );
  });
  await activateFlutterSemantics(baseUrl, sessionId);
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
  emulatorAdmin,
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
              "--window-size=1280,1600",
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
    const expectedSurfaces = role === "trainer"
      ? EXPECTED_TRAINER_SURFACES
      : EXPECTED_ATHLETE_SURFACES;
    for (const surface of expectedSurfaces) {
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
        if (/permission-denied|something went wrong|unable to load|error:|no .* yet|unavailable/i
          .test(state?.text || "")) {
          throw new Error(`${surface.label} rendered an error state`);
        }
        return state?.state === "ready";
      }, `${surface.label} populated backend state`);
      await assertAccessibleControls(baseUrl, sessionId, surface);
      await assertRoute(baseUrl, sessionId, surface.route);
      await saveScreenshot(
        baseUrl,
        sessionId,
        artifactDirectory,
        surface.screenshot,
      );
    }
    if (role === "trainer" && emulatorAdmin) {
      await runYoutubeExerciseFlow({
        baseUrl,
        sessionId,
        firestore: emulatorAdmin.firestore,
        artifactDirectory,
      });
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
  const emulatorAdmin = emulator ? createAdminContext({
    root: context.root,
    projectId: context.projectId,
    hostingUrl: context.hostingUrl,
    appUrl,
    emulator: true,
  }) : null;
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
      emulatorAdmin,
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
      emulatorAdmin: null,
    });
    console.log(
      `Deployed release canary passed for ` +
      `${context.environment}/${context.projectId}.`,
    );
  } finally {
    if (emulatorAdmin) {
      const versions = emulatorAdmin.firestore
        .collection("exerciseTemplates")
        .doc(CANARY_IDS.exerciseTemplate)
        .collection("exerciseVersions");
      await Promise.all([
        versions.doc("2").delete(),
        versions.doc("3").delete(),
      ]);
      await emulatorAdmin.app.delete();
    }
    if (!driver.killed) {
      driver.kill();
    }
    if (driver.exitCode && driver.exitCode !== 0 && driverError) {
      console.error(driverError.trim());
    }
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`Deployed release canary failed: ${error.message}`);
    process.exitCode = 1;
  });
}

module.exports = {
  invokeReleaseCanaryAuthBridge,
};
