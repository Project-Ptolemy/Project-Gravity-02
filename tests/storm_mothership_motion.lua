-- Geometry and real desktop/mobile velocity tracking for the storm and ship.
-- The fixture integrates commanded velocity, not Roblox's contact solver.
package.path = "tests/?.lua;" .. package.path
require("robloxenv")
local config = assert(loadfile("config.lua"))()
local Storm = assert(loadfile("shapes/Storm Gyre.lua"))()
local Ship = assert(loadfile("shapes/Alien Mothership.lua"))()
local x1, x9 = config.x1, { c1 = 0.15, c2 = 0.05 }
local checks = 0
local function check(ok, label) checks = checks + 1; assert(ok, label) end
local function near(a, b, epsilon) return (a - b).Magnitude < (epsilon or 1e-6) end
local function finite(v) return v and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e7 end
local function part(position) return { Position = position or Vector3.zero, Size = Vector3.new(4, 2, 2) } end
local function target(mod, cfg, ctx, id, t, center, record)
    local velocity, point = mod.f2(part(), center or Vector3.zero, record or { id = id }, t, cfg, x1, ctx, x9)
    check(finite(point) and finite(velocity), "finite target and velocity")
    return point
end
local function start(mod, cfg, t)
    local ctx = { pre = {} }
    mod.px(0, cfg, ctx, x9)
    mod.px(t or 0, cfg, ctx, x9)
    return ctx
end

