package.path = "tests/?.lua;" .. package.path
require("robloxenv")
local Controls = assert(loadfile("PluginControls.lua"))()
local Physics = assert(loadfile("ShapePhysics.lua"))()
local BlackHoleV2 = assert(loadfile("shapes/Black Hole v2.lua"))()
local Drop = assert(loadfile("shapes-onreview/Drop.lua"))()
local config = assert(loadfile("config.lua"))()
local x1, x9 = config.x1, { c1 = 0.15, c2 = 0.05 }
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function near(a, b, epsilon) return (a - b).Magnitude < (epsilon or 1e-6) end
local function finite(v) return v and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6 end
local function action(module, key, c, ctx)
	for _, control in ipairs(module.Controls) do
		if control.Key == key then return Controls.activate(control, c, ctx, x1) end
	end
	error("missing action " .. key)
end
local function fixture()
	local p = { Position = Vector3.new(120, 55, 20), AssemblyLinearVelocity = Vector3.new(8, 6, -1),
		AssemblyAngularVelocity = Vector3.zero, CanCollide = false, Anchored = false }
	local original = { density = 0.9 }
	local d = { id = 23, original_can_collide = true, original_anchored = false, original_properties = original,
		lv = { Enabled = true, MaxForce = x1.k4 }, av = { Enabled = true, MaxTorque = math.huge } }
	local ctx = { pre = {}, a = { [p] = d }, b = { Position = Vector3.zero } }
	ctx.apply_shape_physics = function(part, record) return Physics.apply(part, record, x1) end
	return p, d, ctx, original
end

local seeded = Controls.defaults({
	{ Type = "Button", Key = "go", Default = 999 }, { Type = "Toggle", Key = "toggle" },
	{ Type = "TextBox", Key = "text" }, { Type = "Slider", Key = "scaled", Div = 10, Default = 1.6 },
	{ Type = "Slider", Key = "min", Div = 10, Min = 20 },
})
check(seeded.go == nil and seeded.toggle == false and seeded.text == "", "actions have no saved value; typed defaults")
check(seeded.scaled == 1.6 and seeded.min == 2, "Default uses stored units and Min uses display units")
local calls, context = 0, {}
local control = { Type = "Button", Callback = function() calls = calls + 1; coroutine.yield() end }
local thread = coroutine.create(function() Controls.activate(control, {}, context, {}) end)
coroutine.resume(thread)
check(not Controls.activate(control, {}, context, {}) and calls == 1, "double tap cannot duplicate a pending callback")
coroutine.resume(thread)
check(context.button_busy[control] == nil, "button unlocks after completion")
control.Callback = function() error("expected test failure") end
check(not Controls.activate(control, {}, context, {}) and context.button_busy[control] == nil, "callback errors are contained")
context.torn_down = true
control.Callback = function() calls = calls + 1 end
Controls.activate(control, {}, context, {})
check(calls == 1, "closed sessions reject callbacks")

local c = config.x2["Black Hole v2"]
local p, d, ctx, original = fixture()
BlackHoleV2.px(0, c, ctx)
local vel, target = BlackHoleV2.f2(p, Vector3.zero, d, 0, c, x1, ctx, x9)
check(near(target, p.Position) and near(vel, Vector3.zero), "capture begins at the current position")
local incoming = p.AssemblyLinearVelocity
action(BlackHoleV2, "rwRelease", c, ctx)
check(d.free_physics and not d.lv.Enabled and not d.av.Enabled and d.lv.MaxForce == 0, "Stop disables both actuators immediately")
check(p.CanCollide and p.CustomPhysicalProperties == original and near(p.AssemblyLinearVelocity, incoming), "Stop restores properties and preserves momentum")
p.Position = p.Position + Vector3.new(16, -20, 2)
action(BlackHoleV2, "rwRegrab", c, ctx)
BlackHoleV2.px(0.1, c, ctx)
vel, target = BlackHoleV2.f2(p, Vector3.zero, d, 0.1, c, x1, ctx, x9)
Physics.apply(p, d, x1)
check(near(target, p.Position) and d.lv.Enabled and d.av.Enabled, "Regrab recaptures the live location and rearms actuators")
check(not p.CanCollide and d.integral.Magnitude == 0, "Regrab clears old feedback and applies noclip")
action(BlackHoleV2, "rwExplode", c, ctx)
local impulse = p.AssemblyLinearVelocity
check(impulse:Dot(p.Position) > 0 and impulse.Magnitude >= 300 and impulse.Magnitude <= 500, "explosion applies a bounded outward impulse")
p.AssemblyLinearVelocity = impulse + Vector3.new(0, -12, 0)
BlackHoleV2.f2(p, Vector3.zero, d, 0.1, c, x1, ctx, x9)
Physics.apply(p, d, x1)
check(near(p.AssemblyLinearVelocity, impulse + Vector3.new(0, -12, 0)), "subsequent frames do not overwrite ballistic gravity")
for i = 1, 120 do BlackHoleV2.px(0.1 + i / 60, c, ctx) end
check(p.CanCollide, "explosion expiry restores collisions without waiting for another part update")
BlackHoleV2.f2(p, Vector3.zero, d, 2.1, c, x1, ctx, x9)
Physics.apply(p, d, x1)
check(ctx.pre["Black Hole v2"].state == "release" and p.CanCollide, "explosion restores collisions after its coast interval")
check(not d.lv.Enabled and not d.av.Enabled, "released parts stay free of active forces")

