-- Three stacked stadium interchanges carry continuous lanes of rubble traffic.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Nebula Highway"
local TAU = math.pi * 2
local PHI = 0.6180339887498949

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 24, 0, 60) * x9.c2
    st.t = t
end

local function track(q, straight, radius)
    local arc = math.pi * radius
    local total = 4 * straight + 2 * arc
    local dist = q * total
    if dist < 2 * straight then
        return -straight + dist, -radius
    elseif dist < 2 * straight + arc then
        local a = (dist - 2 * straight) / radius - math.pi * 0.5
        return straight + radius * math.cos(a), radius * math.sin(a)
    elseif dist < 4 * straight + arc then
        return straight - (dist - 2 * straight - arc), radius
    end
    local a = (dist - 4 * straight - arc) / radius + math.pi * 0.5
    return -straight + radius * math.cos(a), radius * math.sin(a)
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local road = (slot - 1) % 3
    local id = math.floor((slot - 1) / 3) + 1
    local u, v = (id * PHI) % 1, (id * 0.8191725133961645) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local length = math.clamp(c.k11 or 960, 450, 1500)
    local stack = math.clamp(c.k12 or 80, 30, 180)
    local bend = math.clamp(c.k14 or 95, 40, 240)
    local lanes = math.clamp(c.k15 or 16, 3, 40)
    local base = math.clamp(c.k16 or 40, -100, 250)
    local lane = id % 3 - 1
    local direction = lane == -1 and -1 or 1
    local q = (u + phase * 0.065 * direction * (1 + road * 0.1)) % 1
    local radius = math.max(8, bend + lane * lanes)
    local x, z = track(q, math.max(30, length * 0.5 - bend), radius)
    -- Each level undulates as traffic passes over and under the other two roads.
    local y = base + road * stack + stack * 0.23 * math.sin(q * TAU * 2 - phase * 0.4)
    y = y + (v - 0.5) * 9
    local yaw = road * math.pi / 3 + math.sin(phase * 0.2) * 0.12
    local co, si = math.cos(yaw), math.sin(yaw)
    local target = cen + Vector3.new(x * co - z * si, y, x * si + z * co)
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Highway Length", Min = 450, Max = 1500, Key = "k11", Default = 960 },
    { Type = "Slider", Name = "Overpass Spacing", Min = 30, Max = 180, Key = "k12", Default = 80 },
    { Type = "Slider", Name = "Traffic Speed", Min = 0, Max = 60, Key = "k13", Default = 24, ExactMax = true },
    { Type = "Slider", Name = "Turn Radius", Min = 40, Max = 240, Key = "k14", Default = 95 },
    { Type = "Slider", Name = "Lane Spacing", Min = 3, Max = 40, Key = "k15", Default = 16 },
    { Type = "Slider", Name = "Road Height", Min = -100, Max = 250, Key = "k16", Default = 40 },
}

return M
