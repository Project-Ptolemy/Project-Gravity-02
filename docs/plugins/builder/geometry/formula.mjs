// A small arithmetic language. Formula input never executes JavaScript.
const FUNCTIONS = Object.freeze({
  sin: [1, Math.sin], cos: [1, Math.cos], tan: [1, Math.tan],
  asin: [1, Math.asin], acos: [1, Math.acos], atan: [1, Math.atan],
  atan2: [2, Math.atan2], sqrt: [1, Math.sqrt], abs: [1, Math.abs],
  floor: [1, Math.floor], ceil: [1, Math.ceil], round: [1, Math.round],
  exp: [1, Math.exp], log: [1, Math.log], min: [2, Math.min], max: [2, Math.max], pow: [2, Math.pow],
});
export function compileFormula(source) {
  if (typeof source !== 'string' || !source.trim() || source.length > 500) throw new Error('Each formula needs 1–500 characters.');
  const tokens = source.match(/(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?|[a-zA-Z_][a-zA-Z_0-9]*|\*\*|[^\s]/g) || [];
  let cursor = 0, depth = 0;
  const fail = () => { throw new Error(`Unexpected “${tokens[cursor] ?? 'end of formula'}”. Use numbers, u, v, pi, tau and math functions.`); };
  const take = token => tokens[cursor] === token && (++cursor, true);
  function primary() {
    if (++depth > 40) throw new Error('Formula nesting is too deep.');
    let expression;
    const token = tokens[cursor++];
    if (token === '(') { expression = sum(); if (!take(')')) fail(); }
    else if (/^(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?$/i.test(token || '')) {
      const number = Number(token); if (!Number.isFinite(number)) fail(); expression = () => number;
    } else if (token === 'u') expression = (u) => u;
    else if (token === 'v') expression = (_, v) => v;
    else if (token === 'pi' || token === 'tau') { const n = token === 'pi' ? Math.PI : Math.PI * 2; expression = () => n; }
    else if (Object.hasOwn(FUNCTIONS, token)) {
      const [arity, fn] = FUNCTIONS[token];
      if (!take('(')) fail();
      const args = [sum()];
      while (take(',')) { if (args.length >= arity) throw new Error(`${token} takes ${arity} argument(s).`); args.push(sum()); }
      if (!take(')') || args.length !== arity) throw new Error(`${token} takes ${arity} argument(s).`);
      expression = (u, v) => fn(...args.map(arg => arg(u, v)));
    } else { cursor--; fail(); }
    depth--; return expression;
  }
  function power() {
    const left = primary();
    if (take('^') || take('**')) { const right = unary(); return (u, v) => left(u, v) ** right(u, v); }
    return left;
  }
  function unary() {
    if (take('+')) { if (tokens[cursor] === '+' || tokens[cursor] === '-') fail(); return power(); }
    if (take('-')) { if (tokens[cursor] === '+' || tokens[cursor] === '-') fail(); const value = power(); return (u, v) => -value(u, v); }
    return power();
  }
  function product() {
    let left = unary();
    while (['*', '/', '%'].includes(tokens[cursor])) {
      const op = tokens[cursor++], a = left, b = unary();
      left = (u, v) => op === '*' ? a(u, v) * b(u, v) : op === '/' ? a(u, v) / b(u, v) : a(u, v) % b(u, v);
    }
    return left;
  }
  function sum() {
    let left = product();
    while (['+', '-'].includes(tokens[cursor])) {
      const op = tokens[cursor++], a = left, b = product();
      left = (u, v) => op === '+' ? a(u, v) + b(u, v) : a(u, v) - b(u, v);
    }
    return left;
  }
  const evaluate = sum();
  if (cursor !== tokens.length) fail();
  return (u, v = 0) => {
    const value = evaluate(u, v);
    if (!Number.isFinite(value) || Math.abs(value) > 5000) throw new Error('A formula produced a point outside −5,000…5,000 or an undefined value. Check its range and divisions.');
    return value;
  };
}

export function sampleFormula({ x, y, z, mode = 'curve', samples = 128, rows = 32, closed = false }) {
  const functions = [x, y, z].map(compileFormula);
  if (!['curve', 'surface'].includes(mode)) throw new Error('Choose curve or surface.');
  if (!Number.isInteger(samples) || samples < 2 || samples > 4096) throw new Error('Use 2–4,096 samples.');
  if (mode === 'surface' && (!Number.isInteger(rows) || rows < 2 || samples * rows > 4096)) throw new Error('A surface needs at least 2 rows, with at most 4,096 points in total.');
  const points = [];
  for (let row = 0; row < (mode === 'surface' ? rows : 1); row++) {
    for (let column = 0; column < samples; column++) {
      const u = column / (closed && mode === 'curve' ? samples : samples - 1), v = mode === 'surface' ? row / (rows - 1) : 0;
      try { points.push(Object.fromEntries(['x', 'y', 'z'].map((axis, index) => [axis, functions[index](u, v)]))); }
      catch (error) { throw new Error(`At u=${u.toFixed(3)}, v=${v.toFixed(3)}: ${error.message}`); }
    }
  }
  return { type: mode === 'curve' ? 'path' : 'pointcloud', name: mode === 'curve' ? 'Formula curve' : 'Formula surface', path: { points, closed: mode === 'curve' && closed, smooth: false } };
}
