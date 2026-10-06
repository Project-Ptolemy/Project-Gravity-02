import { PATH_COORDINATE_LIMIT } from './path.mjs';

const AXES = ['x', 'y', 'z'];
const rounded = value => Math.round(value * 10000) / 10000 || 0;
const clone = points => points.map(point => ({ ...point }));
const indicesOf = (points, indices) => [...new Set(indices)].filter(index => Number.isInteger(index) && index >= 0 && index < points.length);

export function selectionCenter(points, indices) {
  const selected = indicesOf(points, indices);
  const center = { x: 0, y: 0, z: 0 };
  if (selected.length) for (const axis of AXES) center[axis] = selected.reduce((sum, index) => sum + points[index][axis], 0) / selected.length;
  return center;
}

function checked(point) {
  if (AXES.some(axis => !Number.isFinite(point[axis]) || Math.abs(point[axis]) > PATH_COORDINATE_LIMIT + 1e-8)) {
    throw new RangeError(`Keep every coordinate between −${PATH_COORDINATE_LIMIT} and ${PATH_COORDINATE_LIMIT}. Reduce the transform and try again.`);
  }
  return Object.fromEntries(AXES.map(axis => [axis, rounded(point[axis])]));
}

/** Scale around the selected centroid, rotate X → Y → Z, then translate. Never mutates input. */
export function transformVertices(points, indices, { translation = {}, rotation = {}, scale = {} } = {}) {
  const selected = indicesOf(points, indices);
  const center = selectionCenter(points, selected);
  const values = Object.fromEntries([['translation', translation, 0], ['rotation', rotation, 0], ['scale', scale, 1]].map(([key, source, fallback]) => {
    const value = Object.fromEntries(AXES.map(axis => [axis, source[axis] ?? fallback]));
    if (AXES.some(axis => !Number.isFinite(value[axis]))) throw new TypeError('Enter finite numbers for every transform coordinate.');
    return [key, value];
  }));
  const angles = AXES.map(axis => (values.rotation[axis] % 360) * Math.PI / 180);
  const [cx, cy, cz] = angles.map(Math.cos), [sx, sy, sz] = angles.map(Math.sin);
  const rotationRows = [
    [cy * cz, sx * sy * cz - cx * sz, cx * sy * cz + sx * sz],
    [cy * sz, sx * sy * sz + cx * cz, cx * sy * sz - sx * cz],
    [-sy, sx * cy, cx * cy],
  ];
  const unchangedAxes = AXES.filter((axis, row) => values.scale[axis] === 1 && values.translation[axis] === 0
    && rotationRows[row].every((value, column) => Math.abs(value - (row === column ? 1 : 0)) < 1e-12));
  const result = clone(points);
  for (const index of selected) {
    let x = (points[index].x - center.x) * values.scale.x;
    let y = (points[index].y - center.y) * values.scale.y;
    let z = (points[index].z - center.z) * values.scale.z;
    [y, z] = [y * cx - z * sx, y * sx + z * cx];
    [x, z] = [x * cy + z * sy, -x * sy + z * cy];
    [x, y] = [x * cz - y * sz, x * sz + y * cz];
    result[index] = checked({ x: x + center.x + values.translation.x, y: y + center.y + values.translation.y, z: z + center.z + values.translation.z });
    // Planar moves and rotations must preserve untouched imported depth exactly.
    for (const axis of unchangedAxes) result[index][axis] = points[index][axis];
  }
  return result;
}

/** Limit a shared translation as a whole so dragging never distorts a selection. */
export function boundedTranslation(points, indices, translation) {
  const selected = indicesOf(points, indices);
  const result = { x: 0, y: 0, z: 0 };
  for (const axis of AXES) {
    const value = translation[axis] ?? 0;
    if (!Number.isFinite(value)) throw new TypeError('Enter finite numbers for every transform coordinate.');
    let low = -Infinity, high = Infinity;
    for (const index of selected) {
      low = Math.max(low, -PATH_COORDINATE_LIMIT - points[index][axis]);
      high = Math.min(high, PATH_COORDINATE_LIMIT - points[index][axis]);
    }
    result[axis] = Math.max(low, Math.min(high, value));
  }
  return result;
}

export function flattenVertices(points, indices, axis, value) {
  if (!AXES.includes(axis)) throw new TypeError('Choose the X, Y or Z axis.');
  if (!Number.isFinite(value) || Math.abs(value) > PATH_COORDINATE_LIMIT) throw new RangeError(`Enter a coordinate between −${PATH_COORDINATE_LIMIT} and ${PATH_COORDINATE_LIMIT}.`);
  const result = clone(points);
  for (const index of indicesOf(points, indices)) result[index] = { ...points[index], [axis]: rounded(value) };
  return result;
}
