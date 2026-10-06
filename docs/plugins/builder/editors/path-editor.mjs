import { flattenPath, MAX_PATH_POINTS, PATH_COORDINATE_LIMIT } from '../geometry/path.mjs';
import { boundedTranslation, flattenVertices, selectionCenter, transformVertices } from '../geometry/vertices.mjs';

const PLANES = { xy: ['x', 'y', 'z'], xz: ['x', 'z', 'y'], yz: ['y', 'z', 'x'] };
const copy = value => JSON.parse(JSON.stringify(value));
const bound = value => Math.max(-PATH_COORDINATE_LIMIT, Math.min(PATH_COORDINATE_LIMIT, value));
const rounded = value => Math.round(value * 10000) / 10000;

/** Opens an isolated draft. Only Apply calls onApply; closing discards edits. */
export function openPathEditor({ path, onApply, minPoints = 2 }) {
  const pointCloud = minPoints === 1;
  const points = (Array.isArray(path?.points) ? path.points : []).slice(0, MAX_PATH_POINTS)
    .filter(point => point && ['x', 'y', 'z'].every(axis => Number.isFinite(point[axis])))
    .map(point => ({ x: bound(point.x), y: bound(point.y), z: bound(point.z) }));
  let draft = { points, closed: !pointCloud && Boolean(path?.closed), smooth: !pointCloud && Boolean(path?.smooth) };
  let selected = points.length - 1;
  let selection = new Set(selected >= 0 ? [selected] : []);
  let mode = points.length > 1 ? 'edit' : 'draw';
  let plane = 'xy';
  let width = 600;
  let height = 420;
  let drag = null;
  let hover = null;
  let alive = true;
  let undoStack = [];
  let redoStack = [];
  const view = { x: 0, y: 0, scale: 1.6 };
  const dialog = document.createElement('dialog');
  dialog.className = 'path-editor';
  dialog.setAttribute('aria-labelledby', 'path-editor-title');
  dialog.innerHTML = `
    <header class="path-editor-header">
      <div><p class="path-editor-eyebrow">CUSTOM GEOMETRY</p><h2 id="path-editor-title">Make your own path</h2></div>
      <button type="button" class="path-editor-close" data-action="cancel" aria-label="Close path editor">&times;</button>
    </header>
    <div class="path-editor-toolbar">
      <div class="path-editor-tools" role="group" aria-label="Drawing tools">
        <button type="button" data-mode="draw" title="Draw connected vertices (D)">Draw</button>
        <button type="button" data-mode="edit" title="Select and move vertices (V)">Move</button>
        <button type="button" data-mode="select" title="Select several vertices (S)">Select</button>
        <button type="button" data-mode="freehand" title="Draw a freehand stroke (F)">Freehand</button>
        <button type="button" data-mode="pan" title="Pan the canvas (H)">Pan</button>
      </div>
      <label class="path-editor-inline">Plane <select data-field="plane" aria-label="Drawing plane"><option value="xy">XY · front</option><option value="xz">XZ · top</option><option value="yz">YZ · side</option></select></label>
      <div class="path-editor-zoom" role="group" aria-label="Canvas view">
        <button type="button" data-action="zoom-out" aria-label="Zoom out">−</button><button type="button" data-action="zoom-in" aria-label="Zoom in">+</button><button type="button" data-action="frame">Fit</button>
      </div>
    </div>
    <p class="path-editor-instructions" id="path-editor-instructions"></p>
    <div class="path-editor-body">
      <div class="path-editor-canvas-wrap">
        <canvas tabindex="0" aria-label="Custom path drawing canvas" aria-describedby="path-editor-instructions path-editor-keyboard"></canvas>
        <span class="path-editor-axes" aria-hidden="true"></span>
        <span class="path-editor-readout" aria-hidden="true"></span>
      </div>
      <aside class="path-editor-properties" aria-label="Path properties">
        <div class="path-editor-property-heading"><h3>Path settings</h3><output data-field="count"></output></div>
        <div class="path-editor-checks"><label><input type="checkbox" data-field="closed"> Closed loop</label><label><input type="checkbox" data-field="smooth"> Smooth curve</label></div>
        <div class="path-editor-snap"><label><input type="checkbox" data-field="snap"> Snap to grid</label><label class="path-editor-inline">Step <input type="number" data-field="step" value="10" min="0.01" max="1000" step="any" aria-label="Grid snapping step"></label></div>
        <label class="path-editor-depth"><span>New point <b data-field="depth-axis">Z</b></span><input type="number" data-field="depth" value="0" min="-5000" max="5000" step="any" aria-label="New point depth"></label>
        <div class="path-editor-selection">
          <div class="path-editor-property-heading"><h3>Selection</h3><output data-field="selection-count" aria-live="polite"></output></div>
          <div class="path-editor-selection-actions"><button type="button" data-action="select-all">All</button><button type="button" data-action="select-none">None</button><button type="button" data-action="select-invert">Invert</button></div>
        </div>
        <div class="path-editor-vertex-heading"><h3>Active vertex</h3><div class="path-editor-vertex-nav"><button type="button" data-action="previous" aria-label="Select previous vertex">‹</button><input type="number" data-field="vertex" min="1" step="1" aria-label="Selected vertex number"><button type="button" data-action="next" aria-label="Select next vertex">›</button></div></div>
        <div class="path-editor-coordinates">${['x', 'y', 'z'].map(axis => `<label>${axis.toUpperCase()}<input type="number" data-coordinate="${axis}" min="-5000" max="5000" step="any" aria-label="Vertex ${axis.toUpperCase()} coordinate"></label>`).join('')}</div>
        <div class="path-editor-node-actions"><button type="button" data-action="insert">Insert vertex</button><button type="button" data-action="delete">Delete vertex</button></div>
        <details class="path-editor-transforms">
          <summary>Transform selection</summary>
          <p class="path-editor-note">Scale, then rotate X → Y → Z around the selection center, then move. Negative scale mirrors; zero flattens.</p>
          <output data-field="selection-center" class="path-editor-center"></output>
          ${[['move', 'Move', 0], ['rotate', 'Rotate °', 0], ['scale', 'Scale ×', 1]].map(([name, label, initial]) => `<fieldset class="path-editor-transform-row"><legend>${label}</legend>${['x', 'y', 'z'].map(axis => `<label>${axis.toUpperCase()}<input type="number" data-transform="${name}.${axis}" value="${initial}" step="any" aria-label="${name === 'rotate' ? 'Rotate' : name === 'scale' ? 'Scale' : 'Move'} selection ${axis.toUpperCase()}"></label>`).join('')}</fieldset>`).join('')}
          <button type="button" data-action="transform-selection">Transform selected</button>
          <div class="path-editor-flatten"><label>Axis<select data-field="flatten-axis" aria-label="Flatten selection axis"><option value="x">X</option><option value="y">Y</option><option value="z" selected>Z</option></select></label><label>Coordinate<input type="number" data-field="flatten-value" value="0" min="-5000" max="5000" step="any" aria-label="Flatten selection coordinate"></label></div>
          <button type="button" data-action="flatten-selection">Set selected to coordinate</button>
        </details>
        <p class="path-editor-note">Insert adds a midpoint after the selected vertex. Change planes or enter coordinates to draw in 3D. Cross edges and combine layers to build complex shapes.</p>
        <p class="path-editor-note" id="path-editor-keyboard">Canvas: Shift-click toggles selection. Arrows move selected vertices; Shift moves 10×. Delete removes selected vertices. D / V / S / F / H switch tools. Ctrl or ⌘ A selects all; Z undoes.</p>
      </aside>
    </div>
    <footer class="path-editor-footer">
      <div class="path-editor-history"><button type="button" data-action="undo">Undo</button><button type="button" data-action="redo">Redo</button><button type="button" data-action="remove-last">Remove last</button><button type="button" data-action="clear">Clear</button></div>
      <p class="path-editor-status" role="status" aria-live="polite"></p>
      <div class="path-editor-final-actions"><button type="button" data-action="cancel">Cancel</button><button type="button" class="path-editor-apply" data-action="apply">Apply path</button></div>
    </footer>`;
  document.body.append(dialog);
  const $ = selector => dialog.querySelector(selector);
  const field = name => $(`[data-field="${name}"]`);
  const action = name => $(`[data-action="${name}"]`);
  const canvas = $('canvas');
  const ctx = canvas.getContext('2d');
  if (pointCloud) {
    $('#path-editor-title').textContent = 'Shape your point cloud';
    $('.path-editor-checks').hidden = true;
    action('apply').textContent = 'Apply points';
    $('.path-editor-properties > .path-editor-note').textContent = 'Each vertex is a separate point. Change planes or enter coordinates to arrange your points in 3D.';
  }
  const selectOnly = index => { selected = index; selection = new Set(index >= 0 ? [index] : []); };
  const state = () => ({ draft: copy(draft), selected, selection: [...selection] });
  const restore = snapshot => { draft = copy(snapshot.draft); selected = snapshot.selected; selection = new Set(snapshot.selection); refresh(); };
  const remember = snapshot => { undoStack.push(snapshot); if (undoStack.length > 80) undoStack.shift(); redoStack = []; };
  const change = fn => { remember(state()); fn(); refresh(); };
  const axes = () => PLANES[plane];
  const pixel = point => ({ x: width / 2 + (point[axes()[0]] - view.x) * view.scale, y: height / 2 - (point[axes()[1]] - view.y) * view.scale });
  const world = point => ({ x: view.x + (point.x - width / 2) / view.scale, y: view.y - (point.y - height / 2) / view.scale });
  const step = () => Math.max(0.01, Math.min(1000, Number(field('step').value) || 10));
  const snap = value => rounded(bound(field('snap').checked ? Math.round(value / step()) * step() : value));
  const pointer = event => { const rect = canvas.getBoundingClientRect(); return { x: event.clientX - rect.left, y: event.clientY - rect.top }; };
  const hit = (position, radius = 13) => {
    let closest = -1;
    let distance = radius * radius;
    draft.points.forEach((point, index) => { const p = pixel(point); const d = (p.x - position.x) ** 2 + (p.y - position.y) ** 2; if (d <= distance) { closest = index; distance = d; } });
    return closest;
  };
  const report = message => { $('.path-editor-status').textContent = message; };
  const setMode = next => { mode = next; hover = null; refresh(); };
  function refresh() {
    if (!alive) return;
    selection = new Set([...selection].filter(index => index >= 0 && index < draft.points.length));
    if (!selection.has(selected)) selected = [...selection].at(-1) ?? -1;
    dialog.querySelectorAll('[data-mode]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.mode === mode)));
    canvas.dataset.mode = mode;
    field('closed').checked = draft.closed;
    field('smooth').checked = draft.smooth;
    field('count').textContent = `${draft.points.length.toLocaleString()} vertices`;
    field('selection-count').textContent = `${selection.size.toLocaleString()} selected`;
    field('selection-center').textContent = selection.size ? `Center: ${Object.entries(selectionCenter(draft.points, selection)).map(([axis, value]) => `${axis.toUpperCase()} ${rounded(value)}`).join(' · ')}` : 'Select vertices to transform.';
    field('vertex').value = selected >= 0 ? selected + 1 : '';
    field('vertex').max = draft.points.length;
    field('vertex').disabled = selected < 0;
    dialog.querySelectorAll('[data-coordinate]').forEach(input => { input.disabled = selected < 0; input.value = selected < 0 ? '' : rounded(draft.points[selected][input.dataset.coordinate]); });
    action('delete').disabled = !selection.size;
    action('delete').textContent = selection.size > 1 ? 'Delete selected' : 'Delete vertex';
    ['previous', 'next', 'select-all', 'select-invert'].forEach(name => { action(name).disabled = !draft.points.length; });
    ['select-none', 'transform-selection', 'flatten-selection'].forEach(name => { action(name).disabled = !selection.size; });
    action('remove-last').disabled = !draft.points.length;
    action('clear').disabled = !draft.points.length;
    action('insert').disabled = draft.points.length >= MAX_PATH_POINTS;
    action('insert').textContent = draft.points.length ? 'Insert vertex' : 'Add first vertex';
    action('undo').disabled = !undoStack.length;
    action('redo').disabled = !redoStack.length;
    action('apply').disabled = draft.points.length < minPoints;
    $('.path-editor-instructions').textContent = {
      draw: pointCloud ? 'Click or tap to place separate points. Switch planes to arrange them in 3D.' : 'Click or tap to connect vertices. Click the first vertex to close your outline. Crossings are welcome.',
      edit: 'Drag a selected vertex to move the selection. Shift-click toggles vertices. Select a vertex to edit its exact coordinates.',
      select: 'Tap vertices to add or remove them from the selection. Drag empty space to select a box. Switch to Move to drag the selection.',
      freehand: pointCloud ? 'Drag to place points along a stroke. Undo removes the entire stroke.' : 'Drag to sketch a connected stroke. Enable Smooth curve for flowing lines; Undo removes the stroke.',
      pan: 'Drag to move the canvas. Scroll to zoom, or use + / −. Fit brings the whole path into view.'
    }[mode];
    field('depth-axis').textContent = axes()[2].toUpperCase();
    field('depth').setAttribute('aria-label', `New point ${axes()[2].toUpperCase()} coordinate`);
    $('.path-editor-axes').textContent = `${axes()[0].toUpperCase()} →   ${axes()[1].toUpperCase()} ↑`;
    report(draft.points.length < minPoints ? `Add at least ${minPoints} ${minPoints === 1 ? 'vertex' : 'vertices'} to apply.` : 'Changes stay in this draft until you apply.');
    render();
  }
  function drawPolyline(points, close = false) {
    if (!points.length) return;
    ctx.beginPath();
    points.forEach((point, index) => { const p = pixel(point); if (index) ctx.lineTo(p.x, p.y); else ctx.moveTo(p.x, p.y); });
    if (close) ctx.closePath();
  }
  function render() {
    if (!alive) return;
    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = '#141814'; ctx.fillRect(0, 0, width, height);
    const target = 55 / view.scale;
    const magnitude = 10 ** Math.floor(Math.log10(target));
    const automaticGrid = [1, 2, 5, 10].map(n => n * magnitude).find(n => n >= target);
    const grid = field('snap').checked && step() * view.scale >= 8 ? step() : automaticGrid;
    const left = world({ x: 0, y: 0 }).x;
    const right = world({ x: width, y: 0 }).x;
    const bottom = world({ x: 0, y: height }).y;
    const top = world({ x: 0, y: 0 }).y;
    ctx.strokeStyle = '#262e23'; ctx.lineWidth = 1;
    ctx.beginPath();
    for (let x = Math.ceil(left / grid) * grid; x <= right; x += grid) { const px = width / 2 + (x - view.x) * view.scale; ctx.moveTo(px, 0); ctx.lineTo(px, height); }
    for (let y = Math.ceil(bottom / grid) * grid; y <= top; y += grid) { const py = height / 2 - (y - view.y) * view.scale; ctx.moveTo(0, py); ctx.lineTo(width, py); }
    ctx.stroke();
    const zero = { x: width / 2 - view.x * view.scale, y: height / 2 + view.y * view.scale };
    ctx.strokeStyle = '#45533c'; ctx.beginPath(); ctx.moveTo(zero.x, 0); ctx.lineTo(zero.x, height); ctx.moveTo(0, zero.y); ctx.lineTo(width, zero.y); ctx.stroke();
    if (!pointCloud && draft.points.length > 1) {
      if (draft.smooth) { drawPolyline(draft.points, draft.closed); ctx.setLineDash([4, 5]); ctx.strokeStyle = '#60714e'; ctx.lineWidth = 1; ctx.stroke(); ctx.setLineDash([]); }
      drawPolyline(flattenPath(draft), draft.closed);
      if (draft.closed) { ctx.fillStyle = '#d4ef9d0b'; ctx.fill('evenodd'); }
      ctx.strokeStyle = '#d4ef9d'; ctx.lineWidth = 2.5; ctx.lineJoin = 'round'; ctx.lineCap = 'round'; ctx.stroke();
    }
    if (!pointCloud && mode === 'draw' && hover && draft.points.length && !drag) {
      const last = pixel(draft.points[draft.points.length - 1]);
      const end = hit(hover) === 0 && draft.points.length >= 3 ? pixel(draft.points[0]) : hover;
      ctx.setLineDash([4, 5]); ctx.strokeStyle = '#a1b681'; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.moveTo(last.x, last.y); ctx.lineTo(end.x, end.y); ctx.stroke(); ctx.setLineDash([]);
    }
    draft.points.forEach((point, index) => {
      const p = pixel(point);
      if (p.x < -20 || p.x > width + 20 || p.y < -20 || p.y > height + 20) return;
      const active = selected === index, chosen = selection.has(index);
      ctx.beginPath(); ctx.arc(p.x, p.y, active ? 6 : chosen ? 5 : draft.points.length > 180 ? 2.4 : 4, 0, Math.PI * 2);
      ctx.fillStyle = chosen ? '#d4ef9d' : '#202b1c'; ctx.fill(); ctx.strokeStyle = active ? '#f3ffe2' : '#afc58e'; ctx.lineWidth = active ? 2 : 1.2; ctx.stroke();
    });
    if (drag?.type === 'select') {
      const x = Math.min(drag.position.x, drag.current.x), y = Math.min(drag.position.y, drag.current.y);
      const w = Math.abs(drag.current.x - drag.position.x), h = Math.abs(drag.current.y - drag.position.y);
      ctx.fillStyle = '#d4ef9d16'; ctx.fillRect(x, y, w, h);
      ctx.strokeStyle = '#d4ef9d'; ctx.lineWidth = 1; ctx.setLineDash([5, 4]); ctx.strokeRect(x, y, w, h); ctx.setLineDash([]);
    }
    if (!pointCloud && draft.points.length) {
      const first = pixel(draft.points[0]);
      const closing = mode === 'draw' && draft.points.length >= 3 && hover && hit(hover) === 0;
      ctx.beginPath(); ctx.arc(first.x, first.y, closing ? 13 : 9, 0, Math.PI * 2); ctx.strokeStyle = closing ? '#efffda' : '#8eab6d'; ctx.lineWidth = 1; ctx.stroke();
      ctx.font = '9px ui-monospace, monospace'; ctx.fillStyle = '#b7caa1';
      ctx.fillText(closing ? 'CLOSE' : 'START', first.x + 13, first.y - 10);
      if (!draft.closed && draft.points.length > 1) { const last = pixel(draft.points[draft.points.length - 1]); ctx.fillText('END', last.x + 10, last.y + 16); }
    } else if (!draft.points.length) {
      ctx.textAlign = 'center'; ctx.fillStyle = '#d7e1cc'; ctx.font = '500 16px system-ui, sans-serif';
      ctx.fillText('Your next shape starts here', width / 2, height / 2 - 20);
      ctx.fillStyle = '#95a28a'; ctx.font = '12px system-ui, sans-serif';
      ctx.fillText('Draw vertices or sketch with Freehand.', width / 2, height / 2 + 5); ctx.textAlign = 'left';
    }
    $('.path-editor-readout').textContent = `Grid ${rounded(grid)} · ${Math.round(view.scale * 100)}%`;
  }
  function fit() {
    const [horizontal, vertical] = axes();
    if (!draft.points.length) { view.x = 0; view.y = 0; view.scale = Math.min(width, height) / 240; render(); return; }
    const xs = draft.points.map(point => point[horizontal]);
    const ys = draft.points.map(point => point[vertical]);
    const lowX = Math.min(...xs), highX = Math.max(...xs), lowY = Math.min(...ys), highY = Math.max(...ys);
    view.x = (lowX + highX) / 2; view.y = (lowY + highY) / 2;
    view.scale = Math.max(0.025, Math.min(250, (width - 86) / Math.max(60, highX - lowX), (height - 86) / Math.max(60, highY - lowY)));
    render();
  }
  function zoom(factor, at = { x: width / 2, y: height / 2 }) {
    const before = world(at);
    view.scale = Math.max(0.025, Math.min(250, view.scale * factor));
    const after = world(at); view.x += before.x - after.x; view.y += before.y - after.y;
    render();
  }
  function addAt(position) {
    if (draft.points.length >= MAX_PATH_POINTS) { report(`Maximum ${MAX_PATH_POINTS.toLocaleString()} vertices. Delete some vertices to continue.`); return false; }
    const location = world(position);
    const [horizontal, vertical, depth] = axes();
    const point = { [horizontal]: snap(location.x), [vertical]: snap(location.y), [depth]: bound(Number(field('depth').value) || 0) };
    const last = draft.points.at(-1);
    if (last && ['x', 'y', 'z'].every(axis => point[axis] === last[axis])) return false;
    draft.points.push(point); selectOnly(draft.points.length - 1); return true;
  }
  function finishPointer(event, cancelled = false) {
    if (!drag || event.pointerId !== drag.id) return;
    const previous = drag;
    drag = null;
    if (cancelled && previous.before) { draft = previous.before.draft; selected = previous.before.selected; selection = new Set(previous.before.selection); }
    else if (previous.type === 'select') {
      const lowX = Math.min(previous.position.x, previous.current.x), highX = Math.max(previous.position.x, previous.current.x);
      const lowY = Math.min(previous.position.y, previous.current.y), highY = Math.max(previous.position.y, previous.current.y);
      selection = new Set(previous.additive ? previous.before.selection : []);
      draft.points.forEach((point, index) => { const p = pixel(point); if (p.x >= lowX && p.x <= highX && p.y >= lowY && p.y <= highY) selection.add(index); });
      selected = [...selection].at(-1) ?? -1;
    }
    else if (previous.before && JSON.stringify(draft) !== JSON.stringify(previous.before.draft)) remember(previous.before);
    if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    refresh();
  }
  canvas.addEventListener('pointerdown', event => {
    if (event.button !== 0 && event.button !== 1) return;
    if (drag) return;
    event.preventDefault(); canvas.focus({ preventScroll: true });
    const position = pointer(event);
    if (mode === 'pan' || event.button === 1) { drag = { id: event.pointerId, type: 'pan', position, view: { ...view } }; }
    else if (mode === 'edit' || mode === 'select') {
      const index = hit(position, event.pointerType === 'touch' ? 22 : 13);
      if (index >= 0 && (event.shiftKey || mode === 'select')) {
        if (selection.has(index)) { selection.delete(index); selected = [...selection].at(-1) ?? -1; }
        else { selection.add(index); selected = index; }
      } else if (index >= 0) {
        if (!selection.has(index)) selectOnly(index);
        selected = index;
        drag = { id: event.pointerId, type: 'edit', position, point: { ...draft.points[index] }, before: state() };
      } else if (mode === 'select') {
        drag = { id: event.pointerId, type: 'select', position, current: position, additive: event.shiftKey, before: state() };
      } else if (!event.shiftKey) selectOnly(-1);
      refresh();
    } else if (mode === 'freehand') {
      drag = { id: event.pointerId, type: 'freehand', position, before: state() };
      draft.closed = false; addAt(position); refresh();
    } else {
      if (!pointCloud && draft.points.length >= 3 && hit(position, event.pointerType === 'touch' ? 22 : 13) === 0) change(() => { draft.closed = true; mode = 'edit'; selectOnly(0); });
      else if (draft.points.length < MAX_PATH_POINTS) {
        const before = state();
        if (addAt(position)) { remember(before); refresh(); }
      } else report(`Maximum ${MAX_PATH_POINTS.toLocaleString()} vertices. Delete some vertices to continue.`);
    }
    if (drag) canvas.setPointerCapture(event.pointerId);
  });
  canvas.addEventListener('pointermove', event => {
    const position = pointer(event); hover = position;
    if (!drag) { if (mode === 'draw') render(); return; }
    if (drag.id !== event.pointerId) return;
    if (drag.type === 'pan') { view.x = drag.view.x - (position.x - drag.position.x) / view.scale; view.y = drag.view.y + (position.y - drag.position.y) / view.scale; render(); }
    else if (drag.type === 'select') { drag.current = position; render(); }
    else if (drag.type === 'edit') {
      const [horizontal, vertical] = axes();
      const translation = boundedTranslation(drag.before.draft.points, drag.before.selection, {
        [horizontal]: snap(drag.point[horizontal] + (position.x - drag.position.x) / view.scale) - drag.point[horizontal],
        [vertical]: snap(drag.point[vertical] - (position.y - drag.position.y) / view.scale) - drag.point[vertical]
      });
      draft.points = transformVertices(drag.before.draft.points, drag.before.selection, { translation });
      refresh();
    } else if (Math.hypot(position.x - drag.position.x, position.y - drag.position.y) >= 5) {
      if (addAt(position)) { drag.position = position; refresh(); }
    }
  });
  canvas.addEventListener('pointerup', event => {
    if (drag?.type === 'freehand' && drag.id === event.pointerId) addAt(pointer(event));
    finishPointer(event);
  });
  canvas.addEventListener('pointercancel', event => finishPointer(event, true));
  canvas.addEventListener('lostpointercapture', event => finishPointer(event));
  canvas.addEventListener('pointerleave', () => { hover = null; render(); });
  canvas.addEventListener('wheel', event => { event.preventDefault(); if (!drag) zoom(Math.exp(-event.deltaY * 0.0015), pointer(event)); }, { passive: false });
  canvas.addEventListener('contextmenu', event => event.preventDefault());

  function insert() {
    if (draft.points.length >= MAX_PATH_POINTS) return;
    change(() => {
      const current = draft.points[selected];
      let point = { x: 0, y: 0, z: 0 };
      if (current) {
        const next = draft.points[selected + 1] || (draft.closed ? draft.points[0] : null);
        point = next ? Object.fromEntries(['x', 'y', 'z'].map(axis => [axis, rounded((current[axis] + next[axis]) / 2)])) : { ...current, [axes()[0]]: bound(current[axes()[0]] + step()) };
      }
      const index = selected + 1; draft.points.splice(index, 0, point); selectOnly(index); mode = 'edit';
    });
  }
  function remove() {
    if (selection.size) change(() => {
      const first = Math.min(...selection);
      draft.points = draft.points.filter((_, index) => !selection.has(index));
      selectOnly(Math.min(first, draft.points.length - 1));
    });
  }
  function updateSelection(fn) {
    if (!selection.size) return;
    try {
      const next = fn();
      if (JSON.stringify(next) !== JSON.stringify(draft.points)) change(() => { draft.points = next; });
      else report('The selected vertices already match this transform.');
    } catch (error) { report(error.message); }
  }
  function transformSelection() {
    updateSelection(() => {
      const options = {};
      for (const [name, key] of [['move', 'translation'], ['rotate', 'rotation'], ['scale', 'scale']]) {
        options[key] = {};
        for (const axis of ['x', 'y', 'z']) {
          const input = $(`[data-transform="${name}.${axis}"]`);
          if (!input.value.trim() || !Number.isFinite(Number(input.value))) throw new Error('Enter finite numbers for every transform coordinate.');
          options[key][axis] = Number(input.value);
        }
      }
      return transformVertices(draft.points, selection, options);
    });
  }
  function undo() { if (undoStack.length) { redoStack.push(state()); restore(undoStack.pop()); } }
  function redo() { if (redoStack.length) { undoStack.push(state()); restore(redoStack.pop()); } }
  dialog.addEventListener('click', event => {
    const button = event.target.closest('button');
    if (!button || drag) return;
    if (button.dataset.mode) { setMode(button.dataset.mode); return; }
    switch (button.dataset.action) {
      case 'cancel': dialog.close(); break;
      case 'apply': if (draft.points.length >= minPoints) { onApply(copy(draft)); dialog.close(); } break;
      case 'frame': fit(); break;
      case 'zoom-in': zoom(1.35); break;
      case 'zoom-out': zoom(1 / 1.35); break;
      case 'previous': selectOnly(selected < 0 ? draft.points.length - 1 : (selected - 1 + draft.points.length) % draft.points.length); refresh(); break;
      case 'next': selectOnly((selected + 1) % draft.points.length); refresh(); break;
      case 'select-all': selection = new Set(draft.points.map((_, index) => index)); refresh(); break;
      case 'select-none': selectOnly(-1); refresh(); break;
      case 'select-invert': selection = new Set(draft.points.map((_, index) => index).filter(index => !selection.has(index))); refresh(); break;
      case 'transform-selection': transformSelection(); break;
      case 'flatten-selection': updateSelection(() => {
        if (!field('flatten-value').value.trim()) throw new Error('Enter a finite coordinate.');
        return flattenVertices(draft.points, selection, field('flatten-axis').value, Number(field('flatten-value').value));
      }); break;
      case 'insert': insert(); break;
      case 'delete': remove(); break;
      case 'remove-last': if (draft.points.length) change(() => { draft.points.pop(); selection.delete(draft.points.length); if (!selection.size) selectOnly(draft.points.length - 1); }); break;
      case 'clear': if (draft.points.length) change(() => { draft.points = []; selectOnly(-1); mode = 'draw'; }); break;
      case 'undo': undo(); break;
      case 'redo': redo(); break;
    }
  });
  field('plane').addEventListener('change', event => {
    plane = event.target.value; field('depth').value = selected >= 0 ? rounded(draft.points[selected][axes()[2]]) : 0; refresh(); fit();
  });
  ['closed', 'smooth'].forEach(name => field(name).addEventListener('change', event => change(() => { draft[name] = event.target.checked; })));
  field('snap').addEventListener('change', render);
  field('step').addEventListener('change', () => { field('step').value = step(); render(); });
  field('depth').addEventListener('change', () => { field('depth').value = bound(Number(field('depth').value) || 0); });
  field('vertex').addEventListener('change', event => { selectOnly(Math.max(0, Math.min(draft.points.length - 1, (Math.round(Number(event.target.value)) || 1) - 1))); refresh(); });
  dialog.querySelectorAll('[data-coordinate]').forEach(input => input.addEventListener('change', () => {
    const value = Number(input.value);
    if (selected < 0 || !input.value.trim() || !Number.isFinite(value)) { refresh(); report('Enter a finite coordinate between −5000 and 5000.'); return; }
    const next = rounded(bound(value));
    if (draft.points[selected][input.dataset.coordinate] !== next) change(() => { draft.points[selected][input.dataset.coordinate] = next; });
    else refresh();
  }));
  dialog.addEventListener('keydown', event => {
    // Keep editor shortcuts local; the scene underneath has its own shortcuts.
    event.stopPropagation();
    const editing = event.target.matches('input, textarea, select');
    if (editing || drag) return;
    const key = event.key.toLowerCase();
    if ((event.ctrlKey || event.metaKey) && key === 'z') { event.preventDefault(); if (event.shiftKey) redo(); else undo(); return; }
    if ((event.ctrlKey || event.metaKey) && key === 'y') { event.preventDefault(); redo(); return; }
    if ((event.ctrlKey || event.metaKey) && key === 'a') { event.preventDefault(); selection = new Set(draft.points.map((_, index) => index)); refresh(); return; }
    if (event.ctrlKey || event.metaKey || event.altKey) return;
    if ({ d: 'draw', v: 'edit', s: 'select', f: 'freehand', h: 'pan' }[key]) { event.preventDefault(); setMode({ d: 'draw', v: 'edit', s: 'select', f: 'freehand', h: 'pan' }[key]); return; }
    if (event.target !== canvas) return;
    if (key === 'delete' || key === 'backspace') { event.preventDefault(); remove(); }
    if (key === 'insert') { event.preventDefault(); insert(); }
    if (key === '+' || key === '=') { event.preventDefault(); zoom(1.35); }
    if (key === '-') { event.preventDefault(); zoom(1 / 1.35); }
    if (key === '0') { event.preventDefault(); fit(); }
    if (!pointCloud && key === 'enter' && mode === 'draw' && draft.points.length >= 3) { event.preventDefault(); change(() => { draft.closed = true; mode = 'edit'; }); }
    const movements = { arrowleft: [0, -1], arrowright: [0, 1], arrowup: [1, 1], arrowdown: [1, -1] };
    if (movements[key] && selected >= 0) {
      event.preventDefault(); const [axisIndex, direction] = movements[key]; const axis = axes()[axisIndex];
      const translation = boundedTranslation(draft.points, selection, { [axis]: direction * (field('snap').checked ? step() : 1) * (event.shiftKey ? 10 : 1) });
      updateSelection(() => transformVertices(draft.points, selection, { translation }));
    }
  });
  const resize = new ResizeObserver(() => {
    const rect = canvas.getBoundingClientRect();
    if (!rect.width || !rect.height) return;
    width = rect.width; height = rect.height;
    const ratio = Math.min(2, window.devicePixelRatio || 1);
    canvas.width = Math.round(width * ratio); canvas.height = Math.round(height * ratio); ctx.setTransform(ratio, 0, 0, ratio, 0, 0); render();
  });
  dialog.addEventListener('close', () => { alive = false; resize.disconnect(); dialog.remove(); }, { once: true });
  dialog.showModal(); resize.observe(canvas); refresh();
  requestAnimationFrame(() => { if (alive) { const rect = canvas.getBoundingClientRect(); width = rect.width; height = rect.height; fit(); canvas.focus({ preventScroll: true }); } });
  return dialog;
}
