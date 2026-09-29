-- One enormous upright wheel rolls across the ground on a thick debris tread.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME, TAU = "Worldbreaker Wheel", math.pi * 2

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 18, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local pick = (slot * 0.6180339887498949) % 1
    local u, v = (slot * 0.8191725133961645) % 1, (slot * 0.6710436067037893) % 1
    local w = (slot * 0.5497004779019703) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local radius = math.clamp(c.k11 or 330, 150, 600)
    local width = math.clamp(c.k12 or 180, 70, 360)
    local travel = math.clamp(c.k14 or 520, 100, 1000)
    local spokes = math.floor(math.clamp(c.k15 or 8, 4, 12) + 0.5)
    local crossing = travel * math.sin(phase * 0.48)
    -- Rotation is distance / radius, so the wheel actually rolls with its travel.
    local rotation = -crossing / radius
    local a, r, z
    if pick < 0.52 then
        a = u * TAU
        r = radius * (0.94 + 0.06 * v)
        z = (w - 0.5) * width
    elseif pick < 0.88 then
        a = (slot % spokes) * TAU / spokes + (w - 0.5) * 0.07
        r = radius * (0.13 + 0.82 * u)
        z = (v - 0.5) * width * 0.62
    else
        a, r, z = u * TAU, radius * 0.16 * math.sqrt(v), (w - 0.5) * width * 1.2
    end
    a = a + rotation
    local target = cen + Vector3.new(crossing + r * math.cos(a), radius + r * math.sin(a), z)
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Wheel Radius", Min = 150, Max = 600, Key = "k11", Default = 330 },
    { Type = "Slider", Name = "Tread Width", Min = 70, Max = 360, Key = "k12", Default = 180 },
    { Type = "Slider", Name = "Rolling Speed", Min = 0, Max = 60, Key = "k13", Default = 18, ExactMax = true },
    { Type = "Slider", Name = "Rolling Distance", Min = 100, Max = 1000, Key = "k14", Default = 520 },
    { Type = "Slider", Name = "Spoke Count", Min = 4, Max = 12, Key = "k15", Default = 8, IntOnly = true },
}

return M
