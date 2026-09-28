local M = {}
M.ContinuousMotion = true
local NAME = "Storm Gyre"
local TAU = math.pi * 2
local PHI = 0.6180339887498949

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then
		st = { phase = 0, t = t }
		x6.pre[NAME] = st
	end
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 8, 0, 40) * x9.c2
	st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local id = d.slot or d.id or 1
	local pick = (id * PHI) % 1
	local u = (id * 0.8191725133961645) % 1
	local v = (id * 0.6710436067037893) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0

	local radius = math.clamp(c.k11 or 100, 35, 220)
	local height = math.clamp(c.k12 or 230, 80, 550)
	local funnels = math.clamp(math.floor(c.k14 or 3), 1, 6)
	local spread = math.clamp(c.k15 or 105, 0, 280)
	local lightning = math.clamp(c.k17 or 150, 30, 400)
	local size = p.Size
	if size and math.max(size.X, size.Y, size.Z) > radius * 0.22 and pick < 0.62 then pick = 0.62 + pick % 0.24 end
	local x, y, z
	if pick < 0.62 then
		local funnel = (id - 1) % funnels
		local localId = math.floor((id - 1) / funnels)
		local orbit = funnel * TAU / funnels + phase * 0.09
		local angle = localId % 3 * TAU / 3 + u * TAU * 3 - phase * 1.2
		local r = radius * (0.055 + 0.72 * u ^ 1.7)
		local separation = funnels == 1 and 0 or spread
		x = separation * math.cos(orbit) + r * math.cos(angle) + radius * 0.13 * u * u * math.sin(phase + funnel)
		z = separation * math.sin(orbit) + r * math.sin(angle)
		y = height * u
	elseif pick < 0.86 then
		local q = 2 * u - 1
		local ring = math.sqrt(math.max(0, 1 - q * q))
		local r = radius + (funnels == 1 and 0 or spread)
		x, z = r * ring * math.cos(v * TAU), r * ring * math.sin(v * TAU)
		y = height + radius * 0.26 * q
	else
		local bolt = (id - 1) % 7
		local angle = bolt * TAU / 7 + phase * 0.09
		-- Keep each bolt attached to the cloud while short, overlapping waves
		-- crackle along it. These continuous local bends are fast enough to read
		-- as lightning without rerolling a path or flinging debris between bolts.
		local pulse = phase * 32 + bolt * 2.399963229728653
		local envelope = math.sin(u * math.pi)
		local jag = radius * (0.1 * math.sin(u * 7 * math.pi + math.sin(pulse) * envelope)
			+ 0.055 * math.sin(u * 17 * math.pi - pulse * 1.37) * envelope)
		local fork = radius * 0.075 * envelope * math.sin(u * 11 * math.pi + pulse)
		local r = (radius + (funnels == 1 and 0 or spread)) * 0.85 + jag
		x = r * math.cos(angle) - fork * math.sin(angle)
		z = r * math.sin(angle) + fork * math.cos(angle)
		y = height - lightning * u
	end
	local target = cen + Vector3.new(x, y + math.clamp(c.k16 or 65, -100, 500), z)
	-- Compact by default for disaster-map rubble. Keep the height anchor fixed
	-- while scaling the silhouette, so wall panels help fill broad surfaces.
	local pivot = cen + Vector3.new(0, c.k16 or 65, 0)
	target = pivot + (target - pivot) * (math.clamp(c.k24 or 55, 25, 150) / 100)
	-- The runtime supplies this even at speed zero or Formation Time Scale zero.
	-- The same offset on every piece keeps the silhouette intact while it moves.
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Debris Scale %", Min = 25, Max = 150, Key = "k24", Default = 55, IntOnly = true,
		Desc = "Smaller formations stay denser with limited rubble. Increase for more or larger parts." },
	{ Type = "Slider", Name = "Funnel Radius", Min = 35, Max = 220, Key = "k11", Default = 100 },
	{ Type = "Slider", Name = "Storm Height", Min = 80, Max = 550, Key = "k12", Default = 230 },
	{ Type = "Slider", Name = "Storm Speed", Min = 0, Max = 40, Key = "k13", Default = 8, ExactMax = true },
	{ Type = "Slider", Name = "Twister Count", Min = 1, Max = 6, Key = "k14", Default = 3, IntOnly = true },
	{ Type = "Slider", Name = "Twister Separation", Min = 0, Max = 280, Key = "k15", Default = 105 },
	{ Type = "Slider", Name = "Hover Height", Min = -100, Max = 500, Key = "k16", Default = 65 },
	{ Type = "Slider", Name = "Lightning Reach", Min = 30, Max = 400, Key = "k17", Default = 150 },
}

return M