-- De-rotate each bolt so a slow orbit cannot pass for lightning crackle.
-- A bolt must bend repeatedly within two seconds without jumping between paths.
do
    local cfg = config.x2["Storm Gyre"]
    local ctx = start(Storm, cfg)
    local bolts = {}
    for id = 1, 512 do
        if id * 0.6180339887498949 % 1 >= 0.86 then
            bolts[#bolts + 1] = { id = id, min = math.huge, max = -math.huge, reversals = 0 }
        end
    end
    local max_step = 0
    for frame = 0, 120 do
        local t = frame / 60
        Storm.px(t, cfg, ctx, x9)
        for _, bolt in ipairs(bolts) do
            local point = target(Storm, cfg, ctx, bolt.id, t)
            local angle = (bolt.id - 1) % 7 * math.pi * 2 / 7 + t * cfg.k13 * x9.c2 * 0.09
            local bend = -point.X * math.sin(angle) + point.Z * math.cos(angle)
            bolt.min, bolt.max = math.min(bolt.min, bend), math.max(bolt.max, bend)
            if bolt.previous then
                max_step = math.max(max_step, (point - bolt.previous).Magnitude)
                local velocity = bend - bolt.bend
                if bolt.velocity and velocity * bolt.velocity < 0 then bolt.reversals = bolt.reversals + 1 end
                bolt.velocity = velocity
            end
            bolt.previous, bolt.bend = point, bend
        end
    end
    local excursion, reversals = 0, 0
    for _, bolt in ipairs(bolts) do
        excursion = excursion + bolt.max - bolt.min
        reversals = reversals + bolt.reversals
    end
    check(excursion / #bolts > 4, "lightning visibly bends independently of its orbit")
    check(reversals / #bolts >= 6, "lightning crackles several times per second")
    check(max_step < 3, "default lightning has no discontinuous frame jumps")
end

-- Persistent beam strata keep the upper end attached, span the requested
-- length and avoid full-length wraps for both sparse and dense collections.
for _, count in ipairs({ 80, 512 }) do
    for _, length in ipairs({ 50, 200, 500 }) do
        local cfg = table.clone(config.x2["Alien Mothership"]); cfg.k14 = length
        local ctx, beam, previous = start(Ship, cfg), {}, {}
        for id = 1, count do
            local point = target(Ship, cfg, ctx, id, 0)
            if point.Y <= -cfg.k12 then beam[#beam + 1] = id end
        end
        check(#beam >= math.floor(count * 0.18), "the beam retains enough pieces to join the ship")
        for frame = 0, 240 do
            local t = frame / 60
            Ship.px(t, cfg, ctx, x9)
            local depths = {}
            for _, id in ipairs(beam) do
                local point = target(Ship, cfg, ctx, id, t)
                local depth = (-point.Y - cfg.k12) / length
                depths[#depths + 1] = depth
                check(depth >= -1e-7 and depth <= 1, "beam stays below the hull and within its length")
                if previous[id] then
                    check(math.abs(point.Y - previous[id].Y) < length * 0.002,
                        "beam flow never wraps or races down the entire column")
                end
                previous[id] = point
            end
            table.sort(depths)
            check(depths[1] < 0.001, "beam emitter touches the underside every frame")
            check(depths[#depths] > 0.9, "beam fills its full requested reach")
            for i = 2, #depths do
                check(depths[i] - depths[i - 1] < 0.13, "beam stays filled without a detached lower cloud")
            end
        end
    end
end

-- Shared clocks support late captures, sparse sampling, speed edits, freezing,
-- reverse time and translated anchors without a random reassignment.
for name, mod in pairs({ ["Storm Gyre"] = Storm, ["Alien Mothership"] = Ship }) do
    local cfg = table.clone(config.x2[name])
    for _, control in ipairs(mod.Controls) do
        check(cfg[control.Key] == control.Default, name .. ": plugin defaults agree with built-ins")
    end
    local ctx = start(mod, cfg)
    for frame = 1, 360 do mod.px(frame / 60, cfg, ctx, x9) end
    local sparse = start(mod, cfg, 6)
    for id = 1, 128 do
        local before = target(mod, cfg, ctx, id, 6)
        check(near(before, target(mod, cfg, sparse, id, 6)), name .. ": sparse and full-rate clocks agree")
        check(near(before, target(mod, cfg, ctx, id, 6)), name .. ": new records keep the same assignment")
        local shift = Vector3.new(70, -15, 22)
        check(near(before + shift, target(mod, cfg, ctx, id, 6, shift)), name .. ": moving anchor translates all geometry")
    end
    local before = target(mod, cfg, ctx, 8, 6)
    cfg.k13 = 0
    mod.px(10, cfg, ctx, x9)
    check(near(before, target(mod, cfg, ctx, 8, 10)), name .. ": speed zero freezes formation motion")
    cfg.k13 = config.x2[name].k13
    mod.px(11, cfg, ctx, x9)
    mod.px(10, cfg, ctx, x9)
    check(near(before, target(mod, cfg, ctx, 8, 10)), name .. ": reverse time retraces the path")
    mod.cleanup(ctx)
    check(ctx.pre[name] == nil, name .. ": cleanup releases its clock")

    for _, high in ipairs({ false, true }) do
        local limits = table.clone(cfg)
        for _, control in ipairs(mod.Controls) do
            if control.Type == "Slider" then
                local upper = control.Max
                if control.Name:lower():find("speed") and not control.ExactMax then upper = upper + 300 end
                limits[control.Key] = (high and upper or control.Min) / (control.Div or 1)
            end
        end
        local boundary = start(mod, limits)
        for _, t in ipairs({ 0, 1 / 120, 0.5, 1000 }) do
            mod.px(t, limits, boundary, x9)
            for id = 1, 128 do target(mod, limits, boundary, id, t) end
        end
    end
end

-- Exercise the actual loader, defaults, damping and update buckets. Y sampling
-- catches the old beam averaging into a disconnected cloud below the hull.
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
    live.x1.k6 = "Alien Mothership"
    live.x4.f4(Vector3.new(0, 300, 0))
    wall_clock = wall_clock + 1
    fixture.run.Heartbeat:Fire(1 / 60)
    local mod, observed = live.get_shape("Alien Mothership"), {}
    local actual_f2 = mod.f2
    mod.f2 = function(p, ...)
        local velocity, point = actual_f2(p, ...)
        observed[p] = point
        return velocity, point
    end
    local pieces = {}
    for id = 1, 80 do
        local p = Instance.new("BasePart", workspace)
        p.Position, p.Size = Vector3.new(id, 280, 0), Vector3.new(4, 2, 2)
        check(live.x4.f1(p), "engine claims mothership debris")
        pieces[id] = p
    end
    for _, fps in ipairs({ 30, 60, 144 }) do
        for _, bucket in ipairs({ 1, 4, 10 }) do
            live.x1.k7 = bucket
            local max_vertical_error, min_depth, max_depth = 0, math.huge, 0
            for frame = 1, fps * 7 do
                local dt = 1 / fps
                wall_clock = wall_clock + dt
                fixture.run.Heartbeat:Fire(dt)
                for _, p in ipairs(pieces) do
                    local record = live.x6.a[p]
                    local velocity = record.lv.VectorVelocity
                    check(finite(velocity), "runtime velocity stays finite")
                    p.AssemblyLinearVelocity = velocity
                    p.Position = p.Position + velocity * dt
                    local point = observed[p]
                    if frame > fps * 6 and point and point.Y <= live.x6.b.Position.Y - 40 then
                        max_vertical_error = math.max(max_vertical_error, math.abs(p.Position.Y - point.Y))
                        local depth = live.x6.b.Position.Y - 40 - p.Position.Y
                        min_depth, max_depth = math.min(min_depth, depth), math.max(max_depth, depth)
                    end
                end
            end
            local label = (mobile and "mobile" or "desktop") .. " at " .. fps .. " Hz, bucket " .. bucket
            check(max_vertical_error < 8, label .. ": real beam remains close to its vertical target")
            check(min_depth < 2 and max_depth > 175, label .. ": real beam joins hull and spans its reach")
        end
    end

    live.x1.k6, live.x1.k7 = "Storm Gyre", 4
    local radius_range = {}
    for frame = 1, 360 do
        local dt = 1 / 60
        wall_clock = wall_clock + dt
        fixture.run.Heartbeat:Fire(dt)
        for _, p in ipairs(pieces) do
            local record = live.x6.a[p]
            local velocity = record.lv.VectorVelocity
            check(finite(velocity), "storm runtime velocity stays finite")
            p.AssemblyLinearVelocity = velocity
            p.Position = p.Position + velocity * dt
            local id = record.slot or record.id
            if frame > 240 and id * 0.6180339887498949 % 1 >= 0.86 then
                local offset = p.Position - live.x6.b.Position - live.x6.motion_offset
                local radius = math.sqrt(offset.X * offset.X + offset.Z * offset.Z)
                local range = radius_range[p] or { min = radius, max = radius }
                range.min, range.max = math.min(range.min, radius), math.max(range.max, radius)
                radius_range[p] = range
            end
        end
    end
    local excursion, count = 0, 0
    for _, range in pairs(radius_range) do
        excursion, count = excursion + range.max - range.min, count + 1
    end
    check(count >= 8 and excursion / count > 3,
        (mobile and "mobile" or "desktop") .. ": bolt crackle remains visible through real velocity tracking")
    live.destroy()
    for _, p in ipairs(pieces) do p:Destroy() end
end
print(checks .. " storm and mothership motion checks passed")
