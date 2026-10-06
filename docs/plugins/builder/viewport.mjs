/** Dependency-free, high DPI formation viewport. World coordinates use Y up. */
const TAU = Math.PI * 2;
const DEFAULT_DISTANCE = 170;
const HALF_FOV = Math.PI / 8;
const NEAR_CLIP = 0.5;
const MAX_DISTANCE = 10_000_000;
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
const dot = (a, b) => a.x * b.x + a.y * b.y + a.z * b.z;
const subtract = (a, b) => ({ x: a.x - b.x, y: a.y - b.y, z: a.z - b.z });
const AXES = Object.freeze({ x: { x: 1, y: 0, z: 0 }, y: { x: 0, y: 1, z: 0 }, z: { x: 0, y: 0, z: 1 } });

export class Viewport {
  constructor(canvas, { onSelect, onCameraChange, onMoveStart, onMove, onMoveEnd } = {}) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d', { alpha: false });
    this.onSelect = onSelect;
    this.onCameraChange = onCameraChange;
    this.onMoveStart = onMoveStart;
    this.onMove = onMove;
    this.onMoveEnd = onMoveEnd;
    this.points = [];
    this.selected = null;
    this.anchor = null;
    this.options = { grid: true, axes: true, pointSize: 3.4, core: true, coreRadius: 2.5, move: true, snap: 0 };
    this.target = { x: 0, y: 20, z: 0 };
    this.yaw = 0.66;
    this.pitch = 0.43;
    this.distance = DEFAULT_DISTANCE;
    this.view = 'perspective';
    this.width = 1;
    this.height = 1;
    this.dpr = 1;
    this._dirty = true;
    this._projected = [];
    this._gizmoHandles = [];
    this._moveDrag = null;
    this._hoverAxis = null;
    this._colors = new Map();
    this._pointers = new Map();
    this._listeners = [];
    this._oldTouchAction = canvas.style.touchAction;
    this._oldCursor = canvas.style.cursor;
    canvas.style.touchAction = 'none';
    canvas.style.cursor = 'grab';
    this._listen('pointerdown', this._pointerDown.bind(this));
    this._listen('pointermove', this._pointerMove.bind(this));
    this._listen('pointerup', this._pointerUp.bind(this));
    this._listen('pointercancel', this._pointerCancel.bind(this));
    this._listen('lostpointercapture', this._pointerCancel.bind(this));
    this._listen('contextmenu', (event) => event.preventDefault());
    this._listen('wheel', this._wheel.bind(this), { passive: false });
    this._listen('keydown', this._keyDown.bind(this));
    this._windowBlur = () => this._cancelPointers();
    this._visibilityChange = () => { if (document.hidden) this._cancelPointers(); };
    window.addEventListener('blur', this._windowBlur);
    document.addEventListener('visibilitychange', this._visibilityChange);
    this._resizeObserver = new ResizeObserver(() => this._resize());
    this._resizeObserver.observe(canvas);
    this._resize();
  }

  get zoom() { return Math.round(DEFAULT_DISTANCE / this.distance * 100); }

  setPoints(points) {
    this.points = Array.isArray(points) ? points : [];
    this._dirty = true;
  }

  setSelected(id) {
    if (this.selected === id) return;
    if (this._moveDrag && this._moveDrag.layerId !== id) this._finishMove(true);
    this.selected = id;
    this.anchor = null;
    this._dirty = true;
  }

  /** The selected layer's world-space position, independent of sampled geometry. */
  setAnchor(position) {
    const next = this._validPoint(position) ? { x: position.x, y: position.y, z: position.z } : null;
    if (next && this.anchor && next.x === this.anchor.x && next.y === this.anchor.y && next.z === this.anchor.z) return;
    if (!next && !this.anchor) return;
    this.anchor = next;
    this._dirty = true;
  }

  setOptions(options = {}) {
    Object.assign(this.options, options);
    this.options.pointSize = clamp(Number(this.options.pointSize) || 3.4, 0.25, 20);
    this.options.coreRadius = clamp(Number(this.options.coreRadius) || 2.5, 0.05, 10000);
    if (!this.options.move && this._moveDrag) this._finishMove(true);
    this._dirty = true;
  }

  setView(view) {
    if (!['perspective', 'front', 'top', 'right'].includes(view)) return;
    this._cancelPointers();
    this.view = view;
    const angles = {
      perspective: [0.66, 0.43],
      front: [0, 0],
      top: [0, Math.PI / 2],
      right: [Math.PI / 2, 0],
    };
    [this.yaw, this.pitch] = angles[view];
    this._cameraChanged();
  }

  /** With no arguments, include the preview core. Explicit subsets focus only those points. */
  fit(points = this.points) {
    this._cancelPointers();
    let bounds = this._bounds(points);
    if (!arguments.length && this.options.core) {
      const radius = this.options.coreRadius;
      bounds ||= { min: { x: -radius, y: -radius, z: -radius }, max: { x: radius, y: radius, z: radius } };
      for (const axis of ['x', 'y', 'z']) {
        bounds.min[axis] = Math.min(bounds.min[axis], -radius);
        bounds.max[axis] = Math.max(bounds.max[axis], radius);
      }
    }
    if (!bounds) {
      this.target = { x: 0, y: 20, z: 0 };
      this.distance = DEFAULT_DISTANCE;
      this._cameraChanged();
      return;
    }
    this.target = {
      x: (bounds.min.x + bounds.max.x) / 2,
      y: (bounds.min.y + bounds.max.y) / 2,
      z: (bounds.min.z + bounds.max.z) / 2,
    };
    this._basis();
    const tanY = Math.tan(HALF_FOV);
    const tanX = tanY * this.width / this.height;
    let distance = 18;
    for (const corner of this._corners(bounds)) {
      const p = this._cameraPoint(corner);
      const outward = this.distance - p.depth;
      const margin = this.view === 'perspective' ? outward : 0;
      distance = Math.max(distance, Math.abs(p.x) / tanX + margin, Math.abs(p.y) / tanY + margin);
    }
    this.distance = clamp(distance * 1.28, 18, MAX_DISTANCE);
    this._cameraChanged();
  }

  render() {
    if (!this._dirty || !this.ctx || this._destroyed) return;
    this._dirty = false;
    this._basis();
    const ctx = this.ctx;
    const width = this.width;
    const height = this.height;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.globalAlpha = 1;
    ctx.lineWidth = 1;
    ctx.setLineDash([]);

    const background = ctx.createLinearGradient(0, 0, width * 0.3, height);
    background.addColorStop(0, '#171e14');
    background.addColorStop(0.6, '#121910');
    background.addColorStop(1, '#10150e');
    ctx.fillStyle = background;
    ctx.fillRect(0, 0, width, height);
    const atmosphere = ctx.createRadialGradient(width * 0.53, height * 0.43, 0, width * 0.53, height * 0.43, Math.max(width, height) * 0.65);
    atmosphere.addColorStop(0, 'rgba(79, 91, 56, 0.12)');
    atmosphere.addColorStop(1, 'rgba(0, 0, 0, 0)');
    ctx.fillStyle = atmosphere;
    ctx.fillRect(0, 0, width, height);

    if (this.options.grid) this._drawGrid();
    if (this.options.axes) this._drawAxes();

    const projected = [];
    const selectedPoints = [];
    const hasSelection = this.selected !== null && this.selected !== undefined;
    for (let index = 0; index < this.points.length; index++) {
      const point = this.points[index];
      if (!this._validPoint(point)) continue;
      if (hasSelection && point.layerId === this.selected) selectedPoints.push(point);
      const screen = this._project(point);
      if (!screen || screen.x < -20 || screen.x > width + 20 || screen.y < -20 || screen.y > height + 20) continue;
      projected.push({ ...screen, point, index });
    }
    projected.sort((a, b) => b.depth - a.depth || a.index - b.index);
    this._projected = projected;

    const selectedBounds = selectedPoints.length ? this._bounds(selectedPoints) : null;
    if (selectedBounds) this._drawBounds(selectedBounds);
    const core = this.options.core ? this._coreItem() : null;
    if (core && this.anchor) this._drawCoreGuide(core);

    // A soft, square halo keeps the formation's individual blocks legible.
    if (hasSelection && selectedPoints.length < 6000) {
      ctx.globalAlpha = 0.055;
      for (const item of projected) {
        if (item.point.layerId !== this.selected) continue;
        const size = this._pointSize(item) + 3;
        ctx.fillStyle = this._color(item.point.color).light;
        ctx.fillRect(item.x - size / 2, item.y - size / 2, size, size);
      }
    }

    // The core is a preview reference, never a formation sample or pick target.
    // Insert it among the depth-sorted debris so foreground parts occlude it.
    const scene = core ? projected.slice() : projected;
    if (core) {
      const index = scene.findIndex(item => item.depth <= core.depth);
      scene.splice(index < 0 ? scene.length : index, 0, core);
    }
    for (const item of scene) {
      if (item.kind === 'core') {
        ctx.globalAlpha = 1;
        this._drawCore(item);
        continue;
      }
      const selected = !hasSelection || item.point.layerId === this.selected;
      const fog = clamp(1 - (item.depth - this.distance) / (this.distance * 2.2), 0.35, 1);
      ctx.globalAlpha = fog * (selected ? 0.96 : 0.49);
      this._drawBlock(item.x, item.y, this._pointSize(item), this._color(item.point.color));
    }
    ctx.globalAlpha = 1;
    if (core) this._drawCoreLabel(core);
    this._gizmoHandles = [];
    this._gizmoCenter = null;
    if (this.options.move && hasSelection && this.anchor) this._drawGizmo();
    if (this.options.axes) this._drawCompass();
  }

  destroy() {
    this._cancelPointers();
    this._destroyed = true;
    this._resizeObserver.disconnect();
    for (const [type, listener, options] of this._listeners) this.canvas.removeEventListener(type, listener, options);
    window.removeEventListener('blur', this._windowBlur);
    document.removeEventListener('visibilitychange', this._visibilityChange);
    this.canvas.style.touchAction = this._oldTouchAction;
    this.canvas.style.cursor = this._oldCursor;
    this._pointers.clear();
    this._colors.clear();
  }

  _listen(type, listener, options) {
    this.canvas.addEventListener(type, listener, options);
    this._listeners.push([type, listener, options]);
  }

  _resize() {
    const bounds = this.canvas.getBoundingClientRect();
    this.width = Math.max(1, bounds.width);
    this.height = Math.max(1, bounds.height);
    this.dpr = Math.min(2, window.devicePixelRatio || 1);
    this.canvas.width = Math.round(this.width * this.dpr);
    this.canvas.height = Math.round(this.height * this.dpr);
    this._dirty = true;
    this.render();
  }

  _basis() {
    const sinYaw = Math.sin(this.yaw);
    const cosYaw = Math.cos(this.yaw);
    const sinPitch = Math.sin(this.pitch);
    const cosPitch = Math.cos(this.pitch);
    this._right = { x: cosYaw, y: 0, z: -sinYaw };
    this._up = { x: -sinYaw * sinPitch, y: cosPitch, z: -cosYaw * sinPitch };
    this._outward = { x: sinYaw * cosPitch, y: sinPitch, z: cosYaw * cosPitch };
    this._focal = this.height / (2 * Math.tan(HALF_FOV));
  }

  _cameraPoint(point) {
    const x = point.x - this.target.x;
    const y = point.y - this.target.y;
    const z = point.z - this.target.z;
    return {
      x: x * this._right.x + z * this._right.z,
      y: x * this._up.x + y * this._up.y + z * this._up.z,
      depth: this.distance - x * this._outward.x - y * this._outward.y - z * this._outward.z,
    };
  }

  _screen(point) {
    if (this.view === 'perspective' && point.depth < NEAR_CLIP) return null;
    const divisor = this.view === 'perspective' ? point.depth : this.distance;
    const scale = this._focal / divisor;
    return { x: this.width / 2 + point.x * scale, y: this.height / 2 - point.y * scale, depth: point.depth, scale };
  }

  _project(point) { return this._screen(this._cameraPoint(point)); }

  /** A world-space ray through a CSS-pixel canvas coordinate. */
  _pointerRay(x, y) {
    this._basis();
    const eye = {
      x: this.target.x + this._outward.x * this.distance,
      y: this.target.y + this._outward.y * this.distance,
      z: this.target.z + this._outward.z * this.distance,
    };
    const horizontal = (x - this.width / 2) / this._focal;
    const vertical = (this.height / 2 - y) / this._focal;
    if (this.view !== 'perspective') {
      return {
        origin: {
          x: eye.x + this.distance * (horizontal * this._right.x + vertical * this._up.x),
          y: eye.y + this.distance * vertical * this._up.y,
          z: eye.z + this.distance * (horizontal * this._right.z + vertical * this._up.z),
        },
        direction: { x: -this._outward.x, y: -this._outward.y, z: -this._outward.z },
      };
    }
    const direction = {
      x: -this._outward.x + horizontal * this._right.x + vertical * this._up.x,
      y: -this._outward.y + vertical * this._up.y,
      z: -this._outward.z + horizontal * this._right.z + vertical * this._up.z,
    };
    const length = Math.hypot(direction.x, direction.y, direction.z);
    for (const axis of ['x', 'y', 'z']) direction[axis] /= length;
    return { origin: eye, direction };
  }

  _planeIntersection(ray, point, normal) {
    const denominator = dot(ray.direction, normal);
    if (Math.abs(denominator) < 1e-8) return null;
    const distance = dot(subtract(point, ray.origin), normal) / denominator;
    if (!Number.isFinite(distance) || (this.view === 'perspective' && distance < NEAR_CLIP)) return null;
    return {
      x: ray.origin.x + ray.direction.x * distance,
      y: ray.origin.y + ray.direction.y * distance,
      z: ray.origin.z + ray.direction.z * distance,
    };
  }

  _axisParameter(ray, anchor, axis) {
    const direction = AXES[axis];
    const parallel = dot(ray.direction, direction);
    const denominator = 1 - parallel * parallel;
    // Looking almost along the axis makes its screen-space drag underdetermined.
    if (denominator < 1e-4) return null;
    const offset = subtract(ray.origin, anchor);
    const rayOffset = dot(offset, ray.direction);
    const parameter = (dot(offset, direction) - parallel * rayOffset) / denominator;
    const rayDistance = parallel * parameter - rayOffset;
    if (!Number.isFinite(parameter) || (this.view === 'perspective' && rayDistance < NEAR_CLIP)) return null;
    return parameter;
  }

  _coreItem() {
    const item = this._project({ x: 0, y: 0, z: 0 });
    if (!item) return null;
    const radius = this.options.coreRadius * item.scale;
    if (item.x + radius < 0 || item.x - radius > this.width || item.y + radius < 0 || item.y - radius > this.height) return null;
    return { ...item, kind: 'core', radius };
  }

  _drawCore(item) {
    const ctx = this.ctx;
    const { x, y, radius } = item;
    const glow = ctx.createRadialGradient(x, y, radius * 0.8, x, y, radius * 1.5);
    glow.addColorStop(0, 'rgba(255, 105, 180, 0.2)');
    glow.addColorStop(1, 'rgba(255, 105, 180, 0)');
    ctx.fillStyle = glow;
    ctx.beginPath();
    ctx.arc(x, y, radius * 1.5, 0, TAU);
    ctx.fill();
    const sphere = ctx.createRadialGradient(x - radius * 0.35, y - radius * 0.4, radius * 0.04, x, y, radius);
    sphere.addColorStop(0, '#ffe0f1');
    sphere.addColorStop(0.3, '#ff8bc7');
    sphere.addColorStop(0.7, '#e74b9b');
    sphere.addColorStop(1, '#95245f');
    ctx.fillStyle = sphere;
    ctx.strokeStyle = 'rgba(255, 181, 220, 0.65)';
    ctx.lineWidth = 0.75;
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, TAU);
    ctx.fill();
    ctx.stroke();
  }

  _drawCoreLabel(item) {
    const ctx = this.ctx;
    const label = 'CORE · 0, 0, 0';
    ctx.font = '500 8px ui-monospace, monospace';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    const width = ctx.measureText(label).width;
    const x = clamp(item.x + item.radius + 10, 10, Math.max(10, this.width - width - 10));
    const y = clamp(item.y + 2, 12, this.height - 12);
    ctx.fillStyle = 'rgba(16, 23, 13, 0.8)';
    ctx.fillRect(x - 4, y - 8, width + 8, 16);
    ctx.fillStyle = '#dca1c0';
    ctx.fillText(label, x, y);
    ctx.textBaseline = 'alphabetic';
  }

  _drawCoreGuide() {
    const length = Math.hypot(this.anchor.x, this.anchor.y, this.anchor.z);
    if (length < this.options.coreRadius * 2) return;
    const ctx = this.ctx;
    ctx.strokeStyle = '#a3b590';
    ctx.lineWidth = 0.75;
    ctx.globalAlpha = 0.35;
    ctx.setLineDash([3, 5]);
    this._line3({ x: 0, y: 0, z: 0 }, this.anchor);
    ctx.setLineDash([]);
    ctx.globalAlpha = 1;
    const middle = this._project({ x: this.anchor.x / 2, y: this.anchor.y / 2, z: this.anchor.z / 2 });
    if (!middle) return;
    ctx.font = '500 8px ui-monospace, monospace';
    ctx.fillStyle = '#839475';
    ctx.textAlign = 'left';
    ctx.fillText(`${Number(length.toFixed(2))} studs`, middle.x + 8, middle.y - 5);
  }

  _drawGizmo() {
    const ctx = this.ctx;
    const start = this._project(this.anchor);
    if (!start || start.x < -70 || start.x > this.width + 70 || start.y < -70 || start.y > this.height + 70) return;
    this._gizmoCenter = start;
    const length = 62 / start.scale;
    const colors = { x: '#e99487', y: '#b8dd8c', z: '#86b7eb' };
    const handles = [];
    for (const axis of ['x', 'y', 'z']) {
      const end = this._project({ ...this.anchor, [axis]: this.anchor[axis] + length });
      if (!end) continue;
      const screenLength = Math.hypot(end.x - start.x, end.y - start.y);
      if (screenLength < 13) continue;
      handles.push({ axis, start, end, screenLength });
    }
    handles.sort((a, b) => b.end.depth - a.end.depth);
    this._gizmoHandles = handles;
    for (const handle of handles) {
      const { axis, end, screenLength } = handle;
      const dx = (end.x - start.x) / screenLength, dy = (end.y - start.y) / screenLength;
      const active = (this._moveDrag?.axis || this._hoverAxis) === axis;
      ctx.strokeStyle = '#10160d';
      ctx.lineWidth = active ? 5 : 4;
      ctx.beginPath();
      ctx.moveTo(start.x + dx * 8, start.y + dy * 8);
      ctx.lineTo(end.x, end.y);
      ctx.stroke();
      ctx.strokeStyle = colors[axis];
      ctx.lineWidth = active ? 2.5 : 1.8;
      ctx.stroke();
      ctx.fillStyle = colors[axis];
      ctx.beginPath();
      ctx.moveTo(end.x, end.y);
      ctx.lineTo(end.x - dx * 9 - dy * 4, end.y - dy * 9 + dx * 4);
      ctx.lineTo(end.x - dx * 9 + dy * 4, end.y - dy * 9 - dx * 4);
      ctx.closePath();
      ctx.fill();
      const labelX = end.x + dx * 10, labelY = end.y + dy * 10;
      ctx.fillStyle = '#151e10';
      ctx.beginPath();
      ctx.arc(labelX, labelY, 8, 0, TAU);
      ctx.fill();
      ctx.font = '700 10px ui-monospace, monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillStyle = colors[axis];
      ctx.fillText(axis.toUpperCase(), labelX, labelY);
    }
    ctx.fillStyle = '#1b2515';
    ctx.strokeStyle = this._moveDrag?.axis === 'plane' ? '#e0f5b3' : '#b2c990';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.arc(start.x, start.y, 5, 0, TAU);
    ctx.fill();
    ctx.stroke();
    ctx.textAlign = 'start';
    ctx.textBaseline = 'alphabetic';
  }

  _hitGizmo(x, y) {
    if (!this.options.move) return null;
    if (this._gizmoCenter && Math.hypot(x - this._gizmoCenter.x, y - this._gizmoCenter.y) <= 9) return 'plane';
    let nearest = 9, hit = null;
    for (const { axis, start, end, screenLength } of this._gizmoHandles) {
      const dx = (end.x - start.x) / screenLength, dy = (end.y - start.y) / screenLength;
      const along = (x - start.x) * dx + (y - start.y) * dy;
      if (along < 10 || along > screenLength + 18) continue;
      const distance = Math.abs((x - start.x) * dy - (y - start.y) * dx);
      if (distance < nearest) { nearest = distance; hit = axis; }
    }
    return hit;
  }

  _pick(x, y) {
    let nearest = null, nearestDistance = Infinity;
    for (let index = this._projected.length - 1; index >= 0; index--) {
      const item = this._projected[index];
      const dx = Math.abs(item.x - x), dy = Math.abs(item.y - y);
      const size = this._pointSize(item), half = size / 2;
      if (dx <= half && dy <= (size < 2 ? half : half - dx / 2)) return item;
      const distance = Math.hypot(dx, dy);
      if (distance <= Math.max(7, half + 3) && distance < nearestDistance) { nearest = item; nearestDistance = distance; }
    }
    return nearest;
  }

  _line3(from, to) {
    let a = this._cameraPoint(from);
    let b = this._cameraPoint(to);
    if (this.view === 'perspective') {
      if (a.depth < NEAR_CLIP && b.depth < NEAR_CLIP) return;
      if (a.depth < NEAR_CLIP || b.depth < NEAR_CLIP) {
        if (b.depth < a.depth) [a, b] = [b, a];
        const t = (NEAR_CLIP - a.depth) / (b.depth - a.depth);
        a = { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, depth: NEAR_CLIP };
      }
    }
    const p = this._screen(a);
    const q = this._screen(b);
    if (!p || !q) return;
    this.ctx.beginPath();
    this.ctx.moveTo(p.x, p.y);
    this.ctx.lineTo(q.x, q.y);
    this.ctx.stroke();
  }

  _drawGrid() {
    const ctx = this.ctx;
    // Keep the grid useful and inexpensive at every zoom, including large imports.
    const desiredStep = this.distance / 15;
    const magnitude = 10 ** Math.floor(Math.log10(desiredStep));
    const fraction = desiredStep / magnitude;
    const step = (fraction >= 5 ? 5 : fraction >= 2 ? 2 : 1) * magnitude;
    const extent = Math.ceil(this.distance / step) * step;
    const centerX = Math.round(this.target.x / step) * step;
    const centerZ = Math.round(this.target.z / step) * step;
    ctx.lineWidth = 0.75;
    ctx.strokeStyle = '#95a68b';
    for (let offset = -extent; offset <= extent; offset += step) {
      const fade = Math.pow(1 - Math.abs(offset) / (extent + step), 1.6);
      const x = centerX + offset;
      const z = centerZ + offset;
      ctx.globalAlpha = (Math.round(x / step) % 5 === 0 ? 0.13 : 0.065) * fade;
      this._line3({ x, y: 0, z: centerZ - extent }, { x, y: 0, z: centerZ + extent });
      ctx.globalAlpha = (Math.round(z / step) % 5 === 0 ? 0.13 : 0.065) * fade;
      this._line3({ x: centerX - extent, y: 0, z }, { x: centerX + extent, y: 0, z });
    }
    ctx.globalAlpha = 1;
  }

  _drawAxes() {
    const ctx = this.ctx;
    const extent = Math.max(80, this.distance);
    ctx.lineWidth = 0.8;
    ctx.globalAlpha = 0.2;
    ctx.strokeStyle = '#e2828a';
    this._line3({ x: -extent, y: 0, z: 0 }, { x: extent, y: 0, z: 0 });
    ctx.strokeStyle = '#729fca';
    this._line3({ x: 0, y: 0, z: -extent }, { x: 0, y: 0, z: extent });
    ctx.globalAlpha = 0.12;
    ctx.strokeStyle = '#7bae99';
    ctx.setLineDash([3, 5]);
    this._line3({ x: 0, y: 0, z: 0 }, { x: 0, y: extent * 0.6, z: 0 });
    ctx.setLineDash([]);
    ctx.globalAlpha = 1;
  }

  _drawBounds(bounds) {
    const ctx = this.ctx;
    const corners = this._corners(bounds, 2.5);
    const edges = [[0, 1], [0, 2], [0, 4], [1, 3], [1, 5], [2, 3], [2, 6], [3, 7], [4, 5], [4, 6], [5, 7], [6, 7]];
    ctx.strokeStyle = '#b4c5a1';
    ctx.lineWidth = 0.7;
    ctx.globalAlpha = 0.15;
    ctx.setLineDash([3, 5]);
    for (const [a, b] of edges) this._line3(corners[a], corners[b]);
    ctx.setLineDash([]);
    ctx.lineWidth = 1;
    ctx.globalAlpha = 0.56;
    for (const [a, b] of edges) {
      const start = corners[a];
      const end = corners[b];
      const length = Math.hypot(start.x - end.x, start.y - end.y, start.z - end.z);
      const amount = Math.min(0.2, 3 / Math.max(0.01, length));
      this._line3(start, { x: start.x + (end.x - start.x) * amount, y: start.y + (end.y - start.y) * amount, z: start.z + (end.z - start.z) * amount });
      this._line3(end, { x: end.x + (start.x - end.x) * amount, y: end.y + (start.y - end.y) * amount, z: end.z + (start.z - end.z) * amount });
    }
    ctx.globalAlpha = 1;
  }

  _drawCompass() {
    const ctx = this.ctx;
    const x = 36;
    const y = this.height - 37;
    const axes = [
      { label: 'X', vector: { x: 1, y: 0, z: 0 }, color: '#c57b86' },
      { label: 'Y', vector: { x: 0, y: 1, z: 0 }, color: '#7cad98' },
      { label: 'Z', vector: { x: 0, y: 0, z: 1 }, color: '#7d9bc3' },
    ];
    axes.sort((a, b) => (a.vector.x - b.vector.x) * this._outward.x + (a.vector.y - b.vector.y) * this._outward.y + (a.vector.z - b.vector.z) * this._outward.z);
    ctx.font = '600 9px system-ui, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.lineWidth = 1.25;
    for (const axis of axes) {
      const v = axis.vector;
      const dx = (v.x * this._right.x + v.z * this._right.z) * 21;
      const dy = -(v.x * this._up.x + v.y * this._up.y + v.z * this._up.z) * 21;
      ctx.strokeStyle = axis.color;
      ctx.globalAlpha = 0.7;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + dx, y + dy);
      ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.fillStyle = '#131a10';
      ctx.beginPath();
      ctx.arc(x + dx, y + dy, 6, 0, TAU);
      ctx.fill();
      ctx.fillStyle = axis.color;
      ctx.fillText(axis.label, x + dx, y + dy);
    }
    ctx.textAlign = 'start';
    ctx.textBaseline = 'alphabetic';
  }

  _pointSize(item) {
    const divisor = this.view === 'perspective' ? item.depth : this.distance;
    return clamp(this.options.pointSize * DEFAULT_DISTANCE / Math.max(0.5, divisor), 0.8, 24);
  }

  _drawBlock(x, y, size, colors) {
    const ctx = this.ctx;
    if (size < 2) {
      ctx.fillStyle = colors.base;
      ctx.fillRect(x - size / 2, y - size / 2, size, size);
      return;
    }
    const half = size * 0.5;
    const quarter = size * 0.25;
    ctx.fillStyle = colors.light;
    ctx.beginPath();
    ctx.moveTo(x, y - half);
    ctx.lineTo(x + half, y - quarter);
    ctx.lineTo(x, y);
    ctx.lineTo(x - half, y - quarter);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = colors.base;
    ctx.beginPath();
    ctx.moveTo(x - half, y - quarter);
    ctx.lineTo(x, y);
    ctx.lineTo(x, y + half);
    ctx.lineTo(x - half, y + quarter);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = colors.dark;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + half, y - quarter);
    ctx.lineTo(x + half, y + quarter);
    ctx.lineTo(x, y + half);
    ctx.closePath();
    ctx.fill();
  }

  _color(value = '#a891ef') {
    if (this._colors.has(value)) return this._colors.get(value);
    this.ctx.fillStyle = '#a891ef';
    this.ctx.fillStyle = value;
    const normalized = this.ctx.fillStyle;
    let rgb = [168, 145, 239];
    if (normalized.startsWith('#')) {
      let hex = normalized.slice(1);
      if (hex.length === 3 || hex.length === 4) hex = [...hex].map((n) => n + n).join('');
      rgb = [0, 2, 4].map((index) => parseInt(hex.slice(index, index + 2), 16));
    } else {
      const channels = normalized.match(/[\d.]+/g);
      if (channels && channels.length >= 3) rgb = channels.slice(0, 3).map(Number);
    }
    const asColor = (channels) => `rgb(${channels.map((n) => Math.round(clamp(n, 0, 255))).join(',')})`;
    const colors = {
      base: asColor(rgb),
      light: asColor(rgb.map((n) => n + (255 - n) * 0.32)),
      dark: asColor(rgb.map((n) => n * 0.69)),
    };
    // Animated colors should not grow this cache without bound.
    if (this._colors.size > 512) this._colors.clear();
    this._colors.set(value, colors);
    return colors;
  }

  _validPoint(point) { return point && Number.isFinite(point.x) && Number.isFinite(point.y) && Number.isFinite(point.z); }

  _bounds(points) {
    const min = { x: Infinity, y: Infinity, z: Infinity };
    const max = { x: -Infinity, y: -Infinity, z: -Infinity };
    let count = 0;
    for (const point of points) {
      if (!this._validPoint(point)) continue;
      count++;
      for (const key of ['x', 'y', 'z']) {
        min[key] = Math.min(min[key], point[key]);
        max[key] = Math.max(max[key], point[key]);
      }
    }
    return count ? { min, max } : null;
  }

  _corners(bounds, padding = 0) {
    return Array.from({ length: 8 }, (_, index) => ({
      x: index & 1 ? bounds.max.x + padding : bounds.min.x - padding,
      y: index & 2 ? bounds.max.y + padding : bounds.min.y - padding,
      z: index & 4 ? bounds.max.z + padding : bounds.min.z - padding,
    }));
  }

  _cameraChanged() {
    this._dirty = true;
    this.onCameraChange?.({ zoom: this.zoom, view: this.view });
    this.render();
  }

  _pointerDown(event) {
    if (event.button !== 0 && event.button !== 1 && event.button !== 2) return;
    event.preventDefault();
    // Preventing the drag default also prevents focus; restore it so shortcuts
    // work immediately after leaving a property field for the preview.
    this.canvas.focus({ preventScroll: true });
    const pointer = {
      x: event.clientX, y: event.clientY, startX: event.clientX, startY: event.clientY,
      moved: false, pan: event.button !== 0 || event.shiftKey, selectionHandled: false,
    };
    this._pointers.set(event.pointerId, pointer);
    this.canvas.setPointerCapture(event.pointerId);
    this.canvas.style.cursor = 'grabbing';
    if (this._pointers.size > 1) {
      this._finishMove(true);
      for (const active of this._pointers.values()) active.moved = true;
      return;
    }
    if (!pointer.pan) {
      this.render();
      const rect = this.canvas.getBoundingClientRect();
      const x = event.clientX - rect.left, y = event.clientY - rect.top;
      const axis = this._hitGizmo(x, y);
      if (axis && this.anchor && this.selected !== null) {
        pointer.selectionHandled = true;
        this._beginMove(event.pointerId, this.selected, axis, this.anchor, x, y);
      } else {
        const hit = this._pick(x, y);
        if (hit) {
          pointer.selectionHandled = true;
          this.setSelected(hit.point.layerId);
          this.onSelect?.(hit.point.layerId);
          if (this.options.move) this._beginMove(event.pointerId, hit.point.layerId, 'plane', hit.point, x, y);
        }
      }
    }
  }

  _pointerMove(event) {
    const pointer = this._pointers.get(event.pointerId);
    if (!pointer) {
      if (this._pointers.size) return;
      const rect = this.canvas.getBoundingClientRect();
      const x = event.clientX - rect.left, y = event.clientY - rect.top;
      const axis = this._hitGizmo(x, y);
      if (axis !== this._hoverAxis) { this._hoverAxis = axis; this._dirty = true; }
      this.canvas.style.cursor = this.options.move && (axis || this._pick(x, y)) ? 'move' : 'grab';
      return;
    }
    const dx = event.clientX - pointer.x;
    const dy = event.clientY - pointer.y;
    if (this._moveDrag?.pointerId === event.pointerId) {
      if (this._moveDrag.started || Math.hypot(event.clientX - pointer.startX, event.clientY - pointer.startY) > 3) {
        pointer.moved = true;
        this._updateMove(event.clientX, event.clientY);
      }
      pointer.x = event.clientX;
      pointer.y = event.clientY;
      return;
    }
    if (this._pointers.size === 2) {
      const other = [...this._pointers.entries()].find(([id]) => id !== event.pointerId)?.[1];
      if (other) {
        const previous = Math.hypot(pointer.x - other.x, pointer.y - other.y);
        const next = Math.hypot(event.clientX - other.x, event.clientY - other.y);
        if (previous > 5 && next > 5) this.distance = clamp(this.distance * previous / next, 8, MAX_DISTANCE);
        this._pan(dx * 0.5, dy * 0.5);
      }
      pointer.moved = true;
    } else {
      if (Math.hypot(event.clientX - pointer.startX, event.clientY - pointer.startY) > 4) pointer.moved = true;
      if (pointer.moved) {
        if (pointer.pan || event.shiftKey) this._pan(dx, dy);
        else {
          this.yaw = (this.yaw - dx * 0.006) % TAU;
          this.pitch = clamp(this.pitch + dy * 0.006, -Math.PI / 2 + 0.02, Math.PI / 2 - 0.02);
          this.view = 'perspective';
        }
      }
    }
    pointer.x = event.clientX;
    pointer.y = event.clientY;
    if (pointer.moved) this._cameraChanged();
  }

  _pan(dx, dy) {
    this._basis();
    const scale = this.distance / this._focal;
    this.target.x += (-dx * this._right.x + dy * this._up.x) * scale;
    this.target.y += dy * this._up.y * scale;
    this.target.z += (-dx * this._right.z + dy * this._up.z) * scale;
  }

  _beginMove(pointerId, layerId, axis, point, x, y) {
    const ray = this._pointerRay(x, y);
    const anchor = { ...(this.anchor || point) };
    const planePoint = { x: point.x, y: point.y, z: point.z };
    const normal = { ...this._outward };
    const initial = axis === 'plane' ? this._planeIntersection(ray, planePoint, normal) : this._axisParameter(ray, anchor, axis);
    if (initial === null) return;
    this._moveDrag = { pointerId, layerId, axis, anchor, planePoint, normal, initial, started: false };
    this._dirty = true;
  }

  _updateMove(clientX, clientY) {
    const drag = this._moveDrag;
    if (!drag) return;
    const rect = this.canvas.getBoundingClientRect();
    const ray = this._pointerRay(clientX - rect.left, clientY - rect.top);
    let delta;
    if (drag.axis === 'plane') {
      const point = this._planeIntersection(ray, drag.planePoint, drag.normal);
      if (!point) return;
      delta = subtract(point, drag.initial);
    } else {
      const parameter = this._axisParameter(ray, drag.anchor, drag.axis);
      if (parameter === null) return;
      delta = { x: 0, y: 0, z: 0, [drag.axis]: parameter - drag.initial };
    }
    if (!this._validPoint(delta)) return;
    if (!drag.started) {
      drag.started = true;
      this.onMoveStart?.(drag.layerId);
      if (this._moveDrag !== drag) return;
    }
    // The host applies these total deltas to its drag-start snapshot. Snapping
    // and bound control limits remain in the model, never in camera math.
    this.onMove?.(delta, { layerId: drag.layerId, axis: drag.axis });
    this._dirty = true;
  }

  _finishMove(cancelled) {
    const drag = this._moveDrag;
    if (!drag) return;
    this._moveDrag = null;
    this._hoverAxis = null;
    this._dirty = true;
    if (drag.started) this.onMoveEnd?.({ cancelled: Boolean(cancelled) });
  }

  _pointerUp(event) {
    const pointer = this._pointers.get(event.pointerId);
    if (!pointer) return;
    if (this._moveDrag?.pointerId === event.pointerId) {
      if (event.clientX !== pointer.x || event.clientY !== pointer.y) this._pointerMove(event);
      this._finishMove(false);
    } else if (!pointer.moved && !pointer.pan && !pointer.selectionHandled && this._pointers.size === 1) {
      this.setSelected(null);
      this.onSelect?.(null);
    }
    this._releasePointer(event.pointerId);
  }

  _pointerCancel(event) {
    if (this._moveDrag?.pointerId === event.pointerId) this._finishMove(true);
    this._releasePointer(event.pointerId);
  }

  _cancelPointers() {
    this._finishMove(true);
    for (const id of [...this._pointers.keys()]) this._releasePointer(id);
    this._hoverAxis = null;
    this._dirty = true;
  }

  _keyDown(event) {
    if (event.key !== 'Escape' || !this._pointers.size) return;
    event.preventDefault();
    event.stopPropagation();
    this._cancelPointers();
  }

  _releasePointer(id) {
    this._pointers.delete(id);
    if (this.canvas.hasPointerCapture(id)) this.canvas.releasePointerCapture(id);
    if (!this._pointers.size) this.canvas.style.cursor = 'grab';
  }

  _wheel(event) {
    event.preventDefault();
    if (this._moveDrag) return;
    const delta = event.deltaY * (event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? this.height : 1);
    this.distance = clamp(this.distance * Math.exp(clamp(delta * 0.001, -0.7, 0.7)), 8, MAX_DISTANCE);
    this._cameraChanged();
  }
}
