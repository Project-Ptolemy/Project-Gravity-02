-- New NDS formations: persistent geometry, real movement and both engine trees.
-- lune run tools/test_luau.luau tests/disaster_shapes.lua
package.path = "tests/?.lua;" .. package.path
local rm = require("robloxmath")
Vector3, CFrame = rm.Vector3, rm.CFrame
Color3 = { fromRGB = function() return {} end }
local config = assert(loadfile("config.lua"))()
local names = assert(loadfile("tests/disaster_catalog.lua"))()
if arg and arg[1] == "vast" then
	for _ = 1, 12 do table.remove(names, 1) end
end
local x9 = { c1 = 0.15, c2 = 0.05 }
local origin = Vector3.new(30, 140, -20)
local sizes = { Vector3.new(4, 2, 2), Vector3.new(12, 1, 8), Vector3.new(2, 18, 2), Vector3.new(40, 2, 16) }
local checks = 0
local function check(ok, message)
	checks = checks + 1
	assert(ok, message)
end
local function finite(v)
	return v and type(v.X) == "number" and type(v.Y) == "number" and type(v.Z) == "number"
		and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < math.huge and math.abs(v.Y) < math.huge and math.abs(v.Z) < math.huge
end
local function near(a, b) return (a - b).Magnitude < 1e-6 end
local function start(mod, c, t)
	local ctx = { pre = {}, n = 160 }
	mod.px(0, c, ctx, x9, config.x1)
	mod.px(t or 0, c, ctx, x9, config.x1)
	return ctx
