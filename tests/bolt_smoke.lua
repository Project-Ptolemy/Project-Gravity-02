package.path = "tests/?.lua;" .. package.path
local rm = require("robloxmath")
Vector3, CFrame = rm.Vector3, rm.CFrame
Color3 = { new = function() return {} end }
Color3.fromRGB = Color3.new
if not math.clamp then
	math.clamp = function(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end
end
-- Luau builtin, and this harness loads the shape against plain Lua's table
-- library rather than robloxenv's. Same polyfill as robloxenv.lua:24.
if not table.clear then
	table.clear = function(t) for k in pairs(t) do t[k] = nil end end
end

local fails, checks = 0, 0
local function check(cond, msg)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("  FAIL  " .. msg)
	end
end
local function finite(v)
	return v and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) ~= math.huge
		and math.abs(v.Y) ~= math.huge
		and math.abs(v.Z) ~= math.huge
end

local SRC = "shapes/Goro Goro no Mi.lua"
local S = assert(load(assert(io.open(SRC)):read("a"), "bolt"))()
local function part(pos) return { Position = pos or Vector3.new(0, 0, 0) } end
local x1 = { k10 = 20, k7 = 4, k3 = Color3.fromRGB(0, 255, 255) }
local x9 = { c1 = 0.15 }
local function mk_x6(n) return { pre = {}, f = 0, n = n or 400 } end
local CFG = { k11 = 200, k12 = 18, k13 = 14, k14 = 12, k15 = 0,
              k16 = 0.3, k17 = 0.4, k18 = 0, k19 = false, k20 = false, k21 = false }
local function cfg(over)
	local o = {}
	for k, v in pairs(CFG) do o[k] = v end
	for k, v in pairs(over or {}) do o[k] = v end
	return o
end

local function split(cen, dir, p)
	local rel = p - cen
	local along = rel:Dot(dir)
	return (rel - dir * along).Magnitude, along
end

print("Goro Goro no Mi · hash")
do
	local adj, chan, n = 0, 0, 0
	for seed = 1, 1500 do
		for node = 0, 30 do
			n = n + 1
			if math.abs(S._h(seed, node, 1) - S._h(seed, node + 1, 1)) < 0.02 then adj = adj + 1 end
			if math.abs(S._h(seed, node, 1) - S._h(seed, node, 2)) < 0.02 then chan = chan + 1 end
		end
	end
	check(math.abs(adj / n - 0.04) < 0.015, ("adjacent nodes decorrelated: %.4f vs 0.04"):format(adj / n))
	check(math.abs(chan / n - 0.04) < 0.015, ("channels decorrelated: %.4f vs 0.04"):format(chan / n))
	local lo, hi = 1, 0
	for seed = 1, 200 do
		for node = 0, 63 do
			local v = S._h(seed, node, 1)
			if v < lo then lo = v end
			if v > hi then hi = v end
			check(v == v and v >= 0 and v < 1, "hash stays in [0,1)")
		end
	end
	check(lo < 0.02 and hi > 0.98, ("hash spans its range: %.3f..%.3f"):format(lo, hi))
end

print("Goro Goro no Mi · main channel")
do
	local x6 = mk_x6()
	local cen = Vector3.new(0, 10, 0)
	local c = cfg()
	local dir = Vector3.new(0, 0, 1)
	local bad, worst, far, seen = 0, 0, 0, {}
	for id = 1, 400 do
		local _, tp = S.f2(part(), cen, { id = id }, 0.5, c, x1, x6, x9)
		if not finite(tp) then
			bad = bad + 1
		else
			seen[("%.2f,%.2f,%.2f"):format(tp.X, tp.Y, tp.Z)] = true
			local perp, along = split(cen, dir, tp)
			if perp > worst then worst = perp end
			if along > far then far = along end
		end
	end
	local distinct = 0
	for _ in pairs(seen) do distinct = distinct + 1 end

	check(bad == 0, ("every id finite (%d bad)"):format(bad))
	check(distinct > 350, ("Weyl spread: %d/400 distinct slots"):format(distinct))
	local bound = (c.k13 + c.k18) * 1.4143 + 1
	check(worst <= bound, ("main channel within %.1f of the axis (worst %.1f)"):format(bound, worst))
	check(far <= c.k11 + 1, ("never overshoots Bolt Length %d (max along %.1f)"):format(c.k11, far))
	check(worst > 1, ("the path is actually jittered, not straight (worst %.1f)"):format(worst))
