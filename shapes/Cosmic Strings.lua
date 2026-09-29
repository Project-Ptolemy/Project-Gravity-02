-- Seven huge tensioned strings open into a fan; waves race between their anchors.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Cosmic Strings"
local TAU = math.pi * 2
local PHI = 0.6180339887498949

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 22, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local stringId = (slot - 1) % 7
    local id = math.floor((slot - 1) / 7) + 1
    local u, v = (id * PHI) % 1, (id * 0.8191725133961645) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local span = math.clamp(c.k11 or 960, 450, 1500)
    local bow = math.clamp(c.k12 or 145, 30, 400)
    local fan = math.clamp(c.k14 or 560, 200, 1000)
    local ripple = math.clamp(c.k15 or 45, 0, 120)
    local base = math.clamp(c.k16 or 55, -100, 300)
    local lane = (stringId - 3) / 3
    local q = (1 - math.cos(u * TAU + phase * 0.68)) * 0.5
    local knot = id % 8 == 0
    if knot then q = id % 16 == 0 and 0 or 1 end
    local envelope = math.sin(math.pi * q)
    local wave = math.sin(q * TAU * 2 - phase * 1.8 + stringId * 0.44)
    local x = (q - 0.5) * span
    local y = bow * envelope * (0.7 + 0.3 * math.abs(lane)) + ripple * envelope * wave
    local z = lane * fan * (0.14 + 0.36 * q)
    z = z + envelope * ripple * 0.65 * math.cos(q * TAU * 2 - phase * 1.8 + stringId)
    -- The broad end of the fan sweeps sideways; the narrow end pulls against it.
    z = z + (q * 2 - 1) * fan * 0.13 * math.sin(phase * 0.48)
    y = y + (q * 2 - 1) * bow * 0.22 * math.sin(phase * 0.62 + lane)
    if knot then
        local a = v * TAU + phase
        x, y, z = x + 13 * math.cos(a), y + 13 * math.sin(a), z + (u - 0.5) * 22
    end
    local target = cen + Vector3.new(x, y + base, z)
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "String Span", Min = 450, Max = 1500, Key = "k11", Default = 960 },
    { Type = "Slider", Name = "String Bow", Min = 30, Max = 400, Key = "k12", Default = 145 },
    { Type = "Slider", Name = "Pluck Speed", Min = 0, Max = 60, Key = "k13", Default = 22, ExactMax = true },
    { Type = "Slider", Name = "Fan Width", Min = 200, Max = 1000, Key = "k14", Default = 560 },
    { Type = "Slider", Name = "Traveling Ripple", Min = 0, Max = 120, Key = "k15", Default = 45 },
    { Type = "Slider", Name = "Anchor Height", Min = -100, Max = 300, Key = "k16", Default = 55 },
}

return M
