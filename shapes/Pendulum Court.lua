-- Three massive A-frames march together while their weighted pendulums oppose.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Pendulum Court"

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 22, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local frame, id = (slot - 1) % 3 - 1, math.floor((slot - 1) / 3) + 1
    local pick = (id * 0.6180339887498949) % 1
    local u, v = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1
    local w = (id * 0.5497004779019703) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local span = math.clamp(c.k11 or 960, 450, 1600)
    local height = math.clamp(c.k12 or 340, 160, 650)
    local size = math.clamp(c.k14 or 95, 40, 180)
    local swing = math.rad(math.clamp(c.k15 or 60, 15, 80))
    local travel = math.clamp(c.k16 or 250, 0, 600)
    local width, depth = span * 0.29, span * 0.09
    local x, y, z
    if pick < 0.48 then
        local side = id % 2 == 0 and 1 or -1
        x = side * width * 0.5 * (1 - u) + (v - 0.5) * width * 0.055
        y, z = height * u, (w - 0.5) * depth
    elseif pick < 0.61 then
        x, y, z = (u - 0.5) * width * 0.68, height * 0.32, (v - 0.5) * depth
    else
        local a = swing * math.sin(phase * 0.95 + frame * math.pi)
        local length = math.max(height * 0.35, height - size * 0.85)
        local sa, ca = math.sin(a), math.cos(a)
        if pick < 0.78 then
            x, y, z = length * u * sa, height - length * u * ca, (v - 0.5) * depth * 0.12
        else
            -- A broad hanging hammer, kept rigid as its suspension rotates.
            local bx, by = (u - 0.5) * size, (v - 0.5) * size
            x = length * sa + bx * ca - by * sa
            y = height - length * ca + bx * sa + by * ca
            z = (w - 0.5) * size
        end
    end
    local target = cen + Vector3.new(x + frame * span * 0.34, y,
        z + travel * math.sin(phase * 0.31))
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Court Span", Min = 450, Max = 1600, Key = "k11", Default = 960 },
    { Type = "Slider", Name = "Frame Height", Min = 160, Max = 650, Key = "k12", Default = 340 },
    { Type = "Slider", Name = "Pendulum Speed", Min = 0, Max = 60, Key = "k13", Default = 22, ExactMax = true },
    { Type = "Slider", Name = "Hammer Size", Min = 40, Max = 180, Key = "k14", Default = 95 },
    { Type = "Slider", Name = "Swing Angle", Min = 15, Max = 80, Key = "k15", Default = 60 },
    { Type = "Slider", Name = "March Distance", Min = 0, Max = 600, Key = "k16", Default = 250 },
}

return M
