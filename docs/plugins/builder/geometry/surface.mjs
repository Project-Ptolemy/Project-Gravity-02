import { compilePath, samplePath, MAX_PATH_POINTS, PATH_COORDINATE_LIMIT } from './path.mjs';

const AXES = ['x', 'y', 'z'];
const RAD = Math.PI / 180;
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const fail = message => { throw new Error(message); };

function number(value, fallback, min, max, label) {
  if (value === undefined) return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
    fail(`${label} must be a finite number between ${min} and ${max}.`);
  }
  return value;
}
function vector(value, fallback, label) {
  if (value === undefined && fallback) return { ...fallback };
  if (!plain(value) || AXES.some(axis => value[axis] === undefined)) fail(`${label} needs X, Y and Z coordinates.`);
  return Object.fromEntries(AXES.map(axis => [axis, number(value[axis], 0, -PATH_COORDINATE_LIMIT, PATH_COORDINATE_LIMIT, `${label} ${axis.toUpperCase()}`)]));
}
function count(value, fallback, min, label) {
  const result = number(value, fallback, min, 2048, label);
  if (!Number.isInteger(result)) fail(`${label} must be a whole number.`);
  return result;
}
function boolean(value, fallback, label) {
  if (value === undefined) return fallback;
  if (typeof value !== 'boolean') fail(`${label} must be true or false.`);
  return value;
}

/** Bake a path into editable surface points in the source layer's local space.
 * Extrusions produce outline walls, without end caps or a filled volume.
 * Revolutions turn a profile around a local axis through `pivot`.
 * Neither the source nor options are modified; callers add the returned spec
 * as a fresh layer so the profile remains available for future variations.
 */
export function createPathSurface(layer, options = {}) {
  if (!plain(layer) || layer.type !== 'path' || !plain(layer.path)) fail('Select an editable path to create a surface.');
  if (!plain(options)) fail('Surface settings must be an object.');
  const input = layer.path;
  if (!Array.isArray(input.points) || input.points.length < 2 || input.points.length > MAX_PATH_POINTS) {
    fail('The source path must have 2 to 4,096 points.');
  }
  const path = {
    points: input.points.map((point, i) => vector(point, null, `Path point ${i + 1}`)),
    closed: boolean(input.closed, false, 'Closed path'),
    smooth: boolean(input.smooth, false, 'Smooth path'),
  };
  const mode = options.mode ?? 'extrude';
  if (!['extrude', 'revolve'].includes(mode)) fail('Choose extrude or revolve.');
  const axis = options.axis ?? (mode === 'extrude' ? 'z' : 'y');
  if (!AXES.includes(axis) && !(mode === 'extrude' && axis === 'custom')) fail('Choose an X, Y or Z axis, or a custom extrusion direction.');
  const samples = count(options.samples, 64, path.closed ? 3 : 2, 'Samples along the path');
  const sweep = mode === 'revolve' ? number(options.sweep, 360, -360, 360, 'Sweep angle') : 0;
  if (mode === 'revolve' && sweep === 0) fail('Sweep angle must be nonzero.');
  const fullTurn = mode === 'revolve' && Math.abs(sweep) === 360;
  const rows = count(options.rows, 16, fullTurn ? 3 : 2, 'Surface rows');
  if (samples * rows > MAX_PATH_POINTS) fail('A surface can contain at most 4,096 points. Reduce samples or rows.');
  const table = compilePath(path);
  if (!(table.total > 0) || !Number.isFinite(table.total)) fail('The source path needs at least two distinct points.');
  const profile = Array.from({ length: samples }, (_, i) => samplePath(table, i / (path.closed ? samples : samples - 1)));
  let offset, pivot, start, centered, depth;
  if (mode === 'extrude') {
    depth = number(options.depth, 30, -PATH_COORDINATE_LIMIT, PATH_COORDINATE_LIMIT, 'Extrusion depth');
    if (depth === 0) fail('Extrusion depth must be nonzero.');
    centered = boolean(options.centered, false, 'Centered extrusion');
    const direction = axis === 'custom'
      ? vector(options.direction, { x: 0, y: 0, z: 1 }, 'Extrusion direction')
      : Object.fromEntries(AXES.map(key => [key, key === axis ? 1 : 0]));
    const length = Math.hypot(direction.x, direction.y, direction.z);
    if (length === 0) fail('The extrusion direction must have a nonzero component.');
    offset = Object.fromEntries(AXES.map(key => [key, direction[key] / length * depth]));
  } else {
    pivot = vector(options.pivot, { x: 0, y: 0, z: 0 }, 'Revolution pivot');
    start = number(options.start, 0, -360, 360, 'Starting angle');
    const radialAxes = AXES.filter(key => key !== axis);
    if (profile.every(point => radialAxes.every(key => point[key] === pivot[key]))) {
      fail('The profile must extend away from the revolution axis. Move the pivot or edit the path.');
    }
  }
  const points = [];
  for (let row = 0; row < rows; row++) {
    // A full revolution has a periodic seam. Partial sweeps and extrusions
    // include both ends, while full turns omit a duplicate last row.
    const fraction = row / (fullTurn ? rows : rows - 1);
    const angle = (start + fraction * sweep) * RAD;
    const cos = mode === 'revolve' ? Math.cos(angle) : 0;
    const sin = mode === 'revolve' ? Math.sin(angle) : 0;
    for (const point of profile) {
      let result;
      if (mode === 'extrude') {
        const distance = fraction - (centered ? 0.5 : 0);
        result = Object.fromEntries(AXES.map(key => [key, point[key] + distance * offset[key]]));
      } else {
        const x = point.x - pivot.x, y = point.y - pivot.y, z = point.z - pivot.z;
        if (axis === 'x') result = { x: point.x, y: pivot.y + y * cos - z * sin, z: pivot.z + y * sin + z * cos };
        if (axis === 'y') result = { x: pivot.x + x * cos + z * sin, y: point.y, z: pivot.z - x * sin + z * cos };
        if (axis === 'z') result = { x: pivot.x + x * cos - y * sin, y: pivot.y + x * sin + y * cos, z: point.z };
      }
      for (const key of AXES) {
        const value = result[key];
        // Trig at quarter turns can overshoot an exact boundary by a few ULPs.
        if (!Number.isFinite(value) || Math.abs(value) > PATH_COORDINATE_LIMIT + 1e-9) {
          fail('The generated surface exceeds the +/-5,000 coordinate limit. Reduce its depth, pivot offset or profile size.');
        }
        result[key] = Math.max(-PATH_COORDINATE_LIMIT, Math.min(PATH_COORDINATE_LIMIT, value));
      }
      points.push(result);
    }
  }
  const suffix = mode === 'extrude' ? ' walls' : ' revolved';
  const spec = {
    type: 'pointcloud', name: (layer.name || 'Path').slice(0, 80 - suffix.length) + suffix,
    path: { points, closed: false, smooth: false },
    tube: 0, spin: 0, fill: false,
  };
  for (const group of ['position', 'rotation', 'scale']) if (layer[group] !== undefined) spec[group] = { ...layer[group] };
  if (layer.color !== undefined) spec.color = layer.color;
  return spec;
}
