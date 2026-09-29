local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Sandstorm Wall"
local TAU = math.pi * 2

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 11, 0, 45) * x9.c2
	st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local id = d.slot or d.id or 1
	local u, v, w = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1, (id * 0.5497004779019703) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local width, height = math.clamp(c.k11 or 940, 400, 1200), math.clamp(c.k12 or 440, 180, 700)
	local roll, reach = math.clamp(c.k14 or 115, 30, 220), math.clamp(c.k15 or 210, 40, 400)
	local q = v * TAU + phase * 0.21
	local x = width * (u - 0.5)
	if (id * 0.6180339887498949) % 1 > 0.72 then
		-- Seven horizontal stream bands reinforce one continuous wind curtain.
		q = ((id - 1) % 7) * TAU / 7 + phase * 0.21 + u * 0.5
	end
	local y = height * (0.5 + 0.5 * math.sin(q))
	local z = roll * math.cos(q) + width * 0.09 * math.cos(u * TAU * 0.75)
	x = x + 35 * math.sin(q + u * TAU) * math.sin(u * math.pi)
	z = z + 18 * math.sin(phase * 0.37 + u * TAU * 3) * math.sin(q) + (w - 0.5) * 12
	local advance = phase * 0.055
	local center = Vector3.new(75 * math.sin(advance * 0.7), c.k16 or 15, reach * math.sin(advance))
	local target = cen + center + Vector3.new(x, y, z)
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Curtain Width", Min = 400, Max = 1200, Key = "k11", Default = 940 },
	{ Type = "Slider", Name = "Curtain Height", Min = 180, Max = 700, Key = "k12", Default = 440 },
	{ Type = "Slider", Name = "Wind Speed", Min = 0, Max = 45, Key = "k13", Default = 11, ExactMax = true },
	{ Type = "Slider", Name = "Rolling Depth", Min = 30, Max = 220, Key = "k14", Default = 115 },
	{ Type = "Slider", Name = "Advance Reach", Min = 40, Max = 400, Key = "k15", Default = 210 },
	{ Type = "Slider", Name = "Base Elevation", Min = -100, Max = 250, Key = "k16", Default = 15 },
}

return M
