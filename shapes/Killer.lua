-- Staggered rubble volleys dive through the core, then bow out for another pass.
local M = { ContinuousMotion = true, AlwaysProcess = true, FrameTracking = true }
local NAME = "Killer"
local TAU = math.pi * 2
local PHI = 0.6180339887498949
local ATTACK = 0.24
local PASS = 1.18
local TURN = 0.13

local function smooth(s) return s * s * (3 - 2 * s) end

function M.px(t, c, x6, x9, x1)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then
        st = { phase = 0, t = t }
        x6.pre[NAME] = st
    end
    local speed = math.clamp(c.k13 or 36, 0, 80) * x9.c2
    -- Frame tracking keeps narrow strikes from becoming bucketed zigzags.
    -- Bound the whole closed trajectory's derivative, reserving speed for
    -- moving anchors. Raising global Max Speed permits faster attack passes.
    local reach = math.clamp(c.k11 or 240, 80, 450)
    local spread = math.clamp(c.k14 or 18, 1, 60)
    local reload = math.clamp(c.k15 or 150, 30, 300)
    local height = math.clamp(c.k16 or 100, 0, 300)
    local extent = math.sqrt(reach * reach + height * height)
    local attack = PASS * 1.5 / ATTACK * (extent + spread * 1.2)
    local recovery = PASS * 1.5 / (1 - ATTACK) * (extent + spread * 1.2)
        + math.pi / (1 - ATTACK) * math.sqrt(reload * reload + height * height * 0.65 * 0.65)
    local derivative = math.max(attack, recovery) * 2 / TAU + TURN * (reach + reload + spread * 2)
    local scale = math.abs(x1 and x1.TimeScale or 1)
    local limit = x1 and x1.MaxSpeed or 500
    if limit > 0 and scale > 0 then
        speed = math.min(speed, limit * 0.85 / derivative / scale)
    end
    st.phase = st.phase + (t - st.t) * speed
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local streams = math.clamp(math.floor(c.k12 or 8), 3, 18)
    local lane = (slot - 1) % streams
    local id = math.floor((slot - 1) / streams) + 1
    local u = (id * PHI + lane * 0.1771243444677046) % 1
    local v = (id * 0.8191725133961645 + lane * 0.4142135623730951) % 1
    local w = (id * 0.6710436067037893 + lane * 0.7320508075688772) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local reach = math.clamp(c.k11 or 240, 80, 450)
    local spread = math.clamp(c.k14 or 18, 1, 60)
    local reload = math.clamp(c.k15 or 150, 30, 300)
    local height = math.clamp(c.k16 or 100, 0, 300)
    local aim = math.clamp(c.k17 or 8, -100, 250)
    local angle = lane * TAU / streams + phase * TURN
    local ca, sa = math.cos(angle), math.sin(angle)
    local top = height * (0.4 + 0.6 * ((lane * PHI + 0.5) % 1))
    local q = (u + phase * 2 / TAU) % 1
    local along, bow
    if q < ATTACK then
        -- A narrow straight dive passes through the core instead of stopping
        -- at it. Smooth endpoint speed joins the reload without a teleport.
        along = 1 - PASS * smooth(q / ATTACK)
        bow = 0
    else
        local r = (q - ATTACK) / (1 - ATTACK)
        along = 1 - PASS + PASS * smooth(r)
        bow = math.sin(math.pi * r) ^ 2
    end
    local width = spread * (0.18 + 0.82 * along * along)
    local tangent = reload * bow + (v - 0.5) * width
    local radial = reach * along
    local target = cen + Vector3.new(radial * ca - tangent * sa,
        aim + top * along + height * 0.65 * bow + (w - 0.5) * width,
        radial * sa + tangent * ca)
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Strike Reach", Min = 80, Max = 450, Key = "k11", Default = 240 },
    { Type = "Slider", Name = "Strike Streams", Min = 3, Max = 18, Key = "k12", Default = 8, IntOnly = true },
    { Type = "Slider", Name = "Attack Speed", Min = 0, Max = 80, Key = "k13", Default = 36, ExactMax = true,
        Desc = "Fast core passes with curved reloads. Global Max Speed bounds the motion; raise it to allow faster volleys." },
    { Type = "Slider", Name = "Volley Spread", Min = 1, Max = 60, Key = "k14", Default = 18 },
    { Type = "Slider", Name = "Reload Sweep", Min = 30, Max = 300, Key = "k15", Default = 150 },
    { Type = "Slider", Name = "Dive Height", Min = 0, Max = 300, Key = "k16", Default = 100 },
    { Type = "Slider", Name = "Aim Height", Min = -100, Max = 250, Key = "k17", Default = 8 },
}

return M
