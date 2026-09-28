-- Geometry plus the real desktop/mobile velocity loop. The integration fixture
-- advances the commanded velocity; it does not simulate Roblox's contact solver.
package.path = "tests/?.lua;" .. package.path
require("robloxenv")
local Hole = assert(loadfile("shapes/Black Hole v2.lua"))()
local config = assert(loadfile("config.lua"))()
local Controls = assert(loadfile("PluginControls.lua"))()
local c, x1, x9 = config.x2["Black Hole v2"], config.x1, { c1 = 0.15, c2 = 0.05 }
local checks = 0
local function check(ok, label) checks = checks + 1; assert(ok, label) end
local function near(a, b, epsilon) return (a - b).Magnitude < (epsilon or 1e-6) end
local function finite(v) return v and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e7 end
local function sample(p, d, ctx, cfg, t, center)
    Hole.px(t, cfg, ctx, x9, x1)
    local velocity, target = Hole.f2(p, center or Vector3.zero, d, t, cfg, x1, ctx, x9)
    check(finite(velocity) and finite(target), "finite motion")
    return target
end
local function part(position)
    return { Position = position, AssemblyLinearVelocity = Vector3.zero }
end

for _, control in ipairs(Hole.Controls) do
    if control.Type ~= "Button" then
        check(c[control.Key] == control.Default, "local plugin and built-in defaults agree: " .. control.Key)
    end
end

-- Mixed starting positions must converge without crossing the center or
-- reversing the inlet, then churn through a volume rather than a disc or shell.
local cfg = table.clone(c); cfg.rwTilt = 0
local ctx, population, previous, settled = { pre = {} }, {}, {}, {}
local converges, turns_forward, fixed_radii, changing_heights = true, true, true, 0
local total_turns, center_sum, moments, inner = 0, Vector3.zero, Vector3.zero, 0
local heights, dense_distance, pair_separation_change = {}, 0, 0
Hole.px(0, cfg, ctx, x9, x1)
for id = 1, 512 do
    local angle, radius = id * 2.399963229728653, 90 + (id * 0.754877666 % 1) * 80
    local p = part(Vector3.new(math.cos(angle) * radius, (id * 0.56984 % 1 - 0.5) * 90, math.sin(angle) * radius))
    local d = { id = id }
    population[id] = { p, d }
    local velocity, target = Hole.f2(p, Vector3.zero, d, 0, cfg, x1, ctx, x9)
    check(near(target, p.Position) and near(velocity, Vector3.zero), "no snap on capture")
    previous[id] = target
end
for frame = 1, 360 do
    Hole.px(frame / 60, cfg, ctx, x9, x1)
    for id, item in ipairs(population) do
        local _, point = Hole.f2(item[1], Vector3.zero, item[2], frame / 60, cfg, x1, ctx, x9)
        local last = previous[id]
        if point.Magnitude > last.Magnitude + 1e-6 then converges = false end
        local angle = math.atan2(last.Z * point.X - last.X * point.Z, last.X * point.X + last.Z * point.Z)
        if item[2].black_hole_v2.progress <= 0.5 then
            if angle < -1e-7 then turns_forward = false end
            total_turns = total_turns + angle
        end
        if frame == 240 then
            settled[id] = point
            heights[id] = { point.Y, point.Y }
            center_sum = center_sum + point
            moments = moments + point * point
            if point.Magnitude < cfg.rwBall * 0.5 then inner = inner + 1 end
        elseif frame > 240 then
            if math.abs(point.Magnitude - settled[id].Magnitude) > 1e-5 then fixed_radii = false end
            heights[id][1] = math.min(heights[id][1], point.Y)
            heights[id][2] = math.max(heights[id][2], point.Y)
            dense_distance = dense_distance + (point - last).Magnitude
        end
        previous[id] = point
    end
    if frame > 240 then
        pair_separation_change = math.max(pair_separation_change,
            math.abs((settled[1] - settled[2]).Magnitude - (previous[1] - previous[2]).Magnitude))
    end
