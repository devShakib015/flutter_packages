// Screenshots the storefront demo via the Chrome DevTools Protocol.
//
// Chrome's own --screenshot flag waits for the page to go idle and gives no
// way to wait a fixed time, which is no use when the page has to finish a few
// round trips first. CDP lets us wait properly.
//
// Node 22+ only, for the built-in WebSocket. No dependencies.
import { spawn } from 'node:child_process';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const CHROME = process.env.CHROME
  ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = Number(process.env.PORT ?? 8101);
const CDP = Number(process.env.CDP_PORT ?? 9222);
const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'doc');
const [WIDTH, HEIGHT] = (process.env.SIZE ?? '1360x740').split('x').map(Number);

const shots = [
  { name: 'storefront', query: 'auto=1', settle: 2500 },
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function targets() {
  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${CDP}/json/list`);
      const list = await r.json();
      const page = list.find((t) => t.type === 'page');
      if (page) return page;
    } catch { /* not up yet */ }
    await sleep(250);
  }
  throw new Error('Chrome never opened its debugging port');
}

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

  send(method, params = {}) {
    const id = ++this.#id;
    this.#ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) =>
      this.#pending.set(id, { resolve, reject }));
  }

  close() { this.#ws.close(); }
}

mkdirSync(OUT, { recursive: true });

const chrome = spawn(CHROME, [
  '--headless=new',
  '--no-sandbox',
  '--hide-scrollbars',
  `--remote-debugging-port=${CDP}`,
  `--window-size=${WIDTH},${HEIGHT}`,
  '--user-data-dir=' + join(process.env.TMPDIR ?? '/tmp', `cross-tab-shot-${process.pid}`),
  'about:blank',
], { stdio: 'ignore' });

try {
  const page = await targets();
  const cdp = await Cdp.connect(page.webSocketDebuggerUrl);
  await cdp.send('Page.enable');
  // Device scale 2 so the PNG is crisp on a retina pub.dev page.
  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width: WIDTH, height: HEIGHT, deviceScaleFactor: 2, mobile: false,
  });

  const painted = async () => {
    // Flutter mounts <flutter-view> only once it is actually up. Polling for
    // it beats guessing a delay: a debug bundle can take ten seconds to boot
    // and a release one under two, and a blank screenshot looks like success.
    for (let i = 0; i < 120; i++) {
      const { result } = await cdp.send('Runtime.evaluate', {
        expression:
          "!!document.querySelector('flutter-view, flt-glass-pane')",
        returnByValue: true,
      });
      if (result.value === true) break;
      await sleep(250);
      if (i === 119) {
        throw new Error('Flutter never painted — is the example being served?');
      }
    }
    // And wait for the fonts. flutter-view exists before MaterialIcons has
    // loaded, and a screenshot taken in that window renders every icon as a
    // tofu box — which looks like a broken app rather than a timing artefact.
    await cdp.send('Runtime.evaluate', {
      expression: 'document.fonts.ready.then(() => true)',
      awaitPromise: true,
      returnByValue: true,
    });
  };

  await cdp.send('Runtime.enable');

  for (const { name, query, settle } of shots) {
    await cdp.send('Page.navigate', {
      url: `http://127.0.0.1:${PORT}/?${query}`,
    });
    await painted();
    // Then a real wait: the election has to settle and broadcasts have to land.
    await sleep(settle);
    const { data } = await cdp.send('Page.captureScreenshot', {
      format: 'png', captureBeyondViewport: false,
    });
    const file = join(OUT, `${name}.png`);
    writeFileSync(file, Buffer.from(data, 'base64'));
    console.log(`  ${file}  ${(Buffer.from(data, 'base64').length / 1024 | 0)} KB`);
  }
  cdp.close();
} finally {
  chrome.kill('SIGKILL');
}