end

print("Goro Goro no Mi · branches and thickness")
do
	local x6 = mk_x6()
	local cen = Vector3.new(0, 10, 0)
	local c = cfg({ k15 = 3, k16 = 0.3, k17 = 0.4, k18 = 2 })
	local dir = Vector3.new(0, 0, 1)
	local len = c.k11
	local main_worst, branch_worst, nmain, nbranch = 0, 0, 0, 0
	local bad = 0
	for id = 1, 2000 do
		local _, tp = S.f2(part(), cen, { id = id }, 0.5, c, x1, x6, x9)
		if not finite(tp) then
			bad = bad + 1
		else
			local perp = split(cen, dir, tp)
			if ((id * 0.7548776662466927) % 1) < c.k16 then
				nbranch = nbranch + 1
				if perp > branch_worst then branch_worst = perp end
			else
				nmain = nmain + 1
				if perp > main_worst then main_worst = perp end
			end
		end
	end
	check(bad == 0, ("every id finite with branches on (%d bad)"):format(bad))
	check(nmain > 0 and nbranch > 0, "both channels populated")
	check(math.abs(nbranch / 2000 - c.k16) < 0.05,
		("branch share tracks the slider: %.3f vs %.2f"):format(nbranch / 2000, c.k16))

	local main_bound = (c.k13 + c.k18) * 1.4143 + 1
	local branch_bound = len * c.k17 + (c.k13 + c.k18) * 1.5
	check(main_worst <= main_bound,
		("main channel still within %.1f (worst %.1f)"):format(main_bound, main_worst))
	check(branch_worst <= branch_bound,
		("branches within %.1f (worst %.1f)"):format(branch_bound, branch_worst))
	check(branch_worst > main_worst, "branches actually leave the main channel")

	local c0 = cfg({ k15 = 0, k16 = 0.3, k18 = 2 })
	local okz = true
	for id = 1, 400 do
		local _, tp = S.f2(part(), cen, { id = id }, 0.5, c0, x1, x6, x9)
		if not finite(tp) then okz = false end
	end
	check(okz, "Branch Count 0 stays finite")

	for _, pair in ipairs({ { 0, 0 }, { 100, 20 } }) do
		local ce = cfg({ k13 = pair[1], k18 = pair[2], k15 = 3, k16 = 0.3 })
		local oke = true
		for id = 1, 400 do
			local _, tp = S.f2(part(), cen, { id = id }, 0.5, ce, x1, x6, x9)
			if not finite(tp) then oke = false end
		end
		check(oke, ("Jaggedness %d / Thickness %d stays finite"):format(pair[1], pair[2]))
	end

	for _, n in ipairs({ 4, 64 }) do
		local cn = cfg({ k12 = n, k15 = 3, k16 = 0.3, k18 = 2 })
		local okn = true
		for id = 1, 200 do
			local _, tp = S.f2(part(), cen, { id = id }, 0.5, cn, x1, x6, x9)
			if not finite(tp) then okn = false end
		end
		check(okn, ("Node Count %d stays finite"):format(n))
	end
end

local MOUSE_HIT = Vector3.new(140, 8, 40)
local function set_mouse(v) MOUSE_HIT = v end
game = {
	GetService = function(_, name)
		if name == "Players" then
			return { LocalPlayer = { GetMouse = function() return { Hit = CFrame.new(MOUSE_HIT) } end } }
		end
		return {
			TouchEnabled = false,
			KeyboardEnabled = true,
			InputBegan = { Connect = function() return { Disconnect = function() end } end },
			InputEnded = { Connect = function() return { Disconnect = function() end } end },
			GetMouseLocation = function() return { X = 400, Y = 300 } end,
		}
	end,
}
workspace = {
	CurrentCamera = { CFrame = CFrame.new(0, 0, 0),
		ViewportPointToRay = function() return { Origin = Vector3.zero, Direction = Vector3.new(0, 0, 1) } end },
	Raycast = function() return { Position = MOUSE_HIT } end,
}
Enum = setmetatable({}, { __index = function()
	return setmetatable({}, { __index = function() return 0 end })
end })

