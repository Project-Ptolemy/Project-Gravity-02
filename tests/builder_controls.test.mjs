import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createLayer, normalizeProject, sampleProject, applyPreviewAction } from '../docs/plugins/builder/model.mjs';
import { exportLua, luaString } from '../docs/plugins/builder/exporter.mjs';

const moving = createLayer('path', {
  id: 'moving', position: { x: 0, y: 0, z: 0 }, spin: 29, spinX: 7,
  timeScale: 0.75, timeOffset: 1.25, wave: 3, waveSpeed: 0.5,
  path: { points: [{ x: 12, y: 2, z: 4 }, { x: -2, y: 8, z: -7 }] },
});
const other = createLayer('sphere', { id: 'other', radius: 4, spin: 0, position: { x: 40, y: 0, z: 0 } });
const project = normalizeProject({ version: 1, name: 'Control actions', parts: 16, layers: [moving, other], controls: [
  { id: 'visible', type: 'toggle', name: 'Show path', layerId: moving.id, property: 'visible', default: true },
  { id: 'fill', type: 'toggle', name: 'Fill sphere', layerId: other.id, property: 'fill', default: false },
  { id: 'speed', name: 'Custom speed', layerId: moving.id, property: 'timeScale', min: -4, max: 4, default: 0.75 },
  { id: 'radius', name: 'Other radius', layerId: other.id, property: 'radius', min: 0, max: 20, default: 4 },
  ...['restart', 'reverse', 'reset'].map(action => ({ id: action, type: 'button', name: action, layerId: moving.id, action })),
] });
const original = JSON.stringify(project);
const nearPoints = (actual, expected) => {
  assert.equal(actual.length, expected.length);
  actual.forEach((point, i) => {
    assert.equal(point.layerId, expected[i].layerId);
    for (const axis of ['x', 'y', 'z']) assert.ok(Math.abs(point[axis] - expected[i][axis]) < 1e-7, `${axis}: ${point[axis]} versus ${expected[i][axis]}`);
  });
};
assert.deepEqual(normalizeProject(JSON.parse(original)), project);
assert.equal(project.controls[2].type, undefined, 'old slider projects remain compatible');
assert.equal(sampleProject(project, 2, { visible: false }).filter(point => point.layerId === moving.id).length, 0);
nearPoints(sampleProject(project, 2, { visible: 'false' }), sampleProject(project, 2));
const filled = sampleProject(project, 0, { fill: true }).filter(point => point.layerId === other.id);
assert.ok(filled.every(point => Math.hypot(point.x - 40, point.y, point.z) < 4));

let values = { speed: 1.5, radius: 7 };
const atReverse = sampleProject(project, 3, values);
values = applyPreviewAction(project, 'reverse', 3, values);
nearPoints(sampleProject(project, 3, values), atReverse);
const backwards = sampleProject(project, 4, values).filter(point => point.layerId === moving.id);
nearPoints(backwards, sampleProject(project, 2, { speed: 1.5 }).filter(point => point.layerId === moving.id));
values = applyPreviewAction(project, 'reverse', 3, values);
nearPoints(sampleProject(project, 4, values), sampleProject(project, 4, { speed: 1.5, radius: 7 }));
values = applyPreviewAction(project, 'restart', 5, values);
const frozen = structuredClone(project);
frozen.layers[0].timeOffset = 0;
nearPoints(sampleProject(project, 5, values).filter(point => point.layerId === moving.id), sampleProject(frozen, 0).filter(point => point.layerId === moving.id));
values = applyPreviewAction(project, 'reset', 6, { ...values, visible: false });
nearPoints(sampleProject(project, 6, values), sampleProject(project, 6, { radius: 7 }));
assert.equal(JSON.stringify(project), original, 'preview buttons never change the saved project');
assert.throws(() => applyPreviewAction(project, 'visible', 0), /action button/);
assert.throws(() => applyPreviewAction(project, 'reverse', Infinity), /finite/);
for (const change of [
  { type: 'unknown' }, { type: 'toggle', property: 'radius' },
  { type: 'toggle', property: 'visible', default: 1 }, { type: 'button', action: 'eval' },
]) assert.throws(() => normalizeProject({ ...project, controls: [{ ...project.controls[0], ...change }] }));
assert.throws(() => normalizeProject({ ...project, controls: [...project.controls, { ...project.controls[0], id: 'duplicate-binding' }] }), /already has a control/);
assert.throws(() => normalizeProject({ ...project, controls: [...project.controls, { ...project.controls.at(-1) }] }), /Duplicate control ID/);

