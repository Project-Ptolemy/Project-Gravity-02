import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import {
  LAYER_TYPES, PROPERTY_DEFS, createLayer, createProject, normalizeProject,
  sampleProject, getProperty, controlDivisor,
} from '../docs/plugins/builder/model.mjs';
import { exportLua, luaString } from '../docs/plugins/builder/exporter.mjs';
import { compilePath, flattenPath, samplePath } from '../docs/plugins/builder/geometry/path.mjs';

const projectOf = (layers, overrides = {}) => ({ version: 1, name: 'Test shape', parts: 120, pointSize: 1.5, layers, controls: [], ...overrides });
const near = (a, b, tolerance = 1e-8) => assert.ok(Math.abs(a - b) <= tolerance, `${a} ≈ ${b}`);
const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z);
const originLayer = (type, overrides = {}) => createLayer(type, { position: { x: 0, y: 0, z: 0 }, spin: 0, ...overrides });
const mean = values => values.reduce((sum, value) => sum + value, 0) / values.length;
const nearPoint = (actual, expected, tolerance = 1e-8) => {
  near(actual.x, expected.x, tolerance); near(actual.y, expected.y, tolerance); near(actual.z, expected.z, tolerance);
};
function uniformCdf(values, label, tolerance = 0.004) {
  for (const threshold of [0.1, 0.25, 0.5, 0.75, 0.9]) {
    const fraction = values.filter(value => value <= threshold).length / values.length;
    assert.ok(Math.abs(fraction - threshold) < tolerance, `${label} CDF at ${threshold}: ${fraction}`);
  }
}

for (const preset of ['orbit', 'helix', 'solar', 'blank']) {
  const project = createProject(preset);
  assert.deepEqual(normalizeProject(project), project);
  assert.equal(sampleProject(project).length, preset === 'blank' ? 0 : project.parts);
}
for (const type of LAYER_TYPES) {
  for (const fill of [false, true]) {
    for (const parts of [1, 17, 640]) {
      const layer = originLayer(type, { fill, spin: 17, spinX: -13, spinZ: 7, pulse: 90, wave: 10, rotation: { x: 10, y: 25, z: -30 }, scale: { x: 2, y: 0.5, z: 1.3 } });
      const project = projectOf([layer], { parts });
      for (const time of [-12.5, 0, 1.25, 1000]) {
        const points = sampleProject(project, time);
        assert.equal(points.length, parts);
        assert.ok(points.every(point => [point.x, point.y, point.z].every(Number.isFinite)), `${type}, ${fill}, ${parts}, ${time}: finite`);
        assert.ok(points.every(point => Math.hypot(point.x, point.y, point.z) < 1000), `${type}: animation remains bounded`);
        assert.deepEqual(sampleProject(project, time), points, `${type}: frozen time is deterministic`);
      }
    }
  }
}

