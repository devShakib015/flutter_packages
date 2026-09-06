// Re-runs the Firefox verification behind this package's browser-support claim.
//
//   packages/document_pip $ tool/verify-firefox.sh            # current stable
//   packages/document_pip $ tool/verify-firefox.sh 151.0      # the declared floor
//
// Firefox speaks WebDriver BiDi, not the DevTools Protocol, so none of the
// Chrome tooling here applies — see tool/firefox-bidi.mjs for the client.
//
// Checks, in order:
//   1. documentPictureInPicture exists and requestWindow works.
//   2. The size asked for is the size given.
//   3. Flutter adds a view inside the pop-out's document and paints there.
//   4. The keyboard bridge replays keys from the pop-out into the opener.
//   5. Whether the opener stays "visible" with a pop-out open — the thing that
//      decides if DocumentPipApp's forced-frame workaround is needed at all.
//      Run with a control, because a backgrounded tab reports hidden anyway.
import { rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { sleep, launchFirefox, newSession, topContext, evaluate, click }
  from './firefox-bidi.mjs';

const APP = process.env.FIREFOX_APP;
const PORT = Number(process.env.BIDI_PORT ?? 9600);
const BASE = process.env.APP_URL ?? 'http://127.0.0.1:8399/';
if (!APP) throw new Error('FIREFOX_APP is not set — run tool/verify-firefox.sh');

const results = [];
const check = (name, ok, detail) => {
  results.push({ name, ok, detail });
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`);
};

const profile = join(tmpdir(), `ff-verify-${process.pid}`);
const ff = launchFirefox(APP, PORT, BASE, profile);
let bidi;
try {
  ({ bidi } = await newSession(PORT));
  // Match on the port from APP_URL, not a hardcoded one: the shell script lets
  // PORT be overridden and a stale literal here fails with a confusing
  // "no browsing context" instead of naming the real problem.
  const ctx = await topContext(bidi, new URL(BASE).port || new URL(BASE).host);

  let booted = false;
  for (let i = 0; i < 90; i++) {
    if (await evaluate(bidi, ctx, `!!document.querySelector('#app')?.firstElementChild`)) { booted = true; break; }
    await sleep(400);
  }
  const ua = (await evaluate(bidi, ctx, 'navigator.userAgent')).match(/Firefox\/[\d.]+/)?.[0];
  console.log(`\n  ${ua}\n`);
  check('the example boots', booted);
  if (!booted) throw new Error('nothing rendered into #app');
  await sleep(2500);

  check('the API is present',
    await evaluate(bidi, ctx, `'documentPictureInPicture' in window`));

  const view = JSON.parse(await evaluate(bidi, ctx, `JSON.stringify({w:innerWidth,h:innerHeight})`));
  let opened = false;
  for (const [dx, dy] of [[29, 64], [29, 60], [29, 68], [20, 64], [38, 64]]) {
    await click(bidi, ctx, view.w / 2 + dx, view.h / 2 + dy);
    await sleep(1200);
    if (await evaluate(bidi, ctx, `!!documentPictureInPicture.window`)) { opened = true; break; }
  }
  check('clicking Pop out opens a window', opened);
  if (!opened) throw new Error('no pop-out');
  await sleep(2000);

  const inside = JSON.parse(await evaluate(bidi, ctx, `(() => {
    const w = documentPictureInPicture.window, d = w.document;
    const host = d.body.firstElementChild;
    const r = host ? host.getBoundingClientRect() : null;
    return JSON.stringify({
      size: [w.innerWidth, w.innerHeight],
      hostSize: r ? [Math.round(r.width), Math.round(r.height)] : null,
      flutter: !!d.querySelector('flutter-view'),
      sheets: d.styleSheets.length,
    });
  })()`));
  check('the size asked for is the size given',
    inside.size[0] === 380 && inside.size[1] === 210,
    `asked 380x210, got ${inside.size.join('x')}`);
  check('Flutter added a view inside the pop-out', inside.flutter,
    `host ${inside.hostSize?.join('x')}, ${inside.sheets} stylesheets copied`);

  // The keyboard bridge, watched exactly where Flutter's KeyboardBinding listens.
  await evaluate(bidi, ctx, `
    window.__seen = [];
    window.__spy = (e) => window.__seen.push(e.type + ':' + e.code);
    addEventListener('keydown', window.__spy, true);
    addEventListener('keyup', window.__spy, true); 'ok'`);
  const { contexts } = await bidi.send('browsingContext.getTree', {});
  const pipCtx = contexts.find((c) => c.context !== ctx)?.context;
  check('the pop-out is its own browsing context', !!pipCtx);
  if (pipCtx) {
    await evaluate(bidi, pipCtx, `document.body.focus(); 'ok'`);
    await bidi.send('input.performActions', {
      context: pipCtx,
      actions: [{ type: 'key', id: 'kb', actions: [
        { type: 'keyDown', value: 'a' }, { type: 'keyUp', value: 'a' }] }],
    });
    await bidi.send('input.releaseActions', { context: pipCtx });
    await sleep(800);
    const seen = JSON.parse(await evaluate(bidi, ctx, `JSON.stringify(window.__seen)`));
    check('the keyboard bridge reaches the opener', seen.length >= 2, seen.join(' '));
  }

  // Does Firefox keep the opener visible? If it does, the forced-frame
  // workaround is unnecessary here and must stay switched off.
  const mark = Number(await evaluate(bidi, ctx, `(window.__raf ??= (function c(){window.__n=(window.__n||0)+1;requestAnimationFrame(c);return 1})(), window.__n)`));
  await bidi.send('browsingContext.create', { type: 'tab', url: 'about:blank' });
  await sleep(2500);
  const state = await evaluate(bidi, ctx, `document.visibilityState`);
  const frames = Number(await evaluate(bidi, ctx, `window.__n`)) - mark;
  check('the opener stays visible with a pop-out open', state === 'visible',
    `visibilityState=${state}, ${frames} animation frames in 2.5s`);

  const failed = results.filter((r) => !r.ok);
  console.log(`\n  ${results.length - failed.length}/${results.length} passed`);
  process.exitCode = failed.length ? 1 : 0;
} catch (e) {
  console.log('  ERROR:', e.message);
  process.exitCode = 1;
} finally {
  bidi?.close();
  ff.kill('SIGTERM'); await sleep(900);
  try { ff.kill('SIGKILL'); } catch { /* gone */ }
  rmSync(profile, { recursive: true, force: true });
}
