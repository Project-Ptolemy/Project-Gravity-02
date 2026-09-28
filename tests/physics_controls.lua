-- Exercise the actual desktop/mobile constraint loop. The fixture integrates
-- commanded velocities; Roblox contact solving and network ownership need a live
-- client, but bypassed controls, feedback instability and target lag are observable.
package.path = "tests/?.lua;" .. package.path
local fixture = require("runtime_fixture")
local Physics = assert(loadfile("ShapePhysics.lua"))()
local checks, clock = 0, 10
local function check(value, message) checks = checks + 1; assert(value, message) end
local function finite(v)
	return v and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end
local function near(a, b, tolerance) return (a - b).Magnitude < (tolerance or 1e-6) end
time = function() return clock end
game.HttpGet = function(_, url)
	local path = assert(url:match("/main/(.-)%?cb="), url)
	local file = assert(io.open(path), path)
	local source = file:read("a"); file:close(); return source
end
local function tick(dt)
	clock = clock + dt
	fixture.run.Heartbeat:Fire(dt)
end

-- Preservation is a user policy: shape-specific noclip must not erase it, and
-- neither preserving nor releasing may create collisions on a noncollidable part.
for _, original in ipairs({ false, true }) do
	for _, disabled in ipairs({ false, true }) do
		for _, free in ipairs({ false, true }) do
			local part, data = { CanCollide = not original }, {
				original_can_collide = original, free_physics = free, collisions = false,
			}
			Physics.apply_collisions(part, data, { Disabled = disabled, PreserveCollisions = true })
			check(part.CanCollide == original, "preservation wins shape noclip and retains the original flag")
			data.collisions = nil
			Physics.apply_collisions(part, data, { Disabled = disabled, PreserveCollisions = false })
			check(part.CanCollide == (original and (disabled or free)), "ordinary held/released/disabled collision policy")
		end
	end
end

