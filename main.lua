--!native

local SESSION_ID = tostring(math.random(1000000, 9999999)) .. tostring(time())

if getgenv()._GRAVITY_SESSION_ID ~= nil and getgenv()._GRAVITY_DESTROY then
	pcall(getgenv()._GRAVITY_DESTROY)
end

getgenv()._GRAVITY_SESSION_ID = SESSION_ID

local function safe_service(name)
	local service = game:GetService(name)
	if cloneref then
		return cloneref(service)
	end
	return service
end

local v1, v2, v3, v4, v5, v6, v7 =
	safe_service("UserInputService"),
	safe_service("Players"),
	safe_service("RunService"),
	safe_service("Workspace"),
	safe_service("StarterGui"),
	safe_service("TweenService"),
	safe_service("ContextActionService")
local HttpService = safe_service("HttpService")

if setthreadidentity then
	pcall(function()
		setthreadidentity(8)
	end)
end

local function cleanup_previous()
	if gethui then
		for _, gui in ipairs(gethui():GetChildren()) do
			if gui:IsA("ScreenGui") and (gui.Name == "GravityLoading" or string.sub(gui.Name, 1, 2) == "G_") then
				pcall(function() gui:Destroy() end)
			end
		end
	elseif syn and syn.protect_gui then
		local core = game:GetService("CoreGui")
		for _, gui in ipairs(core:GetChildren()) do
			if gui:IsA("ScreenGui") and (gui.Name == "GravityLoading" or string.sub(gui.Name, 1, 2) == "G_") then
				pcall(function() gui:Destroy() end)
			end
		end
	else
		local pg = v2.LocalPlayer:FindFirstChild("PlayerGui")
		if pg then
			for _, gui in ipairs(pg:GetChildren()) do
				if gui:IsA("ScreenGui") and (gui.Name == "GravityLoading" or string.sub(gui.Name, 1, 2) == "G_") then
					pcall(function() gui:Destroy() end)
				end
			end
		end
	end
end
cleanup_previous()

local v8, v9 = v2.LocalPlayer, v2.LocalPlayer:GetMouse()
local is_mobile = v1.TouchEnabled and not v1.KeyboardEnabled
local SUB_DIR = is_mobile and "mobilever/" or ""

local loading_sg = Instance.new("ScreenGui")
loading_sg.Name = "GravityLoading"
loading_sg.DisplayOrder = 99999
loading_sg.IgnoreGuiInset = true
if gethui then
	loading_sg.Parent = gethui()
elseif syn and syn.protect_gui then
	syn.protect_gui(loading_sg)
	loading_sg.Parent = game:GetService("CoreGui")
else
	loading_sg.Parent = v8:WaitForChild("PlayerGui")
end
local spinner = Instance.new("Frame", loading_sg)
spinner.Size = UDim2.new(0, 36, 0, 36)
spinner.Position = UDim2.new(0.5, -18, 0.5, -18)
spinner.BackgroundTransparency = 1
local uic = Instance.new("UICorner", spinner)
uic.CornerRadius = UDim.new(1, 0)
local uis = Instance.new("UIStroke", spinner)
uis.Thickness = 3
uis.Color = Color3.fromRGB(255, 255, 255)
local uig = Instance.new("UIGradient", uis)
uig.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 1)
})
local spin_t = 0
local spin_conn = v3.RenderStepped:Connect(function(dt)
	spin_t = spin_t + dt
	spinner.Rotation = spin_t * 400
end)

local loading_text = Instance.new("TextLabel", loading_sg)
loading_text.Size = UDim2.new(0, 100, 0, 20)
loading_text.Position = UDim2.new(0.5, -50, 0.5, 25)
loading_text.BackgroundTransparency = 1
loading_text.Text = "LOADING..."
loading_text.TextColor3 = Color3.fromRGB(200, 200, 200)
loading_text.Font = Enum.Font.GothamMedium
loading_text.TextSize = 12

