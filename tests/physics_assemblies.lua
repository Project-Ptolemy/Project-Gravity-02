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
	local weld = Instance.new("WeldConstraint", chassis)
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
	local hinge = Instance.new("HingeConstraint", wheel)
	joints[wheel] = { hinge }
	check(not context.x4.f1(wheel), label .. "a hinged wheel is protected even though it has its own assembly root")
	local anchored_child = part("AnchoredAssemblyChild")
	local anchored_root = part("AnchoredRoot")
	anchored_root.Anchored = true
	anchored_child.AssemblyRootPart = anchored_root
	check(not context.x4.f1(anchored_child), label .. "unanchored children of an anchored assembly are protected")
	local seat_part = part("SeatedVehicle")
	local seat_weld = Instance.new("Weld", seat_part)
	seat_weld.Part0, seat_weld.Part1 = seat_part, fixture.env.LocalPlayer.Character.HumanoidRootPart
	joints[seat_part] = { seat_weld }
	check(not context.x4.f1(seat_part), label .. "a vehicle welded to a character cannot drag the character indirectly")
	local motor_part = part("DrivenVehiclePart")
	Instance.new("BodyMover", motor_part)
	check(not context.x4.f1(motor_part), label .. "legacy vehicle movers do not receive competing controls")
	local remote = part("RemoteDebris")
	ownership[remote] = false
	local remote_properties = remote.CustomPhysicalProperties
	check(not context.x4.f1(remote) and untouched(remote, remote_properties),
		label .. "a known remote owner prevents claim-time forces and property changes")

	local loose = part("LooseVehicleDebris")
	check(context.x4.f1(loose), label .. "ordinary loose debris remains claimable")
	local d = x6.a[loose]
	tick()
	check(d.lv.VectorVelocity.X > 0, label .. "our own actuators do not block a loose part")
	local joined = Instance.new("Weld", loose)
	joints[loose] = { joined }
	tick()
	check(x6.a[loose] == nil and loose.CanCollide and d.lv.Parent == nil and d.av.Parent == nil,
		label .. "a newly joined part releases its forces and restores collisions before another shape command")
	joints[loose] = {}
	joined:Destroy()
	-- A joint can break without adding or reparenting the part. Retry rejected
	-- candidates through ProcessQueue instead of waiting for a map refresh.
	for _ = 1, 180 do tick() end
	check(x6.a[loose] ~= nil, label .. "detached debris is automatically reconsidered without a DescendantAdded event")
	check(x6.a[chassis] == nil and x6.a[wheel] == nil, label .. "retries leave intact mechanisms alone")
	d = x6.a[loose]
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
		if object == loose and name == "NetworkOwnerV3" then return legacy_owner end
		return previous_hidden(object, name)
	end
	d.no3_val, d.no3_tick = nil, nil
	tick()
	check(not d.lv.Enabled and not d.av.Enabled, label .. "legacy ownership fallback also disables stale commands")
	legacy_owner = 0
	tick(0.2)
	check(d.lv.Enabled and d.lv.VectorVelocity.X > 0, label .. "legacy ownership fallback recovers after a handoff")
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

	context.destroy()
	for _, p in ipairs(parts) do p:Destroy() end
	isnetworkowner = nil
end
print(checks .. " assembly and ownership integration checks passed")
