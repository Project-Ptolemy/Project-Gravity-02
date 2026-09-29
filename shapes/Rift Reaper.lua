local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Rift Reaper"
local TAU = math.pi * 2
local PHI = 0.6180339887498949

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then
		st = { phase = 0, t = t }
		x6.pre[NAME] = st
	end
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 12, 0, 50) * x9.c2
	st.t = t
	local q = st.phase * 0.18
	local reach = math.clamp(c.k15 or 220, 0, 600)
	st.center = Vector3.new(reach * math.cos(q), c.k16 or 135, reach * (0.85 * math.sin(q) + 0.25 * math.sin(q * 0.43)))
	-- The portal tunnel faces its route, so the cutting arcs advance across the map.
	local dx, dz = -math.sin(q), 0.85 * math.cos(q) + 0.1075 * math.cos(q * 0.43)
	local length = math.sqrt(dx * dx + dz * dz)
	st.forward = Vector3.new(dx / length, 0, dz / length)
	st.right = Vector3.new(dz / length, 0, -dx / length)
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local slot = d.slot or d.id or 1
	local side = slot % 2 == 0 and 1 or -1
	local id = math.floor((slot - 1) / 2) + 1
	local pick = (id * PHI) % 1
	local u, v = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local radius = math.clamp(c.k11 or 100, 35, 250)
	local depth = math.clamp(c.k12 or 240, 80, 550)
	local cutting = math.clamp(c.k14 or 210, 80, 400)
	local blades = math.clamp(math.floor(c.k17 or 6), 3, 12)
	local a, r, z
	if pick < 0.34 then
		-- Both mouths retain full outer rims even when the scythes cross the core.
		a = u * TAU + side * phase * 0.35
		r = radius * (1 + 0.04 * math.cos(v * TAU))
		z = side * depth * 0.5 + radius * 0.035 * math.sin(v * TAU)
	elseif pick < 0.58 then
		local blade = (id - 1) % blades
		a = blade * TAU / blades + side * phase * 0.5 + (1 - u) * 0.8
		r = radius * (0.46 + 0.55 * u)
		a = a + (v - 0.5) * TAU / blades * 0.35 * math.sin(math.pi * u)
		z = side * (depth * 0.5 + radius * 0.1 * math.sin(math.pi * u))
	elseif pick < 0.87 then
		-- Long crescent edges cut through, beyond, and back across both mouths.
		local blade = (id - 1) % blades
		local stroke = phase * 0.85 + blade * TAU / blades
		a = blade * TAU / blades - phase + side * (1 - u) * 1.4
		r = cutting * (0.12 + 0.88 * u)
		a = a + (v - 0.5) * 0.15 * math.sin(math.pi * u)
		z = depth * 0.7 * math.sin(stroke) + side * radius * 0.2 * math.sin(math.pi * u)
	else
		a = side * phase + u * TAU * 2.5
		r = radius * (0.34 + 0.26 * math.sin(math.pi * u))
		z = depth * (u - 0.5)
	end
	local center = st and st.center or Vector3.new(math.clamp(c.k15 or 220, 0, 600), c.k16 or 135, 0)
	local forward = st and st.forward or Vector3.new(0, 0, 1)
	local right = st and st.right or Vector3.new(1, 0, 0)
	local target = cen + center + right * (r * math.cos(a)) + Vector3.new(0, r * math.sin(a), 0) + forward * z
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Portal Radius", Min = 35, Max = 250, Key = "k11", Default = 100 },
	{ Type = "Slider", Name = "Portal Separation", Min = 80, Max = 550, Key = "k12", Default = 240 },
	{ Type = "Slider", Name = "Reaping Speed", Min = 0, Max = 50, Key = "k13", Default = 12, ExactMax = true },
	{ Type = "Slider", Name = "Scythe Reach", Min = 80, Max = 400, Key = "k14", Default = 210 },
	{ Type = "Slider", Name = "Sweep Area", Min = 0, Max = 600, Key = "k15", Default = 220 },
	{ Type = "Slider", Name = "Center Height", Min = -100, Max = 450, Key = "k16", Default = 135 },
	{ Type = "Slider", Name = "Scythe Blades", Min = 3, Max = 12, Key = "k17", Default = 6, IntOnly = true },
}

return M
