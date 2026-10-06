import { createPathSurface } from '../geometry/surface.mjs';
import { createLayer, sampleProject } from '../model.mjs';
import { Viewport } from '../viewport.mjs';

export function openSurfaceEditor({ layer, onApply } = {}) {
  if (!layer || layer.type !== 'path') throw new Error('Select an editable path to create a surface.');
  // All previews and validation use a private snapshot, never the live layer.
  const source = JSON.parse(JSON.stringify(layer));
  const dialog = document.createElement('dialog');
  dialog.id = 'surface-editor'; dialog.className = 'modal surface-editor';
  dialog.setAttribute('aria-labelledby', 'surface-title');
  dialog.innerHTML = `
    <div class="modal-heading"><div><span class="eyebrow">BUILD FROM YOUR PATH</span><h2 id="surface-title">Give your outline depth.</h2></div><button type="button" class="icon-button" data-dismiss aria-label="Close surface editor">&#10005;</button></div>
    <p class="modal-intro">Extrude or revolve your path into a new editable point cloud. The original path stays available. Your layer's position, rotation and scale carry over; the new surface starts without motion.</p>
    <div class="surface-layout"><div class="surface-inputs">
      <label class="form-label">Operation<select id="surface-mode"><option value="extrude">Extrude outline walls</option><option value="revolve">Revolve a profile</option></select></label>
      <label class="form-label"><span id="surface-axis-label">Extrusion direction</span><select id="surface-axis"><option value="x">X axis</option><option value="y">Y axis</option><option value="z" selected>Z axis</option><option value="custom">Custom direction</option></select></label>
      <section id="surface-extrude-settings">
        <label class="form-label">Depth (studs)<input id="surface-depth" type="number" value="30" min="-5000" max="5000" step="any"></label>
        <div class="surface-triple" id="surface-direction-settings" hidden>${['x', 'y', 'z'].map(axis => `<label class="form-label">Direction ${axis.toUpperCase()}<input id="surface-direction-${axis}" type="number" value="${axis === 'z' ? 1 : 0}" min="-5000" max="5000" step="any"></label>`).join('')}</div>
        <label class="checkbox-row"><input id="surface-centered" type="checkbox">Center the depth on the path</label>
        <p class="micro-copy">Draw a cross-section, then extend its outline. Open paths make ribbons; closed paths make hollow walls, without end caps. Negative depth reverses the direction. Custom direction is normalized, so depth sets the distance.</p>
      </section>
      <section id="surface-revolve-settings" hidden>
        <div class="form-columns"><label class="form-label">Sweep (degrees)<input id="surface-sweep" type="number" value="360" min="-360" max="360" step="any"></label><label class="form-label">Start (degrees)<input id="surface-start" type="number" value="0" min="-360" max="360" step="any"></label></div>
        <div class="surface-triple">${['x', 'y', 'z'].map(axis => `<label class="form-label">Pivot ${axis.toUpperCase()}<input id="surface-pivot-${axis}" type="number" value="0" min="-5000" max="5000" step="any"></label>`).join('')}</div>
        <p class="micro-copy">Turn your profile around an axis through this pivot. Use a full turn or an open sweep; negative angles reverse the direction. Axis, pivot and depth use the path's local coordinates before layer transforms.</p>
      </section>
      <div class="form-columns surface-density"><label class="form-label">Samples along path<input id="surface-samples" type="number" value="64" min="${source.path?.closed ? 3 : 2}" max="2048" step="1"></label><label class="form-label">Surface rows<input id="surface-rows" type="number" value="16" min="2" max="2048" step="1"></label></div>
      <p class="micro-copy">Up to 4,096 editable points. This preview shows every surface point; the scene uses its debris count. The result is baked geometry: edit its points or create another variation from your original path.</p>
    </div><div class="surface-preview"><canvas id="surface-preview" aria-label="Surface preview. Drag to orbit, scroll to zoom." tabindex="0"></canvas><p id="surface-summary" role="status"></p><button type="button" id="surface-fit" class="secondary-button">Fit preview</button></div></div>
    <p id="surface-error" class="form-error" role="alert"></p>
    <div class="modal-actions"><button type="button" data-dismiss class="secondary-button">Cancel</button><button type="button" id="surface-apply" class="primary-button">Add surface layer</button></div>`;
  document.body.append(dialog);
  const $ = id => dialog.querySelector('#' + id);
  const viewport = new Viewport($('surface-preview'));
  viewport.setOptions({ move: false, core: false, pointSize: 1.6 });
  let frame, timer, fitted = false, previousMode = 'extrude';
  const axisByMode = { extrude: 'z', revolve: 'y' };
  function animate() { viewport.render(); frame = requestAnimationFrame(animate); }
  function settings() {
    const numeric = id => Number($(id).value.trim() === '' ? NaN : $(id).value);
    const vector = group => Object.fromEntries(['x', 'y', 'z'].map(axis => [axis, numeric('surface-' + group + '-' + axis)]));
    return {
      mode: $('surface-mode').value, axis: $('surface-axis').value,
      depth: numeric('surface-depth'), centered: $('surface-centered').checked,
      direction: vector('direction'), pivot: vector('pivot'),
      sweep: numeric('surface-sweep'), start: numeric('surface-start'),
      samples: numeric('surface-samples'), rows: numeric('surface-rows'),
    };
  }
  function preview() {
    try {
      const options = settings();
      const spec = createPathSurface(source, options);
      const previewLayer = createLayer(spec.type, spec);
      const points = sampleProject({ version: 1, layers: [previewLayer], controls: [], parts: spec.path.points.length }, 0);
      viewport.setPoints(points);
      if (!fitted) { viewport.fit(); fitted = true; }
      $('surface-summary').textContent = `${options.mode === 'extrude' ? 'Outline walls' : 'Revolved profile'} · ${spec.path.points.length.toLocaleString()} points · ${options.samples} samples × ${options.rows} rows`;
      $('surface-error').textContent = '';
      $('surface-apply').disabled = false;
      return spec;
    } catch (error) {
      viewport.setPoints([]);
      $('surface-summary').textContent = 'Adjust the settings to preview your surface.';
      $('surface-error').textContent = error.message;
      $('surface-apply').disabled = true;
      return null;
    }
  }
  function updateFields() {
    const mode = $('surface-mode').value;
    axisByMode[previousMode] = $('surface-axis').value;
    if (mode !== previousMode) $('surface-axis').value = axisByMode[mode];
    previousMode = mode;
    const revolve = mode === 'revolve';
    const custom = $('surface-axis').querySelector('[value="custom"]');
    custom.hidden = revolve; custom.disabled = revolve;
    $('surface-axis-label').textContent = revolve ? 'Revolution axis' : 'Extrusion direction';
    $('surface-extrude-settings').hidden = revolve;
    $('surface-revolve-settings').hidden = !revolve;
    $('surface-direction-settings').hidden = revolve || $('surface-axis').value !== 'custom';
    $('surface-rows').min = revolve && Math.abs(Number($('surface-sweep').value)) === 360 ? '3' : '2';
  }
  function schedulePreview(event) {
    updateFields();
    clearTimeout(timer);
    // Apply regenerates from the fields, so it cannot commit a stale preview.
    // Leave an enabled button clickable when a field's blur triggers change.
    timer = setTimeout(preview, event.type === 'change' ? 0 : 100);
  }
  dialog.querySelectorAll('input, select').forEach(input => {
    input.addEventListener('input', schedulePreview);
    input.addEventListener('change', schedulePreview);
  });
  $('surface-fit').onclick = () => viewport.fit();
  $('surface-apply').onclick = () => {
    clearTimeout(timer);
    const spec = preview();
    if (!spec) return;
    try { onApply?.(spec); dialog.close(); }
    catch (error) { $('surface-error').textContent = error.message; }
  };
  dialog.querySelectorAll('[data-dismiss]').forEach(button => { button.onclick = () => dialog.close(); });
  dialog.addEventListener('close', () => { clearTimeout(timer); cancelAnimationFrame(frame); viewport.destroy(); dialog.remove(); }, { once: true });
  dialog.showModal(); updateFields(); preview(); animate();
  return dialog;
}
