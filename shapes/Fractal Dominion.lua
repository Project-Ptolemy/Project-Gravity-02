-- Four great trunks split into a three-generation orthogonal branching network.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Fractal Dominion"
local TAU = math.pi * 2
local PHI = 0.6180339887498949

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 17, 0, 60) * x9.c2
    st.t = t
end

local function bend(x, z, span, rise, growth, phase)
    local r = math.sqrt(x * x + z * z)
    local stretch = 1 + growth * 0.01 * math.sin(phase * 0.5 - r * 3)
    local y = rise * (0.25 + r * 0.9) + rise * 0.32 * math.sin(phase * 0.6 - r * 4)
    return Vector3.new(x * span * stretch, y, z * span * stretch)
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local edge = (slot - 1) % 28
    local id = math.floor((slot - 1) / 28) + 1
    local u, v = (id * PHI) % 1, (slot * 0.8191725133961645) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local span = math.clamp(c.k11 or 860, 400, 1400)
    local rise = math.clamp(c.k12 or 150, 30, 350)
    local thickness = math.clamp(c.k14 or 14, 2, 45)
    local growth = math.clamp(c.k15 or 18, 0, 35)
    local base = math.clamp(c.k16 or 30, -100, 250)
    local arm, ax, az, bx, bz
    if edge < 4 then
        arm, ax, az, bx, bz = edge, 0, 0, 0.35, 0
    elseif edge < 12 then
        local branch = edge - 4
        arm = math.floor(branch / 2)
        local side = branch % 2 == 0 and -1 or 1
        ax, az, bx, bz = 0.35, 0, 0.35, side * 0.22
    else
        local branch = edge - 12
        arm = math.floor(branch / 4)
        local side = math.floor(branch / 2) % 2 == 0 and -1 or 1
        local tip = branch % 2 == 0 and -1 or 1
        ax, az, bx, bz = 0.35, side * 0.22, 0.35 + tip * 0.13, side * 0.22
    end
    local q = (1 - math.cos(u * TAU + phase * 0.7)) * 0.5
    if id % 7 == 0 then q = 1 end
    local x, z = ax + (bx - ax) * q, az + (bz - az) * q
    local angle = arm * math.pi * 0.5
    x, z = x * math.cos(angle) - z * math.sin(angle), x * math.sin(angle) + z * math.cos(angle)
    local pos = bend(x, z, span, rise, growth, phase)
    local a = v * TAU + phase
    pos = pos + Vector3.new(thickness * 0.5 * math.cos(a), thickness * 0.5 * math.sin(a), 0)
    local target = cen + pos + Vector3.new(0, base, 0)
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Branching Span", Min = 400, Max = 1400, Key = "k11", Default = 860 },
    { Type = "Slider", Name = "Outer Branch Rise", Min = 30, Max = 350, Key = "k12", Default = 150 },
    { Type = "Slider", Name = "Branch Surge", Min = 0, Max = 60, Key = "k13", Default = 17, ExactMax = true },
    { Type = "Slider", Name = "Branch Thickness", Min = 2, Max = 45, Key = "k14", Default = 14 },
    { Type = "Slider", Name = "Expansion %", Min = 0, Max = 35, Key = "k15", Default = 18 },
    { Type = "Slider", Name = "Root Height", Min = -100, Max = 250, Key = "k16", Default = 30 },
}

return M