local x9 = { c1 = 0.15, c2 = 0.05, c3 = 0.01, c4 = 0.2, c5 = 0.6, c6 = 0.8, c7 = 0.1, c8 = 0.25 }
local ANTI_SLEEP = Vector3.new(0, 0.01, 0)
local BASE_URL = "https://raw.githubusercontent.com/CarlDV/Project-Gravity-02/main/"

local function safe_http_get(url)
	local cache_buster = "?cb=" .. tostring(math.random(1000000, 9999999))
	local fetch_url = url .. cache_buster
	local success, result = pcall(function()
		return game:HttpGet(fetch_url)
	end)
	if success and result then
		return result
	end
	local req = (type(request) == "function" and request) or (type(http) == "table" and http.request) or (type(syn) == "table" and syn.request)
	if req then
		local s, r = pcall(function()
			return req({Url = fetch_url, Method = "GET"})
		end)
		if s and type(r) == "table" and r.Body then
			return r.Body
		end
	end
	return nil
end

local function load_module(path)
	if getgenv()._GRAVITY_SESSION_ID ~= SESSION_ID then return nil end
	local code = safe_http_get(BASE_URL .. path)
	if getgenv()._GRAVITY_SESSION_ID ~= SESSION_ID then return nil end
	if code and not string.match(code, "^404: Not Found") then
		local func, err = loadstring(code)
		if func then
			return func()
		end
		warn("Syntax error in module " .. path .. ": " .. tostring(err))
		return nil
	end
	warn("Failed to download module: " .. path)
	return nil
end

local config = load_module("config.lua")
local plugin_controls = load_module("PluginControls.lua")
-- load_module returns nil on a failed download or a syntax error, and this is
-- above the init pcall, so a bare config.x1 threw with the loading spinner still
-- on screen and its RenderStepped still connected -- no message, no way to clear
-- it, and _GRAVITY_DESTROY not yet set for a re-execution to clean up.
if not config or type(config.x1) ~= "table" or type(config.x2) ~= "table" or not plugin_controls then
	if spin_conn then
		pcall(function() spin_conn:Disconnect() end)
	end
	if loading_sg then
		pcall(function() loading_sg:Destroy() end)
	end
	warn("Project Gravity: could not load config.lua -- aborting.")
	return
end
local x1 = config.x1
local x2 = config.x2
x1.S = x2

local local_shapes = {}
if isfolder and makefolder and listfiles and readfile then
	pcall(function()
		if not isfolder("GravityShapes") then
			makefolder("GravityShapes")
		end
		local files = listfiles("GravityShapes")
		for _, file in ipairs(files) do
			if string.match(string.lower(file), "%.lua$") or string.match(string.lower(file), "%.txt$") then
				local name = string.match(file, "([^/\\]+)%.[^%.]+$")
				if name then
					local_shapes[name] = file
					if not x2[name] then
						-- The slot is claimed only after the module proves it loads.
						-- Claiming it first left x2[name] as a truthy empty table on every
						-- failure path, which defeated the k6 repair further down: a local
						-- shape with a syntax error stayed selected, get_shape returned
						-- nil, shape_f2 stayed nil, and every claimed part fell through to
						-- ANTI_SLEEP -- the script grabbed the map and did nothing, which
						-- is the exact failure that repair exists to prevent. The AI writes
						-- these files, so a bad one is not a remote possibility.
						local read_success, code = pcall(readfile, file)
						local shape_mod
						if read_success and code then
							local func = loadstring(code)
							if func then
								local load_success, result = pcall(func)
								if load_success and type(result) == "table" then
									shape_mod = result
								end
							end
						end
						if shape_mod then
							local block = plugin_controls.defaults(shape_mod.Controls)
							x2[name] = block
						else
							warn("Project Gravity: local shape '" .. name .. "' failed to load; skipping it.")
							local_shapes[name] = nil
						end
					end
				end
			end
		end
	end)
