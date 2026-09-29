-- Five square scaffolds carry broad slanted blades through staggered drops.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Guillotine Array"

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 19, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local frame, id = (slot - 1) % 5 - 2, math.floor((slot - 1) / 5) + 1
    local pick = (id * 0.6180339887498949) % 1
    local u, v = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1
    local w = (id * 0.5497004779019703) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local span = math.clamp(c.k11 or 1000, 500, 1600)
    local height = math.clamp(c.k12 or 360, 180, 650)
    local stroke = math.min(math.clamp(c.k14 or 260, 60, 450), height * 0.72)
    local travel = math.clamp(c.k15 or 260, 0, 600)
    local depth = math.clamp(c.k16 or 90, 30, 200)
    local width = span * 0.16
    local x, y, z
    if pick < 0.54 then
        local perimeter = u * (2 * height + width)
        if perimeter < height then
            x, y = -width * 0.5, perimeter
        elseif perimeter < height + width then
            x, y = perimeter - height - width * 0.5, height
        else
            x, y = width * 0.5, 2 * height + width - perimeter
        end
        x, z = x + (v - 0.5) * width * 0.1, (w - 0.5) * depth
    elseif pick < 0.84 then
        local raised = (0.5 + 0.5 * math.sin(phase * 1.25 - frame * 1.3)) ^ 3
        x = (u - 0.5) * width * 0.86
        y = height * 0.065 + stroke * raised + height * (0.06 * u + 0.1 * v)
        z = (w - 0.5) * depth * 0.55
    else
        local side = id % 2 == 0 and 1 or -1
        x = side * width * 0.5 + (u - 0.5) * width * 0.25
        y, z = v * height * 0.035, (w - 0.5) * depth * 2.4
    end
    local target = cen + Vector3.new(x + frame * span * 0.205, y,
        z + frame * depth * 0.45 + travel * math.sin(phase * 0.32))
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Array Span", Min = 500, Max = 1600, Key = "k11", Default = 1000 },
    { Type = "Slider", Name = "Scaffold Height", Min = 180, Max = 650, Key = "k12", Default = 360 },
    { Type = "Slider", Name = "Drop Speed", Min = 0, Max = 60, Key = "k13", Default = 19, ExactMax = true },
    { Type = "Slider", Name = "Blade Travel", Min = 60, Max = 450, Key = "k14", Default = 260 },
    { Type = "Slider", Name = "Advance Distance", Min = 0, Max = 600, Key = "k15", Default = 260 },
    { Type = "Slider", Name = "Frame Depth", Min = 30, Max = 200, Key = "k16", Default = 90 },
}

return M
