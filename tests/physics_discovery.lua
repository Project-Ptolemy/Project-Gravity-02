-- Discover newly unanchored map parts through the real desktop/mobile scan and
-- Heartbeat, without calling f1 directly or resetting the core.
package.path = "tests/?.lua;" .. package.path
local fixture = require("runtime_fixture")
local checks, clock, additions = 0, 10, 0
local function check(value, message) checks = checks + 1; assert(value, message) end
time = function() return clock end
game.HttpGet = function(_, url)
	local path = assert(url:match("/main/(.-)%?cb="), url)
	local file = assert(io.open(path), path)
	local source = file:read("a"); file:close(); return source
end
workspace.DescendantAdded, workspace.DescendantRemoving = fixture.signal(), fixture.signal()
workspace.DescendantAdded:Connect(function() additions = additions + 1 end)
rawset(workspace, "GetChildren", function()
	local children = {}
	for _, instance in ipairs(fixture.instances) do
		if instance.Parent == workspace then children[#children + 1] = instance end
	end
	return children
end)
local function in_workspace(instance)
	local current = instance.Parent
	while current do
		if current == workspace then return true end
		current = current.Parent
	end
	return false
end
local anchor_signals = {}
local function node(class, name, parent, anchored)
	local instance = Instance.new(class)
	local meta = getmetatable(instance)
	local read, write = meta.__index, meta.__newindex
	local changed = class == "BasePart" and fixture.signal() or nil
	meta.__newindex = function(self, key, value)
		local anchor_changed = key == "Anchored" and read(self, key) ~= value
		local was_inside = key == "Parent" and in_workspace(self)
		if was_inside then workspace.DescendantRemoving:Fire(self) end
		write(self, key, value)
		if key == "Parent" and in_workspace(self) then workspace.DescendantAdded:Fire(self) end
		if anchor_changed and changed then changed:Fire() end
	end
	rawset(instance, "IsDescendantOf", function(self, ancestor)
		local current = self.Parent
		while current do
			if current == ancestor then return true end
			if current == workspace then return false end
			current = current.Parent
		end
		return false
	end)
	if changed then
		anchor_signals[instance] = changed
		rawset(instance, "GetPropertyChangedSignal", function(_, property)
			assert(property == "Anchored", "unexpected part property subscription: " .. property)
			return changed
		end)
		instance.Position, instance.Size = Vector3.new(20, 120, 0), Vector3.new(4, 2, 2)
		instance.Anchored = anchored == true
		instance.CustomPhysicalProperties = PhysicalProperties.new(2, 0.5, 0.2, 1, 1)
	end
	instance.Name, instance.Parent = name, parent
	return instance
end
local function tick(dt)
	dt = dt or 1 / 60
	clock = clock + dt
	fixture.run.Heartbeat:Fire(dt)
end
local function drain(context)
	for _ = 1, 100 do
		tick()
		if #context.x6.claim_queue == 0 then return end
	end
	error("workspace scan did not drain")
end

for _, mobile in ipairs({ false, true }) do
	fixture.input.TouchEnabled, fixture.input.KeyboardEnabled = mobile, not mobile
	local label = mobile and "mobile: " or "desktop: "
	local map = node("Folder", "DiscoveryMap", workspace)
	local loose = node("BasePart", "InitiallyLoose", map)
	local waiting = node("BasePart", "InitiallyAnchored", map, true)
	local excluded = node("BasePart", "Baseplate", map, true)
	local original_properties = waiting.CustomPhysicalProperties
	assert(loadfile("main.lua"))()
	local context = assert(getgenv()._GRAVITY_CONTEXT)
	local sys, x1, x6, visits = context.x4, context.x1, context.x6, {}
	context.loaded_shapes["Discovery Probe"] = { AlwaysProcess = true, f2 = function(part)
		visits[part] = (visits[part] or 0) + 1
		return Vector3.new(60, 0, 0), part.Position + Vector3.new(20, 0, 0)
	end }
	context.x2["Discovery Probe"] = {}
	x1.k6, x1.k7, x1.k8, x1.Ki, x1.Damping = "Discovery Probe", 1, 1, 0, 0
	x1.AngularDamping, x1.MaxSpeed = 0, 100
	local previous_clock = os.clock
	os.clock = function() return clock end -- deterministic scan budgets
	sys.f4(Vector3.new(0, 120, 0))
	drain(context)
	check(x6.a[loose] ~= nil, label .. "startup scan collects existing loose map parts")
	check(x6.a[waiting] == nil and waiting.Anchored and waiting.CanCollide
		and waiting.CustomPhysicalProperties == original_properties and waiting:FindFirstChild("GRV_ATT") == nil,
		label .. "startup scan leaves anchored map physics untouched")
	local parent, before_additions = waiting.Parent, additions
	waiting.Anchored = false
	tick(); tick()
	check(waiting.Parent == parent and additions == before_additions,
		label .. "unanchoring an existing part emits no workspace addition")
	check(x6.a[waiting] ~= nil and visits[waiting] ~= nil and x6.a[waiting].lv.VectorVelocity.X > 0,
		label .. "an existing map part is picked up and driven immediately after unanchoring without Q")
	check(anchor_signals[waiting]:count() == 0, label .. "claimed parts release their anchor listener")
	excluded.Anchored = false
	tick()
	check(x6.a[excluded] == nil and anchor_signals[excluded]:count() == 0,
		label .. "excluded map parts never acquire an anchor listener or force")

	local added = node("BasePart", "AddedWhileAnchored", map, true)
	drain(context)
	check(anchor_signals[added]:count() == 1, label .. "new anchored descendants are watched after the initial scan")
	local backlog = node("Folder", "ScanBacklog", workspace)
	for _ = 1, 1000 do x6.claim_queue[#x6.claim_queue + 1] = backlog end
	added.Anchored = false
	tick(); tick()
	check(x6.a[added] ~= nil and visits[added] ~= nil and #x6.claim_queue > 0,
		label .. "unanchored additions are picked up while the workspace scan remains busy")
	table.clear(x6.claim_queue)
	backlog:Destroy()

	local joined = node("BasePart", "UnanchoredMechanism", map, true)
	local support = node("BasePart", "MechanismSupport", map, true)
	local weld = Instance.new("WeldConstraint", joined)
	weld.Part0, weld.Part1, weld.Enabled, weld.Active = joined, support, true, true
	rawset(joined, "GetJoints", function() return { weld } end)
	drain(context)
	joined.Anchored = false
	drain(context)
	check(x6.a[joined] == nil and weld.Parent == joined,
		label .. "unanchoring preserves a part's intact mechanism")
	weld.Part1 = nil
	for _ = 1, 36 do tick(); if x6.a[joined] then break end end
	check(x6.a[joined] ~= nil and weld.Parent == joined,
		label .. "newly unanchored debris collects automatically once its joint detaches")

	x1.TargetParts = x6.n
	local capped = node("BasePart", "UnanchoredAtCapacity", map, true)
	drain(context)
	check(anchor_signals[capped]:count() == 1, label .. "a full part limit still discovers anchored candidates")
	capped.Anchored = false
	drain(context)
	check(x6.a[capped] == nil, label .. "unanchoring respects the current part limit")
	x1.TargetParts = 0
	for _ = 1, 36 do tick(); if x6.a[capped] then break end end
	check(x6.a[capped] ~= nil, label .. "unanchored candidates survive a full limit and collect when space returns")

	waiting.Anchored = true
	for _ = 1, 36 do tick() end
	check(x6.a[waiting] == nil and waiting.Anchored and anchor_signals[waiting]:count() == 1,
		label .. "a held part that reanchors returns to waiting without changing its anchor")
	waiting.Anchored = false
	tick(); tick()
	check(x6.a[waiting] ~= nil, label .. "a reanchored part is picked up again when it becomes loose")

	local pooled = node("BasePart", "PooledAnchor", map, true)
	drain(context)
	pooled.Parent = nil
	check(anchor_signals[pooled]:count() == 0, label .. "removing a waiting part disconnects its listener")
	pooled.Anchored = false
	tick()
	check(x6.a[pooled] == nil, label .. "unparented parts cannot be picked up")
	pooled.Parent = map
	drain(context)
	check(x6.a[pooled] ~= nil, label .. "pooled parts are rediscovered when returned to workspace")
	local destroyed = node("BasePart", "DestroyedAnchor", map, true)
	drain(context)
	destroyed:Destroy()
	check(anchor_signals[destroyed]:count() == 0, label .. "destroyed waiting parts release their listener")

	local clean_waiting = node("BasePart", "WaitingAtReleaseAll", map, true)
	local clean_queued = node("BasePart", "QueuedAtReleaseAll", map, true)
	drain(context)
	clean_queued.Anchored = false
	sys.clean_physics()
	clean_waiting.Anchored = false
	for _ = 1, 36 do tick() end
	check(x6.n == 0 and #x6.claim_queue == 0 and anchor_signals[clean_waiting]:count() == 0,
		label .. "release all cancels waiting and already queued anchor pickups")

	local stopped = node("BasePart", "WaitingAtQ", map, true)
	drain(context)
	sys.f5()
	check(anchor_signals[stopped]:count() == 0, label .. "Q disconnects waiting anchor listeners")
	stopped.Anchored = false
	tick()
	check(x6.n == 0 and #x6.claim_queue == 0, label .. "stopped sessions cannot queue new pickups")
	sys.f4(Vector3.new(0, 120, 0))
	drain(context)
	check(x6.a[stopped] ~= nil, label .. "a new run scans the map afresh")
	local unloaded = node("BasePart", "WaitingAtUnload", map, true)
	drain(context)
	check(anchor_signals[unloaded]:count() == 1, label .. "a restarted run registers one anchor listener")
	context.destroy()
	check(anchor_signals[unloaded]:count() == 0, label .. "full unload disconnects waiting anchor listeners")
	unloaded.Anchored = false
	tick()
	sys.ProcessQueue()
	check(x6.n == 0 and #x6.claim_queue == 0, label .. "unload cancels all pending anchor pickups")
	map:Destroy()
	os.clock = previous_clock
end
print(checks .. " workspace physics discovery checks passed")
