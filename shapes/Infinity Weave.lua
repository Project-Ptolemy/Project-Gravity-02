-- Four braided streams cross over and under one another around two huge open lobes.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Infinity Weave"
local TAU = math.pi * 2
local PHI = 0.6180339887498949

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 24, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local strand = (slot - 1) % 4
    local id = math.floor((slot - 1) / 4) + 1
    local u = (id * PHI) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local span = math.clamp(c.k11 or 1000, 450, 1600)
    local crossing = math.clamp(c.k12 or 120, 35, 280)
    local braidWidth = math.clamp(c.k14 or 28, 6, 75)
    local braids = math.clamp(math.floor(c.k15 or 4), 2, 8)
    local base = math.clamp(c.k16 or 100, -100, 300)
    local a = u * TAU + phase * 0.67
    local x, z = span * 0.5 * math.cos(a), span * 0.29 * math.sin(a * 2)
    local y = crossing * math.sin(a)
    local dx, dz = -0.5 * math.sin(a), 0.58 * math.cos(a * 2)
    local norm = math.sqrt(dx * dx + dz * dz)
    local twist = a * braids + strand * TAU / 4 - phase * 0.4
    local side = braidWidth * math.cos(twist)
    x, z = x - dz / norm * side, z + dx / norm * side
    y = y + braidWidth * math.sin(twist)
    -- A slow traveling flex stretches each open lobe without closing the holes.
    local breath = 1 + 0.06 * math.sin(phase * 0.36 + a * 2)
    local target = cen + Vector3.new(x * breath, y + base, z)
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Infinity Span", Min = 450, Max = 1600, Key = "k11", Default = 1000 },
    { Type = "Slider", Name = "Crossing Clearance", Min = 35, Max = 280, Key = "k12", Default = 120 },
    { Type = "Slider", Name = "Weave Flow", Min = 0, Max = 60, Key = "k13", Default = 24, ExactMax = true },
    { Type = "Slider", Name = "Braid Width", Min = 6, Max = 75, Key = "k14", Default = 28 },
    { Type = "Slider", Name = "Braid Turns", Min = 2, Max = 8, Key = "k15", Default = 4, IntOnly = true },
    { Type = "Slider", Name = "Weave Height", Min = -100, Max = 300, Key = "k16", Default = 100 },
}

return M