// Check geometric invariants independently of implementation formulas.
{
  // A generic regular polygon can supply any side count without symbol presets.
  const triangle = originLayer('polygon', { radius: 10 });
  const corners = sampleProject(projectOf([triangle], { parts: 3 }));
  nearPoint(corners[0], { x: 0, y: 10, z: 0 });
  nearPoint(corners[1], { x: -Math.sqrt(75), y: -5, z: 0 });
  nearPoint(corners[2], { x: Math.sqrt(75), y: -5, z: 0 });
  const diamond = projectOf([originLayer('polygon', { sides: 4, radius: 10 })], { parts: 8 });
  for (const point of sampleProject(diamond)) { near(Math.abs(point.x) + Math.abs(point.y), 10); near(point.z, 0); }
  const filled = sampleProject(projectOf([originLayer('polygon', { sides: 4, radius: 10, fill: true })], { parts: 4096 }));
  assert.ok(filled.every(point => Math.abs(point.x) + Math.abs(point.y) <= 10 + 1e-10));
  near(mean(filled.map(point => point.x)), 0, 0.03);
  near(mean(filled.map(point => point.y)), 0, 0.03);
  // Uniform area within this diamond has E[x²+y²] = radius²/3.
  near(mean(filled.map(point => point.x ** 2 + point.y ** 2)), 100 / 3, 0.1);
  assert.deepEqual(sampleProject(diamond, -20), sampleProject(diamond, 50));
}
{
  // Unequal segments must allocate samples by length; open endpoints are exact.
  const path = { points: [{ x: 0, y: 0, z: 0 }, { x: 10, y: 0, z: 0 }, { x: 10, y: 30, z: 0 }], closed: false, smooth: false };
  const project = projectOf([originLayer('path', { path })], { parts: 5 });
  sampleProject(project).forEach((point, index) => nearPoint(point, [{ x: 0, y: 0, z: 0 }, { x: 10, y: 0, z: 0 }, { x: 10, y: 10, z: 0 }, { x: 10, y: 20, z: 0 }, { x: 10, y: 30, z: 0 }][index]));
  nearPoint(sampleProject({ ...project, parts: 1 })[0], { x: 10, y: 10, z: 0 });
  const closed = { ...path, closed: true };
  const closedTable = compilePath(closed);
  near(closedTable.total, 40 + Math.sqrt(1000));
  nearPoint(samplePath(closedTable, 0), path.points[0]);
  nearPoint(samplePath(closedTable, 1), path.points[0]);
  const smooth = { ...path, smooth: true };
  const flattened = flattenPath(smooth);
  assert.equal(flattened.length, 33);
  nearPoint(flattened[0], path.points[0]); nearPoint(flattened[16], path.points[1]); nearPoint(flattened[32], path.points[2]);
  assert.ok(flattened.some(point => point.x > 10 || point.y < 0), 'curves interpolate nodes with Catmull-Rom tangents');
  assert.deepEqual(flattenPath(smooth), flattened);
  assert.equal(compilePath(smooth), compilePath(structuredClone(smooth)), 'equivalent geometry reuses its arc-length table');
  const before = sampleProject(project);
  project.layers[0].path.points[2].y = 60;
  assert.notDeepEqual(sampleProject(project), before, 'editing a vertex invalidates cached geometry');
  assert.equal(before.at(-1).y, 30, 'sampling does not retain mutable point references');
  for (const smooth of [false, true]) for (const node of [{ x: 3, y: 7, z: -2 }, { x: 0.1, y: 0.2, z: 0.3 }]) {
    const repeated = originLayer('path', { path: { points: [node, node, node], closed: true, smooth }, tube: 4 });
    for (const point of sampleProject(projectOf([repeated]))) nearPoint(point, node);
  }
}
{
  // Tubes stay perpendicular to their path in all three drawing planes.
  for (const end of [{ x: 30, y: 40, z: 0 }, { x: 0, y: 0, z: 50 }, { x: 30, y: 0, z: 40 }]) {
    for (const fill of [false, true]) {
      const points = sampleProject(projectOf([originLayer('path', { path: { points: [{ x: 0, y: 0, z: 0 }, end] }, tube: 3, fill })], { parts: 4096 }));
      const distances = points.map(point => {
        const projection = (point.x * end.x + point.y * end.y + point.z * end.z) / 2500;
        return (point.x - end.x * projection) ** 2 + (point.y - end.y * projection) ** 2 + (point.z - end.z * projection) ** 2;
      });
      if (fill) uniformCdf(distances.map(value => value / 9), 'path tube cross-section');
      else distances.forEach(value => near(value, 9));
      const last = points.at(-1);
      near(last.x * end.x + last.y * end.y + last.z * end.z, 2500);
    }
  }
}
{
  const stored = [{ x: -12, y: 4, z: 8 }, { x: 30, y: 9, z: -7 }, { x: 5, y: -18, z: 2 }];
  const project = projectOf([originLayer('pointcloud', { path: { points: stored } })], { parts: 3 });
  sampleProject(project).forEach((point, index) => nearPoint(point, stored[index]));
  for (const parts of [1, 2, 17, 80]) {
    assert.ok(sampleProject({ ...project, parts }).every(point => stored.some(candidate => distance(point, candidate) < 1e-10)), 'point clouds never invent connecting edges');
  }
  const layer = originLayer('pointcloud', { path: { points: [{ x: 1, y: 2, z: 3 }] }, position: { x: 5, y: 6, z: 7 }, scale: { x: 2, y: 3, z: 4 } });
  for (const point of sampleProject(projectOf([layer]))) nearPoint(point, { x: 7, y: 12, z: 19 });
}
{
  for (const type of ['polygon', 'path', 'pointcloud']) {
    const created = createLayer(type);
    assert.equal(created.spin, 0); assert.equal(created.tube, 0);
    const { spin, tube, ...omitted } = created;
    const normalized = normalizeProject(projectOf([omitted])).layers[0];
    assert.equal(normalized.spin, 0); assert.equal(normalized.tube, 0);
  }
  const points = Array.from({ length: 4096 }, (_, index) => ({ x: index, y: 0, z: 0 }));
  assert.doesNotThrow(() => createLayer('path', { path: { points } }));
  assert.throws(() => createLayer('path', { path: { points: [...points, { x: 0, y: 0, z: 0 }] } }), /4096/);
  for (const path of [null, {}, { points: [] }, { points: [points[0]] }, { points: [points[0], null] }, { points: [points[0], {}] }, { points: [points[0], { x: Infinity, y: 0, z: 0 }] }, { points: [points[0], { x: 5001, y: 0, z: 0 }] }, { points: points.slice(0, 2), closed: 1 }, { points: points.slice(0, 2), smooth: 'yes' }]) {
    assert.throws(() => createLayer('path', { path }), /path|point|5000|finite|true or false/);
  }
  assert.doesNotThrow(() => createLayer('pointcloud', { path: { points: [points[0]] } }));
  for (const sides of [2, 129, 3.5, Infinity]) assert.throws(() => createLayer('polygon', { sides }), /sides/);
}

