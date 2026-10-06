import { createArrangement } from '../geometry/arrangement.mjs';
import { normalizeProject, sampleProject } from '../model.mjs';
import { Viewport } from '../viewport.mjs';

/** Only Apply calls onApply({layers, controls}); both arrays contain NEW copies. */
export function openRepeatEditor({ project, layerId, onApply } = {}) {
  const sourceProject = normalizeProject(project);
  const source = sourceProject.layers.find(layer => layer.id === layerId);
  if (!source) throw new Error('Choose a layer to repeat.');
  const dialog = document.createElement('dialog');
  dialog.id = 'repeat-editor'; dialog.className = 'modal repeat-editor';
  dialog.setAttribute('aria-labelledby', 'repeat-title');
  const xyz = (prefix, label, values = [0, 0, 0]) => `<fieldset class="repeat-vector"><legend>${label}</legend>${['x', 'y', 'z'].map((axis, index) => `<label>${axis.toUpperCase()}<input id="repeat-${prefix}-${axis}" type="number" value="${values[index]}" step="any" aria-label="${label} ${axis.toUpperCase()}"></label>`).join('')}</fieldset>`;
  dialog.innerHTML = `
    <div class="modal-heading"><div><span class="eyebrow">BUILD WITH REPETITION</span><h2 id="repeat-title">Arrange editable copies.</h2></div><button type="button" class="icon-button" data-repeat-dismiss aria-label="Close repeat editor">&times;</button></div>
    <p class="modal-intro">Repeat <strong id="repeat-source-name"></strong>. Each copy keeps its geometry, animation and controls, and can be edited independently.</p>
    <div class="repeat-layout"><div class="repeat-inputs">
      <div class="form-columns"><label class="form-label">Arrangement<select id="repeat-mode"><option value="line">Line</option><option value="radial">Radial</option></select></label><label class="form-label">Copies to add<input id="repeat-count" type="number" min="1" max="63" value="${Math.max(1, Math.min(3, 64 - sourceProject.layers.length))}" step="1"></label></div>
      <section id="repeat-line-fields">
        ${xyz('position', 'Position step (studs)', [30, 0, 0])}
        ${xyz('rotation', 'Rotation step (degrees)')}
        <p class="micro-copy">The first copy moves one step from the source; each following copy adds another step. Rotation steps add to its X, Y and Z angles.</p>
      </section>
      <section id="repeat-radial-fields" hidden>
        <div class="form-columns"><label class="form-label">World axis<select id="repeat-axis"><option value="x">X</option><option value="y" selected>Y</option><option value="z">Z</option></select></label><label class="form-label">Sweep (degrees)<input id="repeat-sweep" type="number" value="360" min="-360" max="360" step="any"></label></div>
        <label class="form-label">Pivot coordinates<select id="repeat-pivot-space"><option value="world">World coordinates</option><option value="local">Source-local coordinates</option></select></label>
        ${xyz('pivot', 'Pivot (studs)')}
        <p class="micro-copy" id="repeat-pivot-note">World pivot: 0, 0, 0 is the scene origin. The chosen axis passes through this point.</p>
        <label class="checkbox-row"><input id="repeat-rotate" type="checkbox" checked>Rotate each copy with the arrangement</label>
        <p class="micro-copy">A full ±360° turn spaces the source and copies evenly. Smaller sweeps include the final angle. Negative sweeps run in the opposite direction.</p>
      </section>
      <p class="micro-copy repeat-controls-note">The source stays in place. Control names and bindings are copied; transform defaults follow each copy. Slider ranges expand only when needed to include the new default.</p>
    </div><div class="repeat-preview-panel"><canvas id="repeat-preview" tabindex="0" aria-label="Repeated layers preview. Drag to orbit, scroll to zoom."></canvas><p id="repeat-summary" role="status"></p><button id="repeat-preview-button" type="button" class="secondary-button">Fit preview</button><p class="micro-copy">Preview shows the source and its copies at time zero. Existing scene layers stay unchanged.</p></div></div>
    <p id="repeat-error" class="form-error" role="alert"></p>
    <div class="modal-actions"><button type="button" data-repeat-dismiss class="secondary-button">Cancel</button><button id="repeat-apply" type="button" class="primary-button">Add copies</button></div>`;
  document.body.append(dialog);
  const $ = id => dialog.querySelector('#' + id);
  $('repeat-source-name').textContent = source.name;
  const viewport = new Viewport($('repeat-preview'));
  viewport.setOptions({ move: false, core: false, pointSize: 2 });
  let frame, previewTimer, result = null;
  const readNumber = id => $(id).value === '' ? NaN : Number($(id).value);
  const readVector = prefix => Object.fromEntries(['x', 'y', 'z'].map(axis => [axis, readNumber(`repeat-${prefix}-${axis}`)]));
  function options() {
    const mode = $('repeat-mode').value;
    return {
      mode, count: readNumber('repeat-count'),
      ...(mode === 'line' ? { positionStep: readVector('position'), rotationStep: readVector('rotation') } : {
        axis: $('repeat-axis').value, sweep: readNumber('repeat-sweep'), pivotSpace: $('repeat-pivot-space').value,
        pivot: readVector('pivot'), rotateCopies: $('repeat-rotate').checked,
      }),
    };
  }
  function preview(fit = false) {
    clearTimeout(previewTimer);
    try {
      result = createArrangement(sourceProject, layerId, options());
      const layers = [source, ...result.layers], controls = [...sourceProject.controls.filter(control => control.layerId === layerId), ...result.controls];
      viewport.setPoints(sampleProject({ ...sourceProject, layers, controls, parts: Math.min(8192, Math.max(128, layers.length * 128)) }, 0));
      if (fit) viewport.fit();
      $('repeat-error').textContent = '';
      $('repeat-summary').textContent = `${result.layers.length} new ${result.layers.length === 1 ? 'layer' : 'layers'} · ${result.controls.length} copied ${result.controls.length === 1 ? 'control' : 'controls'} · source retained`;
      $('repeat-apply').disabled = false;
      return result;
    } catch (error) {
      result = null; viewport.setPoints([]);
      $('repeat-error').textContent = error.message;
      $('repeat-summary').textContent = 'Adjust the arrangement to preview its copies.';
      $('repeat-apply').disabled = true;
      return null;
    }
  }
  function updateFields() {
    const radial = $('repeat-mode').value === 'radial';
    $('repeat-line-fields').hidden = radial; $('repeat-radial-fields').hidden = !radial;
    $('repeat-pivot-note').textContent = $('repeat-pivot-space').value === 'local'
      ? 'Source-local pivot: 0, 0, 0 is the source position. Offsets follow its default scale and X → Y → Z rotation; the radial axis remains a world axis.'
      : 'World pivot: 0, 0, 0 is the scene origin. The chosen axis passes through this point.';
  }
  dialog.addEventListener('input', event => {
    if (!event.target.matches('input,select')) return;
    updateFields(); result = null; $('repeat-apply').disabled = true;
    clearTimeout(previewTimer); previewTimer = setTimeout(() => preview(true), 140);
  });
  $('repeat-preview-button').onclick = () => preview(true);
  $('repeat-apply').onclick = () => {
    const copies = preview(); if (!copies) return;
    try { onApply?.(copies); dialog.close(); }
    catch (error) { $('repeat-error').textContent = error.message; }
  };
  dialog.querySelectorAll('[data-repeat-dismiss]').forEach(button => { button.onclick = () => dialog.close(); });
  dialog.addEventListener('close', () => { clearTimeout(previewTimer); cancelAnimationFrame(frame); viewport.destroy(); dialog.remove(); }, { once: true });
  function animate() { viewport.render(); frame = requestAnimationFrame(animate); }
  dialog.showModal(); updateFields(); preview(true); animate();
  return dialog;
}
