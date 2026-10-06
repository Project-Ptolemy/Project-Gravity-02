import { compilePath, samplePath, MAX_PATH_POINTS, PATH_COORDINATE_LIMIT } from './geometry/path.mjs';

// The editor and exported plugin share this point-sampling contract. All units
// are Roblox studs, degrees, and seconds of the engine's formation clock.
export const LAYER_TYPES = Object.freeze(['sphere', 'ring', 'torus', 'helix', 'box', 'grid', 'cone', 'cylinder', 'line', 'spiral', 'polygon', 'path', 'pointcloud']);
export const DEFAULT_PART_COUNT = 128;
const def = (label, min, max, step, value) => Object.freeze({ label, min, max, step, default: value });
export const PROPERTY_DEFS = Object.freeze({
  radius: def('Radius', 0, 500, 0.1, 24),
  height: def('Height', 0, 1000, 0.1, 40),
  width: def('Width', 0, 1000, 0.1, 30),
  depth: def('Depth', 0, 1000, 0.1, 30),
  tube: def('Tube radius', 0, 100, 0.1, 6),
  sides: def('Polygon sides', 3, 128, 1, 3),
  turns: def('Turns', 0.1, 30, 0.1, 3),
  arc: def('Arc', 1, 360, 1, 360),
  spin: def('Spin Y', -360, 360, 1, 15),
  spinX: def('Spin X', -360, 360, 1, 0),
  spinZ: def('Spin Z', -360, 360, 1, 0),
  pulse: def('Pulse amount (%)', 0, 90, 1, 0),
  pulseSpeed: def('Pulse frequency (Hz)', 0, 10, 0.05, 1),
  pulsePhase: def('Pulse phase', -360, 360, 1, 0),
  wave: def('Wave height', 0, 200, 0.1, 0),
  waveSpeed: def('Wave frequency (Hz)', 0, 10, 0.05, 1),
  waveCount: def('Wave cycles along path', 0, 20, 0.1, 1),
  wavePhase: def('Wave phase', -360, 360, 1, 0),
  orbitRadius: def('Orbit radius', 0, 500, 0.1, 0),
  orbitAspect: def('Orbit Z aspect', 0.01, 5, 0.01, 1),
  orbitSpeed: def('Orbit speed (deg/s)', -360, 360, 1, 15),
  orbitTiltX: def('Orbit tilt X', -180, 180, 1, 0),
  orbitTiltZ: def('Orbit tilt Z', -180, 180, 1, 0),
  orbitPhase: def('Orbit phase', -360, 360, 1, 0),
  bobAmount: def('Bob height', 0, 200, 0.1, 0),
  bobSpeed: def('Bob frequency (Hz)', 0, 10, 0.05, 1),
  bobPhase: def('Bob phase', -360, 360, 1, 0),
  twist: def('Twist along path', -720, 720, 1, 0),
  taper: def('Taper along path (%)', -90, 90, 1, 0),
  scatter: def('Scatter per axis', 0, 100, 0.1, 0),
  timeScale: def('Layer time scale', -4, 4, 0.05, 1),
  timeOffset: def('Layer time offset (s)', -600, 600, 0.1, 0),
  phase: def('Phase', -360, 360, 1, 0),
  weight: def('Part weight', 0, 20, 0.1, 1),
  'position.x': def('Position X', -5000, 5000, 0.1, 0),
  'position.y': def('Position Y', -5000, 5000, 0.1, 20),
  'position.z': def('Position Z', -5000, 5000, 0.1, 0),
  'rotation.x': def('Rotation X', -360, 360, 1, 0),
  'rotation.y': def('Rotation Y', -360, 360, 1, 0),
  'rotation.z': def('Rotation Z', -360, 360, 1, 0),
  'scale.x': def('Scale X', 0.01, 10, 0.01, 1),
  'scale.y': def('Scale Y', 0.01, 10, 0.01, 1),
  'scale.z': def('Scale Z', 0.01, 10, 0.01, 1),
});
export const BOOLEAN_DEFS = Object.freeze({
  visible: Object.freeze({ label: 'Visibility', default: true }),
  fill: Object.freeze({ label: 'Fill interior', default: false }),
});
const ACTION_LABELS = Object.freeze({ restart: 'Restart animation', reverse: 'Reverse animation', reset: 'Reset controls' });
// Preview action clocks belong to temporary control values, never project JSON.
// A symbol cannot collide with an imported control ID.
const PREVIEW_ANIMATION = Symbol('preview animation');

