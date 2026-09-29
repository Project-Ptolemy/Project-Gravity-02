-- Nine linked wall panels fold into a marching screen across the island.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Iron Procession"

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 18, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local panel, id = (slot - 1) % 9, math.floor((slot - 1) / 9) + 1
    local pick = (id * 0.6180339887498949) % 1
    local u, v = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1
    local w = (id * 0.5497004779019703) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local span = math.clamp(c.k11 or 1080, 500, 1800)
    local height = math.clamp(c.k12 or 290, 120, 550)
    local fold = math.rad(math.clamp(c.k14 or 38, 0, 65))
    local thickness = math.clamp(c.k15 or 48, 15, 120)
    local travel = math.clamp(c.k16 or 300, 0, 650)
    local width = span / 9
    local angles, totalX, totalZ = {}, 0, 0
    -- Integrating the nine hinge directions keeps adjacent panel edges joined.
    for i = 0, 8 do
        angles[i] = fold * math.sin(phase * 0.65 - i * 0.85) + (i % 2 == 0 and 1 or -1) * fold * 0.32
        totalX = totalX + width * math.cos(angles[i])
        totalZ = totalZ + width * math.sin(angles[i])
    end
    local x, z = -totalX * 0.5, -totalZ * 0.5
    for i = 0, panel - 1 do
        x = x + width * math.cos(angles[i])
        z = z + width * math.sin(angles[i])
    end
    local across, y
    if pick < 0.4 then
        -- Tall edge posts and broad top rails survive low debris counts.
        across, y = id % 2 == 0 and 0 or 1, u * height
    elseif pick < 0.68 then
        across, y = u, height * (id % 2 == 0 and 1 or 0.07)
    else
        across, y = u, v * height
    end
    local a = angles[panel]
    x = x + across * width * math.cos(a) - (w - 0.5) * thickness * math.sin(a)
    z = z + across * width * math.sin(a) + (w - 0.5) * thickness * math.cos(a)
    -- Feet lift in a traveling cadence while the articulated screen advances.
    y = y + height * 0.055 * (0.5 + 0.5 * math.sin(phase * 1.4 - panel * 0.8)) ^ 3
    local target = cen + Vector3.new(x, y, z + travel * math.sin(phase * 0.35))
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Wall Length", Min = 500, Max = 1800, Key = "k11", Default = 1080 },
    { Type = "Slider", Name = "Panel Height", Min = 120, Max = 550, Key = "k12", Default = 290 },
    { Type = "Slider", Name = "March Speed", Min = 0, Max = 60, Key = "k13", Default = 18, ExactMax = true },
    { Type = "Slider", Name = "Folding Angle", Min = 0, Max = 65, Key = "k14", Default = 38 },
    { Type = "Slider", Name = "Wall Thickness", Min = 15, Max = 120, Key = "k15", Default = 48 },
    { Type = "Slider", Name = "Advance Distance", Min = 0, Max = 650, Key = "k16", Default = 300 },
}

return M
