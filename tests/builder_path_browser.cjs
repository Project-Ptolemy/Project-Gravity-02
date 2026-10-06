// Run with PLAYWRIGHT_MODULE pointing to an installed Playwright package, or npm's playwright.
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const harness = `<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><link rel="stylesheet" href="/docs/plugins/builder/style.css"><link rel="stylesheet" href="/docs/plugins/builder/editors/path-editor.css"></head><body><button id="opener">Open editor</button></body></html>`;
const server = http.createServer((request, response) => {
  if (request.url === '/') { response.setHeader('Content-Type', 'text/html'); response.end(harness); return; }
  const target = path.resolve(root, `.${decodeURIComponent(new URL(request.url, 'http://localhost').pathname)}`);
  if (!target.startsWith(root + path.sep) || !fs.existsSync(target)) { response.writeHead(404); response.end(); return; }
  response.setHeader('Content-Type', target.endsWith('.css') ? 'text/css' : target.endsWith('.mjs') ? 'text/javascript' : target.endsWith('.html') ? 'text/html' : 'text/plain');
  response.end(fs.readFileSync(target));
});
const original = { points: [{ x: -60, y: 0, z: 0 }, { x: 60, y: 0, z: 0 }], closed: false, smooth: false };
const open = async (page, source = original, minPoints = 2) => {
  await page.evaluate(async ({ source, minPoints }) => {
    const { openPathEditor } = await import('/docs/plugins/builder/editors/path-editor.mjs');
    window.sourcePath = structuredClone(source); window.appliedPath = null;
    openPathEditor({ path: window.sourcePath, minPoints, onApply: result => { window.appliedPath = result; } });
  }, { source, minPoints });
  await page.waitForSelector('.path-editor[open]');
  await page.waitForTimeout(80);
};
const button = (page, name) => page.locator(`.path-editor [data-action="${name}"]`).last();
const field = (page, name) => page.locator(`.path-editor [data-field="${name}"]`);
const coord = (page, axis) => page.locator(`.path-editor [data-coordinate="${axis}"]`);
const setNumber = async (locator, value) => { await locator.fill(String(value)); await locator.press('Tab'); };

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true });
  const errors = [];
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 920 } });
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await open(page);
    await setNumber(coord(page, 'x'), 100);
    assert.equal(await coord(page, 'x').inputValue(), '100');
    await button(page, 'undo').click(); assert.equal(await coord(page, 'x').inputValue(), '60');
    await button(page, 'redo').click(); assert.equal(await coord(page, 'x').inputValue(), '100');
    await button(page, 'cancel').click();
    assert.equal(await page.evaluate(() => window.appliedPath), null);
    assert.deepEqual(await page.evaluate(() => window.sourcePath), original, 'Cancel never mutates source data');

    await open(page, { points: [], closed: false, smooth: false });
    assert.equal(await button(page, 'apply').isDisabled(), true);
    const box = await page.locator('.path-editor canvas').boundingBox();
    const clicks = [{ x: box.width * .30, y: box.height * .30 }, { x: box.width * .70, y: box.height * .30 }, { x: box.width * .50, y: box.height * .70 }];
    for (const position of clicks) await page.locator('.path-editor canvas').click({ position });
    assert.equal(await field(page, 'count').textContent(), '3 vertices');
    await page.locator('.path-editor canvas').click({ position: clicks[0] });
    assert.equal(await field(page, 'closed').isChecked(), true, 'Drawing can close at the start vertex');
    await button(page, 'undo').click(); assert.equal(await field(page, 'closed').isChecked(), false);
    await button(page, 'redo').click(); assert.equal(await field(page, 'closed').isChecked(), true);
    await field(page, 'smooth').check();
    await button(page, 'undo').click(); assert.equal(await field(page, 'smooth').isChecked(), false);
    await button(page, 'redo').click(); assert.equal(await field(page, 'smooth').isChecked(), true);
    await field(page, 'smooth').uncheck();
    const beforeArrow = Number(await coord(page, 'x').inputValue());
    await page.locator('.path-editor canvas').focus(); await page.keyboard.press('ArrowRight');
    assert.equal(Number(await coord(page, 'x').inputValue()), beforeArrow + 1);
    await button(page, 'insert').click(); assert.equal(await field(page, 'count').textContent(), '4 vertices');
    await button(page, 'delete').click(); assert.equal(await field(page, 'count').textContent(), '3 vertices');
    await setNumber(field(page, 'vertex'), 2); await setNumber(coord(page, 'z'), 50);
    await field(page, 'plane').selectOption('yz'); assert.equal(await coord(page, 'z').inputValue(), '50');
    await field(page, 'plane').selectOption('xy');
    await page.locator('.path-editor [data-mode="freehand"]').click();
    const stroke = await page.locator('.path-editor canvas').boundingBox();
    await page.mouse.move(stroke.x + 80, stroke.y + 100); await page.mouse.down();
    await page.mouse.move(stroke.x + 250, stroke.y + 150, { steps: 20 }); await page.mouse.up();
    const afterStroke = await field(page, 'count').textContent();
    assert.notEqual(afterStroke, '3 vertices');
    await button(page, 'undo').click(); assert.equal(await field(page, 'count').textContent(), '3 vertices', 'Freehand stroke undoes as one change');
    await button(page, 'redo').click(); assert.equal(await field(page, 'count').textContent(), afterStroke);
    await button(page, 'undo').click(); await button(page, 'apply').click();
    const result = await page.evaluate(() => window.appliedPath);
    assert.equal(result.points.length, 3); assert.equal(result.closed, true); assert.equal(result.points[1].z, 50);
    await page.locator('.path-editor').waitFor({ state: 'detached' });

    // Drag editing preserves depth, and snapping applies in the active drawing plane.
    await open(page); await field(page, 'snap').check(); await button(page, 'frame').click();
    const dragBox = await page.locator('.path-editor canvas').boundingBox();
    // For the symmetric two-point path, Fit gives (width - 86) / 120 pixels per unit.
    const scale = Math.min((dragBox.width - 86) / 120, (dragBox.height - 86) / 60);
    await page.mouse.move(dragBox.x + dragBox.width / 2 + 60 * scale, dragBox.y + dragBox.height / 2);
    await page.mouse.down(); await page.mouse.move(dragBox.x + dragBox.width / 2 + 60 * scale + 23, dragBox.y + dragBox.height / 2 - 31, { steps: 5 }); await page.mouse.up();
    assert.equal(Number(await coord(page, 'x').inputValue()) % 10, 0); assert.equal(Number(await coord(page, 'y').inputValue()) % 10, 0);
    await button(page, 'undo').click(); assert.equal(await coord(page, 'x').inputValue(), '60');
    await page.keyboard.press('Escape'); await page.locator('.path-editor').waitFor({ state: 'detached' });
    assert.equal(await page.evaluate(() => window.appliedPath), null);

    const mobile = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 1 });
    mobile.on('pageerror', error => errors.push(error.message));
    await mobile.goto(`http://127.0.0.1:${server.address().port}/`);
    await open(mobile, { points: [], closed: false, smooth: false });
    const mobileBox = await mobile.locator('.path-editor').boundingBox();
    assert.ok(mobileBox.x >= 0 && mobileBox.x + mobileBox.width <= 390, 'Dialog fits a 390px viewport');
    assert.ok(mobileBox.y >= 0 && mobileBox.y + mobileBox.height <= 844, 'Dialog stays inside viewport');
    assert.ok(await mobile.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'No horizontal page overflow');
    const touchBox = await mobile.locator('.path-editor canvas').boundingBox();
    await mobile.touchscreen.tap(touchBox.x + 90, touchBox.y + 60); await mobile.touchscreen.tap(touchBox.x + 200, touchBox.y + 150);
    assert.equal(await field(mobile, 'count').textContent(), '2 vertices');
    await mobile.screenshot({ path: path.join(os.tmpdir(), 'gravity-path-editor-mobile.png') });
    await button(mobile, 'apply').click(); assert.equal((await mobile.evaluate(() => window.appliedPath)).points.length, 2);
    await open(mobile, { points: [{ x: 5, y: 10, z: 15 }], closed: false, smooth: false }, 1);
    assert.equal(await button(mobile, 'apply').isEnabled(), true, 'Point-cloud editing accepts one vertex');
    assert.equal(await field(mobile, 'smooth').isVisible(), false, 'Point clouds show separate points without curve controls');
    await button(mobile, 'cancel').click();

    // Real application integration: draw an outline, overlap a rotated copy, save, reload, export.
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto(`http://127.0.0.1:${server.address().port}/docs/plugins/builder/index.html`);
    await page.locator('#layers .layer-row').first().waitFor();
    await page.locator('.presets-section>summary').click(); await page.locator('#new-project').click();
    assert.equal(await page.locator('#layers .layer-row').count(), 0);
    await page.locator('#draw-path').click();
    const integratedCanvas = page.locator('.path-editor canvas');
    const integratedBox = await integratedCanvas.boundingBox();
    const triangleClicks = [{ x: integratedBox.width * .5, y: integratedBox.height * .25 }, { x: integratedBox.width * .3, y: integratedBox.height * .7 }, { x: integratedBox.width * .7, y: integratedBox.height * .7 }];
    for (const position of triangleClicks) await integratedCanvas.click({ position });
    await integratedCanvas.click({ position: triangleClicks[0] });
    const triangle = [{ x: 0, y: 60, z: 0 }, { x: -51.9615, y: -30, z: 0 }, { x: 51.9615, y: -30, z: 0 }];
    for (let index = 0; index < triangle.length; index++) {
      await setNumber(field(page, 'vertex'), index + 1);
      for (const axis of ['x', 'y', 'z']) await setNumber(coord(page, axis), triangle[index][axis]);
    }
    await button(page, 'apply').click(); await page.locator('.path-editor').waitFor({ state: 'detached' });
    assert.equal(await page.locator('#layers .layer-row').count(), 1);
    await page.locator('#duplicate').click();
    await setNumber(page.locator('[data-prop="rotation.z"]'), 180);
    await page.locator('#camera-view').selectOption('front'); await page.locator('#fit-view').click();
    await page.waitForFunction(() => { const saved = JSON.parse(localStorage.getItem('gravity-shape-studio-v1')); return saved?.layers.length === 2 && saved.layers[1].rotation.z === 180; });
    const saved = await page.evaluate(() => JSON.parse(localStorage.getItem('gravity-shape-studio-v1')));
    assert.ok(saved.layers.every(layer => layer.type === 'path' && layer.path.closed));
    assert.deepEqual(saved.layers[0].path.points, triangle);
    assert.deepEqual(saved.layers[1].path.points, triangle);
    await page.screenshot({ path: path.join(os.tmpdir(), 'gravity-custom-outline-scene.png') });
    await page.reload(); await page.locator('#layers .layer-row').first().waitFor();
    assert.equal(await page.locator('#layers .layer-row').count(), 2, 'Custom geometry survives autosave reload');
    await page.locator('#export').click();
    const lua = await page.locator('#export-code').inputValue();
    assert.equal((lua.match(/\["type"\] = "path"/g) || []).length, 2);
    assert.equal((lua.match(/\["closed"\] = true/g) || []).length, 2);
    assert.ok(lua.includes('{0, 60, 0}') && lua.includes('{-51.9615, -30, 0}'), 'Export retains arbitrary vertex coordinates');
    assert.ok(lua.includes('["z"] = 180'), 'Export retains rotation of overlapping layer');
    const downloadPromise = page.waitForEvent('download'); await page.locator('#download-lua').click();
    const download = await downloadPromise; assert.match(download.suggestedFilename(), /\.lua$/);
    assert.equal(fs.readFileSync(await download.path(), 'utf8'), lua);
    assert.deepEqual(errors, [], 'No browser exceptions');
    console.log('Path editor: isolated drafts, drawing and closing, exact coordinates, planes, drag and snap, undo/redo, freehand, keyboard, apply, and mobile touch passed.');
    console.log('Builder integration: drawn overlapping outlines, rotated duplicate, autosave reload, generated Lua and plugin download passed.');
  } finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
})().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
