local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Extinction Comet"
local TAU = math.pi * 2
local PHI = 0.6180339887498949
local UP = Vector3.new(0, 1, 0)

local function flight(phase, c)
	local q = phase * 0.18
	local reach = math.clamp(c.k15 or 230, 0, 650)
	local dive = math.clamp(c.k16 or 180, 0, 350)
	local center = Vector3.new(reach * math.cos(q), (c.k17 or 50) + dive * (0.5 + 0.5 * math.sin(q * 1.2)),
		reach * (math.sin(q) + 0.3 * math.sin(q * 0.37)))
	local dx, dy, dz = -reach * math.sin(q), dive * 0.6 * math.cos(q * 1.2), reach * (math.cos(q) + 0.111 * math.cos(q * 0.37))
	local flat = math.sqrt(dx * dx + dz * dz)
	local heading = flat > 0.0001 and Vector3.new(dx / flat, 0, dz / flat) or Vector3.new(0, 0, 1)
	local pitch = math.atan2(dy, math.sqrt(flat * flat + dive * dive * 0.04 + 1))
	local forward = heading * math.cos(pitch) + UP * math.sin(pitch)
	local right = UP:Cross(heading)
	return { center = center, right = right, up = forward:Cross(right), forward = forward }
end

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then
		st = { phase = 0, t = t }
		x6.pre[NAME] = st
	end
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 16, 0, 60) * x9.c2
	st.t = t
	st.frame = flight(st.phase, c)
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local id = d.slot or d.id or 1
	local pick = (id * PHI) % 1
	local u, v, w = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1, (id * 0.5497004779019703) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local frame = st and st.frame or flight(phase, c)
	local head = math.clamp(c.k11 or 70, 25, 180)
	local tail = math.clamp(c.k12 or 310, 100, 600)
	local spread = math.clamp(c.k14 or 95, 20, 220)
	local x, y, z
	if pick < 0.32 then
		local sy = 1 - 2 * u
		local ring = math.sqrt(math.max(0, 1 - sy * sy))
		local angle = v * TAU + phase * 0.45
		local rough = 0.86 + w * 0.14
		x, y, z = head * ring * math.cos(angle) * rough, head * ring * math.sin(angle) * rough, head * sy * 1.2
	elseif pick < 0.47 then
		-- A broad curved shock bow gives the leading boulder a strong silhouette.
		local angle = u * TAU - phase * 0.3
		local r = head * (0.9 + v * 0.38)
		x, y, z = r * math.cos(angle), r * math.sin(angle), head * (0.75 - v * v * 0.8)
	else
		-- Five discrete flame braids stream around a bent, tapered tail.
		local strand = (id - 1) % 5
		local angle = strand * TAU / 5 + phase * 0.65 - u * 2.4
		local envelope = spread * math.sin(math.pi * u) ^ 0.7
		local r = head * 0.65 * (1 - u) + envelope * (0.8 + v * 0.2)
		x = r * math.cos(angle) + spread * 0.7 * u * u * math.sin(phase * 0.35 - u * 2)
		y = r * math.sin(angle) + spread * u * u * (0.45 + 0.4 * math.cos(phase * 0.3 - u))
		z = -head * 0.55 - tail * u
	end
	local target = cen + frame.center + frame.right * x + frame.up * y + frame.forward * z
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Comet Radius", Min = 25, Max = 180, Key = "k11", Default = 70 },
	{ Type = "Slider", Name = "Flame Tail Length", Min = 100, Max = 600, Key = "k12", Default = 310 },
	{ Type = "Slider", Name = "Dive Speed", Min = 0, Max = 60, Key = "k13", Default = 16, ExactMax = true },
	{ Type = "Slider", Name = "Flame Spread", Min = 20, Max = 220, Key = "k14", Default = 95 },
	{ Type = "Slider", Name = "Flight Area", Min = 0, Max = 650, Key = "k15", Default = 230 },
	{ Type = "Slider", Name = "Dive Height", Min = 0, Max = 350, Key = "k16", Default = 180 },
	{ Type = "Slider", Name = "Lowest Flight Height", Min = -100, Max = 350, Key = "k17", Default = 50 },
}

return M
