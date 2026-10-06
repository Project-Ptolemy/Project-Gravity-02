import assert from 'node:assert/strict';
import { createLayer, createProject, normalizeProject, sampleProject } from '../docs/plugins/builder/model.mjs';
import { createArrangement } from '../docs/plugins/builder/geometry/arrangement.mjs';
import { serializeProject, readProjectFile } from '../docs/plugins/builder/project-file.mjs';

const near = (actual, expected, tolerance = 2e-5) => assert.ok(Math.abs(actual - expected) < tolerance, `${actual} should equal ${expected}`);
const pointNear = (actual, expected) => ['x', 'y', 'z'].forEach(axis => near(actual[axis], expected[axis]));
const projectOf = layer => ({ ...createProject('blank'), layers: [layer] });
const pointLayer = overrides => createLayer('pointcloud', {
  id: 'source', name: 'My detail', position: { x: 10, y: 0, z: 0 },
  path: { points: [{ x: 1, y: 2, z: 3 }, { x: -4, y: 5, z: -6 }] }, ...overrides,
});
const original = projectOf(pointLayer());
const untouched = structuredClone(original);
const line = createArrangement(original, 'source', { count: 3, positionStep: { x: 10, y: -2, z: 5 }, rotationStep: { z: 15 } });
assert.deepEqual(line.layers.map(layer => layer.position), [{ x: 20, y: -2, z: 5 }, { x: 30, y: -4, z: 10 }, { x: 40, y: -6, z: 15 }]);
assert.deepEqual(line.layers.map(layer => layer.rotation.z), [15, 30, 45]);
assert.deepEqual(original, untouched);
assert.equal(new Set(line.layers.map(layer => layer.id)).size, 3);
line.layers[0].path.points[0].x = 123;
assert.equal(line.layers[1].path.points[0].x, 1);
assert.equal(original.layers[0].path.points[0].x, 1);
assert.deepEqual(createArrangement(original, 'source', { count: 1 }), createArrangement(original, 'source', { count: 1 }), 'copy generation is deterministic');
const occupied = { ...original, layers: [...original.layers, pointLayer({ id: 'repeat-layer-1' })] };
assert.equal(createArrangement(occupied, 'source', { count: 1 }).layers[0].id, 'repeat-layer-2');

// Positions have independently known results on every principal axis.
for (const [axis, source, expected] of [
  ['x', { x: 0, y: 10, z: 0 }, { x: 0, y: 0, z: 10 }],
  ['y', { x: 10, y: 0, z: 0 }, { x: 0, y: 0, z: -10 }],
  ['z', { x: 10, y: 0, z: 0 }, { x: 0, y: 10, z: 0 }],
]) {
  const project = projectOf(pointLayer({ position: source }));
  const result = createArrangement(project, 'source', { mode: 'radial', count: 1, axis, sweep: 90 });
  pointNear(result.layers[0].position, expected);
}
const circle = createArrangement(original, 'source', { mode: 'radial', count: 3, axis: 'z', sweep: 360 });
circle.layers.forEach((layer, index) => pointNear(layer.position, [{ x: 0, y: 10, z: 0 }, { x: -10, y: 0, z: 0 }, { x: 0, y: -10, z: 0 }][index]));
const arc = createArrangement(original, 'source', { mode: 'radial', count: 2, axis: 'z', sweep: -180, rotateCopies: false });
pointNear(arc.layers[0].position, { x: 0, y: -10, z: 0 });
pointNear(arc.layers[1].position, { x: -10, y: 0, z: 0 });
assert.deepEqual(arc.layers[0].rotation, original.layers[0].rotation);

// A local pivot is scaled, rotated and translated by the source transform.
const localSource = pointLayer({ position: { x: 10, y: 20, z: 30 }, rotation: { z: 90 }, scale: { x: 2, y: 3, z: 4 } });
const localCopies = createArrangement(projectOf(localSource), 'source', { mode: 'radial', count: 1, axis: 'z', sweep: 180, pivotSpace: 'local', pivot: { x: 5 } });
pointNear(localCopies.layers[0].position, { x: 10, y: 40, z: 30 });
const worldCopies = createArrangement(projectOf(localSource), 'source', { mode: 'radial', count: 1, axis: 'z', sweep: 180, pivot: { x: 5 } });
pointNear(worldCopies.layers[0].position, { x: 0, y: -20, z: 30 });

