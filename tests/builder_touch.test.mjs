import assert from 'node:assert/strict';
import { Viewport } from '../docs/plugins/builder/viewport.mjs';

// Camera math and gesture lifecycle do not need a drawing context. Browser
// coverage in builder_touch_browser.cjs exercises real captured touch events.
globalThis.window = { addEventListener() {}, removeEventListener() {}, devicePixelRatio: 1 };
globalThis.document = { addEventListener() {}, removeEventListener() {} };
globalThis.ResizeObserver = class { observe() {} disconnect() {} };
const captured = new Set();
const bounds = { left: 10, top: 20, width: 390, height: 300 };
const canvas = {
  style: {}, getContext: () => null, getBoundingClientRect: () => bounds,
  addEventListener() {}, removeEventListener() {}, focus() {},
  setPointerCapture(id) { captured.add(id); }, hasPointerCapture: id => captured.has(id),
  releasePointerCapture(id) { captured.delete(id); },
};
const events = [];
let position = { x: 0, y: 0, z: 0 };
const viewport = new Viewport(canvas, {
  onSelect(id) { events.push(['select', id]); },
  onMoveStart() { events.push(['start']); },
  onMove(delta) { position = { ...delta }; events.push(['move']); },
  onMoveEnd({ cancelled }) { events.push(['end', cancelled]); if (cancelled) position = { x: 0, y: 0, z: 0 }; },
});
const event = (pointerId, x, y, pointerType = 'touch') => ({ pointerId, clientX: x + bounds.left, clientY: y + bounds.top, pointerType, button: 0, preventDefault() {} });
const near = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-8, `${actual} versus ${expected}`);
function reset() {
  viewport._cancelPointers(); viewport.setSelected(null); viewport.setAnchor(null);
  viewport.setView('front'); viewport.target = { x: 0, y: 0, z: 0 }; viewport.distance = 100;
  viewport._projected = []; events.length = 0; viewport._basis();
}
reset();
viewport._projected = [{ x: 195, y: 150, depth: 100, point: { x: 0, y: 0, z: 0, layerId: 'shape' } }];
viewport._pointerDown(event(1, 215, 150));
assert.equal(viewport.selected, 'shape', 'A small sample has a finger-sized touch target');
viewport._pointerMove(event(1, 219, 152));
assert.equal(events.filter(([name]) => name === 'start').length, 0, 'Finger jitter does not edit geometry');
viewport._pointerMove(event(1, 230, 150));
assert.notEqual(position.x, 0, 'A deliberate drag moves geometry');
viewport._pointerDown(event(2, 285, 150));
assert.deepEqual(position, { x: 0, y: 0, z: 0 }, 'A second finger rolls back the pending geometry edit');
assert.deepEqual(events.at(-1), ['end', true]);
assert.equal(viewport._moveDrag, null);
viewport._pointerMove(event(2, 310, 150));
assert.equal(events.filter(([name]) => name === 'start').length, 1, 'Pinch never starts another geometry edit');
viewport._pointerCancel(event(2, 310, 150));
const cancelledCamera = { target: { ...viewport.target }, distance: viewport.distance, yaw: viewport.yaw };
viewport._pointerMove(event(1, 120, 160));
assert.deepEqual({ target: viewport.target, distance: viewport.distance, yaw: viewport.yaw }, cancelledCamera, 'A trailing finger cannot orbit after cancellation');
viewport._pointerUp(event(1, 120, 160));
assert.equal(captured.size, 0);

for (const view of ['front', 'perspective']) {
  reset(); viewport.setView(view);
  const centroid = { x: 140, y: 120 };
  const anchor = viewport._planeIntersection(viewport._pointerRay(centroid.x, centroid.y), viewport.target, viewport._outward);
  viewport._pointerDown(event(1, 90, 120)); viewport._pointerDown(event(2, 190, 120));
  viewport._pointerMove(event(1, 60, 120)); viewport._pointerMove(event(2, 220, 120));
  near(viewport.distance, 100 / 1.6);
  const projected = viewport._project(anchor);
  near(projected.x, centroid.x); near(projected.y, centroid.y);
  const beforeThird = { target: { ...viewport.target }, distance: viewport.distance, yaw: viewport.yaw };
  viewport._pointerDown(event(3, 180, 220)); viewport._pointerMove(event(3, 140, 230));
  assert.deepEqual({ target: viewport.target, distance: viewport.distance, yaw: viewport.yaw }, beforeThird, `${view}: a third finger cannot change the camera`);
  viewport._pointerUp(event(3, 140, 230)); viewport._pointerUp(event(2, 220, 120));
  viewport._pointerMove(event(1, 100, 200)); viewport._pointerUp(event(1, 100, 200));
  assert.deepEqual({ target: viewport.target, distance: viewport.distance, yaw: viewport.yaw }, beforeThird, `${view}: lifting a pinch never becomes orbit or pan`);
  assert.equal(events.filter(([name]) => name === 'select').length, 0, 'Pinch release never deselects');
}

reset();
viewport._projected = [{ x: 195, y: 150, depth: 100, point: { x: 0, y: 0, z: 0, layerId: 'shape' } }];
viewport._pointerDown(event(1, 215, 150, 'mouse')); viewport._pointerUp(event(1, 215, 150, 'mouse'));
assert.equal(viewport.selected, null, 'Mouse selection keeps its precise hit radius');
const wheelPoint = { x: 60, y: 80 };
const wheelAnchor = viewport._planeIntersection(viewport._pointerRay(wheelPoint.x, wheelPoint.y), viewport.target, viewport._outward);
viewport._wheel({ ...event(1, wheelPoint.x, wheelPoint.y), deltaY: -100, deltaMode: 0 });
near(viewport._project(wheelAnchor).x, wheelPoint.x); near(viewport._project(wheelAnchor).y, wheelPoint.y);
const beforeInvalidZoom = viewport.distance;
for (const factor of [0, -1, NaN, Infinity]) viewport.zoomBy(factor);
assert.equal(viewport.distance, beforeInvalidZoom);
viewport.zoomBy(2); near(viewport.distance, beforeInvalidZoom / 2);
viewport.zoomBy(1e100); assert.equal(viewport.distance, 8);
viewport.zoomBy(1e-100); assert.equal(viewport.distance, 10000000);

reset();
viewport._pointerDown(event(1, 40, 40)); bounds.height = 220; viewport._resize();
assert.equal(captured.size, 0, 'Changing orientation cancels the old coordinate system gesture');
viewport.destroy();
console.log('Viewport touch: accurate anchored pinch, touch picking, cancellation, trailing fingers, zoom buttons and resize passed.');
