import { chromium } from 'playwright';

const apiBase = process.env.MTX_API_URL || 'http://127.0.0.1:9997';
const webRtcBase = process.env.WEBRTC_BASE_URL || 'http://127.0.0.1:8889';
const pathName = process.env.WEBRTC_PUBLISH_PATH || 'live/poc-webrtc-ci';
const publishUser = process.env.PUBLISH_USER || 'poc-publisher';
const publishPass = process.env.PUBLISH_PASS || 'poc-publisher-pass';
const timeoutMs = Number(process.env.WEBRTC_CHECK_TIMEOUT_MS || '30000');
const keepAliveMs = Number(process.env.WEBRTC_KEEP_ALIVE_MS || '0');
const mediaSource = process.env.WEBRTC_MEDIA_SOURCE || 'device';
const requireRtp = process.env.WEBRTC_REQUIRE_RTP === '1';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function getJson(endpoint) {
  const response = await fetch(`${apiBase}${endpoint}`);
  if (!response.ok) {
    throw new Error(`${endpoint} returned ${response.status}`);
  }
  return response.json();
}

function hasRtpPackets(sessions) {
  const items = sessions?.items || [];
  return items.some((item) => item.path === pathName && Number(item.rtpPacketsReceived || item.inboundRTPPackets || 0) > 0);
}

async function findPublishedPath() {
  const paths = await getJson('/v3/paths/list');
  const sessions = await getJson('/v3/webrtcsessions/list');
  const text = JSON.stringify({ paths, sessions });
  if (!text.includes(pathName)) {
    return null;
  }
  if (requireRtp && !hasRtpPackets(sessions)) {
    return null;
  }
  return { paths, sessions };
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
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--use-fake-device-for-media-stream',
    '--use-fake-ui-for-media-stream',
    '--autoplay-policy=no-user-gesture-required',
  ],
});

try {
  const context = await browser.newContext({
    permissions: ['camera', 'microphone'],
    httpCredentials: {
      username: publishUser,
      password: publishPass,
    },
  });
  const page = await context.newPage();

  page.on('console', (message) => console.log(`[browser:${message.type()}] ${message.text()}`));
  page.on('pageerror', (error) => console.log(`[browser:error] ${error.message}`));

  await page.goto(`${webRtcBase}/`, { waitUntil: 'domcontentloaded', timeout: timeoutMs }).catch(() => undefined);

  const publishResult = await page.evaluate(async ({ webRtcBase, pathName, mediaSource }) => {
    async function createMediaStream() {
      if (mediaSource === 'canvas') {
        const canvas = document.createElement('canvas');
        canvas.width = 640;
        canvas.height = 360;
        const ctx = canvas.getContext('2d');
        let frame = 0;

        function draw() {
          const t = frame / 30;
          ctx.fillStyle = '#101820';
          ctx.fillRect(0, 0, canvas.width, canvas.height);

          const x = Math.round((canvas.width - 140) * ((Math.sin(t) + 1) / 2));
          ctx.fillStyle = '#00d4ff';
          ctx.fillRect(x, 80, 140, 80);

          ctx.fillStyle = '#ffb000';
          ctx.fillRect(canvas.width - x - 140, 210, 140, 80);

          ctx.fillStyle = '#ffffff';
          ctx.font = '28px sans-serif';
          ctx.fillText('MediaMTX WebRTC CI video', 40, 48);
          ctx.font = '20px sans-serif';
          ctx.fillText(`frame ${frame}`, 40, 330);
          frame += 1;
        }

        draw();
        const timer = setInterval(draw, 1000 / 30);
        const stream = canvas.captureStream(30);
        window.__canvasTimer = timer;
        return stream;
      }

      return navigator.mediaDevices.getUserMedia({ video: true, audio: true });
    }

    const stream = await createMediaStream();
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

    const endpoint = `${webRtcBase}/${pathName}/whip`;
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
      mediaSource,
    };
  }, { webRtcBase, pathName, mediaSource });

  console.log(`Browser media source: ${publishResult.mediaSource}`);
  console.log(`Browser media tracks: ${publishResult.tracks.join(', ')}`);
  console.log(`WHIP response status: ${publishResult.responseStatus}`);

  const result = await waitForPublishedPath();
  console.log(`WebRTC publish confirmed: ${pathName}`);
  console.log(JSON.stringify(result, null, 2));

  if (keepAliveMs > 0) {
    console.log(`Keeping WebRTC publisher alive for ${keepAliveMs}ms`);
    await sleep(keepAliveMs);
  }
} finally {
  await browser.close();
}
