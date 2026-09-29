local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Continental Shelf"
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
	local side = id % 2 == 0 and 1 or -1
	local pick = (id * 0.6180339887498949) % 1
	local u, v = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local width, depth = math.clamp(c.k11 or 350, 180, 520), math.clamp(c.k12 or 560, 250, 850)
	local heave, slide = math.clamp(c.k14 or 115, 30, 240), math.clamp(c.k15 or 105, 20, 240)
	local stroke = phase * 0.24
	local lift = heave * (0.5 + 0.5 * math.sin(stroke + side * 0.8))
	local gap = 10 + 45 * math.cos(stroke)
	local a, z, y = u, depth * (v - 0.5), 0
	if pick < 0.55 then
		-- Broad wedge tops are traced by seven long transverse strata.
		z = depth * (((math.floor((id - 1) / 2) % 7) / 6) - 0.5)
		y = lift * (1 - a) + 24 * math.sin(a * math.pi)
	elseif pick < 0.82 then
		-- The outer rectangle and inner cliff keep both plates legible.
		local edge = math.floor((id - 1) / 2) % 4
		if edge < 2 then a = edge; z = depth * (u - 0.5)
		else z = (edge == 2 and -0.5 or 0.5) * depth end
		y = lift * (1 - a) - 38 * v
	else
		a = u * 0.16
		z = depth * (v - 0.5)
		y = lift * (1 - a) + heave * 0.6 * math.sin(v * math.pi) * math.sin(stroke * 1.7 + u * TAU)
	end
	local x = side * (gap + width * a)
	z = z + side * slide * math.sin(stroke + side * 0.7)
	y = y + side * width * a * 0.08 * math.sin(stroke)
	local center = Vector3.new(70 * math.sin(stroke * 0.67), c.k16 or 35, 110 * math.sin(stroke * 0.81))
	local target = cen + center + Vector3.new(x, y, z)
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Plate Reach", Min = 180, Max = 520, Key = "k11", Default = 350 },
	{ Type = "Slider", Name = "Fault Length", Min = 250, Max = 850, Key = "k12", Default = 560 },
	{ Type = "Slider", Name = "Tectonic Speed", Min = 0, Max = 40, Key = "k13", Default = 10, ExactMax = true },
	{ Type = "Slider", Name = "Collision Heave", Min = 30, Max = 240, Key = "k14", Default = 115 },
	{ Type = "Slider", Name = "Lateral Slide", Min = 20, Max = 240, Key = "k15", Default = 105 },
	{ Type = "Slider", Name = "Base Elevation", Min = -100, Max = 250, Key = "k16", Default = 35 },
}

return M
