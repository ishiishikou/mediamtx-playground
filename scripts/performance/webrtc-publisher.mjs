import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const scenarioId = process.env.PERF_SCENARIO_ID || 'P01_WEBRTC_1';
const clients = Number(process.env.PERF_CLIENTS || '1');
const durationSeconds = Number(process.env.PERF_DURATION_SECONDS || '60');
const statsIntervalSeconds = Number(process.env.PERF_STATS_INTERVAL_SECONDS || '5');
const startStaggerMs = Number(process.env.PERF_CLIENT_START_STAGGER_MS || '250');
const inputY4m = process.env.PERF_INPUT_Y4M;
const outputDir = process.env.PERF_CASE_DIR || 'tmp/performance-results/manual';
const pathPrefix = process.env.PERF_PATH_PREFIX || 'live/perf';
const appUrl = process.env.PERF_APP_URL || '';
const resultEventName = process.env.PERF_RESULT_EVENT_NAME || 'perf:inference-result';
const webRtcBase = process.env.WEBRTC_BASE_URL || 'http://127.0.0.1:8889';
const publishUser = process.env.PUBLISH_USER || 'poc-publisher';
const publishPass = process.env.PUBLISH_PASS || 'poc-publisher-pass';
const headless = process.env.PERF_HEADLESS !== '0';
const timeoutMs = Number(process.env.PERF_START_TIMEOUT_MS || '30000');

if (!inputY4m || !fs.existsSync(inputY4m)) {
  throw new Error(`PERF_INPUT_Y4M is required and must exist: ${inputY4m || '(empty)'}`);
}
if (!Number.isFinite(clients) || clients < 1) {
  throw new Error(`PERF_CLIENTS must be >= 1: ${clients}`);
}

fs.mkdirSync(outputDir, { recursive: true });
const eventsPath = path.join(outputDir, 'browser-events.jsonl');
const statsPath = path.join(outputDir, 'webrtc-stats.csv');
const resultsPath = path.join(outputDir, 'result-events.csv');

const csv = (value) => {
  if (value === undefined || value === null) return '';
  const text = String(value);
  return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
};
const appendEvent = (event) => {
  fs.appendFileSync(eventsPath, `${JSON.stringify({ scenario_id: scenarioId, ...event })}\n`);
};
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

fs.writeFileSync(
  statsPath,
  'timestamp_ms,scenario_id,client_id,stat_id,kind,frames_encoded,frames_sent,frames_per_second,packets_sent,bytes_sent,total_encode_time,quality_limitation_reason\n',
);
fs.writeFileSync(
  resultsPath,
  'scenario_id,client_id,frame_id,source_ts_ms,server_receive_ts_ms,inference_start_ts_ms,inference_end_ts_ms,result_send_ts_ms,browser_receive_ts_ms,browser_render_ts_ms,class_count,detection_count,payload_json\n',
);

const browser = await chromium.launch({
  headless,
  args: [
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--use-fake-device-for-media-stream',
    '--use-fake-ui-for-media-stream',
    `--use-file-for-fake-video-capture=${path.resolve(inputY4m)}`,
    '--autoplay-policy=no-user-gesture-required',
    '--disable-background-timer-throttling',
    '--disable-renderer-backgrounding',
    '--disable-backgrounding-occluded-windows',
  ],
});

const sessions = [];
let sampleTimer;
let sampleInProgress = false;

