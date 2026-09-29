local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Polar Rift"
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
	local u, v, w = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1, (id * 0.5497004779019703) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local height, width = math.clamp(c.k11 or 650, 300, 900), math.clamp(c.k12 or 760, 400, 1100)
	local opening, teeth = math.clamp(c.k14 or 160, 60, 280), math.clamp(c.k15 or 70, 25, 130)
	local level = u
	local x, y, z
	if pick < 0.73 then
		if pick > 0.35 then level = (math.floor((id - 1) / 2) % 11) / 10 end
		local zipper = 0.5 + 0.5 * math.sin(phase * 0.14 - level * TAU)
		local tooth = 1 - math.abs(((level * 9) % 1) * 2 - 1)
		local inner = 35 + opening * zipper + teeth * (1 - tooth)
		local thickness = pick < 0.35 and 0 or v
		x = side * (inner + (width * 0.5 - inner) * thickness)
		y = height * level + side * 27 * math.sin(phase * 0.13)
		z = 42 * math.sin(level * math.pi * 3) + (w - 0.5) * 55
	else
		-- Straight branching bridges stitch the jaws across the moving opening.
		level = ((id - 1) % 9 + 0.5) / 9
		local zipper = 0.5 + 0.5 * math.sin(phase * 0.14 - level * TAU)
		local tooth = 1 - math.abs(((level * 9) % 1) * 2 - 1)
		local inner = 35 + opening * zipper + teeth * (1 - tooth)
		x = (u * 2 - 1) * inner
		y = height * level + 26 * math.sin(u * 7 * math.pi + phase * 0.3) * math.sin(u * math.pi)
		z = 42 * math.sin(level * math.pi * 3) + 32 * math.sin(u * 5 * math.pi + phase * 0.26)
	end
	local travel = phase * 0.055
	local center = Vector3.new(120 * math.sin(travel), c.k16 or 20, 160 * math.sin(travel * 0.7))
	local target = cen + center + Vector3.new(x, y, z)
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Fissure Height", Min = 300, Max = 900, Key = "k11", Default = 650 },
	{ Type = "Slider", Name = "Jaw Span", Min = 400, Max = 1100, Key = "k12", Default = 760 },
	{ Type = "Slider", Name = "Unzipping Speed", Min = 0, Max = 40, Key = "k13", Default = 10, ExactMax = true },
	{ Type = "Slider", Name = "Opening Width", Min = 60, Max = 280, Key = "k14", Default = 160 },
	{ Type = "Slider", Name = "Serration Depth", Min = 25, Max = 130, Key = "k15", Default = 70 },
	{ Type = "Slider", Name = "Base Elevation", Min = -100, Max = 250, Key = "k16", Default = 20 },
}

return M