-- Pull progress is independent of the engine's per-part update stride.
local fast, fast_d, fast_ctx = fixture()
local slow, slow_d, slow_ctx = fixture()
for _, item in ipairs({ { fast, fast_d, fast_ctx }, { slow, slow_d, slow_ctx } }) do
	BlackHoleV2.px(0, c, item[3]); BlackHoleV2.f2(item[1], Vector3.zero, item[2], 0, c, x1, item[3], x9)
end
local fast_target, slow_target
for frame = 1, 1200 do
	local t = frame / 60
	BlackHoleV2.px(t, c, fast_ctx); BlackHoleV2.px(t, c, slow_ctx)
	local _, pos = BlackHoleV2.f2(fast, Vector3.zero, fast_d, t, c, x1, fast_ctx, x9)
	fast_target = pos
	if frame % 10 == 0 then
		_, slow_target = BlackHoleV2.f2(slow, Vector3.zero, slow_d, t, c, x1, slow_ctx, x9)
	end
end
check(finite(fast_target) and finite(slow_target) and near(fast_target, slow_target, 2), "bucketed parts reach the same core on time")
BlackHoleV2.cleanup(ctx); BlackHoleV2.cleanup(ctx)
check(ctx.pre["Black Hole v2"] == nil, "cleanup is repeatable")
d.free_physics, d.collisions = nil, nil
Physics.apply(p, d, x1)
check(d.lv.Enabled and not d.free_active, "another shape can recover released records")

