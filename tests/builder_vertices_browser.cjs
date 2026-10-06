const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const server = http.createServer((request, response) => {
  if (request.url === '/') {
    response.setHeader('Content-Type', 'text/html');
    response.end('<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1"><link rel="stylesheet" href="/docs/plugins/builder/editors/path-editor.css"><button>Open</button>'); return;
  }
  const target = path.resolve(root, `.${decodeURIComponent(new URL(request.url, 'http://localhost').pathname)}`);
  if (!target.startsWith(root + path.sep) || !fs.existsSync(target)) { response.writeHead(404); response.end(); return; }
  response.setHeader('Content-Type', target.endsWith('.css') ? 'text/css' : 'text/javascript'); response.end(fs.readFileSync(target));
});
const source = { points: [{ x: -60, y: 0, z: 0 }, { x: 60, y: 0, z: 0 }, { x: 0, y: 60, z: 30 }], closed: true, smooth: false };
const action = (page, name) => page.locator(`.path-editor [data-action="${name}"]`).last();
const field = (page, name) => page.locator(`.path-editor [data-field="${name}"]`);
const coord = (page, axis) => page.locator(`.path-editor [data-coordinate="${axis}"]`);
const transform = (page, name, axis) => page.locator(`.path-editor [data-transform="${name}.${axis}"]`);
const setNumber = async (input, value) => { await input.fill(String(value)); await input.press('Tab'); };
async function open(page) {
  await page.evaluate(async input => {
    const { openPathEditor } = await import('/docs/plugins/builder/editors/path-editor.mjs');
    window.original = structuredClone(input); window.applied = null;
    openPathEditor({ path: window.original, onApply: value => { window.applied = value; } });
  }, source);
  await page.waitForSelector('.path-editor[open]'); await page.waitForTimeout(60);
}
async function canvasLocations(page) {
  const canvas = page.locator('.path-editor canvas'); await canvas.scrollIntoViewIfNeeded();
  const box = await canvas.boundingBox();
  const scale = Math.min(250, (box.width - 86) / 120, (box.height - 86) / 60);
  return { box, scale, points: source.points.map(point => ({ x: box.x + box.width / 2 + point.x * scale, y: box.y + box.height / 2 - (point.y - 30) * scale })) };
}

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true });
  const errors = [];
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 920 } });
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${server.address().port}/`); await open(page);
    await action(page, 'select-none').click();
    assert.equal(await field(page, 'selection-count').textContent(), '0 selected');
    assert.equal(await coord(page, 'x').isDisabled(), true);
    let positions = await canvasLocations(page);
    await page.keyboard.down('Shift');
    await page.mouse.click(positions.points[0].x, positions.points[0].y); await page.mouse.click(positions.points[1].x, positions.points[1].y);
    await page.keyboard.up('Shift');
    assert.equal(await field(page, 'selection-count').textContent(), '2 selected', 'Shift-click accumulates a selection');
    await page.mouse.move(positions.points[1].x, positions.points[1].y); await page.mouse.down();
    await page.mouse.move(positions.points[1].x + 5 * positions.scale, positions.points[1].y - 10 * positions.scale, { steps: 5 }); await page.mouse.up();
    assert.equal(await coord(page, 'x').inputValue(), '65'); assert.equal(await coord(page, 'y').inputValue(), '10');
    await action(page, 'undo').click(); assert.equal(await coord(page, 'x').inputValue(), '60');
    assert.equal(await field(page, 'selection-count').textContent(), '2 selected', 'Undo restores the selected group');
    await page.locator('.path-editor-transforms summary').click();
    await setNumber(transform(page, 'move', 'x'), 100); await setNumber(transform(page, 'rotate', 'z'), 90); await setNumber(transform(page, 'scale', 'x'), 2);
    await action(page, 'transform-selection').click();
    assert.equal(await coord(page, 'x').inputValue(), '100'); assert.equal(await coord(page, 'y').inputValue(), '120');
    await setNumber(field(page, 'flatten-value'), 42); await action(page, 'flatten-selection').click();
    assert.equal(await coord(page, 'z').inputValue(), '42');
    await action(page, 'undo').click(); assert.equal(await coord(page, 'z').inputValue(), '0');
    await action(page, 'redo').click(); assert.equal(await coord(page, 'z').inputValue(), '42');
    await setNumber(transform(page, 'move', 'x'), 10000); await action(page, 'transform-selection').click();
    assert.match(await page.locator('.path-editor-status').textContent(), /every coordinate/);
    assert.equal(await coord(page, 'x').inputValue(), '100', 'Invalid transforms leave all vertices intact');
    await page.screenshot({ path: path.join(os.tmpdir(), 'gravity-vertex-selection-desktop.png') });
    await action(page, 'apply').click();
    assert.deepEqual(await page.evaluate(() => window.applied.points), [{ x: 100, y: -120, z: 42 }, { x: 100, y: 120, z: 42 }, source.points[2]]);
    assert.deepEqual(await page.evaluate(() => window.original), source);

    await open(page); await page.locator('.path-editor canvas').focus(); await page.keyboard.press('Control+a');
    assert.equal(await field(page, 'selection-count').textContent(), '3 selected');
    await page.keyboard.press('Delete'); assert.equal(await field(page, 'count').textContent(), '0 vertices'); assert.equal(await action(page, 'apply').isDisabled(), true);
    await action(page, 'undo').click(); assert.equal(await field(page, 'selection-count').textContent(), '3 selected');
    await action(page, 'select-invert').click(); assert.equal(await field(page, 'selection-count').textContent(), '0 selected');
    await page.locator('[data-mode="select"]').click(); positions = await canvasLocations(page);
    await page.mouse.move(positions.points[0].x - 20, positions.points[0].y - 15); await page.mouse.down();
    await page.mouse.move(positions.points[1].x + 20, positions.points[1].y + 15, { steps: 5 }); await page.mouse.up();
    assert.equal(await field(page, 'selection-count').textContent(), '2 selected', 'Box selection selects vertices inside the current projection');
    await page.locator('.path-editor canvas').focus(); await page.keyboard.press('Shift+ArrowRight');
    assert.equal(await coord(page, 'x').inputValue(), '70');
    await action(page, 'cancel').click(); assert.equal(await page.evaluate(() => window.applied), null); assert.deepEqual(await page.evaluate(() => window.original), source);

    const mobile = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
    mobile.on('pageerror', error => errors.push(error.message));
    await mobile.goto(`http://127.0.0.1:${server.address().port}/`); await open(mobile);
    await action(mobile, 'select-none').click(); await mobile.locator('[data-mode="select"]').click(); positions = await canvasLocations(mobile);
    await mobile.touchscreen.tap(positions.points[0].x, positions.points[0].y); await mobile.touchscreen.tap(positions.points[1].x, positions.points[1].y);
    assert.equal(await field(mobile, 'selection-count').textContent(), '2 selected', 'Select mode supports additive touch selection without a keyboard');
    await mobile.locator('.path-editor-transforms summary').click(); await setNumber(transform(mobile, 'move', 'z'), 25); await action(mobile, 'transform-selection').click();
    assert.equal(await coord(mobile, 'z').inputValue(), '25');
    assert.ok(await mobile.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'Expanded controls fit a mobile viewport');
    const bounds = await mobile.locator('.path-editor').boundingBox(); assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= 390 && bounds.y >= 0 && bounds.y + bounds.height <= 844);
    await mobile.screenshot({ path: path.join(os.tmpdir(), 'gravity-vertex-selection-mobile.png') });
    await action(mobile, 'apply').click();
    assert.deepEqual(await mobile.evaluate(() => window.applied.points), [{ x: -60, y: 0, z: 25 }, { x: 60, y: 0, z: 25 }, source.points[2]]);
    assert.deepEqual(errors, []);
    console.log('Vertex editor: group selection/drag, box selection, numeric transforms, flattening, limits, batch delete/undo, keyboard nudges, isolated drafts and mobile touch passed.');
  } finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
})().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
