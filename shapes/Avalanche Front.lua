local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Avalanche Front"
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
	local u, v, w = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1, (id * 0.5497004779019703) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local width, run = math.clamp(c.k11 or 820, 400, 1100), math.clamp(c.k12 or 530, 250, 850)
	local rise, tumble = math.clamp(c.k14 or 340, 120, 550), math.clamp(c.k15 or 85, 25, 180)
	local lane = (id - 1) % 11
	local q = v * TAU + phase * 0.16 + lane * 0.11
	local down = (1 - math.cos(q)) * 0.5
	local behind = math.sin(q)
	-- Each lane descends the same vast incline, then climbs behind its face.
	-- The rounded ends join the falling slabs to their uphill return.
	local x = width * (lane / 10 - 0.5)
	local y = rise * (1 - down) + tumble * behind
	local z = run * (down - 0.5) - tumble * behind
	if (id * 0.6180339887498949) % 1 < 0.7 then
		x = x + width * 0.032 * (u - 0.5)
		y = y + 18 * math.sin(u * TAU + phase * 0.24)
	else
		-- Chunky tumbling bands sit across the slope rather than spraying away.
		local roll = phase * 0.55 + u * TAU
		x = x + tumble * 0.4 * math.cos(roll) * (0.4 + w)
		y = y + tumble * 0.4 * math.sin(roll)
		z = z + tumble * 0.24 * math.cos(roll * 2)
	end
	local advance = phase * 0.045
	local center = Vector3.new(90 * math.sin(advance * 0.6), c.k16 or 30, 180 * math.sin(advance))
	local target = cen + center + Vector3.new(x, y, z)
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Avalanche Width", Min = 400, Max = 1100, Key = "k11", Default = 820 },
	{ Type = "Slider", Name = "Slope Length", Min = 250, Max = 850, Key = "k12", Default = 530 },
	{ Type = "Slider", Name = "Descent Speed", Min = 0, Max = 45, Key = "k13", Default = 12, ExactMax = true },
	{ Type = "Slider", Name = "Slope Height", Min = 120, Max = 550, Key = "k14", Default = 340 },
	{ Type = "Slider", Name = "Tumbling Depth", Min = 25, Max = 180, Key = "k15", Default = 85 },
	{ Type = "Slider", Name = "Base Elevation", Min = -100, Max = 250, Key = "k16", Default = 30 },
}

return M
