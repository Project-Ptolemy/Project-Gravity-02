-- A map-wide diamond truss: moving struts connect seven dense stellar joints.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Constellation Lattice"
local TAU = math.pi * 2
local PHI = 0.6180339887498949
local NODES = { { -1, 0, -1 }, { 1, 0, -1 }, { 1, 0, 1 }, { -1, 0, 1 },
    { 0, 1, 0 }, { 0, -0.35, 0 }, { 0, 0.2, 0 } }
local EDGES = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 }, { 1, 5 }, { 2, 5 },
    { 3, 5 }, { 4, 5 }, { 1, 6 }, { 2, 6 }, { 3, 6 }, { 4, 6 },
    { 1, 7 }, { 2, 7 }, { 3, 7 }, { 4, 7 }, { 5, 7 }, { 6, 7 } }

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 18, 0, 60) * x9.c2
    st.t = t
end

local function joint(index, width, height, flex, phase)
    local n = NODES[index]
    local pulse = 1 + flex * 0.001 * math.sin(phase * 0.37 + index * 1.4)
    return Vector3.new(n[1] * width * 0.46 * pulse,
        n[2] * height + flex * 0.45 * math.sin(phase * 0.6 + index),
        n[3] * width * 0.46 * pulse)
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local u, v = (slot * PHI) % 1, (slot * 0.8191725133961645) % 1
    local w = (slot * 0.5497004779019703) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local width = math.clamp(c.k11 or 860, 400, 1400)
    local height = math.clamp(c.k12 or 310, 100, 550)
    local flex = math.clamp(c.k14 or 55, 0, 150)
    local nodeSize = math.clamp(c.k15 or 27, 8, 80)
    local base = math.clamp(c.k16 or 90, -100, 300)
    local pos
    if slot % 10 < 7 then
        local edge = EDGES[(math.floor((slot - 1) / 10) * 7) % #EDGES + 1]
        -- A reversing traverse keeps pieces on their beam without endpoint jumps.
        local q = (1 - math.cos(u * TAU + phase * 0.9)) * 0.5
        local a = joint(edge[1], width, height, flex, phase)
        local b = joint(edge[2], width, height, flex, phase)
        pos = a + (b - a) * q
        pos = pos + Vector3.new(0, math.sin(q * math.pi) * math.sin(phase + u * TAU) * 8, 0)
    else
        local node = (math.floor((slot - 1) / 10) * 3) % #NODES + 1
        local a = u * TAU + phase * 0.65
        local y = v * 2 - 1
        local r = nodeSize * (0.55 + w * 0.45)
        local ring = math.sqrt(1 - y * y)
        pos = joint(node, width, height, flex, phase) + Vector3.new(r * ring * math.cos(a), r * y, r * ring * math.sin(a))
    end
    local yaw = math.sin(phase * 0.19) * 0.2
    local co, si = math.cos(yaw), math.sin(yaw)
    local target = cen + Vector3.new(pos.X * co - pos.Z * si, pos.Y + base, pos.X * si + pos.Z * co)
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Lattice Width", Min = 400, Max = 1400, Key = "k11", Default = 860 },
    { Type = "Slider", Name = "Diamond Height", Min = 100, Max = 550, Key = "k12", Default = 310 },
    { Type = "Slider", Name = "Truss Motion", Min = 0, Max = 60, Key = "k13", Default = 18, ExactMax = true },
    { Type = "Slider", Name = "Joint Flex", Min = 0, Max = 150, Key = "k14", Default = 55 },
    { Type = "Slider", Name = "Star Joint Size", Min = 8, Max = 80, Key = "k15", Default = 27 },
    { Type = "Slider", Name = "Lattice Lift", Min = -100, Max = 300, Key = "k16", Default = 90 },
}

return M
