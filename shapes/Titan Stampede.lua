-- Three massive horned beasts charge together with articulated running legs.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Titan Stampede"
local TAU = math.pi * 2
local UP = Vector3.new(0, 1, 0)

local function charge(phase, c)
	local a = phase * 0.31
	local reach = math.clamp(c.k16 or 210, 0, 450)
	local dx, dz = reach * math.cos(a), reach * 0.78 * math.cos(a * 0.78 + 0.45)
	local flat = math.sqrt(dx * dx + dz * dz)
	local forward = flat > 0.001 and Vector3.new(dx / flat, 0, dz / flat) or Vector3.new(0, 0, 1)
	return { pos = Vector3.new(reach * math.sin(a), math.clamp(c.k15 or 90, -100, 350),
		reach * (math.sin(a * 0.78 + 0.45) - math.sin(0.45))), right = UP:Cross(forward), forward = forward }
end

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 26, 0, 65) * x9.c2
	st.t = t
	st.frame = charge(st.phase, c)
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local slot = d.slot or d.id or 1
	local beast = (slot - 1) % 3 - 1
	-- Anatomy uses the local index so all three beasts retain both sides and
	-- all four legs when parts are claimed in order or the rubble count changes.
	local id = math.floor((slot - 1) / 3) + 1
	local pick = (id * 0.6180339887498949) % 1
	local u, v, w = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1, (id * 0.5497004779019703) % 1
	local side = id % 2 == 0 and 1 or -1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local frame = st and st.frame or charge(phase, c)
	local scale, spread = math.clamp(c.k11 or 110, 45, 200), math.clamp(c.k12 or 165, 80, 320)
	local horn, stride = math.clamp(c.k14 or 85, 25, 160), math.clamp(c.k17 or 60, 0, 130)
	local gait = phase * 2.5 + beast * 0.7
	local bob = scale * 0.045 * math.cos(gait * 2)
	local x, y, z
	if pick < 0.39 then
		local q = 2 * u - 1
		local ring = math.sqrt(math.max(0, 1 - q * q))
		x, y, z = scale * 0.35 * ring * math.cos(v * TAU), scale * 0.37 * ring * math.sin(v * TAU) + bob, scale * 0.79 * q
	elseif pick < 0.73 then
		local leg = (id - 1) % 4
		local front = leg < 2
		local legSide = leg % 2 == 0 and -1 or 1
		local beat = gait + ((leg == 0 or leg == 3) and 0 or math.pi)
		local baseZ = (front and 0.5 or -0.51) * scale
		local footZ = baseZ + stride * math.cos(beat)
		local footY = -scale * 0.81 + scale * 0.3 * math.max(0, math.sin(beat))
		local kneeZ = baseZ + stride * 0.35 * math.cos(beat) + (front and 1 or -1) * scale * 0.12
		local kneeY = -scale * 0.46 + bob * 0.5
		if u < 0.5 then
			local f = u * 2
			x = legSide * scale * (0.26 + 0.08 * f)
			y, z = (-scale * 0.1 + bob) * (1 - f) + kneeY * f, baseZ * (1 - f) + kneeZ * f
		else
			local f = (u - 0.5) * 2
			x = legSide * scale * (0.34 + 0.04 * f)
			y, z = kneeY * (1 - f) + footY * f, kneeZ * (1 - f) + footZ * f
		end
		x = x + scale * 0.065 * math.cos(v * TAU)
		z = z + scale * 0.065 * math.sin(v * TAU)
	elseif pick < 0.87 then
		-- Heavy blunt head points into the charge, below the shoulder hump.
		local q = 2 * u - 1
		local ring = math.sqrt(math.max(0, 1 - q * q))
		x = scale * 0.32 * ring * math.cos(v * TAU)
		y = scale * (-0.08 + 0.25 * ring * math.sin(v * TAU)) + bob
		z = scale * (0.83 + q * 0.31)
	elseif pick < 0.98 then
		x = side * (scale * 0.23 + horn * 0.47 * math.sin(u * math.pi * 0.7))
		y = scale * 0.09 + horn * (0.1 * u + 0.64 * u * u) + bob
		z = scale * 0.87 + horn * (0.15 * u + 0.65 * u * u)
		x = x + (v - 0.5) * scale * 0.07 * (1 - u)
	else
		x = scale * 0.15 * u * math.sin(gait - u * 3)
		y, z = -scale * 0.18 * u + bob, -scale * (0.72 + 0.53 * u)
	end
	x = x + beast * spread
	z = z - math.abs(beast) * scale * 0.42 + scale * 0.055 * math.sin(gait)
	local target = cen + frame.pos + frame.right * x + UP * y + frame.forward * z
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Beast Scale", Min = 45, Max = 200, Key = "k11", Default = 110 },
	{ Type = "Slider", Name = "Herd Spread", Min = 80, Max = 320, Key = "k12", Default = 165 },
	{ Type = "Slider", Name = "Stampede Speed", Min = 0, Max = 65, Key = "k13", Default = 26, ExactMax = true },
	{ Type = "Slider", Name = "Horn Reach", Min = 25, Max = 160, Key = "k14", Default = 85 },
	{ Type = "Slider", Name = "Ground Height", Min = -100, Max = 350, Key = "k15", Default = 90 },
	{ Type = "Slider", Name = "Charge Reach", Min = 0, Max = 450, Key = "k16", Default = 210 },
	{ Type = "Slider", Name = "Stride Reach", Min = 0, Max = 130, Key = "k17", Default = 60 },
}

return M