print("Goro Goro no Mi · aim and flicker")
do
	local cen = Vector3.new(0, 10, 0)
	local c = cfg({ k19 = true, k14 = 12, k15 = 0, k18 = 2 })

	set_mouse(Vector3.new(140, 8, 40))
	local x6 = mk_x6()
	x6.f = 8
	local dir = (MOUSE_HIT - cen).Unit
	local len = (MOUSE_HIT - cen).Magnitude
	local far, bad = 0, 0
	for id = 1, 400 do
		local _, tp = S.f2(part(), cen, { id = id }, 1.0, c, x1, x6, x9)
		if not finite(tp) then bad = bad + 1 else
			local _, along = split(cen, dir, tp)
			if along > far then far = along end
		end
	end
	check(bad == 0, ("cursor aim finite (%d bad)"):format(bad))
	check(far <= len + 1, ("bolt lands on the cursor, not past it (%.1f of %.1f)"):format(far, len))
	check(far > len * 0.8, ("bolt actually reaches the cursor (%.1f of %.1f)"):format(far, len))

	local x6b = mk_x6()
	local ref = {}
	for frame = 8, 11 do
		x6b.f = frame
		for id = 1, 50 do
			local _, tp = S.f2(part(), cen, { id = id }, 1.0 + frame / 60, c, x1, x6b, x9)
			local key = ("%.4f,%.4f,%.4f"):format(tp.X, tp.Y, tp.Z)
			if ref[id] == nil then ref[id] = key end
			check(ref[id] == key,
				("id %d agrees across frame %d within one generation"):format(id, frame))
		end
	end

	local x6c = mk_x6()
	x6c.f = 8
	local _, a = S.f2(part(), cen, { id = 77 }, 1.0, c, x1, x6c, x9)
	local _, b = S.f2(part(), cen, { id = 77 }, 1.0 + 5 / c.k14, c, x1, x6c, x9)
	check((a - b).Magnitude < 1e-6,
		("t alone does not reseed within a generation (moved %.4f)"):format((a - b).Magnitude))

	local moved = 0
	for id = 1, 200 do
		local x6d = mk_x6()
		x6d.f = 8
		local _, p1 = S.f2(part(), cen, { id = id }, 1.0, c, x1, x6d, x9)
		x6d.f = 12
		local _, p2 = S.f2(part(), cen, { id = id }, 1.0 + 2 / c.k14, c, x1, x6d, x9)
		if (p1 - p2).Magnitude > 0.5 then moved = moved + 1 end
	end
	check(moved > 150, ("crossing a generation reseeds (%d/200 parts moved)"):format(moved))

	set_mouse(Vector3.new(0, 210, 0))
	local x6e = mk_x6()
	x6e.f = 8
	local vdir = Vector3.new(0, 1, 0)
	local vworst = 0
	for id = 1, 1000 do
		local _, tp = S.f2(part(), cen, { id = id }, 1.0, cfg({ k19 = true, k15 = 0, k18 = 2 }), x1, x6e, x9)
		if finite(tp) then
			local perp = split(cen, vdir, tp)
			if perp > vworst then vworst = perp end
		end
	end
	check(vworst > 1, ("vertical basis does not collapse (spread %.1f)"):format(vworst))
	set_mouse(Vector3.new(140, 8, 40))
end

-- The slider and runtime must agree on the raised cap. A new processing
-- generation can reroll before the former 60 Hz interval has elapsed.
do
	for _, control in ipairs(S.Controls) do
		if control.Key == "k14" then check(control.Max == 300, "flicker slider allows 300") end
	end
	for _, rate in ipairs({ 300, 1000 }) do
		local run, c = mk_x6(), cfg({ k14 = rate })
		run.f = 4
		S.f2(part(), Vector3.zero, { id = 17 }, 1, c, x1, run, x9)
		local state = run.pre["Goro Goro no Mi"]
		local seed = state.seed
		run.f = 8
		S.f2(part(), Vector3.zero, { id = 17 }, 1.002, c, x1, run, x9)
		check(state.seed == seed, "flicker does not exceed the 300 cap")
		run.f = 12
		local velocity, target = S.f2(part(), Vector3.zero, { id = 17 }, 1.004, c, x1, run, x9)
		check(state.seed == seed + 1 and finite(velocity) and finite(target), "300 flicker rerolls within 4 ms with finite motion")
		S.cleanup(run)
	end
end