// Rotations must compose as matrices, not by adding Euler components. Compare
// actual sampled geometry with independent world-space Rodrigues rotation.
function worldTurn(point, axis, degrees) {
  const a = degrees * Math.PI / 180, c = Math.cos(a), s = Math.sin(a);
  if (axis === 'x') return { x: point.x, y: c * point.y - s * point.z, z: s * point.y + c * point.z };
  if (axis === 'y') return { x: c * point.x + s * point.z, y: point.y, z: -s * point.x + c * point.z };
  return { x: c * point.x - s * point.y, y: s * point.x + c * point.y, z: point.z };
}
for (const rotation of [{ x: 23, y: 41, z: -67 }, { x: 21, y: 90, z: 13 }, { x: -32, y: -90, z: 27 }]) {
  for (const axis of ['x', 'y', 'z']) for (const sweep of [90, -90, 47]) {
    const source = pointLayer({ rotation, scale: { x: 2, y: 0.5, z: 3 } });
    const project = { ...projectOf(source), parts: 2 };
    const copies = createArrangement(project, source.id, { mode: 'radial', count: 1, axis, sweep });
    const before = sampleProject(project), after = sampleProject({ ...project, layers: copies.layers });
    after.forEach((point, index) => pointNear(point, worldTurn(before[index], axis, sweep)));
  }
}

// Cloned controls preserve names/types/actions and bind to each new layer.
// Transform defaults follow the copies even when imported base fields differ.
const controlled = normalizeProject({ ...original, controls: [
  { id: 'repeat-control-1', name: 'Position with my name', layerId: 'source', property: 'position.x', min: 0, max: 20, default: 15 },
  { id: 'angle', name: 'Tilt', layerId: 'source', property: 'rotation.z', min: -30, max: 30, default: 20 },
  { id: '__proto__', type: 'toggle', name: 'Show my detail', layerId: 'source', property: 'visible', default: false },
  { id: 'go', type: 'button', name: 'Restart my detail', layerId: 'source', action: 'restart' },
] });
const controlledBefore = structuredClone(controlled);
const copies = createArrangement(controlled, 'source', { count: 2, positionStep: { x: 20 }, rotationStep: { z: 15 } });
assert.equal(copies.controls.length, 8);
for (const [index, layer] of copies.layers.entries()) {
  const group = copies.controls.filter(control => control.layerId === layer.id);
  assert.deepEqual(group.map(control => control.name), controlled.controls.map(control => control.name));
  assert.equal(group[0].default, 15 + (index + 1) * 20);
  assert.equal(group[0].min, 0); assert.equal(group[0].max, group[0].default);
  assert.equal(group[1].default, 20 + (index + 1) * 15);
  assert.equal(group[2].type, 'toggle'); assert.equal(group[2].default, false);
  assert.equal(group[3].type, 'button'); assert.equal(group[3].action, 'restart');
  assert.equal(layer.visible, false);
}
assert.equal(new Set([...controlled.controls, ...copies.controls].map(control => control.id)).size, 12);
assert.deepEqual(controlled, controlledBefore);
const combined = normalizeProject({ ...controlled, layers: [...controlled.layers, ...copies.layers], controls: [...controlled.controls, ...copies.controls] });
assert.deepEqual(await readProjectFile(new Blob([serializeProject(combined)])), combined);

// All failures leave the original project untouched; nothing is truncated.
for (const options of [
  { count: 0 }, { count: 64 }, { count: 2.5 }, { count: Infinity }, { count: '3' },
  { mode: 'preset' }, { axis: 'q' }, { sweep: 361 }, { pivotSpace: 'screen' },
  { rotateCopies: 1 }, { positionStep: { x: NaN } }, { rotationStep: { z: Infinity } },
  { count: 2, positionStep: { x: 3000 } }, { count: 2, rotationStep: { x: 181 } },
  { mode: 'radial', count: 1, sweep: 180, axis: 'z', pivot: { x: 4000 } },
]) assert.throws(() => createArrangement(original, 'source', options));
assert.throws(() => createArrangement(original, 'missing'), /Choose a layer/);
const full = { ...original, layers: Array.from({ length: 64 }, (_, i) => pointLayer({ id: `layer-${i}` })) };
assert.throws(() => createArrangement(full, 'layer-0', { count: 1 }), /room for 0/);
assert.throws(() => createArrangement(controlled, 'source', { count: 24 }), /96 controls/);
const capacity = createArrangement(original, 'source', { count: 63 });
assert.equal(capacity.layers.length, 63);
assert.deepEqual(original, untouched);
console.log('Builder arrangements: linear/radial geometry, world/local pivots, composed rotations, independent controls, JSON roundtrip and atomic limits passed.');