end

-- Copied all the way down, not one level: x1.Keybinds.Shapes is a table inside a
-- table, and a shallow copy would hand the snapshot the *same* table the user
-- then edits, so "Reset All Settings" would restore the defaults onto itself and
-- leave every shape hotkey in place.
local function copy_table(t)
	local res = {}
	for k, v in pairs(t) do
		if typeof(v) == "table" then
			res[k] = copy_table(v)
		else
			res[k] = v
		end
	end
	return res
end

local function restore_table(target, source)
	for key in pairs(target) do if source[key] == nil then target[key] = nil end end
	for key, value in pairs(source) do
		if typeof(value) == "table" then
			if typeof(target[key]) ~= "table" then target[key] = {} end
			restore_table(target[key], value)
		else target[key] = value end
	end
end

-- Forward-declared so reset_config below can reach x4 at call time. The table
-- itself is built further down, once every field it carries exists.
local context

local default_x1 = {}
for k, v in pairs(x1) do
	-- S is x2 under another name and Targets holds live Players; reset_config
	-- skips both, so snapshotting them is pure work.
	if k ~= "S" and k ~= "Targets" then
		if typeof(v) == "table" then
			default_x1[k] = copy_table(v)
		else
			default_x1[k] = v
		end
	end
end
local default_x2 = {}
for mk, mv in pairs(x2) do
	default_x2[mk] = {}
	for sk, sv in pairs(mv) do
		default_x2[mk][sk] = sv
	end
end

-- Restores the defaults, then hands the three settings that own live state to the
-- code that owns them. The generic loop cannot know that Disabled has to go through
-- x4.apply_disabled (System.lua:1061 calls that "the one entry point"), that a k6
-- change has to arm the shape transition, or that the Perf_* flags describe things
-- already done to the game. Assigning them directly left the flag saying one thing
-- and the world doing another.
--
-- context.x4 / x5 are read at call time, not captured: reset_config is built before
-- either exists.
local function reset_config()
	local was_disabled = x1.Disabled
	local was_shape = x1.k6

	for k, v in pairs(default_x1) do
		if k ~= "S" and k ~= "Targets" then
			if typeof(v) == "table" then
				if typeof(x1[k]) ~= "table" then x1[k] = {} end
				restore_table(x1[k], v)
			else
				x1[k] = v
			end
		end
	end
	for mk, mv in pairs(default_x2) do
		if x2[mk] then
			table.clear(x2[mk])
			for sk, sv in pairs(mv) do
				x2[mk][sk] = sv
			end
		else
			-- Restore a shipped shape whose settings block was removed at runtime.
			x2[mk] = {}
			for sk, sv in pairs(mv) do
				x2[mk][sk] = sv
			end
		end
	end
	-- Modules registered after the startup snapshot keep their own control
	-- defaults. Reset their existing blocks in place, including active pc_cfg refs.
	for name, block in pairs(x2) do
		if not default_x2[name] then
			local mod = context and context.loaded_shapes and context.loaded_shapes[name]
			if type(mod) == "table" and type(mod.Controls) == "table" then
				restore_table(block, plugin_controls.defaults(mod.Controls))
			end
		end
	end
	x1.S = x2

	local x4 = context and context.x4
	-- Disabled: route the transition rather than the flag. apply_disabled re-seats
	-- every claimed part; skipping it left them holding a whole fall's worth of
	-- stale smoothing terms, which is the re-seat fling System.lua:1052 describes.
	if x4 and x4.apply_disabled and was_disabled ~= x1.Disabled then
		local target = x1.Disabled
		x1.Disabled = was_disabled
		pcall(x4.apply_disabled, target)
	end
	-- k6: switch_shape owns d.trans_vl, which System.lua:1140 notes cannot be
	-- derived after the fact because it needs the velocity from before the switch.
	-- Without it every part jumps between velocity fields in a single frame.
	if x4 and x4.switch_shape and was_shape ~= x1.k6 then
		local target = x1.k6
		x1.k6 = was_shape
		pcall(x4.switch_shape, target, false)
	end
