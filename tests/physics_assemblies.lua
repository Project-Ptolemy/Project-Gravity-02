-- Connected mechanisms and ownership handoffs through the real engine loop.
-- The fixture checks which actuators are armed; it does not simulate Roblox's
-- joint solver or server replication.
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

-- The broad instance stub deliberately accepts unknown properties. These
-- fixtures need Roblox's nullable endpoints and joint class inheritance to
-- distinguish a retained, broken joint from one that connects a mechanism.
local function joint(class, parent)
	local instance = Instance.new(class, parent)
	local meta, endpoints = getmetatable(instance), {}
	local read, write = meta.__index, meta.__newindex
	local endpoint = { Part0 = true, Part1 = true, Attachment0 = true, Attachment1 = true }
	meta.__index = function(self, key)
		if endpoint[key] then return endpoints[key] end
		if class == "NoCollisionConstraint" and key == "Active" then
			error(key .. " is not a property of NoCollisionConstraint")
		end
		return read(self, key)
	end
	meta.__newindex = function(self, key, value)
		if endpoint[key] then endpoints[key] = value; return end
		write(self, key, value)
	end
	local legacy = class == "Weld" or class == "Motor6D"
	rawset(instance, "IsA", function(_, name)
		return name == class or (legacy and name == "JointInstance")
			or (not legacy and class ~= "WeldConstraint" and class ~= "NoCollisionConstraint" and name == "Constraint")
	end)
	instance.Enabled = true
	if class ~= "NoCollisionConstraint" then instance.Active = true end
	return instance
end
local function attachment(parent)
	local instance = Instance.new("Attachment", parent)
	local function ancestor(self, class)
		local current = self.Parent
		while current do
			if current:IsA(class) then return current end
			current = current.Parent
		end
	end
	rawset(instance, "FindFirstAncestorWhichIsA", ancestor)
	rawset(instance, "FindFirstAncestorOfClass", ancestor)
	return instance
end

