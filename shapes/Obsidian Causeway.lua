-- A long arched bridge strides ahead on shifting piers and heaving deck slabs.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Obsidian Causeway"

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 16, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local section, id = (slot - 1) % 9 - 4, math.floor((slot - 1) / 9) + 1
    local pick = (id * 0.6180339887498949) % 1
    local u, v = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1
    local w = (id * 0.5497004779019703) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local length = math.clamp(c.k11 or 1000, 450, 1700)
    local height = math.clamp(c.k12 or 180, 60, 350)
    local width = math.clamp(c.k14 or 200, 80, 400)
    local lift = math.clamp(c.k15 or 40, 0, 100)
    local travel = math.clamp(c.k16 or 270, 0, 650)
    local sx = section * length / 9
    local deck = 50 + height * (1 - (section / 4.5) ^ 2)
    local heave = lift * math.sin(phase * 1.15 - section * 0.75)
    local x, y, z
    if pick < 0.58 then
        x = sx + (u - 0.5) * length / 9 * 0.93
        y = deck + heave + (w - 0.5) * 16
        if id % 3 == 0 then
            -- Raised deck edges make the bridge silhouette clear at a distance.
            y, z = y + v * 24, (id % 2 == 0 and 1 or -1) * width * 0.5
        else
            z = (v - 0.5) * width
        end
    elseif pick < 0.78 then
        x = sx + (u - 0.5) * length / 9
        y = 28 + height * 0.86 * (1 - (2 * x / length) ^ 2)
            + lift * 0.3 * math.sin(phase * 1.15 - 6.75 * x / length)
        z = (id % 2 == 0 and 1 or -1) * width * 0.45 + (w - 0.5) * 12
    else
        -- Each supporting pier steps beneath its own rising deck section.
        x = sx + (w - 0.5) * length * 0.032 + lift * 0.55 * math.sin(phase * 1.15 - section * 0.75) * (1 - u)
        y = u * (deck + heave)
        z = (id % 2 == 0 and 1 or -1) * width * 0.4 + (v - 0.5) * width * 0.12
    end
    local target = cen + Vector3.new(x, y, z + travel * math.sin(phase * 0.36))
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Bridge Length", Min = 450, Max = 1700, Key = "k11", Default = 1000 },
    { Type = "Slider", Name = "Arch Height", Min = 60, Max = 350, Key = "k12", Default = 180 },
    { Type = "Slider", Name = "Advance Speed", Min = 0, Max = 60, Key = "k13", Default = 16, ExactMax = true },
    { Type = "Slider", Name = "Bridge Width", Min = 80, Max = 400, Key = "k14", Default = 200 },
    { Type = "Slider", Name = "Segment Lift", Min = 0, Max = 100, Key = "k15", Default = 40 },
    { Type = "Slider", Name = "March Distance", Min = 0, Max = 650, Key = "k16", Default = 270 },
}

return M
