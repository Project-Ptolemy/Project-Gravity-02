import { normalizeProject } from './model.mjs';

// A full project can contain 64 layers of 4,096 XYZ vertices. Even with
// 25-character numbers and the indentation used by our downloads, that stays
// below 64 MiB. Keep this above every file the builder itself can generate.
export const MAX_PROJECT_FILE_BYTES = 64 * 1024 * 1024;

export function serializeProject(project) {
  return JSON.stringify(project, null, 2) + '\n';
}

export async function readProjectFile(file) {
  // Check the actual byte size before reading/parsing an untrusted file.
  if (file.size > MAX_PROJECT_FILE_BYTES) throw new Error('Choose a project file no larger than 64 MiB.');
  return normalizeProject(JSON.parse(await file.text()));
}