end
local function sample(mod, c, ctx, id, cen, rec)
	local p = setmetatable({}, {
		__index = { Position = origin, Size = sizes[(id - 1) % #sizes + 1] },
		__newindex = function() error("geometry changed a debris property") end,
	})
	local velocity, target = mod.f2(p, cen or origin, rec or { id = id }, 0, c, config.x1, ctx, x9)
	check(finite(velocity) and finite(target), "finite mixed-debris target and velocity")
	check(near(velocity, (target - p.Position) * (config.x1.k10 * x9.c1)), "force follows target")
	return target
end
local original_random = math.random
math.random = function() error("formation sampling must not reshuffle parts") end
for _, name in ipairs(names) do
	local mod = assert(loadfile("shapes/" .. name .. ".lua"))()
	local c = assert(config.x2[name], "missing catalog entry: " .. name)
	check(mod.ContinuousMotion and mod.AlwaysProcess, name .. ": large formations stay active")
	check(#mod.Controls >= 5 and #mod.Controls <= 8, name .. ": simple controls")
	local keys = {}
	for _, ctl in ipairs(mod.Controls) do
		check(not keys[ctl.Key] and c[ctl.Key] == ctl.Default, name .. ": unique, saved defaults")
		keys[ctl.Key] = true
		check(ctl.Default >= ctl.Min and ctl.Default <= ctl.Max, name .. ": default fits slider")
	end
	local ctx = start(mod, c, 3)
	local baseline, low, high = {}, Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for id = 1, 160 do
		local pos = sample(mod, c, ctx, id)
		baseline[id] = pos
		low = Vector3.new(math.min(low.X, pos.X), math.min(low.Y, pos.Y), math.min(low.Z, pos.Z))
		high = Vector3.new(math.max(high.X, pos.X), math.max(high.Y, pos.Y), math.max(high.Z, pos.Z))
	end
	check((high - low).Magnitude > 200, name .. ": substantial default silhouette with sparse rubble")
	for _, count in ipairs({ 0, 1, 768, 100000 }) do
		ctx.n = count
		for id = 1, 24 do check(near(baseline[id], sample(mod, c, ctx, id)), name .. ": count changes preserve slots") end
	end
	for _, id in ipairs({ 1, 29, 160, 100000003 }) do
		local p = sample(mod, c, ctx, id)
		check(near(p, sample(mod, c, ctx, id, nil, { id = 999, slot = id })), name .. ": preview matches live slot")
		local shift = Vector3.new(65, -18, 42)
		check(near(p + shift, sample(mod, c, ctx, id, origin + shift)), name .. ": follows core")
		ctx.motion_offset = shift
		check(near(p + shift, sample(mod, c, ctx, id)), name .. ": shared keep-alive translation")
		ctx.motion_offset = nil
	end
	mod.px(3, c, ctx, x9, config.x1)
	for id = 1, 24 do check(near(baseline[id], sample(mod, c, ctx, id)), name .. ": duplicate frame holds pose") end
	local frozen = table.clone(c)
	frozen.k13 = 0
	mod.px(1000, frozen, ctx, x9, config.x1)
	for id = 1, 24 do check(near(baseline[id], sample(mod, frozen, ctx, id)), name .. ": speed zero holds current pose") end
	mod.px(1000, c, ctx, x9, config.x1)
	for id = 1, 24 do check(near(baseline[id], sample(mod, c, ctx, id)), name .. ": speed edit has no phase jump") end
	mod.px(997, c, ctx, x9, config.x1)
	local fresh = start(mod, c)
	for id = 1, 24 do check(near(sample(mod, c, fresh, id), sample(mod, c, ctx, id)), name .. ": reverse time retraces pose") end
	local minimum, maximum = table.clone(c), table.clone(c)
	for _, ctl in ipairs(mod.Controls) do
		minimum[ctl.Key], maximum[ctl.Key] = ctl.Min, ctl.Max
		local a, b = table.clone(c), table.clone(c)
		a[ctl.Key], b[ctl.Key] = ctl.Min, ctl.Max
		local ca, cb, difference = start(mod, a, 2), start(mod, b, 2), 0
		for id = 1, 32 do difference = difference + (sample(mod, a, ca, id) - sample(mod, b, cb, id)).Magnitude end
		check(difference > 0.1, name .. ": control changes behavior: " .. ctl.Name)
	end
	for _, extreme in ipairs({ minimum, maximum }) do
		local run = start(mod, extreme)
		for frame = -20, 40 do
			mod.px(frame * 0.31, extreme, run, x9, config.x1)
			for id = 1, 24 do
				check((sample(mod, extreme, run, id) - origin).Magnitude < 6000, name .. ": bounded combined controls")
			end
		end
	end
	local run, initial, previous, distances = start(mod, c), {}, {}, {}
	for id = 1, 80 do initial[id] = sample(mod, c, run, id); previous[id] = initial[id]; distances[id] = 0 end
	local largest_step = 0
	for frame = 1, 720 do
		mod.px(frame / 60, c, run, x9, config.x1)
		for id = 1, 80 do
			local p = sample(mod, c, run, id)
			largest_step = math.max(largest_step, (p - previous[id]).Magnitude)
			distances[id] = math.max(distances[id], (p - initial[id]).Magnitude)
			previous[id] = p
		end
	end
	local moving = 0
	for _, distance in ipairs(distances) do if distance > 30 then moving = moving + 1 end end
	check(moving >= 72, name .. ": dominant motion moves at least 90% of debris over 30 studs")
	check(largest_step < 80, name .. ": no full-shape teleports at 60 Hz (" .. largest_step .. ")")
	local foreign = {}
	run.pre.other = foreign
	mod.cleanup(run); mod.cleanup(run); mod.cleanup({})
	check(run.pre[name] == nil and run.pre.other == foreign, name .. ": isolated repeatable cleanup")
	mod.px(10000, c, run, x9, config.x1)
	for id = 1, 24 do check(near(initial[id], sample(mod, c, run, id)), name .. ": clean reentry") end
	sample(mod, c, { pre = {} }, 1)
	print(name .. ": geometry, controls, time reversal, continuous movement and cleanup passed")
end
math.random = original_random

-- Execute the actual selector, loader and velocity loop for both device trees.
local fixture = require("runtime_fixture")
local clock = 10
time = function() return clock end
game.HttpGet = function(_, url)
	local path = assert(url:match("/main/(.-)%?cb="), url)
	local file = assert(io.open(path), path)
	local source = file:read("a"); file:close(); return source
end
for _, mobile in ipairs({ false, true }) do
	fixture.input.TouchEnabled, fixture.input.KeyboardEnabled = mobile, not mobile
	assert(loadfile("main.lua"))()
	local live = assert(getgenv()._GRAVITY_CONTEXT)
	live.x4.f4(Vector3.new(0, 160, 0))
	for _, name in ipairs(names) do
		check(live.x4.switch_shape(name, false), name .. ": desktop/mobile selector accepts shape")
		assert(live.get_shape(name))
		local pieces = {}
		for id = 1, 12 do
			local p = Instance.new("BasePart", workspace)
			p.Position, p.Size = Vector3.new(50 + id, 170, 0), sizes[(id - 1) % #sizes + 1]
			check(live.x4.f1(p), name .. ": engine claims mixed rubble")
			-- Roblox initializes this to zero; the permissive fixture has no
			-- class-specific property defaults before the first update bucket.
			live.x6.a[p].lv.VectorVelocity = Vector3.zero
			pieces[id] = p
		end
		local traversed = {}
		for frame = 1, 120 do
			clock = clock + 1 / 60
			fixture.run.Heartbeat:Fire(1 / 60)
			for _, p in ipairs(pieces) do
				local record = assert(live.x6.a[p])
				local velocity = record.lv.VectorVelocity
				check(finite(velocity), name .. ": actual engine issues finite commands")
				traversed[p] = (traversed[p] or 0) + velocity.Magnitude / 60
				p.AssemblyLinearVelocity = velocity
				p.Position = p.Position + velocity / 60
			end
		end
		for _, p in ipairs(pieces) do
			check(traversed[p] > 30, name .. ": engine commands active travel")
			p:Destroy()
		end
	end
	live.destroy()
	print((mobile and "Mobile" or "Desktop") .. ": all " .. #names .. " shapes load, switch and drive debris")
end
print(checks .. " disaster formation checks passed")
