-- A colossal clock face with counter-turning rim segments and three sweeping hands.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Astral Clockwork"
local TAU = math.pi * 2
local PHI = 0.6180339887498949

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 20, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local u, v = (slot * PHI) % 1, (slot * 0.8191725133961645) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local radius = math.clamp(c.k11 or 455, 220, 750)
    local lift = math.clamp(c.k12 or 35, 0, 120)
    local handWidth = math.clamp(c.k14 or 24, 5, 70)
    local rimWidth = math.clamp(c.k15 or 28, 8, 70)
    local tilt = math.clamp(c.k16 or 18, 0, 45) * math.pi / 180
    local base = math.clamp(c.k17 or 95, -100, 300)
    local group = slot % 20
    local x, y, z
    if group < 8 then
        local inner = group >= 4
        local segment = math.floor(u * 48)
        local within = (u * 48) % 1
        local a = (segment + within * 0.78) * TAU / 48 + phase * (inner and -0.1 or 0.075)
        local r = radius * (inner and 0.9 or 1) + (v - 0.5) * rimWidth
        x, z = r * math.cos(a), r * math.sin(a)
        y = lift * 0.18 * math.sin(a * 6 + phase)
    elseif group < 12 then
        local tick = math.floor((slot - 1) / 20) % 12
        local a = tick * TAU / 12 + phase * 0.018
        local r = radius * (0.69 + u * 0.14)
        x, z = r * math.cos(a), r * math.sin(a)
        y = lift * 0.18 * math.sin(a * 6 + phase)
    elseif group < 18 then
        local hand = (group - 12) % 3
        local rate = hand == 0 and 0.82 or (hand == 1 and 0.28 or -0.11)
        local a = phase * rate + hand * TAU / 3
        local q = (1 - math.cos(u * TAU + phase * 0.45)) * 0.5
        local reach = radius * (0.88 - hand * 0.17)
        local along = -radius * 0.09 + q * reach
        local cross = (v - 0.5) * handWidth * (1.5 - q)
        x, z = along * math.cos(a) - cross * math.sin(a), along * math.sin(a) + cross * math.cos(a)
        y = lift * (0.5 + hand * 0.45) + math.sin(q * math.pi) * lift * 0.25
    else
        local a = u * TAU + phase
        local r = radius * (0.035 + 0.065 * v)
        x, y, z = r * math.cos(a), lift * (0.5 + 0.6 * math.sin(a * 2)), r * math.sin(a)
    end
    local angle = tilt * math.sin(phase * 0.17 + 0.45)
    local target = cen + Vector3.new(x, y * math.cos(angle) - z * math.sin(angle) + base,
        y * math.sin(angle) + z * math.cos(angle))
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Clock Radius", Min = 220, Max = 750, Key = "k11", Default = 455 },
    { Type = "Slider", Name = "Hand Clearance", Min = 0, Max = 120, Key = "k12", Default = 35 },
    { Type = "Slider", Name = "Clockwork Speed", Min = 0, Max = 60, Key = "k13", Default = 20, ExactMax = true },
    { Type = "Slider", Name = "Hand Width", Min = 5, Max = 70, Key = "k14", Default = 24 },
    { Type = "Slider", Name = "Rim Thickness", Min = 8, Max = 70, Key = "k15", Default = 28 },
    { Type = "Slider", Name = "Dial Tilt", Min = 0, Max = 45, Key = "k16", Default = 18 },
    { Type = "Slider", Name = "Dial Height", Min = -100, Max = 300, Key = "k17", Default = 95 },
}

return M
