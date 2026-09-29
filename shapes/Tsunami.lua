-- Two inward-breaking surf walls, carried along a sweeping shoreline.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Tsunami"
local TAU = math.pi * 2
local PHI = 0.6180339887498949

local function smooth(s) return s * s * (3 - 2 * s) end

local function bezier(s, a, b, c, d)
    local v = 1 - s
    return v * v * v * a + 3 * v * v * s * b + 3 * v * s * s * c + s * s * s * d
end

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then
        st = { phase = 0, t = t }
        x6.pre[NAME] = st
    end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 24, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local side = slot % 2 == 0 and 1 or -1
    local id = math.floor((slot - 1) / 2) + 1
    local pick = (id * PHI) % 1
    local u = (id * 0.8191725133961645) % 1
    local v = (id * 0.6710436067037893) % 1
    local w = (id * 0.5497004779019703) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local reach = math.clamp(c.k11 or 220, 80, 400)
    local height = math.clamp(c.k12 or 180, 50, 320)
    local depth = math.clamp(c.k14 or 300, 80, 650)
    local curl = math.clamp(c.k15 or 70, 0, 100) / 100
    local sweep = math.clamp(c.k16 or 110, 0, 350)
    local base = math.clamp(c.k17 or -20, -100, 250)
    local a = phase * 0.8 + u * TAU
    local x, y, z

    if pick < 0.84 then
        -- Each piece climbs the outer face, pours over the inward crest,
        -- falls down the hollow face and returns along the bottom. The path
        -- closes at its own endpoints, so wrapping q never teleports debris.
        local q = (u + phase * 0.8 / TAU) % 1
        local tip = 0.42 - curl * 0.27
        if q < 0.46 then
            local s = smooth(q / 0.46)
            x = bezier(s, 1, 1.07, 0.77, tip)
            y = bezier(s, 0, 0.68, 1.24, 0.96)
        elseif q < 0.86 then
            local s = smooth((q - 0.46) / 0.4)
            x = bezier(s, tip, 0.58 + curl * 0.08, 0.84, 0.3)
            y = bezier(s, 0.96, 1.02 - curl * 0.05, 0.14, 0)
        else
            local s = smooth((q - 0.86) / 0.14)
            x = bezier(s, 0.3, 0.04, 1, 1)
            y = bezier(s, 0, -0.015, -0.015, 0)
        end
        z = (v - 0.5) * depth
        local swell = math.sin(phase * 0.95 - v * TAU * 1.2)
        x = reach * x + reach * 0.07 * swell * (0.2 + y)
        y = height * y * (0.94 + 0.06 * math.cos(v * TAU - phase))
        -- A little volume makes mixed building rubble read as heavy surf.
        x = x + (w - 0.5) * reach * 0.075
        y = y + (w - 0.5) * height * 0.035
    else
        -- Low wash rolls well beyond the foot of both breakers.
        x = reach * (0.61 + 0.5 * math.cos(a))
        y = height * (0.012 + 0.045 * math.sin(a) ^ 2) + (w - 0.5) * 5
        z = (v - 0.5) * depth * 1.08 + reach * 0.12 * math.sin(a)
    end

    x = side * x
    local yaw = 0.24 * math.sin(phase * 0.27)
    local cy, sy = math.cos(yaw), math.sin(yaw)
    local target = cen + Vector3.new(x * cy - z * sy, y + base,
        x * sy + z * cy + sweep * math.sin(phase * 0.48))
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Wave Reach", Min = 80, Max = 400, Key = "k11", Default = 220 },
    { Type = "Slider", Name = "Wave Height", Min = 50, Max = 320, Key = "k12", Default = 180 },
    { Type = "Slider", Name = "Surge Speed", Min = 0, Max = 60, Key = "k13", Default = 24, ExactMax = true },
    { Type = "Slider", Name = "Shoreline Width", Min = 80, Max = 650, Key = "k14", Default = 300 },
    { Type = "Slider", Name = "Crest Curl %", Min = 0, Max = 100, Key = "k15", Default = 70, IntOnly = true },
    { Type = "Slider", Name = "Sweep Distance", Min = 0, Max = 350, Key = "k16", Default = 110 },
    { Type = "Slider", Name = "Waterline Height", Min = -100, Max = 250, Key = "k17", Default = -20 },
}

return M
