import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createPathSurface } from '../docs/plugins/builder/geometry/surface.mjs';
import { compilePath, samplePath } from '../docs/plugins/builder/geometry/path.mjs';
import { createLayer, normalizeProject, sampleProject } from '../docs/plugins/builder/model.mjs';
import { exportLua, luaString } from '../docs/plugins/builder/exporter.mjs';

const point = (x, y, z) => ({ x, y, z });
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-8, `${a} ~= ${b}`);
const nearPoint = (a, b) => { for (const key of ['x', 'y', 'z']) near(a[key], b[key]); };
const source = (points, path = {}, props = {}) => createLayer('path', { name: 'My profile', path: { points, ...path }, position: point(0, 0, 0), ...props });
const line = source([point(0, 0, 0), point(12, 0, 0)]);
const projectOf = (layers, parts = 128) => normalizeProject({ version: 1, name: 'Surface test', layers, parts, controls: [] });

// Depth is measured in local studs on any drawing plane, and both extrusion
// endpoints are represented. A custom direction has a normalized distance.
for (const axis of ['x', 'y', 'z']) {
  for (const depth of [-12, 12]) for (const centered of [false, true]) {
    const result = createPathSurface(line, { axis, depth, centered, samples: 3, rows: 3 });
    assert.equal(result.type, 'pointcloud'); assert.equal(result.path.points.length, 9);
    assert.equal(result.path.closed, false); assert.equal(result.path.smooth, false);
    for (let row = 0; row < 3; row++) for (let i = 0; i < 3; i++) {
      const expected = point(i * 6, 0, 0); expected[axis] += depth * (row / 2 - (centered ? .5 : 0));
      nearPoint(result.path.points[row * 3 + i], expected);
    }
  }
}
const diagonal = createPathSurface(line, { axis: 'custom', direction: point(0, 3, 4), depth: 10, samples: 2, rows: 2 });
nearPoint(diagonal.path.points[2], point(0, 6, 8));
nearPoint(diagonal.path.points[3], point(12, 6, 8));

// Sampling respects source closure, curve smoothing and arc length.
const square = source([point(-4, -4, 0), point(4, -4, 0), point(4, 4, 0), point(-4, 4, 0)], { closed: true });
const walls = createPathSurface(square, { depth: 10, samples: 4, rows: 2 });
assert.deepEqual(walls.path.points.slice(0, 4), square.path.points);
assert.deepEqual(walls.path.points.slice(4), square.path.points.map(p => ({ ...p, z: 10 })));
for (const closed of [false, true]) {
  const curved = source([point(-10, 3, 0), point(2, 9, 15), point(10, 7, 4)], { smooth: true, closed });
  const result = createPathSurface(curved, { axis: 'y', depth: 5, samples: 7, rows: 2 });
  const table = compilePath(curved.path);
  for (let i = 0; i < 7; i++) nearPoint(result.path.points[i], samplePath(table, i / (closed ? 7 : 6)));
}

// Revolutions match the builder's right-hand rotations for every axis,
// including pivot offsets, partial sweeps, negative sweeps and a start angle.
const origin = point(10, -4, 7);
for (const axis of ['x', 'y', 'z']) {
  const start = point(12, -1, 11), end = point(14, 2, 15);
  const profile = source([start, end]);
  const result = createPathSurface(profile, { mode: 'revolve', axis, pivot: origin, samples: 2, rows: 2, sweep: 90 });
  nearPoint(result.path.points[0], start); nearPoint(result.path.points[1], end);
  const expected = axis === 'x' ? point(12, -8, 10) : axis === 'y' ? point(14, -1, 5) : point(7, -2, 11);
  nearPoint(result.path.points[2], expected);
  const reversed = createPathSurface(profile, { mode: 'revolve', axis, pivot: origin, samples: 2, rows: 2, start: 90, sweep: -90 });
  nearPoint(reversed.path.points[0], expected); nearPoint(reversed.path.points[2], start);
}
const radialProfile = source([point(5, -10, 0), point(5, 10, 0)]);
const revolved = createPathSurface(radialProfile, { mode: 'revolve', samples: 2, rows: 4 });
for (const [i, expected] of [point(5, -10, 0), point(0, -10, -5), point(-5, -10, 0), point(0, -10, 5)].entries()) {
  nearPoint(revolved.path.points[i * 2], expected);
}
const reverseTurn = createPathSurface(radialProfile, { mode: 'revolve', samples: 2, rows: 4, sweep: -360 });
nearPoint(reverseTurn.path.points[2], point(0, -10, 5));
const touchingAxis = source([point(0, -10, 0), point(5, 10, 0)]);
assert.ok(createPathSurface(touchingAxis, { mode: 'revolve' }).path.points.every(p => Object.values(p).every(Number.isFinite)), 'profile tips on the axis remain finite');

