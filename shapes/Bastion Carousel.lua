-- Four fortified towers sweep out a giant rotating cross that traverses the map.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME, TAU = "Bastion Carousel", math.pi * 2

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 18, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local tower, id = (slot - 1) % 4, math.floor((slot - 1) / 4) + 1
    local pick = (id * 0.6180339887498949) % 1
    local u, v = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1
    local w = (id * 0.5497004779019703) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local reach = math.clamp(c.k11 or 350, 160, 600)
    local height = math.clamp(c.k12 or 260, 110, 480)
    local width = math.clamp(c.k14 or 145, 70, 260)
    local travel = math.clamp(c.k15 or 220, 0, 500)
    local lift = math.clamp(c.k16 or 45, 0, 120)
    local x, y, z
    if pick < 0.7 then
        local edge = math.floor(u * 4)
        local q = (u * 4) % 1
        if pick < 0.32 then q = id % 2 == 0 and 0 or 1 end
        if edge == 0 then x, z = -width * 0.5 + q * width, -width * 0.5
        elseif edge == 1 then x, z = width * 0.5, -width * 0.5 + q * width
        elseif edge == 2 then x, z = width * 0.5 - q * width, width * 0.5
        else x, z = -width * 0.5, width * 0.5 - q * width end
        if pick < 0.32 then
            y = height * v
        elseif pick < 0.55 then
            y = height * (0.9 + (math.floor(q * 5) % 2) * 0.1)
        else
            y = height * v
        end
        x = x + reach
        y = y + lift * (0.5 + 0.5 * math.sin(phase * 0.85 + tower * math.pi * 0.5))
    elseif pick < 0.94 then
        x, y, z = u * reach, 35 + (v - 0.5) * 35, (w - 0.5) * width * 0.35
    else
        local a, r = u * TAU, width * 0.48 * math.sqrt(v)
        x, y, z = r * math.cos(a), 35 + (w - 0.5) * 70, r * math.sin(a)
    end
    local a = tower * math.pi * 0.5 + phase * 0.34
    local ca, sa = math.cos(a), math.sin(a)
    local target = cen + Vector3.new(x * ca - z * sa + travel * math.sin(phase * 0.24), y,
        x * sa + z * ca + travel * 0.5 * math.sin(phase * 0.48))
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Arm Reach", Min = 160, Max = 600, Key = "k11", Default = 350 },
    { Type = "Slider", Name = "Tower Height", Min = 110, Max = 480, Key = "k12", Default = 260 },
    { Type = "Slider", Name = "Turn Speed", Min = 0, Max = 60, Key = "k13", Default = 18, ExactMax = true },
    { Type = "Slider", Name = "Tower Width", Min = 70, Max = 260, Key = "k14", Default = 145 },
    { Type = "Slider", Name = "March Distance", Min = 0, Max = 500, Key = "k15", Default = 220 },
    { Type = "Slider", Name = "Tower Lift", Min = 0, Max = 120, Key = "k16", Default = 45 },
}

return M
