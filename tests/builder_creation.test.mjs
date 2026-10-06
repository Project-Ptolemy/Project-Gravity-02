import assert from 'node:assert/strict';
import { compileFormula, sampleFormula } from '../docs/plugins/builder/geometry/formula.mjs';
import { readCoordinates } from '../docs/plugins/builder/importers/geometry.mjs';

const near = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-10, `${actual} should equal ${expected}`);
const value = (source, u = 0, v = 0) => compileFormula(source)(u, v);
const point = (actual, expected) => ['x', 'y', 'z'].forEach((axis, i) => near(actual[axis], expected[i]));

// Arithmetic follows mathematical precedence, including right-associative
// powers and unary signs. Scientific coordinates accept either exponent case.
for (const [source, expected] of [
  ['2 + 3 * 4', 14], ['(2 + 3) * 4', 20], ['18 / 3 / 2', 3],
  ['10 - 3 - 2', 5], ['13 % 5', 3], ['2 ^ 3 ^ 2', 512],
  ['2 ** 3 ** 2', 512], ['(2 ^ 3) ^ 2', 64], ['-2 ^ 2', -4],
  ['(-2) ^ 2', 4], ['2 ^ -2', 0.25], ['-2 ^ -2', -0.25],
  ['+3 * -2', -6], ['.5 + 1.', 1.5], ['1e2 + 2e-1', 100.2],
  ['1E2 + 2E-1', 100.2], ['1e+2', 100],
]) near(value(source), expected);
near(value('u * 10 + v * 2', 0.5, 0.25), 5.5);
near(value('tau / pi'), 2);
near(value('sin(pi / 2) + cos(0) + tan(0)'), 2);
near(value('asin(1) + acos(0) + atan(1)'), Math.PI * 1.25);
near(value('atan2(1, -1)'), Math.PI * 0.75);
near(value('sqrt(9) + abs(-2) + floor(2.9) + ceil(2.1) + round(2.2)'), 12);
near(value('exp(log(2)) + min(3, 4) + max(3, 4) + pow(2, 3)'), 17);
near(value('min(max(-u, -3), pow(2, v))', 5, 2), -3);
near(value('  \n sin ( u * tau ) \t ', 0.25), 1);

// Untrusted formulas cannot reach JavaScript identifiers, objects or code.
for (const source of [
  '', ' ', 'x', 'Infinity', 'NaN', 'Math.sin(u)', 'globalThis',
  'constructor(1)', 'toString(1)', 'u.constructor', 'u[0]', 'u=1',
  'alert(1)', 'eval(1)', '1;2', '`1`', '"1"', '(() => 1)()',
  'sin u', 'sin()', 'sin(1,2)', 'atan2(1)', 'max(1,2,3)',
  '1 2', '2u', '(1+2', '1+2)', '1+', '*2', '--2', '1e309',
]) assert.throws(() => compileFormula(source), undefined, `Reject formula: ${source}`);
for (const source of [null, 5, {}, '1'.repeat(501), '('.repeat(41) + '1' + ')'.repeat(41)]) {
  assert.throws(() => compileFormula(source));
}
for (const source of ['1 / 0', '0 / 0', 'sqrt(-1)', 'log(0)', 'acos(2)', 'exp(1000)', '5001', '-5001']) {
  assert.throws(() => value(source), /undefined value|outside/, source);
}
near(value('-5000'), -5000); near(value('5000'), 5000);
assert.throws(() => value('u', NaN), /undefined value/);

const line = sampleFormula({ x: 'u * 6', y: '2*u - 1', z: '0', samples: 4 });
assert.equal(line.type, 'path');
assert.equal(line.path.closed, false);
assert.equal(line.path.smooth, false);
assert.equal(line.path.points.length, 4);
point(line.path.points[0], [0, -1, 0]);
point(line.path.points[1], [2, -1 / 3, 0]);
point(line.path.points[3], [6, 1, 0]);
const circle = sampleFormula({ x: '2*cos(tau*u)', y: '2*sin(tau*u)', z: '0', samples: 4, closed: true });
assert.equal(circle.path.closed, true);
for (const [i, expected] of [[2, 0, 0], [0, 2, 0], [-2, 0, 0], [0, -2, 0]].entries()) {
  point(circle.path.points[i], expected);
}
const plane = sampleFormula({ mode: 'surface', x: '20*u', y: '10*v', z: 'u+v', samples: 3, rows: 2, closed: true });
assert.equal(plane.type, 'pointcloud');
assert.equal(plane.path.closed, false);
assert.equal(plane.path.points.length, 6);
point(plane.path.points[0], [0, 0, 0]);
point(plane.path.points[2], [20, 0, 1]);
point(plane.path.points[3], [0, 10, 1]);
point(plane.path.points[5], [20, 10, 2]);
const basic = { x: 'u', y: 'v', z: '0' };
assert.equal(sampleFormula({ ...basic, samples: 4096 }).path.points.length, 4096);
assert.equal(sampleFormula({ ...basic, mode: 'surface', samples: 64, rows: 64 }).path.points.length, 4096);
for (const samples of [0, 1, 2.5, 4097, Infinity, NaN, '16']) {
  assert.throws(() => sampleFormula({ ...basic, samples }), /samples/);
}
for (const rows of [0, 1, 2.5, Infinity, NaN, '2']) {
  assert.throws(() => sampleFormula({ ...basic, mode: 'surface', samples: 3, rows }), /surface/);
}
assert.throws(() => sampleFormula({ ...basic, mode: 'surface', samples: 65, rows: 64 }), /4,096/);
assert.throws(() => sampleFormula({ ...basic, mode: 'solid' }), /curve or surface/);
assert.throws(() => sampleFormula({ ...basic, x: '1 / (u - .5)', samples: 3 }), /u=0\.500, v=0\.000/);

