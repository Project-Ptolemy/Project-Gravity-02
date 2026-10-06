// Local geometry readers. SVG content is copied through a geometry-only
// allowlist; scripts, external references and source markup are never mounted.
const NS = 'http://www.w3.org/2000/svg';
const MAX_POINTS = 4096;
function checkPoints(points) {
  if (!points.length || points.length > MAX_POINTS) throw new Error('Use 1–4,096 points per layer.');
  for (const [i, point] of points.entries()) {
    if (!point || ['x', 'y', 'z'].some(axis => typeof point[axis] !== 'number' || !Number.isFinite(point[axis]) || Math.abs(point[axis]) > 5000)) throw new Error(`Point ${i + 1} needs finite X, Y, Z coordinates between −5,000 and 5,000.`);
  }
  return points;
}
export function readCoordinates(source, { type = 'path', closed = false } = {}) {
  if (typeof source !== 'string' || source.length > 2_000_000) throw new Error('Coordinate text is limited to 2 MB.');
  let points;
  if (/^\s*[\[{]/.test(source)) {
    let parsed;
    try { parsed = JSON.parse(source); } catch { throw new Error('Invalid JSON. Use an array of [x,y,z] points or {"points":[…]}.'); }
    points = Array.isArray(parsed) ? parsed : parsed.points;
    if (!Array.isArray(points)) throw new Error('JSON must contain an array of points.');
    points = points.map((point, i) => {
      if (!Array.isArray(point)) return point;
      if (point.length < 2 || point.length > 3) throw new Error(`Point ${i + 1}: use [x,y] or [x,y,z].`);
      return { x: point[0], y: point[1], z: point.length === 2 ? 0 : point[2] };
    });
  } else {
    const lines = source.split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('#'));
    if (/^x[\s,;]+y(?:[\s,;]+z)?$/i.test(lines[0] || '')) lines.shift();
    points = lines.map((line, i) => {
      const values = line.split(/[\s,;]+/);
      if (/(?:^|[,;])\s*[,;]|[,;]\s*$/.test(line) || values.length < 2 || values.length > 3 || values.some(value => !value || !Number.isFinite(Number(value)))) throw new Error(`Row ${i + 1}: use two or three numbers separated by commas or spaces.`);
      return { x: Number(values[0]), y: Number(values[1]), z: Number(values[2] ?? 0) };
    });
  }
  points = checkPoints(points).map(({ x, y, z }) => ({ x, y, z }));
  if (type === 'path' && points.length < 2) throw new Error('A connected path needs at least two points.');
  if (!['path', 'pointcloud'].includes(type)) throw new Error('Choose a path or a point cloud.');
  return [{ type, name: type === 'path' ? 'Imported path' : 'Imported points', path: { points, closed: !!closed, smooth: false } }];
}

export function readSVG(source, { size = 70, detail = 160 } = {}) {
  if (typeof source !== 'string' || source.length > 2_000_000) throw new Error('SVG files are limited to 2 MB.');
  if (!Number.isFinite(size) || size <= 0 || size > 1000) throw new Error('SVG size must be above 0 and at most 1,000 studs.');
  if (!Number.isInteger(detail) || detail < 8 || detail > 1024) throw new Error('SVG detail must be 8–1,024 samples per contour.');
  const sourceDocument = new DOMParser().parseFromString(source, 'image/svg+xml');
  if (sourceDocument.querySelector('parsererror') || sourceDocument.documentElement.localName !== 'svg') throw new Error('Choose a valid SVG file.');
  const shapes = [], root = document.createElementNS(NS, 'svg');
  root.setAttribute('width', '1000'); root.setAttribute('height', '1000');
  Object.assign(root.style, { position: 'fixed', left: '-2000px', top: '0', visibility: 'hidden', pointerEvents: 'none' });
  const allowed = {
    path: ['d'], polyline: ['points'], polygon: ['points'], line: ['x1', 'y1', 'x2', 'y2'],
    circle: ['cx', 'cy', 'r'], ellipse: ['cx', 'cy', 'rx', 'ry'], rect: ['x', 'y', 'width', 'height', 'rx', 'ry'],
  };
  const ignored = new Set(['defs', 'clipPath', 'mask', 'pattern', 'symbol', 'script', 'style', 'foreignObject', 'image', 'text', 'use', 'metadata', 'title', 'desc']);
  let visited = 0;
  function copyChildren(sourceNode, target, depth = 0) {
    if (depth > 40) throw new Error('SVG nesting is too deep.');
    for (const original of sourceNode.children) {
      if (++visited > 10000) throw new Error('SVG is too complex. Simplify it before importing.');
      const tag = original.localName;
      if (ignored.has(tag) || original.getAttribute('display') === 'none' || original.getAttribute('visibility') === 'hidden') continue;
      if (tag === 'g' || tag === 'svg') {
        const group = document.createElementNS(NS, tag);
        for (const attr of tag === 'svg' ? ['transform', 'x', 'y', 'width', 'height', 'viewBox', 'preserveAspectRatio'] : ['transform']) if (original.hasAttribute(attr)) group.setAttribute(attr, original.getAttribute(attr));
        target.append(group); copyChildren(original, group, depth + 1); continue;
      }
      if (!Object.hasOwn(allowed, tag)) continue;
      // Each moveto starts a separate editable contour. Relative movetos are
      // resolved against the preceding contour endpoint in local SVG units.
      const segments = tag === 'path' ? (original.getAttribute('d') || '').match(/[Mm][^Mm]*/g) || [] : [null];
      let previous = { x: 0, y: 0 };
      for (let segment of segments) {
        if (shapes.length >= 64) throw new Error('SVG has more than 64 contours. Import a smaller selection.');
        const node = document.createElementNS(NS, tag);
        for (const attr of [...allowed[tag], 'transform']) if (original.hasAttribute(attr)) node.setAttribute(attr, original.getAttribute(attr));
        if (segment !== null) {
          if (segment[0] === 'm') {
            const match = segment.match(/^m\s*([+-]?(?:\d*\.\d+|\d+\.?\d*)(?:e[+-]?\d+)?)\s*,?\s*([+-]?(?:\d*\.\d+|\d+\.?\d*)(?:e[+-]?\d+)?)/i);
            if (!match) throw new Error('An SVG path has an invalid relative moveto.');
            // Keep remaining relative implicit lineto pairs relative.
            const remainder = segment.slice(match[0].length).trim();
            segment = `M ${previous.x + Number(match[1])} ${previous.y + Number(match[2])} ${/^[+\-.\d]/.test(remainder) ? 'l ' : ''}${remainder}`;
          }
          node.setAttribute('d', segment);
        }
        target.append(node);
        let length;
        try { length = node.getTotalLength(); previous = node.getPointAtLength(length); } catch { throw new Error('An SVG outline could not be read. Convert it to paths in your vector editor.'); }
        if (!Number.isFinite(length)) throw new Error('SVG contains invalid geometry.');
        if (length <= 0) continue;
        const closed = ['polygon', 'circle', 'ellipse', 'rect'].includes(tag) || /[zZ]\s*$/.test(segment || '');
        shapes.push({ node, length, closed, name: original.getAttribute('id') || `SVG contour ${shapes.length + 1}` });
      }
    }
  }
  document.body.append(root);
  try {
    // Keep the document viewport inside our measurement root. Its transform
    // and nonuniform viewBox scale are part of the imported geometry too.
    const documentViewport = document.createElementNS(NS, 'svg');
    for (const attr of ['transform', 'x', 'y', 'width', 'height', 'viewBox', 'preserveAspectRatio']) {
      if (sourceDocument.documentElement.hasAttribute(attr)) documentViewport.setAttribute(attr, sourceDocument.documentElement.getAttribute(attr));
    }
    root.append(documentViewport);
    copyChildren(sourceDocument.documentElement, documentViewport);
    if (!shapes.length) throw new Error('No outlines found. Convert text and linked symbols to paths first.');
    const contours = shapes.map(({ node, length, closed, name }) => {
      const matrix = root.getCTM().inverse().multiply(node.getCTM());
      let raw;
      if (node.localName === 'polygon' || node.localName === 'polyline') {
        raw = Array.from({ length: node.points.numberOfItems }, (_, i) => node.points.getItem(i));
      } else if (node.localName === 'line') raw = [node.getPointAtLength(0), node.getPointAtLength(length)];
      else raw = Array.from({ length: detail }, (_, i) => node.getPointAtLength(length * i / (closed ? detail : detail - 1)));
      if (raw.length > MAX_POINTS) throw new Error('A contour has over 4,096 vertices. Simplify the SVG first.');
      const points = raw.map(point => { const transformed = new DOMPoint(point.x, point.y).matrixTransform(matrix); return { x: transformed.x, y: -transformed.y, z: 0 }; });
      return { type: 'path', name: name.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, 64) || 'SVG contour', path: { points, closed, smooth: false } };
    });
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const shape of contours) for (const p of shape.path.points) {
      if (!Number.isFinite(p.x) || !Number.isFinite(p.y)) throw new Error('SVG contains an invalid transform.');
      minX = Math.min(minX, p.x); minY = Math.min(minY, p.y); maxX = Math.max(maxX, p.x); maxY = Math.max(maxY, p.y);
    }
    const scale = size / Math.max(maxX - minX, maxY - minY, 1e-8);
    for (const shape of contours) for (const p of shape.path.points) { p.x = (p.x - (minX + maxX) / 2) * scale; p.y = (p.y - (minY + maxY) / 2) * scale; }
    return contours;
  } finally { root.remove(); }
}
