// Optional integration suite. The app itself has no npm dependency.
// Install Playwright separately and run:
//   node tests/builder_browser.cjs
// Or set PLAYWRIGHT_MODULE to an absolute playwright / playwright-core package path.
// PLAYWRIGHT_CHROMIUM_EXECUTABLE can select an existing Chromium executable.
// BUILDER_SCREENSHOT_DIR optionally saves desktop/mobile review images.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');

function loadPlaywright() {
  const candidates = process.env.PLAYWRIGHT_MODULE
    ? [process.env.PLAYWRIGHT_MODULE] : ['playwright', 'playwright-core'];
  for (const candidate of candidates) {
    try { return require(candidate); } catch (error) {
      if (error.code !== 'MODULE_NOT_FOUND') throw error;
    }
  }
  throw new Error('Install playwright separately, or set PLAYWRIGHT_MODULE to its package path. See README.md.');
}

function serveSite() {
  const root = path.resolve(__dirname, '..');
  const mime = { '.html': 'text/html', '.css': 'text/css', '.mjs': 'text/javascript', '.js': 'text/javascript', '.json': 'application/json', '.txt': 'text/plain', '.svg': 'image/svg+xml' };
  const server = http.createServer((req, res) => {
    try {
      const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
      if (pathname === '/favicon.ico') { res.writeHead(204).end(); return; }
      let filename = path.resolve(root, '.' + pathname);
      if (filename !== root && !filename.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
      if (fs.existsSync(filename) && fs.statSync(filename).isDirectory()) filename = path.join(filename, 'index.html');
      if (!fs.existsSync(filename)) { res.writeHead(404).end(); return; }
      res.writeHead(200, { 'Content-Type': mime[path.extname(filename)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      fs.createReadStream(filename).pipe(res);
    } catch { res.writeHead(400).end(); }
  });
  return new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve({
    server, url: `http://127.0.0.1:${server.address().port}/docs/plugins/builder/`,
  })));
}

async function nextPaint(page) {
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
}

async function openDisclosure(disclosure) {
  if (!await disclosure.evaluate(element => element.open)) {
    await disclosure.locator(':scope > summary').click();
  }
}

async function editNumber(page, selector, value) {
  const input = typeof selector === 'string' ? page.locator(selector) : selector;
  // Inspector groups and sidebar settings may be collapsed or retain the
  // user's previous open state. Reveal fields through their real summaries.
  for (const disclosure of await input.locator('xpath=ancestor::details').all()) {
    await openDisclosure(disclosure);
  }
  await input.fill(String(value));
  await input.press('Tab');
  await nextPaint(page);
}

async function download(page, button) {
  const [result] = await Promise.all([page.waitForEvent('download'), page.locator(button).click()]);
  assert.equal(await result.failure(), null, 'download should complete');
  return { name: result.suggestedFilename(), bytes: fs.readFileSync(await result.path()) };
}

async function screenshot(page, name) {
  if (!process.env.BUILDER_SCREENSHOT_DIR) return;
  const directory = path.resolve(process.env.BUILDER_SCREENSHOT_DIR);
  fs.mkdirSync(directory, { recursive: true });
  await page.screenshot({ path: path.join(directory, name + '.png'), fullPage: true });
}

async function navigation(page, builderUrl, device) {
  const home = new URL('../../../', builderUrl).href;
  const guide = new URL('../', builderUrl).href;
  const fits = async label => assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), `${device}: ${label} should fit horizontally`);
  const activate = async locator => device === 'desktop' ? locator.click() : locator.tap();
  await page.goto(home);
  assert.equal(page.url(), home, 'homepage must stay at root, not redirect to the guide');
  assert.match(await page.title(), /Project Gravity/);
  assert.match(await page.locator('h1').textContent(), /Give your ideas/);
  await fits('homepage');
  await screenshot(page, 'home-' + device);
  await activate(page.locator('.hero .primary'));
  await page.locator('#layers .layer-row').first().waitFor();
  assert.equal(page.url(), builderUrl);
  await fits('builder');
  await activate(page.locator('.brand'));
  await page.waitForURL(home);
  assert.equal(page.url(), home, 'builder brand returns home');
  await activate(page.locator('.topbar nav a[href="docs/plugins/"]'));
  await page.waitForURL(guide);
  assert.equal(page.url(), guide, 'plugin guide has its own URL');
  await page.locator('#prompt').waitFor();
  await fits('plugin guide');
  if (process.env.BUILDER_SCREENSHOT_DIR) {
    await page.screenshot({ path: path.join(path.resolve(process.env.BUILDER_SCREENSHOT_DIR), 'guide-' + device + '.png') });
  }
  await activate(page.locator('.topbar nav a[href="builder/"]'));
  await page.locator('#layers .layer-row').first().waitFor();
  assert.equal(page.url(), builderUrl, 'guide links to builder');
  await activate(page.locator('#keyboard-help'));
  assert.match(await page.locator('#help-dialog').textContent(), /freehand/);
  assert.match(await page.locator('#help-dialog').textContent(), /formulas/);
  await fits('quick guide');
  await activate(page.locator('#help-dialog [data-close]'));
  await activate(page.locator('.site-navigation a[href="../"]'));
  await page.waitForURL(guide);
  assert.equal(page.url(), guide, 'builder retains a dedicated guide link');
  await activate(page.locator('.topbar nav a[href="../../"]'));
  await page.waitForURL(home);
  assert.equal(page.url(), home, 'guide navigation returns home');
}

