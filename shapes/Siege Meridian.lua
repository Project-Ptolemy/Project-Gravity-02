-- A monumental arch advances with five independently plunging battering stakes.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Siege Meridian"

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 20, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local pick = (slot * 0.6180339887498949) % 1
    local u, v = (slot * 0.8191725133961645) % 1, (slot * 0.6710436067037893) % 1
    local w = (slot * 0.5497004779019703) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local span = math.clamp(c.k11 or 900, 400, 1500)
    local height = math.clamp(c.k12 or 410, 180, 700)
    local depth = math.clamp(c.k14 or 110, 40, 260)
    local strike = math.clamp(c.k15 or 280, 60, 500)
    local travel = math.clamp(c.k16 or 280, 0, 600)
    local x, y, z
    if pick < 0.42 then
        local a = math.pi * u
        x = math.cos(a) * (span * 0.5 + (v - 0.5) * span * 0.065)
        y = height * (0.48 + math.sin(a) * 0.52) + (v - 0.5) * height * 0.045
        z = (w - 0.5) * depth
    elseif pick < 0.62 then
        local side = slot % 2 == 0 and 1 or -1
        x, y, z = side * span * 0.5 + (v - 0.5) * span * 0.06, u * height * 0.48, (w - 0.5) * depth
    elseif pick < 0.94 then
        local stake = slot % 5 - 2
        local anchorX = stake * span * 0.16
        local anchorY = height * (0.48 + 0.52 * math.sqrt(1 - (anchorX / (span * 0.5)) ^ 2))
        local reach = math.min(strike, anchorY * 0.83)
        local plunge = (0.5 + 0.5 * math.sin(phase * 1.2 - stake * 1.25)) ^ 3
        local endY = anchorY - height * 0.2 - reach * plunge
        if v < 0.3 then
            x, y, z = anchorX, endY + u * (anchorY - endY), (w - 0.5) * depth * 0.12
        else
            -- Heavy, broad stakes remain attached to the high arch by tethers.
            x = anchorX + (u - 0.5) * span * 0.055
            y = endY + (v - 0.3) / 0.7 * height * 0.18
            z = (w - 0.5) * depth * 0.65 + depth * 0.25 * math.sin(phase - stake)
        end
    else
        local side = slot % 2 == 0 and 1 or -1
        x, y, z = side * span * 0.5 + (u - 0.5) * span * 0.14, v * height * 0.045, (w - 0.5) * depth * 2.5
    end
    local target = cen + Vector3.new(x + span * 0.055 * math.sin(phase * 0.23), y,
        z + travel * math.sin(phase * 0.38))
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Arch Span", Min = 400, Max = 1500, Key = "k11", Default = 900 },
    { Type = "Slider", Name = "Arch Height", Min = 180, Max = 700, Key = "k12", Default = 410 },
    { Type = "Slider", Name = "Siege Speed", Min = 0, Max = 60, Key = "k13", Default = 20, ExactMax = true },
    { Type = "Slider", Name = "Arch Depth", Min = 40, Max = 260, Key = "k14", Default = 110 },
    { Type = "Slider", Name = "Strike Reach", Min = 60, Max = 500, Key = "k15", Default = 280 },
    { Type = "Slider", Name = "Advance Distance", Min = 0, Max = 600, Key = "k16", Default = 280 },
}

return M
