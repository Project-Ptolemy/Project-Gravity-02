// Optional development-only browser coverage. The shipped app has no packages.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const directory = path.resolve(__dirname, '../docs/plugins/builder');
const server = http.createServer((request, response) => {
  const pathname = new URL(request.url, 'http://localhost').pathname;
  if (pathname === '/') {
    response.writeHead(200, { 'Content-Type': 'text/html' }).end('<!doctype html><html lang="en"><head><meta name="viewport" content="width=device-width, initial-scale=1"><link rel="stylesheet" href="/style.css"><link rel="stylesheet" href="/editors/surface-editor.css"></head><body></body></html>');
    return;
  }
  if (pathname === '/favicon.ico') { response.writeHead(204).end(); return; }
  const filename = path.resolve(directory, '.' + pathname);
  if (!filename.startsWith(directory + path.sep) || !fs.existsSync(filename) || !fs.statSync(filename).isFile()) { response.writeHead(404).end(); return; }
  response.writeHead(200, { 'Content-Type': filename.endsWith('.css') ? 'text/css' : 'text/javascript', 'Cache-Control': 'no-store' });
  fs.createReadStream(filename).pipe(response);
});

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE });
  try {
    const page = await browser.newPage({ viewport: { width: 1400, height: 1000 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    async function open() {
      await page.evaluate(async () => {
        const { createLayer } = await import('/model.mjs');
        const { openSurfaceEditor } = await import('/editors/surface-editor.mjs');
        window.applied = null; window.applyCount = 0; window.rejectApply = false;
        window.source = createLayer('path', {
          name: 'Original profile', path: { points: [{ x: 3, y: 0, z: 0 }, { x: 3, y: 10, z: 0 }] },
          position: { x: 12, y: 30, z: -10 }, rotation: { x: 15, y: -20, z: 30 }, scale: { x: 1.2, y: .8, z: 2 }, spin: 40,
        });
        window.before = JSON.stringify(window.source);
        openSurfaceEditor({ layer: window.source, onApply(spec) {
          if (window.rejectApply) throw new Error('This scene has no room for another layer.');
          window.applied = spec; window.applyCount++;
        } });
      });
      await page.locator('#surface-editor').waitFor();
      assert.equal(await page.locator('#surface-error').textContent(), '', 'default live preview succeeds');
      assert.equal(await page.locator('#surface-apply').isEnabled(), true);
    }
    async function fill(id, value) {
      await page.locator('#surface-' + id).fill(String(value));
    }
    async function ready() { await page.waitForFunction(() => !document.querySelector('#surface-apply').disabled); }
    async function errorMatch(pattern) {
      await page.waitForFunction(source => new RegExp(source).test(document.querySelector('#surface-error').textContent), pattern.source);
      assert.match(await page.locator('#surface-error').textContent(), pattern);
      assert.equal(await page.locator('#surface-apply').isDisabled(), true);
      assert.equal(await page.evaluate(() => window.applied), null);
    }
    async function applied() {
      await ready(); await page.locator('#surface-apply').click();
      await page.locator('#surface-editor').waitFor({ state: 'detached' });
      const state = await page.evaluate(() => ({ spec: window.applied, count: window.applyCount, unchanged: JSON.stringify(window.source) === window.before }));
      assert.equal(state.count, 1); assert.equal(state.unchanged, true);
      return state.spec;
    }

    await open();
    assert.match(await page.locator('#surface-summary').textContent(), /Outline walls.*1,024 points/);
    await page.locator('#surface-axis').selectOption('custom');
    await fill('direction-x', 0); await fill('direction-y', 3); await fill('direction-z', 4);
    await fill('depth', -10); await fill('samples', 2); await fill('rows', 2);
    await page.locator('#surface-centered').check();
    const diagonal = await applied();
    assert.equal(diagonal.type, 'pointcloud');
    assert.deepEqual(diagonal.path.points, [
      { x: 3, y: 3, z: 4 }, { x: 3, y: 13, z: 4 }, { x: 3, y: -3, z: -4 }, { x: 3, y: 7, z: -4 },
    ]);
    assert.deepEqual(diagonal.position, { x: 12, y: 30, z: -10 }); assert.equal(diagonal.spin, 0);

    await open();
    await fill('depth', 0); await errorMatch(/nonzero/);
    await fill('depth', ''); await errorMatch(/finite number/);
    await fill('depth', 40); await fill('samples', 65); await fill('rows', 64); await errorMatch(/4,096/);
    await fill('samples', 64); await ready();
    assert.match(await page.locator('#surface-summary').textContent(), /4,096 points/);
    await page.keyboard.press('Escape');
    await page.locator('#surface-editor').waitFor({ state: 'detached' });
    assert.equal(await page.evaluate(() => window.applied), null, 'cancel does not apply valid or invalid previews');

    await open();
    await page.locator('#surface-mode').selectOption('revolve');
    assert.equal(await page.locator('#surface-axis').inputValue(), 'y', 'revolve starts with its own axis');
    assert.equal(await page.locator('#surface-extrude-settings').isVisible(), false);
    assert.equal(await page.locator('#surface-revolve-settings').isVisible(), true);
    await fill('samples', 2); await fill('rows', 2); await errorMatch(/rows/);
    await fill('sweep', -90); await fill('start', 90); await ready();
    await page.locator('#surface-axis').selectOption('z');
    await page.locator('#surface-mode').selectOption('extrude');
    assert.equal(await page.locator('#surface-axis').inputValue(), 'z');
    await page.locator('#surface-axis').selectOption('custom');
    await page.locator('#surface-mode').selectOption('revolve');
    assert.equal(await page.locator('#surface-axis').inputValue(), 'z', 'each operation remembers its axis');
    await fill('pivot-x', 1); await fill('pivot-y', 2); await fill('pivot-z', 3);
    const revolution = await applied();
    assert.equal(revolution.path.points.length, 4);
    const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-8, `${a} ~= ${b}`);
    near(revolution.path.points[0].x, 3); near(revolution.path.points[0].y, 4); near(revolution.path.points[0].z, 0);
    assert.deepEqual(revolution.path.points[2], { x: 3, y: 0, z: 0 });

    // Callback failures keep the dialog usable, and fixing capacity externally
    // permits a single application without discarding the user's settings.
    await open();
    await page.evaluate(() => { window.rejectApply = true; });
    await page.locator('#surface-apply').click();
    assert.match(await page.locator('#surface-error').textContent(), /no room/);
    assert.equal(await page.locator('#surface-editor').isVisible(), true);
    await page.evaluate(() => { window.rejectApply = false; });
    const retried = await applied(); assert.equal(retried.path.points.length, 1024);

    // Saved model data and the public exporter accept the exact callback spec.
    const compatibility = await page.evaluate(async spec => {
      const { createLayer, normalizeProject, sampleProject } = await import('/model.mjs');
      const { exportLua } = await import('/exporter.mjs');
      const project = normalizeProject({ version: 1, parts: 128, layers: [createLayer(spec.type, spec)] });
      const roundtrip = normalizeProject(JSON.parse(JSON.stringify(project)));
      return { same: JSON.stringify(roundtrip) === JSON.stringify(project), points: sampleProject(roundtrip).length, lua: exportLua(roundtrip) };
    }, revolution);
    assert.equal(compatibility.same, true); assert.equal(compatibility.points, 128);
    assert.ok(compatibility.lua.includes('["type"] = "pointcloud"'));

    const screenshots = process.env.BUILDER_SCREENSHOT_DIR ? path.resolve(process.env.BUILDER_SCREENSHOT_DIR) : null;
    if (screenshots) fs.mkdirSync(screenshots, { recursive: true });
    await open();
    await page.locator('#surface-mode').selectOption('revolve'); await ready();
    await page.locator('#surface-fit').click();
    if (screenshots) await page.screenshot({ path: path.join(screenshots, 'surface-desktop.png') });
    for (const width of [390, 320]) {
      await page.setViewportSize({ width, height: 844 });
      await page.locator('#surface-preview').scrollIntoViewIfNeeded();
      await page.waitForTimeout(100);
      const bounds = await page.evaluate(() => {
        const dialog = document.querySelector('#surface-editor'), canvas = document.querySelector('#surface-preview');
        return { viewport: innerWidth, body: document.documentElement.scrollWidth, width: dialog.clientWidth, scroll: dialog.scrollWidth, canvas: canvas.getBoundingClientRect().width };
      });
      assert.ok(bounds.body <= bounds.viewport, JSON.stringify(bounds));
      assert.ok(bounds.scroll <= bounds.width + 1, JSON.stringify(bounds));
      assert.ok(bounds.canvas > 180 && bounds.canvas < width, JSON.stringify(bounds));
      if (screenshots) await page.screenshot({ path: path.join(screenshots, `surface-mobile-${width}.png`) });
    }
    await page.locator('#surface-apply').click();
    await page.locator('#surface-editor').waitFor({ state: 'detached' });
    assert.deepEqual(errors, []);
    console.log('Builder surface editor: live previews, custom directions, signed/pivoted sweeps, validation, cancellation, callback isolation, save/export compatibility and desktop/mobile layouts passed.');
  } finally { await browser.close(); server.close(); }
})().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
