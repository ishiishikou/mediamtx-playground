import { chromium } from 'playwright';

const deviceName = process.env.DEVICE || 'Pixel 10';

function contextOptionsFor(device, browserVersion) {
  if (device.toLowerCase() === 'desktop') {
    return {};
  }

  if (device === 'Pixel 10') {
    return {
      viewport: { width: 412, height: 924 },
      screen: { width: 412, height: 924 },
      deviceScaleFactor: 2.625,
      isMobile: true,
      hasTouch: true,
      userAgent: `Mozilla/5.0 (Linux; Android 16; Pixel 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${browserVersion} Mobile Safari/537.36`,
    };
  }

  throw new Error(`Unsupported DEVICE="${device}". Supported values: "Pixel 10", "desktop".`);
}

const browser = await chromium.launch({
  headless: true,
  args: [
    '--remote-debugging-port=9222',
    '--remote-debugging-address=0.0.0.0',
    '--remote-allow-origins=*',
  ],
});

const context = await browser.newContext(contextOptionsFor(deviceName, browser.version()));
const page = await context.newPage();

await page.setContent(`
  <!doctype html>
  <html>
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>CDP Smoke Test</title>
    </head>
    <body>
      <h1>Playwright + WSL + Docker + CDP</h1>
      <p>Device: <strong id="device">${deviceName}</strong></p>
      <p>Counter: <strong id="count">0</strong></p>
      <button id="button" type="button">Playwright click</button>
      <script>
        document.querySelector('#button').addEventListener('click', () => {
          const count = document.querySelector('#count');
          count.textContent = String(Number(count.textContent) + 1);
        });
      </script>
    </body>
  </html>
`);

console.log('CDP Smoke Test started');
console.log(`Device emulation: ${deviceName}`);
console.log(`Viewport: ${await page.evaluate(() => `${window.innerWidth}x${window.innerHeight}`)}`);
console.log(`DPR: ${await page.evaluate(() => window.devicePixelRatio)}`);
console.log('Remote debugging port: 9222');
console.log('Open chrome://inspect/#devices on the Windows host');

try {
  while (true) {
    await page.click('#button');
    console.log(`count: ${await page.textContent('#count')}`);
    await page.waitForTimeout(1000);
  }
} finally {
  await browser.close();
}
