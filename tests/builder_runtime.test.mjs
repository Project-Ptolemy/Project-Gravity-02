import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createLayer, normalizeProject, sampleProject } from '../docs/plugins/builder/model.mjs';
import { exportLua, luaString } from '../docs/plugins/builder/exporter.mjs';

const projectOf = layers => ({ version: 1, name: 'Runtime accuracy probe', parts: 8, pointSize: 1.5, layers, controls: [] });
const moving = projectOf([createLayer('ring', {
  id: 'motion', radius: 20, spin: 37, spinX: 13, spinZ: -7, wave: 2, waveSpeed: 0.4,
  position: { x: 0, y: 0, z: 0 }, scale: { x: 1.1, y: 0.7, z: 1.3 },
})]);
const staticProject = projectOf([createLayer('pointcloud', {
  id: 'static', path: { points: [{ x: 0.123456789012345, y: 0.25, z: -0.125 }] },
  position: { x: 0, y: 0, z: 0 },
})]);
const controlled = {
  ...staticProject,
  controls: [{ id: 'spin', name: 'Spin', layerId: 'static', property: 'spin', min: -60, max: 60, default: 0 }],
};
const frozen = { ...moving, layers: moving.layers.map(layer => ({ ...layer, timeScale: 0 })) };
assert.equal(normalizeProject(staticProject).layers[0].path.points[0].x, 0.123456789012345, 'stored coordinates retain full numeric precision');
assert.ok(exportLua(staticProject).includes('0.123456789012345'), 'Lua literals retain full numeric precision');
assert.match(exportLua(moving), /FrameTracking = true/);
assert.match(exportLua(staticProject), /FrameTracking = false/);
assert.match(exportLua(controlled), /FrameTracking = true/, 'an exposed speed control can enable motion');
assert.match(exportLua(frozen), /FrameTracking = false/, 'a permanently frozen layer keeps ordinary scheduling');

const executable = [process.env.LUNE, 'lune'].filter(Boolean).find(candidate => !spawnSync(candidate, ['--version'], { encoding: 'utf8' }).error);
if (!executable) {
  console.log('Builder engine integration skipped: install Lune or set LUNE. Export scheduling/precision checks passed.');
} else {
  const table = points => '{' + points.map(point => `{${point.x},${point.y},${point.z}}`).join(',') + '}';
  const sampleCases = [30, 60, 144].map(fps => {
    const points = [];
    for (let frame = 1; frame <= fps * 2; frame++) points.push(table(sampleProject(moving, frame / fps)));
    return `[${fps}]={${points.join(',')}}`;
  }).join(',');
  const nativeCenter = { x: 100000.125, y: -40.125, z: 70.0625 };
  const nativeCases = [-12345.625, -3.5, 0, 1.25, 86400.5].map(time => {
    const expected = sampleProject(moving, time).map(point => Object.fromEntries(['x', 'y', 'z'].map(axis => [axis, Math.fround(Math.fround(nativeCenter[axis]) + Math.fround(point[axis]))])));
    return `{time=${time},points=${table(expected)}}`;
  }).join(',');
  const payload = `return {
    moving=assert(loadstring(${luaString(exportLua(moving))}))(),
    static=assert(loadstring(${luaString(exportLua(staticProject))}))(),
    controlled=assert(loadstring(${luaString(exportLua(controlled))}))(),
    expected={${sampleCases}}, static_points=${table(sampleProject(staticProject))},
    native_center={${nativeCenter.x},${nativeCenter.y},${nativeCenter.z}}, native_cases={${nativeCases}}
  }`;
  const directory = mkdtempSync(join(tmpdir(), 'gravity-builder-runtime-'));
  try {
    const path = join(directory, 'payload.lua');
    writeFileSync(path, payload);
    const result = spawnSync(executable, ['run', 'tools/test_luau.luau', 'tests/builder_runtime.lua', path], {
      cwd: fileURLToPath(new URL('..', import.meta.url)), encoding: 'utf8', maxBuffer: 8 * 1024 * 1024,
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    process.stdout.write(result.stdout);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}
