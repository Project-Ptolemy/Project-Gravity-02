package.path = "tests/?.lua;" .. package.path
local fixture = require("runtime_fixture")
local env = fixture.env
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local active_context
local stall_path, stalled
function capture_context(context) active_context = context end

-- Exercise the actual loader and its actual close button without HTTP.
game.HttpGet = function(_, url)
	local path = assert(url:match("/main/(.-)%?cb="), url)
	if path == stall_path and not stalled then
		stalled = true
		coroutine.yield("download pending")
	end
	local file = assert(io.open(path), path)
	local source = file:read("a"); file:close()
	if path == "UI.lua" or path == "mobilever/UI.lua" then
		source = source:gsub("return function%(context%)", "return function(context) capture_context(context)", 1)
	end
	return source
end
local clock = 10
time = function() return clock end
local physics = { AllowSleep = true }
settings = function() return { Physics = physics } end
gethiddenproperty = function(object, key) return object[key] end
sethiddenproperty = function(object, key, value) object[key] = value end
local player = env.LocalPlayer
player.MaximumSimulationRadius, player.SimulationRadius, player.NetworkIsSleeping = 120, 90, true
local original_focus = Instance.new("Part")
player.ReplicationFocus = original_focus

for _, mobile in ipairs({ false, true }) do
	fixture.input.TouchEnabled, fixture.input.KeyboardEnabled = mobile, not mobile
	assert(loadfile("main.lua"))()
	local ctx = assert(active_context)
	check(getgenv()._GRAVITY_CONTEXT == ctx, "loader exposes the live context for UAI")
	local sys, x6 = ctx.x4, ctx.x6
	ctx.x1.k7 = 1 -- deterministic full sweeps for the physics transition checks
	check(type(ctx.destroy) == "function", "loader exposes full teardown")
	check(next(fixture.actions) ~= nil, "session has keyboard actions")
	ctx.x1.k6 = "Black Hole v2"
	ctx.x5.up()
	check(ctx.x2["Black Hole v2"].rwRegrab == nil, "button keys are not saved settings")
	local regrab = assert(fixture.find("rwRegrab"), "shape creates a real button")
	regrab.MouseButton1Click:Fire()
	check(x6.pre["Black Hole v2"].gen == 1, "one UI click dispatches one action")
	regrab.MouseButton1Click:Fire()
	check(x6.pre["Black Hole v2"].gen == 2, "repeated clicks trigger without toggling a saved value")
	ctx.x5.up()
	check(x6.pre["Black Hole v2"].gen == 2, "rebuilding controls does not trigger actions")
	sys.f4(Vector3.new(0, 30, 0))
	clock = clock + 1
	fixture.run.Heartbeat:Fire(1 / 60)
	check(physics.AllowSleep == false and player.ReplicationFocus == x6.b, "engine captures and changes environment")

	local part = Instance.new("BasePart", workspace)
	part.Position, part.Size = Vector3.new(40, 20, 10), Vector3.new(4, 2, 2)
	part.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.5, 0)
	check(sys.f1(part), "real engine claims the test part")
	local record = x6.a[part]
	for frame = 1, 240 do
		clock = clock + 1 / 60
		fixture.run.Heartbeat:Fire(1 / 60)
	end
	check(record.black_hole_v2 and record.lv.VectorVelocity.Magnitude > 0
		and record.av.AngularVelocity.Magnitude == 0,
		"the real loop drives the core orbit without forcing each piece to tumble")
	ctx.x1.Paused = true
	for _ = 1, 3 do fixture.run.Heartbeat:Fire(1 / 60) end
	check(record.lv.VectorVelocity.Magnitude <= 0.011 and record.av.AngularVelocity.Magnitude == 0, "pause stops core movement")
	ctx.x1.Paused = false
	clock = clock + 1 / 60
	fixture.run.Heartbeat:Fire(1 / 60)
	check(record.lv.VectorVelocity.Magnitude > 0.011 and record.av.AngularVelocity.Magnitude == 0, "resuming restores the orbit without self-spin")
	fixture.find("rwRelease").MouseButton1Click:Fire()
	check(record.free_active and not record.lv.Enabled, "UI Stop releases the real engine actuators")
	x6.pc_selected[part] = true
	x6.pc_assign("pin", { ride = true })
	clock = clock + 0.1
	fixture.run.Heartbeat:Fire(1 / 60)
	check(record.pc_mode == "pin" and not record.free_active and record.lv.Enabled,
		"pinning a released part rearms it through the real engine loop")
	check(part.CanCollide and part.CustomPhysicalProperties == record.original_properties,
		"pinning keeps rideable material properties")
	x6.pc_release(part)
	clock = clock + 0.1
	fixture.run.Heartbeat:Fire(1 / 60)
	check(record.free_active and not record.lv.Enabled, "clearing the override returns to Black Hole v2's released state")
	ctx.x1.k6 = "Black Hole"
	clock = clock + 0.1
	fixture.run.Heartbeat:Fire(1 / 60)
	check(not record.free_active and record.lv.Enabled, "switching global shapes recovers a released part")
	check(record.av.AngularVelocity.Magnitude == 0, "switching shapes removes the previous core spin")
	record.release_velocity, record.release_spin = Vector3.new(3, -35, 2), Vector3.new(0, 1, 0)
	sys.f2(part, true)
	check(part.AssemblyLinearVelocity.Y == -35 and part.AssemblyAngularVelocity.Y == 1 and x6.a[part] == nil,
		"unclaim applies the explicit release velocity and removes the record")
	ctx.x1.k6 = "Black Hole v2"

	local reset = fixture.actions[mobile and "R" or "Gravity_Reset"]
	reset(mobile and "R" or "Gravity_Reset", Enum.UserInputState.Begin)
	check(x6.b == nil and not x6.o, "Q releases the core")
	check(next(fixture.actions) ~= nil and not x6.torn_down, "Q leaves the session restartable")
	check(physics.AllowSleep and player.ReplicationFocus == original_focus, "Q restores environment")
	sys.f4(Vector3.new(0, 30, 0))
	clock = clock + 1
	fixture.run.Heartbeat:Fire(1 / 60)
	local core, folder = x6.b, x6.b.Parent
	local unrelated = Instance.new("Folder", workspace)
	unrelated.Name = "AS"
	core.Parent = unrelated
	local records = {}
	for i = 1, 2 do
		local part = Instance.new("Part", i == 1 and workspace or nil)
		part.CanCollide, part.Anchored = false, false
		part.CustomPhysicalProperties = PhysicalProperties.new(0.001, 0, 0)
		local rec = {
			original_can_collide = i == 1, original_anchored = false,
			at = Instance.new("Attachment", part), lv = Instance.new("LinearVelocity", part),
			av = Instance.new("AngularVelocity", part),
		}
		x6.a[part], x6.active_array[i] = rec, part
		records[i] = { part = part, data = rec }
	end
	x6.n = 2
	local cleaned = 0
	ctx.loaded_shapes.fixture = { cleanup = function() cleaned = cleaned + 1 end }
	ctx.loaded_shapes.broken = { cleanup = function() error("fixture cleanup failure") end }
	local old_action = fixture.actions[mobile and "C" or "Gravity_Recenter"]
	local close = assert(fixture.find("UnloadProjectGravity"), "real X button exists")
	close.MouseButton1Click:Fire()
	check(x6.torn_down and not x6.o and x6.b == nil, "X fully tears down runtime")
	check(core._destroyed == true and folder._destroyed == true, "X destroys ball and its holder")
	check(unrelated._destroyed ~= true, "X only removes its owned folder if the core was reparented")
	unrelated:Destroy()
	check(ctx.x5.g == nil and x6.sg == nil, "X removes UI handles")
	check(next(fixture.actions) == nil, "X unbinds every session action")
	check(#x6.c == 0 and #x6.run_connections == 0 and #x6.f1_connections == 0, "X disconnects owned connections")
	check(fixture.input.InputBegan:count() == 0 and fixture.input.InputEnded:count() == 0
		and fixture.input.InputChanged:count() == 0, "X disconnects global input listeners, including UI controls")
	check(x6.n == 0 and #x6.active_array == 0 and next(x6.a) == nil, "X clears physics records")
	for i, entry in ipairs(records) do
		check(entry.part.CanCollide == (i == 1), "original collision is restored, including pooled parts")
		check(entry.data.at._destroyed and entry.data.lv._destroyed and entry.data.av._destroyed,
			"failed shape cleanup cannot strand an actuator")
	end
	check(physics.AllowSleep and player.ReplicationFocus == original_focus, "X restores sleep and replication focus")
	check(player.MaximumSimulationRadius == 120 and player.SimulationRadius == 90 and player.NetworkIsSleeping,
		"X restores captured simulation properties")
	check(getgenv()._GRAVITY_DESTROY == nil and getgenv()._GRAVITY_SESSION_ID == nil, "X unregisters the session")
	check(getgenv()._GRAVITY_CONTEXT == nil, "X clears the UAI integration handle")
	old_action(mobile and "C" or "Gravity_Recenter", Enum.UserInputState.Begin)
	sys.f4(Vector3.zero)
	check(x6.b == nil, "queued old callbacks cannot recreate the core")
	ctx.destroy()
	check(cleaned == 1, "teardown is idempotent")
	if mobile then check(x6.mobile_input == nil, "touch input is removed on unload") end
end

-- Closing during a yielding download must not let the old initializer create
-- new bindings or UI when its response finally arrives.
for _, mobile in ipairs({ false, true }) do
	fixture.input.TouchEnabled, fixture.input.KeyboardEnabled = mobile, not mobile
	local prefix = mobile and "mobilever/" or ""
	for _, path in ipairs({ prefix .. "UI_elements.lua", "ShapePhysics.lua", prefix .. "System_partctl.lua" }) do
		stall_path, stalled = path, false
		local init = coroutine.create(assert(loadfile("main.lua")))
		local ok, result = coroutine.resume(init)
		check(ok and result == "download pending", "fixture suspends initializer at " .. path .. ": " .. tostring(result))
		local destroy = assert(getgenv()._GRAVITY_DESTROY)
		destroy()
		ok, result = coroutine.resume(init)
		check(ok and coroutine.status(init) == "dead", "closed initializer exits after download: " .. path)
		check(next(fixture.actions) == nil and getgenv()._GRAVITY_DESTROY == nil,
			"closed initializer cannot register a session or bindings: " .. path)
		check(fixture.input.InputBegan:count() == 0 and fixture.input.InputEnded:count() == 0
			and fixture.input.InputChanged:count() == 0, "no listeners survive interrupted initialization: " .. path)
	end
end
stall_path = nil
print(checks .. " session lifecycle checks passed")