end

local serialization = load_module("math/serialization.lua")
-- Same reasoning as config.lua above: this is the other hard dependency fetched
-- outside the init pcall, and settings cannot round-trip without it.
if not serialization or type(serialization.sanitize) ~= "function" or type(serialization.desanitize) ~= "function" then
	if spin_conn then
		pcall(function() spin_conn:Disconnect() end)
	end
	if loading_sg then
		pcall(function() loading_sg:Destroy() end)
	end
	warn("Project Gravity: could not load math/serialization.lua -- aborting.")
	return
end
local sanitize = serialization.sanitize
local desanitize = serialization.desanitize

local favorites = {}
local function save_favs()
	if writefile then
		pcall(function()
			writefile("GravityFavorites.json", HttpService:JSONEncode(favorites))
		end)
	end
end
local function load_favs()
	if isfile and isfile("GravityFavorites.json") then
		pcall(function()
			favorites = HttpService:JSONDecode(readfile("GravityFavorites.json"))
		end)
	end
end
load_favs()

local save_pending = false
local function save_settings()
	if not writefile then
		return
	end
	if save_pending then return end
	save_pending = true
	task.delay(0.5, function()
		save_pending = false
		if getgenv()._GRAVITY_SESSION_ID ~= SESSION_ID then return end
		local data = { x1 = sanitize(x1), x2 = sanitize(x2) }
		-- x1.S is x2 under another name (line 150) and sanitize recurses into
		-- tables, so without this every autosave carried a second complete copy of
		-- all 51 shape blocks -- which load_settings then desanitized and threw away
		-- at its k ~= "S" test. Doubled the file and the encode cost on every
		-- slider release.
		data.x1.S = nil
		-- Targets, not Tgt. x1.Tgt was replaced by x1.Targets and this line has been
		-- guarding a key that does not exist; the live targets were kept out only
		-- because sanitize drops Instance values. TgtActive goes with it, since a
		-- restored "targeting on" with no targets means nothing.
		data.x1.Targets = nil
		data.x1.TgtActive = nil
		data.x1.IsLaunching = nil
		-- Paused is live state, not a preference. It persisted, so quitting while
		-- paused brought the next session up frozen -- and the desktop panel has no
		-- Paused control at all, only the rebindable P hotkey, so if that was unbound
		-- there was no way to resume.
		data.x1.Paused = nil
		local success, json = pcall(function()
			return HttpService:JSONEncode(data)
		end)
		if success then
			pcall(function()
				writefile("GravitySettings_Auto.json", json)
			end)
		else
			-- Silence here meant settings stopped persisting with no way to tell.
			warn("Project Gravity: could not encode settings -- not saved. " .. tostring(json))
		end
	end)
end

local function load_settings()
	if isfile and isfile("GravitySettings_Auto.json") then
		local success, data = pcall(function()
			return HttpService:JSONDecode(readfile("GravitySettings_Auto.json"))
		end)
		if success and data then
			local cx1 = desanitize(data.x1)
			local cx2 = desanitize(data.x2)
			for k, v in pairs(cx1) do
				if k ~= "S" and x1[k] ~= nil and typeof(x1[k]) == typeof(v) then
					x1[k] = v
				end
			end
			for mk, mv in pairs(cx2) do
				if x2[mk] and type(mv) == "table" then
					for sk, sv in pairs(mv) do
						if x2[mk][sk] ~= nil and typeof(x2[mk][sk]) == typeof(sv) then
							x2[mk][sk] = sv
						end
					end
				end
			end
		end
	end
end
load_settings()