const TAU = Math.PI * 2;
const RAD = Math.PI / 180;
const PHI = 0.6180339887498949;
const PSI = 0.7548776662466927;
const SCATTER_X = 1.4142135623730951, SCATTER_Y = 1.7320508075688772, SCATTER_Z = 2.23606797749979;
const COLORS = ['#b7f399', '#b8a4ff', '#79d9ea', '#ffc98a', '#f28faf'];
let sequence = 0;
const makeId = () => 'layer-' + (globalThis.crypto?.randomUUID?.() || Date.now().toString(36) + '-' + (++sequence).toString(36));
const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
const fract = value => value - Math.floor(value);
const own = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const error = message => { throw new Error(message); };

function numeric(value, fallback, min, max, label) {
  if (value === undefined) return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value)) error(`${label} must be a finite number.`);
  if (value < min || value > max) error(`${label} must be between ${min} and ${max}.`);
  return value;
}
function text(value, fallback, max, label) {
  if (value === undefined) return fallback;
  if (typeof value !== 'string' || !value.trim() || value.length > max || /[\u0000-\u001f\u007f]/.test(value)) {
    error(`${label} must be 1–${max} characters without line breaks or control characters.`);
  }
  return value.trim();
}
function identifier(value, fallback, label) {
  const result = text(value, fallback, 80, label);
  if (!/^[a-zA-Z0-9_-]+$/.test(result)) error(`${label} may contain only letters, numbers, underscores, and hyphens.`);
  return result;
}
function boolean(value, fallback, label) {
  if (value === undefined) return fallback;
  if (typeof value !== 'boolean') error(`${label} must be true or false.`);
  return value;
}
function decimalPlaces(value, label = 'Control value') {
  for (let places = 0; places <= 6; places++) {
    const divisor = 10 ** places;
    const rounded = Math.round(value * divisor) / divisor;
    if (Math.abs(value - rounded) <= Math.abs(value) * Number.EPSILON * 4) return places;
  }
  error(`${label} supports at most 6 decimal places.`);
}
export function controlDivisor(control) {
  const property = PROPERTY_DEFS[control.property];
  if (!property) error('The control has an unsupported property.');
  return 10 ** Math.max(...[property.step, control.min, control.max, control.default].map(value => decimalPlaces(value)));
}
export function getProperty(layer, property) {
  const [group, axis] = property.split('.');
  return axis ? layer[group][axis] : layer[group];
}
export function setProperty(layer, property, value) {
  if (!own(PROPERTY_DEFS, property) && !own(BOOLEAN_DEFS, property)) error(`Unsupported property: ${property}`);
  const [group, axis] = property.split('.');
  if (property === 'sides') value = Math.round(value);
  if (axis) layer[group][axis] = value;
  else layer[group] = value;
}

export function createLayer(type = 'sphere', overrides = {}) {
  if (!LAYER_TYPES.includes(type)) error(`Unknown layer type: ${type}.`);
  const layer = {
    id: makeId(), name: type[0].toUpperCase() + type.slice(1), type,
    visible: true, color: COLORS[0], position: { x: 0, y: 20, z: 0 },
    rotation: { x: 0, y: 0, z: 0 }, scale: { x: 1, y: 1, z: 1 }, fill: false,
  };
  for (const [key, config] of Object.entries(PROPERTY_DEFS)) if (!key.includes('.')) layer[key] = config.default;
  if (['helix', 'line', 'polygon', 'path', 'pointcloud'].includes(type)) layer.tube = 0;
  if (type === 'spiral') layer.height = 0;
  if (['box', 'grid', 'line', 'polygon', 'path', 'pointcloud'].includes(type)) layer.spin = 0;
  Object.assign(layer, overrides);
  for (const group of ['position', 'rotation', 'scale']) {
    layer[group] = Object.fromEntries(['x', 'y', 'z'].map(axis => [axis, overrides[group]?.[axis] ?? PROPERTY_DEFS[group + '.' + axis].default]));
  }
  return normalizeLayer(layer, 0);
}

