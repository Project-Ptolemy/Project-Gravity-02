import assert from 'node:assert/strict';
import { boundedTranslation, flattenVertices, selectionCenter, transformVertices } from '../docs/plugins/builder/geometry/vertices.mjs';

const source = [{ x: -10, y: 0, z: 5 }, { x: 10, y: 0, z: 5 }, { x: 100, y: 100, z: 100 }];
const untouched = structuredClone(source);
assert.deepEqual(selectionCenter(source, [0, 1, 1, -1, 99]), { x: 0, y: 0, z: 5 }, 'Only valid unique selected vertices contribute to the center');
assert.deepEqual(selectionCenter(source, []), { x: 0, y: 0, z: 0 });
assert.deepEqual(transformVertices(source, [0, 1], {
  scale: { x: 2 }, rotation: { z: 90 }, translation: { x: 3, y: 4, z: 5 }
}), [{ x: 3, y: -16, z: 10 }, { x: 3, y: 24, z: 10 }, source[2]], 'Transforms compose around the selected center without moving unselected vertices');
assert.deepEqual(transformVertices(source, [0, 1], { scale: { x: -1, z: 0 } }), [source[1], source[0], source[2]], 'Negative scale mirrors selected vertices');
assert.deepEqual(transformVertices(source, [0, 1], { rotation: { y: 90 } }), [{ x: 0, y: 0, z: 15 }, { x: 0, y: 0, z: -5 }, source[2]], 'Y-axis rotation follows the right-hand rule');
assert.deepEqual(transformVertices([{ x: 0, y: 1, z: 0 }, { x: 0, y: -1, z: 0 }], [0, 1], { rotation: { x: 90 } }), [{ x: 0, y: 0, z: 1 }, { x: 0, y: 0, z: -1 }]);
assert.deepEqual(flattenVertices(source, [0, 1], 'z', -25), [{ x: -10, y: 0, z: -25 }, { x: 10, y: 0, z: -25 }, source[2]]);
assert.deepEqual(transformVertices(source, [], { translation: { x: 50 } }), source);
assert.throws(() => transformVertices(source, [0, 1], { translation: { x: 4995 } }), /coordinate/, 'A transform that would clip a vertex is rejected as a whole');
assert.throws(() => transformVertices(source, [0, 1], { scale: { x: Infinity } }), /finite/);
assert.throws(() => transformVertices(source, [0, 1], { rotation: { z: NaN } }), /finite/);
assert.throws(() => flattenVertices(source, [0], 'q', 0), /axis/);
assert.throws(() => flattenVertices(source, [0], 'x', 5001), /coordinate/);
assert.deepEqual(boundedTranslation(source, [0, 1], { x: 6000, y: -6000, z: 10 }), { x: 4990, y: -5000, z: 10 });
const dragged = transformVertices(source, [0, 1], { translation: boundedTranslation(source, [0, 1], { x: 6000 }) });
assert.equal(dragged[1].x, 5000); assert.equal(dragged[1].x - dragged[0].x, 20, 'Dragging at the limit preserves the spacing of selected vertices');
assert.deepEqual(source, untouched, 'All operations preserve the source data, including rejected changes');
const precise = [{ x: 1.23456789, y: 2.34567891, z: 3.45678912 }];
assert.deepEqual(transformVertices(precise, [0]), precise, 'An identity transform preserves imported precision');
assert.equal(transformVertices(precise, [0], { translation: { x: 1 } })[0].z, precise[0].z, 'A planar drag preserves depth exactly');
assert.equal(flattenVertices(precise, [0], 'z', 0)[0].x, precise[0].x, 'Flattening preserves the other coordinates exactly');
const precisePair = [...precise, { x: -4.56789123, y: -5.67891234, z: 6.78912345 }];
for (const [axis, movedAxis] of [['x', 'y'], ['y', 'z'], ['z', 'x']]) {
  const result = transformVertices(precisePair, [0, 1], { rotation: { [axis]: 37 }, scale: { [movedAxis]: 2 }, translation: { [movedAxis]: 10 } });
  assert.deepEqual(result.map(point => point[axis]), precisePair.map(point => point[axis]), `${axis.toUpperCase()} rotation preserves its unchanged axis despite in-plane scaling and movement`);
}
let planar = [precise[0], { x: -4.56789123, y: -5.67891234, z: precise[0].z }];
for (let turn = 0; turn < 8; turn++) planar = transformVertices(planar, [0, 1], { rotation: { z: 45 } });
assert.ok(planar.every(point => point.z === precise[0].z), 'Repeated Z rotations preserve a planar selection\'s long-decimal depth exactly');
assert.deepEqual(transformVertices(precisePair, [0, 1], { rotation: { x: 180, y: 180, z: 180 } }), precisePair, 'Composed rotations equivalent to identity preserve imported coordinates');
console.log('Vertex operations: centroid, XYZ transforms, mirroring, flattening, atomic range validation, selection filtering and bounded group movement passed.');
