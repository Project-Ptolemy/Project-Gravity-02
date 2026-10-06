// Shared, deterministic path geometry for the editor, preview and Lua exporter.
export const MAX_PATH_POINTS = 4096;
export const PATH_COORDINATE_LIMIT = 5000;
const CURVE_STEPS = 16;
const cache = new Map();
let cachedPoints = 0;
const copy = point => ({ x: point.x, y: point.y, z: point.z });

export function flattenPath(path) {
  const points = path.points;
  if (!points.length) return [];
  if (!path.smooth || points.length < 3) {
    const result = points.map(copy);
    if (path.closed && points.length > 1) result.push(copy(points[0]));
    return result;
  }
  const result = [copy(points[0])];
  const at = index => points[path.closed ? (index + points.length) % points.length : Math.max(0, Math.min(points.length - 1, index))];
  const segments = path.closed ? points.length : points.length - 1;
  for (let segment = 0; segment < segments; segment++) {
    const p0 = at(segment - 1), p1 = at(segment), p2 = at(segment + 1), p3 = at(segment + 2);
    for (let step = 1; step <= CURVE_STEPS; step++) {
      const t = step / CURVE_STEPS, t2 = t * t, t3 = t2 * t;
      const point = {};
      for (const axis of ['x', 'y', 'z']) {
        // Preserve exact endpoints and constant coordinates. Cancellation in
        // decimal-valued coincident nodes must not create a tiny false tangent.
        point[axis] = step === CURVE_STEPS ? p2[axis]
          : p0[axis] === p1[axis] && p1[axis] === p2[axis] && p2[axis] === p3[axis] ? p1[axis]
            : 0.5 * (2 * p1[axis] + (-p0[axis] + p2[axis]) * t
              + (2 * p0[axis] - 5 * p1[axis] + 4 * p2[axis] - p3[axis]) * t2
              + (-p0[axis] + 3 * p1[axis] - 3 * p2[axis] + p3[axis]) * t3);
      }
      result.push(point);
    }
  }
  return result;
}

export function compilePath(path) {
  // Content keys survive project normalization and detect edits to any node.
  // Limit retained tables as well as entries so large imports do not accumulate.
  const key = JSON.stringify([path.closed, path.smooth, path.points]);
  if (cache.has(key)) {
    const value = cache.get(key);
    cache.delete(key); cache.set(key, value);
    return value;
  }
  const flattened = flattenPath(path), points = [], lengths = [];
  let total = 0;
  for (const point of flattened) {
    const last = points[points.length - 1];
    const length = last ? Math.hypot(point.x - last.x, point.y - last.y, point.z - last.z) : 0;
    if (last && length === 0) continue;
    total += length; points.push(point); lengths.push(total);
  }
  const result = { points, lengths, total };
  cache.set(key, result); cachedPoints += points.length;
  while (cache.size > 32 || cachedPoints > 262144) {
    const oldest = cache.keys().next().value;
    cachedPoints -= cache.get(oldest).points.length; cache.delete(oldest);
  }
  return result;
}

export function samplePath(table, fraction, tube = 0, angle = 0, radial = 1) {
  if (!table.points.length) return { x: 0, y: 0, z: 0 };
  if (table.points.length === 1 || table.total === 0) return copy(table.points[0]);
  const target = Math.max(0, Math.min(1, fraction)) * table.total;
  let low = 1, high = table.lengths.length - 1;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (table.lengths[middle] < target) low = middle + 1;
    else high = middle;
  }
  const p = table.points[low - 1], q = table.points[low];
  const length = table.lengths[low] - table.lengths[low - 1];
  const t = length > 0 ? (target - table.lengths[low - 1]) / length : 0;
  const point = { x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t, z: p.z + (q.z - p.z) * t };
  if (tube > 0 && length > 0) {
    const tx = (q.x - p.x) / length, ty = (q.y - p.y) / length, tz = (q.z - p.z) / length;
    // A stable perpendicular frame works for paths in every drawing plane.
    let nx = Math.abs(tz) < 0.9 ? ty : -tz;
    let ny = Math.abs(tz) < 0.9 ? -tx : 0;
    let nz = Math.abs(tz) < 0.9 ? 0 : tx;
    const normalLength = Math.hypot(nx, ny, nz);
    nx /= normalLength; ny /= normalLength; nz /= normalLength;
    const bx = ty * nz - tz * ny, by = tz * nx - tx * nz, bz = tx * ny - ty * nx;
    const c = tube * radial * Math.cos(angle), s = tube * radial * Math.sin(angle);
    point.x += nx * c + bx * s; point.y += ny * c + by * s; point.z += nz * c + bz * s;
  }
  return point;
}
