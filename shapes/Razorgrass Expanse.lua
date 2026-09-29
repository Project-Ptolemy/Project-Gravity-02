local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Razorgrass Expanse"
local TAU = math.pi * 2

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 12, 0, 45) * x9.c2
	st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local id = d.slot or d.id or 1
	local pick = (id * 0.6180339887498949) % 1
	local u, v = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local width, depth = math.clamp(c.k11 or 860, 400, 1150), math.clamp(c.k12 or 650, 300, 950)
	local height, sway = math.clamp(c.k14 or 250, 100, 430), math.clamp(c.k15 or 125, 35, 230)
	local row = (id - 1) % 7
	local column = math.floor((id - 1) / 7) % 6
	local wave = phase * 0.19 - row * 0.72 - column * 0.38
	local x, y, z
	if pick < 0.82 then
		-- Forty-two long curved blades form a field, with a traveling lean.
		local bend = u * u
		x = width * (column / 5 - 0.5) + sway * bend * math.sin(wave)
		z = depth * (row / 6 - 0.5) + sway * bend * (0.65 + 0.45 * math.cos(wave))
		y = height * u * (1 - 0.25 * u) * (0.83 + 0.17 * math.cos(wave))
		x = x + (v - 0.5) * 45 * math.sin(u * math.pi)
		z = z + height * 0.1 * math.sin(u * math.pi)
	else
		-- Low comb ridges make the repeated rows readable at modest part counts.
		x = width * (u - 0.5)
		z = depth * (row / 6 - 0.5) + 20 * math.sin(u * TAU + wave)
		y = 12 + 22 * math.sin(u * math.pi) ^ 2 * (1 + math.sin(phase * 0.19 - row * 0.72 - u * 2))
	end
	local travel = phase * 0.055
	local center = Vector3.new(130 * math.sin(travel), c.k16 or 15, 110 * math.sin(travel * 0.78))
	local target = cen + center + Vector3.new(x, y, z)
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Field Width", Min = 400, Max = 1150, Key = "k11", Default = 860 },
	{ Type = "Slider", Name = "Field Depth", Min = 300, Max = 950, Key = "k12", Default = 650 },
	{ Type = "Slider", Name = "Wave Speed", Min = 0, Max = 45, Key = "k13", Default = 12, ExactMax = true },
	{ Type = "Slider", Name = "Blade Height", Min = 100, Max = 430, Key = "k14", Default = 250 },
	{ Type = "Slider", Name = "Sweeping Lean", Min = 35, Max = 230, Key = "k15", Default = 125 },
	{ Type = "Slider", Name = "Base Elevation", Min = -100, Max = 250, Key = "k16", Default = 15 },
}

return M
