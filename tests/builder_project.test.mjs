import assert from 'node:assert/strict';
import { createLayer, createProject, normalizeProject } from '../docs/plugins/builder/model.mjs';
import { MAX_PATH_POINTS } from '../docs/plugins/builder/geometry/path.mjs';
import { MAX_PROJECT_FILE_BYTES, readProjectFile, serializeProject } from '../docs/plugins/builder/project-file.mjs';

// Exercise the model's complete geometry allowance with long, exact JSON
// numbers. This catches a file-size limit that accepts small examples but
// rejects projects produced by duplicating full imported/formula layers.
const coordinates = [-0.0000010000000000000002, -0.0000012345678901234567, -0.0000017976931348623157];
assert.ok(coordinates.every(value => JSON.stringify(value).length === 25));
const points = Array.from({ length: MAX_PATH_POINTS }, (_, index) => ({
  x: index === 0 ? -5000 : index === 1 ? Number.MIN_VALUE : coordinates[0],
  y: index === MAX_PATH_POINTS - 1 ? 5000 : index === 1 ? -Number.MIN_VALUE : coordinates[1], z: coordinates[2],
}));
// Lone surrogates are legal JSON text and take six bytes when escaped. Use
// them to cover maximum text-field output as well as maximum point counts.
const name = '\ud800'.repeat(80);
const layers = Array.from({ length: 64 }, (_, index) => createLayer(index % 2 ? 'path' : 'pointcloud', {
  id: ('layer-' + index).padEnd(80, 'x'), name,
  path: { points, closed: !!(index % 2), smooth: !!(index % 3) },
}));
const controls = Array.from({ length: 96 }, (_, index) => ({
  id: ('control-' + index).padEnd(80, 'x'), name, layerId: layers[index % layers.length].id,
  property: index < 64 ? 'radius' : 'height', min: 1, max: 100, default: 24,
}));
const project = normalizeProject({ ...createProject('blank'), name, layers, controls, parts: 8192 });
const contents = serializeProject(project);
const file = new Blob([contents], { type: 'application/json' });
assert.ok(file.size > 2_000_000, 'fixture must exceed the old 2 MB project cap');
assert.ok(file.size < MAX_PROJECT_FILE_BYTES, 'every permitted geometry layer fits a portable project');
assert.deepEqual(await readProjectFile(file), project, 'all vertices, precision and controls survive a maximum-size roundtrip');

let readOversized = false;
await assert.rejects(readProjectFile({
  size: MAX_PROJECT_FILE_BYTES + 1,
  text() { readOversized = true; throw new Error('Do not read an oversized file'); },
}), /64 MiB/);
assert.equal(readOversized, false, 'reject excessive bytes before allocating/parsing their contents');
const blank = createProject('blank');
assert.deepEqual(await readProjectFile({ size: MAX_PROJECT_FILE_BYTES, text: async () => serializeProject(blank) }), blank, 'file-size ceiling is inclusive');
await assert.rejects(readProjectFile(new Blob(['{invalid json'])), SyntaxError);
await assert.rejects(readProjectFile(new Blob([JSON.stringify({ version: 2, layers: [] })])), /version/);
await assert.rejects(readProjectFile(new Blob([JSON.stringify({ version: 1, layers: Array(65).fill({ type: 'sphere' }) })])), /64 layers/);
await assert.rejects(readProjectFile(new Blob([JSON.stringify({ version: 1, layers: [{ type: 'path', path: { points: [...points, points[0]] } }] })])), /4096 points/);
console.log(`Builder project files: ${file.size.toLocaleString('en-US')} byte maximum-geometry roundtrip, exact precision and import limits passed.`);
