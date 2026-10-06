import { normalizeProject, getProperty, setProperty } from '../model.mjs';

const AXES = ['x', 'y', 'z'];
const RAD = Math.PI / 180;
const clone = value => JSON.parse(JSON.stringify(value));
const fail = message => { throw new Error(message); };
function number(value, fallback, label) {
  if (value === undefined) return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value)) fail(`${label} must be a finite number.`);
  return value;
}
function vector(value, label) {
  if (value !== undefined && (!value || typeof value !== 'object' || Array.isArray(value))) fail(`${label} must contain X, Y and Z values.`);
  return Object.fromEntries(AXES.map(axis => [axis, number(value?.[axis], 0, `${label} ${axis.toUpperCase()}`)]));
}
function matrix(rotation) {
  const [x, y, z] = AXES.map(axis => rotation[axis] * RAD);
  const cx = Math.cos(x), sx = Math.sin(x), cy = Math.cos(y), sy = Math.sin(y), cz = Math.cos(z), sz = Math.sin(z);
  // Same local X, then Y, then Z rotation order used by the shape sampler.
  return [[cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx],
    [sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx], [-sy, cy * sx, cy * cx]];
}
function rotate(point, transform) {
  return Object.fromEntries(AXES.map((axis, row) => [axis, AXES.reduce((sum, key, column) => sum + transform[row][column] * point[key], 0)]));
}
function multiply(a, b) {
  return a.map(row => b[0].map((_, column) => row.reduce((sum, value, index) => sum + value * b[index][column], 0)));
}
function euler(transform) {
  const y = Math.asin(Math.max(-1, Math.min(1, -transform[2][0])));
  const regular = Math.abs(Math.cos(y)) > 1e-8;
  return {
    x: (regular ? Math.atan2(transform[2][1], transform[2][2]) : Math.atan2(-transform[1][2], transform[1][1])) / RAD,
    y: y / RAD,
    z: (regular ? Math.atan2(transform[1][0], transform[0][0]) : 0) / RAD,
  };
}
function nextId(prefix, used) {
  let index = 1;
  while (used.has(`${prefix}-${index}`)) index++;
  const id = `${prefix}-${index}`; used.add(id); return id;
}
function tidy(value) {
  // Editor sliders use six decimal places. This also removes trigonometric
  // noise at quarter turns, keeping transform control defaults valid.
  return Math.round(value * 1e6) / 1e6;
}

/**
 * Make independent copies without changing the source project.
 * count is NEW copies. A line uses i * positionStep / rotationStep.
 * Radial copies orbit a world axis. A local pivot is scaled and rotated by
 * the source's default transform, then translated to world coordinates.
 * Partial sweeps include the endpoint; +/-360 excludes the repeated source.
 * Bound controls keep their names/ranges, expanding ranges when necessary
 * to contain transformed defaults. All new transforms use six decimals.
 */
export function createArrangement(input, layerId, options = {}) {
  const project = normalizeProject(input);
  const source = project.layers.find(layer => layer.id === layerId);
  if (!source) fail('Choose a layer to repeat.');
  const mode = options.mode ?? 'line';
  if (!['line', 'radial'].includes(mode)) fail('Choose a line or radial arrangement.');
  const count = number(options.count, 3, 'Copy count');
  if (!Number.isInteger(count) || count < 1 || count > 63) fail('Add between 1 and 63 copies.');
  if (project.layers.length + count > 64) fail(`This adds ${count} layers, but the scene has room for ${64 - project.layers.length}. No copies were added.`);
  const sourceControls = project.controls.filter(control => control.layerId === layerId);
  if (project.controls.length + sourceControls.length * count > 96) fail(`These copies need ${sourceControls.length * count} controls, but the scene has room for ${96 - project.controls.length}. No copies were added.`);
  const base = clone(source);
  for (const control of sourceControls) if (control.type !== 'button') setProperty(base, control.property, control.default);
  const positionStep = vector(options.positionStep, 'Position step'), rotationStep = vector(options.rotationStep, 'Rotation step');
  const pivot = vector(options.pivot, 'Pivot');
  const axis = options.axis ?? 'y', pivotSpace = options.pivotSpace ?? 'world';
  const sweep = number(options.sweep, 360, 'Sweep');
  if (!AXES.includes(axis)) fail('Choose the X, Y or Z radial axis.');
  if (!['world', 'local'].includes(pivotSpace)) fail('Choose a world or source-local pivot.');
  if (sweep < -360 || sweep > 360) fail('Sweep must be between -360 and 360 degrees.');
  if (options.rotateCopies !== undefined && typeof options.rotateCopies !== 'boolean') fail('Rotate copies must be true or false.');
  const sourceRotation = matrix(base.rotation);
  const localPivot = rotate(Object.fromEntries(AXES.map(key => [key, pivot[key] * base.scale[key]])), sourceRotation);
  const center = pivotSpace === 'local' ? Object.fromEntries(AXES.map(key => [key, base.position[key] + localPivot[key]])) : pivot;
  const layerIds = new Set(project.layers.map(layer => layer.id)), controlIds = new Set(project.controls.map(control => control.id));
  const layers = [], controls = [];
  for (let index = 1; index <= count; index++) {
    const layer = clone(base);
    layer.id = nextId('repeat-layer', layerIds);
    const suffix = ` copy ${index}`;
    layer.name = source.name.slice(0, 80 - suffix.length) + suffix;
    if (mode === 'line') {
      for (const key of AXES) {
        layer.position[key] += index * positionStep[key];
        layer.rotation[key] += index * rotationStep[key];
      }
    } else {
      const angle = index * sweep / (Math.abs(sweep) === 360 ? count + 1 : count);
      const turn = matrix({ x: 0, y: 0, z: 0, [axis]: angle });
      const offset = rotate(Object.fromEntries(AXES.map(key => [key, base.position[key] - center[key]])), turn);
      layer.position = Object.fromEntries(AXES.map(key => [key, center[key] + offset[key]]));
      if (options.rotateCopies !== false) layer.rotation = euler(multiply(turn, sourceRotation));
    }
    for (const group of ['position', 'rotation']) for (const key of AXES) {
      const value = layer[group][key], limit = group === 'position' ? 5000 : 360;
      if (!Number.isFinite(value) || value < -limit - 1e-9 || value > limit + 1e-9) fail(`Copy ${index} ${group} ${key.toUpperCase()} must stay between ${-limit} and ${limit}. Reduce the count or step, or move the pivot. No copies were added.`);
      layer[group][key] = tidy(value);
    }
    for (const sourceControl of sourceControls) {
      const control = { ...sourceControl, id: nextId('repeat-control', controlIds), layerId: layer.id };
      if (control.type !== 'button' && control.type !== 'toggle' && /^(position|rotation)\.[xyz]$/.test(control.property)) {
        control.default = getProperty(layer, control.property);
        control.min = Math.min(control.min, control.default);
        control.max = Math.max(control.max, control.default);
      }
      controls.push(control);
    }
    layers.push(layer);
  }
  const validated = normalizeProject({ ...project, layers: [...project.layers, ...layers], controls: [...project.controls, ...controls] });
  return { layers: validated.layers.slice(project.layers.length), controls: validated.controls.slice(project.controls.length) };
}
