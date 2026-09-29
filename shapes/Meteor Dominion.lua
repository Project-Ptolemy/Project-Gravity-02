local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Meteor Dominion"
local TAU = math.pi * 2

function M.px(t, c, x6, x9)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 10, 0, 40) * x9.c2
	st.t = t
end

local function chunky(n)
	return (n < 0 and -1 or 1) * math.sqrt(math.abs(n))
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local id = d.slot or d.id or 1
	local u, v, w = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1, (id * 0.5497004779019703) % 1
	local pick = (id * 0.6180339887498949) % 1
	local st = x6.pre and x6.pre[NAME]
	local phase = st and st.phase or 0
	local size, spread = math.clamp(c.k11 or 110, 55, 200), math.clamp(c.k12 or 540, 250, 800)
	local fall, wake = math.clamp(c.k14 or 250, 100, 450), math.clamp(c.k15 or 160, 50, 280)
	local meteor = (id - 1) % 3
	local q = phase * 0.13 + meteor * TAU / 3
	-- Staggered tilted loops carry all three boulders down, under, and up again.
	local center = Vector3.new((meteor - 1) * spread * 0.5 + spread * 0.22 * math.sin(q),
		(c.k16 or 290) + fall * math.cos(q), spread * 0.31 * math.sin(q))
	local velocity = Vector3.new(spread * 0.22 * math.cos(q), -fall * math.sin(q), spread * 0.31 * math.cos(q))
	local forward = velocity / velocity.Magnitude
	local x, y, z
	if pick < 0.82 then
		local a = u * TAU
		local h = v * 2 - 1
		local radial = math.sqrt(1 - h * h)
		local crust = size * (0.84 + 0.16 * math.cos(a * 5 + h * 8))
		x = crust * chunky(radial * math.cos(a))
		y = crust * 0.84 * chunky(h)
		z = crust * 0.92 * chunky(radial * math.sin(a))
		local roll = phase * 0.09 + meteor
		x, z = x * math.cos(roll) - z * math.sin(roll), x * math.sin(roll) + z * math.cos(roll)
		y = y + size * 0.06 * math.sin(roll * 2 + a)
	else
		-- Short narrowing wakes stay attached to the moving rocks.
		local trail = (0.5 + 0.5 * math.sin(phase * 0.24 + u * TAU))
		local a = v * TAU + phase * 0.16
		local right = Vector3.new(forward.Z, 0, -forward.X)
		right = right.Magnitude > 0.001 and right / right.Magnitude or Vector3.new(1, 0, 0)
		local up = forward:Cross(right)
		local point = -forward * (size * 0.85 + wake * trail)
		point = point + (right * math.cos(a) + up * math.sin(a)) * size * 0.42 * (1 - trail) * (0.6 + 0.4 * w)
		x, y, z = point.X, point.Y, point.Z
	end
	local target = cen + center + Vector3.new(x, y, z)
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Meteor Radius", Min = 55, Max = 200, Key = "k11", Default = 110 },
	{ Type = "Slider", Name = "Impact Spread", Min = 250, Max = 800, Key = "k12", Default = 540 },
	{ Type = "Slider", Name = "Descent Speed", Min = 0, Max = 40, Key = "k13", Default = 10, ExactMax = true },
	{ Type = "Slider", Name = "Fall Distance", Min = 100, Max = 450, Key = "k14", Default = 250 },
	{ Type = "Slider", Name = "Wake Length", Min = 50, Max = 280, Key = "k15", Default = 160 },
	{ Type = "Slider", Name = "Loop Altitude", Min = 100, Max = 650, Key = "k16", Default = 290 },
}

return M