async function desktop(page, url) {
  await page.goto(url);
  await page.locator('#layers .layer-row').first().waitFor();
  const initialLayers = await page.locator('#layers .layer-row').count();
  assert.ok(initialLayers >= 2, 'a ready-to-edit example should open');
  assert.ok(await page.locator('#viewport').evaluate(canvas => canvas.width > 0 && canvas.height > 0));
  await page.locator('#play-pause').click();
  await nextPaint(page);
  await screenshot(page, 'builder-desktop');

  const partCount = await page.locator('#point-count').textContent();
  await page.locator('#toggle-core').click();
  assert.equal(await page.locator('#toggle-core').getAttribute('aria-pressed'), 'false');
  assert.equal(await page.locator('#point-count').textContent(), partCount, 'the preview core is not a formation part');
  await page.locator('#toggle-core').click();
  assert.equal(await page.locator('#toggle-core').getAttribute('aria-pressed'), 'true');
  await page.locator('#toggle-move').click();
  assert.equal(await page.locator('#toggle-move').getAttribute('aria-pressed'), 'false');
  await page.locator('#toggle-move').click();

  const starters = page.locator('details.sidebar-disclosure.presets-section');
  await openDisclosure(starters);
  assert.ok(await starters.locator('.preset-card').first().isVisible());
  await starters.locator(':scope > summary').click();
  const previewSettings = page.locator('details.sidebar-disclosure.preview-settings');
  await openDisclosure(previewSettings);
  assert.ok(await page.locator('#part-count').isVisible());
  assert.ok(await page.locator('#point-size').isVisible());
  await editNumber(page, '#preview-time', 0);
  await page.locator('#frame-forward').click();
  assert.ok(Number(await page.locator('#preview-time').inputValue()) > 0, 'frame controls advance the paused preview');
  await editNumber(page, '#preview-time', 0);
  await previewSettings.locator(':scope > summary').click();

  await page.locator('#add-shape').click();
  await page.locator('[data-add-type="sphere"]').click();
  assert.equal(await page.locator('#layers .layer-row').count(), initialLayers + 1);
  const addedId = await page.locator('#layers .layer-row.selected').getAttribute('data-layer');
  for (const [section, properties] of Object.entries({
    spin: ['timeScale', 'timeOffset'],
    orbit: ['orbitRadius', 'orbitAspect', 'orbitSpeed', 'orbitTiltX', 'orbitTiltZ', 'orbitPhase'],
    bob: ['bobAmount', 'bobSpeed', 'bobPhase'],
    pulse: ['pulsePhase'],
    wave: ['waveCount', 'wavePhase'],
    deform: ['twist', 'taper', 'scatter'],
  })) {
    const group = page.locator(`details.property-group[data-section="${section}"]`);
    await openDisclosure(group);
    for (const property of properties) {
      assert.ok(await group.locator(`input[type="number"][data-prop="${property}"]`).isVisible(), `${property} is editable in ${section}`);
    }
    if (section !== 'spin') await group.locator(':scope > summary').click();
  }
  const radius = 'input[type="number"][data-prop="radius"]';
  const originalRadius = await page.locator(radius).inputValue();
  const beforeEdit = await page.locator('#viewport').evaluate(canvas => canvas.toDataURL());
  await editNumber(page, radius, 37.5);
  assert.equal(await page.locator(radius).inputValue(), '37.5');
  assert.notEqual(await page.locator('#viewport').evaluate(canvas => canvas.toDataURL()), beforeEdit, 'editing geometry changes the preview');
  await page.locator('#undo').click();
  assert.equal(await page.locator(radius).inputValue(), originalRadius);
  await page.locator('#redo').click();
  assert.equal(await page.locator(radius).inputValue(), '37.5');
  await editNumber(page, 'input[type="number"][data-prop="position.x"]', 18);

  await page.locator('#duplicate').click();
  assert.equal(await page.locator('#layers .layer-row').count(), initialLayers + 2);
  const duplicate = page.locator('#layers .layer-row.selected');
  assert.notEqual(await duplicate.getAttribute('data-layer'), addedId, 'duplicate has independent identity');
  await duplicate.locator('.layer-visibility').click();
  assert.ok((await duplicate.getAttribute('class')).includes('invisible'));
  await duplicate.locator('.layer-visibility').click();
  assert.ok(!(await duplicate.getAttribute('class')).includes('invisible'));
  await page.locator('#delete-layer').click();
  assert.equal(await page.locator('#layers .layer-row').count(), initialLayers + 1);
  await page.locator(`[data-layer="${addedId}"] .layer-select`).click();

  await page.locator('#controls-tab').click();
  const initialControls = await page.locator('.control-card').count();
  await page.locator('#new-control').click();
  await page.locator('#control-name').fill('Custom sphere radius');
  await page.locator('#control-layer').selectOption(addedId);
  await page.locator('#control-property').selectOption('radius');
  await page.locator('#control-min').fill('1');
  await page.locator('#control-max').fill('100');
  await page.locator('#control-default').fill('37.5');
  await page.locator('#control-form button[type="submit"]').click();
  assert.equal(await page.locator('.control-card').count(), initialControls + 1);
  const customControl = page.locator('.control-card').filter({ hasText: 'Custom sphere radius' });
  await editNumber(page, customControl.locator('input[type="number"]'), 48);
  assert.equal(await customControl.locator('input[type="range"]').inputValue(), '48');

  await page.locator('#project-name').fill('Browser smoke formation');
  await page.locator('#project-name').press('Tab');
  const saved = await download(page, '#save-project');
  assert.match(saved.name, /\.json$/);
  const project = JSON.parse(saved.bytes.toString('utf8'));
  assert.equal(project.name, 'Browser smoke formation');
  assert.equal(project.layers.length, initialLayers + 1);
  assert.equal(project.controls.length, initialControls + 1);
  assert.equal(project.layers.find(layer => layer.id === addedId).position.x, 18);
  assert.equal(project.controls.find(control => control.name === 'Custom sphere radius').default, 37.5);

  await page.locator('#export').click();
  const lua = await page.locator('#export-code').inputValue();
  assert.match(lua, /function M\.f2\(/);
  assert.match(lua, /M\.Controls/);
  assert.match(lua, /Custom sphere radius/);
  const plugin = await download(page, '#download-lua');
  assert.match(plugin.name, /\.lua$/);
  assert.equal(plugin.bytes.toString('utf8'), lua);
  await page.locator('#export-dialog [data-close]').click();

  await page.locator('#project-name').fill('Temporary change');
  await page.locator('#project-name').press('Tab');
  await page.locator('#project-file').setInputFiles({ name: saved.name, mimeType: 'application/json', buffer: saved.bytes });
  await page.waitForFunction(() => document.querySelector('#project-name').value === 'Browser smoke formation');
  assert.equal(await page.locator('#layers .layer-row').count(), initialLayers + 1);
  await page.reload();
  await page.locator('#layers .layer-row').first().waitFor();
  assert.equal(await page.locator('#project-name').inputValue(), 'Browser smoke formation', 'autosave survives reload');

  await page.locator('#project-file').setInputFiles({ name: 'invalid.json', mimeType: 'application/json', buffer: Buffer.from('{invalid json') });
  await page.locator('#toast.show').waitFor();
  assert.equal(await page.locator('#project-name').inputValue(), 'Browser smoke formation', 'invalid import preserves current project');
  assert.equal(await page.locator('#layers .layer-row').count(), initialLayers + 1);
  await page.locator('#camera-view').selectOption('top');
  await page.locator('#fit-view').click();
  await page.locator('#toggle-grid').click();
  assert.equal(await page.locator('#toggle-grid').getAttribute('aria-pressed'), 'false');
  const preview = await download(page, '#screenshot');
  assert.match(preview.name, /\.png$/);
  assert.ok(preview.bytes.length > 1000, 'preview image has content');
}

async function mobile(page, url) {
  await page.goto(url);
  await page.locator('#layers .layer-row').first().waitFor();
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'mobile layout should not overflow horizontally');
  await screenshot(page, 'builder-mobile');
  const count = await page.locator('#layers .layer-row').count();
  await page.locator('#add-shape').tap();
  await page.locator('[data-add-type="torus"]').tap();
  assert.equal(await page.locator('#layers .layer-row').count(), count + 1);
  const orbitGroup = page.locator('details.property-group[data-section="orbit"]');
  await openDisclosure(orbitGroup);
  await editNumber(page, 'input[type="number"][data-prop="orbitRadius"]', 15);
  assert.equal(await page.locator('input[type="number"][data-prop="orbitRadius"]').inputValue(), '15');
  await page.locator('#controls-tab').tap();
  await page.locator('#new-control').tap();
  assert.ok(await page.locator('#control-name').isVisible());
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'mobile control dialog fits');
  await page.locator('#control-dialog [data-close]').first().tap();
  await page.locator('#viewport').scrollIntoViewIfNeeded();
  const bounds = await page.locator('#viewport').boundingBox();
  await page.touchscreen.tap(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
  await page.locator('#export').tap();
  assert.ok((await page.locator('#export-code').inputValue()).includes('function M.f2('));
  await page.locator('#export-dialog [data-close]').tap();
}

