-- Three long rail barrels on a broad advancing base feed continuous shot lanes.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Railstorm Battery"
local function smooth(u) return u * u * (3 - 2 * u) end

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 30, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local lane, id = (slot - 1) % 3 - 1, math.floor((slot - 1) / 3) + 1
    local pick = (id * 0.6180339887498949) % 1
    local u, v = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1
    local w = (id * 0.5497004779019703) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local length = math.clamp(c.k11 or 440, 220, 750)
    local width = math.clamp(c.k12 or 440, 200, 750)
    local range = math.clamp(c.k14 or 440, 150, 800)
    local travel = math.clamp(c.k15 or 230, 0, 550)
    local height = math.clamp(c.k16 or 120, 60, 260)
    local laneX = lane * width * 0.3
    local x, y, z
    if pick < 0.26 then
        x = laneX + (u - 0.5) * width * 0.34
        y, z = v * height * 0.32, (w - 0.5) * length * 1.12
    elseif pick < 0.65 then
        local edge, q = math.floor(u * 4), (u * 4) % 1
        local bore = width * 0.13
        if edge == 0 then x, y = (q - 0.5) * bore, -bore * 0.5
        elseif edge == 1 then x, y = bore * 0.5, (q - 0.5) * bore
        elseif edge == 2 then x, y = (0.5 - q) * bore, bore * 0.5
        else x, y = -bore * 0.5, (0.5 - q) * bore end
        x, y, z = x + laneX, y + height, (v - 0.5) * length
    else
        local q = (u + phase * 0.2 + lane * 0.19) % 1
        local breech, distance = -length * 0.5, length + range
        if q < 0.58 then
            local s = smooth(q / 0.58)
            x, y, z = laneX, height, breech + distance * s
        else
            -- The return arches to the outside and rejoins the breech smoothly.
            -- Both ends stop continuously, with no wrap from tip to source.
            local s = (q - 0.58) / 0.42
            local arc = math.sin(math.pi * s) ^ 2
            x = laneX + (lane == 0 and 1 or lane) * width * 0.17 * arc
            y, z = height + height * 0.8 * arc, breech + distance * (1 - smooth(s))
        end
        x, y = x + (v - 0.5) * width * 0.025, y + (w - 0.5) * height * 0.06
    end
    local target = cen + Vector3.new(x + travel * math.sin(phase * 0.27), y, z)
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Barrel Length", Min = 220, Max = 750, Key = "k11", Default = 440 },
    { Type = "Slider", Name = "Battery Width", Min = 200, Max = 750, Key = "k12", Default = 440 },
    { Type = "Slider", Name = "Firing Speed", Min = 0, Max = 60, Key = "k13", Default = 30, ExactMax = true },
    { Type = "Slider", Name = "Shot Reach", Min = 150, Max = 800, Key = "k14", Default = 440 },
    { Type = "Slider", Name = "Traverse Distance", Min = 0, Max = 550, Key = "k15", Default = 230 },
    { Type = "Slider", Name = "Barrel Height", Min = 60, Max = 260, Key = "k16", Default = 120 },
}

return M
