// Focused browser regression for preview-only tracking of a stable debris slot.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const directory = path.resolve(__dirname, '../docs/plugins/builder');
const server = http.createServer((request, response) => {
  const pathname = new URL(request.url, 'http://localhost').pathname;
  if (pathname === '/') {
    response.writeHead(200, { 'Content-Type': 'text/html' }).end('<!doctype html><html lang="en"><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{margin:0}canvas{display:block;width:100vw;height:70vh;touch-action:none}</style></head><body><canvas id="preview" tabindex="0" aria-label="Formation preview"></canvas></body></html>');
    return;
  }
  if (pathname === '/favicon.ico') { response.writeHead(204).end(); return; }
  const filename = path.resolve(directory, '.' + pathname);
  if (!filename.startsWith(directory + path.sep) || !fs.existsSync(filename) || !fs.statSync(filename).isFile()) { response.writeHead(404).end(); return; }
  response.writeHead(200, { 'Content-Type': 'text/javascript', 'Cache-Control': 'no-store' });
  fs.createReadStream(filename).pipe(response);
});

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE });
  try {
    const errors = [];
    async function setup(page) {
      page.on('pageerror', error => errors.push(error.message));
      await page.goto(`http://127.0.0.1:${server.address().port}/`);
      await page.evaluate(async () => {
        const { Viewport } = await import('/viewport.mjs');
        window.selections = [];
        const viewport = window.viewport = new Viewport(document.querySelector('canvas'), { onSelect(id) { window.selections.push(id); } });
        window.defaultTracking = viewport.options.trackPart;
        viewport.setOptions({ grid: false, axes: false, core: false, move: false });
        viewport.setView('front'); viewport.view = 'perspective';
        viewport.target = { x: 0, y: 0, z: 0 }; viewport.distance = 100;
        const drawTracked = viewport._drawTrackedPart;
        const fillText = viewport.ctx.fillText.bind(viewport.ctx);
        const arc = viewport.ctx.arc.bind(viewport.ctx);
        window.drawing = { tracked: [], labels: [], rings: [] };
        viewport._drawTrackedPart = function(item) {
          window.drawing.tracked.push({ index: item.index, layerId: item.point.layerId, x: item.x, y: item.y, depth: item.depth });
          return drawTracked.call(this, item);
        };
        viewport.ctx.fillText = function(text, x, y, ...args) {
          if (text === 'PART 1') window.drawing.labels.push({ text, x, y, width: this.measureText(text).width, fill: this.fillStyle });
          return fillText(text, x, y, ...args);
        };
        viewport.ctx.arc = function(x, y, radius, ...args) {
          window.drawing.rings.push({ x, y, radius });
          return arc(x, y, radius, ...args);
        };
        window.renderFrame = ({ points, selected = null, track = true } = {}) => {
          window.drawing = { tracked: [], labels: [], rings: [] };
          viewport.setSelected(selected); viewport.setOptions({ trackPart: track });
          if (points) viewport.setPoints(points);
          viewport.render();
          return {
            ...window.drawing,
            projected: viewport._projected.map(({ index, x, y, depth }) => ({ index, x, y, depth })),
            camera: { target: viewport.target, yaw: viewport.yaw, pitch: viewport.pitch, distance: viewport.distance, view: viewport.view },
            width: viewport.width, height: viewport.height,
            points: JSON.stringify(viewport.points),
          };
        };
      });
    }
    const page = await browser.newPage({ viewport: { width: 900, height: 700 } });
    await setup(page);
    assert.equal(await page.evaluate(() => window.defaultTracking), false);
    const points = [
      { x: -12, y: 0, z: 30, layerId: 'a', color: '#ffdb8a' },
      { x: 12, y: 0, z: -30, layerId: 'a', color: '#b7f399' },
      { x: 0, y: 12, z: 0, layerId: 'b', color: '#b8a4ff' },
    ];
    const render = options => page.evaluate(options => window.renderFrame(options), options);
    const off = await render({ points, selected: 'a', track: false });
    assert.deepEqual(off.labels, []); assert.deepEqual(off.rings, []); assert.deepEqual(off.tracked, []);
    const initial = await render({ points, selected: 'a' });
    assert.equal(initial.tracked.length, 1); assert.equal(initial.tracked[0].index, 0);
    assert.deepEqual(initial.projected.map(item => item.index), [1, 2, 0], 'depth order differs from sample order');
    assert.equal(initial.labels.length, 1); assert.equal(initial.rings.length, 1);
    assert.deepEqual(initial.rings.map(({ x, y }) => ({ x, y })), initial.tracked.map(({ x, y }) => ({ x, y })));
    assert.deepEqual(initial.camera, off.camera, 'tracking never pans, orbits or zooms');
    assert.equal(initial.points, JSON.stringify(points), 'drawing and sorting never mutate samples');
    assert.deepEqual(initial.projected, off.projected, 'overlay never becomes a pick target');

    const movedPoints = [{ ...points[0], x: -9, y: 6, z: -40 }, { ...points[1], z: 40 }, points[2]];
    const moved = await render({ points: movedPoints, selected: 'a' });
    assert.deepEqual(moved.projected.map(item => item.index), [0, 2, 1], 'moving samples cross in depth');
    assert.equal(moved.tracked[0].index, 0, 'same debris slot is tracked after the depth order reverses');
    assert.notEqual(moved.tracked[0].x, initial.tracked[0].x);
    assert.notEqual(moved.tracked[0].y, initial.tracked[0].y);
    assert.deepEqual(moved.camera, initial.camera);
    const selectedB = await render({ selected: 'b' });
    assert.equal(selectedB.tracked[0].index, 2); assert.equal(selectedB.tracked[0].layerId, 'b');
    const unselected = await render({ selected: null });
    assert.equal(unselected.tracked[0].index, 0);
    const missing = await render({ selected: 'hidden-layer' });
    assert.equal(missing.labels.length, 0); assert.equal(missing.tracked.length, 0);

    // Culling the first sample must not silently select the next visible part.
    for (const first of [
      { ...points[0], x: 100000 }, { ...points[0], z: 101 }, { ...points[0], z: 99.75 },
    ]) {
      const hidden = await render({ points: [first, points[1], points[2]], selected: 'a' });
      assert.equal(hidden.labels.length, 0); assert.equal(hidden.rings.length, 0);
      assert.ok(hidden.projected.some(item => item.index === 1), 'another selected-layer sample is still visible');
    }
    const edge = await page.evaluate(points => {
      const viewport = window.viewport;
      const x = (-1 - viewport.width / 2) * viewport.distance / viewport._focal;
      return window.renderFrame({ points: [{ ...points[0], x, y: 0, z: 0 }, points[1]], selected: 'a' });
    }, points);
    assert.ok(edge.projected.some(item => item.index === 0), 'part just beyond the edge remains in the block culling margin');
    assert.equal(edge.labels.length, 0); assert.equal(edge.rings.length, 0, 'offscreen center cannot show a pinned marker');
    const invalid = await page.evaluate(points => window.renderFrame({ points: [{ ...points[0], x: NaN }, points[1]], selected: 'a' }), points);
    assert.equal(invalid.labels.length, 0);

    // Actual animated model samples preserve marker identity and export bytes.
    const animation = await page.evaluate(async () => {
      const { createLayer, normalizeProject, sampleProject } = await import('/model.mjs');
      const { exportLua } = await import('/exporter.mjs');
      const layer = createLayer('ring', { spin: 90, radius: 24, tube: 0, position: { x: 0, y: 0, z: 0 } });
      const project = normalizeProject({ version: 1, parts: 128, layers: [layer] });
      const before = JSON.stringify(project), lua = exportLua(project);
      const first = window.renderFrame({ points: sampleProject(project, 0), selected: layer.id });
      const second = window.renderFrame({ points: sampleProject(project, .5), selected: layer.id });
      const disabled = window.renderFrame({ track: false, selected: layer.id });
      return { first, second, disabled, sameProject: JSON.stringify(project) === before, sameLua: exportLua(project) === lua };
    });
    assert.equal(animation.first.tracked[0].index, 0); assert.equal(animation.second.tracked[0].index, 0);
    assert.notEqual(animation.first.tracked[0].x, animation.second.tracked[0].x);
    assert.equal(animation.disabled.labels.length, 0); assert.equal(animation.disabled.rings.length, 0);
    assert.equal(animation.sameProject, true); assert.equal(animation.sameLua, true);

    const mobile = await browser.newPage({ viewport: { width: 320, height: 500 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });
    await setup(mobile);
    const small = await mobile.evaluate(() => {
      const viewport = window.viewport;
      // Keep the first point near the right/top boundary to exercise label flip.
      const x = (viewport.width - 2 - viewport.width / 2) * viewport.distance / viewport._focal;
      const y = (viewport.height / 2 - 2) * viewport.distance / viewport._focal;
      return window.renderFrame({ points: [{ x, y, z: 0, layerId: 'edge', color: '#b7f399' }, { x: -12, y: 0, z: 0, layerId: 'other', color: '#b8a4ff' }], selected: 'edge' });
    });
    assert.equal(small.labels.length, 1);
    const badge = small.labels[0];
    assert.ok(badge.x >= 5 && badge.x + badge.width + 5 <= small.width);
    assert.ok(badge.y >= 9 && badge.y + 9 <= small.height);
    const other = small.projected.find(item => item.index === 1);
    await mobile.touchscreen.tap(other.x, other.y);
    const selected = await mobile.evaluate(() => { window.viewport.render(); return { selected: window.viewport.selected, selections: window.selections, points: window.viewport.points.length }; });
    assert.equal(selected.selected, 'other'); assert.deepEqual(selected.selections, ['other']); assert.equal(selected.points, 2);
    // The badge itself does not select, move, or add a part.
    await mobile.touchscreen.tap(badge.x + badge.width / 2, badge.y);
    assert.equal(await mobile.evaluate(() => window.viewport.selected), null);
    if (process.env.BUILDER_SCREENSHOT_DIR) {
      const screenshotDirectory = path.resolve(process.env.BUILDER_SCREENSHOT_DIR);
      fs.mkdirSync(screenshotDirectory, { recursive: true });
      await mobile.evaluate(() => { window.viewport.setSelected('other'); window.viewport.render(); });
      await mobile.screenshot({ path: path.join(screenshotDirectory, 'tracked-part-mobile.png') });
    }
    await mobile.evaluate(() => window.viewport.destroy());
    await page.evaluate(() => window.viewport.destroy());
    assert.deepEqual(errors, []);
    console.log('Builder tracking: stable animated slot, depth sorting, selection, clipping, disabled mode, camera/export isolation and mobile rendering/touch passed.');
  } finally { await browser.close(); server.close(); }
})().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
