-- The separated layout can exceed the normal processing radius at large sizes.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Rift Gate"
local TAU = math.pi * 2
local PHI = 0.6180339887498949

local function noise(gate, channel)
	return (math.sin(gate * 127.1 + channel * 311.7) * 43758.5453123) % 1
end

local function state(x6, t)
	x6.pre = x6.pre or {}
	local st = x6.pre[NAME]
	if not st then
		st = { phase = 0, t = t, offsets = {} }
		-- Stable random-looking positions: previews, late claims and count changes
		-- use the same layout. Reserve separated sectors so no retry loop is needed.
		-- The minimum angular gap and radius keep every pair over one unit apart.
		for gate = 1, 5 do
			local angle = ((gate - 1) * 2 % 5) * TAU / 5 + noise(0, 1) * TAU
				+ (noise(gate, 1) - 0.5) * 0.24
			local reach = 1.1 + noise(gate, 2) * 0.35
			st.offsets[gate] = Vector3.new(math.cos(angle) * reach,
				0.15 + noise(gate, 3) * 0.6, math.sin(angle) * reach)
		end
		x6.pre[NAME] = st
	end
	return st
end

function M.px(t, c, x6, x9)
	local st = state(x6, t)
	st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 8, 0, 40) * x9.c2
	st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local id = d.slot or d.id or 1
	local rifts = math.clamp(math.floor(c.k19 or 3), 1, 6)
	local gate = (id - 1) % rifts
	-- Choose anatomy from the index WITHIN a gate. Using the global id for
	-- both gate and mouth made every even-sized stack lose one mouth per gate.
	id = math.floor((id - 1) / rifts) + 1
	local pick = (id * PHI) % 1
	local u, v = (id * 0.8191725133961645) % 1, (id * 0.6710436067037893) % 1
	local st = state(x6, t)
	local phase = st.phase
	local radius = math.clamp(c.k11 or 100, 30, 300)
	local depth = math.clamp(c.k12 or 220, 20, 600)
	local blades = math.clamp(math.floor(c.k14 or 9), 4, 18)
	local opening = math.clamp(c.k15 or 65, 10, 100) / 100
	local twists = math.clamp(c.k16 or 3, 0, 8)
	if c.k18 ~= false then
		opening = opening * (0.85 + 0.15 * math.cos(phase * 1.3))
	end
	local side = id % 2 == 0 and 1 or -1
	local r, a, z

	if pick < 0.28 then
		-- Raised rings preserve both mouths while the iris turns inside them.
		a = u * TAU + side * phase * 0.4
		r = radius * (1.08 + 0.025 * math.cos(v * TAU))
		z = side * depth * 0.5 + radius * 0.025 * math.sin(v * TAU)
	elseif pick < 0.68 then
		local strand = (id - 1) % blades
		local along = u * 2 - 1
		r = radius * (opening + (1 - opening) * along * along)
		r = r + radius * 0.012 * math.cos(v * TAU)
		a = strand * TAU / blades + u * twists * TAU - phase
		z = along * depth * 0.5
	else
		local blade = math.floor((id - 1) / 2) % blades
		local width = math.sin(math.pi * u) ^ 0.7
		r = radius * (opening * 0.72 + u * (1.15 - opening * 0.72))
		a = blade * TAU / blades + side * phase * 0.35 + 0.7 * (1 - u)
			+ (v - 0.5) * (TAU / blades) * 0.65 * width
		z = side * (depth * 0.5 + radius * 0.12 * math.sin(math.pi * u))
	end

	-- Rotate each gate locally before placing it in the scattered layout.
	local lx, ly, lz = r * math.cos(a), r * math.sin(a), z
	local roll, pitch, yaw = math.rad(c.k21 or 0), math.rad(c.k22 or 0), math.rad(c.k23 or 0)
	if roll ~= 0 then
		local cr, sr = math.cos(roll), math.sin(roll)
		lx, ly = lx * cr - ly * sr, lx * sr + ly * cr
	end
	if pitch ~= 0 then
		local cp, sp = math.cos(pitch), math.sin(pitch)
		ly, lz = ly * cp - lz * sp, ly * sp + lz * cp
	end
	if yaw ~= 0 then
		local cy, sy = math.cos(yaw), math.sin(yaw)
		lx, lz = lx * cy + lz * sy, -lx * sy + lz * cy
	end

	local hover = c.k17 or 130
	local offset = Vector3.new(0, hover, 0)
	if gate > 0 then
		local radial_extent, axial_extent = radius * 1.15, depth * 0.5 + radius * 0.12
		local extent = math.sqrt(radial_extent * radial_extent + axial_extent * axial_extent)
		-- Keep complete gates apart even at zero spacing or with a tilted tunnel.
		local spacing = math.max(math.clamp(c.k20 or 320, 0, 600), extent * 2 + 10)
		local scatter = st.offsets[gate] * spacing
		local half_height = radial_extent * math.abs(math.cos(pitch)) + axial_extent * math.abs(math.sin(pitch))
		local motion_y = x6.motion_offset and x6.motion_offset.Y or 0
		local floor = math.max(hover, half_height + 2 - math.min(motion_y, 0))
		offset = Vector3.new(scatter.X, floor + scatter.Y, scatter.Z)
	end
	local target = cen + Vector3.new(lx, ly, lz) + offset
	if x6.motion_offset then target = target + x6.motion_offset end
	return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
	if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
	{ Type = "Slider", Name = "Gate Radius", Min = 30, Max = 300, Key = "k11", Default = 100 },
	{ Type = "Slider", Name = "Tunnel Depth", Min = 20, Max = 600, Key = "k12", Default = 220 },
	{ Type = "Slider", Name = "Vortex Speed", Min = 0, Max = 40, Key = "k13", Default = 8, ExactMax = true },
	{ Type = "Slider", Name = "Iris Blades", Min = 4, Max = 18, Key = "k14", Default = 9, IntOnly = true },
	{ Type = "Slider", Name = "Aperture %", Min = 10, Max = 100, Key = "k15", Default = 65, IntOnly = true },
	{ Type = "Slider", Name = "Tunnel Twists", Min = 0, Max = 8, Key = "k16", Default = 3, IntOnly = true },
	{ Type = "Slider", Name = "Hover Height", Min = -100, Max = 500, Key = "k17", Default = 130 },
	{ Type = "Toggle", Name = "Breathing Aperture", Key = "k18", Default = true },
	{ Type = "Slider", Name = "Rift Count", Min = 1, Max = 6, Key = "k19", Default = 3, IntOnly = true },
	{ Type = "Slider", Name = "Rift Spacing", Min = 0, Max = 600, Key = "k20", Default = 320,
		Desc = "Spread additional rifts around the main gate. A minimum gap prevents overlap; extra rifts stay above the core's horizontal plane." },
	{ Type = "Slider", Name = "Roll", Min = 0, Max = 350, Key = "k21", Default = 0, IntOnly = true },
	{ Type = "Slider", Name = "Pitch", Min = 0, Max = 350, Key = "k22", Default = 0, IntOnly = true },
	{ Type = "Slider", Name = "Yaw", Min = 0, Max = 350, Key = "k23", Default = 0, IntOnly = true },
}

return M
