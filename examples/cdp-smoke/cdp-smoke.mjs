import { chromium } from 'playwright';

const browser = await chromium.launch({
  headless: true,
  args: [
    '--remote-debugging-port=9222',
    '--remote-debugging-address=0.0.0.0',
    '--remote-allow-origins=*',
  ],
});

const page = await browser.newPage();

await page.setContent(`
  <!doctype html>
  <html>
    <head>
      <meta charset="utf-8" />
      <title>CDP Smoke Test</title>
    </head>
    <body>
      <h1>Playwright + WSL + Docker + CDP</h1>
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
