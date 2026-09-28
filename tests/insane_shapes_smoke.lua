-- Standalone LuaJIT geometry checks; no Roblox services, shell listing or network.
-- Run from the repository root: luajit tests/insane_shapes_smoke.lua
package.path = "tests/?.lua;" .. package.path
local rm = require("robloxmath")
Vector3, CFrame = rm.Vector3, rm.CFrame
Color3 = { fromRGB = function() return {} end }
math.clamp = math.clamp or function(x, lo, hi) return math.max(lo, math.min(x, hi)) end

local config = assert(loadfile("config.lua"))()
local names = {
	"Abyssal Jellyfish",
	"Void Cathedral",
	"Ouroboros",
	"Hopf Fibration",
	"Celestial Manta",
	"Megalodon",
	"World Tree",
	"Ragnarok Hammer",
	"Eclipse Scythe",
	"Aegis Bastion",
	"Singularity Trident",
	"Ghost Galleon",
	"Infernal Skull",
	"Chrono Hourglass",
	"Storm Gyre",
	"Torus Knot", "Klein Bottle",
	"Astral Kraken", "Cosmic Lotus", "Phoenix Ascendant",
	"Rift Gate", "Reality Shatter", "Hypercube Nexus",
}
local modules = {}
local x1, x9 = config.x1, { c1 = 0.15, c2 = 0.05 }
local origin = Vector3.new(31, 70, -29)
local part = setmetatable({}, {
	__index = { Position = Vector3.new(-13, 8, 21) },
	__newindex = function() error("shape wrote a part property") end,
})
local checks, fails = 0, 0
local function check(ok, label)
	checks = checks + 1
	if not ok then fails = fails + 1; print("  FAIL  " .. label) end
end
local function finite(v)
	return v and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < math.huge and math.abs(v.Y) < math.huge and math.abs(v.Z) < math.huge
end
local function near(a, b, eps) return (a - b).Magnitude <= (eps or 1e-7) end
local function copy(t)
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end
local function context() return { pre = {}, n = 0, f = 0 } end
local function start(mod, cfg, time)
	local ctx = context()
	mod.px(0, cfg, ctx, x9, x1)
	mod.px(time or 0, cfg, ctx, x9, x1)
	return ctx
end
local function evaluate(mod, cfg, ctx, id, center, rec)
	local velocity, pos = mod.f2(part, center or origin, rec or { id = id }, 0, cfg, x1, ctx, x9)
	return pos, velocity
end
local function target(...)
	local pos = evaluate(...)
	return pos
end
local function cloud(mod, cfg, ctx, count)
	local out = {}
	for id = 1, count do out[id] = target(mod, cfg, ctx, id) end
	return out
end
local function difference(a, b)
	local total = 0
	for i, p in ipairs(a) do total = total + (p - b[i]).Magnitude end
	return total / #a
end

-- A preview must not roll new random assignments or mutate a real part.
local random = math.random
math.random = function() error("geometry must be deterministic") end