for (const type of ['sphere', 'ring']) {
  const project = projectOf([originLayer(type, { radius: 23 })]);
  for (const point of sampleProject(project)) {
    near(Math.hypot(point.x, point.y, point.z), 23);
    if (type === 'ring') near(point.y, 0);
  }
  project.layers[0].fill = true;
  const points = sampleProject(project);
  assert.ok(points.every(point => Math.hypot(point.x, point.y, point.z) <= 23));
  assert.ok(points.some(point => Math.hypot(point.x, point.y, point.z) < 12));
}
{
  // A sphere's volume grows as radius cubed; a disc's area grows as radius
  // squared. Checking these CDFs catches center-heavy radial interpolation.
  for (const [type, exponent] of [['sphere', 3], ['ring', 2]]) {
    const points = sampleProject(projectOf([originLayer(type, { radius: 23, fill: true })], { parts: 4096 }));
    const radii = points.map(p => Math.hypot(p.x, p.y, p.z) / 23);
    uniformCdf(radii.map(radius => radius ** exponent), `${type} interior measure`);
    near(mean(radii.map(radius => radius ** 2)), type === 'sphere' ? 3 / 5 : 1 / 2, 0.002);
  }
  const surface = sampleProject(projectOf([originLayer('sphere', { radius: 23 })], { parts: 4096 }));
  // Equal-area spherical bands have equal height, independent of longitude.
  uniformCdf(surface.map(p => (p.y / 23 + 1) / 2), 'sphere equal-area bands');
  near(mean(surface.map(p => p.x)), 0, 0.02);
  near(mean(surface.map(p => p.y)), 0, 0.02);
  near(mean(surface.map(p => p.z)), 0, 0.02);
}
{
  for (const fill of [false, true]) {
    const points = sampleProject(projectOf([originLayer('torus', { radius: 23, tube: 7, fill })], { parts: 4096 }));
    const crossSectionRadii = points.map(p => ((Math.hypot(p.x, p.z) - 23) ** 2 + p.y ** 2) / 49);
    if (fill) {
      assert.ok(crossSectionRadii.every(radius => radius <= 1 + 1e-10));
      uniformCdf(crossSectionRadii, 'torus filled cross-section');
    } else {
      crossSectionRadii.forEach(radius => near(radius, 1));
    }
    // Surface/volume elements on the outside of a torus are larger than
    // on its inside. The analytical first moment detects uniform-angle bias.
    near(mean(points.map(p => Math.hypot(p.x, p.z))), 23 + 49 / ((fill ? 4 : 2) * 23), 0.02);
  }
}
{
  // Integrating the conical cross-section gives F(h)=1-(1-h)^3 for
  // volume and F(h)=1-(1-h)^2 for lateral area, where h is base-to-tip.
  for (const fill of [false, true]) {
    const points = sampleProject(projectOf([originLayer('cone', { radius: 30, height: 80, fill })], { parts: 4096 }));
    const heights = points.map(p => (p.y + 40) / 80);
    assert.ok(heights.every(height => height > 0 && height < 1));
    uniformCdf(heights.map(height => 1 - (1 - height) ** (fill ? 3 : 2)), `cone ${fill ? 'volume' : 'lateral area'}`);
    near(mean(heights), fill ? 1 / 4 : 1 / 3, 0.0002);
    const radii = points.map((p, index) => Math.hypot(p.x, p.z) / (30 * (1 - heights[index])));
    assert.ok(radii.every(radius => radius <= 1 + 1e-10), 'cone points stay within their cross-section');
    if (fill) uniformCdf(radii.map(radius => radius ** 2), 'cone radial cross-section');
    else radii.forEach(radius => near(radius, 1));
  }
  for (const fill of [false, true]) {
    const points = sampleProject(projectOf([originLayer('cylinder', { radius: 12, height: 70, fill })], { parts: 4096 }));
    uniformCdf(points.map(p => (p.y + 35) / 70), 'cylinder height');
    const radii = points.map(p => Math.hypot(p.x, p.z) / 12);
    if (fill) uniformCdf(radii.map(radius => radius ** 2), 'cylinder radial cross-section');
    else radii.forEach(radius => near(radius, 1));
  }
}
{
  const box = projectOf([originLayer('box', { width: 30, height: 40, depth: 50 })]);
  const faces = new Set();
  for (const p of sampleProject(box)) {
    assert.ok(Math.abs(p.x) <= 15 && Math.abs(p.y) <= 20 && Math.abs(p.z) <= 25);
    if (Math.abs(p.x) === 15) faces.add('x' + Math.sign(p.x));
    if (Math.abs(p.y) === 20) faces.add('y' + Math.sign(p.y));
    if (Math.abs(p.z) === 25) faces.add('z' + Math.sign(p.z));
  }
  assert.equal(faces.size, 6, 'all six box faces are occupied');
  const many = sampleProject({ ...box, parts: 4096 });
  const area = 2 * (30 * 40 + 30 * 50 + 40 * 50);
  for (const [axis, halfExtent, faceArea] of [['x', 15, 40 * 50], ['y', 20, 30 * 50], ['z', 25, 30 * 40]]) {
    for (const sign of [-1, 1]) {
      const count = many.filter(p => p[axis] === halfExtent * sign).length;
      near(count / many.length, faceArea / area, 2 / many.length);
    }
  }
}
{
  const grid = projectOf([originLayer('grid', { width: 10, depth: 10 })], { parts: 25 });
  const points = sampleProject(grid);
  assert.equal(new Set(points.map(p => p.x)).size, 5);
  assert.equal(new Set(points.map(p => p.z)).size, 5);
  assert.equal(new Set(points.map(p => [p.x, p.z].join(','))).size, 25);
}
{
  const base = originLayer('helix', { tube: 0, radius: 10, height: 50, turns: 2 });
  const original = sampleProject(projectOf([base]));
  const moved = sampleProject(projectOf([{ ...base, position: { x: 80, y: -10, z: 45 } }]));
  for (let i = 0; i < original.length; i++) {
    near(moved[i].x - original[i].x, 80); near(moved[i].y - original[i].y, -10); near(moved[i].z - original[i].z, 45);
  }
  const rotated = sampleProject(projectOf([{ ...base, rotation: { x: 0, y: 90, z: 0 } }]));
  for (let i = 0; i < original.length; i++) {
    near(rotated[i].x, original[i].z); near(rotated[i].z, -original[i].x); near(rotated[i].y, original[i].y);
  }
  const animated = projectOf([{ ...base, spin: 90 }]);
  const negative = sampleProject(animated, -1), positive = sampleProject(animated, 1);
  assert.ok(distance(negative[0], positive[0]) > 19, 'negative formation time reverses spin');
}
{
  // Rotation must preserve both radii and pairwise distances, including
  // combined XYZ rotations and negative animation times.
  const base = originLayer('box', { width: 17, height: 31, depth: 43, fill: true });
  const reference = sampleProject(projectOf([base]));
  const animated = { ...base, rotation: { x: 37, y: -61, z: 123 }, spinX: 75, spin: -23, spinZ: 41 };
  for (const time of [-13.25, 0, 6.5]) {
    const rotated = sampleProject(projectOf([animated]), time);
    for (let index = 0; index < reference.length; index++) {
      near(Math.hypot(rotated[index].x, rotated[index].y, rotated[index].z), Math.hypot(reference[index].x, reference[index].y, reference[index].z));
      if (index) near(distance(rotated[index - 1], rotated[index]), distance(reference[index - 1], reference[index]));
    }
  }
  // The three quarter turns establish handedness and XYZ composition order.
  const rotations = { x: p => ({ x: p.x, y: -p.z, z: p.y }), y: p => ({ x: p.z, y: p.y, z: -p.x }), z: p => ({ x: -p.y, y: p.x, z: p.z }) };
  for (const [axis, rotate] of Object.entries(rotations)) {
    const points = sampleProject(projectOf([{ ...base, rotation: { x: 0, y: 0, z: 0, [axis]: 90 } }]));
    points.forEach((point, index) => nearPoint(point, rotate(reference[index])));
  }
  const composed = sampleProject(projectOf([{ ...base, rotation: { x: 90, y: 90, z: 90 } }]));
  composed.forEach((point, index) => nearPoint(point, rotations.z(rotations.y(rotations.x(reference[index])))));
}

