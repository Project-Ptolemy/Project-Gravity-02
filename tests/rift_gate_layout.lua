package.path = "tests/?.lua;" .. package.path
require("robloxenv")
local Rift = assert(loadfile("shapes/Rift Gate.lua"))()
local config = assert(loadfile("config.lua"))()
local x1, x9 = config.x1, { c1 = 0.15, c2 = 0.05 }
local origin = Vector3.new(31, 70, -29)
local part = { Position = origin }
local checks = 0
local function check(ok, label) checks = checks + 1; assert(ok, label) end
local function near(a, b) return (a - b).Magnitude < 1e-6 end
local function sample(c, ctx, gate, slot, t)
	local id = gate + 1 + ((slot or 1) - 1) * c.k19
	local velocity, target = Rift.f2(part, origin, { id = id }, t or 0, c, x1, ctx, x9)
	check(target.Magnitude < math.huge and near(velocity, (target - part.Position) * x1.k10 * x9.c1), "finite target and matching velocity")
	return target
end

-- Corresponding slots have identical anatomy, so their difference measures the
-- placement independently of the module's internal layout representation.
local reference = {}
for count = 1, 6 do
	local c, ctx = table.clone(config.x2["Rift Gate"]), { pre = {} }
	c.k19 = count
	Rift.px(0, c, ctx, x9)
	local primary = sample(c, ctx, 0)
	local offsets = { Vector3.zero }
	local extent = math.sqrt((c.k11 * 1.15) ^ 2 + (c.k12 * 0.5 + c.k11 * 0.12) ^ 2)
	for gate = 1, count - 1 do
		local offset = sample(c, ctx, gate) - primary
		if reference[gate] then check(near(offset, reference[gate]), "changing the count keeps existing placements") end
		reference[gate] = offset
		for _, other in ipairs(offsets) do
			local delta = offset - other
			check(math.sqrt(delta.X ^ 2 + delta.Z ^ 2) > extent * 2, "whole gates are separated horizontally")
		end
		offsets[#offsets + 1] = offset
		for slot = 2, 32 do
			check(near(sample(c, ctx, gate, slot) - sample(c, ctx, 0, slot), offset), "every part shares its gate's placement")
		end
	end
	local one = table.clone(c); one.k19 = 1
	check(near(primary, sample(one, { pre = {} }, 0)), "the primary gate retains its original placement")
	for _, t in ipairs({ 0.2, 1, 5, -2 }) do
		Rift.px(t, c, ctx, x9)
		for gate = 1, count - 1 do
			check(near(sample(c, ctx, gate) - sample(c, ctx, 0), reference[gate]), "animation and reverse time do not reroll placements")
		end
	end
	Rift.cleanup(ctx)
	Rift.px(0, c, ctx, x9)
	check(near(primary, sample(c, ctx, 0)), "cleanup and preview rebuild retain deterministic placement")
end
check(math.abs(reference[1].Y - reference[2].Y) > 1, "extra rifts have varied heights")
check(math.abs(reference[1].Magnitude - reference[2].Magnitude) > 1, "scatter distances vary")

-- Neither large or tilted tunnels nor negative hover/drift may put any part of
-- an additional gate below the horizontal plane through the shape's center.
for _, pitch in ipairs({ 0, 45, 90, 180, 270, 350 }) do
	for _, spacing in ipairs({ 0, 600 }) do
		local c, ctx = table.clone(config.x2["Rift Gate"]), { pre = {}, motion_offset = Vector3.new(-12, -1.5, 6) }
		c.k11, c.k12, c.k17, c.k19, c.k20 = 300, 600, -100, 6, spacing
		c.k21, c.k22, c.k23 = 137, pitch, 219
		Rift.px(0, c, ctx, x9)
		for _, t in ipairs({ 0, 0.4, 2 }) do
			Rift.px(t, c, ctx, x9)
			local primary, offsets = sample(c, ctx, 0), { Vector3.zero }
			for gate = 1, 5 do
				local offset = sample(c, ctx, gate) - primary
				for _, other in ipairs(offsets) do
					local delta = offset - other
					check(math.sqrt(delta.X ^ 2 + delta.Z ^ 2) > 2 * math.sqrt(345 ^ 2 + 336 ^ 2), "extreme rotated gates cannot overlap at zero spacing")
				end
				offsets[#offsets + 1] = offset
				for slot = 1, 128 do
					check(sample(c, ctx, gate, slot, t).Y >= origin.Y, "all additional rift targets stay above the center's horizontal plane")
				end
			end
		end
	end
end
-- Large scattered gates must keep tracking beyond the normal distance cull.
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
	live.x1.k6, live.x1.k7 = "Rift Gate", 1
	local c = live.x2["Rift Gate"]
	c.k11, c.k12, c.k17, c.k19 = 300, 600, 500, 3
	live.x4.f4(Vector3.new(0, 120, 0))
	clock = clock + 1 / 60
	fixture.run.Heartbeat:Fire(1 / 60)
	local rubble = Instance.new("BasePart", workspace)
	rubble.Position, rubble.Size = Vector3.new(50, 125, 0), Vector3.new(4, 2, 2)
	check(live.x4.f1(rubble), "engine claims rift test debris")
	local d = live.x6.a[rubble]
	d.id = 18 -- gate 2, local slot 6
	local _, target = live.get_shape("Rift Gate").f2(rubble, live.x6.b.Position, d,
		live.x6.shape_clock, c, live.x1, live.x6, live.x9)
	check((target - live.x6.b.Position).Magnitude > live.x1.k1, "test gate extends beyond the normal processing radius")
	rubble.Position = target + Vector3.new(5, 0, 0)
	clock = clock + 1 / 60
	fixture.run.Heartbeat:Fire(1 / 60)
	check(not d.parked and d.lv.VectorVelocity.Magnitude > 0.1,
		(mobile and "mobile" or "desktop") .. ": distant gate debris keeps tracking")
	live.destroy()
	rubble:Destroy()
end
print(checks .. " rift placement checks passed")
