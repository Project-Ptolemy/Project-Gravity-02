import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { FLOW_LAYER_TYPES, LAYER_TYPES, createLayer, createProject, normalizeProject, sampleProject, applyPreviewAction } from '../docs/plugins/builder/model.mjs';
import { compilePath, samplePath } from '../docs/plugins/builder/geometry/path.mjs';
import { flowFraction, sampleFlowPath } from '../docs/plugins/builder/geometry/flow.mjs';
import { exportLua, luaString } from '../docs/plugins/builder/exporter.mjs';
import { readProjectFile, serializeProject } from '../docs/plugins/builder/project-file.mjs';

const near = (a, b, tolerance = 1e-7) => assert.ok(Math.abs(a - b) < tolerance, `${a} should equal ${b}`);
const nearPoint = (a, b, tolerance) => ['x', 'y', 'z'].forEach(axis => near(a[axis], b[axis], tolerance));
const nearPoints = (a, b) => { assert.equal(a.length, b.length); a.forEach((point, i) => nearPoint(point, b[i])); };
const finite = points => assert.ok(points.every(point => ['x', 'y', 'z'].every(axis => Number.isFinite(point[axis]))));
const atOrigin = (type, overrides = {}) => createLayer(type, { id: 'moving', position: { x: 0, y: 0, z: 0 }, spin: 0, ...overrides });
const projectOf = (layer, parts = 7, controls = []) => normalizeProject({ ...createProject('blank'), name: 'Individual motion', parts, layers: [layer], controls });
const points = [{ x: 0, y: 0, z: 0 }, { x: 10, y: 0, z: 0 }, { x: 10, y: 30, z: 0 }];
// Normalized tangents straddle abs(tz)=0.9 when JS hypot and Lua sqrt round
// differently. Raw-component axis selection must give identical flow frames.
const thresholdPoints = [{ x: 0, y: 0, z: 0 }, { x: 0.005971094443206402, y: 0, z: 0.012328767123287671 }];
const path = atOrigin('path', { path: { points }, flowSpeed: 5 });
const moving = projectOf(path, 5);
nearPoints(sampleProject(moving, 1), [{ x: 5, y: 0, z: 0 }, { x: 10, y: 5, z: 0 }, { x: 10, y: 15, z: 0 }, { x: 10, y: 25, z: 0 }, { x: 10, y: 25, z: 0 }]);
nearPoint(sampleProject({ ...moving, parts: 1 }, 2)[0], { x: 10, y: 20, z: 0 });
nearPoint(sampleProject(moving, -1)[0], { x: 5, y: 0, z: 0 });
nearPoints(sampleProject(moving, -1.25), sampleProject(projectOf({ ...path, flowSpeed: -5 }, 5), 1.25));
near(flowFraction(0.75, 10, 1, 10, true), 0.75);
near(flowFraction(0.75, 10, -1, 10, true), 0.75);
near(flowFraction(0.75, 5, 1, 10, false), 0.75);
near(flowFraction(0.25, -5, 1, 10, false), 0.25);
near(flowFraction(1, 5, 0, 10, false), 1);
near(flowFraction(0.5, 0, 100, 0, false), 0.5);
assert.ok(Number.isFinite(flowFraction(0.5, 500, Number.MAX_VALUE, 10, true)), 'large elapsed time does not overflow flow');

// The physical centerline distance, rather than vertex index, sets speed.
const line = projectOf(atOrigin('line', { width: 40, tube: 0, flowSpeed: 5 }), 1);
nearPoint(sampleProject(line, 1)[0], { x: 5, y: 0, z: 0 });
nearPoint(sampleProject(line, 5)[0], { x: 15, y: 0, z: 0 });
const polygon = projectOf(atOrigin('polygon', { sides: 4, radius: Math.sqrt(2), flowSpeed: 2 }), 1);
nearPoint(sampleProject(polygon, 1)[0], { x: -Math.sqrt(2), y: 0, z: 0 });
nearPoint(sampleProject(polygon, 4)[0], { x: 0, y: Math.sqrt(2), z: 0 });
const ring = projectOf(atOrigin('ring', { radius: 10, flowSpeed: 5 }), 4);
nearPoint(sampleProject(ring, 1)[0], { x: 10 * Math.cos(Math.PI / 4 + 0.5), y: 0, z: 10 * Math.sin(Math.PI / 4 + 0.5) });
const partial = projectOf(atOrigin('ring', { radius: 10, arc: 180, flowSpeed: 20 }), 1);
nearPoint(sampleProject(partial, 1)[0], { x: 10 * Math.cos(2 * Math.PI - (Math.PI / 2 + 2)), y: 0, z: 10 * Math.sin(2 * Math.PI - (Math.PI / 2 + 2)) });

