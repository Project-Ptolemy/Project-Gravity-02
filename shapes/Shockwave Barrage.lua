local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Shockwave Barrage"
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
	local u, v = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local reach, height = math.clamp(c.k11 or 460, 220, 650), math.clamp(c.k12 or 90, 25, 200)
	local fronts = math.clamp(math.floor(c.k14 or 3), 2, 6)
	local sides = math.clamp(math.floor(c.k15 or 8), 5, 12)
	local front = (id - 1) % fronts
	local q = phase * 0.145 + front * TAU / fronts
	local expansion = 0.5 + 0.5 * math.sin(q)
	local radius = reach * (0.18 + 0.82 * expansion)
	local a, r, y
	if pick < 0.6 then
		-- Flat polygon edges form broad advancing ground fronts.
		local edge = math.floor((id - 1) / fronts) % sides
		local a0, a1 = edge * TAU / sides, (edge + 1) * TAU / sides
		local ex = (1 - u) * math.cos(a0) + u * math.cos(a1)
		local ez = (1 - u) * math.sin(a0) + u * math.sin(a1)
		a, r = math.atan2(ez, ex), radius * math.sqrt(ex * ex + ez * ez)
		r = r + (v - 0.5) * 24
		y = height * (0.22 + 0.38 * expansion) + 12 * math.sin(u * math.pi)
	else
		local spoke = math.floor((id - 1) / fronts) % sides
		a = spoke * TAU / sides
		r = radius * (0.14 + 0.86 * u)
		-- Raised radial ridges connect the pulse center to every corner.
		y = height * math.sin(u * math.pi) * (0.4 + 0.6 * expansion)
		y = y + height * 0.16 * math.sin(phase * 0.32 - u * TAU) * math.sin(u * math.pi)
	end
	local travel = phase * 0.065
	local center = Vector3.new(110 * math.sin(travel), c.k16 or 15, 90 * math.sin(travel * 0.73))
	local target = cen + center + Vector3.new(r * math.cos(a), y, r * math.sin(a))
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Blast Radius", Min = 220, Max = 650, Key = "k11", Default = 460 },
	{ Type = "Slider", Name = "Ridge Height", Min = 25, Max = 200, Key = "k12", Default = 90 },
	{ Type = "Slider", Name = "Pulse Speed", Min = 0, Max = 40, Key = "k13", Default = 10, ExactMax = true },
	{ Type = "Slider", Name = "Wave Fronts", Min = 2, Max = 6, Key = "k14", Default = 3, IntOnly = true },
	{ Type = "Slider", Name = "Polygon Corners", Min = 5, Max = 12, Key = "k15", Default = 8, IntOnly = true },
	{ Type = "Slider", Name = "Base Elevation", Min = -100, Max = 250, Key = "k16", Default = 15 },
}

return M
