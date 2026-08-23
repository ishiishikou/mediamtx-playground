# CDP Smoke Test

Disposable smoke test for the following path only:

```text
Windows Chrome
  -> chrome://inspect
  -> CDP 127.0.0.1:9222
  -> WSL2
  -> Docker published port 9222
  -> socat relay 0.0.0.0:9223
  -> Chromium CDP 127.0.0.1:9222
  -> Playwright
  -> headless Chromium
```

MediaMTX, WebRTC, DNS, and external web sites are not used.

Headless Chromium in this image binds the CDP endpoint to container loopback (`127.0.0.1:9222`). Docker port publishing cannot directly reach that loopback listener, so this example relays `0.0.0.0:9223` to `127.0.0.1:9222` with `socat`.

## Device emulation

The default device is **Pixel 10**.

The smoke test uses the Chromium DevTools Pixel 10 profile values:

- viewport: `412 x 924` CSS px
- device pixel ratio: `2.625`
- mobile rendering: enabled
- touch: enabled
- user agent: Android 16 / Pixel 10

Set `DEVICE=desktop` to disable mobile emulation.

## Run from WSL

```bash
cd examples/cdp-smoke

docker build -t cdp-smoke .
docker run --rm --init --ipc=host \
  -p 127.0.0.1:9222:9223 \
  cdp-smoke
```

Explicit Pixel 10 example:

```bash
docker run --rm --init --ipc=host \
  -e DEVICE="Pixel 10" \
  -p 127.0.0.1:9222:9223 \
  cdp-smoke
```

Desktop example:

```bash
docker run --rm --init --ipc=host \
  -e DEVICE=desktop \
  -p 127.0.0.1:9222:9223 \
  cdp-smoke
```

The container logs should show the selected device, viewport, DPR, and an incrementing counter once per second.

## Verify inside the container if needed

```bash
docker exec <container> curl -sS http://127.0.0.1:9222/json/version
docker exec <container> curl -sS http://127.0.0.1:9223/json/version
```

Both should return the Chromium version JSON. The first accesses Chromium directly; the second accesses it through the `socat` relay.

## Verify from Windows PowerShell

```powershell
Invoke-RestMethod http://127.0.0.1:9222/json/version
Invoke-RestMethod http://127.0.0.1:9222/json/list
```

`/json/list` should include a page whose title is `CDP Smoke Test`.

## Verify with Chrome DevTools

1. Open `chrome://inspect/#devices` on Windows.
2. Open `Configure...`.
3. Add `127.0.0.1:9222`.
4. If the target is not listed, get `devtoolsFrontendUrl` from `/json/list` and open it directly.
5. Confirm that the screencast shows the Pixel 10-sized page.
6. In DevTools Console, run:

```javascript
window.innerWidth
window.innerHeight
window.devicePixelRatio
navigator.userAgent
```

For Pixel 10, the expected viewport is `412 x 924` with DPR `2.625`.

## Remove

This test is intentionally self-contained. Remove the entire directory when it is no longer needed:

```bash
rm -rf examples/cdp-smoke
```