// Surface limits reject invalid geometry instead of silently cropping it.
assert.equal(createPathSurface(line, { samples: 64, rows: 64 }).path.points.length, 4096);
assert.throws(() => createPathSurface(line, { samples: 65, rows: 64 }), /4,096/);
for (const key of ['samples', 'rows']) for (const value of [0, 1, 2.5, 2049, Infinity, NaN, '4', null]) {
  assert.throws(() => createPathSurface(line, { [key]: value }), /whole number|finite number/);
}
assert.throws(() => createPathSurface(square, { samples: 2 }), /Samples/);
assert.throws(() => createPathSurface(radialProfile, { mode: 'revolve', rows: 2 }), /rows/);
for (const key of ['depth', 'start', 'sweep']) for (const value of [Infinity, NaN, '3', null, 5001]) {
  assert.throws(() => createPathSurface(line, { mode: key === 'depth' ? 'extrude' : 'revolve', [key]: value }), /finite number/);
}
for (const [options, message] of [
  [{ mode: 'solid' }, /extrude or revolve/], [{ axis: 'w' }, /axis/], [{ depth: 0 }, /nonzero/],
  [{ centered: 1 }, /true or false/], [{ axis: 'custom', direction: point(0, 0, 0) }, /nonzero/],
  [{ axis: 'custom', direction: { x: 1 } }, /coordinates/], [{ mode: 'revolve', sweep: 0 }, /nonzero/],
  [{ mode: 'revolve', axis: 'custom' }, /axis/], [{ mode: 'revolve', pivot: point(5001, 0, 0) }, /finite number/],
]) assert.throws(() => createPathSurface(line, options), message);
assert.throws(() => createPathSurface(source([point(0, 0, 0), point(0, 0, 0)])), /distinct/);
assert.throws(() => createPathSurface(source([point(0, 0, 0), point(0, 10, 0)]), { mode: 'revolve', axis: 'y' }), /extend away/);
assert.throws(() => createPathSurface(source([point(0, 0, 4999), point(1, 0, 4999)])), /coordinate limit/);
assert.throws(() => createPathSurface(source([point(5000, 0, 5000), point(5000, 1, 5000)]), { mode: 'revolve', rows: 8 }), /coordinate limit/);
assert.throws(() => createPathSurface(source([point(4000, 0, 0), point(4000, 5, 0)]), { mode: 'revolve', pivot: point(-4000, 0, 0) }), /coordinate limit/);
const boundary = createPathSurface(source([point(5000, 0, 0), point(5000, 1, 0)]), { mode: 'revolve', rows: 4, samples: 2 });
assert.ok(boundary.path.points.every(p => Object.values(p).every(n => Number.isFinite(n) && Math.abs(n) <= 5000)));
for (const invalid of [null, {}, { type: 'pointcloud', path: line.path }, { type: 'path', path: {} },
  { type: 'path', path: { points: [null, point(1, 0, 0)] } }, { type: 'path', path: { points: [undefined, point(1, 0, 0)] } },
  { type: 'path', path: { points: [point(NaN, 0, 0), point(1, 0, 0)] } },
  { type: 'path', path: { points: [point(0, 0, 0), point(1, 0, 0)], closed: 1 } },
]) assert.throws(() => createPathSurface(invalid));

