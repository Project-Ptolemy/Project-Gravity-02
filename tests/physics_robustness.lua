-- Run the real desktop/mobile Heartbeat with malformed plugin results and
-- controller transitions. The fixture observes commands, not Roblox contacts.
package.path = "tests/?.lua;" .. package.path
local fixture = require("runtime_fixture")
local Physics = assert(loadfile("ShapePhysics.lua"))()
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

check(Physics.clamp_velocity(Vector3.new(1e30, -1e30, 1e30), 25).Magnitude <= 25.00001,
	"huge finite velocities clamp without squared-magnitude overflow")
check(Physics.clamp_velocity(Vector3.new(0 / 0, 1, 0), 25) == nil, "NaN velocity is rejected")
check(Physics.clamp_velocity(Vector3.new(math.huge, 1, 0), 25) == nil, "infinite velocity is rejected")
check(Physics.clamp_velocity("wrong type", 25) == nil, "non-vector velocity is rejected")

for _, mobile in ipairs({ false, true }) do
	fixture.input.TouchEnabled, fixture.input.KeyboardEnabled = mobile, not mobile
	assert(loadfile("main.lua"))()
	local context = assert(getgenv()._GRAVITY_CONTEXT)
	local x1, x6 = context.x1, context.x6
	local label = mobile and "mobile: " or "desktop: "
	local mod = { AlwaysProcess = true }
	local function good(p) return Vector3.new(60, 0, 0), p.Position + Vector3.new(20, 0, 0) end
	mod.f2 = good
	context.loaded_shapes["Robustness Probe"], context.x2["Robustness Probe"] = mod, {}
	x1.k6, x1.k7, x1.k8, x1.Ki, x1.Damping, x1.MaxSpeed = "Robustness Probe", 1, 1, 0, 0, 25
	x1.AngularDamping, x1.VerticalStiffness = 0, 1
	context.x4.f4(Vector3.new(0, 120, 0))
	tick()
	local parts, data = {}, {}
	for i = 1, 3 do
		local part = Instance.new("BasePart", workspace)
		part.Name, part.Position, part.Size = "Probe" .. i, Vector3.new(i * 20, 120, 0), Vector3.new(4, 2, 2)
		check(context.x4.f1(part), label .. "claims probe " .. i)
		parts[i], data[i] = part, x6.a[part]
	end
	for _, tracking in ipairs({ false, true }) do
		mod.FrameTracking = tracking
		tick()
		for i = 1, 3 do check(near(data[i].lv.VectorVelocity, Vector3.new(25, 0, 0)), label .. "exact target respects Max Speed") end
	end
	mod.FrameTracking = false
	for _, stride in ipairs({ 0, -3, 2.5, 0 / 0, math.huge }) do
		local visited = {}
		mod.f2 = function(p) visited[p] = true; return good(p) end
		x1.k7 = stride
		for _ = 1, 4 do tick() end
		check(visited[parts[1]] and visited[parts[2]] and visited[parts[3]], label .. "invalid update stride cannot starve a bucket")
	end
	x1.k7 = 1
	local errors_before = x6.physics_error_count or 0
	mod.f2 = function() return Vector3.zero end
	for _, smoothing in ipairs({ -3, 2, 0 / 0, math.huge }) do
		x1.k8 = smoothing
		data[1].pc_phys = { k8 = smoothing }
		for _, d in ipairs(data) do d.vl = Vector3.new(10, 0, 0) end
		tick()
		for _, d in ipairs(data) do
			check(Physics.finite_vector(d.lv.VectorVelocity) and d.lv.VectorVelocity.X >= 0 and d.lv.VectorVelocity.X <= 10.00001,
				label .. "invalid smoothing never extrapolates velocity")
		end
	end
	check((x6.physics_error_count or 0) == errors_before, label .. "bad settings recover without failing a physics frame")
	x1.k8, data[1].pc_phys, mod.f2 = 1, nil, good
	for _, d in ipairs(data) do Physics.clear_tracking(d) end
	local water = Instance.new("BasePart", workspace)
	water.Name, water.Position, water.Size = "WaterLevel", Vector3.new(0, 150, 0), Vector3.new(20, 2, 20)
	x1.MaxFidelity = true
	tick()
	check(data[1].lv.VectorVelocity.Y > 0 and data[1].lv.VectorVelocity.Magnitude <= 25.00001,
		label .. "water lift respects the final speed cap")
	water.Name = "RemovedWaterLevel" -- base workspace fixture retains destroyed child entries
	water:Destroy()
	tick()
	x1.MaxFidelity = false
	x6.water_level = false

	local bad_part = parts[2]
	local failures = {
		function() error("part-specific callback failure") end,
		function() return "bad velocity" end,
		function() return Vector3.new(0 / 0, 0, 0) end,
		function() return Vector3.new(math.huge, 0, 0) end,
		function() return Vector3.zero, "bad target" end,
		function() return Vector3.zero, Vector3.new(0, math.huge, 0) end,
	}
	for _, failure in ipairs(failures) do
		mod.f2 = function(p) if p == bad_part then return failure() end; return good(p) end
		for _, d in ipairs(data) do d.lv.VectorVelocity, d.vl = Vector3.new(200, 0, 0), Vector3.new(200, 0, 0) end
		tick()
		check(near(data[2].lv.VectorVelocity, Vector3.zero), label .. "bad part halts its previous command")
		check(data[2].last_target_pos == nil and data[2].integral.Magnitude == 0, label .. "bad result clears feedback memory")
		check(data[1].lv.VectorVelocity.X > 0 and data[3].lv.VectorVelocity.X > 0, label .. "healthy parts still update after callback failure")
	end
	check(x6.physics_error and x6.physics_error.shape == "Robustness Probe", label .. "runtime error identifies the shape")
	mod.f2 = good
	tick()
	check(data[2].lv.VectorVelocity.X > 0, label .. "corrected callback recovers on the next frame")

	local assigned = { f2 = good }
	data[1].pc_mode, data[1].pc_mod = "shape", assigned
	x6.pc_mods = { [assigned] = true }
	mod.px = function() error("prepass failed") end
	x1.k7 = 4
	tick()
	check(data[1].lv.VectorVelocity.X > 0, label .. "assigned shape survives primary prepass failure")
	check(data[2].lv.VectorVelocity.Magnitude == 0 and data[3].lv.VectorVelocity.Magnitude == 0,
		label .. "failed prepass parks primary parts")
	x1.k7 = 1
	mod.px = nil
	assigned.f2 = failures[1]
	tick()
	check(data[1].lv.VectorVelocity.Magnitude == 0 and data[2].lv.VectorVelocity.X > 0,
		label .. "assigned callback failure cannot stop primary parts")
	data[1].pc_mode, data[1].pc_mod, x6.pc_mods = nil, nil, nil

	local blend = { f2 = function(p)
		if p == bad_part then error("second blend invocation failed") end
		return Vector3.new(-60, 0, 0), p.Position - Vector3.new(20, 0, 0)
	end }
	context.loaded_shapes["Broken Blend"], context.x2["Broken Blend"] = blend, {}
	x1.BlendEnabled, x1.BlendShape, x1.BlendWeight = true, "Broken Blend", 50
	for _, d in ipairs(data) do Physics.clear_tracking(d) end
	tick()
	check(x6.bl_failed == "Broken Blend" and x6.bl_f2 == nil, label .. "blend failure after its first part disables the blend")
	check(data[2].lv.VectorVelocity.X > 0 and data[1].lv.VectorVelocity.X > 0,
		label .. "failed blend retains primary targets and finishes the sweep")
	x1.BlendEnabled = false
	tick()

	x1.Paused = true
	tick()
	check(data[1].lv.VectorVelocity.Magnitude <= 0.011, label .. "pause stops on its first frame")
	check(data[1].vl == nil and data[1].last_target_pos == nil and data[1].trans_vl == nil,
		label .. "pause discards smoothing and feedforward history")
	mod.f2 = function(p) return Vector3.zero, p.Position end
	x1.Paused = false
	tick()
	check(data[1].lv.VectorVelocity.Magnitude == 0, label .. "resume never replays a stale velocity: " .. tostring(data[1].lv.VectorVelocity.Magnitude) .. "; " .. tostring(x6.physics_error and x6.physics_error.message))

	data[1].pc_ride = true
	data[1].vl, data[1].lv.VectorVelocity = Vector3.new(400, 0, 0), Vector3.new(400, 0, 0)
	data[1].last_target_pos, data[1].sys_last_t = Vector3.new(500, 0, 0), clock
	context.x4.apply_disabled(true)
	context.x4.apply_disabled(false)
	check(data[1].vl == nil and data[1].last_target_pos == nil and data[1].lv.VectorVelocity.Magnitude == 0,
		label .. "ride parts clear old commands before re-enabling constraints")
	data[1].pc_ride = nil

	x1.k6 = "Point Impact"
	tick()
	check(data[1].lv.VectorVelocity.Magnitude <= 25.00001, label .. "Point Impact obeys the speed cap")
	data[1].pc_mode, data[1].pc_target, data[1].pc_phys = "pin", parts[1].Position + Vector3.new(100, 0, 0), { MaxSpeed = 5 }
	tick()
	check(near(data[1].lv.VectorVelocity, Vector3.new(5, 0, 0)), label .. "a pin follows its own target and speed cap during Point Impact")

	local original_velocity = Vector3.new(7, -12, 1)
	parts[3].AssemblyLinearVelocity = original_velocity
	data[3].free_physics, data[3].launch_velocity = true, Vector3.new(math.huge, 0, 0)
	Physics.apply(parts[3], data[3], x1)
	check(near(parts[3].AssemblyLinearVelocity, original_velocity) and data[3].launch_velocity == nil,
		label .. "invalid release impulse is consumed without poisoning assembly velocity")
	data[2].angular_velocity = "bad spin"
	Physics.apply(parts[2], data[2], x1)
	check(data[2].av.AngularVelocity.Magnitude == 0, label .. "invalid angular request cannot reach an actuator")

	x1.k6, mod.f2 = "Robustness Probe", good
	tick()
	local function pending_frame(unclaim)
		local calls = 0
		mod.f2 = function(p, _, record)
			calls = calls + 1
			if p == parts[3] then
				coroutine.yield("physics pending")
				if unclaim then record.unclaim = true end
			end
			return good(p)
		end
		local thread = coroutine.create(tick)
		local ok, result = coroutine.resume(thread)
		check(ok and result == "physics pending" and x6.physics_running, label .. "callback can suspend a guarded frame")
		tick()
		check(calls == 1, label .. "another Heartbeat cannot overlap the suspended sweep")
		return thread
	end
	local pending = pending_frame()
	local resumed = coroutine.resume(pending)
	check(resumed and coroutine.status(pending) == "dead" and not x6.physics_running,
		label .. "successful callback resume releases the frame guard")
	pending = pending_frame()
	x1.Paused = true
	tick()
	resumed = coroutine.resume(pending)
	check(resumed and not x6.physics_running and data[3].lv.VectorVelocity.Magnitude <= 0.011,
		label .. "a callback resumed after pause cannot rearm motion")
	x1.Paused, mod.f2 = false, good
	tick()
	pending = pending_frame(true)
	local old_record = data[3]
	context.x4.f2(parts[3])
	check(context.x4.f1(parts[3]), label .. "part can be reclaimed while its old callback is pending")
	data[3] = x6.a[parts[3]]
	data[3].lv.VectorVelocity = Vector3.new(2, 0, 0)
	parts[3].AssemblyLinearVelocity = Vector3.new(9, 1, 0)
	old_record.free_physics, old_record.launch_velocity = true, Vector3.new(1000, 0, 0)
	x6.apply_shape_physics(parts[3], old_record)
	check(near(parts[3].AssemblyLinearVelocity, Vector3.new(9, 1, 0)) and not old_record.free_active,
		label .. "immediate physics helper rejects an obsolete claim record")
	resumed = coroutine.resume(pending)
	check(resumed and x6.a[parts[3]] == data[3] and near(data[3].lv.VectorVelocity, Vector3.new(2, 0, 0)),
		label .. "old unclaim callback cannot release or move a newer claim")
	pending = pending_frame(true)
	data[3].pc_mode, data[3].pc_target = "pin", parts[3].Position + Vector3.new(0, 100, 0)
	data[3].lv.VectorVelocity = Vector3.new(2, 0, 0)
	local previous_frame = x6.f
	tick()
	check(x6.f > previous_frame and data[3].lv.VectorVelocity.Y > 0,
		label .. "a new assignment runs while the old callback is still suspended")
	local assigned_velocity = data[3].lv.VectorVelocity
	resumed = coroutine.resume(pending)
	check(resumed and near(data[3].lv.VectorVelocity, assigned_velocity),
		label .. "old callback cannot overwrite a newer assignment")
	mod.f2 = good
	tick()
	check(x6.a[parts[3]] == data[3] and data[3].lv.VectorVelocity.Y > 0,
		label .. "new assignment takes over without a stale unclaim request")
	data[3].pc_mode, data[3].pc_target = nil, nil
	pending = pending_frame(true)
	check(context.x4.switch_shape("Point Impact", false), label .. "can switch away from a suspended plugin")
	previous_frame = x6.f
	tick()
	check(x6.f > previous_frame and not x6.physics_running, label .. "new shape runs before the old callback resumes")
	resumed = coroutine.resume(pending)
	tick()
	check(resumed and x6.a[parts[3]] == data[3], label .. "old shape cannot leak an unclaim request into its replacement")
	mod.f2 = good
	context.x4.switch_shape("Robustness Probe", false)
	tick()
	pending = pending_frame()
	local old_core = x6.b
	context.x4.f5()
	context.x4.f4(Vector3.new(400, 120, 0))
	mod.f2 = good
	previous_frame = x6.f
	tick()
	check(x6.f > previous_frame, label .. "restarted core runs while its predecessor is still suspended")
	resumed = coroutine.resume(pending)
	check(resumed and not x6.physics_running and x6.b ~= old_core,
		label .. "old frame cannot continue against a restarted core")
	mod.f2 = good
	tick()
	for i, part in ipairs(parts) do
		if not x6.a[part] then check(context.x4.f1(part), label .. "reclaims probe after restart") end
		data[i] = x6.a[part]
		data[i].lv.VectorVelocity = Vector3.zero
	end
	pending = pending_frame()
	context.destroy()
	local stopped_velocity = data[3].lv.VectorVelocity
	resumed = coroutine.resume(pending)
	check(resumed and coroutine.status(pending) == "dead" and not x6.physics_running
		and near(data[3].lv.VectorVelocity, stopped_velocity), label .. "unloaded callback exits without touching actuators")
	for _, part in ipairs(parts) do part:Destroy() end
end
print(checks .. " physics robustness integration checks passed")
