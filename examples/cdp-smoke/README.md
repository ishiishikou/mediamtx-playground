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

## Run from WSL

```bash
cd examples/cdp-smoke

docker build -t cdp-smoke .
docker run --rm --init --ipc=host \
  -p 127.0.0.1:9222:9223 \
  cdp-smoke
```

The container logs should show an incrementing counter once per second.

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
4. Confirm that `CDP Smoke Test` appears under Remote Target.
5. Click `inspect`.
6. In DevTools Console, run:

```javascript
document.querySelector('#count').textContent
```

Run it again a few seconds later. The value should have increased because Playwright clicks the button once per second inside the headless Chromium instance.

## Remove

This test is intentionally self-contained. Remove the entire directory when it is no longer needed:

```bash
rm -rf examples/cdp-smoke
```
