// Optional browser coverage: portable projects remain usable beyond both the
// old 2 MB import cap and the browser's localStorage autosave quota.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const directory = path.resolve(__dirname, '..');
const server = http.createServer((request, response) => {
  const pathname = new URL(request.url, 'http://localhost').pathname;
  if (pathname === '/favicon.ico') { response.writeHead(204).end(); return; }
  let filename = path.resolve(directory, '.' + pathname);
  if (fs.existsSync(filename) && fs.statSync(filename).isDirectory()) filename = path.join(filename, 'index.html');
  if (!filename.startsWith(directory + path.sep) || !fs.existsSync(filename) || !fs.statSync(filename).isFile()) { response.writeHead(404).end(); return; }
  const type = filename.endsWith('.html') ? 'text/html' : filename.endsWith('.css') ? 'text/css' : 'text/javascript';
  response.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  fs.createReadStream(filename).pipe(response);
});

(async () => {
  const { createLayer, createProject, normalizeProject } = await import('../docs/plugins/builder/model.mjs');
  const { serializeProject } = await import('../docs/plugins/builder/project-file.mjs');
  const points = Array.from({ length: 4096 }, (_, index) => ({
    x: Math.sin(index * 0.13) * 25, y: Math.cos(index * 0.17) * 25, z: Math.sin(index * 0.11) * 25,
  }));
  const project = normalizeProject({ ...createProject('blank'), name: 'Large portable geometry', parts: 120,
    layers: Array.from({ length: 24 }, (_, index) => createLayer(index ? 'pointcloud' : 'path', {
      id: `large-${index}`, name: `Imported outline ${index + 1}`, path: { points, closed: !index },
    })),
  });
  assert.ok(JSON.stringify(project).length > 6 * 1024 * 1024, 'fixture must exceed Chromium localStorage quota');
  const buffer = Buffer.from(serializeProject(project));
  assert.ok(buffer.length > 2_000_000);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, reducedMotion: 'reduce' });
    page.setDefaultTimeout(30000);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${server.address().port}/docs/plugins/builder/`);
    await page.locator('#layers .layer-row').first().waitFor();
    const initialName = await page.locator('#project-name').inputValue();
    const initialLayers = await page.locator('#layers .layer-row').count();
    const [initialDownload] = await Promise.all([page.waitForEvent('download'), page.locator('#save-project').click()]);
    const initialBytes = fs.readFileSync(await initialDownload.path());
    const races = await page.evaluate(async initialText => {
      const input = document.querySelector('#project-file');
      const projectText = name => JSON.stringify({ ...JSON.parse(initialText), name });
      const start = text => {
        Object.defineProperty(input, 'files', { configurable: true, value: [{ size: 100, text }] });
        return input.onchange();
      };
      try {
        let finishOld;
        const old = start(() => new Promise(resolve => { finishOld = resolve; }));
        await start(async () => projectText('Newest selection'));
        finishOld(projectText('Stale selection')); await old;
        const latest = document.querySelector('#project-name').value;
        document.querySelector('#undo').click();
        const undoName = document.querySelector('#project-name').value;

        let rejectOld;
        const failed = start(() => new Promise((_, reject) => { rejectOld = reject; }));
        await start(async () => projectText('Newest after failure'));
        rejectOld(new Error('An obsolete read failed')); await failed;
        const notice = document.querySelector('#toast').textContent;

        let finishEdited;
        const pending = start(() => new Promise(resolve => { finishEdited = resolve; }));
        const name = document.querySelector('#project-name');
        name.value = 'Edited while reading'; name.dispatchEvent(new Event('change'));
        finishEdited(projectText('Do not overwrite edits')); await pending;
        return { latest, undoName, notice, edited: name.value, cancelled: document.querySelector('#toast').textContent };
      } finally { delete input.files; }
    }, initialBytes.toString('utf8'));
    assert.equal(races.latest, 'Newest selection', 'a slow older file cannot replace the latest selected project');
    assert.equal(races.undoName, initialName, 'a discarded read does not add an undo step');
    assert.match(races.notice, /Newest after failure opened/, 'a stale failure cannot replace the latest import status');
    assert.equal(races.edited, 'Edited while reading', 'edits made during file reading remain intact');
    assert.match(races.cancelled, /import cancelled/);
    await page.locator('#project-file').setInputFiles({ name: 'initial.gravity.json', mimeType: 'application/json', buffer: initialBytes });
    await page.waitForFunction(() => document.querySelector('#save-status').textContent === 'All changes saved locally');

    await page.locator('#project-file').setInputFiles({ name: 'large.gravity.json', mimeType: 'application/json', buffer });
    await page.waitForFunction(() => document.querySelector('#project-name').value === 'Large portable geometry');
    assert.equal(await page.locator('#layers .layer-row').count(), project.layers.length);
    await page.waitForFunction(() => document.querySelector('#save-status').textContent.includes('Browser storage is full'));
    assert.match(await page.locator('#save-status').textContent(), /download a project to save/);
    assert.equal(await page.evaluate(() => JSON.parse(localStorage.getItem('gravity-shape-studio-v1')).name), initialName, 'quota failure preserves the last successful autosave');
    const [largeDownload] = await Promise.all([page.waitForEvent('download'), page.locator('#save-project').click()]);
    assert.equal(await largeDownload.failure(), null);
    const downloaded = fs.readFileSync(await largeDownload.path());
    assert.deepEqual(JSON.parse(downloaded.toString('utf8')), project, 'all imported coordinates survive Save');

    await page.reload();
    await page.locator('#layers .layer-row').first().waitFor();
    assert.equal(await page.locator('#project-name').inputValue(), initialName, 'reload still restores the last successful autosave');
    assert.equal(await page.locator('#layers .layer-row').count(), initialLayers);
    await page.locator('#project-file').setInputFiles({ name: largeDownload.suggestedFilename(), mimeType: 'application/json', buffer: downloaded });
    await page.waitForFunction(() => document.querySelector('#project-name').value === 'Large portable geometry');
    const [reopenedDownload] = await Promise.all([page.waitForEvent('download'), page.locator('#save-project').click()]);
    assert.deepEqual(fs.readFileSync(await reopenedDownload.path()), downloaded, 'downloaded project reopens exactly after losing unsaved browser state');

    const invalid = Buffer.from(JSON.stringify({ version: 1, layers: Array(65).fill({ type: 'sphere' }) }));
    await page.locator('#project-file').setInputFiles({ name: 'invalid.gravity.json', mimeType: 'application/json', buffer: invalid });
    await page.waitForFunction(() => document.querySelector('#toast').textContent.includes('64 layers'));
    assert.equal(await page.locator('#project-name').inputValue(), project.name, 'invalid project preserves the active project');
    assert.equal(await page.locator('#layers .layer-row').count(), project.layers.length);
    assert.deepEqual(errors, []);
    console.log(`Builder project browser: ${downloaded.length.toLocaleString('en-US')} byte download/reopen, autosave quota guidance and invalid-import preservation passed.`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => server.close());