(async () => {
  const { chromium } = loadPlaywright();
  const { server, url } = await serveSite();
  let browser;
  try {
    browser = await chromium.launch({ headless: true, ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {}) });
    const errors = [];
    const watch = page => {
      page.on('pageerror', error => errors.push(error.message));
      page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
      page.on('requestfailed', request => errors.push(request.url() + ': ' + request.failure()?.errorText));
    };
    const desktopContext = await browser.newContext({ viewport: { width: 1440, height: 960 }, acceptDownloads: true });
    const desktopPage = await desktopContext.newPage();
    watch(desktopPage);
    await navigation(desktopPage, url, 'desktop');
    await desktop(desktopPage, url);
    const mobileContext = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2, acceptDownloads: true });
    const mobilePage = await mobileContext.newPage();
    watch(mobilePage);
    await navigation(mobilePage, url, 'mobile');
    await mobile(mobilePage, url);
    const narrowContext = await browser.newContext({ viewport: { width: 320, height: 740 }, isMobile: true, hasTouch: true });
    const narrowPage = await narrowContext.newPage();
    watch(narrowPage);
    await navigation(narrowPage, url, 'narrow');
    assert.deepEqual(errors, [], 'builder should emit no browser errors');
    console.log('Builder browser: root/guide/builder navigation at 1440/390/320px, layers, geometry, controls, undo/redo, JSON/Lua/PNG export, import and autosave passed.');
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