-- A settings file can name a shape that no longer ships -- Deflect was folded
-- into Cursed Technique Red -- and nothing downstream catches that. switch_shape
-- checks x2 (System.lua), but only for an explicit switch; the startup path calls
-- get_shape(x1.k6) directly, which warns, returns nil, and leaves shape_f2 nil.
-- Every claimed part then falls through to ANTI_SLEEP, so the script grabs the
-- map and does nothing with it, with only a warn to explain why. Falling back to
-- the default costs one lookup and turns that into a working panel.
if not x2[x1.k6] then
	x1.k6 = default_x1.k6
end

if setfpscap then
	pcall(function()
		setfpscap(x1.FPSCap or 60)
	end)
end

local loaded_shapes = {}
local function get_shape(name)
	if getgenv()._GRAVITY_SESSION_ID ~= SESSION_ID then return nil end
	if not loaded_shapes[name] then
		local success, result = false, nil

		if local_shapes and local_shapes[name] then
			local read_success, code = pcall(readfile, local_shapes[name])
			if read_success and code then
				local func, err = loadstring(code)
				if func then
					success, result = pcall(func)
				else
					result = "Syntax error in local shape: " .. tostring(err)
				end
			else
				result = "Failed to read local shape file"
			end
		end

		if not success then
			local url = BASE_URL .. "shapes/" .. HttpService:UrlEncode(name) .. ".lua"
			local code = safe_http_get(url)
			-- The 404 test load_module already does. Without it the literal body
			-- "404: Not Found" went to loadstring and a missing shape was reported as
			-- a syntax error in its source, which sends you looking in the wrong place.
			if code and string.match(code, "^404: Not Found") then
				code = nil
				result = "Not found on the server"
			end
			if code then
				local func, err = loadstring(code)
				if func then
					success, result = pcall(func)
				else
					result = "Syntax error in shape source: " .. tostring(err)
				end
			elseif not result then
				result = "HTTP Request Failed"
			end
		end

		if getgenv()._GRAVITY_SESSION_ID ~= SESSION_ID then return nil end
		if success and result then
			loaded_shapes[name] = result
		else
			warn("Failed to load shape: " .. tostring(name) .. " Error: " .. tostring(result))
		end
	end
	return loaded_shapes[name]
end

local x6 = {
	b = nil,
	c = {},
	a = setmetatable({}, {__mode = "k"}),
	o = false,
	d = false,
	p = 0,
	f = 0,
	n = 0,
	pi_targets = {},
	pi_timer = 0,
	ex_nodes = {},
	ex_timer = 0,
	esp_timer = 0,
	claim_queue = {},
	active_array = {},
	run_connections = {},
	pre = {},
	pre_buffer = table.create(200),
	sculptor_selected = setmetatable({}, {__mode = "k"}),
	sculptor_dragging = false,
	sculptor_drag_start = nil,
	sculptor_box_start = nil,
	sculptor_box = nil,
	sculptor_highlights = setmetatable({}, {__mode = "k"}),
	sculptor_preset_ui = nil,
	pc_selected = setmetatable({}, {__mode = "k"}),
	pc_highlights = setmetatable({}, {__mode = "k"}),
	pc_offsets = setmetatable({}, {__mode = "k"}),
	pc_mods = {},
	transition_time = 0,
	transition_dur = 2,
	f1_connections = {},
}

get_shape(x1.k6)

coroutine.wrap(function()
	for mn, _ in pairs(x2) do
		-- Stop if the session was torn down or superseded while we were waiting.
		-- This loop runs for ten seconds or more, so it easily outlives a
		-- re-execution, and anything it loaded afterwards was never cleaned up.
		if x6.torn_down or getgenv()._GRAVITY_SESSION_ID ~= SESSION_ID then
			return
		end
		if mn ~= x1.k6 then
			pcall(function()
				get_shape(mn)
			end)
			if task and task.wait then
				task.wait(0.05)
			end
		end
	end
end)()

