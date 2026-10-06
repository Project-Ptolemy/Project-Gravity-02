// Optional browser integration for the control types exposed by the editor.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const server = http.createServer((request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  if (pathname === '/favicon.ico') { response.writeHead(204).end(); return; }
  let filename = path.resolve(root, '.' + pathname);
  if (!filename.startsWith(root + path.sep)) { response.writeHead(404).end(); return; }
  if (fs.existsSync(filename) && fs.statSync(filename).isDirectory()) filename = path.join(filename, 'index.html');
  if (!fs.existsSync(filename) || !fs.statSync(filename).isFile()) { response.writeHead(404).end(); return; }
  response.writeHead(200, { 'Content-Type': filename.endsWith('.html') ? 'text/html' : filename.endsWith('.css') ? 'text/css' : 'text/javascript' });
  fs.createReadStream(filename).pipe(response);
});

(async () => {
  const { createLayer, createProject } = await import('../docs/plugins/builder/model.mjs');
  const project = { ...createProject('blank'), name: 'Browser controls', layers: [
    createLayer('path', { id: 'first', spin: 25, path: { points: [{ x: -20, y: 0, z: 3 }, { x: 15, y: 30, z: -10 }] } }),
    createLayer('sphere', { id: 'second', radius: 8, position: { x: 30, y: 20, z: 0 } }),
  ] };
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, reducedMotion: 'reduce' });
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(project => { if (!localStorage.getItem('gravity-shape-studio-v1')) localStorage.setItem('gravity-shape-studio-v1', JSON.stringify(project)); }, project);
    await page.goto(`http://127.0.0.1:${server.address().port}/docs/plugins/builder/`);
    await page.locator('#layers .layer-row').first().waitFor();
    await page.locator('#controls-tab').click();
    await page.locator('[data-new-control="toggle"]').click();
    await page.locator('#control-name').fill('My deliberate name');
    await page.locator('#control-type').selectOption('slider');
    await page.locator('#control-layer').selectOption('second');
    await page.locator('#control-property').selectOption('radius');
    await page.locator('#control-type').selectOption('button');
    await page.locator('#control-action').selectOption('reverse');
    assert.equal(await page.locator('#control-name').inputValue(), 'My deliberate name');
    await page.locator('#control-type').selectOption('toggle');
    await page.locator('#control-property').selectOption('fill');
    await page.locator('#control-layer').selectOption('first');
    await page.locator('#control-property').selectOption('visible');
    assert.equal(await page.locator('#control-name').inputValue(), 'My deliberate name');
    await page.locator('#control-form button[type="submit"]').click();
    await page.locator('#control-dialog').waitFor({ state: 'hidden' });
    await page.locator('[data-preview-toggle]').uncheck();
    assert.equal(await page.locator('[data-preview-toggle]').isChecked(), false);
    await page.locator('#reset-controls').click();
    assert.equal(await page.locator('[data-preview-toggle]').isChecked(), true);

    for (const action of ['reverse', 'restart', 'reset']) {
      await page.locator('[data-new-control="button"]').click();
      await page.locator('#control-layer').selectOption('first');
      await page.locator('#control-action').selectOption(action);
      await page.locator('#control-name').fill(`Custom ${action}`);
      await page.locator('#control-form button[type="submit"]').click();
      await page.locator('#control-dialog').waitFor({ state: 'hidden' });
    }
    const paint = () => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await page.evaluate(() => { const time = document.getElementById('preview-time'); time.value = '6'; time.dispatchEvent(new Event('change')); });
    await paint();
    const before = await page.locator('#viewport').evaluate(canvas => canvas.toDataURL());
    await page.getByRole('button', { name: 'Custom reverse', exact: true }).click();
    await paint();
    assert.equal(await page.locator('#viewport').evaluate(canvas => canvas.toDataURL()), before, 'reversing preserves the current pose');
    await page.getByRole('button', { name: 'Custom restart', exact: true }).click();
    await paint();
    assert.notEqual(await page.locator('#viewport').evaluate(canvas => canvas.toDataURL()), before, 'restart updates the preview');
    await page.getByRole('button', { name: 'Custom reset', exact: true }).click();
    await paint();
    assert.equal(await page.locator('#viewport').evaluate(canvas => canvas.toDataURL()), before, 'reset restores the original clock');
    await page.locator('[data-preview-toggle]').uncheck();
    const [download] = await Promise.all([page.waitForEvent('download'), page.locator('#save-project').click()]);
    const saved = JSON.parse(fs.readFileSync(await download.path(), 'utf8'));
    assert.deepEqual(saved.controls.map(control => control.type), ['toggle', 'button', 'button', 'button']);
    assert.equal(saved.controls[0].default, true, 'temporary switches do not change project defaults');
    assert.equal(saved.controls[0].name, 'My deliberate name');
    await page.locator('#export').click();
    const lua = await page.locator('#export-code').inputValue();
    assert.match(lua, /Type = "Toggle"/); assert.equal((lua.match(/Type = "Button"/g) || []).length, 3);
    assert.match(lua, /Callback = function\(c, x6\) run_action/);
    await page.locator('#export-dialog [data-close]').click();
    await page.waitForFunction(() => JSON.parse(localStorage.getItem('gravity-shape-studio-v1')).controls.length === 4);
    await page.reload();
    await page.locator('#controls-tab').click();
    assert.equal(await page.locator('[data-preview-toggle]').isChecked(), true);
    assert.equal(await page.locator('[data-run-control]').count(), 3);
    await page.locator('.control-card').filter({ has: page.getByRole('button', { name: 'Custom reverse', exact: true }) }).locator('[data-delete-control]').click();
    assert.equal(await page.locator('[data-run-control]').count(), 2);

    const inheritedIds = { ...project, name: 'Imported identifier names', layers: [
      { ...project.layers[0], id: 'constructor' }, { ...project.layers[1], id: '__proto__' },
    ], controls: [
      { id: 'constructor', type: 'slider', name: 'Imported spin', layerId: 'constructor', property: 'spin', min: -360, max: 360, default: 25 },
      { id: '__proto__', type: 'toggle', name: 'Imported visibility', layerId: 'constructor', property: 'visible', default: false },
      { id: 'toString', type: 'button', name: 'Imported reverse', layerId: 'constructor', action: 'reverse' },
    ] };
    await page.locator('#project-file').setInputFiles({ name: 'inherited-ids.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(inheritedIds)) });
    await page.waitForFunction(() => document.querySelector('#project-name').value === 'Imported identifier names');
    await page.locator('#controls-tab').click();
    assert.equal(await page.locator('#preview-constructor').inputValue(), '25');
    assert.equal(await page.locator('[data-preview-toggle="__proto__"]').isChecked(), false);
    await page.locator('#preview-constructor').fill('42');
    await page.locator('[data-preview-toggle="__proto__"]').check();
    await page.locator('[data-run-control="toString"]').click();
    assert.equal(await page.locator('#preview-constructor').inputValue(), '42');
    assert.equal(await page.locator('[data-preview-toggle="__proto__"]').isChecked(), true);
    await page.locator('#reset-controls').click();
    assert.equal(await page.locator('#preview-constructor').inputValue(), '25');
    assert.equal(await page.locator('[data-preview-toggle="__proto__"]').isChecked(), false);
    assert.deepEqual(errors, []);
    console.log('Builder control UI: name preservation, type changes, toggles, live actions, JSON restore, Lua export and deletion passed.');
  } finally { await browser.close(); server.close(); }
})().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
