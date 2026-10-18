// Deterministic slow-frame clock and responsive breakpoint regressions.
// The real app/model run unchanged; only browser frame delivery is controlled.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const server = http.createServer((request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  let file = path.resolve(root, '.' + pathname);
  if (!file.startsWith(root + path.sep)) return response.writeHead(403).end();
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
  if (!fs.existsSync(file)) return response.writeHead(404).end();
  response.setHeader('Content-Type', { '.html': 'text/html', '.mjs': 'text/javascript', '.css': 'text/css' }[path.extname(file)] || 'text/plain');
  response.end(fs.readFileSync(file));
});

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE });
  const failures = [], errors = [];
  const check = (value, message) => { if (!value) failures.push(message); };
  const near = (value, expected, message) => check(Math.abs(value - expected) < 1e-10, `${message}: ${value} != ${expected}`);
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, reducedMotion: 'reduce' });
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      const callbacks = new Map();
      let now = 0, next = 0;
      Object.defineProperty(performance, 'now', { value: () => now });
      window.requestAnimationFrame = callback => { callbacks.set(++next, callback); return next; };
      window.cancelAnimationFrame = id => callbacks.delete(id);
      window.deliverFrame = (milliseconds, render = true) => {
        now += milliseconds;
        if (render) {
          const pending = [...callbacks.values()]; callbacks.clear();
          pending.forEach(callback => callback(now));
        }
      };
    });
    await page.goto(`http://127.0.0.1:${server.address().port}/docs/plugins/builder/`);
    await page.locator('.layer-row').first().waitFor({ state: 'attached' });
    await page.evaluate(() => { deliverFrame(0); deliverFrame(0); deliverFrame(0); });
    const advance = (milliseconds, render = true) => page.evaluate(({ milliseconds, render }) => deliverFrame(milliseconds, render), { milliseconds, render });
    const click = id => page.evaluate(id => document.getElementById(id).click(), id);
    const value = () => page.locator('#preview-time').evaluate(input => Number(input.value));
    await advance(500);
    near(await value(), 0, 'reduced-motion startup stays paused');
    await click('play-pause');
    await advance(250);
    near(await value(), 0.25, 'a slow frame advances the full quarter-second');
    await page.evaluate(() => { const input = document.getElementById('playback-speed'); input.value = '2'; input.dispatchEvent(new Event('change')); });
    await advance(400);
    near(await value(), 1.05, 'playback speed scales actual elapsed time');
    await click('play-pause');
    await advance(1000);
    near(await value(), 1.05, 'paused wall time does not advance formation time');
    await click('play-pause');
    await advance(125);
    near(await value(), 1.3, 'resume starts from its own clock boundary');

    // A mobile frame may be delayed throughout a dialog interaction. Closing
    // it must not count that paused interval as part of the next live frame.
    await click('help');
    await advance(600, false);
    await page.evaluate(() => document.getElementById('help-dialog').close());
    await advance(100);
    near(await value(), 1.5, 'closing a dialog excludes time spent editing between frames');

    await page.evaluate(() => {
      const input = document.getElementById('preview-time');
      input.value = '0.1234567890123'; input.dispatchEvent(new Event('change'));
    });
    near(await value(), 0.1234567890123, 'manual time preserves exact input immediately');
    await click('frame-forward');
    near(await value(), 0.1234567890123 + 1 / 60, 'single-frame stepping immediately publishes its exact pose time');

    await page.setViewportSize({ width: 960, height: 450 });
    const bounds = await page.evaluate(() => {
      const scene = document.querySelector('.left-panel'), inspector = document.querySelector('.right-panel');
      const a = scene.getBoundingClientRect(), b = inspector.getBoundingClientRect();
      return { width: innerWidth, sceneVisible: !!scene.offsetWidth, inspectorVisible: !!inspector.offsetWidth,
        overlap: Math.min(a.right, b.right) - Math.max(a.left, b.left) > 1 && Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 1,
        sceneInert: scene.inert, inspectorInert: inspector.inert };
    });
    check(!(bounds.sceneVisible && bounds.inspectorVisible && bounds.overlap), 'tablet landscape must not overlap scene and inspector: ' + JSON.stringify(bounds));
    await page.setViewportSize({ width: 1440, height: 900 });
    check(await page.evaluate(() => !document.querySelector('.left-panel').inert && !document.querySelector('.right-panel').inert), 'desktop breakpoint re-enables both panels');
    check(errors.length === 0, 'no page errors: ' + errors.join('; '));
    assert.deepEqual(failures, []);
    console.log('Builder clock/breakpoints: slow frames, speed, pause/resume, dialog boundaries, exact stepping and landscape panel isolation passed.');
  } finally {
    await browser.close(); server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