// Coordinate readers preserve supplied geometry, default only omitted Z to
// zero, and reject incomplete rows instead of silently shifting columns.
const expected = [{ x: 1, y: 2, z: 3 }, { x: -4.5, y: 0, z: 6 }];
for (const source of [
  'x,y,z\r\n1,2,3\r\n-4.5,0,6',
  '# points\n\nX Y Z\n1 2 3\n-4.5 0 6\n',
  'x;y;z\n1; 2; 3\n-4.5; 0; 6',
  '1e0,2E0,3\n-4.5,0,6',
  JSON.stringify([[1, 2, 3], [-4.5, 0, 6]]),
  JSON.stringify(expected),
  JSON.stringify({ points: expected }),
]) {
  const layers = readCoordinates(source, { closed: true });
  assert.equal(layers.length, 1);
  assert.equal(layers[0].type, 'path');
  assert.equal(layers[0].path.closed, true);
  assert.equal(layers[0].path.smooth, false);
  assert.deepEqual(layers[0].path.points, expected);
}
for (const source of ['x,y\n1,2\n3,4', '1 2\n3 4', '[[1,2],[3,4]]']) {
  assert.deepEqual(readCoordinates(source)[0].path.points, [{ x: 1, y: 2, z: 0 }, { x: 3, y: 4, z: 0 }]);
}
assert.deepEqual(readCoordinates('[{"x":1,"y":2,"z":3,"label":"a"},{"x":4,"y":5,"z":6}]')[0].path.points,
  [{ x: 1, y: 2, z: 3 }, { x: 4, y: 5, z: 6 }]);
assert.deepEqual(readCoordinates('5000,-5000,0', { type: 'pointcloud' })[0].path.points, [{ x: 5000, y: -5000, z: 0 }]);
assert.throws(() => readCoordinates('1,2,3'), /at least two/);
for (const source of [
  '', '# empty', 'x,y,z', '[]', '{}', '{"points":{}}', '[broken',
  '1,2,3,4\n5,6,7', '1,2,\n3,4,5', '1,,2\n3,4,5', '1, ,2\n3,4,5',
  '1; ;2\n3;4;5', 'NaN,2,3\n4,5,6', 'Infinity,2,3\n4,5,6',
  '5001,2,3\n4,5,6', '-5001,2,3\n4,5,6', 'word,2,3\n4,5,6',
  '[[1],[2]]', '[[1,2,3,4],[5,6,7]]', '[[1,2,null],[3,4,5]]',
  '[["1",2,3],[4,5,6]]', '[null,[1,2,3]]', '[true,[1,2,3]]',
  '[{"x":1,"y":2},[3,4,5]]', '[[1e309,2,3],[4,5,6]]',
]) assert.throws(() => readCoordinates(source), undefined, `Reject coordinates: ${source}`);
assert.throws(() => readCoordinates('1,2\n3,4', { type: 'mesh' }), /path or a point cloud/);
assert.throws(() => readCoordinates(null), /2 MB/);
assert.throws(() => readCoordinates('0'.repeat(2_000_001)), /2 MB/);
const many = Array.from({ length: 4096 }, (_, i) => [i, 0, 0]);
assert.equal(readCoordinates(JSON.stringify(many))[0].path.points.length, 4096);
assert.throws(() => readCoordinates(JSON.stringify([...many, [4096, 0, 0]])), /4,096/);

console.log('Builder creation: safe formula arithmetic, curve/surface sampling, limits and coordinate imports passed.');