async function preparePage(clientIndex) {
  const clientId = `webrtc-${String(clientIndex).padStart(3, '0')}`;
  const streamPath = `${pathPrefix}/${scenarioId.toLowerCase()}/${clientId}`;
  const context = await browser.newContext({
    permissions: ['camera', 'microphone'],
    ignoreHTTPSErrors: true,
    httpCredentials: { username: publishUser, password: publishPass },
  });

  await context.addInitScript(({ eventName }) => {
    window.__perfResults = [];
    window.__perfPeerConnections = [];
    window.__perfEmitResult = (detail = {}) => {
      const browserReceiveTsMs = performance.timeOrigin + performance.now();
      requestAnimationFrame(() => {
        const browserRenderTsMs = performance.timeOrigin + performance.now();
        window.__perfResults.push({
          ...detail,
          browser_receive_ts_ms: browserReceiveTsMs,
          browser_render_ts_ms: browserRenderTsMs,
        });
      });
    };
    window.addEventListener(eventName, (event) => window.__perfEmitResult(event.detail || {}));
  }, { eventName: resultEventName });

  const page = await context.newPage();
  page.on('console', (message) => appendEvent({
    timestamp_ms: Date.now(), client_id: clientId, type: `console:${message.type()}`, message: message.text(),
  }));
  page.on('pageerror', (error) => appendEvent({
    timestamp_ms: Date.now(), client_id: clientId, type: 'pageerror', message: error.message,
  }));
  page.on('crash', () => appendEvent({
    timestamp_ms: Date.now(), client_id: clientId, type: 'page-crash', message: 'page crashed',
  }));

  const startedAt = Date.now();
  appendEvent({ timestamp_ms: startedAt, client_id: clientId, type: 'start-requested', stream_path: streamPath });

  if (appUrl) {
    await page.goto(appUrl, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
    const hookResult = await page.evaluate(async ({ clientId, streamPath, scenarioId }) => {
      if (typeof window.__PERF_START_PUBLISH !== 'function') {
        throw new Error('PERF_APP_URL requires window.__PERF_START_PUBLISH(options)');
      }
      return window.__PERF_START_PUBLISH({ clientId, streamPath, scenarioId });
    }, { clientId, streamPath, scenarioId });
    appendEvent({ timestamp_ms: Date.now(), client_id: clientId, type: 'app-publish-started', hook_result: hookResult });
  } else {
    await page.goto(`${webRtcBase}/`, { waitUntil: 'domcontentloaded', timeout: timeoutMs }).catch(() => undefined);
    const result = await page.evaluate(async ({ webRtcBase, streamPath, publishUser, publishPass }) => {
      const mediaStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
      const pc = new RTCPeerConnection();
      window.__perfPeerConnections.push(pc);
      for (const track of mediaStream.getTracks()) pc.addTrack(track, mediaStream);

      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await new Promise((resolve) => {
        if (pc.iceGatheringState === 'complete') return resolve();
        const timer = setTimeout(resolve, 5000);
        pc.addEventListener('icegatheringstatechange', () => {
          if (pc.iceGatheringState === 'complete') {
            clearTimeout(timer);
            resolve();
          }
        });
      });

      const auth = btoa(`${publishUser}:${publishPass}`);
      const response = await fetch(`${webRtcBase}/${streamPath}/whip`, {
        method: 'POST',
        headers: {
          Authorization: `Basic ${auth}`,
          'Content-Type': 'application/sdp',
        },
        body: pc.localDescription.sdp,
      });
      const answer = await response.text();
      if (!response.ok) throw new Error(`WHIP failed: ${response.status} ${answer}`);
      await pc.setRemoteDescription({ type: 'answer', sdp: answer });
      window.__perfMediaStream = mediaStream;
      return { responseStatus: response.status, tracks: mediaStream.getTracks().map((track) => track.kind) };
    }, { webRtcBase, streamPath, publishUser, publishPass });
    appendEvent({ timestamp_ms: Date.now(), client_id: clientId, type: 'whip-connected', ...result });
  }

  return { clientId, streamPath, context, page, startedAt };
}

async function sampleStats() {
  if (sampleInProgress) return;
  sampleInProgress = true;
  try {
    const timestampMs = Date.now();
    for (const session of sessions) {
      const reports = await session.page.evaluate(async () => {
        const output = [];
        for (const pc of window.__perfPeerConnections || []) {
          const stats = await pc.getStats();
          stats.forEach((report) => {
            if (report.type === 'outbound-rtp' && report.kind === 'video') {
              output.push({
                id: report.id,
                kind: report.kind,
                framesEncoded: report.framesEncoded,
                framesSent: report.framesSent,
                framesPerSecond: report.framesPerSecond,
                packetsSent: report.packetsSent,
                bytesSent: report.bytesSent,
                totalEncodeTime: report.totalEncodeTime,
                qualityLimitationReason: report.qualityLimitationReason,
              });
            }
          });
        }
        return output;
      }).catch((error) => {
        appendEvent({ timestamp_ms: timestampMs, client_id: session.clientId, type: 'stats-error', message: error.message });
        return [];
      });

      for (const report of reports) {
        fs.appendFileSync(statsPath, [
          timestampMs, scenarioId, session.clientId, report.id, report.kind,
          report.framesEncoded, report.framesSent, report.framesPerSecond,
          report.packetsSent, report.bytesSent, report.totalEncodeTime,
          report.qualityLimitationReason,
        ].map(csv).join(',') + '\n');
      }
    }
  } finally {
    sampleInProgress = false;
  }
}

async function flushResults(session) {
  const rows = await session.page.evaluate(() => window.__perfResults || []).catch(() => []);
  for (const row of rows) {
    const detections = Array.isArray(row.detections) ? row.detections : [];
    const classCount = new Set(detections.map((item) => item.class ?? item.class_name).filter(Boolean)).size;
    fs.appendFileSync(resultsPath, [
      scenarioId,
      session.clientId,
      row.frame_id,
      row.source_ts_ms,
      row.server_receive_ts_ms,
      row.inference_start_ts_ms,
      row.inference_end_ts_ms,
      row.result_send_ts_ms,
      row.browser_receive_ts_ms,
      row.browser_render_ts_ms,
      classCount,
      detections.length,
      JSON.stringify(row),
    ].map(csv).join(',') + '\n');
  }
  return rows.length;
}

try {
  for (let index = 1; index <= clients; index += 1) {
    sessions.push(await preparePage(index));
    if (index < clients) await sleep(startStaggerMs);
  }

  await sampleStats();
  sampleTimer = setInterval(sampleStats, Math.max(1, statsIntervalSeconds) * 1000);
  await sleep(durationSeconds * 1000);
  clearInterval(sampleTimer);
  await sampleStats();

  let resultCount = 0;
  for (const session of sessions) resultCount += await flushResults(session);

  const completedAt = Date.now();
  const summary = {
    scenario_id: scenarioId,
    protocol: 'webrtc',
    requested_clients: clients,
    connected_clients: sessions.length,
    failed_clients: clients - sessions.length,
    duration_seconds: durationSeconds,
    result_event_count: resultCount,
    mode: appUrl ? 'application-hook' : 'direct-whip',
    app_url_configured: Boolean(appUrl),
    started_at_ms: Math.min(...sessions.map((session) => session.startedAt)),
    completed_at_ms: completedAt,
  };
  fs.writeFileSync(path.join(outputDir, 'webrtc-summary.json'), `${JSON.stringify(summary, null, 2)}\n`);
  appendEvent({ timestamp_ms: completedAt, type: 'scenario-completed', ...summary });
} catch (error) {
  appendEvent({ timestamp_ms: Date.now(), type: 'scenario-failed', message: error.stack || error.message });
  throw error;
} finally {
  if (sampleTimer) clearInterval(sampleTimer);
  for (const session of sessions) await session.context.close().catch(() => undefined);
  await browser.close();
}
