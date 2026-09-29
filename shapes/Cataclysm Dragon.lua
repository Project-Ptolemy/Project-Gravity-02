-- A wide bat-winged hunter: the entire dragon charges through a banking path.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Cataclysm Dragon"
local TAU = math.pi * 2
local UP = Vector3.new(0, 1, 0)

local function flight(phase, c)
	local a = phase * 0.34
	local reach = math.clamp(c.k16 or 190, 0, 450)
	local dive = math.clamp(c.k17 or 65, 0, 180)
	local dx, dz = reach * math.cos(a), reach * 0.83 * math.cos(a * 0.83 + 0.4)
	local flat = math.sqrt(dx * dx + dz * dz)
	local heading = flat > 0.001 and Vector3.new(dx / flat, 0, dz / flat) or Vector3.new(0, 0, 1)
	local pitch = math.atan2(dive * 0.72 * math.cos(a * 0.72), math.sqrt(flat * flat + dive * dive * 0.2 + 1))
	local forward = heading * math.cos(pitch) + UP * math.sin(pitch)
	local right = UP:Cross(heading)
	local up = forward:Cross(right)
	local bank = math.sin(a * 0.83) * 0.4
	right, up = right * math.cos(bank) + up * math.sin(bank), up * math.cos(bank) - right * math.sin(bank)
	local pos = Vector3.new(reach * math.sin(a), math.clamp(c.k15 or 125, -100, 500) + dive * math.sin(a * 0.72),
		reach * (math.sin(a * 0.83 + 0.4) - math.sin(0.4)))
	return { pos = pos, right = right, up = up, forward = forward }
end

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 20, 0, 60) * x9.c2
	st.t = t
	st.flight = flight(st.phase, c)
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local id = d.slot or d.id or 1
	local pick = (id * 0.6180339887498949) % 1
	local u, v, w = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1, (id * 0.5497004779019703) % 1
	local side = id % 2 == 0 and 1 or -1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local frame = st and st.flight or flight(phase, c)
	local length, span = math.clamp(c.k11 or 420, 160, 700), math.clamp(c.k12 or 230, 80, 380)
	local x, y, z
	if pick < 0.48 then
		-- Two broad triangular webs share the elbow. The outer web folds after
		-- the root, leaving unmistakable bat wings rather than thin pinwheels.
		local a, b = math.sqrt(u), v * math.sqrt(u)
		if w < 0.52 then
			x = span * (0.12 * (1 - a) + 0.48 * (a - b) + b)
			z = length * (0.08 * (1 - a) + 0.23 * (a - b) + 0.02 * b)
		else
			x = span * (0.12 * (1 - a) + (a - b) + 0.5 * b)
			z = length * (0.08 * (1 - a) + 0.02 * (a - b) - 0.19 * b)
		end
		local angle = math.rad(math.clamp(c.k14 or 36, 0, 70)) * math.sin(phase * 1.7 - x / span * 0.75)
		y = length * 0.045 + x * math.sin(angle) + (w - 0.5) * length * 0.018
		x = side * x * math.cos(angle)
	elseif pick < 0.77 then
		z = length * (0.34 - 0.94 * u)
		local girth = length * (0.065 * (1 - u) + 0.008) * (0.7 + 0.3 * math.sin(math.pi * u))
		x, y = girth * math.cos(v * TAU), girth * math.sin(v * TAU)
	elseif pick < 0.88 then
		if w < 0.7 then
			-- A blunt armored head and an opening lower jaw, ahead of the neck.
			local jaw = v < 0.5 and -1 or 1
			x = (u * 2 - 1) * length * 0.055
			y = length * (0.025 + jaw * (0.025 + 0.03 * (0.5 + 0.5 * math.sin(phase * 1.2))))
			z = length * (0.31 + w * 0.23)
		else
			x = side * length * (0.045 + 0.045 * u)
			y, z = length * (0.07 + 0.12 * u), length * (0.33 - 0.14 * u)
		end
	elseif pick < 0.96 then
		local fore = math.floor((id - 1) / 2) % 2 == 0
		local step = phase * 1.7 + (fore and 0 or math.pi)
		x = side * length * (0.045 + 0.1 * u)
		y = -length * (0.035 + 0.13 * u) + length * 0.025 * u * math.sin(step)
		z = length * ((fore and 0.13 or -0.2) - 0.065 * u + 0.035 * u * math.cos(step))
	else
		-- Large dorsal spines survive a modest rubble budget.
		local spine = math.floor((id - 1) / 2) % 7
		x = (v - 0.5) * length * 0.015 * (1 - u)
		y = length * (0.055 + 0.1 * u)
		z = length * (0.2 - spine * 0.09 - 0.06 * u)
	end
	local aft = math.clamp((length * 0.25 - z) / length, 0, 1)
	x = x + length * 0.13 * aft * aft * math.sin(phase * 1.7 - aft * 5)
	y = y + length * 0.045 * aft * math.sin(phase * 1.7 - aft * 4)
	local target = cen + frame.pos + frame.right * x + frame.up * y + frame.forward * z
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Body Length", Min = 160, Max = 700, Key = "k11", Default = 420 },
	{ Type = "Slider", Name = "Wing Reach", Min = 80, Max = 380, Key = "k12", Default = 230 },
	{ Type = "Slider", Name = "Charge Speed", Min = 0, Max = 60, Key = "k13", Default = 20, ExactMax = true },
	{ Type = "Slider", Name = "Wingbeat Angle", Min = 0, Max = 70, Key = "k14", Default = 36 },
	{ Type = "Slider", Name = "Flight Height", Min = -100, Max = 500, Key = "k15", Default = 125 },
	{ Type = "Slider", Name = "Hunting Reach", Min = 0, Max = 450, Key = "k16", Default = 190 },
	{ Type = "Slider", Name = "Dive Depth", Min = 0, Max = 180, Key = "k17", Default = 65 },
}

return M
