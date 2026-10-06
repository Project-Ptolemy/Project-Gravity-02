// Optional real-browser coverage for the isolated repetition editor.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const server = http.createServer((request, response) => {
  const pathname = new URL(request.url, 'http://localhost').pathname;
  if (pathname === '/') {
    response.writeHead(200, { 'Content-Type': 'text/html' }).end('<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/plugins/builder/style.css"><link rel="stylesheet" href="/docs/plugins/builder/editors/repeat-editor.css"></head><body></body></html>');
    return;
  }
  if (pathname === '/favicon.ico') { response.writeHead(204).end(); return; }
  const filename = path.resolve(root, '.' + pathname);
  if (!filename.startsWith(root + path.sep) || !fs.existsSync(filename) || !fs.statSync(filename).isFile()) { response.writeHead(404).end(); return; }
  response.writeHead(200, { 'Content-Type': filename.endsWith('.css') ? 'text/css' : 'text/javascript' });
  fs.createReadStream(filename).pipe(response);
});

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, reducedMotion: 'reduce' });
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.evaluate(async () => {
      const { createProject, createLayer } = await import('/docs/plugins/builder/model.mjs');
      window.sourceProject = { ...createProject('blank'), layers: [createLayer('path', {
        id: 'source', name: '<My custom outline>', position: { x: 10, y: 0, z: 0 }, rotation: { z: 90 }, scale: { x: 2 },
        path: { points: [{ x: 0, y: 0, z: 0 }, { x: 4, y: 8, z: 3 }, { x: -6, y: 3, z: 2 }] },
      })], controls: [
        { id: 'move', name: 'Keep my control name', layerId: 'source', property: 'position.x', min: -10, max: 30, default: 10 },
        { id: 'restart', name: 'Start again', layerId: 'source', type: 'button', action: 'restart' },
      ] };
      window.originalJSON = JSON.stringify(window.sourceProject);
    });
    async function open() {
      await page.evaluate(async () => {
        const { openRepeatEditor } = await import('/docs/plugins/builder/editors/repeat-editor.mjs');
        window.applied = null;
        openRepeatEditor({ project: window.sourceProject, layerId: 'source', onApply(copies) { window.applied = copies; } });
      });
      await page.locator('#repeat-editor').waitFor();
    }
    await open();
    assert.equal(await page.locator('#repeat-source-name').textContent(), '<My custom outline>');
    assert.equal(await page.locator('#repeat-error').textContent(), '');
    await page.locator('#repeat-count').fill('2');
    await page.locator('#repeat-position-x').fill('20');
    await page.locator('#repeat-rotation-z').fill('15');
    await page.locator('#repeat-preview-button').click();
    assert.match(await page.locator('#repeat-summary').textContent(), /2 new layers.*4 copied controls/);
    assert.equal(await page.locator('#repeat-apply').isEnabled(), true);
    const preview = await page.locator('#repeat-preview').evaluate(canvas => canvas.toDataURL());
    assert.ok(preview.length > 1000, 'viewport renders the repetition');
    await page.locator('#repeat-apply').click();
    await page.locator('#repeat-editor').waitFor({ state: 'detached' });
    const line = await page.evaluate(() => window.applied);
    assert.deepEqual(line.layers.map(layer => layer.position.x), [30, 50]);
    assert.deepEqual(line.layers.map(layer => layer.rotation.z), [105, 120]);
    assert.deepEqual(line.controls.map(control => control.name), ['Keep my control name', 'Start again', 'Keep my control name', 'Start again']);
    assert.equal(await page.evaluate(() => JSON.stringify(window.sourceProject) === window.originalJSON), true);

    await open();
    await page.locator('#repeat-position-x').fill('5000');
    await page.locator('#repeat-preview-button').click();
    assert.match(await page.locator('#repeat-error').textContent(), /Copy 1 position X/);
    assert.equal(await page.locator('#repeat-apply').isDisabled(), true);
    assert.equal(await page.evaluate(() => window.applied), null);
    await page.locator('#repeat-position-x').fill('20');
    await page.locator('#repeat-count').fill('48');
    await page.locator('#repeat-preview-button').click();
    assert.match(await page.locator('#repeat-error').textContent(), /96 controls/);
    await page.getByRole('button', { name: 'Cancel', exact: true }).click();
    await page.locator('#repeat-editor').waitFor({ state: 'detached' });
    assert.equal(await page.evaluate(() => window.applied), null);

    await page.setViewportSize({ width: 390, height: 844 });
    await open();
    await page.locator('#repeat-mode').selectOption('radial');
    await page.locator('#repeat-count').fill('1');
    await page.locator('#repeat-axis').selectOption('z');
    await page.locator('#repeat-sweep').fill('180');
    await page.locator('#repeat-pivot-space').selectOption('local');
    await page.locator('#repeat-pivot-x').fill('5');
    await page.locator('#repeat-preview-button').click();
    assert.match(await page.locator('#repeat-pivot-note').textContent(), /default scale.*world axis/);
    const bounds = await page.locator('#repeat-editor').boundingBox();
    assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= 390, 'dialog fits mobile width');
    assert.equal(await page.locator('#repeat-editor').evaluate(dialog => dialog.scrollWidth <= dialog.clientWidth), true, 'mobile fields do not overflow horizontally');
    await page.locator('#repeat-apply').click();
    await page.locator('#repeat-editor').waitFor({ state: 'detached' });
    const radial = await page.evaluate(() => window.applied);
    assert.equal(radial.layers.length, 1);
    assert.deepEqual(radial.layers[0].position, { x: 10, y: 20, z: 0 });
    assert.equal(await page.evaluate(() => JSON.stringify(window.sourceProject) === window.originalJSON), true);
    await open();
    await page.keyboard.press('Escape');
    await page.locator('#repeat-editor').waitFor({ state: 'detached' });
    assert.equal(await page.evaluate(() => window.applied), null);
    assert.deepEqual(errors, []);
    console.log('Builder repeat UI: independent copies/controls, atomic errors, cancellation, live preview and mobile radial pivots passed.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => server.close());
