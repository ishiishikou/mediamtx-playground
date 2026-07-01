import { chromium } from 'playwright';

const apiBase = process.env.MTX_API_URL || 'http://127.0.0.1:9997';
const webRtcBase = process.env.WEBRTC_BASE_URL || 'http://127.0.0.1:8889';
const pathName = process.env.WEBRTC_PUBLISH_PATH || 'live/poc-webrtc-ci';
const publishUser = process.env.PUBLISH_USER || 'poc-publisher';
const publishPass = process.env.PUBLISH_PASS || 'poc-publisher-pass';
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

async function waitForPublishedPath() {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    const result = await findPublishedPath();
    if (result) {
      return result;
    }
    await sleep(1000);
  }
  throw new Error(`WebRTC publish path was not found: ${pathName}`);
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

  await page.goto(`${webRtcBase}/`, { waitUntil: 'domcontentloaded', timeout: timeoutMs }).catch(() => undefined);

  const publishResult = await page.evaluate(async ({ webRtcBase, pathName, publishUser, publishPass }) => {
    const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
    const pc = new RTCPeerConnection();

    for (const track of stream.getTracks()) {
      pc.addTrack(track, stream);
    }

    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    await new Promise((resolve) => {
      if (pc.iceGatheringState === 'complete') {
        resolve();
        return;
      }
      const timer = setTimeout(resolve, 5000);
      pc.addEventListener('icegatheringstatechange', () => {
        if (pc.iceGatheringState === 'complete') {
          clearTimeout(timer);
          resolve();
        }
      });
    });

    const endpoint = `${webRtcBase}/${pathName}/whip?user=${encodeURIComponent(publishUser)}&pass=${encodeURIComponent(publishPass)}`;
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/sdp' },
      body: pc.localDescription.sdp,
    });

    const answer = await response.text();
    if (!response.ok) {
      throw new Error(`WHIP publish failed: ${response.status} ${answer}`);
    }

    await pc.setRemoteDescription({ type: 'answer', sdp: answer });
    window.__mediamtxPublisher = { pc, stream };

    return {
      tracks: stream.getTracks().map((track) => `${track.kind}:${track.readyState}`),
      responseStatus: response.status,
    };
  }, { webRtcBase, pathName, publishUser, publishPass });

  console.log(`Browser media tracks: ${publishResult.tracks.join(', ')}`);
  console.log(`WHIP response status: ${publishResult.responseStatus}`);

  const result = await waitForPublishedPath();
  console.log(`WebRTC publish confirmed: ${pathName}`);
  console.log(JSON.stringify(result, null, 2));
} finally {
  await browser.close();
}
