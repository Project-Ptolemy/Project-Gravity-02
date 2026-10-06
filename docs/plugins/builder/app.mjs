import { createProject, createLayer, normalizeProject, sampleProject, controlDivisor, BOOLEAN_DEFS, applyPreviewAction, PROPERTY_DEFS, LAYER_TYPES, getProperty, setProperty } from './model.mjs';
import { exportLua } from './exporter.mjs';
import { Viewport } from './viewport.mjs';
import { openPathEditor } from './editors/path-editor.mjs';
import { openSourceEditor } from './editors/source-editor.mjs';
import { readProjectFile, serializeProject } from './project-file.mjs';

const $ = id => document.getElementById(id);
const escapeHTML = value => String(value).replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character]);
const clone = value => JSON.parse(JSON.stringify(value));
const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
const format = value => Number(Number(value).toFixed(6)).toString();
const titleCase = value => value.charAt(0).toUpperCase() + value.slice(1);
const controlType = control => control.type || 'slider';
const ACTION_LABELS = { restart: 'Restart animation', reverse: 'Reverse animation', reset: 'Reset controls' };
const typeName = type => ({ path: 'Custom path', pointcloud: 'Point cloud' })[type] || titleCase(type);
const uniqueId = () => 'control-' + (globalThis.crypto?.randomUUID?.() || Date.now().toString(36) + '-' + Math.random().toString(36).slice(2));
const STORAGE_KEY = 'gravity-shape-studio-v1';
const colors = ['#b7f399', '#b8a4ff', '#79d9ea', '#ffc98a', '#f28faf'];
const paths = {
  plus: '<path d="M12 5v14M5 12h14"/>', close: '<path d="m6 6 12 12M18 6 6 18"/>',
  search: '<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6"/>', chevron: '<path d="m6 9 6 6 6-6"/>', solo: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/>',
  undo: '<path d="M3 10h10a7 7 0 0 1 7 7M3 10l5-5M3 10l5 5"/>', redo: '<path d="M21 10H11a7 7 0 0 0-7 7m17-7-5-5m5 5-5 5"/>',
  download: '<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>', copy: '<rect x="8" y="8" width="12" height="13" rx="2"/><path d="M15 8V3H3v12h5"/>',
  eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>', 'eye-off': '<path d="m3 3 18 18M9 5.5a12 12 0 0 1 3-.5c6.5 0 10 7 10 7a20 20 0 0 1-3.3 4.2M6.2 6.2A22 22 0 0 0 2 12s3.5 7 10 7a12 12 0 0 0 5-1.1"/>',
  trash: '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7"/>',
  'arrow-up': '<path d="M12 20V4m-6 6 6-6 6 6"/>', 'arrow-down': '<path d="M12 4v16m-6-6 6 6 6-6"/>',
  play: '<path d="m8 4 12 8-12 8Z" fill="currentColor" stroke="none"/>', pause: '<path d="M7 5v14M17 5v14" stroke-width="4"/>', restart: '<path d="M3 10a9 9 0 1 1 1 7M3 4v6h6"/>',
  grid: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18M15 3v18M3 9h18M3 15h18"/>',
  maximize: '<path d="M9 3H3v6m12-6h6v6M3 15v6h6m12-6v6h-6"/>', camera: '<path d="M8 5 6 8H3v12h18V8h-3l-2-3Z"/><circle cx="12" cy="13" r="4"/>',
  axes: '<path d="M5 4v15h15M5 19l9-9M2 7l3-3 3 3m9 9 3 3-3 3"/>',
  folder: '<path d="M3 6h7l2 3h9v12H3Z"/><path d="M3 6V3h7l2 3h7v3"/>', save: '<path d="M4 3h14l3 3v15H3V3ZM7 3v6h10V3M7 21v-8h10v8"/>',
  help: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 1 1 4 2c-1.5 1-1.5 1-1.5 3M12 17h.01"/>',
  keyboard: '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M6 9h.01M10 9h.01M14 9h.01M18 9h.01M6 12h.01M10 12h.01M14 12h.01M18 12h.01M7 16h10"/>',
  sliders: '<path d="M4 7h3m4 0h9M4 17h9m4 0h3"/><circle cx="9" cy="7" r="2"/><circle cx="15" cy="17" r="2"/>',
  sparkles: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5ZM20 2v4m-2-2h4"/>',
  check: '<path d="m5 12 4 4L19 6"/>', edit: '<path d="m4 16-1 5 5-1L20 8l-4-4ZM14 6l4 4"/>',
  cube: '<path d="m12 2 10 5v10l-10 5-10-5V7Zm-10 5 10 5 10-5M12 12v10"/>',
  orbit: '<ellipse cx="12" cy="12" rx="11" ry="4" transform="rotate(-35 12 12)"/><ellipse cx="12" cy="12" rx="11" ry="4" transform="rotate(35 12 12)"/><circle cx="12" cy="12" r="3"/>',
  sphere: '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><ellipse cx="12" cy="12" rx="9" ry="4"/>',
  ring: '<ellipse cx="12" cy="12" rx="10" ry="5.5" transform="rotate(-25 12 12)"/><ellipse cx="12" cy="12" rx="7" ry="3.5" transform="rotate(-25 12 12)"/>',
  torus: '<ellipse cx="12" cy="12" rx="10" ry="7"/><ellipse cx="12" cy="11" rx="4.5" ry="2.5"/><path d="M2 11c2 9 18 9 20 0"/>',
  helix: '<path d="M5 2c14 0 14 5 0 5s-4 5 7 5 11 5-2 5-7 5 8 5M6 3v18"/>',
  box: '<path d="m12 2 10 5v10l-10 5-10-5V7Zm-10 5 10 5 10-5M12 12v10"/>',
  cone: '<path d="M2 18 12 2l10 16"/><ellipse cx="12" cy="18" rx="10" ry="4"/><path d="M12 2v16" stroke-dasharray="2 2"/>',
  cylinder: '<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v14c0 4 16 4 16 0V5"/><path d="M4 18c0-4 16-4 16 0" stroke-dasharray="2 2"/>',
  line: '<path d="m4 20 16-16"/><circle cx="4" cy="20" r="2"/><circle cx="20" cy="4" r="2"/><path d="m8 14 2 2m2-6 2 2"/>',
  spiral: '<path d="M12 12c1-4 7-1 5 2s-9 5-11 0S8 3 15 5s10 13 0 16C4 24-4 10 5 3"/>',
  polygon: '<path d="m12 2 10 18H2Z"/><circle cx="12" cy="2" r="1"/><circle cx="2" cy="20" r="1"/><circle cx="22" cy="20" r="1"/>',
  path: '<path d="m3 18 6-13 7 14 5-13"/><circle cx="3" cy="18" r="2"/><circle cx="9" cy="5" r="2"/><circle cx="16" cy="19" r="2"/><circle cx="21" cy="6" r="2"/>',
  pointcloud: '<path d="M4 6h.01M12 3h.01M20 7h.01M7 13h.01M16 12h.01M4 20h.01M13 21h.01M21 18h.01" stroke-width="4"/>',
};
function icon(name) { return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name] || paths.cube}</svg>`; }
function fillIcons(root = document) { root.querySelectorAll('[data-icon]').forEach(element => { element.innerHTML = icon(element.dataset.icon); }); }
fillIcons();

let project = createProject('orbit');
project.pointSize = 3.4;
let restored = false;
let storageWarning = '';
try {
  const saved = localStorage.getItem(STORAGE_KEY);
  if (saved) { project = normalizeProject(JSON.parse(saved)); restored = true; }
} catch { storageWarning = 'Could not restore local project. Open a saved project file to recover it.'; }
let selectedId = project.layers[1]?.id || project.layers[0]?.id || null;
let previewValues = Object.create(null);
let time = 0;
let playing = !matchMedia('(prefers-reduced-motion: reduce)').matches;
let speed = 1;
let dirty = true;
let activeTab = 'properties';
let grid = true, axes = true, core = true, moveLayers = true;
let dragSession = null;
let editingControl = null;
let suggestedControlName = '';
let layerFilter = '', draggedLayer = null;
let soloState = null;
const openSections = new Map([['transform', true], ['geometry', true], ['spin', true]]);
let saveTimer, toastTimer;
const undoStack = [], redoStack = [];
let historyGroup = null, historyTime = 0;
const viewport = new Viewport($('viewport'), {
  onSelect(id) { selectedId = id; renderLayers(); renderProperties(); viewport.setSelected(id); },
  onCameraChange(camera) { $('zoom-value').textContent = `${camera.zoom}%`; $('camera-view').value = camera.view; },
  onMoveStart: beginLayerDrag,
  onMove: moveLayerDrag,
  onMoveEnd: finishLayerDrag,
});
const selectedLayer = () => project.layers.find(layer => layer.id === selectedId);
function currentPosition(layer) {
  return Object.fromEntries(['x', 'y', 'z'].map(axis => {
    const binding = project.controls.find(control => control.layerId === layer.id && control.property === 'position.' + axis);
    return [axis, binding ? previewValues[binding.id] ?? binding.default : layer.position[axis]];
  }));
}
function syncAnchor() {
  const layer = selectedLayer(), toggle = project.controls.find(control => control.layerId === layer?.id && control.property === 'visible');
  const visible = toggle ? previewValues[toggle.id] ?? toggle.default : layer?.visible;
  viewport.setAnchor(visible ? currentPosition(layer) : null);
}
function setLayerFlag(layer, property, value) {
  setProperty(layer, property, value);
  const control = project.controls.find(control => control.layerId === layer.id && control.property === property);
  if (control) { control.default = value; delete previewValues[control.id]; }
}
function setLayerValue(layer, property, proposed) {
  const limits = propertyConfig(property, layer), value = Number(clamp(property === 'sides' ? Math.round(proposed) : proposed, limits.min, limits.max).toFixed(6));
  setProperty(layer, property, value);
  const control = project.controls.find(control => control.layerId === layer.id && control.property === property);
  if (control) { control.default = value; delete previewValues[control.id]; }
}
function beginLayerDrag(layerId) {
  const layer = project.layers.find(layer => layer.id === layerId); if (!layer) return;
  selectedId = layerId;
  dragSession = { before: JSON.stringify(project), undo: [...undoStack], redo: [...redoStack], position: currentPosition(layer), values: Object.assign(Object.create(null), previewValues), wasPlaying: playing, layerId, recorded: false };
  playing = false; updatePlayback();
  $('drag-readout').hidden = false;
}
function moveLayerDrag(delta, { layerId, axis = 'plane' } = {}) {
  if (!dragSession || dragSession.layerId !== layerId) return;
  const layer = selectedLayer(); if (!layer) return;
  if (!dragSession.recorded) { remember(); dragSession.recorded = true; }
  const snap = Number($('snap-size').value);
  for (const key of ['x', 'y', 'z']) {
    if (axis !== 'plane' && axis !== key) continue;
    let value = dragSession.position[key] + delta[key];
    if (snap) value = Math.round(value / snap) * snap;
    setLayerValue(layer, 'position.' + key, value);
  }
  changed(); syncAnchor();
  $('properties-panel').querySelectorAll('[data-prop^="position."]').forEach(input => { input.value = format(fieldValue(layer, input.dataset.prop)); });
  const p = currentPosition(layer);
  $('drag-readout').textContent = `X ${format(p.x)}   Y ${format(p.y)}   Z ${format(p.z)} studs${snap ? ` · snap ${snap}` : ''}`;
}
function finishLayerDrag({ cancelled = false } = {}) {
  if (!dragSession) return;
  if (cancelled && dragSession.recorded) {
    project = JSON.parse(dragSession.before); previewValues = dragSession.values;
    undoStack.splice(0, undoStack.length, ...dragSession.undo); redoStack.splice(0, redoStack.length, ...dragSession.redo);
    changed();
  }
  playing = dragSession.wasPlaying; dragSession = null; historyGroup = null;
  $('drag-readout').hidden = true; renderLayers(); renderProperties(); renderControls(); syncAnchor(); updatePlayback();
}
function toast(message) { $('toast').textContent = message; $('toast').classList.add('show'); clearTimeout(toastTimer); toastTimer = setTimeout(() => $('toast').classList.remove('show'), 3800); }
function persist() {
  clearTimeout(saveTimer);
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(project)); $('save-status').textContent = 'All changes saved locally'; }
  catch (error) {
    $('save-status').textContent = error.name === 'QuotaExceededError' || error.name === 'NS_ERROR_DOM_QUOTA_REACHED'
      ? 'Browser storage is full · download a project to save'
      : 'Local storage unavailable · download a project to save';
  }
}
function changed() { dirty = true; $('save-status').textContent = 'Saving changes…'; clearTimeout(saveTimer); saveTimer = setTimeout(persist, 350); updateHistory(); }
function remember(group) {
  const now = performance.now();
  if (!group || group !== historyGroup || now - historyTime > 900) {
    undoStack.push(JSON.stringify(project));
    if (undoStack.length > 70) undoStack.shift();
    redoStack.length = 0;
  }
  historyGroup = group || null;
  historyTime = now;
}
function mutate(callback, group) { remember(group); callback(); changed(); }
function updateHistory() { $('undo').disabled = !undoStack.length; $('redo').disabled = !redoStack.length; }
function history(direction) {
  const source = direction === 'undo' ? undoStack : redoStack;
  const destination = direction === 'undo' ? redoStack : undoStack;
  if (!source.length) return;
  destination.push(JSON.stringify(project)); project = JSON.parse(source.pop());
  if (!selectedLayer()) selectedId = project.layers[0]?.id || null;
  historyGroup = null; previewValues = Object.create(null); soloState = null; changed(); renderAll();
}
function renderTitle() {
  $('project-name').value = project.name;
  $('scene-name').textContent = project.name;
  document.title = `${project.name} · Shape Studio`;
}
function renderLayers() {
  $('layer-count').textContent = `${project.layers.length} layer${project.layers.length === 1 ? '' : 's'}`;
  $('visible-count').textContent = `${project.layers.filter(layer => layer.visible).length} visible`;
  const scrollTop = $('layers').scrollTop;
  const filtered = project.layers.filter(layer => `${layer.name} ${layer.type}`.toLowerCase().includes(layerFilter));
  $('layers').innerHTML = filtered.map(layer => `<div class="layer-row ${layer.id === selectedId ? 'selected' : ''} ${layer.visible ? '' : 'invisible'}" data-layer="${escapeHTML(layer.id)}" role="listitem" draggable="true" style="--layer-color:${layer.color}"><button class="layer-select" aria-pressed="${layer.id === selectedId}" title="Select ${escapeHTML(layer.name)}; drag to reorder"><span class="layer-symbol">${icon(layer.type)}</span><span class="layer-name">${escapeHTML(layer.name)}</span></button><button class="icon-button layer-visibility" aria-label="${layer.visible ? 'Hide' : 'Show'} ${escapeHTML(layer.name)}" aria-pressed="${layer.visible}" title="${layer.visible ? 'Hide' : 'Show'} layer">${icon(layer.visible ? 'eye' : 'eye-off')}</button></div>`).join('') || `<p class="layers-empty">${project.layers.length ? 'No layers match your search.' : 'Your next idea belongs here.'}</p>`;
  $('layers').scrollTop = scrollTop;
  $('duplicate').disabled = !selectedLayer() || project.layers.length >= 64;
  $('delete-layer').disabled = !selectedLayer();
  const index = project.layers.findIndex(layer => layer.id === selectedId);
  $('move-up').disabled = index < 1;
  $('move-down').disabled = index < 0 || index === project.layers.length - 1;
  $('add-layer').disabled = $('add-shape').disabled = project.layers.length >= 64;
  $('focus-layer').disabled = $('solo-layer').disabled = !selectedLayer();
  $('show-all').disabled = !project.layers.some(layer => !layer.visible);
  $('solo-layer').setAttribute('aria-pressed', soloState?.id === selectedId);
  viewport.setSelected(selectedId);
  syncAnchor();
}
const geometry = {
  sphere: ['radius'], ring: ['radius', 'arc'], torus: ['radius', 'tube', 'arc'], helix: ['radius', 'height', 'turns', 'tube', 'arc'],
  box: ['width', 'height', 'depth'], grid: ['width', 'depth'], cone: ['radius', 'height'], cylinder: ['radius', 'height'], line: ['width', 'tube'], spiral: ['radius', 'height', 'turns', 'tube', 'arc'],
  polygon: ['sides', 'radius', 'tube'], path: ['tube'], pointcloud: [],
};
const sectionProperties = {
  transform: ['position.x', 'position.y', 'position.z', 'rotation.x', 'rotation.y', 'rotation.z', 'scale.x', 'scale.y', 'scale.z'],
  spin: ['spin', 'spinX', 'spinZ', 'timeScale', 'timeOffset'],
  orbit: ['orbitRadius', 'orbitAspect', 'orbitSpeed', 'orbitTiltX', 'orbitTiltZ', 'orbitPhase'],
  bob: ['bobAmount', 'bobSpeed', 'bobPhase'],
  pulse: ['pulse', 'pulseSpeed', 'pulsePhase'],
  wave: ['wave', 'waveSpeed', 'waveCount', 'wavePhase'],
  deform: ['twist', 'taper', 'scatter'],
};
function availableProperties(layer) { return [...new Set([...geometry[layer.type], 'weight', 'phase', ...Object.values(sectionProperties).flat()])]; }
function propertyGroup(id, title, symbol, content, count) {
  return `<details class="property-section property-group" data-section="${id}" ${openSections.get(id) ? 'open' : ''}><summary><span class="section-symbol">${icon(symbol)}</span><span>${title}</span>${count ? `<span class="controls-counter">${count}</span>` : ''}<span class="disclosure-arrow">${icon('chevron')}</span></summary>${content}<button class="text-button section-reset" data-reset-section="${id}" title="Reset ${title.toLowerCase()} values, keeping any control limits">${icon('restart')}Reset ${title.toLowerCase()}</button></details>`;
}
function propertyConfig(property, layer = selectedLayer()) {
  const config = { ...PROPERTY_DEFS[property] };
  const control = project.controls.find(control => control.layerId === layer?.id && control.property === property);
  if (control) { config.min = control.min; config.max = control.max; config.step = 1 / controlDivisor(control); }
  return config;
}
function fieldValue(layer, property) {
  const control = project.controls.find(control => control.layerId === layer.id && control.property === property);
  return control ? control.default : getProperty(layer, property);
}
function rangeField(layer, property, label, unit = '', visualMax) {
  const config = propertyConfig(property, layer), value = fieldValue(layer, property);
  const bound = project.controls.some(control => control.layerId === layer.id && control.property === property);
  const rangeMax = Math.min(config.max, Math.max(visualMax ?? config.max, value));
  const rangeMin = Math.max(config.min, property.startsWith('spin') ? Math.min(-90, value) : config.min);
  return `<div class="property-row"><label for="prop-${property}">${escapeHTML(label || config.label)}${unit ? `<small>${unit}</small>` : ''}</label><input id="prop-${property}" data-prop="${property}" type="number" value="${format(value)}" min="${config.min}" max="${config.max}" step="any" aria-label="${escapeHTML(label || config.label)}"><button class="expose-button" data-expose="${property}" title="${bound ? 'Edit' : 'Add'} in-game control for ${escapeHTML(config.label)}" aria-label="${bound ? 'Edit' : 'Add'} ${escapeHTML(config.label)} control">${icon(bound ? 'sliders' : 'plus')}</button><input data-prop="${property}" type="range" value="${value}" min="${rangeMin}" max="${rangeMax}" step="${config.step}" aria-label="${escapeHTML(label || config.label)} slider"></div>`;
}
function transformRow(layer, group, label, unit) {
  return `<div class="transform-label"><span>${label}</span><span>${unit}</span></div><div class="transform-row">${['x', 'y', 'z'].map(axis => {
    const key = group + '.' + axis, config = propertyConfig(key, layer);
    return `<div class="axis-field"><span aria-hidden="true">${axis.toUpperCase()}</span><input type="number" data-prop="${key}" value="${format(fieldValue(layer, key))}" min="${config.min}" max="${config.max}" step="any" aria-label="${label} ${axis.toUpperCase()}"><button type="button" class="transform-expose" data-expose="${key}" aria-label="Add ${label} ${axis.toUpperCase()} control" title="Create in-game control">+</button></div>`;
  }).join('')}</div>`;
}
function renderProperties() {
  const layer = selectedLayer();
  if (!layer) { $('properties-panel').innerHTML = `<div class="no-selection">${icon('cube')}<h3>Room for your imagination.</h3><p>Select a layer to customize it,<br>or add a new shape to get started.</p></div>`; return; }
  $('properties-panel').innerHTML = `<div class="selected-heading" style="--layer-color:${layer.color}"><span class="selected-icon">${icon(layer.type)}</span><div><input id="layer-name" aria-label="Layer name" value="${escapeHTML(layer.name)}" maxlength="64"><p>${typeName(layer.type)}</p></div></div>
  ${customGeometryFields(layer)}
  ${propertyGroup('transform', 'Transform', 'axes', transformRow(layer, 'position', 'Position', 'studs') + transformRow(layer, 'rotation', 'Rotation', 'degrees') + transformRow(layer, 'scale', 'Scale', '×'), 9)}
  ${propertyGroup('geometry', 'Geometry', layer.type, geometry[layer.type].map(property => rangeField(layer, property, layer.type === 'line' && property === 'width' ? 'Length' : null, property === 'arc' ? '°' : ['turns', 'sides'].includes(property) ? '' : 'studs', property === 'arc' ? 360 : property === 'sides' ? 16 : property === 'turns' ? 10 : 100)).join('') + (!['grid', 'pointcloud'].includes(layer.type) ? `<label class="checkbox-row"><input id="fill-volume" type="checkbox" ${fieldValue(layer, 'fill') ? 'checked' : ''}>${layer.type === 'path' ? 'Fill tube cross-section' : layer.type === 'polygon' ? 'Fill polygon interior' : 'Fill the interior'}</label>` : '') + rangeField(layer, 'weight', 'Part weight', '×', 5) + rangeField(layer, 'phase', 'Base phase', '°', 360) + '<p class="section-note">Weight sets this layer’s share of the debris. Base phase offsets the shape, pulse, and wave.</p>')}
  ${propertyGroup('spin', 'Spin & timing', 'restart', rangeField(layer, 'spin', 'Spin Y', '°/s', 90) + rangeField(layer, 'spinX', 'Spin X', '°/s', 90) + rangeField(layer, 'spinZ', 'Spin Z', '°/s', 90) + rangeField(layer, 'timeScale', 'Time scale', '×', 4) + rangeField(layer, 'timeOffset', 'Time offset', 's', 60) + '<p class="section-note">Time scale affects all motion on this layer. Zero freezes it; a negative value reverses it.</p>', 5)}
  ${propertyGroup('orbit', 'Orbit', 'orbit', '<p class="section-note motion-note">Move the whole layer around its position. Spin still rotates the shape itself.</p>' + rangeField(layer, 'orbitRadius', 'Orbit radius', 'studs', 150) + rangeField(layer, 'orbitAspect', 'Ellipse aspect', 'Z / X', 3) + rangeField(layer, 'orbitSpeed', 'Orbit speed', '°/s', 90) + rangeField(layer, 'orbitTiltX', 'Tilt X', '°', 180) + rangeField(layer, 'orbitTiltZ', 'Tilt Z', '°', 180) + rangeField(layer, 'orbitPhase', 'Orbit phase', '°', 360), 6)}
  ${propertyGroup('bob', 'Float & bob', 'arrow-up', rangeField(layer, 'bobAmount', 'Bob height', 'studs', 60) + rangeField(layer, 'bobSpeed', 'Bob frequency', 'Hz', 3) + rangeField(layer, 'bobPhase', 'Bob phase', '°', 360) + '<p class="section-note">Moves the whole layer up and down in world space. Height is the distance from center to peak.</p>', 3)}
  ${propertyGroup('pulse', 'Pulse', 'sphere', rangeField(layer, 'pulse', 'Pulse amount', '%', 90) + rangeField(layer, 'pulseSpeed', 'Pulse frequency', 'Hz', 3) + rangeField(layer, 'pulsePhase', 'Pulse phase', '°', 360), 3)}
  ${propertyGroup('wave', 'Wave', 'helix', rangeField(layer, 'wave', 'Wave height', 'studs', 50) + rangeField(layer, 'waveSpeed', 'Wave frequency', 'Hz', 3) + rangeField(layer, 'waveCount', 'Wave count', 'cycles', 10) + rangeField(layer, 'wavePhase', 'Wave phase', '°', 360) + '<p class="section-note">Wave count sets the number of crests along the point sequence. The wave follows local Y before rotation.</p>', 4)}
  ${propertyGroup('deform', 'Deform & scatter', 'sliders', rangeField(layer, 'twist', 'Twist along path', '°', 360) + rangeField(layer, 'taper', 'Taper along path', '%', 90) + rangeField(layer, 'scatter', 'Scatter distance', 'studs', 50) + '<p class="section-note">Twist and taper follow the point sequence. Scatter adds a stable offset to each point; it does not flicker between frames.</p>', 3)}
  <section class="property-section"><h3>Preview color<span>${icon('eye')}</span></h3><div class="color-row">${colors.map(color => `<button class="color-swatch ${layer.color.toLowerCase() === color ? 'selected' : ''}" style="--swatch:${color}" data-color="${color}" aria-label="Set preview color ${color}"></button>`).join('')}<input type="color" id="layer-color" value="${layer.color}" aria-label="Custom preview color"><span class="color-value">${layer.color.toUpperCase()}</span></div><p class="section-note">Helps you identify layers. Original part colors are kept in game.</p></section>`;
}
function customGeometryFields(layer) {
  if (layer.type === 'polygon') return `<section class="custom-geometry-panel"><p>Choose the number of sides below. Convert to a path to move each vertex freely.</p><button id="convert-path" class="secondary-button">${icon('edit')}Edit individual vertices</button></section>`;
  if (!layer.path) return '';
  return `<section class="custom-geometry-panel"><div class="custom-geometry-summary"><span>${layer.path.points.length.toLocaleString()} vertices</span><span>${layer.type === 'pointcloud' ? 'Separate points' : (layer.path.closed ? 'Closed' : 'Open') + (layer.path.smooth ? ' · Smooth' : ' · Straight')}</span></div><button id="edit-path" class="secondary-button">${icon('edit')}Edit vertices</button>${layer.type === 'pointcloud' ? '<p>Points stay separate. Their order determines how debris is distributed.</p>' : '<p>Draw, move or insert vertices. Switch drawing planes to shape it in 3D. Tube radius gives your outline thickness.</p>'}<div class="geometry-mirrors"><span>Mirror</span>${['x', 'y', 'z'].map(axis => `<button class="quiet-button" data-mirror="${axis}" aria-label="Mirror vertices on ${axis.toUpperCase()} axis">${axis.toUpperCase()}</button>`).join('')}</div></section>`;
}
function renderControls() {
  $('control-count').textContent = project.controls.length;
  $('controls-panel').innerHTML = `<div class="controls-intro"><h3>A formation that listens.</h3><p>Add sliders, toggle switches, and real action buttons. They work in the preview and your exported plugin.</p><button id="new-control" class="secondary-button" ${project.layers.length ? '' : 'disabled'}>${icon('plus')}Add a slider</button><div class="control-type-actions"><button class="secondary-button" data-new-control="toggle" ${project.layers.length ? '' : 'disabled'}>+ Toggle</button><button class="secondary-button" data-new-control="button" ${project.layers.length ? '' : 'disabled'}>+ Button</button></div></div>` + project.controls.map(control => {
    const layer = project.layers.find(layer => layer.id === control.layerId), type = controlType(control), value = previewValues[control.id] ?? control.default;
    const context = type === 'button' ? ACTION_LABELS[control.action] : (BOOLEAN_DEFS[control.property] || PROPERTY_DEFS[control.property]).label;
    let preview;
    if (type === 'toggle') preview = `<label class="control-switch"><span>${value ? 'On' : 'Off'}</span><input type="checkbox" role="switch" data-preview-toggle="${escapeHTML(control.id)}" aria-label="${escapeHTML(control.name)} preview toggle" ${value ? 'checked' : ''}></label>`;
    else if (type === 'button') preview = `<button class="primary-button control-action-button" data-run-control="${escapeHTML(control.id)}">${icon(control.action === 'reset' ? 'sliders' : 'restart')}${escapeHTML(control.name)}</button><p class="control-action-description">${control.action === 'restart' ? 'Start this layer’s animation clock from zero.' : control.action === 'reverse' ? 'Reverse this layer’s motion from its current pose.' : 'Restore this layer’s controls and animation state.'}</p>`;
    else {
      const step = control.property === 'sides' ? 1 : 1 / controlDivisor(control);
      preview = `<div class="control-preview"><input type="range" data-preview="${escapeHTML(control.id)}" min="${control.min}" max="${control.max}" step="${step}" value="${value}" aria-label="${escapeHTML(control.name)} preview slider"><input type="number" id="preview-${escapeHTML(control.id)}" data-preview="${escapeHTML(control.id)}" min="${control.min}" max="${control.max}" step="any" value="${format(value)}" aria-label="${escapeHTML(control.name)} preview value"></div><div class="control-limits"><span>${control.min}</span><span>${control.max}</span></div>`;
    }
    return `<div class="control-card" data-control="${escapeHTML(control.id)}"><p class="control-context">${escapeHTML(layer.name)} · ${type.toUpperCase()} · ${escapeHTML(context)}</p><div class="control-card-heading"><span class="control-name">${escapeHTML(control.name)}</span><button class="icon-button" data-edit-control="${escapeHTML(control.id)}" aria-label="Edit ${escapeHTML(control.name)} control">${icon('edit')}</button><button class="icon-button" data-delete-control="${escapeHTML(control.id)}" aria-label="Delete ${escapeHTML(control.name)} control">${icon('trash')}</button></div>${preview}</div>`;
  }).join('') + (project.controls.length ? '<button id="reset-controls" class="text-button reset-controls">Reset preview to defaults</button><p class="micro-copy" style="margin:8px 17px">Preview controls are temporary. Edit a control to change its exported default.</p>' : `<div class="controls-empty">${icon('sliders')}<p>A bigger orbit. A visibility switch.<br>A button that reverses time. You decide.</p></div>`);
}
function renderAll() {
  renderTitle(); renderLayers(); renderProperties(); renderControls(); updateHistory();
  if (!$('part-count').querySelector(`option[value="${project.parts}"]`)) $('part-count').add(new Option(`${project.parts.toLocaleString()} parts`, project.parts));
  $('part-count').value = project.parts; $('point-size').value = project.pointSize;
  viewport.setOptions({ pointSize: project.pointSize, grid, axes, core, coreRadius: 2.5, move: moveLayers }); dirty = true;
}
function setTab(tab) {
  activeTab = tab;
  for (const name of ['properties', 'controls']) { const active = tab === name; $(`${name}-tab`).classList.toggle('active', active); $(`${name}-tab`).setAttribute('aria-selected', active); $(`${name}-panel`).hidden = !active; }
  if (tab === 'controls') renderControls();
}
function addLayer(type) {
  if (type === 'path') { drawPath(); return; }
  if (type === 'pointcloud') { importGeometry('coordinates'); return; }
  if (project.layers.length >= 64) { toast('A project can contain up to 64 layers.'); return; }
  const name = titleCase(type), matches = project.layers.filter(layer => layer.type === type).length;
  const layer = createLayer(type, { name: matches ? `${name} ${matches + 1}` : name, color: colors[project.layers.length % colors.length] });
  layerFilter = ''; $('layer-search').value = ''; soloState = null;
  mutate(() => { project.layers.push(layer); selectedId = layer.id; });
  $('shape-dialog').close(); renderAll(); setTab('properties'); toast(`${layer.name} added. Make it your own.`);
  $('layers').querySelector('.selected')?.scrollIntoView({ block: 'nearest' });
  if (project.layers.length === 1) { viewport.setPoints(sampleProject(project, time, previewValues)); viewport.fit(); }
  if (type === 'polygon') { viewport.setView('front'); viewport.setPoints(sampleProject(project, time, previewValues)); viewport.fit(); }
}
function addGeometry(specs) {
  if (project.layers.length + specs.length > 64) throw new Error('A project can contain up to 64 layers.');
  const layers = specs.map((spec, index) => createLayer(spec.type, { ...spec, color: colors[(project.layers.length + index) % colors.length] }));
  // Validate the complete result before committing one undoable action.
  normalizeProject({ ...project, layers: [...project.layers, ...layers] });
  mutate(() => { project.layers.push(...layers); selectedId = layers[0].id; });
  layerFilter = ''; $('layer-search').value = ''; soloState = null;
  renderAll(); setTab('properties'); viewport.setView('front'); viewport.setPoints(sampleProject(project, time, previewValues)); viewport.fit();
  toast(`${layers.length === 1 ? layers[0].name : layers.length + ' geometry layers'} added. Select a layer to edit its vertices.`);
}
function drawPath() {
  if (project.layers.length >= 64) { toast('A project can contain up to 64 layers.'); return; }
  $('shape-dialog').close();
  openPathEditor({ path: { points: [], closed: false, smooth: false }, onApply: path => addGeometry([{ type: 'path', name: 'Custom path', path }]) });
}
function editPath() {
  const layer = selectedLayer(); if (!layer?.path) return;
  openPathEditor({ path: layer.path, minPoints: layer.type === 'pointcloud' ? 1 : 2, onApply: path => {
    const replacement = createLayer(layer.type, { ...layer, path });
    mutate(() => { project.layers[project.layers.indexOf(layer)] = replacement; });
    renderAll(); toast('Vertices updated.');
  } });
}
function importGeometry(mode = 'svg') {
  if (project.layers.length >= 64) { toast('A project can contain up to 64 layers.'); return; }
  $('shape-dialog').close(); openSourceEditor({ mode, remainingLayers: 64 - project.layers.length, onApply: addGeometry });
}
function convertPolygon() {
  const layer = selectedLayer(); if (layer?.type !== 'polygon') return;
  const sides = Math.round(fieldValue(layer, 'sides')), radius = fieldValue(layer, 'radius'), phase = fieldValue(layer, 'phase') * Math.PI / 180;
  const path = { closed: true, smooth: false, points: Array.from({ length: sides }, (_, i) => {
    const angle = i / sides * Math.PI * 2 + phase + Math.PI / 2;
    return { x: Math.cos(angle) * radius, y: Math.sin(angle) * radius, z: 0 };
  }) };
  openPathEditor({ path, onApply: edited => {
    const replacement = createLayer('path', { ...layer, type: 'path', path: edited, fill: false });
    mutate(() => {
      project.layers[project.layers.indexOf(layer)] = replacement;
      project.controls = project.controls.filter(control => control.layerId !== layer.id || !['radius', 'sides'].includes(control.property));
    });
    renderAll(); toast('Polygon converted to an editable outline. Undo restores its polygon controls.');
  } });
}
function duplicateLayer() {
  const layer = selectedLayer(); if (!layer || project.layers.length >= 64) return;
  const copy = createLayer(layer.type, { ...clone(layer), id: createLayer(layer.type).id, name: (layer.name.slice(0, 57) + ' copy') });
  mutate(() => {
    project.layers.splice(project.layers.indexOf(layer) + 1, 0, copy);
    for (const control of project.controls.filter(control => control.layerId === layer.id)) {
      if (project.controls.length >= 96) break;
      project.controls.push({ ...control, id: uniqueId(), layerId: copy.id, name: (control.name.slice(0, 57) + ' copy') });
    }
    selectedId = copy.id;
  });
  renderAll(); toast('Layer duplicated, including its controls.');
}
function deleteLayer() {
  const layer = selectedLayer(); if (!layer) return;
  const index = project.layers.indexOf(layer);
  mutate(() => { project.layers.splice(index, 1); project.controls = project.controls.filter(control => control.layerId !== layer.id); selectedId = project.layers[Math.min(index, project.layers.length - 1)]?.id || null; });
  renderAll(); toast(`${layer.name} removed. Undo to bring it back.`);
}
function loadPreset(preset) {
  soloState = null; layerFilter = ''; $('layer-search').value = '';
  mutate(() => { project = createProject(preset); project.pointSize = 3.4; selectedId = project.layers[1]?.id || project.layers[0]?.id || null; previewValues = Object.create(null); time = 0; });
  renderAll(); viewport.setPoints(sampleProject(project, time)); viewport.fit(); toast(preset === 'blank' ? 'A fresh canvas. Your previous scene is one undo away.' : `${project.name} loaded. Let’s make it yours.`);
}
function bindProperty(input) {
  const layer = selectedLayer(), property = input.dataset.prop;
  if (!layer || input.value === '' || !Number.isFinite(Number(input.value))) return;
  const config = propertyConfig(property, layer), value = Number(clamp(property === 'sides' ? Math.round(Number(input.value)) : Number(input.value), config.min, config.max).toFixed(6));
  mutate(() => setLayerValue(layer, property, value), layer.id + property);
  syncAnchor();
  $('properties-panel').querySelectorAll('[data-prop]').forEach(sibling => {
    if (sibling.dataset.prop !== property || sibling === input) return;
    if (sibling.type === 'range') { if (value > Number(sibling.max)) sibling.max = value; if (value < Number(sibling.min)) sibling.min = value; }
    sibling.value = format(value);
  });
}
function openControl(property = null, id = null, requestedType = 'slider') {
  if (!project.layers.length) return;
  if (!id && property) id = project.controls.find(control => control.layerId === selectedId && control.property === property)?.id || null;
  editingControl = id;
  const control = project.controls.find(control => control.id === id), layer = project.layers.find(layer => layer.id === control?.layerId) || selectedLayer() || project.layers[0];
  const type = control ? controlType(control) : (property && BOOLEAN_DEFS[property] ? 'toggle' : requestedType);
  $('control-dialog-title').textContent = control ? 'Edit control' : 'Add a control';
  $('control-type').value = type;
  $('control-layer').innerHTML = project.layers.map(layer => `<option value="${escapeHTML(layer.id)}">${escapeHTML(layer.name)}</option>`).join('');
  $('control-layer').value = layer.id;
  $('control-action').value = control?.action || 'restart';
  suggestedControlName = ''; $('control-name').value = '';
  configureControlForm(control?.property || property);
  if (control) {
    $('control-name').value = control.name;
    if (type === 'slider') { $('control-min').value = control.min; $('control-max').value = control.max; $('control-default').value = control.default; }
    if (type === 'toggle') $('control-toggle-default').checked = control.default;
  }
  $('control-error').textContent = '';
  $('control-dialog').showModal();
}
function availableBooleanProperties(layer) {
  return Object.keys(BOOLEAN_DEFS).filter(key => key !== 'fill' || !['grid', 'pointcloud'].includes(layer.type));
}
function populateControlProperties(preferred = $('control-property').value) {
  const layer = project.layers.find(layer => layer.id === $('control-layer').value), type = $('control-type').value;
  const definitions = type === 'toggle' ? BOOLEAN_DEFS : PROPERTY_DEFS;
  const properties = type === 'toggle' ? availableBooleanProperties(layer) : availableProperties(layer);
  const current = project.controls.find(control => control.id === editingControl);
  if (current && controlType(current) === type && current.layerId === layer.id && !properties.includes(current.property)) properties.push(current.property);
  $('control-property').innerHTML = properties.map(key => `<option value="${key}">${escapeHTML(definitions[key].label)}</option>`).join('');
  const unbound = properties.find(key => !project.controls.some(control => control.id !== editingControl && control.layerId === layer.id && control.property === key));
  $('control-property').value = properties.includes(preferred) ? preferred : (unbound || properties[0]);
}
function configureControlForm(preferred) {
  const type = $('control-type').value;
  $('control-number-fields').hidden = type !== 'slider';
  for (const id of ['control-min', 'control-max', 'control-default']) $(id).disabled = type !== 'slider';
  $('control-toggle-label').hidden = type !== 'toggle';
  $('control-property-label').hidden = type === 'button'; $('control-property').disabled = type === 'button';
  $('control-action-label').hidden = type !== 'button'; $('control-action-note').hidden = type !== 'button';
  if (type !== 'button') populateControlProperties(preferred);
  setControlDefaults();
}
function setControlDefaults() {
  const layer = project.layers.find(layer => layer.id === $('control-layer').value), type = $('control-type').value, property = $('control-property').value;
  const label = type === 'button' ? ACTION_LABELS[$('control-action').value] : (type === 'toggle' ? BOOLEAN_DEFS[property] : PROPERTY_DEFS[property]).label;
  if (!$('control-name').value || $('control-name').value === suggestedControlName) $('control-name').value = `${layer.name} ${label.toLowerCase()}`.slice(0, 48);
  suggestedControlName = `${layer.name} ${label.toLowerCase()}`.slice(0, 48);
  if (type === 'button') return;
  const value = fieldValue(layer, property);
  if (type === 'toggle') { $('control-toggle-default').checked = Boolean(value); return; }
  const config = PROPERTY_DEFS[property];
  $('control-min').value = config.min < 0 ? Math.max(config.min, Math.min(-90, value)) : config.min;
  $('control-max').value = Math.min(config.max, Math.max(value * 2, property.includes('scale') ? 3 : 100));
  $('control-default').value = value;
}
function bakeControl(projectValue, control) {
  if (controlType(control) === 'button') return;
  const layer = projectValue.layers.find(layer => layer.id === control.layerId);
  if (layer) setProperty(layer, control.property, control.default);
}
function saveControl(event) {
  event.preventDefault();
  const type = $('control-type').value;
  const control = { id: editingControl || uniqueId(), type, name: $('control-name').value.trim(), layerId: $('control-layer').value };
  if (type === 'button') control.action = $('control-action').value;
  else {
    control.property = $('control-property').value;
    if (type === 'toggle') control.default = $('control-toggle-default').checked;
    else Object.assign(control, { min: Number($('control-min').value), max: Number($('control-max').value), default: Number($('control-default').value) });
  }
  try {
    const next = clone(project), index = next.controls.findIndex(item => item.id === editingControl);
    if (index < 0) next.controls.push(control); else { bakeControl(next, next.controls[index]); next.controls[index] = control; }
    const valid = normalizeProject(next); bakeControl(valid, control);
    mutate(() => { project = valid; delete previewValues[control.id]; });
    $('control-dialog').close(); renderAll(); setTab('controls'); toast(type === 'button' ? 'Button saved. Click it to try the action.' : 'Control saved. Try it in the preview.');
  } catch (error) { $('control-error').textContent = error.message; }
}
function safeFilename() { return (project.name.replace(/[<>:"/\\|?*\u0000-\u001f]/g, '-').replace(/[. ]+$/g, '').trim() || 'My Formation').slice(0, 72); }
function download(contents, filename, type = 'text/plain') {
  const url = URL.createObjectURL(new Blob([contents], { type }));
  const link = document.createElement('a'); link.href = url; link.download = filename; document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}
function saveProject() { download(serializeProject(project), safeFilename() + '.gravity.json', 'application/json'); toast('Editable project downloaded.'); }
function showExport() {
  try {
    $('export-code').value = exportLua(project);
    const layers = project.layers.filter(layer => layer.visible || project.controls.some(control => control.layerId === layer.id && control.type === 'toggle' && control.property === 'visible')), controls = project.controls.filter(control => layers.some(layer => layer.id === control.layerId));
    $('export-summary').textContent = `${project.name} · ${layers.length} layers · ${controls.length} controls`;
    $('export-dialog').showModal();
  } catch (error) { toast(error.message); }
}
async function copyLua() {
  try { await navigator.clipboard.writeText($('export-code').value); toast('Lua plugin copied to clipboard.'); }
  catch { $('export-code').focus(); $('export-code').select(); try { if (document.execCommand('copy')) { toast('Lua plugin copied to clipboard.'); return; } } catch {} toast('Select and copy the highlighted Lua, or download the plugin.'); }
}
function updatePlayback() { $('play-pause').innerHTML = icon(playing ? 'pause' : 'play'); $('play-pause').setAttribute('aria-label', playing ? 'Pause animation' : 'Play animation'); $('preview-status').textContent = playing ? 'Live preview' : 'Preview paused'; }
function showShapes() { if (project.layers.length >= 64) { toast('A project can contain up to 64 layers.'); return; } $('shape-dialog').showModal(); }

$('layers').addEventListener('click', event => {
  const row = event.target.closest('[data-layer]'); if (!row) return;
  const layer = project.layers.find(layer => layer.id === row.dataset.layer);
  if (event.target.closest('.layer-visibility')) { soloState = null; mutate(() => { setLayerFlag(layer, 'visible', !layer.visible); }); renderLayers(); renderControls(); }
  else { selectedId = layer.id; renderLayers(); renderProperties(); }
});
$('layer-search').addEventListener('input', () => { layerFilter = $('layer-search').value.trim().toLowerCase(); renderLayers(); });
$('layers').addEventListener('dragstart', event => {
  const row = event.target.closest('[data-layer]'); if (!row) return;
  draggedLayer = row.dataset.layer; event.dataTransfer.effectAllowed = 'move'; event.dataTransfer.setData('text/plain', draggedLayer);
});
$('layers').addEventListener('dragover', event => {
  const row = event.target.closest('[data-layer]'); if (!row || !draggedLayer || row.dataset.layer === draggedLayer) return;
  event.preventDefault(); event.dataTransfer.dropEffect = 'move';
  $('layers').querySelectorAll('.drag-over').forEach(item => item.classList.remove('drag-over')); row.classList.add('drag-over');
});
$('layers').addEventListener('drop', event => {
  event.preventDefault(); const row = event.target.closest('[data-layer]');
  if (row && draggedLayer && row.dataset.layer !== draggedLayer) {
    const id = draggedLayer, target = row.dataset.layer;
    mutate(() => { const from = project.layers.findIndex(layer => layer.id === id); const [layer] = project.layers.splice(from, 1); const to = project.layers.findIndex(layer => layer.id === target); project.layers.splice(to, 0, layer); selectedId = id; });
  }
  draggedLayer = null; renderLayers(); renderProperties();
});
$('layers').addEventListener('dragend', () => { draggedLayer = null; $('layers').querySelectorAll('.drag-over').forEach(row => row.classList.remove('drag-over')); });
$('focus-layer').onclick = () => {
  const points = sampleProject(project, time, previewValues).filter(point => point.layerId === selectedId);
  if (points.length) viewport.fit(points); else toast('Show this layer and give it a positive part weight to focus it.');
};
$('solo-layer').onclick = () => {
  if (!selectedLayer()) return;
  mutate(() => {
    if (soloState?.id === selectedId) { for (const layer of project.layers) setLayerFlag(layer, 'visible', soloState.visibility[layer.id] ?? layer.visible); soloState = null; }
    else { const visibility = soloState?.visibility || Object.fromEntries(project.layers.map(layer => [layer.id, layer.visible])); soloState = { id: selectedId, visibility }; for (const layer of project.layers) setLayerFlag(layer, 'visible', layer.id === selectedId); }
  });
  renderLayers(); renderControls();
};
$('show-all').onclick = () => { soloState = null; mutate(() => { project.layers.forEach(layer => { setLayerFlag(layer, 'visible', true); }); }); renderLayers(); renderControls(); };
$('properties-panel').addEventListener('toggle', event => { if (event.target.dataset.section) openSections.set(event.target.dataset.section, event.target.open); }, true);
$('properties-panel').addEventListener('input', event => {
  if (event.target.dataset.prop) bindProperty(event.target);
  if (event.target.id === 'layer-color') { mutate(() => { selectedLayer().color = event.target.value; }, selectedId + 'color'); renderLayers(); const value = $('properties-panel').querySelector('.color-value'); if (value) value.textContent = event.target.value.toUpperCase(); }
});
$('properties-panel').addEventListener('change', event => {
  if (event.target.dataset.prop) { const value = fieldValue(selectedLayer(), event.target.dataset.prop); event.target.value = format(value); historyGroup = null; }
  if (event.target.id === 'layer-name') { const name = event.target.value.trim(); if (name) mutate(() => { selectedLayer().name = name; }); renderLayers(); renderProperties(); renderControls(); }
  if (event.target.id === 'fill-volume') { mutate(() => { setLayerFlag(selectedLayer(), 'fill', event.target.checked); }); renderControls(); }
});
$('properties-panel').addEventListener('click', event => {
  if (event.target.closest('#edit-path')) { editPath(); return; }
  if (event.target.closest('#convert-path')) { convertPolygon(); return; }
  const mirror = event.target.closest('[data-mirror]');
  if (mirror && selectedLayer()?.path) {
    mutate(() => { selectedLayer().path.points.forEach(point => { point[mirror.dataset.mirror] *= -1; }); });
    renderProperties(); return;
  }
  const reset = event.target.closest('[data-reset-section]');
  if (reset) {
    const layer = selectedLayer(), section = reset.dataset.resetSection;
    const properties = section === 'geometry' ? [...geometry[layer.type], 'weight', 'phase'] : sectionProperties[section];
    const defaults = createLayer(layer.type);
    mutate(() => { for (const key of properties) setLayerValue(layer, key, getProperty(defaults, key)); if (section === 'geometry') setLayerFlag(layer, 'fill', defaults.fill); });
    renderProperties(); renderControls(); syncAnchor(); toast('Section reset. Undo restores your previous settings.'); return;
  }
  const expose = event.target.closest('[data-expose]'); if (expose) openControl(expose.dataset.expose);
  const color = event.target.closest('[data-color]'); if (color) { mutate(() => { selectedLayer().color = color.dataset.color; }); renderLayers(); renderProperties(); }
});
$('controls-panel').addEventListener('click', event => {
  if (event.target.closest('#new-control')) openControl();
  const create = event.target.closest('[data-new-control]');
  if (create) openControl(null, null, create.dataset.newControl);
  const run = event.target.closest('[data-run-control]');
  if (run) { previewValues = applyPreviewAction(project, run.dataset.runControl, time, previewValues); dirty = true; syncAnchor(); renderControls(); }
  const edit = event.target.closest('[data-edit-control]'); if (edit) openControl(null, edit.dataset.editControl);
  const remove = event.target.closest('[data-delete-control]'); if (remove) { mutate(() => { const control = project.controls.find(control => control.id === remove.dataset.deleteControl); bakeControl(project, control); delete previewValues[control.id]; project.controls = project.controls.filter(control => control.id !== remove.dataset.deleteControl); }); renderControls(); renderProperties(); syncAnchor(); }
  if (event.target.closest('#reset-controls')) { previewValues = Object.create(null); dirty = true; syncAnchor(); renderControls(); toast('Preview controls reset to their defaults.'); }
});
$('controls-panel').addEventListener('input', event => {
  const id = event.target.dataset.preview; if (!id || event.target.value === '') return;
  const control = project.controls.find(control => control.id === id), proposed = Number(event.target.value); if (!Number.isFinite(proposed)) return;
  previewValues[id] = Number(clamp(proposed, control.min, control.max).toFixed(6)); dirty = true; syncAnchor();
  $('controls-panel').querySelectorAll('[data-preview]').forEach(input => { if (input !== event.target && input.dataset.preview === id) input.value = format(previewValues[id]); });
});
$('controls-panel').addEventListener('change', event => {
  const toggle = event.target.dataset.previewToggle;
  if (toggle) { previewValues[toggle] = event.target.checked; dirty = true; syncAnchor(); renderControls(); return; }
  const id = event.target.dataset.preview;
  if (id) { const control = project.controls.find(control => control.id === id); event.target.value = format(previewValues[id] ?? control.default); }
});
$('control-form').addEventListener('submit', saveControl);
$('control-layer').addEventListener('change', () => configureControlForm());
$('control-type').addEventListener('change', () => configureControlForm());
$('control-action').addEventListener('change', setControlDefaults);
$('control-property').addEventListener('change', setControlDefaults);
$('properties-tab').onclick = () => setTab('properties'); $('controls-tab').onclick = () => setTab('controls');
document.querySelector('.inspector-tabs').addEventListener('keydown', event => { if (['ArrowLeft', 'ArrowRight'].includes(event.key)) { event.preventDefault(); setTab(activeTab === 'controls' ? 'properties' : 'controls'); $(`${activeTab}-tab`).focus(); } });
for (const id of ['add-layer', 'add-shape', 'empty-add']) $(id).onclick = showShapes;
$('draw-path').onclick = drawPath;
$('import-geometry').onclick = () => importGeometry('svg');
$('formula-geometry').onclick = () => importGeometry('formula');
$('shape-library').innerHTML = LAYER_TYPES.filter(type => !['path', 'pointcloud'].includes(type)).map(type => `<button class="shape-option" data-add-type="${type}">${icon(type)}<span>${typeName(type)}</span></button>`).join('');
$('shape-library').onclick = event => { const button = event.target.closest('[data-add-type]'); if (button) addLayer(button.dataset.addType); };
$('custom-shape-library').onclick = event => {
  const button = event.target.closest('[data-create]'); if (!button) return;
  if (button.dataset.create === 'path') drawPath(); else importGeometry(button.dataset.create);
};
function presetPicture(preset) {
  if (preset === 'orbit') return '<svg viewBox="0 0 100 65" fill="none"><g transform="translate(50 32)" stroke="#b7cf8f" stroke-width="1"><ellipse rx="36" ry="11" transform="rotate(-25)"/><ellipse rx="30" ry="12" transform="rotate(48)" stroke="#b8a4ff"/><ellipse rx="23" ry="9" transform="rotate(-70)" stroke="#79d9ea"/><circle r="10" fill="#b7cf8f15" stroke-dasharray="1.5 2.5"/><ellipse rx="5" ry="10"/><path d="M-9-3h18M-9 3h18" opacity=".5"/></g></svg>';
  if (preset === 'helix') return '<svg viewBox="0 0 100 65" fill="none" stroke-width="1.5"><path d="M35 4c40 8 0 20 0 28s40 20 0 29" stroke="#b7cf8f"/><path d="M65 4c-40 8 0 20 0 28s-40 20 0 29" stroke="#b8a4ff"/><path d="M35 5h30M42 13h16M36 23h28M35 33h30M43 43h14M37 53h26M35 61h30" stroke="#698d62" stroke-dasharray="1 3"/></svg>';
  return '<svg viewBox="0 0 100 65" fill="none"><ellipse cx="50" cy="32" rx="43" ry="18" transform="rotate(-15 50 32)" stroke="#b8a4ff"/><ellipse cx="50" cy="32" rx="29" ry="12" transform="rotate(-15 50 32)" stroke="#b7cf8f"/><circle cx="50" cy="32" r="8" fill="#ffc98a33" stroke="#ffc98a"/><circle cx="77" cy="22" r="4" fill="#79d9ea"/><circle cx="10" cy="43" r="2" fill="#b8a4ff"/></svg>';
}
$('presets').innerHTML = [['orbit', 'Orbit Bloom'], ['helix', 'Double Helix'], ['solar', 'Solar System']].map(([id, name]) => `<button class="preset-card" data-preset="${id}" aria-label="Load ${name} preset"><span class="preset-preview">${presetPicture(id)}</span><span>${name}</span></button>`).join('');
$('presets').onclick = event => { const button = event.target.closest('[data-preset]'); if (button) loadPreset(button.dataset.preset); };
$('new-project').onclick = () => loadPreset('blank');
$('duplicate').onclick = duplicateLayer; $('delete-layer').onclick = deleteLayer;
for (const [id, offset] of [['move-up', -1], ['move-down', 1]]) $(id).onclick = () => { const index = project.layers.findIndex(layer => layer.id === selectedId); if (index < 0 || index + offset < 0 || index + offset >= project.layers.length) return; mutate(() => { const [layer] = project.layers.splice(index, 1); project.layers.splice(index + offset, 0, layer); }); renderLayers(); };
$('undo').onclick = () => history('undo'); $('redo').onclick = () => history('redo');
$('project-name').onchange = () => { const name = $('project-name').value.trim(); if (name) mutate(() => { project.name = name; }); renderTitle(); };
$('part-count').onchange = () => { mutate(() => { project.parts = Number($('part-count').value); }); };
$('point-size').oninput = () => { mutate(() => { project.pointSize = Number($('point-size').value); }, 'pointSize'); viewport.setOptions({ pointSize: project.pointSize }); };
$('play-pause').onclick = () => { playing = !playing; updatePlayback(); };
$('restart').onclick = () => { time = 0; dirty = true; };
$('preview-time').onchange = () => { const value = Number($('preview-time').value); if ($('preview-time').value !== '' && Number.isFinite(value)) { time = clamp(value, -3600, 3600); playing = false; dirty = true; updatePlayback(); } $('preview-time').value = format(time); };
for (const [id, amount] of [['frame-back', -1], ['frame-forward', 1]]) $(id).onclick = () => { playing = false; time += amount / 60; dirty = true; updatePlayback(); };
$('playback-speed').onchange = () => { speed = Number($('playback-speed').value); };
$('camera-view').onchange = () => viewport.setView($('camera-view').value);
$('fit-view').onclick = () => viewport.fit();
$('toggle-grid').onclick = () => { grid = !grid; viewport.setOptions({ grid }); $('toggle-grid').classList.toggle('active', grid); $('toggle-grid').setAttribute('aria-pressed', grid); };
$('toggle-axes').onclick = () => { axes = !axes; viewport.setOptions({ axes }); $('toggle-axes').classList.toggle('active', axes); $('toggle-axes').setAttribute('aria-pressed', axes); };
$('toggle-core').onclick = () => { core = !core; viewport.setOptions({ core, coreRadius: 2.5 }); $('toggle-core').classList.toggle('active', core); $('toggle-core').setAttribute('aria-pressed', core); };
$('toggle-move').onclick = () => { moveLayers = !moveLayers; viewport.setOptions({ move: moveLayers }); $('toggle-move').classList.toggle('active', moveLayers); $('toggle-move').setAttribute('aria-pressed', moveLayers); };
$('screenshot').onclick = () => { viewport.render(); $('viewport').toBlob(blob => { if (blob) { download(blob, safeFilename() + '.png', 'image/png'); toast('Preview image downloaded.'); } }, 'image/png'); };
$('save-project').onclick = saveProject; $('import-project').onclick = () => $('project-file').click();
$('project-file').onchange = async () => {
  const file = $('project-file').files[0]; if (!file) return;
  try {
    const imported = await readProjectFile(file);
    soloState = null; layerFilter = ''; $('layer-search').value = '';
    mutate(() => { project = imported; selectedId = project.layers[0]?.id || null; previewValues = Object.create(null); time = 0; });
    renderAll(); viewport.setPoints(sampleProject(project, time)); viewport.fit(); toast(`${project.name} opened. Your previous project is in Undo.`);
  } catch (error) { toast(`Could not open project: ${error.message}`); }
  $('project-file').value = '';
};
$('export').onclick = showExport; $('copy-lua').onclick = copyLua;
$('download-lua').onclick = () => { download($('export-code').value, safeFilename() + '.lua'); toast('Plugin downloaded. Save it in GravityShapes to use it.'); };
for (const id of ['help', 'keyboard-help']) $(id).onclick = () => $('help-dialog').showModal();
document.querySelectorAll('[data-close]').forEach(button => { button.onclick = () => button.closest('dialog').close(); });
document.querySelectorAll('dialog').forEach(dialog => { dialog.addEventListener('click', event => { if (event.target === dialog) { const bounds = dialog.getBoundingClientRect(); if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close(); } }); });
document.addEventListener('keydown', event => {
  if (dragSession) return;
  if (event.target.closest('input,textarea,select,[contenteditable="true"]') || document.querySelector('dialog[open]')) return;
  const command = event.ctrlKey || event.metaKey, key = event.key.toLowerCase();
  if (command && key === 'z') { event.preventDefault(); history(event.shiftKey ? 'redo' : 'undo'); }
  else if (command && key === 'y') { event.preventDefault(); history('redo'); }
  else if (command && key === 'd') { event.preventDefault(); duplicateLayer(); }
  else if (command && key === 's') { event.preventDefault(); saveProject(); }
  else if (!command && key === ' ') { event.preventDefault(); playing = !playing; updatePlayback(); }
  else if (!command && key === 'a') showShapes();
  else if (!command && key === 'f') viewport.fit();
  else if (key === 'delete' || key === 'backspace') { event.preventDefault(); deleteLayer(); }
});
document.addEventListener('visibilitychange', () => { if (document.hidden) persist(); });
window.addEventListener('pagehide', persist);

let lastFrame = performance.now(), lastTimeLabel = -1, lastPointCount = -1;
function frame(now) {
  const delta = Math.min((now - lastFrame) / 1000, 0.06); lastFrame = now;
  if (playing && !document.hidden && !document.querySelector('dialog[open]')) { time += delta * speed; dirty = true; }
  if (dirty) {
    const points = sampleProject(project, time, previewValues); viewport.setPoints(points);
    if (lastPointCount !== points.length) { $('point-count').textContent = `${points.length.toLocaleString()} parts`; $('empty-scene').hidden = points.length > 0; lastPointCount = points.length; }
    if (!points.length) {
      $('empty-scene').querySelector('h2').textContent = project.layers.length ? 'Let your layers be seen.' : 'It starts with a shape.';
      $('empty-scene').querySelector('p').textContent = project.layers.length ? 'Show a layer and give it a positive part weight to see your formation.' : 'A ring, a sphere, or something entirely your own. Add your first layer and see where it goes.';
    }
    dirty = false;
  }
  if (now - lastTimeLabel > 60) {
    const absolute = Math.abs(time); $('time-display').textContent = `${time < 0 ? '−' : ''}${Math.floor(absolute / 60).toString().padStart(2, '0')}:${(absolute % 60).toFixed(2).padStart(5, '0')}`;
    $('timeline-progress').style.width = `${((time % 10 + 10) % 10) * 10}%`; lastTimeLabel = now;
    if (document.activeElement !== $('preview-time')) $('preview-time').value = format(time);
  }
  viewport.render(); requestAnimationFrame(frame);
}
renderAll(); updatePlayback();
viewport.setPoints(sampleProject(project, 0));
// Give the first scene comfortable breathing room between the editor overlays.
requestAnimationFrame(() => { viewport.fit(); requestAnimationFrame(frame); });
if (storageWarning) toast(storageWarning);
else if (restored) $('save-status').textContent = 'Restored your locally saved project';
