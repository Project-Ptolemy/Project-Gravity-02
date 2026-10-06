// Flow changes path position, never the original slot's individual phase.
// Tiny collapsed outlines stay still rather than dividing by a near-zero size.
export function flowFraction(base, speed, time, length, closed) {
  if (speed === 0 || length <= 1e-9) return base;
  const cycle = closed ? 1 : 2;
  const period = cycle * length / Math.abs(speed);
  const offset = Number.isFinite(period) ? (time % period) * speed / length : time * speed / length;
  const value = base + offset;
  const wrapped = value - Math.floor(value / cycle) * cycle;
  return closed ? wrapped : 1 - Math.abs(1 - wrapped);
}

const frames = new WeakMap();
const average = (a, b) => a.map((value, index) => (value + b[index]) / 2);

// Use shared vertex offset frames, including one shared closed-seam frame.
// Interpolating these bounded vectors is continuous even at a sharp reversal
// or a perpendicular-frame branch. Corners may narrow the tube; normalizing
// an interpolated vector would instead introduce singular flips there.
function offsetFrames(table, closed) {
  let cached = frames.get(table);
  if (cached?.closed === closed) return cached.values;
  const segmentFrames = [];
  for (let index = 1; index < table.points.length; index++) {
    const p = table.points[index - 1], q = table.points[index];
    const dx = q.x - p.x, dy = q.y - p.y, dz = q.z - p.z;
    const length = Math.hypot(dx, dy, dz);
    const tx = dx / length, ty = dy / length, tz = dz / length;
    // Choose from raw components: hypot and Lua sqrt can round a normalized
    // tangent to opposite sides of a threshold such as abs(tz) < 0.9.
    const ax = Math.abs(dx), ay = Math.abs(dy), az = Math.abs(dz);
    let nx, ny, nz;
    if (az <= ax && az <= ay) [nx, ny, nz] = [ty, -tx, 0];
    else if (ay <= ax) [nx, ny, nz] = [-tz, 0, tx];
    else [nx, ny, nz] = [0, tz, -ty];
    const normal = Math.hypot(nx, ny, nz);
    nx /= normal; ny /= normal; nz /= normal;
    segmentFrames.push([nx, ny, nz, ty * nz - tz * ny, tz * nx - tx * nz, tx * ny - ty * nx]);
  }
  const first = closed ? average(segmentFrames.at(-1), segmentFrames[0]) : segmentFrames[0];
  const values = [first];
  for (let index = 1; index < segmentFrames.length; index++) values.push(average(segmentFrames[index - 1], segmentFrames[index]));
  values.push(closed ? first : segmentFrames.at(-1));
  frames.set(table, { closed, values });
  return values;
}

/** Arc-length sample with continuous, bounded tube offsets for active flow. */
export function sampleFlowPath(table, fraction, closed, tube = 0, angle = 0, radial = 1) {
  if (!table.points.length) return { x: 0, y: 0, z: 0 };
  if (table.points.length === 1 || table.total <= 1e-9) return { ...table.points[0] };
  const target = Math.max(0, Math.min(1, fraction)) * table.total;
  let low = 1, high = table.lengths.length - 1;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (table.lengths[middle] < target) low = middle + 1; else high = middle;
  }
  const p = table.points[low - 1], q = table.points[low];
  const length = table.lengths[low] - table.lengths[low - 1];
  const t = length > 0 ? (target - table.lengths[low - 1]) / length : 0;
  const point = { x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t, z: p.z + (q.z - p.z) * t };
  if (tube > 0) {
    const frame = offsetFrames(table, closed), a = frame[low - 1], b = frame[low];
    const c = tube * radial * Math.cos(angle), s = tube * radial * Math.sin(angle);
    for (const [index, axis] of ['x', 'y', 'z'].entries()) point[axis] += (a[index] * (1 - t) + b[index] * t) * c + (a[index + 3] * (1 - t) + b[index + 3] * t) * s;
  }
  return point;
}
