import { normalizeProject, resolveLayers, PROPERTY_DEFS, controlDivisor } from './model.mjs';

// Lua has decimal byte escapes, not JSON's \uXXXX escapes. Keep UTF-8 names and
// quote every user string as data, including strings containing Lua delimiters.
export function luaString(value) {
  return '"' + String(value).replace(/["\\\u0000-\u001f\u007f]/g, char => {
    if (char === '"' || char === '\\') return '\\' + char;
    return '\\' + char.charCodeAt(0).toString().padStart(3, '0');
  }) + '"';
}
function literal(value) {
  if (typeof value === 'string') return luaString(value);
  if (typeof value === 'number') return String(value);
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (Array.isArray(value)) return '{' + value.map(literal).join(', ') + '}';
  return '{' + Object.entries(value).map(([key, item]) => `[${luaString(key)}] = ${literal(item)}`).join(', ') + '}';
}

export function exportLua(input) {
  const project = normalizeProject(input);
  const hasVisibilityControl = layer => project.controls.some(control => control.layerId === layer.id && control.type === 'toggle' && control.property === 'visible');
  const layers = project.layers.filter(layer => layer.visible || hasVisibilityControl(layer));
  const visibleValues = Object.fromEntries(project.controls.filter(control => control.type === 'toggle' && control.property === 'visible').map(control => [control.id, true]));
  if (!resolveLayers(project, visibleValues).length) throw new Error('Add a visible layer with a positive part weight before exporting.');
  const layerIndices = new Map(layers.map((layer, i) => [layer.id, i + 1]));
  const controls = project.controls.filter(control => layerIndices.has(control.layerId));
  const data = layers.map(layer => {
    const result = { type: layer.type, visible: layer.visible, fill: layer.fill, position: layer.position, rotation: layer.rotation, scale: layer.scale };
    for (const property of Object.keys(PROPERTY_DEFS)) if (!property.includes('.')) result[property] = layer[property];
    if (layer.type === 'path') {
      result.geometry = { points: layer.path.points.map(point => [point.x, point.y, point.z]), closed: layer.path.closed, smooth: layer.path.smooth };
    } else if (layer.type === 'pointcloud') {
      result.geometry = { points: layer.path.points.map(point => [point.x, point.y, point.z]) };
    }
    return result;
  });
  const bindings = controls.filter(control => control.type !== 'button').map(control => {
    const [property, axis] = control.property.split('.');
    if (control.type === 'toggle') return { key: control.id, layer: layerIndices.get(control.layerId), type: 'toggle', property, axis: '', default: control.default };
    return { key: control.id, layer: layerIndices.get(control.layerId), property, axis: axis || '', min: control.min, max: control.max, default: control.default };
  });
  const panel = controls.map(control => {
    if (control.type === 'toggle') return `    { Type = "Toggle", Name = ${luaString(control.name)}, Key = ${luaString(control.id)}, Default = ${literal(control.default)} },`;
    if (control.type === 'button') return `    { Type = "Button", Name = ${luaString(control.name)}, Key = ${luaString(control.id)}, Callback = function(c, x6) run_action(${layerIndices.get(control.layerId)}, ${luaString(control.action)}, c, x6) end },`;
    const property = PROPERTY_DEFS[control.property];
    const divisor = controlDivisor(control);
    const multiplier = 1 / divisor;
    const name = control.name + (divisor > 1 ? ` (×${multiplier})` : '');
    const description = property.label + ' (' + control.min + ' to ' + control.max + ')' + (divisor > 1 ? `; multiply displayed value by ${multiplier}` : '');
    return `    { Type = "Slider", Name = ${luaString(name)}, Key = ${luaString(control.id)}, Min = ${Math.round(control.min * divisor)}, Max = ${Math.round(control.max * divisor)}, Div = ${divisor}, Default = ${control.default}, ExactMax = true, Desc = ${luaString(description)} },`;
  }).join('\n');
  return `-- Project Gravity Shape Builder · ${project.name}
-- Save as GravityShapes/<your shape name>.lua and restart Project Gravity.
-- Preview colors and point size do not recolor or resize held parts.
-- Each held part occupies a sample of the visible layers, by part weight.
-- Flow follows local centerline distance; open outlines bounce at their ends.
-- Moving tubes interpolate bounded corner offsets and may narrow at turns.
-- Transform order: primitive/flow, Y twist, radial taper, scatter, Y wave,
-- individual displacement, scale/pulse, X/Y/Z spin, orbit, bob, then position.
-- Layer time is formation time * timeScale + timeOffset (seconds).
local M = {}
local NAME = ${luaString('Shape Builder: ' + project.name)}
local BASE = {
${data.map(layer => '    (function() return ' + literal(layer) + ' end)(),').join('\n')}
}
local BINDINGS = ${literal(bindings)}
local TAU, RAD = math.pi * 2, math.pi / 180
local PHI, PSI = 0.6180339887498949, 0.7548776662466927
local SCATTER_X, SCATTER_Y, SCATTER_Z = 1.4142135623730951, 1.7320508075688772, 2.23606797749979
local function clamp(value, lo, hi) return math.min(hi, math.max(lo, value)) end
local function finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function fract(value) return value - math.floor(value) end
local function flow_fraction(base, speed, time, length, closed)
    if speed == 0 or length <= 1e-9 then return base end
    local cycle = closed and 1 or 2
    local period = cycle * length / math.abs(speed)
    local offset = finite(period) and math.fmod(time, period) * speed / length or time * speed / length
    local value = base + offset
    local wrapped = value - math.floor(value / cycle) * cycle
    return closed and wrapped or 1 - math.abs(1 - wrapped)
end
local function torus_angle(fraction, eccentricity)
    local target = TAU * fraction
    local angle, low, high = target, 0, TAU
    for iteration = 1, 16 do
        local residual = angle + eccentricity * math.sin(angle) - target
        if math.abs(residual) < 1e-12 then break end
        if residual > 0 then high = angle else low = angle end
        local slope = 1 + eccentricity * math.cos(angle)
        local next_angle = slope > 1e-12 and (angle - residual / slope) or -1
        angle = next_angle > low and next_angle < high and next_angle or (low + high) / 2
    end
    return angle
end

-- Flatten curves once when loading the plugin, then share immutable arc-length
-- tables between frames. Keep only original nodes in the export for file size.
local function compile_path(geometry)
    local nodes, points, lengths, total = geometry.points, {}, {}, 0
    local function append(point)
        local last = points[#points]
        local length = 0
        if last then
            local dx, dy, dz = point[1] - last[1], point[2] - last[2], point[3] - last[3]
            length = math.sqrt(dx * dx + dy * dy + dz * dz)
            if length == 0 then return end
        end
        total = total + length
        points[#points + 1], lengths[#lengths + 1] = point, total
    end
    local function at(index)
        if geometry.closed then return nodes[(index - 1) % #nodes + 1] end
        return nodes[math.max(1, math.min(#nodes, index))]
    end
    append(nodes[1])
    local segments = geometry.closed and #nodes or #nodes - 1
    if geometry.smooth and #nodes >= 3 then
        for segment = 1, segments do
            local p0, p1, p2, p3 = at(segment - 1), at(segment), at(segment + 1), at(segment + 2)
            for step = 1, 16 do
                local t = step / 16
                local t2, t3 = t * t, t * t * t
                local point = {}
                for axis = 1, 3 do
                    if step == 16 then point[axis] = p2[axis]
                    elseif p0[axis] == p1[axis] and p1[axis] == p2[axis] and p2[axis] == p3[axis] then point[axis] = p1[axis]
                    else
                        point[axis] = 0.5 * (2 * p1[axis] + (-p0[axis] + p2[axis]) * t
                            + (2 * p0[axis] - 5 * p1[axis] + 4 * p2[axis] - p3[axis]) * t2
                            + (-p0[axis] + 3 * p1[axis] - 3 * p2[axis] + p3[axis]) * t3)
                    end
                end
                append(point)
            end
        end
    else
        for segment = 1, segments do append(at(segment + 1)) end
    end
    return { points = points, lengths = lengths, total = total, closed = geometry.closed }
end
for _, layer in ipairs(BASE) do
    if layer.type == "path" then layer.geometry = compile_path(layer.geometry) end
end

-- Binary search avoids walking every segment for every held part.
local function sample_path(geometry, fraction, tube, angle, radial)
    local points = geometry.points
    if #points == 1 or geometry.total == 0 then return points[1][1], points[1][2], points[1][3] end
    local target = clamp(fraction, 0, 1) * geometry.total
    local low, high = 2, #points
    while low < high do
        local middle = math.floor((low + high) / 2)
        if geometry.lengths[middle] < target then low = middle + 1 else high = middle end
    end
    local p, q = points[low - 1], points[low]
    local length = geometry.lengths[low] - geometry.lengths[low - 1]
    local t = length > 0 and (target - geometry.lengths[low - 1]) / length or 0
    local x, y, z = p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t, p[3] + (q[3] - p[3]) * t
    if tube > 0 and length > 0 then
        local tx, ty, tz = (q[1] - p[1]) / length, (q[2] - p[2]) / length, (q[3] - p[3]) / length
        local nx, ny, nz
        if math.abs(tz) < 0.9 then nx, ny, nz = ty, -tx, 0 else nx, ny, nz = -tz, 0, tx end
        local normal_length = math.sqrt(nx * nx + ny * ny + nz * nz)
        nx, ny, nz = nx / normal_length, ny / normal_length, nz / normal_length
        local bx, by, bz = ty * nz - tz * ny, tz * nx - tx * nz, tx * ny - ty * nx
        local c, s = tube * radial * math.cos(angle), tube * radial * math.sin(angle)
        x, y, z = x + nx * c + bx * s, y + ny * c + by * s, z + nz * c + bz * s
    end
    return x, y, z
end

-- Shared vertex offset frames keep active flow continuous through corners
-- and the closed seam. Linear interpolation stays bounded without singular
-- normalization at reversals; stationary geometry keeps its legacy frames.
local function flow_frames(geometry)
    if geometry.flow_frames then return geometry.flow_frames end
    local segments = {}
    for i = 2, #geometry.points do
        local p, q = geometry.points[i - 1], geometry.points[i]
        local dx, dy, dz = q[1] - p[1], q[2] - p[2], q[3] - p[3]
        local length = math.sqrt(dx * dx + dy * dy + dz * dz)
        local tx, ty, tz = dx / length, dy / length, dz / length
        local ax, ay, az = math.abs(dx), math.abs(dy), math.abs(dz)
        local nx, ny, nz
        if az <= ax and az <= ay then nx, ny, nz = ty, -tx, 0
        elseif ay <= ax then nx, ny, nz = -tz, 0, tx
        else nx, ny, nz = 0, tz, -ty end
        local normal = math.sqrt(nx * nx + ny * ny + nz * nz)
        nx, ny, nz = nx / normal, ny / normal, nz / normal
        segments[#segments + 1] = {nx, ny, nz, ty * nz - tz * ny, tz * nx - tx * nz, tx * ny - ty * nx}
    end
    local function average(a, b)
        local result = {}
        for axis = 1, 6 do result[axis] = (a[axis] + b[axis]) / 2 end
        return result
    end
    local first = geometry.closed and average(segments[#segments], segments[1]) or segments[1]
    local frames = {first}
    for i = 2, #segments do frames[#frames + 1] = average(segments[i - 1], segments[i]) end
    frames[#frames + 1] = geometry.closed and first or segments[#segments]
    geometry.flow_frames = frames
    return frames
end

local function sample_flow_path(geometry, fraction, tube, angle, radial)
    local points = geometry.points
    if #points == 1 or geometry.total <= 1e-9 then return points[1][1], points[1][2], points[1][3] end
    local target = clamp(fraction, 0, 1) * geometry.total
    local low, high = 2, #points
    while low < high do
        local middle = math.floor((low + high) / 2)
        if geometry.lengths[middle] < target then low = middle + 1 else high = middle end
    end
    local p, q = points[low - 1], points[low]
    local length = geometry.lengths[low] - geometry.lengths[low - 1]
    local t = length > 0 and (target - geometry.lengths[low - 1]) / length or 0
    local position = {p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t, p[3] + (q[3] - p[3]) * t}
    if tube > 0 then
        local frames = flow_frames(geometry)
        local a, b = frames[low - 1], frames[low]
        local c, s = tube * radial * math.cos(angle), tube * radial * math.sin(angle)
        for axis = 1, 3 do position[axis] = position[axis] + (a[axis] * (1 - t) + b[axis] * t) * c + (a[axis + 3] * (1 - t) + b[axis + 3] * t) * s end
    end
    return position[1], position[2], position[3]
end

local function state(x6)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = {}; x6.pre[NAME] = st end
    return st
end

local function resolve_layers(c)
    local layers = {}
    for i, base in ipairs(BASE) do
        local layer = {}
        for key, value in pairs(base) do
            if key == "geometry" then layer[key] = value
            elseif type(value) == "table" then layer[key] = { x = value.x, y = value.y, z = value.z }
            else layer[key] = value end
        end
        layers[i] = layer
    end
    c = c or {}
    for _, binding in ipairs(BINDINGS) do
        local value = c[binding.key]
        if binding.type == "toggle" then
            if type(value) ~= "boolean" then value = binding.default end
        else
            if not finite(value) then value = binding.default end
            value = clamp(value, binding.min, binding.max)
            if binding.property == "sides" then value = math.floor(value + 0.5) end
        end
        local layer = layers[binding.layer]
        if binding.axis ~= "" then layer[binding.property][binding.axis] = value
        else layer[binding.property] = value end
    end
    return layers
end

function M.px(t, c, x6, x9, x1)
    local st = state(x6)
    -- Natural ordering leaves gaps in IDs after release. Compact real records
    -- once per population change instead of folding two IDs onto one sample.
    if type(x6.a) == "table" and (not st.indices or st.held_count ~= x6.n or st.claim_counter ~= x6.part_id_counter) then
        local ids = {}
        for _, record in pairs(x6.a) do
            if type(record) == "table" and finite(record.id) then ids[#ids + 1] = record.id end
        end
        table.sort(ids)
        st.indices = {}
        for i, id in ipairs(ids) do st.indices[id] = i end
        st.actual_count = #ids > 0 and #ids or nil
        st.held_count, st.claim_counter = x6.n, x6.part_id_counter
    end
    local layers = resolve_layers(c)
    local total = 0
    st.layers = {}
    st.time = finite(t) and t or 0
    for index, layer in ipairs(layers) do
        if layer.visible and layer.weight > 0 then
            local animation = st.animation and st.animation[index]
            if animation then
                layer.timeScale = layer.timeScale * animation.direction
                layer.timeOffset = layer.timeOffset + animation.offset
            end
            local layer_time = st.time * layer.timeScale + layer.timeOffset
            layer.motion_time = layer_time
            local rx = (layer.rotation.x + layer_time * layer.spinX) * RAD
            local ry = (layer.rotation.y + layer_time * layer.spin) * RAD
            local rz = (layer.rotation.z + layer_time * layer.spinZ) * RAD
            layer.cx, layer.sx = math.cos(rx), math.sin(rx)
            layer.cy, layer.sy = math.cos(ry), math.sin(ry)
            layer.cz, layer.sz = math.cos(rz), math.sin(rz)
            layer.phase_rad = layer.phase * RAD
            layer.pulse_scale = 1 + layer.pulse / 100 * math.sin(layer_time * layer.pulseSpeed * TAU + layer.phase_rad + layer.pulsePhase * RAD)
            layer.wave_phase = layer_time * layer.waveSpeed * TAU + layer.phase_rad + layer.wavePhase * RAD
            local orbit = (layer_time * layer.orbitSpeed + layer.orbitPhase) * RAD
            local tilt_x, tilt_z = layer.orbitTiltX * RAD, layer.orbitTiltZ * RAD
            local ox, oy, oz = layer.orbitRadius * math.cos(orbit), 0, layer.orbitRadius * layer.orbitAspect * math.sin(orbit)
            oy, oz = -oz * math.sin(tilt_x), oz * math.cos(tilt_x)
            ox, oy = ox * math.cos(tilt_z) - oy * math.sin(tilt_z), ox * math.sin(tilt_z) + oy * math.cos(tilt_z)
            layer.ox, layer.oy, layer.oz = ox, oy + layer.bobAmount * math.sin(layer_time * layer.bobSpeed * TAU + layer.bobPhase * RAD), oz
            total = total + layer.weight
            layer.cumulative = total
            st.layers[#st.layers + 1] = layer
        end
    end
    st.weight = total
end

local function sample(layer, index, count)
    local u = (index + 0.5) / math.max(1, count)
    local v, w = fract((index + 0.5) * PHI), fract((index + 0.5) * PSI)
    local phase = layer.phase_rad
    local a, b = layer.arc * RAD * u + phase, TAU * v
    local x, y, z = 0, 0, 0
    if layer.type == "sphere" then
        local sy = 1 - 2 * u
        local r = layer.radius * (layer.fill and w ^ (1 / 3) or 1)
        local horizontal = math.sqrt(math.max(0, 1 - sy * sy))
        x, y, z = math.cos(b + phase) * horizontal * r, sy * r, math.sin(b + phase) * horizontal * r
    elseif layer.type == "ring" then
        local r = layer.radius * (layer.fill and math.sqrt(v) or 1)
        local along = layer.flowSpeed == 0 and u or flow_fraction(u, layer.flowSpeed, layer.motion_time, layer.radius * layer.arc * RAD, layer.arc == 360)
        local angle = layer.flowSpeed == 0 and a or layer.arc * RAD * along + phase
        x, z = math.cos(angle) * r, math.sin(angle) * r
    elseif layer.type == "torus" then
        local r = layer.tube * (layer.fill and math.sqrt(w) or 1)
        local angle = layer.radius > 0 and layer.radius >= layer.tube and torus_angle(v, r / layer.radius) or b
        x = (layer.radius + r * math.cos(angle)) * math.cos(a)
        y = r * math.sin(angle)
        z = (layer.radius + r * math.cos(angle)) * math.sin(a)
    elseif layer.type == "helix" or layer.type == "spiral" then
        local angle = a * layer.turns - phase * (layer.turns - 1)
        local r = layer.radius * (layer.type == "spiral" and u or 1)
        local tube = layer.tube * (layer.fill and math.sqrt(w) or 1)
        x = (r + tube * math.cos(b)) * math.cos(angle)
        y = (u - 0.5) * layer.height + tube * math.sin(b)
        z = (r + tube * math.cos(b)) * math.sin(angle)
    elseif layer.type == "box" then
        x, y, z = u - 0.5, v - 0.5, w - 0.5
        if not layer.fill then
            local areas = {layer.height * layer.depth, layer.width * layer.depth, layer.width * layer.height}
            local area = 2 * (areas[1] + areas[2] + areas[3])
            if area > 0 then
                local position, face = u * area, 0
                while face < 5 and position >= areas[math.floor(face / 2) + 1] do
                    position = position - areas[math.floor(face / 2) + 1]
                    face = face + 1
                end
                local q, r = position / areas[math.floor(face / 2) + 1] - 0.5, v - 0.5
                if face < 2 then x, y, z = face == 0 and -0.5 or 0.5, q, r
                elseif face < 4 then x, y, z = q, face == 2 and -0.5 or 0.5, r
                else x, y, z = q, r, face == 4 and -0.5 or 0.5 end
            else x, y, z = u - 0.5, u - 0.5, u - 0.5 end
        end
        x, y, z = x * layer.width, y * layer.height, z * layer.depth
    elseif layer.type == "grid" then
        local columns = math.min(count, math.max(1, math.ceil(math.sqrt(count * math.max(0.01, layer.width) / math.max(0.01, layer.depth)))))
        local rows = math.ceil(count / columns)
        x = (columns > 1 and ((index % columns) / (columns - 1) - 0.5) or 0) * layer.width
        z = (rows > 1 and (math.floor(index / columns) / (rows - 1) - 0.5) or 0) * layer.depth
    elseif layer.type == "cone" or layer.type == "cylinder" then
        local remaining = layer.type == "cone" and (layer.fill and (1 - u) ^ (1 / 3) or math.sqrt(1 - u)) or 1
        local height = layer.type == "cone" and (1 - remaining) or u
        local r = layer.radius * remaining * (layer.fill and math.sqrt(w) or 1)
        x, y, z = math.cos(b + phase) * r, (height - 0.5) * layer.height, math.sin(b + phase) * r
    elseif layer.type == "line" then
        local along = layer.flowSpeed == 0 and u or flow_fraction(u, layer.flowSpeed, layer.motion_time, layer.width, false)
        x = (along - 0.5) * layer.width
        local r = layer.tube * (layer.fill and math.sqrt(w) or 1)
        y, z = math.cos(b) * r, math.sin(b) * r
    elseif layer.type == "polygon" then
        local fraction = index / math.max(1, count)
        local perimeter = 2 * layer.sides * layer.radius * math.sin(math.pi / layer.sides)
        local along = (layer.flowSpeed == 0 and fraction or flow_fraction(fraction, layer.flowSpeed, layer.motion_time, perimeter, true)) * layer.sides
        local edge = math.floor(along)
        local t = along - edge
        local first = TAU * edge / layer.sides + phase + math.pi / 2
        local second = first + TAU / layer.sides
        x = (math.cos(first) * (1 - t) + math.cos(second) * t) * layer.radius
        y = (math.sin(first) * (1 - t) + math.sin(second) * t) * layer.radius
        if layer.fill then
            local r = math.sqrt(v)
            x, y = x * r, y * r
        elseif layer.tube > 0 then
            local normal = first + math.pi / layer.sides
            local nx = layer.flowSpeed == 0 and math.cos(normal) or math.cos(math.pi / layer.sides) * (math.cos(first) * (1 - t) + math.cos(second) * t)
            local ny = layer.flowSpeed == 0 and math.sin(normal) or math.cos(math.pi / layer.sides) * (math.sin(first) * (1 - t) + math.sin(second) * t)
            x = x + nx * layer.tube * math.cos(b)
            y = y + ny * layer.tube * math.cos(b)
            z = layer.tube * math.sin(b)
        end
    elseif layer.type == "path" then
        local fraction = layer.geometry.closed and index / math.max(1, count) or (count > 1 and index / (count - 1) or 0.5)
        if layer.flowSpeed == 0 then
            x, y, z = sample_path(layer.geometry, fraction, layer.tube, b, layer.fill and math.sqrt(w) or 1)
        else
            fraction = flow_fraction(fraction, layer.flowSpeed, layer.motion_time, layer.geometry.total, layer.geometry.closed)
            x, y, z = sample_flow_path(layer.geometry, fraction, layer.tube, b, layer.fill and math.sqrt(w) or 1)
        end
    elseif layer.type == "pointcloud" then
        local points = layer.geometry.points
        local point = points[math.min(#points, math.floor(u * #points) + 1)]
        x, y, z = point[1], point[2], point[3]
    end
    local twist = layer.twist * (u - 0.5) * RAD
    x, z = x * math.cos(twist) + z * math.sin(twist), -x * math.sin(twist) + z * math.cos(twist)
    local taper = 1 + layer.taper / 100 * (2 * u - 1)
    x, z = x * taper, z * taper
    x = x + layer.scatter * (2 * fract((index + 0.5) * SCATTER_X) - 1)
    y = y + layer.scatter * (2 * fract((index + 0.5) * SCATTER_Y) - 1)
    z = z + layer.scatter * (2 * fract((index + 0.5) * SCATTER_Z) - 1)
    y = y + layer.wave * math.sin(TAU * u * layer.waveCount + layer.wave_phase)
    if layer.partMoveX ~= 0 or layer.partMoveY ~= 0 or layer.partMoveZ ~= 0 then
        local theta = TAU * (layer.motion_time * layer.partMoveSpeed + u * layer.partMoveSpread) + layer.partMovePhase * RAD
        x = x + layer.partMoveX * math.sin(theta)
        y = y + layer.partMoveY * math.sin(theta + layer.partMovePhaseY * RAD)
        z = z + layer.partMoveZ * math.sin(theta + layer.partMovePhaseZ * RAD)
    end
    x, y, z = x * layer.scale.x * layer.pulse_scale, y * layer.scale.y * layer.pulse_scale, z * layer.scale.z * layer.pulse_scale
    y, z = y * layer.cx - z * layer.sx, y * layer.sx + z * layer.cx
    x, z = x * layer.cy + z * layer.sy, -x * layer.sy + z * layer.cy
    x, y = x * layer.cz - y * layer.sz, x * layer.sz + y * layer.cz
    return Vector3.new(x + layer.ox + layer.position.x, y + layer.oy + layer.position.y, z + layer.oz + layer.position.z)
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local st = state(x6)
    if not st.layers then M.px(t, c, x6, x9, x1) end
    local count = d.slot_n or st.actual_count or x6.n or ${project.parts}
    if not finite(count) or count < 1 then count = ${project.parts} end
    count = math.max(1, math.floor(count))
    local slot = d.slot or (st.indices and st.indices[d.id]) or d.id or 1
    if not finite(slot) then slot = 1 end
    local index = (math.max(1, math.floor(slot)) - 1) % count
    local target = cen
    if st.weight > 0 then
        local start = 0
        for i, layer in ipairs(st.layers) do
            local finish = i == #st.layers and count or math.floor(layer.cumulative / st.weight * count)
            if index < finish then
                target = cen + sample(layer, index - start, finish - start)
                break
            end
            start = finish
        end
    end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

-- Actions change only this module's runtime state and bound control values.
-- Use the shared formation clock; wall time would jump while paused/reversed.
local function run_action(index, action, c, x6)
    local st = state(x6)
    st.animation = st.animation or {}
    if action == "reset" then
        for _, binding in ipairs(BINDINGS) do
            if binding.layer == index then c[binding.key] = binding.default end
        end
        st.animation[index] = nil
    else
        local layer = resolve_layers(c)[index]
        local animation = st.animation[index] or { direction = 1, offset = 0 }
        local t = finite(x6.shape_clock) and x6.shape_clock or st.time or 0
        local rate = layer.timeScale * animation.direction
        if action == "restart" then animation.offset = -t * rate - layer.timeOffset
        else
            animation.direction = -animation.direction
            animation.offset = animation.offset + 2 * t * rate
        end
        st.animation[index] = animation
    end
    st.layers = nil
end

M.Controls = {
${panel}
}

function M.cleanup(x6, x1)
    if x6.pre then x6.pre[NAME] = nil end
end

return M
`;
}
