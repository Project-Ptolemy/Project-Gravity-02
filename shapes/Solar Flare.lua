local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Solar Flare"
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
	local pick = (id * 0.6180339887498949) % 1
	local u, v, w = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1, (id * 0.5497004779019703) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local radius, arch = math.clamp(c.k11 or 320, 160, 480), math.clamp(c.k12 or 360, 140, 600)
	local extension = math.clamp(c.k14 or 185, 60, 350)
	local tongues = math.clamp(math.floor(c.k15 or 6), 3, 10)
	local a, r, y
	if pick < 0.55 then
		-- A broad half-sun remains filled beneath its erupting prominences.
		local latitude = math.asin(v)
		a = u * TAU + phase * 0.075
		r = radius * math.cos(latitude)
		y = radius * 0.82 * math.sin(latitude)
		local pulse = 1 + 0.025 * math.sin(phase * 0.17 + a * 4 + latitude * 3)
		r, y = r * pulse, y * pulse
	else
		local tongue = (id - 1) % tongues
		local flow = phase * 0.11 + tongue * TAU / tongues
		-- Each tongue is a broad arch rooted in the dome, not an orbiting ring.
		a = flow + 0.6 * u + (v - 0.5) * 0.14 * math.sin(math.pi * u)
		r = radius * (0.56 + 0.44 * u) + extension * math.sin(math.pi * u * 0.5)
		y = radius * 0.66 * (1 - u) + arch * math.sin(math.pi * u)
		y = y * (0.88 + 0.12 * math.sin(flow + phase * 0.07))
		y = y + (w - 0.5) * 28 * math.sin(math.pi * u)
	end
	local drift = phase * 0.045
	local center = Vector3.new(75 * math.sin(drift), c.k16 or 45, 75 * math.cos(drift * 0.79))
	local target = cen + center + Vector3.new(r * math.cos(a), y, r * math.sin(a))
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Solar Radius", Min = 160, Max = 480, Key = "k11", Default = 320 },
	{ Type = "Slider", Name = "Flare Height", Min = 140, Max = 600, Key = "k12", Default = 360 },
	{ Type = "Slider", Name = "Flare Speed", Min = 0, Max = 45, Key = "k13", Default = 11, ExactMax = true },
	{ Type = "Slider", Name = "Flare Extension", Min = 60, Max = 350, Key = "k14", Default = 185 },
	{ Type = "Slider", Name = "Flare Tongues", Min = 3, Max = 10, Key = "k15", Default = 6, IntOnly = true },
	{ Type = "Slider", Name = "Base Elevation", Min = -100, Max = 250, Key = "k16", Default = 45 },
}

return M
