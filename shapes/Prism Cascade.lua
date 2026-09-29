-- Five open triangular prism cages climb and fall in a linked procession.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Prism Cascade"
local TAU = math.pi * 2
local PHI = 0.6180339887498949
local EDGES = { { 0, 1 }, { 1, 2 }, { 2, 0 }, { 3, 4 }, { 4, 5 }, { 5, 3 }, { 0, 3 }, { 1, 4 }, { 2, 5 } }

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 20, 0, 60) * x9.c2
    st.t = t
end

local function vertex(cage, index, spacing, radius, depth, rise, sway, phase)
    local a = (index % 3) * TAU / 3
    local x, y = radius * math.sin(a), radius * math.cos(a)
    local tilt = 0.14 * math.sin(phase * 0.5 - cage * 0.9)
    local co, si = math.cos(tilt), math.sin(tilt)
    return Vector3.new((cage - 2) * spacing + x * co - y * si,
        x * si + y * co + rise * (1 + math.sin(phase * 0.65 - cage * 0.85)),
        (index < 3 and -0.5 or 0.5) * depth + sway * math.sin(phase * 0.4 - cage))
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local u = (slot * PHI) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local spacing = math.clamp(c.k11 or 190, 100, 310)
    local radius = math.clamp(c.k12 or 95, 45, 170)
    local depth = math.clamp(c.k14 or 220, 80, 430)
    local rise = math.clamp(c.k15 or 110, 25, 250)
    local sway = math.clamp(c.k16 or 55, 0, 150)
    local base = math.clamp(c.k17 or 80, -100, 300)
    local a, b
    local q = (1 - math.cos(u * TAU + phase * 0.82)) * 0.5
    if slot % 5 ~= 0 then
        local id = math.floor((slot - 1) / 5)
        local cage = id % 5
        local edge = EDGES[math.floor(id / 5) % #EDGES + 1]
        a = vertex(cage, edge[1], spacing, radius, depth, rise, sway, phase)
        b = vertex(cage, edge[2], spacing, radius, depth, rise, sway, phase)
    else
        local link = math.floor((slot - 1) / 5) % 4
        local endFace = math.floor((slot - 1) / 20) % 2 == 0 and 0 or 3
        a = vertex(link, endFace + 1, spacing, radius, depth, rise, sway, phase)
        b = vertex(link + 1, endFace + 2, spacing, radius, depth, rise, sway, phase)
    end
    local pos = a + (b - a) * q
    if slot % 5 == 0 then pos = pos + Vector3.new(0, -math.sin(q * math.pi) * rise * 0.3, 0) end
    local target = cen + pos + Vector3.new(0, base, 0)
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Prism Spacing", Min = 100, Max = 310, Key = "k11", Default = 190 },
    { Type = "Slider", Name = "Triangle Radius", Min = 45, Max = 170, Key = "k12", Default = 95 },
    { Type = "Slider", Name = "Cascade Speed", Min = 0, Max = 60, Key = "k13", Default = 20, ExactMax = true },
    { Type = "Slider", Name = "Prism Depth", Min = 80, Max = 430, Key = "k14", Default = 220 },
    { Type = "Slider", Name = "Cascade Rise", Min = 25, Max = 250, Key = "k15", Default = 110 },
    { Type = "Slider", Name = "Side Sweep", Min = 0, Max = 150, Key = "k16", Default = 55 },
    { Type = "Slider", Name = "Prism Height", Min = -100, Max = 300, Key = "k17", Default = 80 },
}

return M
