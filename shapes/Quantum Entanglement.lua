local M = {}

-- Quantum Entanglement: parts are paired. Each pair shares a random unit vector
-- (the "quantum state"). When a measurement fires, one part collapses to
-- cen + s * R and its partner instantly snaps to cen - s * R, no matter how far
-- apart they were. Between measurements both parts drift in a fuzzy cloud.
--
-- The "instant" correlation is faked with a single-frame velocity spike. The
-- partner reads the same state from x6.pre, so it knows where to go without any
-- visible signal passing between them.

local ANTI_SLEEP = Vector3.new(0, 0.01, 0)
local UP = Vector3.new(0, 1, 0)

-- Pair state constants
local SUPERPOSITION = 0
local MEASURING = 1
local COLLAPSED = 2

local function random_unit_vector()
	-- Uniform distribution on a sphere: z is cos(theta), a is phi.
	local z = math.random() * 2 - 1
	local a = math.random() * math.pi * 2
	local r = math.sqrt(1 - z * z)
	return Vector3.new(r * math.cos(a), z, r * math.sin(a))
end

function M.px(t, c, x6, x9, x1)
	local st = x6.pre["Quantum Entanglement"]
	if not st then
		st = { pairs = {}, next_measure = 0 }
		x6.pre["Quantum Entanglement"] = st
	end

	local pair_count = math.floor(c.k11 or 50)
	if pair_count < 2 then
		pair_count = 2
	end
	local measure_interval = c.k14 or 3
	local collapse_hold = c.k15 or 2

	-- Rebuild pair table if the control changed
	if #st.pairs ~= pair_count then
		st.pairs = {}
		for i = 1, pair_count do
			st.pairs[i] = {
				state = SUPERPOSITION,
				s = random_unit_vector(),
				measure_t = 0,
				collapse_t = 0,
				observed = 0, -- which part of the pair is being observed (0 or 1)
			}
		end
		st.next_measure = t + math.random() * measure_interval
	end

	-- Time to measure a random pair?
	if t >= st.next_measure then
		local idx = math.random(1, pair_count)
		local pair = st.pairs[idx]
		if pair.state == SUPERPOSITION then
			pair.state = MEASURING
			pair.s = random_unit_vector()
			pair.measure_t = t
			pair.observed = math.random(0, 1)
		end
		st.next_measure = t + measure_interval * (0.5 + math.random())
	end

	-- Advance pair states
	for _, pair in ipairs(st.pairs) do
		if pair.state == MEASURING and t - pair.measure_t > 0.5 then
			pair.state = COLLAPSED
			pair.collapse_t = t
		elseif pair.state == COLLAPSED and t - pair.collapse_t > collapse_hold then
			pair.state = SUPERPOSITION
		end
	end
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local wp = p.Position
	local st = x6.pre["Quantum Entanglement"]
	if not st or #st.pairs == 0 then
		return ANTI_SLEEP, nil
	end

	local pair_count = #st.pairs
	local cloud_radius = c.k12 or 100
	local orbit_radius = c.k13 or 200
	local drift_speed = (c.k16 or 5) * x9.c2

	-- Assign this part to a pair and a slot within that pair
	local idx = d.slot or d.id or 0
	local pair_idx = (idx % pair_count) + 1
	local slot = math.floor(idx / pair_count) % 2 -- 0 or 1
	local pair = st.pairs[pair_idx]

	if pair.state == SUPERPOSITION then
		-- Drift in a fuzzy cloud. Each part has its own random walk phase.
		if not d.v1 then
			d.v1 = math.random() * math.pi * 2
			d.v2 = math.random() * math.pi * 2
			d.v3 = math.random() * math.pi * 2
		end
		local ph = t * drift_speed
		-- Divide by sqrt(3) so the maximum displacement equals cloud_radius.
		local inv_sqrt3 = 1 / math.sqrt(3)
		local dx = math.sin(ph + d.v1) * cloud_radius * inv_sqrt3
		local dy = math.sin(ph * 0.7 + d.v2) * cloud_radius * inv_sqrt3
		local dz = math.sin(ph * 1.3 + d.v3) * cloud_radius * inv_sqrt3
		local target = cen + Vector3.new(dx, dy, dz)
		return (target - wp) * (x1.k10 * x9.c1), target
	end

	-- MEASURING or COLLAPSED: both parts know the shared state s
	local s = pair.s
	local target
	if slot == pair.observed then
		target = cen + s * orbit_radius
	else
		target = cen - s * orbit_radius
	end

	if pair.state == MEASURING then
		-- Only the observed part moves. The partner keeps drifting so the
		-- correlation appears instantaneous when collapse hits.
		if slot == pair.observed then
			return (target - wp) * (x1.k10 * x9.c1 * 3), target
		else
			-- Partner stays in superposition: keep drifting.
			if not d.v1 then
				d.v1 = math.random() * math.pi * 2
				d.v2 = math.random() * math.pi * 2
				d.v3 = math.random() * math.pi * 2
			end
			local ph = t * drift_speed
			local inv_sqrt3 = 1 / math.sqrt(3)
			local dx = math.sin(ph + d.v1) * cloud_radius * inv_sqrt3
			local dy = math.sin(ph * 0.7 + d.v2) * cloud_radius * inv_sqrt3
			local dz = math.sin(ph * 1.3 + d.v3) * cloud_radius * inv_sqrt3
			local drift_target = cen + Vector3.new(dx, dy, dz)
			return (drift_target - wp) * (x1.k10 * x9.c1), drift_target
		end
	else
		-- COLLAPSED: both parts snap hard. The partner's velocity is spiked so
		-- it crosses the map in one frame, faking instantaneous correlation.
		local mult = slot == pair.observed and 5 or 50
		return (target - wp) * (x1.k10 * x9.c1 * mult), target
	end
end

M.Controls = {
	{ Type = "Slider", Name = "Pair Count", Min = 2, Max = 200, Key = "k11", Default = 50, IntOnly = true },
	{ Type = "Slider", Name = "Cloud Radius", Min = 20, Max = 500, Key = "k12", Default = 100 },
	{ Type = "Slider", Name = "Orbit Radius", Min = 50, Max = 1000, Key = "k13", Default = 200 },
	{ Type = "Slider", Name = "Measure Interval", Min = 1, Max = 20, Key = "k14", Default = 0.3, Div = 10 },
	{ Type = "Slider", Name = "Collapse Hold", Min = 1, Max = 10, Key = "k15", Default = 0.2, Div = 10 },
	{ Type = "Slider", Name = "Drift Speed", Min = 1, Max = 50, Key = "k16", Default = 0.5, Div = 10 },
}

-- The pair table holds live state machines. Left in x6.pre it survives a shape
-- switch, so returning mid-collapse re-measures immediately and next_measure
-- fires a burst of collapses. Same convention as Celestial Ribbon:128.
function M.cleanup(x6, x1)
	if not x6.pre then
		return
	end
	x6.pre["Quantum Entanglement"] = nil
end

return M
