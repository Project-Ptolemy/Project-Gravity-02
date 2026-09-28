package.path = "tests/?.lua;" .. package.path
local fixture = require("runtime_fixture")
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local env, keys, last_fps = fixture.env, {}, nil
local actions = env.svc("ContextActionService")
local bind, unbind = actions.BindAction, actions.UnbindAction
actions.BindAction = function(self, name, fn, touch, key) bind(self, name, fn); keys[name] = key end
actions.UnbindAction = function(self, name) unbind(self, name); keys[name] = nil end
setfpscap = function(fps) last_fps = fps end

-- Load the actual desktop/mobile panels and click their actual launch buttons.
game.HttpGet = function(_, url)
	if url:find("/ProjectUAI/main/dist/uai.lua", 1, true) then
		return "getgenv()._UAI_LAUNCH_CONTEXT = ...; return {}"
	end
	local path = assert(url:match("/main/(.-)%?cb="), url)
	local file = assert(io.open(path)); local source = file:read("a"); file:close(); return source
end

for _, mobile in ipairs({ false, true }) do
	fixture.input.TouchEnabled, fixture.input.KeyboardEnabled = mobile, not mobile
	assert(loadfile("main.lua"))()
	local context = assert(getgenv()._GRAVITY_CONTEXT)
	local button
	for _, instance in ipairs(fixture.instances) do
		if instance._destroyed ~= true and instance.Text == "PROJECT UAI" then button = instance end
	end
	check(button ~= nil, "Gravity exposes the UAI launcher")
	button.MouseButton1Click:Fire()
	check(getgenv()._UAI_LAUNCH_CONTEXT.gravity == context, "launcher passes the live context")
	check(type(context.session_id) == "string", "part IDs can be scoped to the actual Gravity session")
	local x1, x6, controls = context.x1, context.x6, context.controls
	check(controls and controls.fps_cap and type(context.x5.refresh_advanced) == "function", "both panels expose live settings hooks")
	check(type(context.x8.rebind_all) == "function" and type(context.x4.switch_shape) == "function", "both engines expose keybind and shape handlers")
	local recenter_id = mobile and "C" or "Gravity_Recenter"
	x1.Keybinds.Recenter, x1.Keybinds.Shapes["Black Hole"] = "F5", "F6"
	context.x8.rebind_all()
	check(keys[recenter_id] == Enum.KeyCode.F5 and keys["Gravity_Shape_Black Hole"] == Enum.KeyCode.F6, "rebinding updates actual core and shape actions")
	check(context.x8.find_conflict("F5", "shape:Black Hole") == "Recenter Core", "native conflict detection includes core bindings")
	check(context.x8.find_conflict("F6", "Recenter") == "Black Hole", "native conflict detection includes shape bindings")
	check(context.x8.find_conflict("F5", "Recenter") == nil and context.x8.key_from_name("") == nil, "same binding and an empty key are handled correctly")
	fixture.actions["Gravity_Shape_Black Hole"]("Gravity_Shape_Black Hole", Enum.UserInputState.Begin)
	check(x1.k6 == "Black Hole", "the real mobile/desktop shortcut selects its shape")
	local saves, save = 0, context.save_settings
	context.save_settings = function() saves = saves + 1 end
	check(context.x4.switch_shape("Celestial Ribbon", false) and saves == 0, "session-only shape changes do not request a save")
	context.save_settings = save

	context.x4.f4(Vector3.new(0, 30, 0))
	local part = Instance.new("BasePart", workspace)
	part.Name, part.Position, part.Size = "UAI Held", Vector3.new(10, 20, 5), Vector3.new(4, 2, 2)
	part.CanCollide, part.Material = true, Enum.Material.Wood
	check(context.x4.f1(part), "the real engine claims a part for external control")
	local d = x6.a[part]
	x6.pc_select(part, true)
	check(x6.pc_assign("pin", { target = Vector3.new(15, 30, 5) }) == 1 and d.pc_target.Y == 30, "native pin accepts an explicit world target")
	x6.pc_set_phys({ k10 = 70, Damping = 0.7 })
	x6.pc_set_ride(true)
	check(d.pc_mode == "pin" and d.pc_phys.k10 == 70 and part.CanCollide, "native physics and ride updates preserve pin mode")
	x6.pc_clear()
	check(d.pc_mode == "pin" and x6.pc_count() == 0, "clearing selection retains overrides")
	check(x6.pc_release_all() == 1 and d.pc_mode == nil and d.pc_phys == nil and d.pc_ride == nil, "release all reaches deselected overrides")
	x6.pc_select(part, true)
	x6.pc_set_phys({ MaxSpeed = 100 })
	x6.pc_set_ride(true)
	x6.pc_clear()
	check(x6.pc_release_all() == 1 and not d.pc_ride and d.pc_phys == nil, "release all includes ride/physics overrides with no assigned mode")
	local cleanups = 0
	local mod = { f2 = function() return Vector3.zero end, Controls = { { Type = "Slider", Key = "radius", Min = 0, Max = 100, Default = 12 } },
		cleanup = function() cleanups = cleanups + 1 end }
	context.loaded_shapes["UAI Runtime Test"], context.x2["UAI Runtime Test"] = mod, { radius = 50 }
	x6.pc_select(part, true)
	x6.pc_assign("shape", { shape = "UAI Runtime Test" })
	x6.pc_assign("shape", { shape = "UAI Runtime Test" })
	check(x6.pc_mods[mod] == 1, "reassigning through the API preserves native module refcounts")
	x6.pc_clear()
	x6.pc_release_all()
	check(cleanups == 1 and x6.pc_mods[mod] == nil, "releasing the final override invokes cleanup once")
	local function control_row(label)
		for _, instance in ipairs(fixture.instances) do
			if instance._destroyed ~= true and instance.Parent and instance.Text == label then return instance.Parent end
		end
		error("control row not found: " .. label)
	end
	x1.PartCtlPull, x1.PartCtlSurfaceSnap = 70, false
	context.x5.refresh_partctl()
	local pull_text, snap_button
	for _, child in ipairs(control_row("Pull Strength"):GetChildren()) do if child.ClassName == "TextBox" then pull_text = child end end
	for _, child in ipairs(control_row("Surface Snap"):GetChildren()) do if child.ClassName == "TextButton" then snap_button = child end end
	check(pull_text and pull_text.Text == "70" and d.pc_phys == nil, "external panel defaults repaint sliders without applying another override")
	assert(snap_button).MouseButton1Click:Fire()
	check(x1.PartCtlSurfaceSnap == true, "the first native click after an external setting change uses the refreshed toggle value")

	local lighting = env.svc("Lighting")
	lighting.GlobalShadows = true
	local fx, emitter = Instance.new("PostEffect", lighting), Instance.new("ParticleEmitter", part)
	fx.Enabled, emitter.Enabled = true, true
	local old_lighting_descendants, old_world_descendants = lighting.GetDescendants, workspace.GetDescendants
	rawset(lighting, "GetDescendants", function() return { fx } end)
	rawset(workspace, "GetDescendants", function() return { part, emitter } end)
	x1.Perf_DisableShadows, x1.Perf_DisablePostFX, x1.Perf_PotatoMaterials, x1.Perf_HideParticles = true, true, true, true
	x1.FPSCap, x1.UIScale, x1.ShowHUD, x1.k3 = 144, 1.5, false, Color3.fromRGB(12, 34, 56)
	controls.apply_settings({ Perf_DisableShadows = true, Perf_DisablePostFX = true, Perf_PotatoMaterials = true, Perf_HideParticles = true,
		FPSCap = 144, UIScale = 1.5, ShowHUD = false, k3 = x1.k3 })
	check(lighting.GlobalShadows == false, "native shadow control changes Lighting.GlobalShadows")
	check(fx.Enabled == false, "native post-effect control changes the effect")
	check(emitter.Enabled == false, "native particle control changes the emitter")
	check(part.Material == Enum.Material.SmoothPlastic, "native material control changes the held part")
	check(last_fps == 144 and not fixture.find("StatusHUD").Visible and x6.b.Color.B == 56 / 255, "FPS, HUD visibility and core color take effect immediately")
	-- PreserveCollisions restores original values even when a shape requests noclip.
	x1.PreserveCollisions, d.collisions = true, false
	controls.apply_settings({ PreserveCollisions = true })
	check(part.CanCollide, "preservation takes precedence over shape noclip requests")
	d.collisions, d.pc_ride, x1.PreserveCollisions = nil, true, false
	controls.apply_settings({ PreserveCollisions = false })
	check(part.CanCollide, "ride collision survives preservation being disabled")
	d.pc_ride, d.free_physics = nil, true
	controls.apply_settings({ PreserveCollisions = false })
	check(part.CanCollide, "free physics retains original collisions")
	d.free_physics = nil
	controls.apply_settings({ PreserveCollisions = false })
	check(not part.CanCollide, "ordinary held parts follow the preservation setting")
	local tags, kb, shape_keys = x1.k5, x1.Keybinds, x1.Keybinds.Shapes
	local custom_settings = context.x2["UAI Runtime Test"]
	x1.k5[1] = "Changed"
	context.save_settings = function() saves = saves + 1 end
	local before_saves = saves
	check(controls.reset(false) == nil, "both complete settings resets refresh without errors")
	check(saves == before_saves, "session-only reset does not request a save")
	context.save_settings = save
	check(lighting.GlobalShadows and fx.Enabled and emitter.Enabled and part.Material == Enum.Material.Wood, "reset restores original visual properties")
	check(last_fps == 60 and x1.UIScale == 1 and fixture.find("StatusHUD").Visible, "reset reapplies FPS, scale and HUD defaults")
	check(keys[recenter_id] == Enum.KeyCode.E and not fixture.actions["Gravity_Shape_Black Hole"], "reset immediately restores core bindings and removes shape shortcuts")
	check(x1.k5 == tags and tags[1] == "NoAttract" and x1.Keybinds == kb and kb.Shapes == shape_keys, "reset preserves native settings table identities")
	check(context.x2["UAI Runtime Test"] == custom_settings and custom_settings.radius == 12, "post-startup plugins reset to their own control defaults in place")
	rawset(lighting, "GetDescendants", old_lighting_descendants)
	rawset(workspace, "GetDescendants", old_world_descendants)
	local old = context
	assert(loadfile("main.lua"))()
	context = assert(getgenv()._GRAVITY_CONTEXT)
	check(context ~= old and old.x6.torn_down, "reload publishes the new context")
	old.destroy()
	check(getgenv()._GRAVITY_CONTEXT == context, "old teardown cannot clear a newer context")
	context.destroy()
	check(getgenv()._GRAVITY_CONTEXT == nil, "unload disconnects UAI")
	check(next(keys) == nil, "unload removes all newly rebound native shortcuts")