// Imported IDs may legally match Object.prototype names. Actions on one layer
// must never mistake inherited functions/prototypes for another layer's clock.
for (const id of ['constructor', '__proto__', 'toString']) {
  const imported = normalizeProject(JSON.parse(JSON.stringify({ ...project,
    layers: [{ ...moving, id }, other], controls: [
      { id: 'other-go', type: 'button', name: 'Reverse other', layerId: other.id, action: 'reverse' },
      { id: '__proto__', type: 'button', name: 'Reverse imported', layerId: id, action: 'reverse' },
      { id: 'constructor', type: 'toggle', name: 'Show imported', layerId: id, property: 'visible', default: true },
    ],
  })));
  const before = sampleProject(imported, 2);
  let actionValues = applyPreviewAction(imported, 'other-go', 2);
  nearPoints(sampleProject(imported, 2, actionValues), before);
  assert.equal(Object.getPrototypeOf(actionValues), null);
  // Object spread changes the outer prototype, as some API callers may do.
  actionValues = applyPreviewAction(imported, '__proto__', 2, { ...actionValues });
  nearPoints(sampleProject(imported, 2, actionValues), before);
  nearPoints(sampleProject(imported, 3, actionValues).filter(point => point.layerId === id),
    sampleProject(imported, 1).filter(point => point.layerId === id));
  actionValues.constructor = false;
  assert.ok(sampleProject(imported, 3, actionValues).every(point => point.layerId !== id));
}

const initiallyOff = normalizeProject({ ...project, layers: [{ ...moving, visible: false }], controls: [
  { ...project.controls[0], default: false }, ...project.controls.slice(4),
] });
assert.deepEqual(sampleProject(initiallyOff), []);
assert.equal(sampleProject(initiallyOff, 0, { visible: true }).length, initiallyOff.parts);
assert.match(exportLua(initiallyOff), /Type = "Toggle"/);
assert.match(exportLua(initiallyOff), /Default = false/);

// Execute exported switches and callbacks through the application's real
// button dispatcher, comparing target positions after each interaction.
const executable = process.env.LUAJIT || process.env.LUAU;
if (executable) {
  const literal = value => typeof value === 'boolean' ? String(value) : typeof value === 'number' ? String(value) : luaString(value);
  let preview = {}, steps = '';
  const check = time => {
    const points = sampleProject(project, time, preview);
    steps += `check(${time}, {${points.map(p => `{${p.x},${p.y},${p.z}}`).join(',')}})\n`;
  };
  const set = (id, value) => { preview[id] = value; steps += `c[${luaString(id)}] = ${literal(value)}\n`; };
  const action = (id, time) => {
    preview = applyPreviewAction(project, id, time, preview);
    steps += `x6.shape_clock = ${time}; assert(dispatch.activate(buttons[${luaString(id)}], c, x6, x1))\n`;
  };
  check(0); set('speed', 1.5); set('radius', 7); set('fill', true); check(3);
  action('reverse', 3); check(3); check(4); action('reverse', 4); check(4); check(5);
  set('visible', false); check(6); action('restart', 6); set('visible', true); check(6); check(7);
  set('speed', 0); action('restart', 8); check(8); action('reverse', 8); check(9);
  set('speed', -2); check(9); action('reverse', 9); check(9); check(10);
  action('reset', 10); check(10); action('reverse', 10); action('reverse', 10); check(12);
  const code = `
local dispatch = dofile(${luaString(fileURLToPath(new URL('../PluginControls.lua', import.meta.url)))})
Vector3 = {}; local mt = {}; mt.__index = mt
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z}, mt) end
mt.__add = function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__mul = function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
local module = assert((loadstring or load)(${luaString(exportLua(project))}))()
local x6, x1, x9 = {pre={unrelated=true},n=${project.parts}}, {k10=20}, {c1=.15}
local c, buttons = dispatch.defaults(module.Controls), {}
for _, control in ipairs(module.Controls) do if control.Type == "Button" then buttons[control.Key] = control end end
local function check(t, expected)
    x6.shape_clock = t
    module.px(t,c,x6,x9,x1)
    for i, point in ipairs(expected) do
        local _, target = module.f2({Position=Vector3.new(0,0,0)},Vector3.new(0,0,0),{id=i},t,c,x1,x6,x9)
        assert(math.abs(target.X-point[1])<1e-7 and math.abs(target.Y-point[2])<1e-7 and math.abs(target.Z-point[3])<1e-7,"target parity at "..t.." slot "..i)
    end
end
${steps}
module.cleanup(x6,x1); module.cleanup(x6,x1)
assert(x6.pre.unrelated); local count=0; for _ in pairs(x6.pre) do count=count+1 end; assert(count==1)
print("Exported control actions: toggle/defaults, continuous reverse, restart, reset and cleanup parity passed.")
`;
  const directory = mkdtempSync(join(tmpdir(), 'gravity-controls-'));
  try {
    const file = join(directory, 'controls.lua'); writeFileSync(file, code);
    const result = spawnSync(executable, [file], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stdout + result.stderr); process.stdout.write(result.stdout);
  } finally { rmSync(directory, { recursive: true, force: true }); }
} else console.log('Lua control parity skipped: set LUAJIT or LUAU to enable it.');
console.log('Builder controls: legacy sliders, switches, action clocks, validation and project isolation passed.');