// Derived layers retain static placement, start with no motion, and neither
// share data nor IDs with the original. JSON reopening preserves every point.
const transformed = source(square.path.points, { closed: true }, {
  position: point(8, 30, -14), rotation: point(25, -32, 61), scale: point(.6, 1.8, 2.3), color: '#aabbcc',
  spin: 45, spinX: -12, wave: 3, pulse: 22, orbitRadius: 12, bobAmount: 5, twist: 20, taper: 10, scatter: 3,
});
const snapshot = JSON.stringify(transformed);
const spec = createPathSurface(transformed, { samples: 4, rows: 3 });
assert.equal(JSON.stringify(transformed), snapshot); assert.equal(spec.id, undefined);
for (const group of ['position', 'rotation', 'scale']) {
  assert.deepEqual(spec[group], transformed[group]); assert.notEqual(spec[group], transformed[group]);
}
assert.equal(spec.color, transformed.color);
const created = createLayer(spec.type, spec);
assert.notEqual(created.id, transformed.id);
for (const key of ['spin', 'spinX', 'spinZ', 'wave', 'pulse', 'orbitRadius', 'bobAmount', 'twist', 'taper', 'scatter', 'tube']) assert.equal(created[key], 0);
const saved = projectOf([transformed, created]);
assert.deepEqual(normalizeProject(JSON.parse(JSON.stringify(saved))), saved);
assert.deepEqual(sampleProject(projectOf([created]), 0), sampleProject(projectOf([created]), 100));

// Execute actual exports to verify surface ordering and static transforms at
// small, exact and oversampled debris counts in both JavaScript and Lua.
const executable = [process.env.LUAJIT, process.env.LUAU, 'luajit', 'lua'].filter(Boolean).find(candidate => !spawnSync(candidate, ['-v']).error);
if (executable) {
  const header = `
local meta = {}; meta.__index = meta
Vector3 = {new = function(x,y,z) return setmetatable({X=x,Y=y,Z=z},meta) end}
meta.__add = function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
meta.__sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
meta.__mul = function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
local function check(source,count,expected)
  local module = assert((loadstring or load)(source))()
  local x1,x6,x9,c = {k10=20},{pre={},n=count},{c1=.15},{}
  module.px(0,c,x6,x9,x1)
  for i,point in ipairs(expected) do
    local _,target = module.f2({Position=Vector3.new(0,0,0)},Vector3.new(0,0,0),{id=i},0,c,x1,x6,x9)
    assert(math.abs(target.X-point[1])<1e-7 and math.abs(target.Y-point[2])<1e-7 and math.abs(target.Z-point[3])<1e-7, 'surface parity')
  end
end
`;
  const cases = [created, createLayer('pointcloud', revolved), createLayer('pointcloud', diagonal)];
  let suite = '';
  for (const layer of cases) for (const count of [1, 7, layer.path.points.length, 128]) {
    const project = projectOf([layer], count);
    const expected = sampleProject(project).map(p => `{${p.x},${p.y},${p.z}}`).join(',');
    suite += `check(${luaString(exportLua(project))},${count},{${expected}})\n`;
  }
  const directory = mkdtempSync(join(tmpdir(), 'gravity-surface-test-'));
  try {
    const filename = join(directory, 'surface-parity.lua'); writeFileSync(filename, header + suite);
    const result = spawnSync(executable, [filename], { encoding: 'utf8', maxBuffer: 2 * 1024 * 1024 });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    console.log('Surface Lua runtime parity passed.');
  } finally { rmSync(directory, { recursive: true, force: true }); }
} else console.log('Surface Lua runtime parity skipped: set LUAJIT or LUAU.');
console.log('Builder surfaces: extrusion, custom directions, revolving, pivots, curve sampling, bounds, isolation and JSON round trips passed.');
