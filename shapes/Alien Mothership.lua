local M = {}
local NAME = "Alien Mothership"
local TAU = math.pi * 2
local PHI = 0.6180339887498949

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then
		st = { phase = 0, t = t }
		x6.pre[NAME] = st
	end
	st.phase = st.phase + (t - st.t) * math.max(0, c.k13 or 15) * x9.c2
	st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local id = d.slot or d.id or 1
	local lane = (id - 1) % 10
	local u = (id * 0.8191725133961645) % 1
	local v = (id * 0.6710436067037893) % 1
	local w = (id * 0.5497004779019703) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local radius = math.max(1, c.k11 or 120)
	local height = math.max(0, c.k12 or 40)
	local beam_length = math.max(0, c.k14 or 200)
	local x, y, z

	if lane < 6 then
		local r = radius * math.sqrt(u)
		local angle = v * TAU + phase
		x, z = r * math.cos(angle), r * math.sin(angle)
		y = math.sqrt(math.max(0, 1 - u * u)) * height * (lane % 2 == 0 and 1 or -1)
	elseif lane < 8 then
		-- Keep a filled column from the hull's underside to the beam's foot.
		-- Wrapping every piece from bottom to top made the velocity tracker chase
		-- a beam-length jump and left the entire column floating below the ship.
		-- The first beam piece anchors the emitter even with a small collection.
		local beam_id = math.floor((id - 1) / 10) * 2 + lane - 6
		local depth = (beam_id * PHI) % 1
		local flow = depth + 0.025 * math.sin(depth * math.pi)
			* math.sin(depth * TAU * 2 + phase * 4)
		local r = math.min(10, radius * 0.1) + flow * radius * 0.4
		local angle = v * TAU + phase * 3 - depth * TAU
		x, z = r * math.cos(angle), r * math.sin(angle)
		y = -height - flow * beam_length
	else
		local group = math.floor(u * 3)
		local orbit = phase * 0.5 + group * TAU / 3
		local angle = v * TAU + phase * 5
		local r = w * 10
		x = radius * 1.5 * math.cos(orbit) + r * math.cos(angle)
		z = radius * 1.5 * math.sin(orbit) + r * math.sin(angle)
		y = math.sin(phase * 2 + group) * 20 + (w - 0.5) * 5
	end

	local target = cen + Vector3.new(x, y, z)
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Radius", Min = 50, Max = 400, Key = "k11", Default = 120 },
	{ Type = "Slider", Name = "Core Height", Min = 10, Max = 150, Key = "k12", Default = 40 },
	{ Type = "Slider", Name = "Speed", Min = 0, Max = 100, Key = "k13", Div = 10, Default = 15 },
	{ Type = "Slider", Name = "Beam Length", Min = 50, Max = 500, Key = "k14", Default = 200 },
}

return M