local spinning, spin_d, spin_ctx = fixture()
spin_d.id = 1 -- core role
BlackHoleV2.px(0, c, spin_ctx)
BlackHoleV2.f2(spinning, Vector3.zero, spin_d, 0, c, x1, spin_ctx, x9)
local ball_points = {}
for frame = 1, 240 do
	BlackHoleV2.px(frame / 60, c, spin_ctx)
	local _, point = BlackHoleV2.f2(spinning, Vector3.zero, spin_d, frame / 60, c, x1, spin_ctx, x9)
	if frame > 180 then ball_points[#ball_points + 1] = point end
end
Physics.apply(spinning, spin_d, x1)
-- Dense Spin-style motion uses independent tilted positional orbits. Driving
-- every piece's angular motor adds contact work without improving that motion.
check(c.rwBallSpin >= 360, "the default core completes at least one revolution per second")
check(spin_d.angular_velocity == nil and not spin_d.angular_active,
	"dense motion needs no per-part angular motor request")
local radius0, ymin, ymax = ball_points[1].Magnitude, ball_points[1].Y, ball_points[1].Y
local steady = true
for _, point in ipairs(ball_points) do
	if math.abs(point.Magnitude - radius0) > 1e-3 then steady = false end
	ymin, ymax = math.min(ymin, point.Y), math.max(ymax, point.Y)
end
check(steady and ymax - ymin > radius0 * 0.2, "a settled part keeps its radius while spinning through three dimensions")
-- One slider controls the spin speed.
local speed_control = table.clone(c)
speed_control.rwBallSpin = 360
local phase = spin_ctx.pre["Black Hole v2"].ball_angle
BlackHoleV2.px(4.1, speed_control, spin_ctx)
check(math.abs(spin_ctx.pre["Black Hole v2"].ball_angle - phase - math.rad(360) * 0.1) < 1e-6,
	"the slider changes orbit speed without resetting its phase")
speed_control.rwBallSpin = 0
local _, still = BlackHoleV2.f2(spinning, Vector3.zero, spin_d, 4.1, speed_control, x1, spin_ctx, x9)
BlackHoleV2.px(4.2, speed_control, spin_ctx)
local _, held = BlackHoleV2.f2(spinning, Vector3.zero, spin_d, 4.2, speed_control, x1, spin_ctx, x9)
check(near(still, held), "zero ball spin stops both tilted orbit and precession")

-- Isolate the approach from the optional ball radius, tilt and ring.
local approach = table.clone(c)
approach.rwBall, approach.rwTilt, approach.rwRing = 0, 0, 0
local spiral, spiral_d, spiral_ctx = fixture()
BlackHoleV2.px(0, approach, spiral_ctx)
BlackHoleV2.f2(spiral, Vector3.zero, spiral_d, 0, approach, x1, spiral_ctx, x9)
local radius, turns = spiral.Position.Magnitude, 0
local previous_angle = spiral_d.black_hole_v2.angle
for frame = 1, 240 do
	BlackHoleV2.px(frame / 60, approach, spiral_ctx)
	local _, point = BlackHoleV2.f2(spiral, Vector3.zero, spiral_d, frame / 60, approach, x1, spiral_ctx, x9)
	check(point.Magnitude <= radius + 1e-5, "spiral continuously converges toward the center")
	radius = point.Magnitude
	turns = turns + math.abs(spiral_d.black_hole_v2.angle - previous_angle)
	previous_angle = spiral_d.black_hole_v2.angle
end
check(radius < 1e-6 and turns > math.pi, "approach winds around the center and reaches it")
local function pull_radius(speed)
	local part, data, run = fixture()
	local cfg = table.clone(approach); cfg.rwPull = speed
	BlackHoleV2.px(0, cfg, run)
	BlackHoleV2.f2(part, Vector3.zero, data, 0, cfg, x1, run, x9)
	local point
	for frame = 1, 60 do
		BlackHoleV2.px(frame / 60, cfg, run)
		_, point = BlackHoleV2.f2(part, Vector3.zero, data, frame / 60, cfg, x1, run, x9)
	end
	return point.Magnitude, part.Position.Magnitude
end
local stopped, original_radius = pull_radius(0)
check(math.abs(stopped - original_radius) < 1e-6, "zero pull speed holds the current spiral radius")
check(pull_radius(80) < pull_radius(20), "higher pull speed brings parts to the center sooner")

local ride, ride_d = fixture()
ride_d.original_properties, ride_d.original_can_collide = nil, false
ride_d.free_physics = true
Physics.apply(ride, ride_d, x1)
ride_d.free_physics, ride_d.pc_ride = nil, true
Physics.apply(ride, ride_d, x1)
check(ride.CanCollide and ride.CustomPhysicalProperties[1] > 0.1,
	"rearming a rideable part restores its supporting collision and density")

local dc = Controls.defaults(Drop.Controls)
p, d, ctx = fixture()
local start = p.Position
Drop.px(0, dc, ctx)
vel, target = Drop.f2(p, Vector3.zero, d, 0, dc, x1, ctx, x9)
check(near(start, p.Position) and near(start, target) and not d.unclaim, "Drop starts with a smooth gather, without teleporting")
for i = 1, 60 do Drop.px(i / 60, dc, ctx) end
vel, target = Drop.f2(p, Vector3.zero, d, 1, dc, x1, ctx, x9)
check(not near(target, start) and finite(target) and not d.unclaim, "Drop lifts toward the canopy before releasing")
action(Drop, "dpDrop", dc, ctx)
for i = 61, 180 do Drop.px(i / 60, dc, ctx) end
vel, target = Drop.f2(p, Vector3.zero, d, 3, dc, x1, ctx, x9)
check(d.unclaim and d.release_velocity.Y == -dc.dpDown, "Drop Now ends in an explicit downward release")
check(near(start, p.Position), "Drop never writes the part transform")
Drop.cleanup(ctx); Drop.cleanup(ctx)
print(checks .. " plugin action and release checks passed")
