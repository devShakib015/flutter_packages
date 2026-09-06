// A minimal WebDriver BiDi client. Firefox speaks BiDi, not CDP, so none of the
// Chrome tooling in this repo applies. Node 22+ built-in WebSocket, no deps.
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';

export class Bidi {
  #ws; #id = 0; #pending = new Map(); #events = [];
  static async connect(url) {
    const b = new Bidi();
    b.#ws = new WebSocket(url);
    await new Promise((res, rej) => {
      b.#ws.addEventListener('open', res, { once: true });
      b.#ws.addEventListener('error', rej, { once: true });
    });
    b.#ws.addEventListener('message', (e) => {
      const m = JSON.parse(e.data);
      if (m.id === undefined) { b.#events.push(m); return; }
      const p = b.#pending.get(m.id);
      if (!p) return;
      b.#pending.delete(m.id);
      m.type === 'error' ? p.reject(new Error(`${m.error}: ${m.message}`)) : p.resolve(m.result);
    });
    return b;
  }
  send(method, params = {}) {
    const id = ++this.#id;
    this.#ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => this.#pending.set(id, { resolve, reject }));
  }
  close() { this.#ws.close(); }
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function launchFirefox(app, port, url, profileDir) {
  rmSync(profileDir, { recursive: true, force: true });
  mkdirSync(profileDir, { recursive: true });
  writeFileSync(join(profileDir, 'user.js'), [
    'user_pref("browser.shell.checkDefaultBrowser", false);',
    'user_pref("browser.startup.homepage_override.mstone", "ignore");',
    'user_pref("datareporting.policy.dataSubmissionEnabled", false);',
    'user_pref("datareporting.healthreport.uploadEnabled", false);',
    'user_pref("browser.aboutwelcome.enabled", false);',
    'user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);',
    'user_pref("app.update.auto", false);',
    'user_pref("browser.tabs.warnOnClose", false);',
  ].join('\n'));
  return spawn(`${app}/Contents/MacOS/firefox`, [
    '--remote-debugging-port', String(port),
    '--profile', profileDir,
    '--no-remote',
    '--new-instance',
    url,
  ], { stdio: 'ignore' });
}

export async function newSession(port, tries = 120) {
  for (let i = 0; i < tries; i++) {
    try {
      const b = await Bidi.connect(`ws://127.0.0.1:${port}/session`);
      const r = await b.send('session.new', { capabilities: {} });
      return { bidi: b, sessionId: r.sessionId };
    } catch { await sleep(500); }
  }
  throw new Error('Firefox never opened a BiDi session');
}

export async function topContext(bidi, match) {
  for (let i = 0; i < 80; i++) {
    const { contexts } = await bidi.send('browsingContext.getTree', {});
    const hit = contexts.find((c) => !match || (c.url ?? '').includes(match));
    if (hit) return hit.context;
    await sleep(300);
  }
  throw new Error(`no browsing context matching ${match}`);
}

export async function evaluate(bidi, context, expression) {
  const r = await bidi.send('script.evaluate', {
    expression, target: { context }, awaitPromise: true, resultOwnership: 'none',
  });
  if (r.type === 'exception') throw new Error(r.exceptionDetails?.text ?? 'threw');
  return r.result?.value;
}

export async function click(bidi, context, x, y) {
  await bidi.send('input.performActions', {
    context,
    actions: [{
      type: 'pointer', id: 'mouse', parameters: { pointerType: 'mouse' },
      actions: [
        { type: 'pointerMove', x: Math.round(x), y: Math.round(y) },
        { type: 'pointerDown', button: 0 },
        { type: 'pause', duration: 40 },
        { type: 'pointerUp', button: 0 },
      ],
    }],
  });
  await bidi.send('input.releaseActions', { context });
}
