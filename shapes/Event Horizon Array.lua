-- Four separated dense cores trade debris through broad arcing tidal bridges.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Event Horizon Array"
local TAU = math.pi * 2
local PHI = 0.6180339887498949
local LINKS = { { 0, 1 }, { 1, 2 }, { 2, 3 }, { 3, 0 }, { 0, 2 }, { 1, 3 } }

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 20, 0, 60) * x9.c2
    st.t = t
end

local function core(index, width, wander, phase)
    local a = math.pi * 0.25 + index * math.pi * 0.5 + 0.13 * math.sin(phase * 0.2)
    local r = width * 0.62 + wander * 0.4 * math.sin(phase * 0.45 + index)
    return Vector3.new(r * math.cos(a), wander * 0.5 * math.sin(phase * 0.65 + index * 1.6), r * math.sin(a))
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local u, v = (slot * PHI) % 1, (slot * 0.8191725133961645) % 1
    local w = (slot * 0.5497004779019703) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local width = math.clamp(c.k11 or 740, 350, 1200)
    local size = math.clamp(c.k12 or 64, 25, 150)
    local arch = math.clamp(c.k14 or 220, 50, 450)
    local wander = math.clamp(c.k15 or 80, 0, 200)
    local base = math.clamp(c.k16 or 90, -100, 300)
    local pos
    if slot % 10 < 4 then
        local index = math.floor((slot - 1) / 10) % 4
        local a = u * TAU + phase * (1 + index * 0.13)
        local h = v * 2 - 1
        local r = size * (0.4 + 0.6 * w ^ (1 / 3))
        local ring = math.sqrt(1 - h * h)
        pos = core(index, width, wander, phase) + Vector3.new(r * ring * math.cos(a), r * h, r * ring * math.sin(a))
    else
        local link = LINKS[math.floor((slot - 1) / 10) % #LINKS + 1]
        local a = core(link[1], width, wander, phase)
        local b = core(link[2], width, wander, phase)
        local q = (1 - math.cos(u * TAU + phase * 1.1)) * 0.5
        local wave = math.sin(q * math.pi)
        local sign = slot % 2 == 0 and 1 or -1
        local side = Vector3.new(-(b.Z - a.Z), 0, b.X - a.X).Unit
        pos = a + (b - a) * q + Vector3.new(0, arch * wave * (0.85 + sign * 0.15), 0)
        pos = pos + side * (wave * (sign * size * 0.38 + size * 0.6 * math.sin(q * TAU - phase * 0.65)))
    end
    local target = cen + pos + Vector3.new(0, base, 0)
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Core Separation", Min = 350, Max = 1200, Key = "k11", Default = 740 },
    { Type = "Slider", Name = "Core Radius", Min = 25, Max = 150, Key = "k12", Default = 64 },
    { Type = "Slider", Name = "Tidal Exchange", Min = 0, Max = 60, Key = "k13", Default = 20, ExactMax = true },
    { Type = "Slider", Name = "Bridge Arch", Min = 50, Max = 450, Key = "k14", Default = 220 },
    { Type = "Slider", Name = "Core Wander", Min = 0, Max = 200, Key = "k15", Default = 80 },
    { Type = "Slider", Name = "Array Height", Min = -100, Max = 300, Key = "k16", Default = 90 },
}

return M