function normalizeLayer(input, index) {
  if (!plain(input)) error(`Layer ${index + 1} must be an object.`);
  if (!LAYER_TYPES.includes(input.type)) error(`Layer ${index + 1} has an unsupported shape type.`);
  const label = `Layer ${index + 1}`;
  const layer = {
    id: identifier(input.id, `layer-${index + 1}`, `${label} ID`),
    name: text(input.name, input.type[0].toUpperCase() + input.type.slice(1), 80, `${label} name`),
    type: input.type,
    visible: boolean(input.visible, true, `${label} visibility`),
    fill: boolean(input.fill, false, `${label} fill`),
    color: input.color === undefined ? COLORS[index % COLORS.length] : input.color,
    position: {}, rotation: {}, scale: {},
  };
  if (typeof layer.color !== 'string' || !/^#[0-9a-f]{6}$/i.test(layer.color)) error(`${label} color must be a six-digit hex color, such as #b7f399.`);
  for (const group of ['position', 'rotation', 'scale']) if (input[group] !== undefined && !plain(input[group])) error(`${label} ${group} must contain x, y, and z values.`);
  for (const [property, config] of Object.entries(PROPERTY_DEFS)) {
    const [group, axis] = property.split('.');
    const value = axis ? input[group]?.[axis] : input[property];
    const custom = ['polygon', 'path', 'pointcloud'].includes(layer.type);
    const fallback = custom && (property === 'spin' || property === 'tube') ? 0 : config.default;
    const number = numeric(value, fallback, config.min, config.max, `${label}: ${config.label}`);
    if (property === 'sides' && !Number.isInteger(number)) error(`${label}: Polygon sides must be a whole number.`);
    setProperty(layer, property, number);
  }
  if (layer.type === 'path' || layer.type === 'pointcloud') {
    const path = input.path === undefined ? { points: [{ x: -24, y: -16, z: 0 }, { x: 0, y: 20, z: 0 }, { x: 24, y: -16, z: 0 }] } : input.path;
    if (!plain(path)) error(`${label} path must be an object containing points.`);
    const minimum = layer.type === 'pointcloud' ? 1 : 2;
    if (!Array.isArray(path.points) || path.points.length < minimum || path.points.length > MAX_PATH_POINTS) error(`${label} path must contain ${minimum} to ${MAX_PATH_POINTS} points.`);
    layer.path = {
      points: path.points.map((point, index) => {
        if (!plain(point)) error(`${label} point ${index + 1} must contain x, y, and z coordinates.`);
        if (['x', 'y', 'z'].some(axis => point[axis] === undefined)) error(`${label} point ${index + 1} must contain x, y, and z coordinates.`);
        return Object.fromEntries(['x', 'y', 'z'].map(axis => [axis, numeric(point[axis], 0, -PATH_COORDINATE_LIMIT, PATH_COORDINATE_LIMIT, `${label} point ${index + 1} ${axis.toUpperCase()}`)]));
      }),
      closed: boolean(path.closed, false, `${label} closed path`),
      smooth: boolean(path.smooth, false, `${label} smooth path`),
    };
  }
  return layer;
}

export function normalizeProject(input) {
  if (!plain(input)) error('Choose a builder project JSON object.');
  if (input.version !== 1) error('This project version is not supported. Expected version 1.');
  if (!Array.isArray(input.layers) || input.layers.length > 64) error('A project must have a layers array with no more than 64 layers.');
  if (input.controls !== undefined && (!Array.isArray(input.controls) || input.controls.length > 96)) error('A project can contain up to 96 controls.');
  const project = {
    version: 1,
    name: text(input.name, 'Untitled shape', 80, 'Project name'),
    parts: numeric(input.parts, DEFAULT_PART_COUNT, 1, 8192, 'Preview part count'),
    pointSize: numeric(input.pointSize, 3.4, 0.25, 10, 'Preview point size'),
    layers: input.layers.map(normalizeLayer), controls: [],
  };
  if (!Number.isInteger(project.parts)) error('Preview part count must be a whole number.');
  const ids = new Set();
  for (const layer of project.layers) {
    if (ids.has(layer.id)) error(`Duplicate layer ID: ${layer.id}.`);
    ids.add(layer.id);
  }
  const controlIds = new Set(), bindings = new Set();
  project.controls = (input.controls || []).map((inputControl, index) => {
    if (!plain(inputControl)) error(`Control ${index + 1} must be an object.`);
    const label = `Control ${index + 1}`;
    const type = inputControl.type ?? 'slider';
    if (!['slider', 'toggle', 'button'].includes(type)) error(`${label} has an unsupported control type.`);
    if (!ids.has(inputControl.layerId)) error(`${label} refers to a layer that does not exist.`);
    const id = identifier(inputControl.id, `control-${index + 1}`, `${label} ID`);
    if (controlIds.has(id)) error(`Duplicate control ID: ${id}.`);
    controlIds.add(id);
    if (type === 'button') {
      if (!own(ACTION_LABELS, inputControl.action)) error(`${label} has an unsupported action.`);
      return { id, type, name: text(inputControl.name, ACTION_LABELS[inputControl.action], 80, `${label} name`), layerId: inputControl.layerId, action: inputControl.action };
    }
    const property = inputControl.property;
    const definitions = type === 'toggle' ? BOOLEAN_DEFS : PROPERTY_DEFS;
    if (typeof property !== 'string' || !own(definitions, property)) error(`${label} has an unsupported property.`);
    const binding = inputControl.layerId + ':' + property;
    if (bindings.has(binding)) error(`${label}: this layer property already has a control.`);
    bindings.add(binding);
    const current = getProperty(project.layers.find(layer => layer.id === inputControl.layerId), property);
    if (type === 'toggle') return {
      id, type, name: text(inputControl.name, definitions[property].label, 80, `${label} name`), layerId: inputControl.layerId, property,
      default: boolean(inputControl.default, current, `${label} default`),
    };
    const config = PROPERTY_DEFS[property];
    const control = {
      id,
      name: text(inputControl.name, config.label, 80, `${label} name`),
      layerId: inputControl.layerId, property,
      min: numeric(inputControl.min, config.min, config.min, config.max, `${label} minimum`),
      max: numeric(inputControl.max, config.max, config.min, config.max, `${label} maximum`),
    };
    if (control.min >= control.max) error(`${label} minimum must be less than its maximum.`);
    control.default = numeric(inputControl.default, clamp(current, control.min, control.max), control.min, control.max, `${label} default`);
    if (property === 'sides' && ![control.min, control.max, control.default].every(Number.isInteger)) error(`${label}: Polygon sides controls must use whole numbers.`);
    for (const key of ['min', 'max', 'default']) {
      const places = decimalPlaces(control[key], `${label} ${key}`);
      const divisor = 10 ** places;
      control[key] = Math.round(control[key] * divisor) / divisor;
    }
    if (inputControl.type !== undefined) control.type = type;
    return control;
  });
  return project;
}

export function createProject(preset = 'orbit') {
  const project = { version: 1, name: 'Untitled shape', parts: DEFAULT_PART_COUNT, pointSize: 3.4, layers: [], controls: [] };
  const add = (type, overrides) => { const layer = createLayer(type, overrides); project.layers.push(layer); return layer; };
  if (preset === 'blank') return project;
  if (preset === 'helix') {
    project.name = 'Double Helix';
    add('helix', { name: 'First strand', radius: 19, height: 64, turns: 2, spin: 18, color: COLORS[0], weight: 2 });
    add('helix', { name: 'Second strand', radius: 19, height: 64, turns: 2, phase: 180, spin: 18, color: COLORS[1], weight: 2 });
    add('ring', { name: 'Lower halo', radius: 24, position: { y: -12 }, color: COLORS[2], weight: 0.7 });
    add('ring', { name: 'Upper halo', radius: 24, position: { y: 52 }, color: COLORS[2], weight: 0.7 });
  } else if (preset === 'solar') {
    project.name = 'Solar System';
    add('sphere', { name: 'Sun', radius: 12, color: '#ffc98a', weight: 2, pulse: 5, pulseSpeed: 0.4 });
    add('ring', { name: 'Inner orbit', radius: 28, color: COLORS[0], weight: 1 });
    add('ring', { name: 'Outer orbit', radius: 46, rotation: { x: 20 }, color: COLORS[1], weight: 1.5 });
    add('sphere', { name: 'Planet', radius: 5, position: { x: 28 }, color: COLORS[2], weight: 0.6 });
  } else if (preset === 'orbit') {
    project.name = 'Orbit Bloom';
    add('sphere', { name: 'Living core', radius: 13, color: COLORS[0], weight: 1.4, pulse: 9, pulseSpeed: 0.3 });
    add('ring', { name: 'Outer halo', radius: 36, rotation: { x: 28, z: -20 }, spin: 9, color: COLORS[0], weight: 1.1 });
    add('ring', { name: 'Crossing orbit', radius: 30, rotation: { x: 72, z: 35 }, spin: -12, color: COLORS[1], weight: 1 });
    add('ring', { name: 'Inner orbit', radius: 23, rotation: { x: -32, z: 60 }, spin: 18, color: COLORS[2], weight: 0.8 });
  } else error(`Unknown preset: ${preset}.`);
  const core = project.layers[0];
  project.controls.push({ id: 'core-radius', name: 'Core radius', layerId: core.id, property: 'radius', min: 1, max: 60, default: core.radius });
  return normalizeProject(project);
}

function resolveAllLayers(project, values = {}) {
  const layers = project.layers.map(layer => ({ ...layer, position: { ...layer.position }, rotation: { ...layer.rotation }, scale: { ...layer.scale } }));
  const byId = new Map(layers.map(layer => [layer.id, layer]));
  for (const control of project.controls) {
    if (control.type === 'button') continue;
    const proposed = own(values, control.id) ? values[control.id] : control.default;
    const layer = byId.get(control.layerId);
    if (!layer) continue;
    if (control.type === 'toggle') setProperty(layer, control.property, typeof proposed === 'boolean' ? proposed : control.default);
    else {
      const value = typeof proposed === 'number' && Number.isFinite(proposed) ? proposed : control.default;
      setProperty(layer, control.property, clamp(value, control.min, control.max));
    }
  }
  for (const layer of layers) {
    const animations = values[PREVIEW_ANIMATION];
    const animation = animations && own(animations, layer.id) ? animations[layer.id] : null;
    if (animation) { layer.timeScale *= animation.direction; layer.timeOffset += animation.offset; }
  }
  return layers;
}
export function resolveLayers(project, values = {}) {
  const layers = resolveAllLayers(project, values);
  return layers.filter(layer => layer.visible && layer.weight > 0);
}

export function applyPreviewAction(input, controlId, time, values = {}) {
  const project = normalizeProject(input);
  if (!Number.isFinite(time)) error('Preview time must be a finite number.');
  const control = project.controls.find(item => item.id === controlId && item.type === 'button');
  if (!control) error('Choose an action button in this project.');
  const next = Object.assign(Object.create(null), values);
  const animations = Object.assign(Object.create(null), values[PREVIEW_ANIMATION]);
  next[PREVIEW_ANIMATION] = animations;
  if (control.action === 'reset') {
    for (const item of project.controls) if (item.layerId === control.layerId) delete next[item.id];
    delete animations[control.layerId];
  } else {
    const layer = resolveAllLayers(project, values).find(item => item.id === control.layerId);
    const animation = { direction: 1, offset: 0, ...(own(animations, control.layerId) ? animations[control.layerId] : {}) };
    if (control.action === 'restart') animation.offset -= time * layer.timeScale + layer.timeOffset;
    else { animation.direction *= -1; animation.offset += 2 * time * layer.timeScale; }
    animations[control.layerId] = animation;
  }
  return next;
}

// The minor-angle CDF on a regular torus is (angle + e*sin(angle)) / TAU.
// Its Jacobian is R + r*cos(angle); uniform angles overpopulate the inner rim.
function torusAngle(fraction, eccentricity) {
  const target = TAU * fraction;
  let angle = target, low = 0, high = TAU;
  for (let iteration = 0; iteration < 16; iteration++) {
    const residual = angle + eccentricity * Math.sin(angle) - target;
    if (Math.abs(residual) < 1e-12) break;
    if (residual > 0) high = angle; else low = angle;
    const slope = 1 + eccentricity * Math.cos(angle);
    const next = slope > 1e-12 ? angle - residual / slope : -1;
    angle = next > low && next < high ? next : (low + high) / 2;
  }
  return angle;
}

// index is zero-based within its layer; count is that layer's actual share.
// Order: primitive -> local-Y twist -> radial taper -> local scatter -> Y wave
// -> scale/pulse -> X/Y/Z rotation/spin -> tilted orbit -> world-Y bob -> position.
// The layer clock (time*timeScale+timeOffset) drives every temporal modifier.
export function sampleLayer(layer, index, count, time = 0, pathTable = null) {
  time = time * layer.timeScale + layer.timeOffset;
  const u = (index + 0.5) / Math.max(1, count);
  const v = fract((index + 0.5) * PHI), w = fract((index + 0.5) * PSI);
  const phase = layer.phase * RAD;
  const a = layer.arc * RAD * u + phase, b = TAU * v;
  let x = 0, y = 0, z = 0;
  if (layer.type === 'sphere') {
    const sy = 1 - 2 * u, r = layer.radius * (layer.fill ? Math.cbrt(w) : 1), horizontal = Math.sqrt(Math.max(0, 1 - sy * sy));
    x = Math.cos(b + phase) * horizontal * r; y = sy * r; z = Math.sin(b + phase) * horizontal * r;
  } else if (layer.type === 'ring') {
    const r = layer.radius * (layer.fill ? Math.sqrt(v) : 1);
    x = Math.cos(a) * r; z = Math.sin(a) * r;
  } else if (layer.type === 'torus') {
    const r = layer.tube * (layer.fill ? Math.sqrt(w) : 1);
    const angle = layer.radius > 0 && layer.radius >= layer.tube ? torusAngle(v, r / layer.radius) : b;
    x = (layer.radius + r * Math.cos(angle)) * Math.cos(a); y = r * Math.sin(angle); z = (layer.radius + r * Math.cos(angle)) * Math.sin(a);
  } else if (layer.type === 'helix' || layer.type === 'spiral') {
    const angle = a * layer.turns - phase * (layer.turns - 1);
    const r = layer.radius * (layer.type === 'spiral' ? u : 1);
    const tube = layer.tube * (layer.fill ? Math.sqrt(w) : 1);
    x = (r + tube * Math.cos(b)) * Math.cos(angle); y = (u - 0.5) * layer.height + tube * Math.sin(b); z = (r + tube * Math.cos(b)) * Math.sin(angle);
  } else if (layer.type === 'box') {
    x = u - 0.5; y = v - 0.5; z = w - 0.5;
    if (!layer.fill) {
      const areas = [layer.height * layer.depth, layer.width * layer.depth, layer.width * layer.height];
      const area = 2 * (areas[0] + areas[1] + areas[2]);
      if (area > 0) {
        let position = u * area, face = 0;
        while (face < 5 && position >= areas[Math.floor(face / 2)]) { position -= areas[Math.floor(face / 2)]; face++; }
        const q = position / areas[Math.floor(face / 2)] - 0.5, r = v - 0.5;
        if (face < 2) { x = face === 0 ? -0.5 : 0.5; y = q; z = r; }
        else if (face < 4) { x = q; y = face === 2 ? -0.5 : 0.5; z = r; }
        else { x = q; y = r; z = face === 4 ? -0.5 : 0.5; }
      } else { x = u - 0.5; y = u - 0.5; z = u - 0.5; }
    }
    x *= layer.width; y *= layer.height; z *= layer.depth;
  } else if (layer.type === 'grid') {
    const columns = Math.min(count, Math.max(1, Math.ceil(Math.sqrt(count * Math.max(0.01, layer.width) / Math.max(0.01, layer.depth)))));
    const rows = Math.ceil(count / columns);
    x = (columns > 1 ? (index % columns) / (columns - 1) - 0.5 : 0) * layer.width;
    z = (rows > 1 ? Math.floor(index / columns) / (rows - 1) - 0.5 : 0) * layer.depth;
  } else if (layer.type === 'cone' || layer.type === 'cylinder') {
    const remaining = layer.type === 'cone' ? (layer.fill ? Math.cbrt(1 - u) : Math.sqrt(1 - u)) : 1;
    const height = layer.type === 'cone' ? 1 - remaining : u;
    const r = layer.radius * remaining * (layer.fill ? Math.sqrt(w) : 1);
    x = Math.cos(b + phase) * r; y = (height - 0.5) * layer.height; z = Math.sin(b + phase) * r;
  } else if (layer.type === 'line') {
    x = (u - 0.5) * layer.width;
    const r = layer.tube * (layer.fill ? Math.sqrt(w) : 1);
    y = Math.cos(b) * r; z = Math.sin(b) * r;
  } else if (layer.type === 'polygon') {
    const along = index / Math.max(1, count) * layer.sides;
    const edge = Math.floor(along), t = along - edge;
    const first = TAU * edge / layer.sides + phase + Math.PI / 2;
    const second = first + TAU / layer.sides;
    x = (Math.cos(first) * (1 - t) + Math.cos(second) * t) * layer.radius;
    y = (Math.sin(first) * (1 - t) + Math.sin(second) * t) * layer.radius;
    if (layer.fill) { const r = Math.sqrt(v); x *= r; y *= r; }
    else if (layer.tube > 0) {
      const normal = first + Math.PI / layer.sides;
      x += Math.cos(normal) * layer.tube * Math.cos(b);
      y += Math.sin(normal) * layer.tube * Math.cos(b);
      z = layer.tube * Math.sin(b);
    }
  } else if (layer.type === 'path') {
    const fraction = layer.path.closed ? index / Math.max(1, count) : count > 1 ? index / (count - 1) : 0.5;
    ({ x, y, z } = samplePath(pathTable || compilePath(layer.path), fraction, layer.tube, b, layer.fill ? Math.sqrt(w) : 1));
  } else if (layer.type === 'pointcloud') {
    const point = layer.path.points[Math.min(layer.path.points.length - 1, Math.floor(u * layer.path.points.length))];
    ({ x, y, z } = point);
  }
  const twist = layer.twist * (u - 0.5) * RAD;
  [x, z] = [x * Math.cos(twist) + z * Math.sin(twist), -x * Math.sin(twist) + z * Math.cos(twist)];
  const taper = 1 + layer.taper / 100 * (2 * u - 1);
  x *= taper; z *= taper;
  x += layer.scatter * (2 * fract((index + 0.5) * SCATTER_X) - 1);
  y += layer.scatter * (2 * fract((index + 0.5) * SCATTER_Y) - 1);
  z += layer.scatter * (2 * fract((index + 0.5) * SCATTER_Z) - 1);
  y += layer.wave * Math.sin(TAU * u * layer.waveCount + time * layer.waveSpeed * TAU + phase + layer.wavePhase * RAD);
  const pulse = 1 + layer.pulse / 100 * Math.sin(time * layer.pulseSpeed * TAU + phase + layer.pulsePhase * RAD);
  x *= layer.scale.x * pulse; y *= layer.scale.y * pulse; z *= layer.scale.z * pulse;
  const rx = (layer.rotation.x + time * layer.spinX) * RAD;
  const ry = (layer.rotation.y + time * layer.spin) * RAD;
  const rz = (layer.rotation.z + time * layer.spinZ) * RAD;
  [y, z] = [y * Math.cos(rx) - z * Math.sin(rx), y * Math.sin(rx) + z * Math.cos(rx)];
  [x, z] = [x * Math.cos(ry) + z * Math.sin(ry), -x * Math.sin(ry) + z * Math.cos(ry)];
  [x, y] = [x * Math.cos(rz) - y * Math.sin(rz), x * Math.sin(rz) + y * Math.cos(rz)];
  const orbit = (time * layer.orbitSpeed + layer.orbitPhase) * RAD;
  const tiltX = layer.orbitTiltX * RAD, tiltZ = layer.orbitTiltZ * RAD;
  let ox = layer.orbitRadius * Math.cos(orbit), oy = 0, oz = layer.orbitRadius * layer.orbitAspect * Math.sin(orbit);
  [oy, oz] = [-oz * Math.sin(tiltX), oz * Math.cos(tiltX)];
  [ox, oy] = [ox * Math.cos(tiltZ) - oy * Math.sin(tiltZ), ox * Math.sin(tiltZ) + oy * Math.cos(tiltZ)];
  x += ox; y += oy + layer.bobAmount * Math.sin(time * layer.bobSpeed * TAU + layer.bobPhase * RAD); z += oz;
  return { x: x + layer.position.x, y: y + layer.position.y, z: z + layer.position.z, color: layer.color, layerId: layer.id };
}

export function sampleProject(project, time = 0, values = {}) {
  const normalized = normalizeProject(project);
  if (typeof time !== 'number' || !Number.isFinite(time)) error('Preview time must be a finite number.');
  const layers = resolveLayers(normalized, values);
  const weight = layers.reduce((sum, layer) => sum + layer.weight, 0);
  if (!weight) return [];
  const points = [];
  let cumulative = 0, start = 0;
  for (let i = 0; i < layers.length; i++) {
    const layer = layers[i]; cumulative += layer.weight;
    const end = i === layers.length - 1 ? normalized.parts : Math.floor(cumulative / weight * normalized.parts);
    const count = end - start;
    const pathTable = layer.type === 'path' ? compilePath(layer.path) : null;
    for (let index = 0; index < count; index++) points.push(sampleLayer(layer, index, count, time, pathTable));
    start = end;
  }
  return points;
}
