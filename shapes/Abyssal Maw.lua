-- A vast toothed mouth lunges ahead of a tapering, swimming armored body.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Abyssal Maw"
local TAU = math.pi * 2
local UP = Vector3.new(0, 1, 0)

local function flight(phase, c)
	local a = phase * 0.28
	local reach = math.clamp(c.k17 or 180, 0, 450)
	local dx, dz = reach * math.cos(a), reach * 0.8 * math.cos(a * 0.8 + 0.6)
	local flat = math.sqrt(dx * dx + dz * dz)
	local forward = flat > 0.001 and Vector3.new(dx / flat, 0, dz / flat) or Vector3.new(0, 0, 1)
	local right = UP:Cross(forward)
	local lunge = math.clamp(c.k11 or 135, 50, 230) * 0.38 * math.sin(phase * 1.5)
	return { pos = Vector3.new(reach * math.sin(a), math.clamp(c.k16 or 105, -100, 400) + 20 * math.sin(a * 1.2),
		reach * (math.sin(a * 0.8 + 0.6) - math.sin(0.6))) + forward * lunge, right = right, forward = forward }
end

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 26, 0, 65) * x9.c2
	st.t = t
	st.flight = flight(st.phase, c)
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local id = d.slot or d.id or 1
	local pick = (id * 0.6180339887498949) % 1
	local u, v, w = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1, (id * 0.5497004779019703) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local frame = st and st.flight or flight(phase, c)
	local radius, length = math.clamp(c.k11 or 135, 50, 230), math.clamp(c.k12 or 380, 140, 650)
	local fangs = math.clamp(c.k14 or 65, 15, 130)
	local bite = math.clamp(c.k15 or 80, 0, 95) / 100
	local opening = 1 - bite * (0.5 + 0.5 * math.sin(phase * 1.5 - 0.65)) ^ 2
	local x, y, z
	if pick < 0.26 then
		local a = u * TAU
		local r = radius * (1 + 0.09 * math.cos(v * TAU))
		x, y, z = r * math.cos(a), r * math.sin(a) * opening, radius * 0.38 + radius * 0.09 * math.sin(v * TAU)
	elseif pick < 0.51 then
		-- Two offset rings of chunky tapered fangs point into the opening.
		local tooth = (id - 1) % 18
		local a = tooth * TAU / 18
		local r = radius - fangs * u
		local width = radius * 0.042 * (1 - u) * (2 * v - 1)
		x = r * math.cos(a) - width * math.sin(a)
		y = (radius * opening - fangs * u) * math.sin(a) + width * math.cos(a)
		z = radius * (0.39 + 0.12 * (w - 0.5)) + fangs * u * 0.35
	elseif pick < 0.94 then
		local r = radius * (0.14 + 0.86 * (1 - u) ^ 0.65)
		local a = v * TAU
		local squeeze = 1 - (1 - opening) * (1 - u) ^ 4
		x, y, z = r * math.cos(a), r * math.sin(a) * squeeze, radius * 0.3 - length * u
		local bend = u * u
		x = x + radius * 0.42 * bend * math.sin(phase * 1.6 - u * 4)
		y = y + radius * 0.18 * bend * math.cos(phase * 1.6 - u * 4)
	else
		local side = id % 2 == 0 and 1 or -1
		x = side * radius * (0.28 + 0.8 * u)
		y = radius * (0.08 + 0.07 * math.sin(phase * 1.6 - u * 2))
		z = -length * (0.52 + 0.4 * u + 0.12 * v * (1 - u))
	end
	local target = cen + frame.pos + frame.right * x + UP * y + frame.forward * z
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Mouth Radius", Min = 50, Max = 230, Key = "k11", Default = 135 },
	{ Type = "Slider", Name = "Body Length", Min = 140, Max = 650, Key = "k12", Default = 380 },
	{ Type = "Slider", Name = "Lunge Speed", Min = 0, Max = 65, Key = "k13", Default = 26, ExactMax = true },
	{ Type = "Slider", Name = "Fang Length", Min = 15, Max = 130, Key = "k14", Default = 65 },
	{ Type = "Slider", Name = "Chomp Depth %", Min = 0, Max = 95, Key = "k15", Default = 80 },
	{ Type = "Slider", Name = "Attack Height", Min = -100, Max = 400, Key = "k16", Default = 105 },
	{ Type = "Slider", Name = "Hunting Reach", Min = 0, Max = 450, Key = "k17", Default = 180 },
}

return M
