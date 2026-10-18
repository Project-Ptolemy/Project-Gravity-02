-- Generated modules run inside the real desktop/mobile engine. This integrates
-- commanded velocity, not Roblox contacts, network ownership or part inertia.
package.path = "tests/?.lua;" .. package.path
local fixture = require("runtime_fixture")
local payload = assert(loadfile(assert(arg[1], "run via builder_runtime.test.mjs")))()
local clock, checks = 10, 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function near(a, b, tolerance) return (a - b).Magnitude <= (tolerance or 1e-6) end
-- Lune's native Roblox Vector3 exercises the engine's float32 boundary.
-- A world target rounds once when the local offset becomes a Vector3, then
-- again when adding the core; double-only math mocks cannot catch that.
do
    local saved = Vector3
    Vector3 = require("@lune/roblox").Vector3
    local xyz = payload.native_center
    local center = Vector3.new(xyz[1], xyz[2], xyz[3])
    local part, x6, c, x1, x9 = { Position = Vector3.zero }, { n = 8 }, {}, { k10 = 20 }, { c1 = 0.15 }
    for _, case in ipairs(payload.native_cases) do
        payload.moving.px(case.time, c, x6, x9, x1)
        for i, point in ipairs(case.points) do
            local _, target = payload.moving.f2(part, center, { id = i }, case.time, c, x1, x6, x9)
            check(target.X == point[1] and target.Y == point[2] and target.Z == point[3], "native float32 target matches browser rounding at distant world coordinates")
        end
    end
    Vector3 = saved
end
time = function() return clock end
game.HttpGet = function(_, url)
    local path = assert(url:match("/main/(.-)%?cb="), url)
    local file = assert(io.open(path), path)
    local source = file:read("a"); file:close(); return source
end
local function tick(dt)
    clock = clock + dt
    fixture.run.Heartbeat:Fire(dt)
end

for _, mobile in ipairs({ false, true }) do
    fixture.input.TouchEnabled, fixture.input.KeyboardEnabled = mobile, not mobile
    assert(loadfile("main.lua"))()
    local context = assert(getgenv()._GRAVITY_CONTEXT)
    local x1, x6, label = context.x1, context.x6, mobile and "mobile" or "desktop"
    for _, name in ipairs({ "moving", "static", "controlled" }) do
        context.loaded_shapes[name], context.x2[name] = payload[name], {}
    end
    x1.k6, x1.k7 = "moving", 10
    x1.MaxFidelity, x1["Force Smooth (Lags)"] = false, false
    context.x4.f4(Vector3.new(0, 120, 0))
    tick(1 / 60)
    local pieces, observed, calls = {}, {}, {}
    for id = 1, 8 do
        local p = Instance.new("BasePart", workspace)
        p.Position, p.Size = x6.b.Position, Vector3.new(2, 2, 2)
        check(context.x4.f1(p), label .. ": claim generated formation part")
        pieces[id] = p
    end
    local original = payload.moving.f2
    payload.moving.f2 = function(p, ...)
        local velocity, target = original(p, ...)
        observed[p] = target
        calls[p] = (calls[p] or 0) + 1
        return velocity, target
    end
    local settings = {}
    for _, key in ipairs({ "k7", "k8", "Damping", "MaxSpeed", "Ki" }) do settings[key] = x1[key] end
    for _, fps in ipairs({ 30, 60, 144 }) do
        x6.shape_clock, x6.transition_time, x6.water_level = 0, 0, false
        payload.moving.cleanup(x6, x1)
        for _, p in ipairs(pieces) do
            p.Position, p.AssemblyLinearVelocity = x6.b.Position, Vector3.zero
            local d = x6.a[p]
            d.last_target_pos, d.sys_last_t, d.physics_last_t, d.trans_vl = nil, nil, nil, nil
            d.integral, d.vl = Vector3.zero, Vector3.zero
        end
        for frame = 1, fps * 2 do
            table.clear(observed)
            local dt = 1 / fps
            if frame > fps then x6.b.Position = x6.b.Position + Vector3.new(7 * dt, 0, 0) end
            tick(dt)
            for i, p in ipairs(pieces) do
                local expected = payload.expected[fps][frame][i]
                local target = x6.b.Position + Vector3.new(expected[1], expected[2], expected[3])
                check(observed[p] and near(observed[p], target), label .. ": generated targets match browser math at " .. fps .. " Hz")
                local velocity = x6.a[p].lv.VectorVelocity
                check(velocity.Magnitude <= x1.MaxSpeed + 1e-6, label .. ": target tracking respects global speed cap")
                p.AssemblyLinearVelocity, p.Position = velocity, p.Position + velocity * dt
                if frame > fps then
                    check(near(p.Position, observed[p], 1e-5), label .. ": animated parts converge to moving targets at " .. fps .. " Hz")
                end
            end
        end
    end
    for key, value in pairs(settings) do check(x1[key] == value, label .. ": tracking preserves setting " .. key) end
    payload.moving.f2 = original

    -- Static targets inside the core dead-zone still run, but retain ordinary
    -- four-frame scheduling rather than spending per-frame work on every part.
    x1.k6, x1.k7 = "static", 4
    tick(1 / 60)
    local static_f2 = payload.static.f2
    table.clear(calls)
    payload.static.f2 = function(p, ...)
        calls[p] = (calls[p] or 0) + 1
        local velocity, target = static_f2(p, ...)
        observed[p] = target
        return velocity, target
    end
    for _, p in ipairs(pieces) do p.Position = x6.b.Position end
    for _ = 1, 40 do tick(1 / 60) end
    for i, p in ipairs(pieces) do
        local point = payload.static_points[i]
        check(calls[p] == 10, label .. ": static targets keep bucket scheduling inside the core")
        check(near(observed[p], x6.b.Position + Vector3.new(point[1], point[2], point[3])), label .. ": static target retains precise coordinates")
    end
    payload.static.f2 = static_f2
    context.destroy()
    for _, p in ipairs(pieces) do p:Destroy() end
end
print(checks .. " generated-builder desktop/mobile engine checks passed (30, 60, 144 Hz; target parity, tracking, speed limits and static scheduling)")
