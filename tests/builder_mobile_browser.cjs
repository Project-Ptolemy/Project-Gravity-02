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

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ headless: true, ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {}) });
  const url = `http://127.0.0.1:${server.address().port}/docs/plugins/builder/`;
  const errors = [];
  try {
    for (const [width, height] of [[320, 640], [390, 844], [768, 1024], [1024, 768], [844, 390]]) {
      const page = await browser.newPage({ viewport: { width, height }, hasTouch: true, isMobile: true, reducedMotion: 'reduce' });
      page.setDefaultTimeout(12000);
      page.on('pageerror', error => errors.push(error.message));
      await page.goto(url);
      await page.locator('.layer-row').first().waitFor();
      const nav = panel => page.locator(`#mobile-navigation [data-panel="${panel}"]`);
      const fits = async () => assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.documentElement.scrollHeight <= innerHeight), `${width}×${height}: workspace stays inside screen`);
      await fits();
      const preview = await page.locator('#viewport').boundingBox();
      await nav('preview').tap(); await paint(page);
      const expanded = await page.locator('#viewport').boundingBox();
      assert.ok(expanded.width * expanded.height > preview.width * preview.height * 1.2, 'Preview expands without losing editing state');
      assert.equal(await page.locator('#scene-panel').evaluate(panel => panel.inert), true);
      await page.locator('#zoom-in').tap();
      await page.locator('#zoom-out').tap();
      await nav('scene').tap();
      await page.locator('.layer-row').nth(1).locator('.layer-edit').tap();
      assert.equal(await nav('properties').getAttribute('aria-pressed'), 'true');
      const exact = page.locator('input[type=number][data-prop="position.x"]');
      await exact.fill('0.123456789123'); await exact.press('Tab');
      assert.equal(await exact.inputValue(), '0.123456789123', 'exact values survive editing without six-decimal rounding');
      assert.ok(await exact.evaluate(input => parseFloat(getComputedStyle(input).fontSize) >= 16), 'numeric fields avoid iOS focus zoom');
      assert.ok((await exact.boundingBox()).height >= 44, 'numeric fields are easy to tap');
      await page.locator('#undo').tap();
      assert.equal(await exact.inputValue(), '0');
      await page.locator('#redo').tap();
      assert.equal(await exact.inputValue(), '0.123456789123');
      await nav('controls').tap();
      assert.equal(await page.locator('#controls-panel').isVisible(), true);
      await page.locator('#new-control').tap();
      await page.locator('#control-name').fill('Mobile radius');
      await page.locator('#control-form button[type=submit]').tap();
      assert.ok(await page.locator('.control-card').count() > 0);
      await nav('scene').tap();
      await page.locator('#draw-path').tap();
      const canvas = page.locator('.path-editor canvas');
      await canvas.scrollIntoViewIfNeeded();
      const bounds = await canvas.boundingBox();
      await page.touchscreen.tap(bounds.x + bounds.width * 0.3, bounds.y + 65);
      await page.touchscreen.tap(bounds.x + bounds.width * 0.6, bounds.y + 110);
      await page.locator('.path-editor [data-action=apply]').tap();
      assert.equal(await nav('properties').getAttribute('aria-pressed'), 'true');
      await page.locator('#export').tap();
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
      if (process.env.BUILDER_SCREENSHOT_DIR) {
        fs.mkdirSync(process.env.BUILDER_SCREENSHOT_DIR, { recursive: true });
        await page.screenshot({ path: path.join(process.env.BUILDER_SCREENSHOT_DIR, `export-${width}.png`) });
      }
      await page.locator('#export-dialog [data-close]').tap();
      await fits();
      // A keyboard resize exposes the editor without covering controls with the preview.
      await page.evaluate(() => {
        Object.defineProperty(window.visualViewport, 'height', { configurable: true, value: innerHeight - 180 });
        visualViewport.dispatchEvent(new Event('resize'));
      });
      assert.equal(await page.locator('body').evaluate(body => body.classList.contains('keyboard-open')), true);
      assert.equal(await page.locator('#mobile-navigation').isVisible(), true);
      await page.evaluate(() => { delete visualViewport.height; visualViewport.dispatchEvent(new Event('resize')); });
      await nav('properties').tap();
      if (process.env.BUILDER_SCREENSHOT_DIR) await page.screenshot({ path: path.join(process.env.BUILDER_SCREENSHOT_DIR, `editing-${width}.png`) });
      await page.setViewportSize({ width: 1440, height: 960 });
      assert.equal(await page.locator('#scene-panel').evaluate(panel => panel.inert), false, 'desktop restoration re-enables both panels');
      assert.equal(await page.locator('#inspector-panel').isVisible(), true);
      await page.close();
      console.log(`Mobile workspace ${width}×${height}: navigation, precision, undo, controls, drawing, export and keyboard passed.`);
    }
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
