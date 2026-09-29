-- An open ribbed bowl is fed by four long chutes beneath three sweeping forge arms.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Starforge Crucible"
local TAU = math.pi * 2
local PHI = 0.6180339887498949

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 20, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local u, v = (slot * PHI) % 1, (slot * 0.8191725133961645) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local bowl = math.clamp(c.k11 or 325, 170, 520)
    local depth = math.clamp(c.k12 or 180, 70, 320)
    local reach = math.clamp(c.k14 or 520, 300, 850)
    local clearance = math.clamp(c.k15 or 110, 25, 240)
    local chuteWidth = math.clamp(c.k16 or 24, 5, 65)
    local base = math.clamp(c.k17 or 20, -100, 250)
    local group = slot % 20
    local x, y, z
    if group < 8 then
        local rib = math.floor((slot - 1) / 20) % 12
        local q = (1 - math.cos(u * TAU + phase * 0.52)) * 0.5
        local r = bowl * (0.22 + 0.78 * q)
        local a = rib * TAU / 12 + phase * 0.07
        x, z = r * math.cos(a), r * math.sin(a)
        y = depth * q * q
    elseif group < 11 then
        local inner = group == 10
        local a = u * TAU + phase * (inner and -0.4 or 0.12)
        local r = bowl * (inner and 0.23 or 1) + (v - 0.5) * 10
        x, z = r * math.cos(a), r * math.sin(a)
        y = inner and 0 or depth
    elseif group < 16 then
        local chute = math.floor((slot - 1) / 20) % 4
        local a = chute * TAU / 4 + math.sin(phase * 0.25) * 0.15
        -- Closed out-and-back feed paths: the high leg carries debris inward,
        -- the low leg returns it along the underside of the same chute.
        local flow = u * TAU + phase * 0.85
        local q = (1 - math.cos(flow)) * 0.5
        local r = bowl * 0.3 + q * (math.max(reach, bowl * 1.2) - bowl * 0.3)
        local across = (v - 0.5) * chuteWidth
        x, z = r * math.cos(a) - across * math.sin(a), r * math.sin(a) + across * math.cos(a)
        y = depth * q * 0.65 + chuteWidth * 0.45 * math.sin(flow)
    else
        local arm = math.floor((slot - 1) / 20) % 3
        local a = arm * TAU / 3 - phase * 0.38
        local q = (1 - math.cos(u * TAU + phase * 0.55)) * 0.5
        local r = bowl * 0.14 + q * (reach - bowl * 0.14)
        local across = (v - 0.5) * chuteWidth * (1.8 - q)
        x, z = r * math.cos(a) - across * math.sin(a), r * math.sin(a) + across * math.cos(a)
        y = depth + clearance + clearance * 0.22 * math.sin(q * math.pi + phase + arm)
    end
    local target = cen + Vector3.new(x, y + base, z)
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Crucible Radius", Min = 170, Max = 520, Key = "k11", Default = 325 },
    { Type = "Slider", Name = "Bowl Depth", Min = 70, Max = 320, Key = "k12", Default = 180 },
    { Type = "Slider", Name = "Forge Motion", Min = 0, Max = 60, Key = "k13", Default = 20, ExactMax = true },
    { Type = "Slider", Name = "Feed And Arm Reach", Min = 300, Max = 850, Key = "k14", Default = 520 },
    { Type = "Slider", Name = "Forge Arm Lift", Min = 25, Max = 240, Key = "k15", Default = 110 },
    { Type = "Slider", Name = "Feed Width", Min = 5, Max = 65, Key = "k16", Default = 24 },
    { Type = "Slider", Name = "Bowl Height", Min = -100, Max = 250, Key = "k17", Default = 20 },
}

return M