const addedProperties = ['orbitRadius', 'orbitSpeed', 'orbitAspect', 'orbitTiltX', 'orbitTiltZ', 'orbitPhase', 'bobAmount', 'bobSpeed', 'bobPhase', 'waveCount', 'wavePhase', 'pulsePhase', 'twist', 'taper', 'scatter', 'timeScale', 'timeOffset'];
for (const property of addedProperties) assert.ok(PROPERTY_DEFS[property], `${property} has a validated, exportable definition`);
{
  const layer = originLayer('sphere', { radius: 0, orbitRadius: 12, orbitSpeed: 90, orbitAspect: 0.5 });
  const orbit = projectOf([layer], { parts: 1 });
  for (const [time, expected] of [[0, [12, 0, 0]], [1, [0, 0, 6]], [2, [-12, 0, 0]], [3, [0, 0, -6]], [-1, [0, 0, -6]]]) {
    nearPoint(sampleProject(orbit, time)[0], { x: expected[0], y: expected[1], z: expected[2] });
  }
  for (const time of [-9.25, -0.3, 0, 1.7, 12.125]) {
    const point = sampleProject(orbit, time)[0];
    near(point.x ** 2 / 144 + point.z ** 2 / 36, 1);
    nearPoint(sampleProject(orbit, time + 4)[0], point);
  }
  nearPoint(sampleProject(projectOf([{ ...layer, orbitTiltX: 90 }], { parts: 1 }), 1)[0], { x: 0, y: -6, z: 0 });
  nearPoint(sampleProject(projectOf([{ ...layer, orbitTiltZ: 90 }], { parts: 1 }))[0], { x: 0, y: 12, z: 0 });
  nearPoint(sampleProject(projectOf([{ ...layer, orbitTiltX: 90, orbitTiltZ: 90 }], { parts: 1 }), 1)[0], { x: 6, y: 0, z: 0 });
  nearPoint(sampleProject(projectOf([{ ...layer, orbitPhase: 90 }], { parts: 1 }))[0], { x: 0, y: 0, z: 6 });
  const translated = { ...layer, position: { x: 40, y: 50, z: 60 }, rotation: { x: 38, y: 73, z: -41 }, spinX: 17, spin: -92, spinZ: 73, scale: { x: 2, y: 3, z: 4 } };
  nearPoint(sampleProject(projectOf([translated], { parts: 1 }), 1)[0], { x: 40, y: 50, z: 66 });
}
{
  const layer = originLayer('sphere', { radius: 0, bobAmount: 8, bobSpeed: 0.5 });
  for (const [time, expected] of [[0, 0], [0.5, 8], [1, 0], [1.5, -8], [-0.5, -8]]) {
    const point = sampleProject(projectOf([layer], { parts: 1 }), time)[0];
    nearPoint(point, { x: 0, y: expected, z: 0 });
    nearPoint(sampleProject(projectOf([layer], { parts: 1 }), time + 2)[0], point);
  }
  near(sampleProject(projectOf([{ ...layer, bobPhase: 90 }]))[0].y, 8);
  const transformed = { ...layer, position: { x: 3, y: 10, z: -8 }, rotation: { x: 90, y: 90, z: 90 }, scale: { x: 2, y: 3, z: 4 } };
  nearPoint(sampleProject(projectOf([transformed], { parts: 1 }), 0.5)[0], { x: 3, y: 18, z: -8 });
}
{
  const layer = originLayer('sphere', { radius: 10, pulse: 50, pulseSpeed: 0.5 });
  for (const [time, expected] of [[0, 10], [0.5, 15], [1, 10], [1.5, 5], [-0.5, 5]]) {
    for (const point of sampleProject(projectOf([layer], { parts: 17 }), time)) near(Math.hypot(point.x, point.y, point.z), expected);
  }
  for (const point of sampleProject(projectOf([{ ...layer, pulsePhase: 90 }], { parts: 17 }))) near(Math.hypot(point.x, point.y, point.z), 15);
  const wave = originLayer('line', { width: 0, tube: 0, wave: 6, waveSpeed: 0.5, waveCount: 2 });
  for (const [time, wavePhase, sign] of [[0, 0, 1], [1, 0, -1], [-1, 0, -1], [0, 180, -1], [2, 0, 1]]) {
    const points = sampleProject(projectOf([{ ...wave, wavePhase }], { parts: 4 }), time);
    points.forEach((point, index) => nearPoint(point, { x: 0, y: 6 * sign * (index % 2 ? -1 : 1), z: 0 }));
  }
}
{
  const cylinder = originLayer('cylinder', { radius: 10, height: 40 });
  const original = sampleProject(projectOf([cylinder], { parts: 4 }));
  const tapered = sampleProject(projectOf([{ ...cylinder, taper: 50 }], { parts: 4 }));
  for (let index = 0; index < 4; index++) {
    near(tapered[index].y, original[index].y);
    near(Math.hypot(tapered[index].x, tapered[index].z), [6.25, 8.75, 11.25, 13.75][index]);
  }
  const twist = sampleProject(projectOf([originLayer('ring', { radius: 10, twist: 360 })], { parts: 2 }));
  twist.forEach(point => nearPoint(point, { x: -10, y: 0, z: 0 }));
  const twisted = sampleProject(projectOf([{ ...cylinder, twist: 270 }], { parts: 4 }));
  twisted.forEach((point, index) => {
    near(point.y, original[index].y);
    near(Math.hypot(point.x, point.z), 10);
  });
}
{
  const layer = originLayer('sphere', { radius: 0, scatter: 7 });
  const project = projectOf([layer], { parts: 4096 });
  const scattered = sampleProject(project);
  for (const axis of ['x', 'y', 'z']) {
    assert.ok(scattered.every(point => point[axis] >= -7 && point[axis] <= 7));
    uniformCdf(scattered.map(point => (point[axis] + 7) / 14), `scatter ${axis}`);
    near(mean(scattered.map(point => point[axis])), 0, 0.02);
  }
  assert.deepEqual(sampleProject(project, -20), scattered, 'scatter must not reroll as formation time changes');
  assert.deepEqual(sampleProject(project, 17.25), scattered, 'scatter remains stable at frozen and future times');
  assert.deepEqual(sampleProject({ ...project, parts: 17 }), scattered.slice(0, 17), 'scatter remains stable when part count changes');
  const doubled = sampleProject(projectOf([{ ...layer, scatter: 14 }], { parts: 17 }));
  doubled.forEach((point, index) => nearPoint(point, { x: scattered[index].x * 2, y: scattered[index].y * 2, z: scattered[index].z * 2 }));
}
{
  // Project version 1 files predate these controls. Their omitted fields must
  // preserve the original four-point ring, including zero/default motion.
  const layer = originLayer('ring', { radius: 10 });
  const legacy = { ...layer };
  for (const property of addedProperties) delete legacy[property];
  const project = projectOf([legacy], { parts: 4 });
  assert.deepEqual(sampleProject(project), sampleProject(projectOf([layer], { parts: 4 })));
  const diagonal = Math.sqrt(50);
  const corners = [[diagonal, diagonal], [-diagonal, diagonal], [-diagonal, -diagonal], [diagonal, -diagonal]];
  sampleProject(project, -50).forEach((point, index) => nearPoint(point, { x: corners[index][0], y: 0, z: corners[index][1] }));
}
{
  const layer = originLayer('helix', { spinX: 13, spin: -31, spinZ: 8, pulse: 29, pulseSpeed: 0.7, pulsePhase: 42, wave: 4, waveCount: 2.5, waveSpeed: 0.3, wavePhase: -38, orbitRadius: 17, orbitSpeed: 27, orbitAspect: 0.7, orbitTiltX: 21, orbitTiltZ: -15, orbitPhase: 71, bobAmount: 5, bobSpeed: 0.2, bobPhase: -20, twist: 45, taper: 30, scatter: 1.5 });
  const reference = projectOf([layer], { parts: 37 });
  const clocks = [[-2, 1.25], [0, -3.5], [0.5, 7], [1, 0]];
  for (const [timeScale, timeOffset] of clocks) {
    const adjusted = projectOf([{ ...layer, timeScale, timeOffset }], { parts: 37 });
    for (const time of [-9.2, 0, 12.75]) {
      const expected = sampleProject(reference, time * timeScale + timeOffset);
      const actual = sampleProject(adjusted, time);
      actual.forEach((point, index) => nearPoint(point, expected[index]));
      assert.deepEqual(sampleProject(adjusted, time), actual, 're-evaluating a frozen pose is deterministic');
    }
  }
  for (const property of addedProperties) {
    for (const value of [PROPERTY_DEFS[property].min, PROPERTY_DEFS[property].max]) {
      const extreme = projectOf([{ ...layer, [property]: value }], { parts: 17 });
      for (const time of [-1000, 0, 1000]) assert.ok(sampleProject(extreme, time).every(point => [point.x, point.y, point.z].every(Number.isFinite)), `${property}=${value} remains finite`);
    }
  }
}
{
  const first = originLayer('sphere', { weight: 1 });
  const second = originLayer('ring', { weight: 3 });
  const hidden = originLayer('box', { visible: false, weight: 20 });
  for (const parts of [1, 2, 7, 100, 512, 8192]) {
    const points = sampleProject(projectOf([first, second, hidden], { parts }));
    assert.equal(points.length, parts);
    assert.equal(points.filter(p => p.layerId === first.id).length, Math.floor(parts / 4));
    assert.ok(points.every(p => p.layerId !== hidden.id));
  }
  assert.deepEqual(sampleProject(projectOf([{ ...first, weight: 0 }])), []);
  assert.throws(() => exportLua(projectOf([{ ...first, weight: 0 }])), /positive part weight/);
}

