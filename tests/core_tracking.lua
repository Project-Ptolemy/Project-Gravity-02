-- Observe the actual core and multi-target positions throughout jumps and
-- transient invalid replication data on both desktop and mobile.
package.path = "tests/?.lua;" .. package.path
local fixture = require("runtime_fixture")
local checks, clock = 0, 10
local function check(value, message) checks = checks + 1; assert(value, message) end
local function near(a, b) return (a - b).Magnitude < 1e-5 end
time = function() return clock end
game.HttpGet = function(_, url)
	local path = assert(url:match("/main/(.-)%?cb="), url)
	local file = assert(io.open(path), path)
	local source = file:read("a"); file:close(); return source
end
local function tick(dt)
	dt = dt or 1 / 60
	clock = clock + dt
	fixture.run.Heartbeat:Fire(dt)
end
local player = fixture.env.LocalPlayer
local root = player.Character.HumanoidRootPart

for _, mobile in ipairs({ false, true }) do
	fixture.input.TouchEnabled, fixture.input.KeyboardEnabled = mobile, not mobile
	assert(loadfile("main.lua"))()
	local context = assert(getgenv()._GRAVITY_CONTEXT)
	local x1, x6 = context.x1, context.x6
	local label = mobile and "mobile: " or "desktop: "
	local observed_center
	context.loaded_shapes["Tracking Probe"] = { AlwaysProcess = true, f2 = function(p, center)
		observed_center = center
		return Vector3.zero, p.Position
	end }
	context.x2["Tracking Probe"] = {}
	x1.k6, x1.k7, x1.AnchorSelf, x1.PredictiveTracking = "Tracking Probe", 1, true, true
	x1.Ki, x1.AngularDamping = 0, 0
	root.Position, root.AssemblyLinearVelocity = Vector3.new(0, 120, 0), Vector3.zero
	context.x4.f4(root.Position)
	local p = Instance.new("BasePart", workspace)
	p.Name, p.Position, p.Size = "TrackingDebris", Vector3.new(20, 120, 0), Vector3.new(4, 2, 2)
	check(context.x4.f1(p), label .. "claims tracking probe")

	for _, fps in ipairs({ 30, 60, 144 }) do
		for _, factor in ipairs({ 0, 150, 500 }) do
			x1.PredictionFactor = factor
			for step = 0, fps do
				local t = step / fps
				local height = math.max(0, 50 * t - 0.5 * 196.2 * t * t)
				local vy = height > 0 and (50 - 196.2 * t) or 0
				root.Position = Vector3.new(16 * t, 120 + height, 0)
				root.AssemblyLinearVelocity = Vector3.new(16, vy, 0)
				tick(1 / fps)
				local expected = root.Position + Vector3.new(16 * factor / 1000, 0, 0)
				check(near(x6.b.Position, expected), label .. "jump prediction keeps actual height at " .. fps .. " Hz / " .. factor .. " ms")
				check(near(observed_center, expected), label .. "held parts see this frame's core instead of the previous frame")
			end
		end
	end
	x1.PredictionFactor = 150
	root.Position, root.AssemblyLinearVelocity = Vector3.new(10, 130, 20), Vector3.new(16, -100, 4)
	x1.Targets, x1.TgtActive, x1.AnchorSelf = { player }, true, false
	x6.pi_targets = { player }
	x6.pi_timer = clock
	tick()
	local predicted = root.Position + Vector3.new(2.4, 0, 0.6)
	check(near(x6.b.Position, predicted) and near(x6.target_positions[1], predicted),
		label .. "target and multi-target prediction use the same height-safe position")
	x1.PredictiveTracking = false
	tick()
	check(near(x6.b.Position, root.Position), label .. "disabling prediction follows exact XYZ position")
	x1.PredictiveTracking, x1.TgtActive, x1.AnchorSelf = true, false, true
	x1.Targets, x6.pi_targets = {}, {}

	for _, velocity in ipairs({ Vector3.new(0 / 0, 0, 0), Vector3.new(math.huge, -math.huge, 0) }) do
		root.AssemblyLinearVelocity = velocity
		tick()
		check(near(x6.b.Position, root.Position), label .. "invalid velocity cannot teleport or hide the core")
	end
	root.AssemblyLinearVelocity = Vector3.new(1e30, -1e30, 1e30)
	tick()
	local lead = x6.b.Position - root.Position
	check(lead.Magnitude <= 37.50001 and lead.Y == 0, label .. "huge finite velocity has a bounded horizontal lead")
	root.AssemblyLinearVelocity = Vector3.new(16, -50, 0)
	for _, factor in ipairs({ -20, 0 / 0, math.huge, "invalid" }) do
		x1.PredictionFactor = factor
		tick()
		local offset = x6.b.Position - root.Position
		check(offset.Y == 0 and offset.X >= 0 and offset.X <= 8, label .. "invalid prediction factors cannot poison the core")
	end
	x1.PredictionFactor = 150
	local last_good, original = x6.b.Position, root.Position
	root.Position = Vector3.new(0 / 0, 0, 0)
	tick()
	check(near(x6.b.Position, last_good), label .. "invalid replicated position retains the last valid core location")
	root.Position, root.AssemblyLinearVelocity = original, Vector3.zero
	tick()
	check(near(x6.b.Position, original), label .. "tracking recovers on the next valid frame")
	-- Platform in the recording reads the local character in its prepass. Bad
	-- world input must be stopped before it poisons shared shape state, too.
	x1.k6 = "Platform"
	tick()
	local platform = assert(x6.pre.Platform)
	local plane, errors_before = platform.pos, x6.physics_error_count or 0
	root.Position = Vector3.new(0 / 0, 0, 0)
	tick()
	check(near(platform.pos, plane), label .. "invalid character physics cannot poison a shape prepass")
	root.Position = original
	tick()
	check(platform.pos.Y == platform.pos.Y and (x6.physics_error_count or 0) == errors_before,
		label .. "the actual Platform recovers without persistent NaN state or shape errors")
	context.destroy()
	p:Destroy()
end
print(checks .. " core tracking integration checks passed")
