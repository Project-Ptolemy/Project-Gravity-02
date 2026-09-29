-- An island-sized belt rolls over two drums while crossing the terrain.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME, TAU = "Continental Conveyor", math.pi * 2

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
    local span = math.clamp(c.k11 or 720, 350, 1200)
    local radius = math.clamp(c.k12 or 100, 50, 220)
    local width = math.clamp(c.k14 or 240, 100, 440)
    local travel = math.clamp(c.k15 or 230, 0, 550)
    local height = math.clamp(c.k16 or 110, 0, 350)
    local x, y, z
    if pick < 0.7 then
        -- A closed capsule has straight working runs and round drum returns.
        -- Distance, rather than angle, keeps debris evenly spaced on the belt.
        local perimeter = 2 * span + TAU * radius
        local run = ((u + phase * 0.12) % 1) * perimeter
        if run < span then
            x, y = -span * 0.5 + run, radius
        elseif run < span + math.pi * radius then
            local a = math.pi * 0.5 - (run - span) / radius
            x, y = span * 0.5 + radius * math.cos(a), radius * math.sin(a)
        elseif run < 2 * span + math.pi * radius then
            x, y = span * 1.5 + math.pi * radius - run, -radius
        else
            local a = -math.pi * 0.5 - (run - 2 * span - math.pi * radius) / radius
            x, y = -span * 0.5 + radius * math.cos(a), radius * math.sin(a)
        end
        z = (v - 0.5) * width
        y = y + (w - 0.5) * radius * 0.12
    elseif pick < 0.92 then
        -- Exposed spokes make both enormous drums readable inside the belt.
        local side = slot % 2 == 0 and 1 or -1
        local spoke = math.floor(slot / 2) % 6
        local a = spoke * TAU / 6 - phase * 0.12 * (2 * span + TAU * radius) / radius
        local r = radius * (0.15 + 0.79 * u)
        x, y, z = side * span * 0.5 + r * math.cos(a), r * math.sin(a), (v - 0.5) * width * 0.82
    else
        x, y, z = (u - 0.5) * span, (v - 0.5) * radius * 0.28, (w - 0.5) * width * 0.3
    end
    local yaw = 0.14 * math.sin(phase * 0.27)
    local cy, sy = math.cos(yaw), math.sin(yaw)
    local target = cen + Vector3.new(x * cy - z * sy, y + height,
        x * sy + z * cy + travel * math.sin(phase * 0.34))
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Belt Span", Min = 350, Max = 1200, Key = "k11", Default = 720 },
    { Type = "Slider", Name = "Drum Radius", Min = 50, Max = 220, Key = "k12", Default = 100 },
    { Type = "Slider", Name = "Drive Speed", Min = 0, Max = 60, Key = "k13", Default = 18, ExactMax = true },
    { Type = "Slider", Name = "Belt Width", Min = 100, Max = 440, Key = "k14", Default = 240 },
    { Type = "Slider", Name = "Crossing Distance", Min = 0, Max = 550, Key = "k15", Default = 230 },
    { Type = "Slider", Name = "Deck Height", Min = 0, Max = 350, Key = "k16", Default = 110 },
}

return M