const controlledLayer = originLayer('ring', { radius: 10 });
const controlled = projectOf([controlledLayer], { controls: [
  { id: 'radius', name: 'Orbit radius', layerId: controlledLayer.id, property: 'radius', min: 5, max: 40, default: 20 },
  { id: 'lift', name: 'Lift', layerId: controlledLayer.id, property: 'position.y', min: -20, max: 20, default: 2 },
] });
near(Math.hypot(sampleProject(controlled)[0].x, sampleProject(controlled)[0].z), 20);
near(sampleProject(controlled)[0].y, 2);
near(Math.hypot(sampleProject(controlled, 0, { radius: 30 })[0].x, sampleProject(controlled, 0, { radius: 30 })[0].z), 30);
near(sampleProject(controlled, 0, { lift: 100 })[0].y, 20, 0);
near(sampleProject(controlled, 0, { radius: NaN })[0].y, 2);
assert.equal(controlledLayer.radius, 10, 'control preview never mutates saved geometry');
assert.equal(getProperty(controlledLayer, 'scale.x'), 1);
const precise = {
  ...controlled,
  controls: [{ ...controlled.controls[0], min: 0.121, max: 0.129, default: 0.125 }],
};
assert.equal(controlDivisor(precise.controls[0]), 1000, 'narrow fractional sliders retain useful precision');
const preciseLua = exportLua(precise);
assert.ok(preciseLua.includes('Min = 121, Max = 129, Div = 1000, Default = 0.125'));
assert.ok(preciseLua.includes('(×0.001)'));
assert.doesNotThrow(() => normalizeProject({ ...precise, controls: [{ ...precise.controls[0], min: 0.123456, max: 0.123457, default: 0.123456 }] }));
assert.throws(() => normalizeProject({ ...precise, controls: [{ ...precise.controls[0], min: 0.123456, max: 0.123457, default: 0.1234565 }] }), /decimal|precision/i);
assert.equal(controlDivisor({ ...precise.controls[0], min: 0.1, max: 0.1 + 0.2, default: 0.2 }), 10, 'ordinary floating-point noise does not inflate slider precision');