-- One motion vocabulary for the whole interface. Every tween in UI.lua and
-- UI_elements.lua pulls from here, so "how does a hover feel" is answered in one
-- place instead of by whichever TweenInfo happened to get pasted at the call
-- site -- which is how the same hover ended up at 0.2s in one file and 0.15s in
-- another, and how a dozen calls ended up on bare TweenInfo.new(t) (Quad/Out by
-- Roblox default) that reads sluggish next to a deliberate curve.
--
-- The scale is intentionally coarse. Interactions that should feel instant
-- (hover, press) sit under 0.12s, because past roughly 0.15s a pointer response
-- stops reading as feedback and starts reading as lag. Structural motion
-- (windows, panels) is slower because it is telling you where something came
-- from. Anything that moves a large distance gets Quint/Out, which covers most
-- of the ground early and settles softly; anything that should feel physical
-- gets Back, which overshoots slightly.
local ANIM = {
	-- Pointer feedback. Fast enough to feel attached to the cursor.
	HOVER = TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	-- Press is faster than release: the push should feel immediate, the return
	-- can relax. Asymmetry here is what makes a button feel clicky.
	PRESS = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	RELEASE = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	-- A toggle knob is a physical object; Back sells the travel.
	TOGGLE = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	-- Colour has no momentum, so easing it with a curve that overshoots looks
	-- wrong. Plain and quick.
	TINT = TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	-- Follows the cursor during a drag, so it has to be nearly immediate or the
	-- knob lags behind the pointer.
	SLIDE = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	-- Structural motion.
	OPEN = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	OPEN_POP = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	CLOSE = TweenInfo.new(0.19, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	CLOSE_POP = TweenInfo.new(0.19, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	-- Panel collapse choreography.
	ROLL = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	FOLD = TweenInfo.new(0.36, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	UNFOLD = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	-- Setting-driven rescale: no character wanted, just get there.
	RESCALE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

context = {
	session_id = SESSION_ID,
	v1 = v1,
	v2 = v2,
	v3 = v3,
	v4 = v4,
	v5 = v5,
	v6 = v6,
	v7 = v7,
	v8 = v8,
	v9 = v9,
	x1 = x1,
	x2 = x2,
	x6 = x6,
	x9 = x9,
	favorites = favorites,
	save_favs = save_favs,
	save_settings = save_settings,
	get_shape = get_shape,
	plugin_controls = plugin_controls,
	local_shapes = local_shapes,
	loaded_shapes = loaded_shapes,
	load_module = load_module,
	is_mobile = is_mobile,
	SUB_DIR = SUB_DIR,
	reset_config = reset_config,
	ANIM = ANIM,
}

local function destroy()
	if x6.destroying then return end
	x6.destroying = true
	x6.o, x6.d = false, false
	x1.IsLaunching = false
	-- Read by the preload coroutine below, which task.waits its way through every
	-- shape and cannot otherwise be stopped: without this it keeps fetching and
	-- writing into loaded_shapes after teardown, and anything it adds after the
	-- cleanup sweep further down is never cleaned up at all.
	x6.torn_down = true
	if context.x8 and context.x8.unbind_all then pcall(context.x8.unbind_all) end
	if context.x4 and context.x4.restore_environment then pcall(context.x4.restore_environment) end
	if context.x5 and context.x5.restore_perf then pcall(context.x5.restore_perf) end
	if x6.mobile_cleanup then pcall(x6.mobile_cleanup) end
	if spin_conn then
		pcall(function() spin_conn:Disconnect() end)
		spin_conn = nil
	end
	if loading_sg then
		pcall(function() loading_sg:Destroy() end)
		loading_sg = nil
	end
	for i = #x6.c, 1, -1 do
		pcall(function() x6.c[i]:Disconnect() end)
		x6.c[i] = nil
	end
	for i = #x6.run_connections, 1, -1 do
		pcall(function() x6.run_connections[i]:Disconnect() end)
		x6.run_connections[i] = nil
	end
	-- The third list. f1() disconnects the previous generation on every rebuild, so
	-- this is bounded at one per session -- but that last one is a live Heartbeat
	-- holding the whole f1 closure, and nothing here was releasing it.
	if x6.f1_connections then
		for i = #x6.f1_connections, 1, -1 do
			pcall(function() x6.f1_connections[i]:Disconnect() end)
			x6.f1_connections[i] = nil
		end
	end
	-- SelectionBoxes the sculptor parented onto world parts. No shape owns them
	-- (Sculptor has no cleanup) so the sweep below cannot reach them, and the next
	-- session starts with a fresh table that has no record of them -- so if they
	-- are not destroyed here they are in the world permanently.
	if x6.sculptor_clear then
		pcall(x6.sculptor_clear)
	elseif x6.sculptor_highlights then
		for _, hl in pairs(x6.sculptor_highlights) do
			pcall(function() hl:Destroy() end)
		end
		table.clear(x6.sculptor_highlights)
	end
	-- Overrides first: pc_clear only drops the selection, so without this the
	-- parts keep pc_mode/pc_mod pointing at a module that is about to be torn
	-- down. Releasing walks x6.a, so it also catches parts that were assigned
	-- and then deselected.
	if x6.pc_release_all then
		pcall(x6.pc_release_all)
	end
	-- The formation preview's ghost markers. They live in a Folder inside the core's
	-- AS holder, which the sweep further down destroys anyway -- but that makes their
	-- removal incidental to something else, and this path runs on re-execution, where
	-- anything left behind is left behind permanently.
	if x6.preview_clear then
		pcall(x6.preview_clear)
	end
	if x6.pc_clear then
		pcall(x6.pc_clear)
	elseif x6.pc_highlights then
		for _, hl in pairs(x6.pc_highlights) do
			pcall(function() hl:Destroy() end)
		end
		table.clear(x6.pc_highlights)
	end
	if x6.sculptor_selected then
		table.clear(x6.sculptor_selected)
	end
	if x6.pc_selected then
		table.clear(x6.pc_selected)
	end
	if x6.pc_offsets then
		table.clear(x6.pc_offsets)
	end
	x6.pc_active = false
	if x6.pc_box then
		pcall(function() x6.pc_box:Destroy() end)
		x6.pc_box = nil
	end
	if x6.sculptor_box then
		pcall(function() x6.sculptor_box:Destroy() end)
		x6.sculptor_box = nil
	end
	-- Shapes that own an instance hand it back here. Every loaded shape is asked,
	-- not just the current one, because this is the teardown that runs when the
	-- script is re-executed and the shape may have been switched since.
	for _, mod in pairs(loaded_shapes) do
		if type(mod) == "table" and mod.cleanup then
			pcall(mod.cleanup, x6, x1)
		end
	end
	for p, d in pairs(x6.a) do
		if d then
			-- Restore pooled, temporarily unparented parts too. One failed property
			-- write must not leave its velocity actuator alive.
			pcall(function() p.CanCollide = d.original_can_collide end)
			pcall(function() p.Anchored = d.original_anchored end)
			pcall(function() p.CustomPhysicalProperties = d.original_properties end)
			for _, instance in pairs({ d.at, d.lv, d.av }) do
				pcall(function() instance:Destroy() end)
			end
		end
	end
	x6.a = setmetatable({}, {__mode = "k"})
	table.clear(x6.active_array)
	table.clear(x6.claim_queue)
	table.clear(x6.pre)
	x6.n = 0
	if context.x4 and context.x4.clear_target_markers then pcall(context.x4.clear_target_markers) end
	-- Keep the exact owned folder even if a game reparents or renames the core.
	local core, holder = x6.b, x6.core_folder
	x6.b, x6.core_folder = nil, nil
	if core then pcall(function() core:Destroy() end) end
	if holder then pcall(function() holder:Destroy() end) end
	if x6.sg then
		pcall(function() x6.sg:Destroy() end)
		x6.sg = nil
	end
	if context.x5 then context.x5.g, context.x5.up = nil, nil end
	-- Only clear the handles if they are still ours. A superseded session tears
	-- itself down after a newer one has already registered, so clearing
	-- unconditionally would deregister the session that is actually running and
	-- leave the next re-execution with nothing to call.
	if getgenv()._GRAVITY_SESSION_ID == SESSION_ID then
		getgenv()._GRAVITY_SESSION_ID = nil
		getgenv()._GRAVITY_DESTROY = nil
	end
	if getgenv()._GRAVITY_CONTEXT == context then getgenv()._GRAVITY_CONTEXT = nil end
end

context.destroy = destroy
getgenv()._GRAVITY_DESTROY = destroy

local success, err = pcall(function()
	local UI_builder = load_module(SUB_DIR .. "UI.lua")
	if not UI_builder then error("Failed to load UI") end
	if x6.torn_down then return end
	local x5 = UI_builder(context)
	if x6.torn_down then return end
	context.x5 = x5

	local system_builder = load_module(SUB_DIR .. "System.lua")
	if not system_builder then error("Failed to load System") end
	if x6.torn_down then return end
	local sys = system_builder(context)
	if x6.torn_down then return end
	local x4 = sys.x4
	local x8 = sys.x8
	context.x4 = x4
	-- The UI reaches back into x8 to rebind hotkeys, so it has to be in the
	-- context before x5.st() builds the panel below.
	context.x8 = x8
	local controls_builder = load_module("RuntimeControls.lua")
	if not controls_builder then error("Failed to load RuntimeControls") end
	if x6.torn_down then return end
	context.controls = controls_builder(context)
	local custom_shapes = load_module("CustomShapes.lua")
	if not custom_shapes then error("Failed to load CustomShapes") end
	if x6.torn_down then return end
	context.custom_shapes = custom_shapes.create(context)

	x4.f3()
	x8.i()
	if x6.torn_down then return end
	x5.st()

	-- A saved k6 can already name a testing shape, in which case it is active
	-- without the user having picked it this session and none of the switch paths
	-- ever fire. Announcing it here is the whole point of the notice: the case
	-- where you did not choose the shape is the one where you most need telling.
	local startup_shape = get_shape(x1.k6)
	if startup_shape and startup_shape.Testing then
		x8.notify("Testing", tostring(x1.k6) .. " is still in testing.", 4)
	end
end)

-- Guarded, and nil-checked. destroy() nils these same two upvalues, and it is
-- reachable from another thread the whole time the pcall above is yielding on its
-- HTTP fetches: a re-execution calls this session's _GRAVITY_DESTROY (line 5), so
-- the old thread used to resume here and throw on a nil spin_conn -- outside every
-- pcall, which meant the lines below never ran and the superseded session was
-- never torn down at all.
if spin_conn then
	pcall(function() spin_conn:Disconnect() end)
	spin_conn = nil
end
if loading_sg then
	pcall(function() loading_sg:Destroy() end)
	loading_sg = nil
end

-- Another execution took over while this one was still loading. Everything this
-- session built has to go; destroy() now leaves the newer session's handles alone.
if getgenv()._GRAVITY_SESSION_ID ~= SESSION_ID then
	pcall(destroy)
	warn("Project Gravity: a newer execution took over during load; this one stopped.")
	return
end

if not success then
	destroy()
	warn("Project Gravity Initialization Failed: " .. tostring(err))
else
	getgenv()._GRAVITY_SESSION_ID = SESSION_ID
	-- Live integration handle. Consumers resolve it for each action so a reload
	-- or unload cannot leave them controlling the previous Gravity session.
	getgenv()._GRAVITY_CONTEXT = context
end
