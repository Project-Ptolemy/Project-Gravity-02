-- Nine jagged points rise from a thick crown that expands, sweeps and slams.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME, TAU = "Crown of Ruin", math.pi * 2

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 22, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local pick = (slot * 0.6180339887498949) % 1
    local u, v = (slot * 0.8191725133961645) % 1, (slot * 0.6710436067037893) % 1
    local w = (slot * 0.5497004779019703) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local radius = math.clamp(c.k11 or 370, 170, 650)
    local height = math.clamp(c.k12 or 220, 90, 420)
    local expansion = math.clamp(c.k14 or 25, 0, 55) / 100
    local lift = math.clamp(c.k15 or 170, 0, 350)
    local travel = math.clamp(c.k16 or 260, 0, 600)
    local tooth = 1 - math.abs(2 * ((u * 9) % 1) - 1)
    local y, r
    if pick < 0.55 then
        -- Linear slopes, rather than sine lobes, form unmistakably sharp teeth.
        y = height * (0.34 + 0.66 * tooth) + (v - 0.5) * height * 0.035
        r = radius * (1 + 0.13 * tooth + (w - 0.5) * 0.09)
    elseif pick < 0.82 then
        y = height * 0.34 * v
        r = radius * (0.96 + (w - 0.5) * 0.13)
    else
        local corner = (slot % 9 + 0.5) / 9
        u = corner
        y = height * v
        r = radius * (0.96 + 0.17 * v + (w - 0.5) * 0.1)
    end
    r = r * (1 + expansion * math.sin(phase * 0.75))
    local a = u * TAU + phase * 0.34
    local slam = lift * (0.5 + 0.5 * math.sin(phase * 1.1)) ^ 4
    local x, z = r * math.cos(a), r * math.sin(a)
    local target = cen + Vector3.new(x + travel * math.sin(phase * 0.27), y + slam,
        z + travel * 0.38 * math.sin(phase * 0.54))
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Crown Radius", Min = 170, Max = 650, Key = "k11", Default = 370 },
    { Type = "Slider", Name = "Spike Height", Min = 90, Max = 420, Key = "k12", Default = 220 },
    { Type = "Slider", Name = "Ruin Speed", Min = 0, Max = 60, Key = "k13", Default = 22, ExactMax = true },
    { Type = "Slider", Name = "Expansion %", Min = 0, Max = 55, Key = "k14", Default = 25, IntOnly = true },
    { Type = "Slider", Name = "Slam Height", Min = 0, Max = 350, Key = "k15", Default = 170 },
    { Type = "Slider", Name = "Sweep Distance", Min = 0, Max = 600, Key = "k16", Default = 260 },
}

return M
