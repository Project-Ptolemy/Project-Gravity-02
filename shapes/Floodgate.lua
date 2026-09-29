local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Floodgate"
local TAU = math.pi * 2

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 10, 0, 40) * x9.c2
	st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local id = d.slot or d.id or 1
	local pick = (id * 0.6180339887498949) % 1
	local u, v, w = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1, (id * 0.5497004779019703) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local width, height = math.clamp(c.k11 or 800, 400, 1100), math.clamp(c.k12 or 330, 150, 550)
	local reach, surge = math.clamp(c.k14 or 540, 200, 800), math.clamp(c.k15 or 80, 20, 180)
	local x, y, z
	if pick < 0.44 then
		-- Four piers and two heavy lintels make exactly three open spillways.
		local member = (id - 1) % 6
		if member < 4 then
			x, y = width * (member / 3 - 0.5), height * u
			x = x + 23 * math.cos(v * TAU)
			z = 30 * math.sin(v * TAU)
		else
			x, y, z = width * (u - 0.5), (member == 4 and height or 0), (v - 0.5) * 65
			y = y + 18 * math.sin(v * TAU)
		end
	else
		local gate = (id - 1) % 3
		local q = phase * 0.18 + u * TAU + gate * 0.65
		local outward = (1 - math.cos(q)) * 0.5
		x = width * ((gate + 0.5) / 3 - 0.5) + width * 0.13 * (v * 2 - 1)
		z = reach * outward
		-- The outgoing torrent and returning undercurrent meet smoothly.
		y = height * 0.42 * (1 - outward) + surge * math.sin(q) * (0.7 + 0.3 * w)
		x = x + 22 * math.sin(q * 2 + v * TAU) * outward
	end
	local travel = phase * 0.065
	local center = Vector3.new(105 * math.sin(travel), c.k16 or 30, 75 * math.sin(travel * 0.8))
	local target = cen + center + Vector3.new(x, y, z - reach * 0.35)
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Dam Width", Min = 400, Max = 1100, Key = "k11", Default = 800 },
	{ Type = "Slider", Name = "Dam Height", Min = 150, Max = 550, Key = "k12", Default = 330 },
	{ Type = "Slider", Name = "Flood Speed", Min = 0, Max = 40, Key = "k13", Default = 10, ExactMax = true },
	{ Type = "Slider", Name = "Spillway Reach", Min = 200, Max = 800, Key = "k14", Default = 540 },
	{ Type = "Slider", Name = "Surge Height", Min = 20, Max = 180, Key = "k15", Default = 80 },
	{ Type = "Slider", Name = "Base Elevation", Min = -100, Max = 250, Key = "k16", Default = 30 },
}

return M
