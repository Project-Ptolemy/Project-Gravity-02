local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Thunderhead Armada"
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
	local span, height = math.clamp(c.k11 or 940, 450, 1250), math.clamp(c.k12 or 470, 220, 750)
	local drop, reach = math.clamp(c.k14 or 390, 120, 650), math.clamp(c.k15 or 155, 30, 350)
	local cloud = (id - 1) % 3
	local cloudX = (cloud - 1) * span * 0.31
	local cloudZ = math.sin(cloud * 2.1 + phase * 0.032) * span * 0.09
	local x, y, z
	if pick < 0.6 then
		-- Three flat anvil caps have wide crowns and pinched lower decks.
		local deck = math.floor((id - 1) / 3) % 3
		local a = u * TAU + phase * 0.065
		local r = deck == 2 and math.sqrt(v) or (0.88 + 0.12 * v)
		local scale = deck == 0 and 0.73 or 1
		x = cloudX + span * 0.205 * r * scale * math.cos(a)
		z = cloudZ + span * 0.14 * r * scale * math.sin(a)
		y = height + (deck == 0 and -45 or 25) + 10 * math.sin(a * 5 + phase * 0.08)
	else
		local bolt = math.floor((id - 1) / 3) % 3
		local branch = math.floor((id - 1) / 9) % 3 - 1
		local root = (bolt - 1) * span * 0.092
		local fork = math.max(0, u - 0.42) / 0.58
		local flicker = phase * 0.27 + bolt * 1.8 + cloud
		x = cloudX + root + 23 * math.sin(u * 9 * math.pi + flicker) * math.sin(u * math.pi)
		x = x + branch * span * 0.075 * fork
		y = height - 45 - drop * u
		z = cloudZ + (w - 0.5) * 15 + 28 * math.sin(u * 7 * math.pi + flicker * 0.8)
		z = z + branch * span * 0.035 * fork
	end
	local travel = phase * 0.06
	local center = Vector3.new(reach * math.sin(travel), c.k16 or 0, reach * 0.85 * math.sin(travel * 0.71))
	local target = cen + center + Vector3.new(x, y, z)
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Cloudbank Span", Min = 450, Max = 1250, Key = "k11", Default = 940 },
	{ Type = "Slider", Name = "Cloud Altitude", Min = 220, Max = 750, Key = "k12", Default = 470 },
	{ Type = "Slider", Name = "Storm Speed", Min = 0, Max = 40, Key = "k13", Default = 10, ExactMax = true },
	{ Type = "Slider", Name = "Lightning Drop", Min = 120, Max = 650, Key = "k14", Default = 390 },
	{ Type = "Slider", Name = "Migration Reach", Min = 30, Max = 350, Key = "k15", Default = 155 },
	{ Type = "Slider", Name = "Base Elevation", Min = -100, Max = 250, Key = "k16", Default = 0 },
}

return M
