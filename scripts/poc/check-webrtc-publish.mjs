import { chromium } from 'playwright';

const apiBase = process.env.MTX_API_URL || 'http://127.0.0.1:9997';
const pathName = process.env.WEBRTC_PUBLISH_PATH || 'live/poc-webrtc-ci';
const url = process.env.WEBRTC_PUBLISH_URL || `http://127.0.0.1:8889/${pathName}/publish?user=poc-publisher&pass=poc-publisher-pass`;
const timeoutMs = Number(process.env.WEBRTC_CHECK_TIMEOUT_MS || '30000');

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function getJson(endpoint) {
  const response = await fetch(`${apiBase}${endpoint}`);
  if (!response.ok) {
    throw new Error(`${endpoint} returned ${response.status}`);
  }
  return response.json();
}

async function findPublishedPath() {
  const paths = await getJson('/v3/paths/list');
  const sessions = await getJson('/v3/webrtcsessions/list');
  const text = JSON.stringify({ paths, sessions });
  return text.includes(pathName) ? { paths, sessions } : null;
}

async function clickStart(page) {
  const selectors = [
    'text=/publish|start|connect/i',
    'button',
    'input[type="button"]',
    'input[type="submit"]',
  ];

  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    if (await locator.count()) {
      try {
        await locator.click({ timeout: 3000 });
        return true;
      } catch {
        // Try next selector.
      }
    }
  }
  return false;
}

const browser = await chromium.launch({
  headless: true,
  args: [
    '--use-fake-device-for-media-stream',
    '--use-fake-ui-for-media-stream',
    '--autoplay-policy=no-user-gesture-required',
  ],
});

try {
  const context = await browser.newContext({ permissions: ['camera', 'microphone'] });
  const page = await context.newPage();

  page.on('console', (message) => console.log(`[browser:${message.type()}] ${message.text()}`));
  page.on('pageerror', (error) => console.log(`[browser:error] ${error.message}`));

  console.log(`Open ${url}`);
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: timeoutMs });

  await page.evaluate(async () => {
    const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
    window.__tracks = stream.getTracks().map((track) => `${track.kind}:${track.readyState}`);
  });
  console.log(`Fake media tracks: ${(await page.evaluate(() => window.__tracks)).join(', ')}`);

  console.log(`Clicked start control: ${await clickStart(page)}`);

  const startedAt = Date.now();
  let found = null;
  while (Date.now() - startedAt < timeoutMs) {
    found = await findPublishedPath();
    if (found) break;
    await sleep(1000);
  }

  if (!found) {
    throw new Error(`WebRTC publish path was not found: ${pathName}`);
  }

  console.log(`WebRTC publish confirmed: ${pathName}`);
  console.log(JSON.stringify(found, null, 2));
} finally {
  await browser.close();
}
