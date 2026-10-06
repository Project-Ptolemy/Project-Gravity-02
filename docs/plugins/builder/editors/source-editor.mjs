import { readSVG, readCoordinates } from '../importers/geometry.mjs';
import { sampleFormula } from '../geometry/formula.mjs';
import { createLayer, sampleProject, DEFAULT_PART_COUNT } from '../model.mjs';
import { Viewport } from '../viewport.mjs';

export function openSourceEditor({ mode = 'svg', onApply, remainingLayers = 64 } = {}) {
  const dialog = document.createElement('dialog');
  dialog.className = 'modal source-editor'; dialog.id = 'source-editor';
  dialog.setAttribute('aria-labelledby', 'source-title');
  dialog.innerHTML = `
    <div class="modal-heading"><div><span class="eyebrow">YOUR OWN GEOMETRY</span><h2 id="source-title">Bring a shape to life.</h2></div><button type="button" class="icon-button" data-dismiss aria-label="Close geometry editor">✕</button></div>
    <p class="modal-intro">Import your outlines or describe a shape with coordinates. Every result becomes an editable layer.</p>
    <label class="form-label source-mode">Create from<select id="source-mode"><option value="svg">SVG outlines</option><option value="coordinates">Coordinates</option><option value="formula">Math formulas</option></select></label>
    <div class="source-layout"><div class="source-inputs">
      <section data-source-panel="svg">
        <label class="form-label">SVG file<input id="source-svg-file" type="file" accept=".svg,image/svg+xml"></label>
        <label class="form-label">Or paste SVG<textarea id="source-svg" spellcheck="false" placeholder="&lt;svg …&gt;…&lt;/svg&gt;"></textarea></label>
        <div class="form-columns"><label class="form-label">Longest side (studs)<input id="source-svg-size" type="number" value="70" min="0.1" max="1000" step="any"></label><label class="form-label">Samples per curved contour<input id="source-svg-detail" type="number" value="160" min="8" max="1024"></label></div>
        <p class="micro-copy">Paths, polygons, lines, circles, ellipses and rectangles. Each contour becomes its own outline layer. Text and linked symbols must be converted to paths. Fills, images, clipping and CSS styling are not imported.</p>
      </section>
      <section data-source-panel="coordinates" hidden>
        <label class="form-label">Coordinate file<input id="source-coordinates-file" type="file" accept=".csv,.txt,.xyz,.json,text/plain,application/json"></label>
        <label class="form-label">X, Y, Z — one point per line<textarea id="source-coordinates" spellcheck="false">-25, -10, 0
0, 20, 0
25, -10, 0</textarea></label>
        <label class="form-label">Connect points<select id="source-coordinates-type"><option value="path">Connected path</option><option value="pointcloud">Separate points / point cloud</option></select></label>
        <label class="checkbox-row"><input id="source-coordinates-closed" type="checkbox">Close the path</label>
        <p class="micro-copy">Use commas, spaces, or JSON: [[x,y,z], …]. Two coordinates set Z to zero. Values are in studs; up to 4,096 points. Point clouds keep your sampled surfaces and disconnected geometry.</p>
      </section>
      <section data-source-panel="formula" hidden>
        <label class="form-label">Geometry<select id="source-formula-mode"><option value="curve">Curve — u from 0 to 1</option><option value="surface">Surface — u and v from 0 to 1</option></select></label>
        <label class="form-label">X(u, v)<input id="source-formula-x" value="60 * (u - 0.5)" spellcheck="false" maxlength="500"></label>
        <label class="form-label">Y(u, v)<input id="source-formula-y" value="15 * sin(tau * u)" spellcheck="false" maxlength="500"></label>
        <label class="form-label">Z(u, v)<input id="source-formula-z" value="0" spellcheck="false" maxlength="500"></label>
        <div class="form-columns"><label class="form-label">Samples along u<input id="source-formula-samples" type="number" value="128" min="2" max="4096"></label><label class="form-label" id="source-rows-label" hidden>Rows along v<input id="source-formula-rows" type="number" value="32" min="2" max="2048"></label></div>
        <label class="checkbox-row" id="source-close-label"><input id="source-formula-closed" type="checkbox">Closed curve (join last to first)</label>
        <details class="source-reference"><summary>Formula reference</summary><p>u and v range from 0 to 1. Angles are radians. Use pi, tau, + − * / % ^, parentheses, sin, cos, tan, asin, acos, atan, atan2, sqrt, abs, floor, ceil, round, exp, log, min, max and pow. Multiplication needs *.</p><p>For a surface, try Z = 40 * (v - 0.5). At most 4,096 sampled points. Formulas are baked into geometry when added; animate the result with the layer’s motion controls.</p></details>
      </section>
    </div><div class="source-preview"><canvas id="source-preview" aria-label="Geometry preview. Drag to orbit, scroll to zoom." tabindex="0"></canvas><p id="source-summary" role="status">Preview your geometry before adding it.</p><button type="button" id="source-preview-button" class="secondary-button">Preview geometry</button></div></div>
    <p id="source-error" class="form-error" role="alert"></p>
    <div class="modal-actions"><button type="button" data-dismiss class="secondary-button">Cancel</button><button type="button" id="source-apply" class="primary-button">Add to scene</button></div>`;
  document.body.append(dialog);
  const $ = id => dialog.querySelector('#' + id);
  $('source-mode').value = mode;
  const viewport = new Viewport($('source-preview'));
  viewport.setOptions({ move: false, core: false, pointSize: 1.2 });
  let frame;
  function animate() { viewport.render(); frame = requestAnimationFrame(animate); }
  function selectMode() {
    mode = $('source-mode').value;
    dialog.querySelectorAll('[data-source-panel]').forEach(panel => { panel.hidden = panel.dataset.sourcePanel !== mode; });
    $('source-error').textContent = ''; $('source-summary').textContent = 'Preview your geometry before adding it.';
    viewport.setPoints([]);
  }
  function generate() {
    let layers;
    if (mode === 'svg') layers = readSVG($('source-svg').value, { size: Number($('source-svg-size').value), detail: Number($('source-svg-detail').value) });
    else if (mode === 'coordinates') layers = readCoordinates($('source-coordinates').value, { type: $('source-coordinates-type').value, closed: $('source-coordinates-closed').checked });
    else layers = [sampleFormula({
      x: $('source-formula-x').value, y: $('source-formula-y').value, z: $('source-formula-z').value,
      mode: $('source-formula-mode').value, samples: Number($('source-formula-samples').value), rows: Number($('source-formula-rows').value), closed: $('source-formula-closed').checked,
    })];
    if (layers.length > remainingLayers) throw new Error(`This needs ${layers.length} layers, but your scene has room for ${remainingLayers}. Remove some layers first.`);
    return layers;
  }
  function preview() {
    const specs = generate();
    const layers = specs.map((spec, i) => createLayer(spec.type, { ...spec, position: { x: 0, y: 0, z: 0 }, color: ['#d4ef9d', '#b8a4ff', '#79d9ea'][i % 3] }));
    const points = sampleProject({ version: 1, layers, controls: [], parts: Math.min(8192, Math.max(DEFAULT_PART_COUNT, specs.reduce((n, layer) => n + layer.path.points.length, 0))) }, 0);
    viewport.setPoints(points); viewport.fit();
    $('source-summary').textContent = `${specs.length} layer${specs.length === 1 ? '' : 's'} · ${specs.reduce((n, spec) => n + spec.path.points.length, 0).toLocaleString()} vertices`;
    $('source-error').textContent = '';
    return specs;
  }
  $('source-preview-button').onclick = () => { try { preview(); } catch (error) { $('source-error').textContent = error.message; } };
  $('source-apply').onclick = () => {
    try { const specs = preview(); onApply?.(specs); dialog.close(); }
    catch (error) { $('source-error').textContent = error.message; }
  };
  $('source-mode').onchange = selectMode;
  $('source-formula-mode').onchange = () => {
    const surface = $('source-formula-mode').value === 'surface';
    $('source-rows-label').hidden = !surface; $('source-close-label').hidden = surface;
    if (surface && Number($('source-formula-samples').value) * Number($('source-formula-rows').value) > 4096) $('source-formula-samples').value = 64;
  };
  for (const kind of ['svg', 'coordinates']) {
    $('source-' + kind + '-file').onchange = async event => {
      const file = event.target.files[0]; if (!file) return;
      try {
        if (file.size > 2_000_000) throw new Error('Choose a file smaller than 2 MB.');
        const source = await file.text(); if (!dialog.isConnected) return;
        $('source-' + kind).value = source; preview();
      } catch (error) { $('source-error').textContent = error.message; }
      event.target.value = '';
    };
  }
  dialog.querySelectorAll('[data-dismiss]').forEach(button => { button.onclick = () => dialog.close(); });
  dialog.addEventListener('close', () => { cancelAnimationFrame(frame); viewport.destroy(); dialog.remove(); }, { once: true });
  dialog.showModal(); selectMode(); animate();
  if (mode !== 'svg') $('source-preview-button').click();
  return dialog;
}