for _, mobile in ipairs({ false, true }) do
	fixture.input.TouchEnabled, fixture.input.KeyboardEnabled = mobile, not mobile
	local ownership, joints, parts = {}, {}, {}
	isnetworkowner = function(part) return ownership[part] ~= false end
	assert(loadfile("main.lua"))()
	local context = assert(getgenv()._GRAVITY_CONTEXT)
	local x1, x6 = context.x1, context.x6
	local label = mobile and "mobile: " or "desktop: "
	local visits = {}
	local probe = { AlwaysProcess = true, f2 = function(part)
		visits[part] = (visits[part] or 0) + 1
		return Vector3.new(60, 0, 0), part.Position + Vector3.new(20, 0, 0)
	end }
	context.loaded_shapes["Assembly Probe"], context.x2["Assembly Probe"] = probe, {}
	x1.k6, x1.k7, x1.k8, x1.Ki, x1.Damping = "Assembly Probe", 1, 1, 0, 0
	x1.AngularDamping, x1.MaxSpeed = 0, 100
	context.x4.f4(Vector3.new(0, 120, 0))
	tick()
	table.clear(x6.claim_queue)
	local function part(name)
		local p = Instance.new("BasePart", workspace)
		p.Name, p.Position, p.Size = name, Vector3.new(20, 120, 0), Vector3.new(4, 2, 2)
		p.AssemblyRootPart, p.ReceiveAge = p, 0
		joints[p] = {}
		rawset(p, "GetJoints", function()
			local result = {}
			for _, joint in ipairs(joints[p]) do result[#result + 1] = joint end
			local d = x6.a[p]
			if d then result[#result + 1] = d.lv; result[#result + 1] = d.av end
			return result
		end)
		rawset(p, "IsDescendantOf", function(_, parent) return p.Parent ~= nil and parent == workspace end)
		parts[#parts + 1] = p
		return p
	end
	local function untouched(p, properties)
		return x6.a[p] == nil and p.CanCollide and p.CustomPhysicalProperties == properties
			and p:FindFirstChild("GRV_LV") == nil and p:FindFirstChild("GRV_AV") == nil
	end

	local chassis, panel = part("VehicleChassis"), part("VehiclePanel")
	local weld = joint("WeldConstraint", chassis)
	weld.Part0, weld.Part1 = chassis, panel
	panel.AssemblyRootPart = chassis
	joints[chassis], joints[panel] = { weld }, { weld }
	local properties = PhysicalProperties.new(2, 0.5, 0.2, 1, 1)
	chassis.CustomPhysicalProperties, panel.CustomPhysicalProperties = properties, properties
	check(not context.x4.f1(chassis), label .. "a welded assembly root cannot receive an independent shape force")
	check(not context.x4.f1(panel), label .. "a welded child cannot receive a competing shape force")
	check(untouched(chassis, properties) and untouched(panel, properties), label .. "skipped vehicle retains collisions, mass and native joints")
	check(weld.Parent == chassis, label .. "claiming never breaks the vehicle's joints")

	local wheel = part("VehicleWheel")
	local hinge = joint("HingeConstraint", wheel)
	hinge.Attachment0, hinge.Attachment1 = attachment(wheel), attachment(chassis)
	joints[wheel] = { hinge }
	check(not context.x4.f1(wheel), label .. "a hinged wheel is protected even though it has its own assembly root")
	local anchored_child = part("AnchoredAssemblyChild")
	local anchored_root = part("AnchoredRoot")
	anchored_root.Anchored = true
	anchored_child.AssemblyRootPart = anchored_root
	check(not context.x4.f1(anchored_child), label .. "unanchored children of an anchored assembly are protected")
	local seat_part = part("SeatedVehicle")
	local seat_weld = joint("Weld", seat_part)
	seat_weld.Part0, seat_weld.Part1 = seat_part, fixture.env.LocalPlayer.Character.HumanoidRootPart
	joints[seat_part] = { seat_weld }
	check(not context.x4.f1(seat_part), label .. "a vehicle welded to a character cannot drag the character indirectly")
	local motor_part = part("DrivenVehiclePart")
	Instance.new("BodyMover", motor_part)
	check(not context.x4.f1(motor_part), label .. "legacy vehicle movers do not receive competing controls")

	for _, case in ipairs({ "disabled", "inactive", "dangling", "self-connected", "removed endpoint" }) do
		local debris = part("RetainedJointDebris " .. case)
		local retained = joint(case == "inactive" and "Weld" or "WeldConstraint", debris)
		retained.Part0, retained.Part1 = debris, chassis
		if case == "disabled" then retained.Enabled = false
		elseif case == "inactive" then retained.Active = false
		elseif case == "dangling" then retained.Part1 = nil
		elseif case == "self-connected" then retained.Part1 = debris
		else
			local removed = part("RemovedWeldEndpoint")
			removed.Parent = nil
			retained.Part1 = removed
		end
		joints[debris] = { retained }
		check(context.x4.f1(debris), label .. case .. " retained joint does not prevent collection")
		check(retained.Parent == debris, label .. "collecting " .. case .. " debris leaves its native joint intact")
		tick()
		check(x6.a[debris] and visits[debris] ~= nil, label .. case .. " retained joint also permits held-part updates")
		context.x4.f2(debris, false)
		retained:Destroy()
	end
	local self_linked = part("SelfAttachedDebris")
	local self_hinge = joint("HingeConstraint", self_linked)
	self_hinge.Attachment0, self_hinge.Attachment1 = attachment(self_linked), attachment(self_linked)
	joints[self_linked] = { self_hinge }
	check(context.x4.f1(self_linked), label .. "attachments on the same part do not form an external mechanism")
	context.x4.f2(self_linked, false)
	self_hinge:Destroy()
	local orphaned = part("OrphanedAttachmentDebris")
	local orphan_hinge = joint("HingeConstraint", orphaned)
	orphan_hinge.Attachment0, orphan_hinge.Attachment1 = attachment(orphaned), attachment(nil)
	joints[orphaned] = { orphan_hinge }
	check(context.x4.f1(orphaned), label .. "a hinge with an unattached endpoint does not block loose debris")
	context.x4.f2(orphaned, false)
	orphan_hinge.Attachment1:Destroy()
	orphan_hinge:Destroy()
	local external = Instance.new("Folder", workspace)
	local nested = part("NestedAttachmentMechanism")
	local nested_hinge = joint("HingeConstraint", external)
	nested_hinge.Attachment0 = attachment(attachment(nested))
	nested_hinge.Attachment1 = attachment(attachment(chassis))
	joints[nested] = { nested_hinge }
	check(not context.x4.f1(nested), label .. "a mechanism parented elsewhere protects nested attachment endpoints")
	check(nested_hinge.Parent == external, label .. "rejecting an external mechanism leaves its native constraint intact")

	for _, class in ipairs({ "LinearVelocity", "AngularVelocity", "VectorForce", "Torque", "AlignPosition", "AlignOrientation" }) do
		local driven = part("Foreign " .. class)
		local actuator = joint(class, driven)
		actuator.Attachment0 = attachment(driven)
		if class == "AlignPosition" then actuator.Mode = Enum.PositionAlignmentMode.OneAttachment end
		if class == "AlignOrientation" then actuator.Mode = Enum.OrientationAlignmentMode.OneAttachment end
		-- Force actuators may be visible only as children, unlike joints between
		-- two parts returned by GetJoints.
		joints[driven] = {}
		check(not context.x4.f1(driven), label .. "an active foreign " .. class .. " keeps its existing force control")
		actuator.Enabled = false
		check(context.x4.f1(driven), label .. "a disabled foreign " .. class .. " does not prevent collection")
		context.x4.f2(driven, false)
		actuator.Enabled, actuator.Attachment0 = true, nil
		check(context.x4.f1(driven), label .. "a dangling foreign " .. class .. " does not prevent collection")
		context.x4.f2(driven, false)
		actuator:Destroy()
	end
	local externally_driven = part("ExternallyDrivenDebris")
	local external_force = joint("VectorForce", external)
	external_force.Attachment0 = attachment(externally_driven)
	joints[externally_driven] = { external_force }
	check(not context.x4.f1(externally_driven), label .. "an externally parented force actuator protects its attached part")
	for _, class in ipairs({ "AlignPosition", "AlignOrientation" }) do
		local primary, secondary = part("AlignmentPrimary " .. class), part("AlignmentSecondary " .. class)
		local align = joint(class, secondary)
		local mode = class == "AlignPosition" and Enum.PositionAlignmentMode or Enum.OrientationAlignmentMode
		align.Mode = mode.OneAttachment
		align.Attachment0, align.Attachment1 = attachment(primary), attachment(secondary)
		joints[primary], joints[secondary] = { align }, { align }
		check(not context.x4.f1(primary), label .. "one-attachment " .. class .. " protects its driven Attachment0")
		check(context.x4.f1(secondary), label .. "one-attachment " .. class .. " ignores the unused Attachment1")
		context.x4.f2(secondary, false)
		align.Mode = mode.TwoAttachment
		align.Attachment0 = attachment(secondary)
		check(not context.x4.f1(secondary), label .. "two-attachment " .. class .. " protects an active same-part controller")
		align:Destroy()
	end
	local reaction_primary, reaction_secondary = part("ReactionTorquePrimary"), part("ReactionTorqueSecondary")
	local reaction = joint("AngularVelocity", reaction_secondary)
	reaction.Attachment0, reaction.Attachment1 = attachment(reaction_primary), attachment(reaction_secondary)
	reaction.RelativeTo, reaction.ReactionTorqueEnabled = Enum.ActuatorRelativeTo.Attachment1, true
	joints[reaction_secondary] = { reaction }
	check(not context.x4.f1(reaction_secondary), label .. "angular reaction torque protects the Attachment1 reference part")
	reaction.ReactionTorqueEnabled = false
	check(context.x4.f1(reaction_secondary), label .. "disabled reaction torque leaves the reference part eligible")
	context.x4.f2(reaction_secondary, false)
	reaction.RelativeTo, reaction.ReactionTorqueEnabled = Enum.ActuatorRelativeTo.World, true
	check(context.x4.f1(reaction_secondary), label .. "world-relative angular velocity ignores the Attachment1 reference part")
	context.x4.f2(reaction_secondary, false)
	reaction:Destroy()
	local no_collision_part = part("NoCollisionDebris")
	local no_collision = joint("NoCollisionConstraint", no_collision_part)
	no_collision.Part0, no_collision.Part1 = no_collision_part, chassis
	joints[no_collision_part] = { no_collision }
	check(context.x4.f1(no_collision_part), label .. "a no-collision policy does not connect or drive loose debris")
	context.x4.f2(no_collision_part, false)
	no_collision:Destroy()

	local remote = part("RemoteDebris")
	ownership[remote] = false
	remote.CustomPhysicalProperties = properties
	check(context.x4.f1(remote), label .. "loose debris registers before network ownership arrives")
	local remote_data = assert(x6.a[remote])
	check(remote:FindFirstChild("GRV_ATT") == remote_data.at and not remote.CanCollide
		and remote.CustomPhysicalProperties ~= properties,
		label .. "pending ownership retains the normal attachment, collision and mass preparation")
	check(remote_data.lv.Enabled == false and remote_data.av.Enabled == false,
		label .. "pending ownership cannot apply claim-time forces")
	tick()
	check(visits[remote] == nil and remote_data.lv.Enabled == false and remote_data.av.Enabled == false,
		label .. "pending ownership does not invoke the shape or rearm actuators")
	-- Leave enough workspace traversal queued to exceed one frame's processing
	-- budget. Ownership recovery must use the held record, without waiting for
	-- that unrelated scan to drain and the deferred-candidate retry timer to fire.
	local backlog = Instance.new("Folder", workspace)
	rawset(backlog, "IsDescendantOf", function(_, parent) return parent == workspace end)
	for _ = 1, 300 do x6.claim_queue[#x6.claim_queue + 1] = backlog end
	ownership[remote] = true
	tick()
	check(#x6.claim_queue > 0 and visits[remote] == 1 and remote_data.lv.Enabled and remote_data.av.Enabled
		and near(remote_data.lv.VectorVelocity, Vector3.new(60, 0, 0)),
		label .. "ownership arrival drives debris on the next heartbeat while the workspace scan is still queued")
	table.clear(x6.claim_queue)
	backlog:Destroy()
	context.x4.f2(remote, false)
	check(untouched(remote, properties), label .. "releasing prepared debris restores original properties")
	local pending_release = part("PendingOwnershipRelease")
	ownership[pending_release], pending_release.CustomPhysicalProperties = false, properties
	check(context.x4.f1(pending_release) and x6.a[pending_release].suspended,
		label .. "pending-release debris registers with suspended forces")
	context.x4.f2(pending_release, false)
	check(ownership[pending_release] == false and untouched(pending_release, properties)
		and pending_release:FindFirstChild("GRV_ATT") == nil,
		label .. "releasing debris before ownership arrives restores original properties and removes all constraints")
	local aggressive = part("AggressiveDebris")
	ownership[aggressive], x1.AggressiveClaim = false, true
	check(context.x4.f1(aggressive) and not x6.a[aggressive].suspended,
		label .. "Aggressive Claim registers remote debris without ownership suspension")
	tick()
	check(visits[aggressive] == 1 and x6.a[aggressive].lv.VectorVelocity.X > 0,
		label .. "Aggressive Claim continues to bypass the ownership drive gate")
	context.x4.f2(aggressive, false)
	x1.AggressiveClaim = false

	local loose = part("LooseVehicleDebris")
	check(context.x4.f1(loose), label .. "ordinary loose debris remains claimable")
	local d = x6.a[loose]
	tick()
	check(d.lv.VectorVelocity.X > 0, label .. "our own actuators do not block a loose part")
	local joined = joint("Weld", loose)
	joined.Part0, joined.Part1 = loose, chassis
	joints[loose] = { joined }
	tick()
	check(x6.a[loose] == nil and loose.CanCollide and d.lv.Parent == nil and d.av.Parent == nil,
		label .. "a newly joined part releases its forces and restores collisions before another shape command")
	joined.Part1 = nil
	-- A joint can break without adding or reparenting the part. Retry rejected
	-- candidates while the initial scan is still busy, rather than waiting for
	-- that scan to drain or for the part to be added to the workspace again.
	local retry_backlog = Instance.new("Folder", workspace)
	rawset(retry_backlog, "IsDescendantOf", function(_, parent) return parent == workspace end)
	for _ = 1, 36 do
		for _ = #x6.claim_queue + 1, 300 do x6.claim_queue[#x6.claim_queue + 1] = retry_backlog end
		tick()
		if x6.a[loose] then break end
	end
	check(x6.a[loose] ~= nil and #x6.claim_queue > 0,
		label .. "detached debris is reconsidered within 0.6 seconds while workspace traversal remains queued")
	check(joined.Parent == loose, label .. "a retried claim retains the broken joint instance")
	table.clear(x6.claim_queue)
	retry_backlog:Destroy()
	joined:Destroy()
	joints[loose] = {}
	check(x6.a[chassis] == nil and x6.a[wheel] == nil, label .. "retries leave intact mechanisms alone")
	d = x6.a[loose]
	local capped = part("DeferredPartCountCandidate")
	local capped_weld = joint("Weld", capped)
	capped_weld.Part0, capped_weld.Part1 = capped, chassis
	joints[capped] = { capped_weld }
	check(not context.x4.f1(capped), label .. "a connected candidate enters deferred collection")
	capped_weld.Part1 = nil
	x1.TargetParts = x6.n
	for _ = 1, 36 do tick() end
	check(x6.a[capped] == nil, label .. "deferred collection respects the target part ceiling")
	x1.TargetParts = 0
	for _ = 1, 36 do tick(); if x6.a[capped] then break end end
	check(x6.a[capped] ~= nil, label .. "raising the target part ceiling preserves and reclaims a deferred candidate")
	context.x4.f2(capped, false)
	capped_weld:Destroy()
	local anchored_later = part("AnchoredAfterClaim")
	check(context.x4.f1(anchored_later), label .. "claims an initially free part")
	anchored_later.Anchored = true
	tick()
	check(x6.a[anchored_later] == nil and anchored_later.Anchored,
		label .. "releasing a newly anchored part cannot undo the game's anchoring")

	ownership[loose] = false
	tick()
	check(d.lv.Enabled == false and d.av.Enabled == false, label .. "ownership loss disables both actuators")
	check(d.vl == nil and d.last_target_pos == nil and near(d.lv.VectorVelocity, Vector3.zero),
		label .. "ownership loss clears old commands and feedforward")
	local skipped = visits[loose]
	tick()
	check(visits[loose] == skipped, label .. "the shape cannot command a part simulated by another client")
	context.x4.apply_disabled(true)
	check(loose.CanCollide and d.lv.Enabled == false, label .. "Disable still restores a suspended part's collision policy")
	context.x4.apply_disabled(false)
	check(d.lv.Enabled == false and d.av.Enabled == false, label .. "Enable cannot rearm a suspended part before ownership is rechecked")
	ownership[loose] = true
	tick()
	check(d.lv.Enabled and d.av.Enabled and near(d.lv.VectorVelocity, Vector3.new(60, 0, 0)),
		label .. "ownership recovery starts with a fresh bounded command")
	local previous_hidden, legacy_owner = gethiddenproperty, 2
	isnetworkowner = function() error("ownership API unavailable") end
	gethiddenproperty = function(object, name)
		if name == "NetworkOwnerV3" then return legacy_owner end
		return previous_hidden(object, name)
	end
	local legacy_error = part("LegacyOwnershipError")
	check(context.x4.f1(legacy_error), label .. "an unavailable ownership API cannot reject otherwise eligible debris")
	isnetworkowner = nil
	local legacy_missing = part("LegacyOwnershipMissing")
	check(context.x4.f1(legacy_missing), label .. "a missing ownership API cannot reject otherwise eligible debris")
	d.no3_val, d.no3_tick = nil, nil
	tick()
	check(not d.lv.Enabled and not d.av.Enabled, label .. "legacy ownership fallback also disables stale commands")
	check(visits[legacy_error] == nil and visits[legacy_missing] == nil
		and x6.a[legacy_error].lv.Enabled == false and x6.a[legacy_missing].lv.Enabled == false,
		label .. "legacy ownership fallback prevents commands for newly registered remote debris")
	legacy_owner = 0
	tick(0.2)
	check(d.lv.Enabled and d.lv.VectorVelocity.X > 0, label .. "legacy ownership fallback recovers after a handoff")
	check(visits[legacy_error] == 1 and visits[legacy_missing] == 1,
		label .. "legacy ownership handoff recovers newly registered debris")
	gethiddenproperty = previous_hidden
	isnetworkowner = function(part) return ownership[part] ~= false end

	local errors_before = x6.physics_error_count or 0
	for _, property in ipairs({ "Position", "AssemblyLinearVelocity", "AssemblyAngularVelocity" }) do
		local original = loose[property]
		loose[property] = Vector3.new(0 / 0, 0, 0)
		local before = visits[loose]
		tick()
		check(d.lv.Enabled == false and d.av.Enabled == false and visits[loose] == before,
			label .. "invalid world " .. property .. " is suspended before shape evaluation")
		check((x6.physics_error_count or 0) == errors_before, label .. "invalid world physics is not misreported as a shape error")
		loose[property] = original
		tick()
		check(d.lv.Enabled and d.lv.VectorVelocity.X > 0, label .. "valid world " .. property .. " resumes automatically")
	end
	local invalid = part("InvalidPhysicsAtClaim")
	invalid.Position = Vector3.new(math.huge, 0, 0)
	check(not context.x4.f1(invalid), label .. "invalid world parts cannot acquire force constraints")

	-- Several rounds of a large deferred population must not lose candidates.
	-- Keep engine time deterministic so machine speed does not decide how much
	-- of the frame budget this stress fixture can exercise.
	context.x4.clean_physics()
	local stress_parts, stress_welds, all_blocked = {}, {}, true
	for i = 1, 1200 do
		local candidate = part("StressDebris" .. i)
		local native = joint("Weld", candidate)
		native.Part0, native.Part1 = candidate, chassis
		joints[candidate] = { native }
		stress_parts[i], stress_welds[i] = candidate, native
		if context.x4.f1(candidate) then all_blocked = false end
	end
	check(all_blocked, label .. "all 1200 connected stress candidates initially remain protected")
	for i = 1, 32 do
		local removed = part("DestroyedStressCandidate" .. i)
		local native = joint("Weld", removed)
		native.Part0, native.Part1 = removed, chassis
		joints[removed] = { native }
		check(not context.x4.f1(removed), label .. "a soon-destroyed candidate is initially deferred")
		removed:Destroy()
	end
	local stress_backlog = Instance.new("Folder", workspace)
	rawset(stress_backlog, "IsDescendantOf", function(_, parent) return parent == workspace end)
	local previous_clock = os.clock
	os.clock = function() return clock end
	x1.MaxFidelity = true
	local function stress_tick()
		for _ = #x6.claim_queue + 1, 5000 do x6.claim_queue[#x6.claim_queue + 1] = stress_backlog end
		-- The queue is the behavior under stress. Drive its real callback directly
		-- rather than evaluating 1200 independent shapes after every claim batch.
		clock = clock + 0.1
		context.x4.ProcessQueue()
	end
	for _ = 1, 20 do stress_tick() end
	local intact = true
	for _, candidate in ipairs(stress_parts) do if x6.a[candidate] then intact = false end end
	check(intact, label .. "repeated large retry rounds keep every intact mechanism protected")
	for _, native in ipairs(stress_welds) do native.Part1 = nil end
	local collected = 0
	for _ = 1, 90 do
		stress_tick()
		collected = 0
		for _, candidate in ipairs(stress_parts) do if x6.a[candidate] then collected = collected + 1 end end
		if collected == #stress_parts then break end
	end
	check(collected == 1200 and #x6.claim_queue > 0,
		label .. "every detached stress candidate is collected while unrelated workspace traversal remains busy")
	os.clock, x1.MaxFidelity = previous_clock, false
	local after_clean = part("DeferredAtClean")
	local clean_weld = joint("Weld", after_clean)
	clean_weld.Part0, clean_weld.Part1 = after_clean, chassis
	joints[after_clean] = { clean_weld }
	check(not context.x4.f1(after_clean), label .. "clean-up begins with an explicitly deferred candidate")
	context.x4.clean_physics()
	clean_weld.Part1 = nil
	for _ = 1, 36 do tick() end
	check(x6.n == 0 and after_clean:FindFirstChild("GRV_LV") == nil,
		label .. "clean physics releases the stress population and cancels automatic deferred reclaim")
	stress_backlog:Destroy()
	local after_unload = part("DeferredAtUnload")
	local unload_weld = joint("Weld", after_unload)
	unload_weld.Part0, unload_weld.Part1 = after_unload, chassis
	joints[after_unload] = { unload_weld }
	check(not context.x4.f1(after_unload), label .. "unload begins with an explicitly deferred candidate")
	context.destroy()
	unload_weld.Part1 = nil
	tick(0.6)
	context.x4.ProcessQueue()
	check(x6.n == 0 and after_unload:FindFirstChild("GRV_LV") == nil,
		label .. "unload cancels pending claims even if a stale callback attempts queue processing")
	external:Destroy()
	for _, p in ipairs(parts) do p:Destroy() end
	isnetworkowner = nil
end
print(checks .. " assembly and ownership integration checks passed")