for (const input of [null, [], 'shape']) assert.throws(() => normalizeProject(input), /JSON object/);
assert.throws(() => normalizeProject({ ...controlled, version: 2 }), /version/);
assert.throws(() => normalizeProject({ ...controlled, parts: 0 }), /part count/);
assert.throws(() => normalizeProject({ ...controlled, parts: 1.5 }), /whole number/);
assert.throws(() => normalizeProject({ ...controlled, parts: 8193 }), /part count/);
assert.throws(() => normalizeProject({ ...controlled, layers: [null] }), /Layer 1/);
assert.throws(() => normalizeProject({ ...controlled, layers: [{ ...controlledLayer, radius: Infinity }] }), /finite number/);
assert.throws(() => normalizeProject({ ...controlled, layers: [{ ...controlledLayer, type: 'script' }] }), /unsupported shape/);
assert.throws(() => normalizeProject({ ...controlled, layers: [{ ...controlledLayer, color: 'url(evil)' }] }), /color/);
assert.throws(() => normalizeProject({ ...controlled, layers: [controlledLayer, controlledLayer] }), /Duplicate layer ID/);
assert.throws(() => normalizeProject({ ...controlled, layers: [{ ...controlledLayer, visible: 'false' }] }), /true or false/);
assert.throws(() => normalizeProject({ ...controlled, layers: [{ ...controlledLayer, scale: { x: 0 } }] }), /Scale X/);
assert.throws(() => normalizeProject({ ...controlled, controls: [{ ...controlled.controls[0], min: 40, max: 5 }] }), /minimum/);
assert.throws(() => normalizeProject({ ...controlled, controls: [{ ...controlled.controls[0], default: 500 }] }), /default/);
assert.throws(() => normalizeProject({ ...controlled, controls: [{ ...controlled.controls[0], layerId: 'missing' }] }), /does not exist/);
assert.throws(() => normalizeProject({ ...controlled, controls: [{ ...controlled.controls[0], property: '__proto__.x' }] }), /unsupported property/);
assert.throws(() => normalizeProject({ ...controlled, controls: [controlled.controls[0], { ...controlled.controls[0], id: 'other' }] }), /already has a control/);
assert.throws(() => normalizeProject({ ...controlled, name: 'Injected\nreturn nil' }), /control characters/);
assert.throws(() => sampleProject(controlled, NaN), /finite number/);
const extra = normalizeProject({ ...controlled, executable: 'evil', layers: [{ ...controlledLayer, onClick: 'evil' }] });
assert.ok(!('executable' in extra)); assert.ok(!('onClick' in extra.layers[0]));
assert.equal(Object.prototype.polluted, undefined);

const nastyName = '"; error(\'injected\'); -- ]=] 🪐';
const nasty = { ...controlled, name: nastyName, controls: [{ ...controlled.controls[0], name: nastyName }] };
const source = exportLua(nasty);
assert.ok(source.includes('local NAME = ' + luaString('Shape Builder: ' + nastyName)));
assert.ok(source.includes('Div = 10, Default = 20, ExactMax = true'));
assert.ok(source.includes('Min = 50, Max = 400'));
assert.ok(source.includes('d.slot_n or st.actual_count or x6.n'));
assert.ok(source.includes('(x1.k10 * x9.c1), target'));
assert.ok(!source.includes('HttpGet') && !source.includes('require('));
assert.throws(() => exportLua(createProject('blank')), /visible layer/);
{
  const hidden = createLayer('helix', { visible: false });
  const project = { ...controlled, layers: [...controlled.layers, hidden], controls: [...controlled.controls, { id: 'hidden-control', name: 'HIDDEN', layerId: hidden.id, property: 'radius', min: 1, max: 100, default: 10 }] };
  const lua = exportLua(project);
  assert.ok(!lua.includes('hidden-control') && !lua.includes('HIDDEN'));
  assert.ok(!lua.includes('["type"] = "helix"'));
}