end

-- Exercise a real shape download yield without involving Roblox networking.
for _, prefix in ipairs({ "", "mobilever/" }) do
	local x6 = { a = {}, active_array = {}, pc_selected = {}, pc_mods = {}, c = {}, pre = {} }
	local part = Instance.new("BasePart", workspace)
	local d = { id = 1 }
	x6.a[part], x6.pc_selected[part] = d, true
	local mod = { f2 = function() end, Controls = {} }
	local context = { x1 = {}, x2 = { Test = {} }, x6 = x6, v1 = fixture.input, v4 = workspace, v8 = env.LocalPlayer,
		shape_physics = assert(loadfile("ShapePhysics.lua"))(),
		get_shape = function() coroutine.yield("loading"); return mod end }
	assert(loadfile(prefix .. "System_partctl.lua"))()(context, {})
	local valid, affected = true, nil
	local thread = coroutine.create(function() affected = x6.pc_assign("shape", { shape = "Test", guard = function() return valid end }) end)
	local ok, why = coroutine.resume(thread)
	check(ok and why == "loading", "native shape assignment yields during download")
	valid = false
	check(coroutine.resume(thread) and affected == 0 and d.pc_mode == nil and mod.pc_cfg_ref == nil,
		"cancelled assignment leaves records, selections and module references unchanged")
end

print(checks .. " UAI integration checks passed")
