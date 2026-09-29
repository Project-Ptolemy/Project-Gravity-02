-- A heavy moving hull drives three battering prows through a rolling wake.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Dreadnought"
local TAU = math.pi * 2
local UP = Vector3.new(0, 1, 0)

local function voyage(phase, c)
	local a = phase * 0.29
	local reach = math.clamp(c.k16 or 170, 0, 420)
	local dx, dz = reach * math.cos(a), reach * 0.72 * math.cos(a * 0.72 + 0.5)
	local flat = math.sqrt(dx * dx + dz * dz)
	local forward = flat > 0.001 and Vector3.new(dx / flat, 0, dz / flat) or Vector3.new(0, 0, 1)
	local right = UP:Cross(forward)
	local roll = math.sin(phase * 0.8) * 0.065
	return {
		pos = Vector3.new(reach * math.sin(a), math.clamp(c.k15 or 55, -100, 350) + 8 * math.sin(phase * 1.2),
			reach * (math.sin(a * 0.72 + 0.5) - math.sin(0.5))),
		right = right * math.cos(roll) + UP * math.sin(roll),
		up = UP * math.cos(roll) - right * math.sin(roll), forward = forward,
	}
end

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 18, 0, 55) * x9.c2
	st.t = t
	st.frame = voyage(st.phase, c)
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local id = d.slot or d.id or 1
	local pick = (id * 0.6180339887498949) % 1
	local u, v, w = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1, (id * 0.5497004779019703) % 1
	local side = id % 2 == 0 and 1 or -1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local frame = st and st.frame or voyage(phase, c)
	local length, beam = math.clamp(c.k11 or 420, 180, 700), math.clamp(c.k12 or 180, 80, 320)
	local ram, wake = math.clamp(c.k14 or 110, 30, 220), math.clamp(c.k17 or 150, 40, 280)
	local x, y, z
	if pick < 0.5 then
		z = length * (u - 0.5)
		-- Broad deck and slab sides narrow into a distinct armored prow.
		local width = beam * 0.5 * (1 - 0.8 * math.max(0, (u - 0.65) / 0.35))
		if w < 0.56 then
			x, y = (v * 2 - 1) * width, beam * (w < 0.44 and 0.1 or -0.27)
		else
			x, y = side * width * (0.83 + 0.17 * v), beam * (-0.27 + 0.37 * v)
		end
	elseif pick < 0.7 then
		-- Stepped fortification on the deck, dense enough for large wall panels.
		local tier = (id - 1) % 3
		local width = beam * (0.32 - tier * 0.065)
		local depth = length * (0.3 - tier * 0.06)
		if w < 0.58 then
			x, y, z = (2 * u - 1) * width, beam * (0.24 + tier * 0.16), (2 * v - 1) * depth - length * 0.06
		else
			x, y, z = side * width, beam * (0.1 + tier * 0.16 + 0.14 * u), (2 * v - 1) * depth - length * 0.06
		end
	elseif pick < 0.87 then
		local prow = (id - 1) % 3 - 1
		local strike = 0.5 + 0.5 * math.sin(phase * 2.2 - math.abs(prow) * 0.7)
		local extension = ram * (0.55 + 0.45 * strike)
		x = prow * beam * 0.29 + (v - 0.5) * beam * 0.24 * (1 - u)
		y = beam * (-0.05 + (w - 0.5) * 0.2 * (1 - u))
		z = length * (0.36 - 0.05 * math.abs(prow)) + extension * u
	else
		-- Each wake part remains on one continuous rolling arc; no recycling
		-- or modulo travel can teleport a panel from the stern to the bow.
		local row = math.floor((id - 1) / 2) % 4
		local angle = u * TAU + phase * 1.5 - row * 0.75
		local radius = wake * (0.17 + row * 0.055)
		x = side * (beam * 0.48 + row * wake * 0.11 + radius * 0.45 * math.cos(angle))
		y = -beam * 0.16 + radius * math.sin(angle)
		z = -length * (0.24 + row * 0.095) + radius * math.cos(angle) + (v - 0.5) * wake * 0.075
	end
	local target = cen + frame.pos + frame.right * x + frame.up * y + frame.forward * z
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Hull Length", Min = 180, Max = 700, Key = "k11", Default = 420 },
	{ Type = "Slider", Name = "Hull Width", Min = 80, Max = 320, Key = "k12", Default = 180 },
	{ Type = "Slider", Name = "Ram Speed", Min = 0, Max = 55, Key = "k13", Default = 18, ExactMax = true },
	{ Type = "Slider", Name = "Ram Reach", Min = 30, Max = 220, Key = "k14", Default = 110 },
	{ Type = "Slider", Name = "Deck Height", Min = -100, Max = 350, Key = "k15", Default = 55 },
	{ Type = "Slider", Name = "Patrol Reach", Min = 0, Max = 420, Key = "k16", Default = 170 },
	{ Type = "Slider", Name = "Wake Reach", Min = 40, Max = 280, Key = "k17", Default = 150 },
}

return M