// Execute the generated module itself. Numeric parity covers the serialization,
// exported controls, all primitive branches, transform order, and runtime slots.
const executables = [process.env.LUAU, process.env.LUAJIT, 'luajit', 'luau', 'lua'].filter(Boolean);
const executable = executables.find(candidate => !spawnSync(candidate, ['-v'], { encoding: 'utf8' }).error);
if (executable) {
  const cases = [];
  const nodes = [{ x: -20, y: 9, z: 0 }, { x: -10, y: 9, z: 0 }, { x: 10, y: -7, z: 40 }, { x: 10, y: -7, z: 40 }, { x: 18, y: 22, z: 40 }];
  const largePath = originLayer('path', { path: { points: Array.from({ length: 4096 }, (_, i) => ({ x: i, y: Math.sin(i) * 17, z: Math.cos(i) * 13 })), closed: true, smooth: true } });
  cases.push({ project: projectOf([largePath], { parts: 17 }), time: 0, values: {} });
  cases.push({ project: projectOf([originLayer('path', { path: { points: Array.from({ length: 3 }, () => ({ x: 0.1, y: 0.2, z: 0.3 })), smooth: true, closed: true }, tube: 4 })], { parts: 7 }), time: 0, values: {} });
  for (const closed of [false, true]) for (const smooth of [false, true]) for (const fill of [false, true]) {
    const layer = originLayer('path', {
      path: { points: nodes, closed, smooth }, tube: 2.5, fill,
      spin: -17, spinX: 9, spinZ: 3, rotation: { x: 20, y: -13, z: 34 },
      scale: { x: 0.7, y: 1.4, z: 2 }, wave: 2, pulse: 12, twist: 31,
    });
    for (const parts of [1, 2, 47]) cases.push({ project: projectOf([layer], { parts }), time: -2.3, values: {} });
  }
  for (const type of ['path', 'pointcloud']) {
    for (const points of [nodes, [nodes[0], nodes[0]], [{ x: 0, y: 0, z: 0 }, { x: 0, y: 0, z: 50 }]]) {
      cases.push({ project: projectOf([originLayer(type, { path: { points, closed: true, smooth: true }, tube: 3 })], { parts: 31 }), time: 0, values: {} });
    }
  }
  const polygon = originLayer('polygon', { radius: 30, sides: 6, tube: 1.4 });
  const sidesControl = { id: 'sides', name: 'Sides', property: 'sides', layerId: polygon.id, min: 3, max: 128, default: 6 };
  for (const fill of [false, true]) for (const sides of [3, 6.6, 128, 500]) {
    cases.push({ project: projectOf([{ ...polygon, fill }], { parts: 101, controls: [sidesControl] }), time: 1.5, values: { sides } });
  }
  assert.throws(() => normalizeProject(projectOf([polygon], { controls: [{ ...sidesControl, default: 6.5 }] })), /whole numbers/);
  for (const fill of [false, true]) {
    const layers = LAYER_TYPES.map((type, index) => originLayer(type, {
      fill, weight: index % 3 + 1, radius: 22, height: 34, width: 35, depth: 23, tube: 2.5,
      turns: 2.3, arc: 285, phase: 47, spin: -18, spinX: 7, spinZ: -4,
      wave: 3, waveSpeed: 0.35, pulse: 27, pulseSpeed: 0.75,
      timeScale: -0.75, timeOffset: 1.5, pulsePhase: 17, waveCount: 2.3, wavePhase: -29,
      orbitRadius: 17, orbitSpeed: -31, orbitAspect: 0.65, orbitTiltX: 28, orbitTiltZ: -19, orbitPhase: 75,
      bobAmount: 7, bobSpeed: 0.45, bobPhase: -35, twist: 140, taper: -27, scatter: 2.25,
      position: { x: 3, y: 20, z: -2 }, rotation: { x: -24, y: 11, z: 35 }, scale: { x: 0.7, y: 1.3, z: 1.8 },
    }));
    for (const parts of [1, 17, 190]) for (const time of [-3.25, 0, 2.5]) cases.push({ project: projectOf(layers, { parts }), time, values: {} });
  }
  cases.push({ project: nasty, time: 0, values: {} });
  cases.push({ project: controlled, time: 2.5, values: { radius: 33.25, lift: -8.75 } });
  cases.push({ project: controlled, time: -1, values: { radius: 300, lift: -100 } });
  cases.push({ project: precise, time: -3.25, values: { radius: 0.127 } });
  const boundLayer = originLayer('torus', {
    radius: 20, tube: 4, wave: 3, pulse: 25,
    timeScale: 0.5, timeOffset: -2.25, pulsePhase: 17, waveCount: 2.3, wavePhase: -29,
    orbitRadius: 17, orbitSpeed: -31, orbitAspect: 0.65, orbitTiltX: 28, orbitTiltZ: -19, orbitPhase: 75,
    bobAmount: 7, bobSpeed: 0.45, bobPhase: -35, twist: 140, taper: -27, scatter: 2.25,
  });
  const allControls = addedProperties.map(property => ({ id: property, name: property, layerId: boundLayer.id, property, min: PROPERTY_DEFS[property].min, max: PROPERTY_DEFS[property].max, default: boundLayer[property] }));
  const boundProject = projectOf([boundLayer], { parts: 31, controls: allControls });
  for (const time of [-12.75, 0, 15]) {
    cases.push({ project: boundProject, time, values: {} });
    cases.push({ project: boundProject, time, values: Object.fromEntries(allControls.map(control => [control.id, control.min])) });
    cases.push({ project: boundProject, time, values: Object.fromEntries(allControls.map(control => [control.id, control.max])) });
  }
  // Horn/spindle tori and zero dimensions must stay finite in both runtimes.
  for (const [radius, tube] of [[4, 4], [2, 4], [0, 4], [4, 0], [0, 0]]) {
    for (const fill of [false, true]) cases.push({ project: projectOf([originLayer('torus', { radius, tube, fill })], { parts: 31 }), time: 0, values: {} });
  }
  for (const type of ['cone', 'cylinder', 'box']) {
    for (const fill of [false, true]) cases.push({ project: projectOf([originLayer(type, { width: 0, height: 0, depth: 0, radius: 0, fill })], { parts: 7 }), time: -3, values: {} });
  }
  const header = `
local meta = {}
meta.__index = meta
Vector3 = {new = function(x, y, z) return setmetatable({X=x, Y=y, Z=z}, meta) end}
meta.__add = function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
meta.__sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
meta.__mul = function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
local compile = loadstring or load
local x1, x9 = {k10=20}, {c1=0.15}
local cen, p = Vector3.new(100, -40, 70), {Position=Vector3.new(-3, 2, 5)}
local function near(a,b, label) assert(math.abs(a-b)<0.0000001, label..": "..tostring(a).." != "..tostring(b)) end
local function check(source, count, t, values, expected)
    local module = assert(compile(source))()
    local c, x6 = {}, {pre={unrelated=true}, n=count}
    for _, control in ipairs(module.Controls) do c[control.Key] = control.Default end
    for key, value in pairs(values) do c[key] = value end
    module.px(t, c, x6, x9, x1)
    for i, point in ipairs(expected) do
        local velocity, target = module.f2(p, cen, {id=i}, t, c, x1, x6, x9)
        near(target.X, point[1]+cen.X, "target x"); near(target.Y, point[2]+cen.Y, "target y"); near(target.Z, point[3]+cen.Z, "target z")
        near(velocity.X, (target.X-p.Position.X)*3, "velocity x")
        -- Sorted formation slots override both original IDs and total held count.
        x6.n = count * 2
        local _, sorted = module.f2(p, cen, {id=40000+i, slot=i, slot_n=count}, t, c, x1, x6, x9)
        near(sorted.X, target.X, "slot x"); near(sorted.Y, target.Y, "slot y"); near(sorted.Z, target.Z, "slot z")
        x6.n = count
    end
    -- Natural ordering has no d.slot. Released parts leave noncontiguous IDs;
    -- these must still occupy distinct samples, including same-count reclaims.
    x6.a, x6.part_id_counter = {}, count * 13 + 40000
    for i = 1, count do x6.a[i] = {id=40000+i*13} end
    module.px(t, c, x6, x9, x1)
    for i, point in ipairs(expected) do
        local _, target = module.f2(p, cen, x6.a[i], t, c, x1, x6, x9)
        near(target.X, point[1]+cen.X, "sparse id x"); near(target.Y, point[2]+cen.Y, "sparse id y"); near(target.Z, point[3]+cen.Z, "sparse id z")
    end
    x6.a[count].id = x6.part_id_counter + 1
    x6.part_id_counter = x6.part_id_counter + 1
    module.px(t, c, x6, x9, x1)
    local _, replaced = module.f2(p, cen, x6.a[count], t, c, x1, x6, x9)
    near(replaced.X, expected[count][1]+cen.X, "reclaimed id x")
    module.cleanup(x6, x1); module.cleanup(x6, x1)
    assert(x6.pre.unrelated, "cleanup touched unrelated state")
    local entries = 0; for _ in pairs(x6.pre) do entries=entries+1 end
    assert(entries==1, "cleanup left state behind")
    -- Re-entry may call f2 before px; it must safely rebuild its own cache.
    local _, target = module.f2(p, cen, x6.a[1], t, c, x1, x6, x9)
    near(target.X, expected[1][1]+cen.X, "re-entry x")
end
`;
  const suite = cases.map(({ project, time, values }) => {
    const expected = sampleProject(project, time, values);
    const luaValues = '{' + Object.entries(values).map(([key, value]) => `[${luaString(key)}]=${value}`).join(',') + '}';
    const luaExpected = '{' + expected.map(point => `{${point.x},${point.y},${point.z}}`).join(',') + '}';
    return `check(${luaString(exportLua(project))}, ${project.parts}, ${time}, ${luaValues}, ${luaExpected})`;
  }).join('\n');
  const dir = mkdtempSync(join(tmpdir(), 'gravity-builder-test-'));
  try {
    const file = join(dir, 'builder-parity.lua');
    writeFileSync(file, header + suite + '\nprint("Exported Lua: browser geometry, controls, runtime slots and lifecycle parity passed.")\n');
    const result = spawnSync(executable, [file], { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    process.stdout.write(result.stdout);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
} else {
  console.log('Exported Lua runtime parity skipped: install luau/LuaJIT or set LUAU/LUAJIT to enable it.');
}
console.log(`Builder model: ${LAYER_TYPES.length} primitives, transforms, animation, weighting, controls, validation and export passed.`);
