# CDP Smoke Test

Disposable smoke test for the following path only:

```text
Windows Chrome
  -> chrome://inspect
  -> CDP 127.0.0.1:9222
  -> WSL2
  -> Docker
  -> Playwright
  -> headless Chromium
```

MediaMTX, WebRTC, DNS, and external web sites are not used.

## Run from WSL

```bash
cd examples/cdp-smoke

docker build -t cdp-smoke .
docker run --rm --init --ipc=host \
  -p 127.0.0.1:9222:9222 \
  cdp-smoke
```

The container logs should show an incrementing counter once per second.

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
