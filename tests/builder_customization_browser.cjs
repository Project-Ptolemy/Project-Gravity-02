// End-to-end composition of vertex edits, surfaces and repeated layers.
// Playwright is a separately installed development tool, never an app dependency.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const server = http.createServer((request, response) => {
  const pathname = new URL(request.url, 'http://localhost').pathname;
  if (pathname === '/favicon.ico') { response.writeHead(204).end(); return; }
  let filename = path.resolve(root, '.' + pathname);
  if (!filename.startsWith(root + path.sep)) { response.writeHead(403).end(); return; }
  if (fs.existsSync(filename) && fs.statSync(filename).isDirectory()) filename = path.join(filename, 'index.html');
  if (!fs.existsSync(filename) || !fs.statSync(filename).isFile()) { response.writeHead(404).end(); return; }
  const type = filename.endsWith('.html') ? 'text/html' : filename.endsWith('.css') ? 'text/css' : 'text/javascript';
  response.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  fs.createReadStream(filename).pipe(response);
});
async function save(page) {
  const [file] = await Promise.all([page.waitForEvent('download'), page.locator('#save-project').click()]);
  assert.equal(await file.failure(), null);
  return JSON.parse(fs.readFileSync(await file.path(), 'utf8'));
}
async function importProject(page, project) {
  await page.locator('#project-file').setInputFiles({ name: 'custom.gravity.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(project)) });
  await page.waitForFunction(name => document.getElementById('project-name').value === name, project.name);
}
async function screenshot(page, name) {
  if (!process.env.BUILDER_SCREENSHOT_DIR) return;
  fs.mkdirSync(process.env.BUILDER_SCREENSHOT_DIR, { recursive: true });
  await page.screenshot({ path: path.join(process.env.BUILDER_SCREENSHOT_DIR, name + '.png') });
}

(async () => {
  const { createLayer, createProject, normalizeProject } = await import('../docs/plugins/builder/model.mjs');
  const fixture = normalizeProject({ ...createProject('blank'), name: 'Custom workshop', parts: 256,
    layers: [createLayer('path', { id: 'profile', name: 'My profile', color: '#eec288',
      position: { x: 30, y: 40, z: -2 }, rotation: { z: 20 }, scale: { x: 1.2 },
      path: { points: [{ x: 5, y: -10, z: 0 }, { x: 15, y: 0, z: 0 }, { x: 5, y: 10, z: 0 }] },
    })], controls: [{ id: 'profile-x', name: 'My chosen position', layerId: 'profile', property: 'position.x', min: -100, max: 100, default: 42 }],
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE });
  const url = `http://127.0.0.1:${server.address().port}/docs/plugins/builder/`;
  const errors = [];
  const watch = page => { page.on('pageerror', error => errors.push(error.message)); page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); }); };
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, reducedMotion: 'reduce', acceptDownloads: true });
    watch(page); await page.goto(url); await page.locator('#layers .layer-row').first().waitFor();
    assert.equal(await page.locator('#part-count').inputValue(), '128');
    await page.waitForFunction(() => document.getElementById('point-count').textContent === '128 parts');
    await importProject(page, fixture);
    assert.equal(await page.locator('#part-count').inputValue(), '256', 'existing projects retain their saved debris count');

    await page.locator('#edit-path').click();
    await page.locator('.path-editor [data-action="select-all"]').click();
    await page.locator('.path-editor-transforms summary').click();
    await page.locator('.path-editor [data-transform="move.x"]').fill('3');
    await page.locator('.path-editor [data-action="transform-selection"]').click();
    await screenshot(page, 'workshop-vertices-desktop');
    await page.locator('.path-editor [data-action="apply"]').click();
    const edited = await save(page);
    assert.deepEqual(edited.layers[0].path.points, fixture.layers[0].path.points.map(p => ({ ...p, x: p.x + 3 })));
    await page.locator('#undo').click(); assert.deepEqual((await save(page)).layers[0].path, fixture.layers[0].path);
    await page.locator('#redo').click();

    await page.locator('#make-surface').click();
    await page.locator('#surface-depth').fill('12');
    await page.locator('#surface-samples').fill('8');
    await page.locator('#surface-rows').fill('3');
    await page.waitForFunction(() => document.getElementById('surface-summary').textContent.includes('24 points'));
    await screenshot(page, 'workshop-surface-desktop');
    await page.locator('#surface-apply').click();
    await page.locator('#surface-editor').waitFor({ state: 'detached' });
    const surfaced = await save(page);
    assert.equal(surfaced.layers.length, 2);
    assert.deepEqual(surfaced.layers[0], edited.layers[0], 'surface generation preserves the source');
    assert.equal(surfaced.layers[1].type, 'pointcloud');
    assert.equal(surfaced.layers[1].path.points.length, 24);
    assert.equal(surfaced.layers[1].position.x, 42, 'surface uses bound transform defaults');
    assert.equal(surfaced.layers[1].color, fixture.layers[0].color);
    assert.equal(Math.max(...surfaced.layers[1].path.points.map(p => p.z)), 12);
    await page.locator('#undo').click(); assert.equal(await page.locator('#layers .layer-row').count(), 1);
    await page.locator('#redo').click(); assert.equal(await page.locator('#layers .layer-row').count(), 2);

    await page.locator('[data-layer="profile"] .layer-select').click();
    await page.locator('#repeat-layer').click();
    await page.locator('#repeat-count').fill('2');
    await page.locator('#repeat-position-x').fill('20');
    await page.locator('#repeat-preview-button').click();
    await screenshot(page, 'workshop-repeat-desktop');
    await page.locator('#repeat-apply').click();
    await page.locator('#repeat-editor').waitFor({ state: 'detached' });
    const repeated = await save(page);
    assert.equal(repeated.layers.length, 4); assert.equal(repeated.controls.length, 3);
    assert.deepEqual(repeated.layers.slice(2).map(layer => layer.position.x), [62, 82]);
    assert.ok(repeated.controls.every(control => control.name === 'My chosen position'));
    assert.equal(new Set(repeated.controls.map(control => control.id)).size, 3);
    await page.locator('#undo').click();
    assert.equal(await page.locator('#layers .layer-row').count(), 2);
    assert.equal((await save(page)).controls.length, 1);
    await page.locator('#redo').click();
    assert.deepEqual(await save(page), repeated, 'redo restores exactly the same arrangement and controls');
    await page.waitForFunction(() => document.getElementById('save-status').textContent === 'All changes saved locally');
    await page.reload(); await page.locator('#layers .layer-row').first().waitFor();
    assert.deepEqual(await save(page), repeated, 'all tools survive autosave/reload');
    await page.locator('#export').click();
    const lua = await page.locator('#export-code').inputValue();
    assert.match(lua, /pointcloud/); assert.match(lua, /My chosen position/); assert.match(lua, /function M\.f2/);
    await page.locator('#export-dialog [data-close]').click();

    const mobile = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, reducedMotion: 'reduce' });
    watch(mobile); await mobile.goto(url); await mobile.locator('#layers .layer-row').first().waitFor();
    await importProject(mobile, repeated);
    await mobile.locator('#make-surface').tap();
    await mobile.locator('#surface-mode').selectOption('revolve');
    assert.ok(await mobile.locator('#surface-editor').evaluate(dialog => dialog.scrollWidth <= dialog.clientWidth));
    await screenshot(mobile, 'workshop-surface-mobile');
    await mobile.locator('#surface-apply').tap();
    await mobile.locator('#surface-editor').waitFor({ state: 'detached' });
    assert.equal(await mobile.locator('#layers .layer-row').count(), 5);
    await mobile.locator('#repeat-layer').tap();
    await mobile.locator('#repeat-mode').selectOption('radial');
    assert.ok(await mobile.locator('#repeat-editor').evaluate(dialog => dialog.scrollWidth <= dialog.clientWidth));
    await screenshot(mobile, 'workshop-repeat-mobile');
    await mobile.locator('#repeat-editor [data-repeat-dismiss]').first().tap();
    assert.equal(await mobile.locator('#layers .layer-row').count(), 5, 'mobile cancellation adds nothing');
    assert.deepEqual(errors, [], 'integrated tools emit no browser errors');
    console.log('Builder customization: 128-part default, old projects, vertex→surface→repeat workflow, source/control preservation, undo/redo, autosave, Lua export and mobile passed.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => server.close());