// Active-flow tube offsets share each vertex and the closed seam. Exercise
// corners, exact reversals, the old normal-frame branch, and smooth outlines.
for (const nodes of [points,
  [{ x: 0, y: 0, z: 0 }, { x: 10, y: 0, z: 0 }, { x: 0, y: 0, z: 0 }],
  [{ x: 0, y: 0, z: 0 }, { x: 0, y: 10, z: 19 }, { x: 0, y: 13, z: 39 }, { x: 11, y: 15, z: 41 }],
  [...thresholdPoints, { x: 0.012, y: 0.002, z: 0.016 }],
]) for (const closed of [false, true]) for (const smooth of [false, true]) {
  const table = compilePath({ points: nodes, closed, smooth });
  for (let i = 1; i < table.lengths.length - 1; i++) {
    const fraction = table.lengths[i] / table.total;
    for (const angle of [0, 1.2, 3.8]) {
      const before = sampleFlowPath(table, fraction - 1e-9, closed, 3, angle);
      const after = sampleFlowPath(table, fraction + 1e-9, closed, 3, angle);
      nearPoint(before, after, 1e-4);
    }
  }
  if (closed) for (const angle of [0, 1.2, 3.8]) nearPoint(sampleFlowPath(table, 1 - 1e-9, true, 3, angle), sampleFlowPath(table, 1e-9, true, 3, angle), 1e-4);
  for (const fraction of [0, 0.2, 0.5, 0.9, 1]) {
    const center = samplePath(table, fraction), offset = sampleFlowPath(table, fraction, closed, 3, 2.1);
    assert.ok(Math.hypot(offset.x - center.x, offset.y - center.y, offset.z - center.z) <= 3 + 1e-8, 'interpolated offsets remain bounded by tube radius');
  }
}
const tubePolygon = projectOf(atOrigin('polygon', { sides: 4, radius: Math.sqrt(2), tube: 3, flowSpeed: 2 }), 1);
for (const time of [0, 1, 2, 3, 4]) nearPoints(sampleProject(tubePolygon, time - 1e-9), sampleProject(tubePolygon, time + 1e-9));
for (const type of FLOW_LAYER_TYPES) {
  const collapsed = atOrigin(type, { flowSpeed: 500, radius: 0, width: 0, path: { points: [points[0], points[0], points[0]], closed: true } });
  for (const time of [-1000, 0, 1000]) finite(sampleProject(projectOf(collapsed, 1), time));
}
const tiny = atOrigin('path', { flowSpeed: 500, path: { points: [points[0], { x: Number.MIN_VALUE, y: 0, z: 0 }] } });
finite(sampleProject(projectOf(tiny), 10));

// Zero/default motion takes exactly the old branches, preserving endpoints
// and existing tube placement rather than silently replacing legacy frames.
const properties = ['flowSpeed', 'partMoveX', 'partMoveY', 'partMoveZ', 'partMoveSpeed', 'partMoveSpread', 'partMovePhase', 'partMovePhaseY', 'partMovePhaseZ'];
for (const type of LAYER_TYPES) {
  const layer = atOrigin(type, { tube: 2, wave: 4, twist: 20, scale: { x: 2 }, path: { points } });
  const omitted = { ...layer }; properties.forEach(property => delete omitted[property]);
  for (const count of [1, 2, 7]) for (const time of [-1, 0, 7.5]) {
    assert.deepEqual(sampleProject(projectOf(layer, count), time), sampleProject(projectOf(omitted, count), time));
    if (!FLOW_LAYER_TYPES.includes(type)) assert.deepEqual(sampleProject(projectOf({ ...layer, flowSpeed: 37 }, count), time), sampleProject(projectOf(layer, count), time));
  }
}
nearPoints(sampleProject(projectOf(atOrigin('path', { path: { points } }), 2)), [points[0], points[2]]);
nearPoint(sampleProject(projectOf(atOrigin('path', { path: { points } }), 1))[0], { x: 10, y: 10, z: 0 });
nearPoint(sampleProject(projectOf(atOrigin('path', { tube: 2, path: { points: thresholdPoints } }), 1))[0],
  { x: 1.6806439100854127, y: 0.7247497801609603, z: -0.8063626459393823 }, 1e-12);

