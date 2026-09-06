// Captures the example's two windows over the Chrome DevTools Protocol and
// composites them, so doc/popout.png is reproducible rather than hand-made.
//
// Why it is built this way, all of it learned by looking at the output:
//
//  * A Document Picture-in-Picture window is a real, separate browsing context
//    and turns up as its OWN CDP page target, so it can be screenshotted.
//  * Chrome does not composite a window it considers occluded, and the moment
//    the pop-out takes focus the opener usually falls behind whatever else is
//    on the desktop. Both Page.captureScreenshot and Page.startScreencast then
//    return blank frames — 291 screencast frames, every one empty. So the page
//    is captured BEFORE the pop-out exists, while it is still frontmost, and
//    the pop-out after, while it is.
//  * Which means the two shots are not simultaneous — so the animation is
//    PAUSED first. Both windows then show one frozen, shared state, and the
//    composite is honest: two real screenshots of the same app at the same
//    instant of its clock, placed where the user actually sees them.
//  * No --window-size. With it, Chrome ignores requestWindow's width and height
//    entirely and opens the pop-out at the opener's size — 380x210, 600x400 and
//    300x300 all came back as 1200x766. Without it every one is honoured, and
//    only oversized requests are clamped (1000x700 -> 866x606).
//  * No Emulation.setDeviceMetricsOverride. Flutter's web engine caches display
//    metrics, so moving the viewport under a running app leaves the page
//    painting into a stale rect and the pop-out painting nothing.
//  * Not --headless=new: it renders, but once a second window exists it clips
//    the page's surface to the pop-out's dimensions.
//
// Node 22+ only, for the built-in WebSocket. No dependencies.
import { spawn } from 'node:child_process';
import { writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const CHROME = process.env.CHROME
  ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = Number(process.env.PORT ?? 8398);
const CDP = Number(process.env.CDP_PORT ?? 9223);
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'doc', 'frames', 'popout');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class Cdp {
  #ws; #id = 0; #pending = new Map();
  static async connect(url) {
    const c = new Cdp();
    c.#ws = new WebSocket(url);
    await new Promise((res, rej) => {
      c.#ws.addEventListener('open', res, { once: true });
      c.#ws.addEventListener('error', rej, { once: true });
    });
    c.#ws.addEventListener('message', (e) => {
      const m = JSON.parse(e.data);
      const p = c.#pending.get(m.id);
      if (!p) return;
      c.#pending.delete(m.id);
      m.error ? p.reject(new Error(m.error.message)) : p.resolve(m.result);
    });
    return c;
  }
  send(method, params = {}, sessionId) {
    const id = ++this.#id;
    this.#ws.send(JSON.stringify({ id, method, params, sessionId }));
    return new Promise((resolve, reject) =>
      this.#pending.set(id, { resolve, reject }));
  }
  close() { this.#ws.close(); }
}

rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });

const profile = join(process.env.TMPDIR ?? '/tmp', `document-pip-shot-${process.pid}`);
const chrome = spawn(CHROME, [
  '--hide-scrollbars',
  '--no-first-run',
  '--no-default-browser-check',
  `--remote-debugging-port=${CDP}`,
  `--user-data-dir=${profile}`,
  `http://127.0.0.1:${PORT}/`,
], { stdio: 'ignore' });

