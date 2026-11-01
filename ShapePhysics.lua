-- Optional per-part plugin requests, applied by the engine after f2.
-- Keeping the record while constraints are disabled makes a natural release
-- reversible without claiming a second copy of the part or cancelling gravity.
local M = {}
local LIGHT = PhysicalProperties.new(0.001, 0, 0, 0, 0)
local RIDE = PhysicalProperties.new(0.7, 0.5, 0.3, 1, 1)

function M.finite_vector(value)
	return typeof(value) == "Vector3"
		and value.X == value.X and value.Y == value.Y and value.Z == value.Z
		and math.abs(value.X) < math.huge and math.abs(value.Y) < math.huge and math.abs(value.Z) < math.huge
end

-- Normalize before taking a length: squaring a large, finite Vector3 can
-- overflow its float components and turn a speed clamp into a NaN.
function M.clamp_velocity(value, limit)
	if not M.finite_vector(value) then return nil end
	if type(limit) ~= "number" or limit ~= limit or limit < 0 or limit == math.huge then limit = 3300 end
	local largest = math.max(math.abs(value.X), math.abs(value.Y), math.abs(value.Z))
	if largest == 0 then return value end
	local scaled = value / largest
	local length = scaled.Magnitude
	if largest > limit / length then return scaled * (limit / length) end
	return value
end

-- A callback can fail only for a particular part or return invalid arithmetic.
-- Guard every invocation so one imported module cannot abort the whole sweep.
function M.evaluate(callback, part, center, data, clock, config, settings, state, constants)
	local running = state and state.physics_running
	if running then
		local owner = state.a[part]
		running.part, running.record = part, owner
		running.mode, running.module, running.config = owner.pc_mode, owner.pc_mod, owner.pc_cfg
	end
	local ok, velocity, target = pcall(callback, part, center, data, clock, config, settings, state, constants)
	if running then running.part, running.record, running.mode, running.module, running.config = nil, nil, nil, nil, nil end
	if not ok then return false, tostring(velocity) end
	if velocity == nil and (data.unclaim or data.free_physics) then velocity = Vector3.zero end
	if not M.finite_vector(velocity) then return false, "f2 must return a finite Vector3 velocity" end
	if target ~= nil and not M.finite_vector(target) then return false, "f2 target must be a finite Vector3" end
	return true, velocity, target
end

-- Also used when a setting changes while physics is paused/stopped. Keep shape,
-- free-physics and ride priorities identical to the normal per-frame path.
function M.apply_collisions(p, d, x1)
	local free = d.free_physics == true
	local keep = free or x1.Disabled or x1.PreserveCollisions
	-- Preserve means restore the captured value, even when a shape requests
	-- noclip. In particular, originally noncolliding parts must stay that way.
	if d.collisions ~= nil and not x1.Disabled and not x1.PreserveCollisions then keep = d.collisions end
	local want = keep and d.original_can_collide or false
	if d.collisions == nil and not free and not x1.Disabled and not x1.PreserveCollisions and d.pc_ride then want = true end
	if p.CanCollide ~= want then p.CanCollide = want end
	d.collision_active = d.collisions ~= nil or nil
end

local function clear_tracking(d)
	d.vl, d.trans_vl, d.last_target_pos, d.sys_last_t = nil, nil, nil, nil
	d.parked = nil
	d.integral = Vector3.zero
end
M.clear_tracking = clear_tracking

function M.park(d)
	clear_tracking(d)
	if d.lv then d.lv.VectorVelocity = Vector3.zero end
	if d.av then d.av.AngularVelocity = Vector3.zero end
end

function M.apply(p, d, x1)
	local free = d.free_physics == true
	local resumed = false
	if free and not d.free_active then
		d.free_active = true
		if d.lv then d.lv.Enabled, d.lv.MaxForce = false, 0 end
		if d.av then d.av.Enabled, d.av.MaxTorque = false, 0 end
		p.Anchored = d.original_anchored
		p.CustomPhysicalProperties = d.original_properties
		clear_tracking(d)
	elseif not free and d.free_active then
		d.free_active = nil
		resumed = true
		if x1.Disabled then p.CustomPhysicalProperties = d.original_properties
		elseif d.pc_ride then p.CustomPhysicalProperties = d.original_properties or RIDE
		else p.CustomPhysicalProperties = LIGHT end
		if d.lv then
			d.lv.VectorVelocity = Vector3.zero
			d.lv.MaxForce = x1.Disabled and 0 or x1.k4
			d.lv.Enabled = true
		end
		if d.av then
			d.av.AngularVelocity = Vector3.zero
			d.av.MaxTorque = x1.Disabled and 0 or math.huge
			d.av.Enabled = true
		end
		clear_tracking(d)
	end

	if free and d.launch_velocity then
		if M.finite_vector(d.launch_velocity) then p.AssemblyLinearVelocity = d.launch_velocity end
		d.launch_velocity = nil -- an impulse once, never a per-frame thrust
	end
	if d.av and (d.angular_velocity ~= nil or d.angular_active) then
		if not M.finite_vector(d.angular_velocity) then d.angular_velocity = nil end
		d.av.AngularVelocity = (not free and not x1.Disabled and d.angular_velocity) or Vector3.zero
		d.angular_active = d.angular_velocity ~= nil or nil
	end
	if free or resumed or d.collisions ~= nil or d.collision_active then
		M.apply_collisions(p, d, x1)
	end
	return free
end

return M
