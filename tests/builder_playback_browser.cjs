// Real-app playback and part-movement regressions. Playwright is development-only.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { tmpdir } = require('node:os');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const directory = path.resolve(__dirname, '..');
const server = http.createServer((request, response) => {
  const pathname = new URL(request.url, 'http://localhost').pathname;
  if (pathname === '/favicon.ico') { response.writeHead(204).end(); return; }
  let filename = path.resolve(directory, '.' + pathname);
  if (fs.existsSync(filename) && fs.statSync(filename).isDirectory()) filename = path.join(filename, 'index.html');
  if (!filename.startsWith(directory + path.sep) || !fs.existsSync(filename) || !fs.statSync(filename).isFile()) { response.writeHead(404).end(); return; }
  response.writeHead(200, { 'Content-Type': filename.endsWith('.html') ? 'text/html' : filename.endsWith('.css') ? 'text/css' : 'text/javascript', 'Cache-Control': 'no-store' });
  fs.createReadStream(filename).pipe(response);
});
const screenshotDirectory = path.resolve(process.env.BUILDER_SCREENSHOT_DIR || path.join(tmpdir(), 'gravity-motion-review'));

(async () => {
  const { createLayer, createProject, normalizeProject } = await import('../docs/plugins/builder/model.mjs');
  const nodes = [{ x: -35, y: -12, z: 0 }, { x: -12, y: 22, z: 14 }, { x: 8, y: -8, z: -10 }, { x: 35, y: 14, z: 0 }];
  const fixture = (type, name) => normalizeProject({ ...createProject('blank'), name, layers: [createLayer(type, {
    id: 'moving-shape', name: 'My custom shape', position: { x: 0, y: 20, z: 0 }, path: { points: nodes, closed: false, smooth: false },
  })] });
  const staticPath = fixture('path', 'Custom path playback');
  const pointCloud = fixture('pointcloud', 'Point cloud movement');
  fs.mkdirSync(screenshotDirectory, { recursive: true });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE });
  try {
    const errors = [];
    const base = `http://127.0.0.1:${server.address().port}`;
    async function setup(options) {
      const page = await browser.newPage({ reducedMotion: 'reduce', ...options });
      page.on('pageerror', error => errors.push(error.message));
      // Observe inputs to the real renderer without exposing a runtime test API
      // or replacing the app's model, animation scheduler, or draw operations.
      await page.route('**/viewport.mjs', async route => {
        const original = fs.readFileSync(path.join(directory, 'docs/plugins/builder/viewport.mjs'), 'utf8');
        await route.fulfill({ contentType: 'text/javascript', body: original + `
const originalSetPoints = Viewport.prototype.setPoints;
Viewport.prototype.setPoints = function(points) {
  if (this.canvas.id === 'viewport') {
    const data = window.playbackProbe ||= { count: 0, points: [], signature: '' };
    data.count++;
    data.points = points.map(({x,y,z,layerId}) => ({x,y,z,layerId}));
    data.signature = JSON.stringify(data.points);
  }
  return originalSetPoints.call(this, points);
};
` });
      });
      await page.goto(base + '/docs/plugins/builder/');
      await page.locator('#layers .layer-row').first().waitFor();
      return page;
    }
    const paint = page => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    async function importProject(page, project) {
      await page.locator('#project-file').setInputFiles({ name: 'movement.gravity.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(project)) });
      await page.waitForFunction(name => document.querySelector('#project-name').value === name, project.name);
      await paint(page);
    }
    async function playing(page, value) {
      const active = await page.locator('#play-pause').getAttribute('aria-label') === 'Pause animation';
      if (active !== value) await page.locator('#play-pause').click();
      await paint(page);
      // The visible clock refreshes every 60 ms; let it publish the final pose.
      if (!value) await page.waitForTimeout(85);
    }
    async function edit(page, property, value) {
      const field = page.locator('#prop-' + property);
      await field.fill(String(value)); await field.dispatchEvent('change'); await paint(page);
    }
    async function snapshot(page) {
      return page.evaluate(() => ({
        ...window.playbackProbe, time: Number(document.querySelector('#preview-time').value),
        canvas: document.querySelector('#viewport').toDataURL(),
      }));
    }
    async function download(page) {
      const [file] = await Promise.all([page.waitForEvent('download'), page.locator('#save-project').click()]);
      assert.equal(await file.failure(), null);
      return JSON.parse(fs.readFileSync(await file.path(), 'utf8'));
    }
    async function addControl(page, property, name, min, max, value) {
      await page.locator(`[data-expose="${property}"]`).click();
      assert.equal(await page.locator('#control-property').inputValue(), property);
      await page.locator('#control-name').fill(name);
      await page.locator('#control-min').fill(String(min)); await page.locator('#control-max').fill(String(max));
      await page.locator('#control-default').fill(String(value));
      await page.locator('#control-form button[type="submit"]').click();
      await page.locator('#control-dialog').waitFor({ state: 'hidden' });
    }
    async function noOverflow(page) {
      const bounds = await page.evaluate(() => ({ viewport: innerWidth, width: document.documentElement.scrollWidth }));
      assert.ok(bounds.width <= bounds.viewport, JSON.stringify(bounds));
    }
    const page = await setup({ viewport: { width: 1440, height: 1000 } });
    await importProject(page, staticPath);
    assert.equal(await page.locator('#part-count').inputValue(), '128');
    await playing(page, true);
    await page.waitForFunction(() => document.querySelector('#preview-status').textContent === 'No movement configured');
    assert.equal(await page.locator('#motion-hint').isVisible(), true);
    assert.match(await page.locator('#motion-hint-text').textContent(), /path flow|movement distance/);
    const still = await snapshot(page);
    await page.waitForFunction(time => Number(document.querySelector('#preview-time').value) > time + .2, still.time);
    const stillLater = await snapshot(page);
    assert.equal(stillLater.signature, still.signature, 'Play advances time but does not animate unconfigured custom geometry');
    assert.equal(stillLater.canvas, still.canvas, 'unconfigured canvas remains still');
    await page.screenshot({ path: path.join(screenshotDirectory, 'playback-static-desktop.png') });
    await page.locator('#configure-movement').click();
    assert.equal(await page.locator('[data-section="part-motion"]').getAttribute('open'), '');
    assert.equal(await page.locator('#prop-flowSpeed').isVisible(), true);
    await page.screenshot({ path: path.join(screenshotDirectory, 'part-movement-desktop.png') });

    await edit(page, 'flowSpeed', 17);
    await page.waitForFunction(() => document.querySelector('#preview-status').textContent === 'Live preview');
    assert.equal(await page.locator('#motion-hint').isVisible(), false);
    const flowing = await snapshot(page);
    await page.waitForFunction(signature => window.playbackProbe.signature !== signature, flowing.signature);
    const flowed = await snapshot(page);
    assert.notEqual(flowed.canvas, flowing.canvas, 'path flow changes the actual drawing');
    await page.locator('#undo').click();
    assert.equal(await page.locator('#prop-flowSpeed').inputValue(), '0');
    await page.locator('#redo').click();
    assert.equal(await page.locator('#prop-flowSpeed').inputValue(), '17');
    await playing(page, false);
    const paused = await snapshot(page);
    await page.waitForTimeout(220);
    const pausedLater = await snapshot(page);
    assert.equal(pausedLater.signature, paused.signature); assert.equal(pausedLater.canvas, paused.canvas);
    assert.equal(pausedLater.time, paused.time, 'pause freezes the clock and the debris');
    await playing(page, true);
    await page.waitForFunction(signature => window.playbackProbe.signature !== signature, paused.signature);

    await playing(page, false);
    const beforeTrack = await download(page);
    await page.locator('#toggle-part-tracker').click();
    assert.equal(await page.locator('#toggle-part-tracker').getAttribute('aria-pressed'), 'true');
    assert.match(await page.locator('#toggle-part-tracker').textContent(), /Tracking part 1/);
    assert.deepEqual(await download(page), beforeTrack, 'part tracking is preview-only');
    await addControl(page, 'flowSpeed', 'Travel speed', -30, 30, 17);
    await page.locator('#properties-tab').click();
    const savedPath = await download(page);
    assert.equal(savedPath.layers[0].flowSpeed, 17);
    for (const key of ['position', 'rotation', 'scale', 'path']) assert.deepEqual(savedPath.layers[0][key], staticPath.layers[0][key], `flow preserves ${key}`);
    assert.equal(savedPath.layers[0].spin, 0);
    assert.equal(savedPath.controls[0].property, 'flowSpeed');
    await page.locator('#export').click();
    const pathLua = await page.locator('#export-code').inputValue();
    assert.match(pathLua, /Travel speed/); assert.match(pathLua, /flowSpeed/);
    await page.locator('#export-dialog [data-close]').click();
    await page.reload();
    await page.locator('#layers .layer-row').first().waitFor();
    await importProject(page, savedPath);
    assert.deepEqual(await download(page), savedPath, 'new motion property and control reopen exactly');

    await importProject(page, pointCloud);
    await page.locator('#properties-tab').click();
    if (await page.locator('[data-section="part-motion"]').getAttribute('open') === null) await page.locator('[data-section="part-motion"] > summary').click();
    assert.equal(await page.locator('#prop-flowSpeed').count(), 0, 'point clouds expose offsets instead of path flow');
    await edit(page, 'partMoveX', 9); await edit(page, 'partMoveY', 7); await edit(page, 'partMoveZ', 5);
    await edit(page, 'partMoveSpeed', .4); await edit(page, 'partMoveSpread', 1.5);
    await playing(page, true);
    const cloud = await snapshot(page);
    await page.waitForFunction(time => Number(document.querySelector('#preview-time').value) > time + .15, cloud.time);
    const moved = await snapshot(page);
    for (const axis of ['x', 'y', 'z']) assert.notEqual(cloud.points[0][axis], moved.points[0][axis], `individual ${axis} offsets move the sampled debris`);
    assert.notEqual(cloud.canvas, moved.canvas);
    await edit(page, 'timeScale', 0);
    await page.waitForFunction(() => document.querySelector('#preview-status').textContent === 'Layer clocks frozen');
    assert.equal(await page.locator('#motion-hint').isVisible(), true);
    assert.match(await page.locator('#motion-hint-text').textContent(), /Time scale/);
    const frozen = await snapshot(page);
    await page.waitForFunction(time => Number(document.querySelector('#preview-time').value) > time + .15, frozen.time);
    assert.equal((await snapshot(page)).signature, frozen.signature, 'zero layer time scale freezes the pose while global Play continues');
    await page.locator('#configure-movement').click();
    assert.equal(await page.locator('[data-section="spin"]').getAttribute('open'), '');
    await edit(page, 'timeScale', 1);
    await page.waitForFunction(() => document.querySelector('#preview-status').textContent === 'Live preview');
    await playing(page, false);
    await addControl(page, 'partMoveX', 'Horizontal drift', 0, 25, 9);
    const savedCloud = await download(page);
    for (const [property, value] of Object.entries({ partMoveX: 9, partMoveY: 7, partMoveZ: 5, partMoveSpeed: .4, partMoveSpread: 1.5 })) assert.equal(savedCloud.layers[0][property], value);
    assert.deepEqual(savedCloud.layers[0].position, pointCloud.layers[0].position);
    assert.deepEqual(savedCloud.layers[0].rotation, pointCloud.layers[0].rotation);
    assert.deepEqual(savedCloud.layers[0].path, pointCloud.layers[0].path);
    await page.locator('#export').click();
    const cloudLua = await page.locator('#export-code').inputValue();
    assert.match(cloudLua, /Horizontal drift/); assert.match(cloudLua, /partMoveX/); assert.match(cloudLua, /partMovePhaseY/);
    await page.locator('#export-dialog [data-close]').click();
    await importProject(page, savedCloud);
    assert.deepEqual(await download(page), savedCloud);
    await noOverflow(page);

    const mobile = await setup({ viewport: { width: 320, height: 760 }, isMobile: true, hasTouch: true });
    await importProject(mobile, { ...staticPath, name: 'A very long custom formation with flowing paths and moving debris' }); await playing(mobile, true);
    await mobile.waitForFunction(() => document.querySelector('#preview-status').textContent === 'No movement configured');
    await mobile.locator('#motion-hint').scrollIntoViewIfNeeded();
    await noOverflow(mobile);
    const caption = await mobile.evaluate(() => {
      const title = document.querySelector('#scene-name');
      const status = document.querySelector('#preview-status').getBoundingClientRect();
      const tools = document.querySelector('.manipulation-tools').getBoundingClientRect();
      const camera = document.querySelector('#camera-view').getBoundingClientRect();
      const style = getComputedStyle(title), bounds = title.getBoundingClientRect();
      return { statusBottom: status.bottom, toolbarTop: tools.top, titleRight: bounds.right, cameraLeft: camera.left,
        titleWidth: title.clientWidth, textWidth: title.scrollWidth, whiteSpace: style.whiteSpace, textOverflow: style.textOverflow };
    });
    assert.ok(caption.statusBottom <= caption.toolbarTop, 'mobile playback status stays above the movement toolbar: ' + JSON.stringify(caption));
    assert.ok(caption.titleRight <= caption.cameraLeft, 'long scene title does not intersect the camera selector: ' + JSON.stringify(caption));
    assert.ok(caption.textWidth > caption.titleWidth, 'fixture exercises a title wider than its available space');
    assert.equal(caption.whiteSpace, 'nowrap'); assert.equal(caption.textOverflow, 'ellipsis');
    await mobile.screenshot({ path: path.join(screenshotDirectory, 'playback-static-mobile.png'), fullPage: true });
    await mobile.locator('.canvas-area').screenshot({ path: path.join(screenshotDirectory, 'playback-caption-mobile.png') });
    await mobile.locator('#configure-movement').click();
    assert.equal(await mobile.locator('#prop-flowSpeed').isVisible(), true);
    await mobile.locator('[data-section="part-motion"]').scrollIntoViewIfNeeded();
    await noOverflow(mobile);
    await mobile.screenshot({ path: path.join(screenshotDirectory, 'part-movement-mobile.png'), fullPage: true });
    await edit(mobile, 'flowSpeed', 12);
    await mobile.locator('#toggle-part-tracker').click();
    assert.equal(await mobile.locator('#toggle-part-tracker').getAttribute('aria-pressed'), 'true');
    await mobile.locator('.site-navigation a').filter({ hasText: 'Plugin guide' }).click();
    await mobile.waitForURL(base + '/docs/plugins/');
    await mobile.goBack();
    await mobile.locator('.brand').click(); await mobile.waitForURL(base + '/');
    await noOverflow(mobile);
    assert.deepEqual(errors, []);
    console.log('Builder playback UI: static guidance, flowing debris, XYZ movement, clock freezing, pause/resume, tracking, undo/redo, controls, JSON/Lua and mobile navigation passed.');
  } finally { await browser.close(); server.close(); }
})().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
