local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Oblivion Drill"
local TAU = math.pi * 2
local PHI = 0.6180339887498949
local UP = Vector3.new(0, 1, 0)

local function flight(phase, c)
	local q = phase * 0.16
	local reach = math.clamp(c.k15 or 250, 0, 650)
	local dive = math.clamp(c.k17 or 65, 0, 220)
	local center = Vector3.new(reach * math.cos(q), (c.k16 or 95) + dive * math.sin(q * 0.73),
		reach * (math.sin(q) + 0.25 * math.sin(q * 0.61)))
	local dx, dy, dz = -reach * math.sin(q), dive * 0.73 * math.cos(q * 0.73), reach * (math.cos(q) + 0.1525 * math.cos(q * 0.61))
	local flat = math.sqrt(dx * dx + dz * dz)
	local heading = flat > 0.0001 and Vector3.new(dx / flat, 0, dz / flat) or Vector3.new(0, 0, 1)
	local pitch = math.atan2(dy, math.sqrt(flat * flat + dive * dive * 0.09 + 1))
	local forward = heading * math.cos(pitch) + UP * math.sin(pitch)
	local right = UP:Cross(heading)
	return { center = center, right = right, up = forward:Cross(right), forward = forward }
end

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then
		st = { phase = 0, t = t }
		x6.pre[NAME] = st
	end
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 20, 0, 70) * x9.c2
	st.t = t
	st.frame = flight(st.phase, c)
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local id = d.slot or d.id or 1
	local pick = (id * PHI) % 1
	local u, v = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local frame = st and st.frame or flight(phase, c)
	local radius = math.clamp(c.k11 or 105, 35, 240)
	local length = math.clamp(c.k12 or 380, 140, 700)
	local turns = math.clamp(math.floor(c.k14 or 3), 2, 6)
	local a, r, z
	if pick < 0.64 then
		-- Three broad continuous screw flights taper toward the boring tip.
		local start = (id - 1) % 3
		a = start * TAU / 3 + u * turns * TAU - phase * 1.4
		a = a + (v - 0.5) * 0.48 * math.sin(math.pi * u)
		r = radius * (0.05 + 0.95 * (1 - u) ^ 0.72)
		z = length * (u - 0.5)
	elseif pick < 0.84 then
		a = u * TAU - phase
		r = radius * (0.8 + v * 0.2)
		z = -length * (0.44 + 0.06 * v)
	else
		local tooth = (id - 1) % 5
		a = tooth * TAU / 5 - phase * 1.8 + u * 0.85
		r = radius * 0.57 * (1 - u)
		z = length * (0.2 + u * 0.34)
	end
	local target = cen + frame.center + frame.right * (r * math.cos(a)) + frame.up * (r * math.sin(a)) + frame.forward * z
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Drill Radius", Min = 35, Max = 240, Key = "k11", Default = 105 },
	{ Type = "Slider", Name = "Drill Length", Min = 140, Max = 700, Key = "k12", Default = 380 },
	{ Type = "Slider", Name = "Boring Speed", Min = 0, Max = 70, Key = "k13", Default = 20, ExactMax = true },
	{ Type = "Slider", Name = "Screw Turns", Min = 2, Max = 6, Key = "k14", Default = 3, IntOnly = true },
	{ Type = "Slider", Name = "Boring Area", Min = 0, Max = 650, Key = "k15", Default = 250 },
	{ Type = "Slider", Name = "Center Height", Min = -100, Max = 450, Key = "k16", Default = 95 },
	{ Type = "Slider", Name = "Dive Height", Min = 0, Max = 220, Key = "k17", Default = 65 },
}

return M