// Individual phase stays attached to the original local slot while it flows.
const motion = { partMoveX: 3, partMoveY: 4, partMoveZ: 5, partMoveSpeed: -0.7, partMoveSpread: 2.5, partMovePhase: 19, partMovePhaseY: 71, partMovePhaseZ: -33 };
for (const type of LAYER_TYPES) {
  const layer = atOrigin(type, { ...motion, path: { points } });
  const stationary = { ...layer, partMoveX: 0, partMoveY: 0, partMoveZ: 0 };
  for (const time of [-2, 0, 3]) {
    const actual = sampleProject(projectOf(layer), time), base = sampleProject(projectOf(stationary), time);
    actual.forEach((point, index) => {
      const theta = Math.PI * 2 * (time * motion.partMoveSpeed + (index + 0.5) / actual.length * motion.partMoveSpread) + motion.partMovePhase * Math.PI / 180;
      nearPoint(point, { x: base[index].x + 3 * Math.sin(theta), y: base[index].y + 4 * Math.sin(theta + 71 * Math.PI / 180), z: base[index].z + 5 * Math.sin(theta - 33 * Math.PI / 180) });
    });
  }
}
const transformed = projectOf(atOrigin('sphere', { radius: 0, partMoveX: 2, partMoveY: 3, partMoveZ: 4, partMoveSpread: 0, scale: { x: 2, z: 3 }, rotation: { y: 90 }, position: { x: 10, y: 20, z: 30 } }), 1);
nearPoint(sampleProject(transformed, 0.25)[0], { x: 22, y: 20, z: 26 });
for (const key of ['flowSpeed', 'partMoveX', 'partMoveY', 'partMoveZ', 'partMoveSpeed', 'partMoveSpread', 'partMovePhase', 'partMovePhaseY', 'partMovePhaseZ']) assert.throws(() => atOrigin('path', { [key]: Infinity }));

const controlled = projectOf(atOrigin('path', { ...motion, path: { points, closed: true, smooth: true }, flowSpeed: 7, tube: 2, timeScale: 0.75, timeOffset: 1.2 }), 13, [
  { id: 'flow', name: 'Flow', layerId: 'moving', property: 'flowSpeed', min: -500, max: 500, default: 7 },
  { id: 'amount', name: 'Part X', layerId: 'moving', property: 'partMoveX', min: 0, max: 200, default: 3 },
  ...['reverse', 'restart', 'reset'].map(action => ({ id: action, name: action, type: 'button', layerId: 'moving', action })),
]);
assert.deepEqual(await readProjectFile(new Blob([serializeProject(controlled)])), controlled);
const unchanged = structuredClone(controlled);
let values = { flow: -9, amount: 6 };
const beforeReverse = sampleProject(controlled, 3, values);
values = applyPreviewAction(controlled, 'reverse', 3, values);
nearPoints(sampleProject(controlled, 3, values), beforeReverse);
nearPoints(sampleProject(controlled, 4, values), sampleProject(controlled, 2, { flow: -9, amount: 6 }));
values = applyPreviewAction(controlled, 'restart', 5, values);
nearPoints(sampleProject(controlled, 5, values), sampleProject({ ...controlled, layers: [{ ...controlled.layers[0], timeOffset: 0 }] }, 0, { flow: -9, amount: 6 }));
values = applyPreviewAction(controlled, 'reset', 6, values);
nearPoints(sampleProject(controlled, 6, values), sampleProject(controlled, 6));
assert.deepEqual(controlled, unchanged);

