-- Optional per-part plugin requests, applied by the engine after f2.
-- Keeping the record while constraints are disabled makes a natural release
-- reversible without claiming a second copy of the part or cancelling gravity.
local M = {}
local LIGHT = PhysicalProperties.new(0.001, 0, 0, 0, 0)
local RIDE = PhysicalProperties.new(0.7, 0.5, 0.3, 1, 1)

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
		p.AssemblyLinearVelocity = d.launch_velocity
		d.launch_velocity = nil -- an impulse once, never a per-frame thrust
	end
	if d.av and (d.angular_velocity ~= nil or d.angular_active) then
		d.av.AngularVelocity = (not free and not x1.Disabled and d.angular_velocity) or Vector3.zero
		d.angular_active = d.angular_velocity ~= nil or nil
	end
	if free or resumed or d.collisions ~= nil or d.collision_active then
		M.apply_collisions(p, d, x1)
	end
	return free
end

return M