for _, name in ipairs(names) do
	print(name)
	local mod = assert(loadfile("shapes/" .. name .. ".lua"))()
	modules[name] = mod
	local cfg = assert(config.x2[name], "shape must be registered: " .. name)
	local ctx = start(mod, cfg, 2.5)
	local keys = {}
	for _, ctl in ipairs(mod.Controls) do
		check(not keys[ctl.Key], name .. ": unique control key " .. ctl.Key)
		keys[ctl.Key] = true
		local value = cfg[ctl.Key]
		check(type(value) == (ctl.Type == "Toggle" and "boolean" or "number"), name .. ": saved type " .. ctl.Key)
		check(value == ctl.Default, name .. ": local-loader default matches catalog " .. ctl.Key)
		if ctl.Type == "Slider" then
			local shown = value * (ctl.Div or 1)
			check(shown >= ctl.Min and shown <= ctl.Max, name .. ": slider keeps default " .. ctl.Key)
		end
	end

	local seen, distinct = {}, 0
	for id = 1, 512 do
		local pos, velocity = evaluate(mod, cfg, ctx, id)
		check(finite(pos) and finite(velocity), name .. ": finite target and force " .. id)
		check((pos - origin).Magnitude < x1.k1, name .. ": default fits processing radius " .. id)
		check(near(velocity, (pos - part.Position) * (x1.k10 * x9.c1)), name .. ": force follows pure target " .. id)
		local key = ("%.2f,%.2f,%.2f"):format(pos.X, pos.Y, pos.Z)
		if not seen[key] then distinct = distinct + 1; seen[key] = true end
	end
	check(distinct >= 500, name .. ": part slots spread out (" .. distinct .. "/512)")

	local baseline = cloud(mod, cfg, ctx, 128)
	for _, count in ipairs({ 0, 1, 40, 512, 100000 }) do
		ctx.n = count
		check(difference(baseline, cloud(mod, cfg, ctx, 128)) < 1e-7, name .. ": independent of held count " .. count)
	end
	for _, id in ipairs({ 1, 17, 79, 131, 100000003 }) do
		local rec = { id = id }
		local pos = target(mod, cfg, ctx, id, nil, rec)
		check(finite(pos), name .. ": sparse claim id " .. id)
		check(near(pos, target(mod, cfg, ctx, id, nil, { id = 999, slot = id, slot_n = 40 })), name .. ": preview uses slot " .. id)
		local shift = Vector3.new(90, -13, 28)
		check(near(pos + shift, target(mod, cfg, ctx, id, origin + shift)), name .. ": follows anchor " .. id)
		check(rec.id == id and next(rec, "id") == nil, name .. ": evaluation leaves part record alone")
	end
	check(difference(baseline, cloud(mod, cfg, ctx, 128)) < 1e-7, name .. ": sampling order does not change pose")
	mod.px(2.5, cfg, ctx, x9, x1)
	check(difference(baseline, cloud(mod, cfg, ctx, 128)) < 1e-7, name .. ": duplicate px call does not advance")
	for frame = 1, 20 do
		ctx.f = frame
		mod.px(2.5, cfg, ctx, x9, x1)
	end
	check(difference(baseline, cloud(mod, cfg, ctx, 128)) < 1e-7, name .. ": frozen formation clock stays frozen")

	local zero = cloud(mod, cfg, start(mod, cfg), 128)
	mod.px(0, cfg, ctx, x9, x1)
	check(difference(zero, cloud(mod, cfg, ctx, 128)) < 1e-7, name .. ": reversing time restores the pose")
	mod.px(2.5, cfg, ctx, x9, x1)
	check(difference(baseline, cloud(mod, cfg, ctx, 128)) < 1e-7, name .. ": forward after reverse restores motion")
	local frozen = copy(cfg)
	frozen.k13 = 0
	mod.px(2.5, frozen, ctx, x9, x1)
	mod.px(20000, frozen, ctx, x9, x1)
	check(difference(baseline, cloud(mod, frozen, ctx, 128)) < 1e-7, name .. ": speed zero holds current pose")
	frozen.k13 = 40
	mod.px(20000, frozen, ctx, x9, x1)
	check(difference(baseline, cloud(mod, frozen, ctx, 128)) < 1e-7, name .. ": speed edit has no phase jump")

	local minimum, maximum = copy(cfg), copy(cfg)
	for _, ctl in ipairs(mod.Controls) do
		local low, high = copy(cfg), copy(cfg)
		if ctl.Type == "Slider" then
			low[ctl.Key], high[ctl.Key] = ctl.Min / (ctl.Div or 1), ctl.Max / (ctl.Div or 1)
		else low[ctl.Key], high[ctl.Key] = false, true end
		minimum[ctl.Key], maximum[ctl.Key] = low[ctl.Key], high[ctl.Key]
		local lo_cloud = cloud(mod, low, start(mod, low, 4), 128)
		local hi_cloud = cloud(mod, high, start(mod, high, 4), 128)
		check(difference(lo_cloud, hi_cloud) > 0.001, name .. ": control changes geometry " .. ctl.Key)
		for i = 1, 128 do
			check(finite(lo_cloud[i]) and finite(hi_cloud[i]), name .. ": slider extremes " .. ctl.Key .. "/" .. i)
		end
	end
	for _, limits in ipairs({ minimum, maximum }) do
		local extreme = start(mod, limits, -12)
		for frame = 1, 80 do
			mod.px(frame * 0.7 - 12, limits, extreme, x9, x1)
			for id = 1, 80 do
				local pos, velocity = evaluate(mod, limits, extreme, id)
				check(finite(pos) and finite(velocity) and (pos - origin).Magnitude < 5000, name .. ": bounded at combined extremes")
			end
		end
	end

	-- A late claim and a preview take the same live pose as an existing record.
	ctx = start(mod, cfg)
	local previous = cloud(mod, cfg, ctx, 80)
	local oldest = { id = 17 }
	local max_step = 0
	for frame = 1, 360 do
		mod.px(frame / 60, cfg, ctx, x9, x1)
		local now = cloud(mod, cfg, ctx, 80)
		for id = 1, 80 do max_step = math.max(max_step, (now[id] - previous[id]).Magnitude) end
		check(near(target(mod, cfg, ctx, 17, nil, oldest), target(mod, cfg, ctx, 17)), name .. ": new claim joins live pose")
		previous = now
	end
	check(max_step < 20, name .. ": continuous motion (max frame step " .. string.format("%.3f", max_step) .. ")")

	local foreign = {}
	ctx.pre.unrelated = foreign
	mod.cleanup(ctx)
	mod.cleanup(ctx)
	mod.cleanup({})
	check(ctx.pre[name] == nil and ctx.pre.unrelated == foreign, name .. ": cleanup only clears own state")
	mod.px(10000, cfg, ctx, x9, x1)
	check(difference(zero, cloud(mod, cfg, ctx, 128)) < 1e-7, name .. ": re-entry starts without stale animation")
	check(finite(target(mod, cfg, context(), 1)), name .. ": pure target exists before px")

	if mod.ContinuousMotion then
		-- Real debris has very different sizes. A frozen pattern still follows the
		-- runtime's real-time orbit, rigidly and without resizing or writing parts.
		local held = copy(cfg)
		held.k13 = 0
		local live = start(mod, held)
		local sizes = { Vector3.new(4, 2, 2), Vector3.new(12, 1, 8), Vector3.new(2, 18, 2), Vector3.new(40, 2, 16) }
		local previous, initial = {}, {}
		for frame = 0, 90 do
			local a = frame / 30 * 1.2
			live.motion_offset = Vector3.new(6 * (math.cos(a) - 1), 1.5 * math.sin(a * 2), 6 * math.sin(a))
			mod.px(0, held, live, x9, x1)
			for id = 1, 160 do
				local rubble = setmetatable({}, {
					__index = { Position = origin, Size = sizes[(id - 1) % #sizes + 1] },
					__newindex = function() error("shape changed debris properties") end,
				})
				local force, pos = mod.f2(rubble, origin, { id = id }, 0, held, x1, live, x9)
				check(finite(force) and finite(pos), name .. ": mixed rubble remains finite")
				if frame == 0 then initial[id] = pos else
					check((pos - previous[id]).Magnitude > 0.23, name .. ": every frozen slot keeps moving")
					check(near(pos - live.motion_offset, initial[id]), name .. ": keep-alive preserves the silhouette")
				end
				previous[id] = pos
			end
		end
	end
end

-- Check the defining silhouettes, beyond finiteness and control wiring.
do
	local name = "Rift Gate"
	local mod, cfg = modules[name], copy(config.x2[name])
	cfg.k19 = 1
	local ctx = start(mod, cfg)
	local front, back, throat = 0, 0, 0
	for _, pos in ipairs(cloud(mod, cfg, ctx, 800)) do
		local v = pos - origin - Vector3.new(0, cfg.k17, 0)
		check(math.sqrt(v.X * v.X + v.Y * v.Y) >= cfg.k11 * cfg.k15 / 100 * 0.70, "Rift Gate: open aperture")
		if v.Z > cfg.k12 * 0.48 then front = front + 1 end
		if v.Z < -cfg.k12 * 0.48 then back = back + 1 end
		if math.abs(v.Z) < cfg.k12 * 0.1 then throat = throat + 1 end
	end
	check(front > 100 and back > 100 and throat > 20, "Rift Gate: both mouths and connecting throat populated")
	for count = 1, 6 do
		local scattered = copy(cfg)
		scattered.k19 = count
		local live = start(mod, scattered)
		for gate = 0, count - 1 do
			local positive, negative, middle = 0, 0, 0
			local center = target(mod, scattered, live, gate + 1) - target(mod, scattered, live, 1)
				+ origin + Vector3.new(0, cfg.k17, 0)
			for slot = 1, 384 do
				local id = gate + 1 + (slot - 1) * count
				local pos = target(mod, scattered, live, id) - center
				if pos.Z > cfg.k12 * 0.48 then positive = positive + 1 end
				if pos.Z < -cfg.k12 * 0.48 then negative = negative + 1 end
				if math.abs(pos.Z) < cfg.k12 * 0.1 then middle = middle + 1 end
			end
			check(positive > 70 and negative > 70 and middle > 15, "Rift: complete mouths and throat in gate " .. gate .. "/" .. count)
		end
	end
end
do
	local name = "Phoenix Ascendant"
	local mod, cfg = modules[name], config.x2[name]
	-- The bird rides a Celestial-Ribbon-style Lissajous path, so its parts are
	-- laid out in a moving frame rather than about the raw anchor. Reconstruct
	-- that frame at travel 0 (a fresh start) and project each part back into it
	-- to recover the local wing/tail axes.
	local hover = origin + Vector3.new(0, cfg.k16, 0)
	local function point(th)
		return hover + Vector3.new(math.cos(th * 1.0) * cfg.k18, math.sin(th * 0.577) * cfg.k20, math.sin(th * 1.618) * cfg.k18)
	end
	local center = point(0)
	local fwd = (point(0.05) - center).Unit
	local right = Vector3.new(0, 1, 0):Cross(fwd).Unit
	local up = fwd:Cross(right).Unit
	local left, rightw, tail = 0, 0, 0
	for _, pos in ipairs(cloud(mod, cfg, start(mod, cfg), 800)) do
		local d = pos - center
		local lx, lz = right:Dot(d), fwd:Dot(d)
		if lx < -cfg.k11 * 0.6 then left = left + 1 end
		if lx > cfg.k11 * 0.6 then rightw = rightw + 1 end
		if lz < -cfg.k14 * 0.8 then tail = tail + 1 end
	end
	check(left > 80 and rightw > 80 and tail > 30, "Phoenix: two full wings and trailing feathers")
	for _, rise in ipairs({ 0, 120, 300 }) do
		local vertical = copy(cfg)
		vertical.k18, vertical.k20 = 0, rise
		local live, previous = start(mod, vertical), nil
		for frame = 0, 2400 do
			mod.px(frame / 120, vertical, live, x9, x1)
			local basis = live.pre[name].flight
			check(math.abs(basis.right:Dot(basis.up)) < 1e-9 and math.abs(basis.right:Dot(basis.fwd)) < 1e-9,
				"Phoenix: vertical flight basis stays orthogonal")
			check(math.abs(basis.up.Magnitude - 1) < 1e-9 and finite(basis.pos), "Phoenix: vertical flight stays finite and normalized")
			if previous then check(previous:Dot(basis.fwd) > 0.99, "Phoenix: no frame flip at vertical turnaround") end
			previous = basis.fwd
		end
	end
end
do
	local name = "Astral Kraken"
	local mod, cfg = modules[name], config.x2[name]
	local sectors, head = {}, 0
	for _, pos in ipairs(cloud(mod, cfg, start(mod, cfg), 1000)) do
		local v = pos - origin - Vector3.new(0, cfg.k17, 0)
		if v.Y > cfg.k11 then head = head + 1 end
		if math.sqrt(v.X * v.X + v.Z * v.Z) > cfg.k14 * 0.5 then
			local angle = math.atan2(v.Z, v.X) % (math.pi * 2)
			sectors[math.floor(angle / (math.pi * 2) * cfg.k12)] = true
		end
	end
	local count = 0
	for _ in pairs(sectors) do count = count + 1 end
	check(count == cfg.k12 and head > 80, "Kraken: mantle and arms surround the anchor")
end
do
	local name = "Cosmic Lotus"
	local mod, cfg = modules[name], copy(config.x2[name])
	cfg.k14 = 1
	local function reach(time)
		local sum = 0
		for _, pos in ipairs(cloud(mod, cfg, start(mod, cfg, time), 800)) do
			local v = pos - origin
			sum = sum + math.sqrt(v.X * v.X + v.Z * v.Z)
		end
		return sum
	end
	local smallest, largest = math.huge, 0
	for time = 0, 16 do
		local r = reach(time)
		smallest, largest = math.min(smallest, r), math.max(largest, r)
	end
	check(largest > smallest * 1.5, "Lotus: bloom visibly opens and closes")
end
do
	local name = "Reality Shatter"
	local mod, cfg = modules[name], config.x2[name]
	local ctx = start(mod, cfg)
	local center = origin + Vector3.new(0, cfg.k16, 0)
	local closed = cloud(mod, cfg, ctx, 800)
	mod.px(math.pi / (cfg.k13 * x9.c2), cfg, ctx, x9, x1)
	local burst = cloud(mod, cfg, ctx, 800)
	local before, after = 0, 0
	for i = 1, 800 do
		before = before + (closed[i] - center).Magnitude
		after = after + (burst[i] - center).Magnitude
	end
	check(after > before * 1.8, "Shatter: fragments explode away from the core")
	local pairs_checked = 0
	for i = 1, 760 do
		local j = i + 20
		if (closed[i] - center).Magnitude > cfg.k11 * 0.7 and (closed[j] - center).Magnitude > cfg.k11 * 0.7 then
			check(math.abs((closed[i] - closed[j]).Magnitude - (burst[i] - burst[j]).Magnitude) < 1e-6, "Shatter: each shard stays rigid")
			pairs_checked = pairs_checked + 1
		end
	end
	check(pairs_checked > 400, "Shatter: rigid shard check covers the shell")
	mod.px(math.pi * 2 / (cfg.k13 * x9.c2), cfg, ctx, x9, x1)
	for i, pos in ipairs(cloud(mod, cfg, ctx, 800)) do
		check(math.abs((pos - center).Magnitude - (closed[i] - center).Magnitude) < 1e-6, "Shatter: shell reassembles")
	end
end

-- All six may be loaded at once for previews, blends and Part Control.
do
	local ctx, initial = context(), {}
	for _, name in ipairs(names) do
		modules[name].px(0, config.x2[name], ctx, x9, x1)
		modules[name].px(3, config.x2[name], ctx, x9, x1)
		initial[name] = cloud(modules[name], config.x2[name], ctx, 40)
	end
	modules[names[1]].cleanup(ctx)
	for i = 2, #names do
		local name = names[i]
		check(difference(initial[name], cloud(modules[name], config.x2[name], ctx, 40)) < 1e-7, name .. ": independent state during blending")
	end
end

math.random = random
print(("\n%d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