// Execute real exported target sampling, including sorted and gapped slots.
const executable = process.env.LUAJIT || process.env.LUAU;
if (executable) {
  const fixtures = [];
  for (const type of LAYER_TYPES) fixtures.push(projectOf(atOrigin(type, { ...motion, flowSpeed: 9, tube: 2, path: { points }, spin: 13, wave: 2, twist: 37, scale: { x: 1.3, y: 0.7, z: 2 }, rotation: { x: 12, y: -19, z: 22 } }), 9));
  for (const closed of [false, true]) for (const smooth of [false, true]) for (const count of [1, 7]) fixtures.push(projectOf(atOrigin('path', { ...motion, flowSpeed: -13, tube: 3, fill: true, path: { points, closed, smooth } }), count));
  fixtures.push(partial, polygon, tubePolygon, line, projectOf(tiny), controlled);
  for (const count of [1, 7]) for (const closed of [false, true]) fixtures.push(projectOf(atOrigin('path', { flowSpeed: 1, tube: 2, path: { points: thresholdPoints, closed } }), count));
  let suite = '';
  for (const fixture of fixtures) {
    suite += `do local module = assert((loadstring or load)(${luaString(exportLua(fixture))}))()\nlocal c = dispatch.defaults(module.Controls)\nlocal x6 = {pre={},n=${fixture.parts},a={},part_id_counter=9000}\n`;
    for (const time of [-2.2, 0, 1, 6.25]) {
      const expected = sampleProject(fixture, time);
      suite += `check(module,c,x6,${time},{${expected.map(p => `{${p.x},${p.y},${p.z}}`).join(',')}})\n`;
    }
    suite += 'module.cleanup(x6); end\n';
  }
  let preview = { flow: -9, amount: 6 };
  suite += `do local module = assert((loadstring or load)(${luaString(exportLua(controlled))}))()\nlocal c = dispatch.defaults(module.Controls); c.flow=-9; c.amount=6\nlocal x6={pre={},n=${controlled.parts}}; local buttons={}\nfor _, control in ipairs(module.Controls) do if control.Type=="Button" then buttons[control.Key]=control end end\n`;
  for (const [action, time, later] of [['reverse', 3, 4], ['restart', 5, 5], ['reset', 6, 7]]) {
    preview = applyPreviewAction(controlled, action, time, preview);
    suite += `x6.shape_clock=${time}; assert(dispatch.activate(buttons[${luaString(action)}],c,x6,{}))\n`;
    for (const t of [time, later]) suite += `check(module,c,x6,${t},{${sampleProject(controlled, t, preview).map(p => `{${p.x},${p.y},${p.z}}`).join(',')}})\n`;
  }
  suite += 'end\n';
  const code = `
local dispatch=dofile(${luaString(fileURLToPath(new URL('../PluginControls.lua', import.meta.url)))})
Vector3={}; local mt={};mt.__index=mt
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},mt) end
mt.__add=function(a,b)return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
mt.__sub=function(a,b)return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
mt.__mul=function(a,b)return Vector3.new(a.X*b,a.Y*b,a.Z*b)end
local function check(module,c,x6,time,expected)
  x6.shape_clock=time; module.px(time,c,x6,{c1=.15},{k10=20})
  for i,p in ipairs(expected) do
    local _,target=module.f2({Position=Vector3.new(0,0,0)},Vector3.new(0,0,0),{id=10000+i,slot=i,slot_n=#expected},time,c,{k10=20},x6,{c1=.15})
    assert(math.abs(target.X-p[1])<1e-6 and math.abs(target.Y-p[2])<1e-6 and math.abs(target.Z-p[3])<1e-6,'individual target parity at '..time..' slot '..i)
  end
end
${suite}
print('Exported individual motion: flow, local displacement, controls, slots and action-clock parity passed.')
`;
  const directory = mkdtempSync(join(tmpdir(), 'gravity-motion-'));
  try {
    const filename = join(directory, 'motion.lua'); writeFileSync(filename, code);
    const result = spawnSync(executable, [filename], { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
    assert.equal(result.status, 0, result.stdout + result.stderr); process.stdout.write(result.stdout);
  } finally { rmSync(directory, { recursive: true, force: true }); }
} else console.log('Lua motion parity skipped: set LUAJIT or LUAU to enable it.');
console.log('Builder individual motion: flow distance/boundaries, continuous tubes, local phases, legacy defaults, controls and action clocks passed.');