for _, mobile in ipairs({ false, true }) do
	fixture.input.TouchEnabled, fixture.input.KeyboardEnabled = mobile, not mobile
	assert(loadfile("main.lua"))()
	local context = assert(getgenv()._GRAVITY_CONTEXT)
	local x1, x6 = context.x1, context.x6
	local label = mobile and "mobile" or "desktop"
	local target = Vector3.new(20, 120, 0)
	local mod = { AlwaysProcess = true, f2 = function(p)
		return (target - p.Position) * 3, target
	end }
	context.loaded_shapes["Physics Control Probe"] = mod
	context.x2["Physics Control Probe"] = {}
	x1.k6, x1.k7, x1.k8, x1.Ki, x1.MaxSpeed = "Physics Control Probe", 1, 1, 0, 5000
	x1.AngularDamping, x1.VerticalStiffness = 0, 1
	context.x4.f4(Vector3.new(0, 120, 0))
	tick(1 / 60)
	local part = Instance.new("BasePart", workspace)
	part.Position, part.Size = Vector3.new(0, 120, 0), Vector3.new(4, 2, 2)
	check(context.x4.f1(part), label .. ": engine claims the physics probe")
	local data = x6.a[part]
	local function reset(damping, override)
		data.last_target_pos, data.sys_last_t, data.integral = nil, nil, Vector3.zero
		data.vl, data.trans_vl, data.pc_mode = nil, nil, nil
		data.pc_phys = override ~= nil and { Damping = override } or nil
		part.Position, part.AssemblyLinearVelocity = Vector3.new(0, 120, 0), Vector3.new(100, 0, 0)
		target = Vector3.new(20, 120, 0)
		x1.Damping = damping
	end
	for _, tracking in ipairs({ false, true }) do
		mod.FrameTracking = tracking
		local mode = tracking and "frame tracking" or "ordinary attraction"
		for _, fidelity in ipairs({ "default", "Force Smooth", "Max Fidelity" }) do
			x1["Force Smooth (Lags)"] = fidelity == "Force Smooth"
			x1.MaxFidelity = fidelity == "Max Fidelity"
			for _, fps in ipairs({ 30, 60, 144 }) do
				local dt = 1 / fps
				local message = label .. ", " .. mode .. ", " .. fidelity .. ", " .. fps .. " Hz: "
				reset(0)
				tick(dt)
				local undamped = data.lv.VectorVelocity
				reset(5)
				tick(dt)
				local damped = data.lv.VectorVelocity
				check(finite(damped) and damped.X > 0 and damped.X < undamped.X * 0.8,
					message .. "global damping visibly reduces recovery without reversing")
				reset(5, 0)
				tick(dt)
				check(near(data.lv.VectorVelocity, undamped), message .. "per-part damping zero overrides the global value")
				reset(0, 5)
				tick(dt)
				check(near(data.lv.VectorVelocity, damped), message .. "per-part damping applies independently of global damping")
				for _, damping in ipairs({ 0, 0.5, 1, 5 }) do
					reset(damping)
					local previous, stable = 20, true
					for _ = 1, fps do
						tick(dt)
						local velocity = data.lv.VectorVelocity
						part.AssemblyLinearVelocity = velocity
						part.Position = part.Position + velocity * dt
						local remaining = target.X - part.Position.X
						if not finite(velocity) or remaining < -1e-6 or remaining > previous + 1e-6 then stable = false end
						previous = remaining
					end
					check(stable and previous < 20, message .. "damping " .. damping .. " converges without oscillation")
				end

				-- Once acquired, damping must reduce error correction without slowing
				-- the target's own movement; this is essential for dense spinning cores.
				reset(5)
				part.Position, part.AssemblyLinearVelocity = target, Vector3.zero
				tick(dt)
				local follows = true
				for _ = 1, fps * 2 do
					target = target + Vector3.new(15 * dt, 0, 0)
					tick(dt)
					local velocity = data.lv.VectorVelocity
					part.AssemblyLinearVelocity = velocity
					part.Position = part.Position + velocity * dt
					if not finite(velocity) or (tracking and not near(part.Position, target, 1e-4)) then follows = false end
				end
				check(follows and math.abs(data.lv.VectorVelocity.X - 15) < 1,
					message .. "damping retains movement feedforward")
			end
		end
	end

	-- Exercise the shipped combination too: integral feedback and delayed sweeps
	-- can expose interactions hidden by a snap-smoothing, zero-integral probe.
	mod.FrameTracking = false
	x1.k7, x1.k8, x1.Ki = 4, 0.8, 0.1
	x1.MaxFidelity, x1["Force Smooth (Lags)"] = false, false
	for _, damping in ipairs({ 0, 5 }) do
		reset(damping)
		local stable = true
		for _ = 1, 60 * 12 do
			tick(1 / 60)
			local velocity = data.lv.VectorVelocity
			part.AssemblyLinearVelocity = velocity
			part.Position = part.Position + velocity / 60
			if not finite(velocity) or (part.Position - target).Magnitude > 40 then stable = false end
		end
		check(stable and (part.Position - target).Magnitude < 3,
			label .. ": damping " .. damping .. " settles with default integral, smoothing and buckets")
	end
	x1.k7, x1.k8, x1.Ki = 1, 1, 0

	-- The public setting hook must work immediately while paused, then survive
	-- a running Black Hole update with either legacy value of its noclip setting.
	x1.k6, x1.MaxFidelity, x1["Force Smooth (Lags)"] = "Black Hole v2", false, false
	reset(0.5)
	tick(1 / 60)
	for _, noclip in ipairs({ false, true }) do
		context.x2["Black Hole v2"].rwNoclip = noclip
		for _, preserve in ipairs({ false, true }) do
			x1.Paused, x1.PreserveCollisions = true, preserve
			context.controls.apply_settings({ PreserveCollisions = preserve })
			check(part.CanCollide == preserve, label .. ": preservation changes immediately while Black Hole is paused")
			x1.Paused = false
			tick(1 / 60)
			check(part.CanCollide == preserve, label .. ": gathering respects preservation for either noclip setting")
		end
	end
	-- Ride assignment, toggling and release use the same policy immediately,
	-- including originally noncolliding pieces and disabled constraints.
	for _, original in ipairs({ false, true }) do
		local ride = Instance.new("BasePart", workspace)
		ride.Position, ride.Size, ride.CanCollide = Vector3.new(10, 125, 10), Vector3.new(4, 2, 2), original
		check(context.x4.f1(ride), label .. ": claims ride collision probe")
		local record = x6.a[ride]
		x6.pc_selected[ride] = true
		for _, preserve in ipairs({ false, true }) do
			for _, disabled in ipairs({ false, true }) do
				x1.PreserveCollisions = preserve
				context.x4.apply_disabled(disabled)
				local ride_collision = not (preserve or disabled) or original
				x6.pc_set_ride(true)
				check(ride.CanCollide == ride_collision, label .. ": ride toggle honors original preservation/disabled flag")
				x6.pc_set_ride(false)
				check(ride.CanCollide == (original and (preserve or disabled)), label .. ": clearing ride honors collision policy")
				x6.pc_assign("pin", { ride = true })
				check(ride.CanCollide == ride_collision, label .. ": ride assignment honors collision policy")
				x6.pc_release(ride)
				check(ride.CanCollide == (original and (preserve or disabled)), label .. ": release honors collision policy")
			end
		end
		context.x4.apply_disabled(false)
		x1.PreserveCollisions = false
		record.free_physics = true
		context.shape_physics.apply(ride, record, x1)
		x6.pc_set_ride(true)
		x6.pc_set_ride(false)
		check(ride.CanCollide == original and ride.CustomPhysicalProperties == record.original_properties,
			label .. ": ride toggling a free part retains original physics")
		x6.pc_selected[ride] = nil
		context.x4.f2(ride)
		ride:Destroy()
	end
	context.destroy()
	part:Destroy()
end
print(checks .. " physics control and damping integration checks passed")
