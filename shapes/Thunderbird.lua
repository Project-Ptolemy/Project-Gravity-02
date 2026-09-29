-- An angular storm bird with hammering wingbeats and long lightning streamers.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Thunderbird"
local TAU = math.pi * 2
local UP = Vector3.new(0, 1, 0)

local function flight(phase, c)
	local a = phase * 0.31
	local reach = math.clamp(c.k16 or 210, 0, 450)
	local dive = math.clamp(c.k17 or 85, 0, 200)
	local dx, dz = reach * math.cos(a), reach * 0.95 * math.cos(a * 0.95 + 0.8)
	local flat = math.sqrt(dx * dx + dz * dz)
	local heading = flat > 0.001 and Vector3.new(dx / flat, 0, dz / flat) or Vector3.new(0, 0, 1)
	local pitch = math.atan2(-dive * 1.4 * math.sin(a * 1.4), math.sqrt(flat * flat + dive * dive * 0.3 + 1))
	local forward = heading * math.cos(pitch) + UP * math.sin(pitch)
	local right = UP:Cross(heading)
	local up = forward:Cross(right)
	local bank = math.sin(a + 0.6) * 0.5
	right, up = right * math.cos(bank) + up * math.sin(bank), up * math.cos(bank) - right * math.sin(bank)
	return { pos = Vector3.new(reach * math.sin(a), math.clamp(c.k15 or 145, -100, 500) + dive * math.cos(a * 1.4),
		reach * (math.sin(a * 0.95 + 0.8) - math.sin(0.8))), right = right, up = up, forward = forward }
end

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 24, 0, 60) * x9.c2
	st.t = t
	st.flight = flight(st.phase, c)
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local id = d.slot or d.id or 1
	local pick = (id * 0.6180339887498949) % 1
	local u, v, w = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1, (id * 0.5497004779019703) % 1
	local side = id % 2 == 0 and 1 or -1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local frame = st and st.flight or flight(phase, c)
	local span, tail = math.clamp(c.k11 or 245, 90, 400), math.clamp(c.k12 or 280, 80, 450)
	local x, y, z
	if pick < 0.62 then
		local feather = math.floor((id - 1) / 2) % 7
		local s = (feather + u) / 7
		-- Seven broad stepped vanes form a chevron, not fine individual quills.
		x = span * (0.07 + 0.93 * s)
		z = span * (0.27 - 0.45 * s - v * (0.26 + 0.17 * s))
		local angle = math.rad(math.clamp(c.k14 or 38, 0, 70)) * math.sin(phase * 2 - s * 0.8)
		y = span * 0.05 + x * math.sin(angle) + span * 0.025 * (w - 0.5)
		x = side * x * math.cos(angle)
	elseif pick < 0.81 then
		local strand = (id - 1) % 3 - 1
		local q = u * 5
		local segment = math.floor(q)
		local f = q - segment
		local zig = ((segment % 2 == 0 and 1 or -1) * (1 - 2 * f))
		local spread = 0.035 + 0.1 * u
		x = strand * span * spread + tail * 0.075 * zig * u
		y = -tail * 0.1 * u + tail * 0.07 * u * math.sin(phase * 2 - u * 6 + strand)
		z = -span * 0.15 - tail * u
		x = x + span * 0.018 * (v - 0.5) * (1 - u)
	elseif pick < 0.95 then
		local q = 2 * u - 1
		local radius = math.sqrt(math.max(0, 1 - q * q))
		x, y, z = span * 0.09 * radius * math.cos(v * TAU), span * 0.085 * radius * math.sin(v * TAU), span * (0.06 + 0.3 * q)
	else
		if w < 0.62 then
			x, y, z = span * 0.065 * (v - 0.5) * (1 - u), span * (0.05 - 0.06 * u), span * (0.32 + 0.19 * u)
		else
			local crest = (id - 1) % 3 - 1
			x, y, z = crest * span * 0.04 * u, span * (0.08 + 0.15 * u), span * (0.2 - 0.1 * u)
		end
	end
	local target = cen + frame.pos + frame.right * x + frame.up * y + frame.forward * z
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Wing Reach", Min = 90, Max = 400, Key = "k11", Default = 245 },
	{ Type = "Slider", Name = "Lightning Tail Length", Min = 80, Max = 450, Key = "k12", Default = 280 },
	{ Type = "Slider", Name = "Storm Speed", Min = 0, Max = 60, Key = "k13", Default = 24, ExactMax = true },
	{ Type = "Slider", Name = "Wingbeat Angle", Min = 0, Max = 70, Key = "k14", Default = 38 },
	{ Type = "Slider", Name = "Flight Height", Min = -100, Max = 500, Key = "k15", Default = 145 },
	{ Type = "Slider", Name = "Hunting Reach", Min = 0, Max = 450, Key = "k16", Default = 210 },
	{ Type = "Slider", Name = "Dive Depth", Min = 0, Max = 200, Key = "k17", Default = 85 },
}

return M