end
check(converges, "every inward path shrinks monotonically to its own core radius")
check(turns_forward and total_turns / #population > 0.5, "the inlet keeps spiraling in one direction")
check(fixed_radii, "dense core orbits preserve each particle's radius")
for _, height in ipairs(heights) do
    if height[2] - height[1] > c.rwBall * 0.1 then changing_heights = changing_heights + 1 end
end
check(changing_heights > #population * 0.95, "settled parts move through tilted orbits instead of fixed horizontal bands")
check(dense_distance / #population > c.rwBall * 10, "the dense core continues churning rapidly")
check(pair_separation_change > 0.5,
    "core particles have independent orbits rather than one rigid spinning globe")
check(center_sum.Magnitude / #population < c.rwBall * 0.1, "the sphere stays centered")
local variance = moments / #population
check(math.min(variance.X, variance.Y, variance.Z) / math.max(variance.X, variance.Y, variance.Z) > 0.7,
    "the cloud fills three dimensions evenly")
check(inner >= 50 and inner <= 78, "the core fills the sphere's interior, including its inner eighth of volume")
for _, point in ipairs(settled) do check(point.Magnitude <= c.rwBall + 1e-6, "no settled part escapes the sphere") end

-- The every-frame core path is deliberately inexpensive at high debris counts.
-- Count expensive calls instead of relying on machine-dependent timing limits.
do
    local sine, cosine, trig_calls = math.sin, math.cos, 0
    math.sin = function(...) trig_calls = trig_calls + 1; return sine(...) end
    math.cos = function(...) trig_calls = trig_calls + 1; return cosine(...) end
    for _, item in ipairs(population) do
        Hole.f2(item[1], Vector3.zero, item[2], 6, cfg, x1, ctx, x9)
        check(item[2].angular_velocity == nil and item[2].collisions == nil,
            "settled motion adds no self-spin motors or collision override")
    end
    math.sin, math.cos = sine, cosine
    check(trig_calls == 0, "settled core uses the shared frame basis without per-part trigonometry")
end

-- A degenerate pile, a late arrival, an axis-aligned part and a moving center
-- all use the same path, without singularities or a phase reset of other parts.
for _, position in ipairs({ Vector3.zero, Vector3.new(0, 120, 0), Vector3.new(0, -120, 0), Vector3.new(0.000001, 0, 0) }) do
    local p, d, run = part(position), { id = 41 }, { pre = {} }
    check(near(sample(p, d, run, c, 100), position), "late/axial capture starts at the live location")
    for frame = 1, 180 do sample(p, d, run, c, 100 + frame / 60) end
    local before = sample(p, d, run, c, 103)
    local shift = Vector3.new(37, -12, 54)
    check(near(sample(p, d, run, c, 103, shift), before + shift), "moving the anchor translates the complete orbit")
end

local function sampled_path(fps, stride)
    local p, d, run = part(Vector3.new(125, 48, -20)), { id = 7 }, { pre = {} }
    sample(p, d, run, c, 0)
    local point
    for frame = 1, fps * 5 do
        Hole.px(frame / fps, c, run, x9, x1)
        if frame % stride == 0 then
            _, point = Hole.f2(p, Vector3.zero, d, frame / fps, c, x1, run, x9)
        end
    end
    return point
end
local reference = sampled_path(120, 1)
check(near(reference, sampled_path(30, 1), 0.08), "30 and 120 fps finish on the same orbit")
check(near(reference, sampled_path(60, 10), 0.08), "sparse evaluations preserve capture timing and phase")

do
    local p, d, run = part(Vector3.new(135, 30, 20)), { id = 17 }, { pre = {} }
    local settings = table.clone(c)
    sample(p, d, run, settings, 0)
    for frame = 1, 60 do sample(p, d, run, settings, frame / 60) end
    local hold = sample(p, d, run, settings, 1)
    settings.rwPull = 0
    for frame = 61, 120 do
        local point = sample(p, d, run, settings, frame / 60)
        check(math.abs(point.Magnitude - hold.Magnitude) < 1e-6, "zero pull holds an in-progress radius")
    end
    local before = sample(p, d, run, settings, 2)
    settings.rwPull, settings.rwSpin, settings.rwBallSpin = 160, 30, 1440
    check(near(sample(p, d, run, settings, 2), before), "speed controls preserve position and capture progress")
    for frame = 121, 240 do sample(p, d, run, settings, frame / 60) end
    before = sample(p, d, run, settings, 4)
    settings.rwBall, settings.rwTilt = 40, 80
    check(near(sample(p, d, run, settings, 4), before), "size and tilt controls do not teleport settled parts")
    local after = sample(p, d, run, settings, 4.001)
    check((after - before).Magnitude < 1, "a resized core starts changing smoothly")
end

-- No snap when moving parts between the optional ring and the sphere.
do
    local p, d, run = part(Vector3.new(100, 20, 0)), { id = 2 }, { pre = {} }
    local settings = table.clone(c)
    sample(p, d, run, settings, 0)
    for frame = 1, 180 do p.Position = sample(p, d, run, settings, frame / 60) end
    settings.rwRing = 60
    check(near(sample(p, d, run, settings, 3), p.Position), "switching to the ring recaptures the live position")
    for frame = 181, 300 do p.Position = sample(p, d, run, settings, frame / 60) end
    check(p.Position.Magnitude > c.rwBall * 2 and d.angular_velocity == nil, "ring parts hold an outer orbit")
    settings.rwRing = 0
    check(near(sample(p, d, run, settings, 5), p.Position), "returning to the core starts from the ring")
end

-- Exercise extreme controls and a stopped/reversed formation clock.
for _, ball in ipairs({ 0, 70 }) do
    local settings = table.clone(c)
    settings.rwBall, settings.rwBallSpin, settings.rwPull, settings.rwSpin, settings.rwTilt = ball, 1440, 400, 30, 80
    local p, d, run = part(Vector3.new(0, 40, 0)), { id = 101 }, { pre = {} }
    sample(p, d, run, settings, 0)
    for frame = 1, 120 do sample(p, d, run, settings, frame / 60) end
    local before = sample(p, d, run, settings, 2)
    x1.TimeScale = 0
    check(near(sample(p, d, run, settings, 2), before) and d.angular_velocity == nil,
        "a frozen clock stops dense motion without a self-spin motor")
    x1.TimeScale = -1
    local after = sample(p, d, run, settings, 2 - 1 / 60)
    check(math.abs(after.Magnitude - before.Magnitude) < 1e-6,
        "reverse time preserves the packed radius")
    x1.TimeScale = 1
    check(near(sample(p, d, run, settings, 2), before), "reverse time retraces the dense orbit exactly")
end

-- Combined tilted motion and precession must fit the same physical speed
-- budget at large radii and fast/reversed formation clocks.
do
    local settings, physics = table.clone(c), table.clone(x1)
    settings.rwBall, settings.rwBallSpin, settings.rwPull = 70, 1440, 400
    physics.MaxSpeed = 180
    for _, scale in ipairs({ 0.25, 1, 4, -2 }) do
        physics.TimeScale = math.abs(scale)
        local p, d, run = part(Vector3.new(5, 12, 7)), { id = 33 }, { pre = {} }
        local t = 0
        Hole.px(t, settings, run, x9, physics)
        Hole.f2(p, Vector3.zero, d, t, settings, physics, run, x9)
        for _ = 1, 120 do
            t = t + 1 / 60
            Hole.px(t, settings, run, x9, physics)
            Hole.f2(p, Vector3.zero, d, t, settings, physics, run, x9)
        end
        physics.TimeScale = scale
        local _, previous_point = Hole.f2(p, Vector3.zero, d, t, settings, physics, run, x9)
        for _ = 1, 60 do
            t = t + scale / 60
            Hole.px(t, settings, run, x9, physics)
            local _, point = Hole.f2(p, Vector3.zero, d, t, settings, physics, run, x9)
            check((point - previous_point).Magnitude * 60 <= physics.MaxSpeed * 0.75 + 1e-6,
                "large dense core reserves speed for anchor motion at every time scale")
            previous_point = point
        end
    end
end

-- Run the actual loader and engine, keeping default smoothing and damping and
-- deliberately selecting a ten-frame processing bucket. Integrate constraints
-- at 30, 60 and 144 Hz; merely inspecting the shape's targets would miss flattening.
local fixture = require("runtime_fixture")
local active_context, wall_clock = nil, 10
function capture_context(context) active_context = context end
time = function() return wall_clock end
game.HttpGet = function(_, url)
    local path = assert(url:match("/main/(.-)%?cb="), url)
    local file = assert(io.open(path), path)
    local source = file:read("a"); file:close()
    if path == "UI.lua" or path == "mobilever/UI.lua" then
        source = source:gsub("return function%(context%)", "return function(context) capture_context(context)", 1)
    end
    return source
end
for _, mobile in ipairs({ false, true }) do
    fixture.input.TouchEnabled, fixture.input.KeyboardEnabled = mobile, not mobile
    assert(loadfile("main.lua"))()
    local live = assert(active_context)
    live.x1.k6, live.x1.k7 = "Black Hole v2", 10
    live.x4.f4(Vector3.new(0, 120, 0))
    wall_clock = wall_clock + 1
    fixture.run.Heartbeat:Fire(1 / 60)
    local mod = live.get_shape("Black Hole v2")
    local actual_f2, observed = mod.f2, {}
    mod.f2 = function(p, ...)
        local velocity, target = actual_f2(p, ...)
        observed[p] = target
        return velocity, target
    end
    local pieces = {}
    for id = 1, 64 do
        local p = Instance.new("BasePart", workspace)
        p.Position = Vector3.new(id + 50, 100 + id % 13, id % 29 - 14)
        p.Size = id % 3 == 0 and Vector3.new(24, 2, 9) or Vector3.new(4, 2, 2)
        check(live.x4.f1(p), "engine claims mixed debris")
        pieces[id] = p
    end
    for _, fps in ipairs({ 30, 60, 144 }) do
        for id, p in ipairs(pieces) do
            p.Position = live.x6.b.Position + Vector3.new(id + 50, id % 13 - 20, id % 29 - 14)
        end
        for _, control in ipairs(mod.Controls) do
            if control.Key == "rwRegrab" then Controls.activate(control, live.x2["Black Hole v2"], live.x6, live.x1) end
        end
        local baselines, height_ranges, full_rate, accurate, bounded = {}, {}, true, true, true
        for frame = 1, fps * 4 do
            local dt = 1 / fps
            if frame > fps * 3 then live.x6.b.Position = live.x6.b.Position + Vector3.new(15 * dt, 0, 0) end
            table.clear(observed)
            wall_clock = wall_clock + dt
            fixture.run.Heartbeat:Fire(dt)
            for _, p in ipairs(pieces) do
                local record = live.x6.a[p]
                if not observed[p] then full_rate = false end
                local velocity = record.lv.VectorVelocity
                if not finite(velocity) or velocity.Magnitude > live.x1.MaxSpeed + 1e-6 then bounded = false end
                p.AssemblyLinearVelocity = velocity
                p.Position = p.Position + velocity * dt
                if frame >= fps * 3 then
                    local offset = p.Position - live.x6.b.Position
                    if observed[p] and not near(p.Position, observed[p], 1e-5) then accurate = false end
                    if baselines[p] then
                        local baseline = baselines[p]
                        if math.abs(offset.Magnitude - baseline.Magnitude) > 1e-4 then
                            accurate = false
                        end
                        height_ranges[p][1] = math.min(height_ranges[p][1], offset.Y)
                        height_ranges[p][2] = math.max(height_ranges[p][2], offset.Y)
                    else
                        baselines[p] = offset
                        height_ranges[p] = { offset.Y, offset.Y }
                    end
                    if offset.Magnitude > c.rwBall + 1e-4 then accurate = false end
                end
            end
        end
        local label = (mobile and "mobile" or "desktop") .. " at " .. fps .. " Hz"
        check(full_rate, label .. ": no stale bucketed orbit targets")
        check(accurate, label .. ": actual commanded motion holds a sphere while the center moves")
        check(bounded, label .. ": constraints respect the configured speed limit")
        local moving = 0
        for _, range in pairs(height_ranges) do if range[2] - range[1] > c.rwBall * 0.1 then moving = moving + 1 end end
        check(moving > #pieces * 0.9, label .. ": physical commands carry parts through all three dimensions")
    end
    local saved = {}
    for _, key in ipairs({ "k7", "k8", "Damping", "MaxSpeed" }) do saved[key] = live.x1[key] end
    live.x1.k6 = "Black Hole"
    wall_clock = wall_clock + 1 / 60
    fixture.run.Heartbeat:Fire(1 / 60)
    for key, value in pairs(saved) do check(live.x1[key] == value, "frame tracking never rewrites global physics settings") end
    live.destroy()
    for _, p in ipairs(pieces) do p:Destroy() end
end
print(checks .. " black hole geometry and engine motion checks passed")
