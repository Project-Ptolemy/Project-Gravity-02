// Real multi-touch regression. Use PLAYWRIGHT_MODULE for an existing install.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const directory = path.resolve(__dirname, '../docs/plugins/builder');
const server = http.createServer((request, response) => {
  const pathname = new URL(request.url, 'http://localhost').pathname;
  if (pathname === '/') {
    response.writeHead(200, { 'Content-Type': 'text/html' }).end('<!doctype html><html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/editors/path-editor.css"></head><body></body></html>');
    return;
  }
  if (pathname === '/favicon.ico') { response.writeHead(204).end(); return; }
  const filename = path.resolve(directory, '.' + pathname);
  if (!filename.startsWith(directory + path.sep) || !fs.existsSync(filename) || !fs.statSync(filename).isFile()) { response.writeHead(404).end(); return; }
  response.writeHead(200, { 'Content-Type': filename.endsWith('.css') ? 'text/css' : 'text/javascript', 'Cache-Control': 'no-store' });
  fs.createReadStream(filename).pipe(response);
});
const source = { points: [{ x: -60, y: 0, z: 12 }, { x: 60, y: 0, z: 12 }], closed: false, smooth: false };

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    const cdp = await page.context().newCDPSession(page);
    const touch = (type, points = []) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: points.map(([id, x, y]) => ({ id, x, y, radiusX: 5, radiusY: 5, force: 1 })) });
    const field = name => page.locator(`[data-field="${name}"]`);
    const action = name => page.locator(`[data-action="${name}"]`).last();
    const tool = name => page.locator(`[data-mode="${name}"]`).first();
    const readout = () => page.locator('.path-editor-readout').textContent();
    async function open() {
      await page.evaluate(async input => {
        const { openPathEditor } = await import('/editors/path-editor.mjs');
        window.applied = null;
        openPathEditor({ path: input, onApply(result) { window.applied = result; } });
      }, source);
      await page.locator('.path-editor canvas').waitFor();
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    }
    await open();
    let box = await page.locator('canvas').boundingBox();
    const scale = Math.min(250, (box.width - 86) / 120, (box.height - 86) / 60);
    const x = box.x + box.width / 2 - 60 * scale;
    const y = box.y + box.height / 2;
    const second = [2, box.x + box.width - 55, y];
    await touch('touchStart', [[1, x, y]]);
    await touch('touchMove', [[1, x + 4, y + 2]]);
    assert.equal(await page.locator('[data-coordinate="x"]').inputValue(), '-60', 'Touch jitter only selects a vertex');
    await touch('touchMove', [[1, x + 30, y]]);
    assert.notEqual(await page.locator('[data-coordinate="x"]').inputValue(), '-60', 'Deliberate touch drag edits the vertex');
    await touch('touchStart', [[1, x + 30, y], second]);
    assert.equal(await page.locator('[data-coordinate="x"]').inputValue(), '60', 'Second finger restores the original selection and geometry');
    assert.equal(await action('undo').isDisabled(), true, 'Cancelled edit creates no undo entry');
    const beforePinch = await readout();
    await touch('touchMove', [[1, x + 10, y - 8], [2, second[1] + 20, y + 8]]);
    assert.notEqual(await readout(), beforePinch, 'Two fingers pinch in the Move tool');
    const beforeThird = await readout();
    await touch('touchStart', [[1, x + 10, y - 8], [2, second[1] + 20, y + 8], [3, box.x + box.width / 2, y + 35]]);
    await touch('touchMove', [[1, x + 10, y - 8], [2, second[1] + 20, y + 8], [3, box.x + box.width / 2 + 15, y + 50]]);
    assert.equal(await readout(), beforeThird, 'An extra finger does not jump the zoom');
    await touch('touchEnd', [[1, x + 10, y - 8]]);
    await touch('touchMove', [[1, x + 70, y + 25]]);
    await touch('touchEnd');
    assert.equal(await readout(), beforeThird, 'A trailing finger does not restart a tool');
    assert.equal(await action('undo').isDisabled(), true);
    await action('apply').click();
    assert.deepEqual(await page.evaluate(() => window.applied), source, 'Navigation leaves every coordinate and path property intact');

    await open(); await tool('draw').click();
    box = await page.locator('canvas').boundingBox();
    const a = [1, box.x + 110, box.y + 50], b = [2, box.x + 220, box.y + 90];
    await touch('touchStart', [a]);
    assert.equal(await field('count').textContent(), '2 vertices', 'Draw defers placement until tap release');
    await touch('touchStart', [a, b]);
    await touch('touchMove', [[1, a[1] - 12, a[2]], [2, b[1] + 20, b[2]]]);
    await touch('touchEnd');
    assert.equal(await field('count').textContent(), '2 vertices', 'Pinching in Draw adds no vertices');
    assert.equal(await action('undo').isDisabled(), true);
    await page.touchscreen.tap(a[1], a[2]);
    assert.equal(await field('count').textContent(), '3 vertices', 'A deliberate tap still adds one vertex');
    await action('undo').click();
    assert.equal(await field('count').textContent(), '2 vertices');

    await tool('freehand').click();
    await touch('touchStart', [a]);
    await touch('touchMove', [[1, a[1] + 35, a[2] + 15]]);
    assert.notEqual(await field('count').textContent(), '2 vertices');
    await touch('touchStart', [[1, a[1] + 35, a[2] + 15], b]);
    assert.equal(await field('count').textContent(), '2 vertices', 'Pinching restores an unfinished freehand stroke');
    await touch('touchEnd');
    assert.equal(await action('undo').isDisabled(), true);

    await touch('touchStart', [a]);
    await touch('touchMove', [[1, a[1] + 25, a[2] + 10]]);
    await touch('touchCancel');
    assert.equal(await field('count').textContent(), '2 vertices', 'OS touch cancellation restores the draft');
    await touch('touchStart', [a]);
    await touch('touchMove', [[1, a[1] + 25, a[2] + 10]]);
    await page.evaluate(() => window.dispatchEvent(new Event('blur')));
    await touch('touchEnd');
    assert.equal(await field('count').textContent(), '2 vertices', 'Losing window focus cancels the active edit');
    await action('apply').click();
    assert.deepEqual(await page.evaluate(() => window.applied), source);
    assert.deepEqual(errors, [], 'No exceptions from real touch capture and cancellation');
    console.log('Path touch: multi-finger navigation in every tool, precise taps, drag rollback, cancellation and undo passed.');
  } finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
})().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