let cdp;
try {
  let version;
  for (let i = 0; i < 80; i++) {
    try {
      version = await (await fetch(`http://127.0.0.1:${CDP}/json/version`)).json();
      break;
    } catch { await sleep(250); }
  }
  if (!version) throw new Error('Chrome never opened its debugging port');
  cdp = await Cdp.connect(version.webSocketDebuggerUrl);

  const listTargets = async () =>
    await (await fetch(`http://127.0.0.1:${CDP}/json/list`)).json();

  let pageTarget;
  for (let i = 0; i < 80; i++) {
    pageTarget = (await listTargets())
      .find((t) => t.type === 'page' && t.url.startsWith(`http://127.0.0.1:${PORT}`));
    if (pageTarget) break;
    await sleep(250);
  }
  if (!pageTarget) throw new Error('the example never loaded');
  const page = (await cdp.send('Target.attachToTarget',
    { targetId: pageTarget.id, flatten: true })).sessionId;
  await cdp.send('Runtime.enable', {}, page);
  await cdp.send('Page.enable', {}, page);

  const evalIn = async (session, expression) => {
    const r = await cdp.send('Runtime.evaluate',
      { expression, returnByValue: true, awaitPromise: true }, session);
    return r.result?.value;
  };
  const click = async (session, x, y) => {
    for (const type of ['mousePressed', 'mouseReleased']) {
      await cdp.send('Input.dispatchMouseEvent',
        { type, button: 'left', clickCount: 1, x: Math.round(x), y: Math.round(y) }, session);
    }
  };
  const shoot = async (session, file) => {
    const shot = await cdp.send('Page.captureScreenshot', { format: 'png' }, session);
    writeFileSync(file, Buffer.from(shot.data, 'base64'));
  };

  // A deterministic window, so the picture is the same on any machine. Set
  // AFTER launch on purpose: --window-size makes Chrome ignore requestWindow's
  // dimensions, Browser.setWindowBounds does not — checked, the pop-out still
  // comes back at the 380x210 the example asks for.
  const { windowId } = await cdp.send('Browser.getWindowForTarget',
    { targetId: pageTarget.id });
  await cdp.send('Browser.setWindowBounds', {
    windowId,
    bounds: { left: 60, top: 60, width: 1080, height: 640, windowState: 'normal' },
  });

  for (let i = 0; i < 80; i++) {
    if (await evalIn(page, `!!document.querySelector('#app')?.firstElementChild`)) break;
    await sleep(250);
  }
  await sleep(1800);

  const view = JSON.parse(await evalIn(page, `JSON.stringify({w: innerWidth, h: innerHeight})`));
  const dpr = await evalIn(page, 'devicePixelRatio');
  console.log(`  page viewport ${view.w}x${view.h} @${dpr}x`);
  const cx = view.w / 2, cy = view.h / 2;

  // Freeze the shared clock, then put the playhead somewhere that reads well.
  // Flutter paints to canvas, so these are offsets from the centred column
  // rather than elements: pause sits left of "Pop out", the scrubber above it.
  await click(page, cx - 64, cy + 64);          // pause
  await sleep(400);
  await click(page, cx - 96, cy - 4);           // scrub to roughly a third in
  await sleep(600);

  await shoot(page, join(OUT, 'page.png'));
  console.log('  page captured while it is still frontmost');

  let opened = false;
  for (const [dx, dy] of [[29, 64], [29, 60], [29, 68], [20, 64], [38, 64]]) {
    await click(page, cx + dx, cy + dy);
    await sleep(900);
    if (await evalIn(page, `!!documentPictureInPicture.window`)) { opened = true; break; }
  }
  if (!opened) throw new Error('could not open the pop-out by clicking');

  const pipTarget = (await listTargets())
    .find((t) => t.type === 'page' && t.id !== pageTarget.id);
  if (!pipTarget) throw new Error('the pop-out did not appear as a CDP target');
  const pip = (await cdp.send('Target.attachToTarget',
    { targetId: pipTarget.id, flatten: true })).sessionId;
  await cdp.send('Runtime.enable', {}, pip);
  await cdp.send('Page.enable', {}, pip);
  const size = await evalIn(pip, `JSON.stringify({w: innerWidth, h: innerHeight})`);
  console.log(`  pop-out is its own CDP target, ${size} — the size the example asked for`);
  await sleep(1200);
  await shoot(pip, join(OUT, 'pip.png'));
  console.log('  pop-out captured, same frozen state');
} finally {
  cdp?.close();
  chrome.kill('SIGTERM');
  await sleep(600);
  try { chrome.kill('SIGKILL'); } catch { /* already gone */ }
  rmSync(profile, { recursive: true, force: true });
}
