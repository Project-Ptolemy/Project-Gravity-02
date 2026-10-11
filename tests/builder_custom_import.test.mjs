import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createLayer, normalizeProject, sampleProject, applyPreviewAction } from '../docs/plugins/builder/model.mjs';
import { exportLua, luaString } from '../docs/plugins/builder/exporter.mjs';

// Exercise the exact website export through the actual in-game import manager.
const layer = createLayer('torus', {
  id: 'orbit', radius: 23.5, tube: 3, spin: 19, spinX: -7,
  position: { x: 3, y: 8, z: -4 }, wave: 2, timeScale: 0.75,
});
const second = createLayer('sphere', { id: 'sphere', radius: 5, position: { x: 40, y: 0, z: 0 } });
const project = normalizeProject({ version: 1, name: 'Website orbit', parts: 23, layers: [layer, second], controls: [
  { id: 'radius', name: 'Orbit radius', layerId: layer.id, property: 'radius', min: 5, max: 100, default: 23.5 },
  { id: 'visible', type: 'toggle', name: 'Show orbit', layerId: layer.id, property: 'visible', default: true },
  { id: 'reverse', type: 'button', name: 'Reverse orbit', layerId: layer.id, action: 'reverse' },
] });
const large = normalizeProject({ version: 1, name: 'Detailed website geometry', parts: 19, controls: [], layers:
  Array.from({ length: 3 }, (_, index) => createLayer('pointcloud', {
    id: 'cloud-' + index, spin: 9, position: { x: index * 30, y: 0, z: 0 },
    path: { points: Array.from({ length: 4096 }, (_, i) => ({
      x: Math.sin(i * 0.173) * 83, y: Math.cos(i * 0.213) * 53, z: Math.sin(i * 0.119 + 0.37) * 37,
    })) },
  })),
});
const sources = [exportLua(project), exportLua(large)];
assert.ok(Buffer.byteLength(sources[1]) > 256 * 1024, 'the large website export exceeds the old small-script limit');
assert.ok(Buffer.byteLength(sources[1]) < 64 * 1024 * 1024, 'the large export fits the supported paste limit');

const executable = [process.env.LUAU, process.env.LUAJIT, 'luau', 'luajit', 'lua']
  .filter(Boolean).find(candidate => !spawnSync(candidate, ['-v']).error);
if (!executable) {
  console.log('Custom shape import parity skipped: install Luau/LuaJIT or set LUAU/LUAJIT.');
} else {
  const expected = (input, time, values = {}) => '{' + sampleProject(input, time, values)
    .map(point => `{${point.x},${point.y},${point.z}}`).join(',') + '}';
  const reverseValues = applyPreviewAction(project, 'reverse', 2, { radius: 31.25 });
  const code = `
local compile = loadstring or load
local importer = assert(compile(${luaString(readFileSync(new URL('../CustomShapes.lua', import.meta.url), 'utf8'))}))()
local dispatch = assert(compile(${luaString(readFileSync(new URL('../PluginControls.lua', import.meta.url), 'utf8'))}))()
Vector3 = {}; local mt = {}; mt.__index = mt
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z}, mt) end
mt.__add = function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__mul = function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function import(name, source, parts)
    local switches, refreshed = 0, 0
    local context = { x1 = { k6 = "Existing", k10 = 20 }, x2 = { Existing = {} },
        loaded_shapes = {}, local_shapes = {}, plugin_controls = dispatch,
        x6 = { pre = { unrelated = true }, n = parts } }
    context.x4 = { switch_shape = function(selected)
        switches = switches + 1; context.x1.k6 = selected; return true
    end }
    context.x6.populate_modes = function() refreshed = refreshed + 1 end
    local manager = importer.create(context)
    local valid, entry = manager.validate(name, source)
    check(valid, "website export validates: " .. tostring(entry))
    check(context.x2[name] == nil and context.loaded_shapes[name] == nil and switches == 0,
        "checking a website export does not activate it")
    local ok, result = manager.add(name, source)
    check(ok, "website export adds: " .. tostring(result))
    check(not result.persisted and context.x1.k6 == name and switches == 1 and refreshed == 1,
        "website export registers and activates without file APIs")
    return context, context.loaded_shapes[name], context.x2[name]
end
local function targets(context, module, c, time, expected)
    local center, part = Vector3.new(100, -40, 70), { Position = Vector3.new(-3, 2, 5) }
    local x9 = { c1 = 0.15 }
    context.x6.shape_clock = time
    module.px(time, c, context.x6, x9, context.x1)
    for i, point in ipairs(expected) do
        local velocity, target = module.f2(part, center, { id = 1000+i, slot = i, slot_n = #expected }, time,
            c, context.x1, context.x6, x9)
        check(math.abs(target.X-point[1]-center.X)<1e-7 and math.abs(target.Y-point[2]-center.Y)<1e-7
            and math.abs(target.Z-point[3]-center.Z)<1e-7, "imported target matches website at slot " .. i)
        check(math.abs(velocity.X-(target.X-part.Position.X)*3)<1e-7
            and math.abs(velocity.Y-(target.Y-part.Position.Y)*3)<1e-7
            and math.abs(velocity.Z-(target.Z-part.Position.Z)*3)<1e-7, "imported shape produces the expected pull velocity")
    end
end
local context, module, c = import("Renamed website orbit", ${luaString(sources[0])}, ${project.parts})
check(c.radius == 23.5 and c.visible == true and c.reverse == nil, "website controls preserve slider/toggle defaults and omit button state")
targets(context, module, c, 0, ${expected(project, 0)})
c.radius = 31.25
targets(context, module, c, 2, ${expected(project, 2, { radius: 31.25 })})
local reverse
for _, control in ipairs(module.Controls) do if control.Key == "reverse" then reverse = control end end
check(reverse and dispatch.activate(reverse, c, context.x6, context.x1), "imported website action button remains callable")
targets(context, module, c, 3, ${expected(project, 3, reverseValues)})
c.visible = false
targets(context, module, c, 4, ${expected(project, 4, { ...reverseValues, visible: false })})
module.cleanup(context.x6, context.x1)
check(context.x6.pre.unrelated == true, "website cleanup keeps unrelated session state")
local largeContext, largeModule, largeConfig = import("Large website geometry", ${luaString(sources[1])}, ${large.parts})
targets(largeContext, largeModule, largeConfig, 1.25, ${expected(large, 1.25)})
print(checks .. " website export to in-game import checks passed (including ${Buffer.byteLength(sources[1])}-byte geometry)")
`;
  const directory = mkdtempSync(join(tmpdir(), 'gravity-custom-import-'));
  try {
    const file = join(directory, 'import.lua');
    writeFileSync(file, code);
    const result = spawnSync(executable, [file], { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    process.stdout.write(result.stdout);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}
