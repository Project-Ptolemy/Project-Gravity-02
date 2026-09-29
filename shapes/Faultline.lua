local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Faultline"
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
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local slot = d.slot or d.id or 1
	local slabs = math.clamp(math.floor(c.k17 or 11), 5, 18)
	local slab = (slot - 1) % slabs
	local id = math.floor((slot - 1) / slabs) + 1
	local pick = (id * PHI) % 1
	local u = (id * 0.8191725133961645 + slab * 0.137) % 1
	local v = (id * 0.6710436067037893 + slab * 0.293) % 1
	local w = (id * 0.5497004779019703 + slab * 0.071) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local width = math.clamp(c.k11 or 480, 160, 900)
	local height = math.clamp(c.k12 or 140, 30, 320)
	local depth = math.clamp(c.k14 or 90, 20, 250)
	local reach = math.clamp(c.k15 or 210, 0, 500)
	local beat = phase - slab * 0.55
	local heave = (0.5 + 0.5 * math.sin(beat)) ^ 2
	local x = width * ((slab + u) / slabs - 0.5)
	local y, z
	if pick < 0.62 then
		-- Each slab has a jagged triangular crest; the uplift runs along the fault.
		local crest = 0.32 + 0.68 * (1 - math.abs(u * 2 - 1))
		y = height * (0.12 + heave * 0.88) * crest * (0.2 + v * 0.8)
		z = (w - 0.5) * depth * 0.24 + y * 0.2 * math.sin(beat - 0.5)
	elseif pick < 0.86 then
		local side = slot % 2 == 0 and 1 or -1
		y = height * (0.06 + heave * 0.25) * (1 - v)
		z = side * depth * (0.2 + v * 0.8)
	else
		-- Low outrunning fracture edges widen the footprint through the terrain.
		local side = slot % 2 == 0 and 1 or -1
		local sweep = 0.5 + 0.5 * math.sin(beat - 0.8)
		y = height * 0.045 * math.sin(v * math.pi) ^ 2
		z = side * depth * (0.7 + sweep * 1.4)
	end
	local travel = phase * 0.15
	local yaw = 0.4 * math.sin(travel * 0.63)
	local cy, sy = math.cos(yaw), math.sin(yaw)
	local center = Vector3.new(reach * 0.4 * math.sin(travel * 0.71), c.k16 or 0, reach * math.sin(travel))
	local target = cen + center + Vector3.new(x * cy - z * sy, y, x * sy + z * cy)
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Rupture Width", Min = 160, Max = 900, Key = "k11", Default = 480 },
	{ Type = "Slider", Name = "Slab Height", Min = 30, Max = 320, Key = "k12", Default = 140 },
	{ Type = "Slider", Name = "Rupture Speed", Min = 0, Max = 50, Key = "k13", Default = 12, ExactMax = true },
	{ Type = "Slider", Name = "Fracture Spread", Min = 20, Max = 250, Key = "k14", Default = 90 },
	{ Type = "Slider", Name = "Advance Area", Min = 0, Max = 500, Key = "k15", Default = 210 },
	{ Type = "Slider", Name = "Base Elevation", Min = -100, Max = 250, Key = "k16", Default = 0 },
	{ Type = "Slider", Name = "Rising Slabs", Min = 5, Max = 18, Key = "k17", Default = 11, IntOnly = true },
}

return M
