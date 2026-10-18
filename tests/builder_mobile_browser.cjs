// Responsive editing and export checks. Uses the same optional Playwright setup as builder_browser.cjs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const server = http.createServer((request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  let file = path.resolve(root, '.' + pathname);
  if (!file.startsWith(root + path.sep)) return response.writeHead(403).end();
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
  if (!fs.existsSync(file)) return response.writeHead(404).end();
  response.setHeader('Content-Type', { '.html': 'text/html', '.mjs': 'text/javascript', '.css': 'text/css' }[path.extname(file)] || 'text/plain');
  response.end(fs.readFileSync(file));
});
const paint = page => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
const viewportSizes = [[320, 568], [390, 844], [568, 320], [844, 390], [768, 1024], [1024, 768]];

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true, ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {}) });
  const url = `http://127.0.0.1:${server.address().port}/docs/plugins/builder/`;
  const errors = [];
  try {
    for (const [width, height] of viewportSizes) {
      const page = await browser.newPage({ viewport: { width, height }, hasTouch: true, isMobile: true, reducedMotion: 'reduce' });
      page.setDefaultTimeout(12000);
      page.on('pageerror', error => errors.push(error.message));
      await page.goto(url);
      await page.locator('.layer-row').first().waitFor();
      const nav = panel => page.locator(`#mobile-navigation [data-panel="${panel}"]`);
      const fits = async () => assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.documentElement.scrollHeight <= innerHeight), `${width}×${height}: workspace stays inside screen`);
      const screenshot = async name => {
        if (!process.env.BUILDER_SCREENSHOT_DIR) return;
        fs.mkdirSync(process.env.BUILDER_SCREENSHOT_DIR, { recursive: true });
        await page.screenshot({ path: path.join(process.env.BUILDER_SCREENSHOT_DIR, `${name}-${width}x${height}.png`) });
      };
      const inScreen = async (locator, description) => {
        const box = await locator.boundingBox();
        assert.ok(box && box.width > 0 && box.height > 0 && box.x >= -1 && box.y >= -1 && box.x + box.width <= width + 1 && box.y + box.height <= height + 1,
          `${width}×${height}: ${description} fits the visible screen (${JSON.stringify(box)})`);
      };
      const dialogFits = async selector => {
        const dialog = page.locator(selector);
        await paint(page);
        await inScreen(dialog, selector);
        assert.ok(await dialog.evaluate(element => element.scrollWidth <= element.clientWidth + 1), `${width}×${height}: ${selector} has no horizontal clipping`);
      };
      const reachable = async (selector, description) => {
        const locator = page.locator(selector);
        await locator.scrollIntoViewIfNeeded();
        await inScreen(locator, description);
        assert.ok(await locator.evaluate(element => {
          const box = element.getBoundingClientRect();
          return element.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2));
        }), `${width}×${height}: ${description} is not covered by another control`);
      };
      const previewToolFits = async selector => {
        const locator = page.locator(selector);
        await inScreen(locator, selector);
        assert.ok(await locator.evaluate(element => {
          const box = element.getBoundingClientRect();
          const preview = element.closest('.canvas-area').getBoundingClientRect();
          return box.x >= preview.x && box.y >= preview.y && box.right <= preview.right && box.bottom <= preview.bottom
            && element.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2));
        }), `${width}×${height}: ${selector} stays inside the preview and is not covered`);
      };
      await fits();
      assert.ok(await page.locator('#scene-panel').evaluate(panel => {
        const box = panel.getBoundingClientRect();
        return [...panel.querySelectorAll('.layer-row')].filter(row => {
          const bounds = row.getBoundingClientRect();
          return bounds.top >= box.top && bounds.bottom <= box.bottom;
        }).length >= 2;
      }), `${width}×${height}: initial Layers view shows at least two complete layers without scrolling`);
      await screenshot('scene');
      if (width > height) {
        const scene = await page.locator('#scene-panel').boundingBox();
        const canvas = await page.locator('#viewport').boundingBox();
        assert.ok(scene.x >= canvas.x + canvas.width - 1, `${width}×${height}: landscape places the editor beside its preview`);
      }
      const preview = await page.locator('#viewport').boundingBox();
      await nav('preview').tap(); await paint(page);
      const expanded = await page.locator('#viewport').boundingBox();
      assert.ok(expanded.width * expanded.height > preview.width * preview.height * 1.2, 'Preview expands without losing editing state');
      assert.equal(await page.locator('#scene-panel').evaluate(panel => panel.inert), true);
      for (const selector of ['#camera-view', '#zoom-in', '#zoom-out', '#fit-view', '#screenshot', '#toggle-axes', '#toggle-move', '#toggle-core', '#snap-size', '#play-pause', '#restart']) await previewToolFits(selector);
      await screenshot('preview');
      await page.locator('#zoom-in').tap();
      await page.locator('#zoom-out').tap();
      await nav('scene').tap();
      await page.locator('.layer-row').nth(1).locator('.layer-edit').tap();
      assert.equal(await nav('properties').getAttribute('aria-pressed'), 'true');
      const exact = page.locator('input[type=number][data-prop="position.x"]');
      await exact.fill('0.123456789123'); await exact.press('Tab');
      assert.equal(await exact.inputValue(), '0.123456789123', 'exact values survive editing without six-decimal rounding');
      assert.ok(await exact.evaluate(input => parseFloat(getComputedStyle(input).fontSize) >= 16), 'numeric fields avoid iOS focus zoom');
      assert.ok((await exact.boundingBox()).height >= 44, 'numeric fields retain a comfortable touch target');
      await page.locator('#undo').tap();
      assert.equal(await exact.inputValue(), '0');
      await page.locator('#redo').tap();
      assert.equal(await exact.inputValue(), '0.123456789123');
      if (width === 390) {
        await page.setViewportSize({ width: 844, height: 390 });
        await paint(page);
        assert.equal(await nav('properties').getAttribute('aria-pressed'), 'true', 'rotation retains the active editor');
        assert.equal(await exact.inputValue(), '0.123456789123', 'rotation retains the selected layer and exact geometry');
        await page.setViewportSize({ width, height });
        await paint(page);
        assert.equal(await exact.inputValue(), '0.123456789123');
      }
      await nav('controls').tap();
      assert.equal(await page.locator('#controls-panel').isVisible(), true);
      await page.locator('#new-control').tap();
      await dialogFits('#control-dialog');
      await page.locator('#control-name').fill('Mobile radius');
      await reachable('#control-form button[type=submit]', 'Save control');
      await page.locator('#control-form button[type=submit]').tap();
      assert.ok(await page.locator('.control-card').count() > 0);
      await nav('scene').tap();
      await page.locator('#add-layer').tap();
      await dialogFits('#shape-dialog');
      await screenshot('library');
      await reachable('#custom-shape-library [data-create="path"]', 'Draw a path from the shape library');
      await page.locator('#custom-shape-library [data-create="path"]').tap();
      await dialogFits('.path-editor');
      await inScreen(page.locator('.path-editor-final-actions'), 'path Apply action');
      await inScreen(page.locator('.path-editor-close'), 'path Close action');
      await screenshot('draw');
      const canvas = page.locator('.path-editor canvas');
      await canvas.scrollIntoViewIfNeeded();
      const bounds = await canvas.evaluate(element => {
        const canvas = element.getBoundingClientRect();
        const body = element.closest('.path-editor-body').getBoundingClientRect();
        const top = Math.max(canvas.top, body.top), bottom = Math.min(canvas.bottom, body.bottom);
        return { x: canvas.x, y: top, width: canvas.width, height: bottom - top };
      });
      assert.ok(bounds.height >= 120, `${width}×${height}: path editor exposes enough canvas for drawing`);
      await page.touchscreen.tap(bounds.x + bounds.width * 0.3, bounds.y + bounds.height * 0.3);
      await page.touchscreen.tap(bounds.x + bounds.width * 0.6, bounds.y + bounds.height * 0.65);
      assert.match(await page.locator('.path-editor [data-field=count]').textContent(), /2 vertices/, 'both touches reach the drawing canvas');
      await page.locator('.path-editor [data-action=toggle-properties]').tap();
      assert.equal(await canvas.isVisible(), false, 'Settings uses the available space for vertex editing');
      const vertexX = page.locator('.path-editor [data-coordinate=x]');
      await reachable('.path-editor [data-coordinate=x]', 'exact vertex coordinate');
      await vertexX.fill('12.5'); await vertexX.press('Tab');
      assert.equal(await vertexX.inputValue(), '12.5');
      await screenshot('path-settings');
      await page.locator('.path-editor [data-action=toggle-properties]').tap();
      assert.equal(await canvas.isVisible(), true, 'returning to Canvas preserves the open draft');
      assert.match(await page.locator('.path-editor [data-field=mobile-count]').textContent(), /2 pts/);
      await reachable('.path-editor [data-action=apply]', 'Apply path');
      await page.locator('.path-editor [data-action=apply]').tap();
      assert.equal(await nav('properties').getAttribute('aria-pressed'), 'true');

      // Exercise generated geometry through the real mobile library and app callbacks.
      await nav('scene').tap();
      const beforeFormula = await page.locator('.layer-row').count();
      await page.locator('#add-layer').tap();
      await page.locator('#custom-shape-library [data-create="formula"]').tap();
      await dialogFits('#source-editor');
      await page.locator('#source-formula-samples').fill('16');
      await page.locator('#source-formula-x').fill('40 * (u - 0.5)');
      await reachable('#source-apply', 'Add generated geometry');
      await screenshot('formula');
      await page.locator('#source-apply').tap();
      assert.equal(await page.locator('.layer-row').count(), beforeFormula + 1);

      await page.locator('#export').tap();
      await dialogFits('#export-dialog');
      assert.equal(await page.locator('#export-source').evaluate(details => details.open), false, 'code is collapsed behind the installation steps');
      assert.match(await page.locator('#export-code').inputValue(), /0\.123456789123/);
      await page.evaluate(() => {
        Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async () => { throw Error('denied'); } } });
        document.execCommand = () => false;
      });
      await page.locator('#copy-lua').tap();
      assert.equal(await page.locator('#export-source').evaluate(details => details.open), true);
      assert.match(await page.locator('#export-copy-status').textContent(), /Copy the selected script/);
      assert.ok(await page.locator('#export-code').evaluate(text => text.selectionEnd === text.value.length), 'manual copy selects the whole plugin');
      await screenshot('export');
      await page.locator('#export-dialog [data-close]').tap();
      await fits();
      // A keyboard resize exposes the editor without covering controls with the preview.
      await page.evaluate(() => {
        Object.defineProperty(window.visualViewport, 'height', { configurable: true, value: innerHeight - 180 });
        visualViewport.dispatchEvent(new Event('resize'));
      });
      assert.equal(await page.locator('body').evaluate(body => body.classList.contains('keyboard-open')), true);
      assert.equal(await page.locator('#mobile-navigation').isVisible(), true);
      assert.ok(await page.locator('#mobile-navigation').evaluate(element => element.getBoundingClientRect().bottom <= visualViewport.height + 1), 'navigation remains above the software keyboard');
      await page.evaluate(() => { delete visualViewport.height; visualViewport.dispatchEvent(new Event('resize')); });
      // Android's keyboard may shrink the layout viewport itself rather than
      // only visualViewport; the active field must still get the editing layout.
      await page.locator('#project-name').focus();
      await page.setViewportSize({ width, height: height - 180 });
      await page.waitForFunction(() => document.body.classList.contains('keyboard-open'));
      assert.ok(await page.locator('#mobile-navigation').evaluate(element => element.getBoundingClientRect().bottom <= innerHeight + 1), 'navigation also fits an Android keyboard resize');
      await page.setViewportSize({ width, height });
      await page.waitForFunction(() => !document.body.classList.contains('keyboard-open'));
      await page.locator('#project-name').blur();
      await nav('properties').tap();
      await screenshot('editing');
      await page.setViewportSize({ width: 1440, height: 960 });
      await page.waitForFunction(() => !document.querySelector('#scene-panel').inert);
      assert.equal(await page.locator('#scene-panel').evaluate(panel => panel.inert), false, 'desktop restoration re-enables both panels');
      assert.equal(await page.locator('#inspector-panel').isVisible(), true);
      await page.close();
      console.log(`Mobile workspace ${width}×${height}: compact layers, orientation, navigation, precision, undo, controls, library, drawing, formulas, export and keyboard passed.`);
    }
    const desktop = await browser.newPage({ viewport: { width: 1440, height: 960 }, reducedMotion: 'reduce' });
    desktop.on('pageerror', error => errors.push(error.message));
    await desktop.goto(url);
    await desktop.locator('.layer-row').first().waitFor();
    assert.equal(await desktop.locator('#mobile-navigation').isVisible(), false);
    const left = await desktop.locator('#scene-panel').boundingBox(), right = await desktop.locator('#inspector-panel').boundingBox();
    const canvas = await desktop.locator('#viewport').boundingBox();
    assert.ok(left.width >= 200 && right.width >= 250 && canvas.width >= 700 && canvas.x >= left.x + left.width - 1 && right.x >= canvas.x + canvas.width - 1, 'desktop retains its three-column workspace');
    if (process.env.BUILDER_SCREENSHOT_DIR) await desktop.screenshot({ path: path.join(process.env.BUILDER_SCREENSHOT_DIR, 'desktop-1440x960.png') });
    await desktop.close();
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