print("Goro Goro no Mi · hold to fire and cleanup")
do
	local cen = Vector3.new(0, 10, 0)
	local x6 = mk_x6()
	x6.f = 8

	local c_off = cfg({ k19 = true, k20 = false })
	local _, tp = S.f2(part(), cen, { id = 5 }, 1.0, c_off, x1, x6, x9)
	check(finite(tp), "bolt is live with Hold To Fire off")
	-- The listeners are connected unconditionally now and gated on a live flag on
	-- the state table. They used to be created only while the toggle was on, and
	-- since f2 can never re-make them, turning it off mid-hold left st.holding
	-- latched true for good and the bolt never stopped firing.
	check(x6.pre["Goro Goro no Mi"].hold_enabled == false,
		"Hold To Fire off disarms the listeners")

	local x6m = mk_x6()
	x6m.f = 8
	local c_on = cfg({ k19 = true, k20 = true })
	S.f2(part(), cen, { id = 5 }, 1.0, c_on, x1, x6m, x9)
	local stm = x6m.pre["Goro Goro no Mi"]
	stm.holding = true
	check(stm.hold_enabled == true, "Hold To Fire on arms the listeners")
	S.f2(part(), cen, { id = 5 }, 1.1, cfg({ k19 = true, k20 = false }), x1, x6m, x9)
	check(stm.holding == false and stm.tap_locked == false,
		"turning Hold To Fire off releases a latched hold instead of firing forever")

	local x6h = mk_x6()
	x6h.f = 8
	local far, allsame = 0, {}
	for id = 1, 200 do
		local vel, p2 = S.f2(part(), cen, { id = id }, 1.0, c_on, x1, x6h, x9)
		check(finite(p2) and finite(vel), ("idle id %d finite"):format(id))
		local dist = (p2 - cen).Magnitude
		if dist > far then far = dist end
		allsame[("%.2f,%.2f,%.2f"):format(p2.X, p2.Y, p2.Z)] = true
	end
	local distinct = 0
	for _ in pairs(allsame) do distinct = distinct + 1 end
	check(far > 1, ("idle parts hold a cloud, not a single point (max %.1f)"):format(far))
	check(distinct > 150, ("idle cloud is spread, not stacked (%d/200)"):format(distinct))
	check(x6h.pre["Goro Goro no Mi"].conns ~= nil, "listeners connected when Hold To Fire is on")

	local disconnected = 0
	for _, cn in ipairs(x6h.pre["Goro Goro no Mi"].conns) do
		local real = cn.Disconnect
		cn.Disconnect = function(...) disconnected = disconnected + 1; return real(...) end
	end
	local nconns = #x6h.pre["Goro Goro no Mi"].conns
	S.cleanup(x6h, x1)
	check(disconnected == nconns, ("cleanup disconnects all %d listeners"):format(nconns))
	check(x6h.pre["Goro Goro no Mi"] == nil, "cleanup clears its x6.pre entry")
	local ok = pcall(S.cleanup, mk_x6(), x1)
	check(ok, "cleanup is safe to call twice / on fresh state")
end

print("Goro Goro no Mi · neon recolour")
do
	local cen = Vector3.new(0, 10, 0)
	local x6 = mk_x6()
	x6.f = 8
	local writes = 0
	local function tracked()
		local t = { Position = Vector3.new(0, 0, 0) }
		return setmetatable({}, {
			__index = t,
			__newindex = function(_, k, v) writes = writes + 1; t[k] = v end,
		}), t
	end

	local pa = tracked()
	S.f2(pa, cen, { id = 3 }, 1.0, cfg({ k21 = false }), x1, x6, x9)
	check(writes == 0, ("no property writes with the toggle off (%d)"):format(writes))

	writes = 0
	local pb, raw = tracked()
	local c_on = cfg({ k21 = true })
	S.f2(pb, cen, { id = 3 }, 1.0, c_on, x1, x6, x9)
	local first = writes
	check(first > 0, "the toggle actually writes")
	check(raw.Material ~= nil and raw.Color ~= nil, "both Material and Color are set")
	writes = 0
	for _ = 1, 20 do
		S.f2(pb, cen, { id = 3 }, 1.0, c_on, x1, x6, x9)
	end
	check(writes == 0, ("guarded: %d further writes across 20 frames"):format(writes))
end

print(("\n%d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
