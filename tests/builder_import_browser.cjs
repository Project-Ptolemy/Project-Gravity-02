// Optional real-browser coverage for SVG geometry and the source editor.
// Set PLAYWRIGHT_MODULE when Playwright is installed outside this repository.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const directory = path.resolve(__dirname, '../docs/plugins/builder');
const server = http.createServer((request, response) => {
  const pathname = new URL(request.url, 'http://localhost').pathname;
  if (pathname === '/') {
    response.writeHead(200, { 'Content-Type': 'text/html' }).end('<!doctype html><html><head><link rel="stylesheet" href="/style.css"><link rel="stylesheet" href="/editors/source-editor.css"></head><body></body></html>');
    return;
  }
  if (pathname === '/favicon.ico') { response.writeHead(204).end(); return; }
  const filename = path.resolve(directory, '.' + pathname);
  if (!filename.startsWith(directory + path.sep) || !fs.existsSync(filename) || !fs.statSync(filename).isFile()) { response.writeHead(404).end(); return; }
  response.writeHead(200, { 'Content-Type': filename.endsWith('.html') ? 'text/html' : filename.endsWith('.css') ? 'text/css' : 'text/javascript', 'Cache-Control': 'no-store' });
  fs.createReadStream(filename).pipe(response);
});

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE });
  try {
    const page = await browser.newPage({ viewport: { width: 1400, height: 1000 } });
    const errors = [], unexpectedRequests = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (!request.url().startsWith('http://127.0.0.1:')) unexpectedRequests.push(request.url()); });
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    const results = await page.evaluate(async () => {
      const { readSVG } = await import('/importers/geometry.mjs');
      const { normalizeProject, createLayer } = await import('/model.mjs');
      const svg = markup => `<svg xmlns="http://www.w3.org/2000/svg">${markup}</svg>`;
      const imports = {
        relative: readSVG(svg('<path d="M0 0 h10 m5 5 10 0 M0 20 l10 0 z m5 5 10 0"/>'), { size: 100, detail: 8 }),
        polygon: readSVG(svg('<polygon id="outline" points="0,0 10,0 3,7"/>'), { size: 10, detail: 8 }),
        transformed: readSVG(svg('<g transform="rotate(90)"><line x1="0" y1="0" x2="10" y2="0"/></g>'), { size: 10 }),
        rootTransform: readSVG('<svg xmlns="http://www.w3.org/2000/svg" transform="rotate(90)"><line x2="10"/></svg>', { size: 10 }),
        viewBox: readSVG('<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 10 10" preserveAspectRatio="none"><polygon points="0,0 10,0 10,10 0,10"/></svg>', { size: 20 }),
        nested: readSVG(svg('<svg x="10" y="10" width="200" height="100" viewBox="0 0 10 10" preserveAspectRatio="none"><polygon points="0,0 10,0 10,10 0,10"/></svg>'), { size: 20 }),
        safe: readSVG(svg('<script>window.svgExecuted=true</script><image href="https://invalid.example/image"/><foreignObject><iframe src="https://invalid.example/frame"/></foreignObject><style>@import url(https://invalid.example/style);</style><use href="https://invalid.example/source#item"/><line x2="10" onload="window.svgExecuted=true"/>'), { size: 10 }),
      };
      const invalid = ['<not-svg/>', '<svg><path></svg>', svg('<text>hello</text>'), svg('<path d="M0 0"/>')].map(source => { try { readSVG(source); return null; } catch (error) { return error.message; } });
      for (const layers of Object.values(imports)) normalizeProject({ version: 1, layers: layers.map(spec => createLayer(spec.type, spec)) });
      return { imports, invalid, executed: !!window.svgExecuted, temporarySVGs: document.querySelectorAll('svg').length };
    });
    assert.equal(results.imports.relative.length, 4, 'separate movetos stay separate contours');
    const relative = results.imports.relative.map(layer => layer.path.points);
    assert.deepEqual(relative.map(points => [points[0].x, points[0].y]), [[-50, 50], [10, 30], [-50, -30], [-30, -50]]);
    assert.equal(results.imports.relative[2].path.closed, true);
    assert.equal(results.imports.polygon[0].path.points.length, 3, 'polygon corners remain exact nodes');
    assert.deepEqual(results.imports.polygon[0].path.points, [{ x: -5, y: 3.5, z: 0 }, { x: 5, y: 3.5, z: 0 }, { x: -2, y: -3.5, z: 0 }]);
    for (const key of ['transformed', 'rootTransform']) {
      const points = results.imports[key][0].path.points;
      assert.ok(points.every(point => Math.abs(point.x) < 1e-8));
      assert.ok(Math.abs(points[0].y - points[1].y - 10) < 1e-8, key + ' transforms are preserved');
    }
    for (const key of ['viewBox', 'nested']) {
      const points = results.imports[key][0].path.points;
      assert.equal(Math.max(...points.map(p => p.x)) - Math.min(...points.map(p => p.x)), 20);
      assert.equal(Math.max(...points.map(p => p.y)) - Math.min(...points.map(p => p.y)), 10);
    }
    assert.ok(results.invalid.every(Boolean));
    assert.equal(results.imports.safe.length, 1);
    assert.equal(results.executed, false); assert.equal(results.temporarySVGs, 0);
    assert.deepEqual(unexpectedRequests, [], 'source SVG cannot mount scripts or fetch external resources');

    async function open(mode, remainingLayers = 64) {
      await page.evaluate(async ({ mode, remainingLayers }) => {
        const { openSourceEditor } = await import('/editors/source-editor.mjs');
        window.applied = null;
        openSourceEditor({ mode, remainingLayers, onApply(specs) { window.applied = specs; } });
      }, { mode, remainingLayers });
      await page.locator('#source-editor').waitFor();
    }
    await open('coordinates');
    assert.equal(await page.locator('#source-error').textContent(), '', 'coordinate preview succeeds');
    await page.locator('#source-coordinates-type').selectOption('pointcloud');
    await page.locator('#source-coordinates').fill('[[1,2,3],[7,8,9],[4,5,6]]');
    await page.locator('#source-apply').click();
    await page.locator('#source-editor').waitFor({ state: 'detached' });
    const points = await page.evaluate(() => window.applied);
    assert.equal(points[0].type, 'pointcloud'); assert.equal(points[0].path.points.length, 3);

    await open('formula');
    assert.equal(await page.locator('#source-error').textContent(), '', 'formula curve preview succeeds');
    await page.locator('#source-formula-mode').selectOption('surface');
    await page.locator('#source-formula-samples').fill('8');
    await page.locator('#source-formula-rows').fill('4');
    await page.locator('#source-formula-x').fill('20 * (u - 0.5)');
    await page.locator('#source-formula-y').fill('5 * sin(tau * u)');
    await page.locator('#source-formula-z').fill('10 * (v - 0.5)');
    await page.locator('#source-preview-button').click();
    assert.match(await page.locator('#source-summary').textContent(), /32 vertices/);
    assert.equal(await page.locator('#source-error').textContent(), '');
    await page.locator('#source-apply').click();
    await page.locator('#source-editor').waitFor({ state: 'detached' });
    const surface = await page.evaluate(() => window.applied[0]);
    assert.equal(surface.type, 'pointcloud'); assert.equal(surface.path.points.length, 32);
    assert.equal(surface.path.points[0].x, -10); assert.equal(surface.path.points.at(-1).z, 5);

    await open('svg', 1);
    await page.locator('#source-svg').fill('<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0L10 0 M0 10L10 10"/></svg>');
    await page.locator('#source-apply').click();
    assert.match(await page.locator('#source-error').textContent(), /room for 1/);
    assert.equal(await page.evaluate(() => window.applied), null);
    await page.locator('#source-svg').fill('<svg xmlns="http://www.w3.org/2000/svg"><polygon points="0,0 10,0 5,10"/></svg>');
    await page.locator('#source-apply').click();
    await page.locator('#source-editor').waitFor({ state: 'detached' });
    assert.equal((await page.evaluate(() => window.applied[0].path.points)).length, 3);

    // Exercise the real app callbacks: one import is one undo, and geometry
    // survives both JSON files and browser restore before exporting to Lua.
    await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
    await page.locator('#layers .layer-row').first().waitFor();
    const initialLayers = await page.locator('#layers .layer-row').count();
    await page.locator('#import-geometry').click();
    await page.locator('#source-svg').fill('<svg xmlns="http://www.w3.org/2000/svg"><polygon points="0,0 10,0 5,10"/><path d="M15 0L25 0L20 10Z"/></svg>');
    await page.locator('#source-preview-button').click();
    assert.equal(await page.locator('#source-error').textContent(), '');
    await page.locator('#source-apply').click();
    await page.locator('#source-editor').waitFor({ state: 'detached' });
    assert.equal(await page.locator('#layers .layer-row').count(), initialLayers + 2);
    await page.locator('#undo').click();
    assert.equal(await page.locator('#layers .layer-row').count(), initialLayers);
    await page.locator('#redo').click();
    assert.equal(await page.locator('#layers .layer-row').count(), initialLayers + 2);

    await page.locator('#formula-geometry').click();
    await page.locator('#source-formula-mode').selectOption('surface');
    await page.locator('#source-formula-samples').fill('8');
    await page.locator('#source-formula-rows').fill('4');
    await page.locator('#source-formula-z').fill('20 * (v - 0.5)');
    await page.locator('#source-apply').click();
    await page.locator('#source-editor').waitFor({ state: 'detached' });
    assert.equal(await page.locator('#layers .layer-row').count(), initialLayers + 3);

    const [jsonDownload] = await Promise.all([page.waitForEvent('download'), page.locator('#save-project').click()]);
    assert.equal(await jsonDownload.failure(), null);
    const savedBytes = fs.readFileSync(await jsonDownload.path());
    const saved = JSON.parse(savedBytes.toString('utf8'));
    const imported = saved.layers.slice(initialLayers);
    assert.deepEqual(imported.map(layer => layer.type), ['path', 'path', 'pointcloud']);
    assert.equal(imported[0].path.points.length, 3); assert.equal(imported[2].path.points.length, 32);
    assert.ok(imported.every(layer => layer.spin === 0 && layer.tube === 0));
    await page.waitForFunction(count => JSON.parse(localStorage.getItem('gravity-shape-studio-v1'))?.layers.length === count, initialLayers + 3);
    await page.reload();
    await page.locator('#layers .layer-row').first().waitFor();
    assert.equal(await page.locator('#layers .layer-row').count(), initialLayers + 3);
    await page.locator('#project-file').setInputFiles({ name: 'roundtrip.gravity.json', mimeType: 'application/json', buffer: savedBytes });
    await page.waitForFunction(count => document.querySelectorAll('#layers .layer-row').length === count, initialLayers + 3);
    const [roundTripDownload] = await Promise.all([page.waitForEvent('download'), page.locator('#save-project').click()]);
    assert.deepEqual(JSON.parse(fs.readFileSync(await roundTripDownload.path(), 'utf8')), saved);
    await page.locator('#export').click();
    const lua = await page.locator('#export-code').inputValue();
    assert.ok(lua.includes('["type"] = "pointcloud"') && lua.includes('["type"] = "path"'));
    assert.ok(lua.includes('compile_path(layer.geometry)') && lua.includes('local function sample_path'));
    const [luaDownload] = await Promise.all([page.waitForEvent('download'), page.locator('#download-lua').click()]);
    assert.equal(fs.readFileSync(await luaDownload.path(), 'utf8'), lua);
    await page.locator('#export-dialog [data-close]').click();
    if (process.env.BUILDER_SCREENSHOT_DIR) {
      const screenshotDirectory = path.resolve(process.env.BUILDER_SCREENSHOT_DIR);
      fs.mkdirSync(screenshotDirectory, { recursive: true });
      await page.screenshot({ path: path.join(screenshotDirectory, 'imported-geometry-scene.png'), fullPage: true });
      await page.locator('#formula-geometry').click();
      await page.screenshot({ path: path.join(screenshotDirectory, 'formula-editor.png'), fullPage: true });
    }
    assert.deepEqual(errors, []);
    console.log('Builder imports: SVG contours/transforms/security, source previews, real imports/undo, point clouds, formula surfaces, JSON restore and Lua exports passed.');
  } finally { await browser.close(); server.close(); }
})().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
