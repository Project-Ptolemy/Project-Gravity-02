-- Manual shape imports share the same module contract as GravityShapes files.
-- Validation executes the module, just as the existing local-file loader does.
local M = {}
local DIRECTORY = "GravityShapes"
local MAX_NAME_BYTES = 80
-- Large builder projects can export many megabytes of vertex coordinates.
local MAX_SOURCE_BYTES = 64 * 1024 * 1024

local function trim(value)
	return value:match("^%s*(.-)%s*$")
end

local function clean_name(value)
	if type(value) ~= "string" then return nil, "Enter a name for your shape." end
	local name = trim(value)
	local lower = name:lower()
	if lower:match("%.lua$") or lower:match("%.txt$") then
		name = trim(name:sub(1, -5))
	end
	if name == "" then return nil, "Enter a name for your shape." end
	if #name > MAX_NAME_BYTES then return nil, "Keep the shape name within 80 bytes." end
	if name:find('[<>:"/\\|?*]') or name:find("%c") then
		return nil, 'The name cannot contain control characters or < > : " / \\ | ? *.'
	end
	if name:sub(-1) == "." then return nil, "The shape name cannot end with a dot." end
	local device = (name:match("^[^%.]+") or name):upper()
	if device == "CON" or device == "PRN" or device == "AUX" or device == "NUL"
		or device:match("^COM[1-9]$") or device:match("^LPT[1-9]$") then
		return nil, "That name is reserved by the file system. Choose another name."
	end
	return name
end

local function clean_source(value)
	if type(value) ~= "string" then return nil, "Paste the shape's Lua module." end
	if #value > MAX_SOURCE_BYTES then return nil, "The shape module must be at most 64 MiB." end
	local source = trim(value)
	-- Accept a copied Markdown code block without storing the surrounding fence.
	if source:sub(1, 3) == "```" then
		local language, body = source:match("^```([^\r\n]*)\r?\n(.-)\r?\n```$")
		language = language and trim(language):lower()
		if body and (language == "" or language == "lua" or language == "luau") then
			source = trim(body)
		end
	end
	if source == "" then return nil, "Paste the shape's Lua module." end
	return source
end

local function finite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function validate_controls(controls)
	if controls == nil then return true end
	if type(controls) ~= "table" then return false, "The module's Controls must be a table." end
	local count = 0
	for key in pairs(controls) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false, "Controls must be an array of control tables."
		end
		count = count + 1
	end
	for index = 1, count do
		local control = controls[index]
		local prefix = "Control " .. index .. ": "
		if type(control) ~= "table" then return false, prefix .. "expected a control table." end
		local kind = control.Type
		if kind ~= "Slider" and kind ~= "Toggle" and kind ~= "TextBox" and kind ~= "Button" then
			return false, prefix .. "Type must be Slider, Toggle, TextBox or Button."
		end
		if type(control.Name) ~= "string" or trim(control.Name) == "" then
			return false, prefix .. "Name must be a nonempty string."
		end
		if (kind ~= "Button" or control.Key ~= nil)
			and (type(control.Key) ~= "string" or control.Key == "") then
			return false, prefix .. "Key must be a nonempty string."
		end
		if control.Desc ~= nil and type(control.Desc) ~= "string" then
			return false, prefix .. "Desc must be a string."
		end
		if kind == "Slider" then
			if not finite(control.Min) or not finite(control.Max) or control.Max <= control.Min
				or not finite(control.Max - control.Min) then
				return false, prefix .. "Min and Max must be finite numbers, with Max greater than Min."
			end
			local divisor = control.Div == nil and 1 or control.Div
			if not finite(divisor) or divisor <= 0 then return false, prefix .. "Div must be a positive finite number." end
			if control.Default ~= nil and not finite(control.Default) then
				return false, prefix .. "Default must be a finite number."
			end
			local value = control.Default == nil and control.Min / divisor or control.Default
			if not finite(value) or not finite(value * divisor) then
				return false, prefix .. "Default and Div exceed the numeric range."
			end
		elseif kind == "Toggle" then
			if control.Default ~= nil and type(control.Default) ~= "boolean" then
				return false, prefix .. "Default must be true or false."
			end
		elseif kind == "TextBox" then
			if control.Default ~= nil and type(control.Default) ~= "string" then
				return false, prefix .. "Default must be a string."
			end
			if control.MaxChars ~= nil and (not finite(control.MaxChars)
				or control.MaxChars < 0 or control.MaxChars % 1 ~= 0) then
				return false, prefix .. "MaxChars must be a nonnegative whole number."
			end
		elseif type(control.Callback) ~= "function" then
			return false, prefix .. "Button needs a Callback function."
		end
	end
	return true
end

function M.create(context)
	local manager = {}
	local busy = false

	local function live()
		local state = context.x6
		if state and (state.torn_down or state.destroying) then return false end
		if context.session_id and type(getgenv) == "function" then
			local ok, globals = pcall(getgenv)
			if not ok or not globals or globals._GRAVITY_SESSION_ID ~= context.session_id then return false end
		end
		return true
	end

	local function collision(name)
		local lower = name:lower()
		for _, registry in ipairs({ context.x2, context.local_shapes or {}, context.loaded_shapes or {} }) do
			for existing in pairs(registry) do
				if type(existing) == "string" and existing:lower() == lower then return true end
			end
		end
		return false
	end

	-- The first result says whether checking the disk was possible. Failure to
	-- inspect it still allows a session shape, but must never risk an overwrite.
	local function inspect_disk(name)
		if type(isfolder) == "function" then
			local ok, exists = pcall(isfolder, DIRECTORY)
			if ok and exists == false then return true, false end
		end
		if type(listfiles) == "function" then
			local ok, files = pcall(listfiles, DIRECTORY)
			if ok and type(files) == "table" then
				for _, path in ipairs(files) do
					if type(path) == "string" then
						local basename = path:match("([^/\\]+)$")
						local lower = basename and basename:lower()
						if lower == name:lower() .. ".lua" or lower == name:lower() .. ".txt" then
							return true, true
						end
					end
				end
				return true, false
			end
		end
		if type(isfile) == "function" then
			for _, extension in ipairs({ ".lua", ".txt" }) do
				local ok, exists = pcall(isfile, DIRECTORY .. "/" .. name .. extension)
				if not ok or type(exists) ~= "boolean" then return false, false end
				if exists then return true, true end
			end
			return true, false
		end
		return false, false
	end

	local function available(name)
		if collision(name) then return false, "A shape named '" .. name .. "' already exists. Choose another name." end
		local _, exists = inspect_disk(name)
		if exists then return false, "A file for '" .. name .. "' already exists. Choose another name." end
		return true
	end

	local function validate(raw_name, raw_source)
		if not live() then return false, "This Gravity session has ended." end
		if type(context.x2) ~= "table" or type(context.loaded_shapes) ~= "table"
			or type(context.local_shapes) ~= "table" then
			return false, "The shape registry is unavailable."
		end
		local name, name_error = clean_name(raw_name)
		if not name then return false, name_error end
		local source, source_error = clean_source(raw_source)
		if not source then return false, source_error end
		local free, duplicate_error = available(name)
		if not free then return false, duplicate_error end
		if not live() then return false, "This Gravity session has ended." end

		local compiler = loadstring
		if type(compiler) ~= "function" and type(getgenv) == "function" then
			local ok, globals = pcall(getgenv)
			if ok and globals then compiler = globals.loadstring end
		end
		if type(compiler) ~= "function" then return false, "This executor cannot compile Lua modules." end
		local compiled, chunk, compile_error = pcall(compiler, source, "Custom shape: " .. name)
		if not compiled or type(chunk) ~= "function" then
			return false, "Lua syntax error: " .. tostring(compiled and compile_error or chunk)
		end
		local ran, shape = pcall(chunk)
		if not live() then return false, "This Gravity session has ended." end
		if not ran then return false, "The module could not load: " .. tostring(shape) end
		if type(shape) ~= "table" or type(shape.f2) ~= "function" then
			return false, "The module must return a table with an f2 function."
		end
		local valid_controls, controls_error = validate_controls(shape.Controls)
		if not valid_controls then return false, controls_error end
		local controls = context.plugin_controls
		if not controls or type(controls.defaults) ~= "function" then
			return false, "Shape controls are unavailable."
		end
		local defaults_ok, defaults = pcall(controls.defaults, shape.Controls)
		if not defaults_ok or type(defaults) ~= "table" then
			return false, "The module's Controls could not load: " .. tostring(defaults)
		end
		if not live() then return false, "This Gravity session has ended." end
		return true, { name = name, source = source, module = shape, defaults = defaults }
	end

	function manager.validate(raw_name, raw_source)
		local ran, ok, result = pcall(validate, raw_name, raw_source)
		if not ran then return false, "Could not validate the shape: " .. tostring(ok) end
		return ok, result
	end

	local function add(raw_name, raw_source)
		local valid, entry = manager.validate(raw_name, raw_source)
		if not valid then return false, entry end
		-- Module initialization can yield; another import may have taken this name.
		local free, duplicate_error = available(entry.name)
		if not free then return false, duplicate_error end
		if not live() then return false, "This Gravity session has ended." end
		local path = DIRECTORY .. "/" .. entry.name .. ".lua"
		local persisted, save_error = false, nil
		if type(writefile) == "function" then
			local safe, exists = inspect_disk(entry.name)
			if exists then return false, "A file for '" .. entry.name .. "' already exists. Choose another name." end
			if safe then
				if type(makefolder) == "function" then
					local should_create = true
					if type(isfolder) == "function" then
						local checked, exists_folder = pcall(isfolder, DIRECTORY)
						should_create = not checked or not exists_folder
					end
					if should_create then pcall(makefolder, DIRECTORY) end
				end
				-- Folder helpers may yield too; check again before touching the file.
				local still_safe, now_exists = inspect_disk(entry.name)
				if now_exists then return false, "A file for '" .. entry.name .. "' already exists. Choose another name." end
				if not live() then return false, "This Gravity session has ended." end
				if collision(entry.name) then return false, "That shape name was just added. Choose another name." end
				if still_safe then
					persisted, save_error = pcall(writefile, path, entry.source)
				else
					save_error = "existing files could not be checked"
				end
			else
				save_error = "existing files could not be checked"
			end
		else
			save_error = "file saving is unavailable"
		end
		if not live() then return false, "This Gravity session has ended." end
		if collision(entry.name) then return false, "That shape name was just added. Choose another name." end
		context.loaded_shapes[entry.name] = entry.module
		context.x2[entry.name] = entry.defaults
		if persisted then context.local_shapes[entry.name] = path end
		-- Saving bytes and discovering local modules on the next launch are
		-- separate capabilities. Match main.lua's local-shape discovery gate.
		local reloadable = persisted and type(isfolder) == "function" and type(makefolder) == "function"
			and type(listfiles) == "function" and type(readfile) == "function"

		local state, ui = context.x6, context.x5
		if state and type(state.populate_modes) == "function" then
			local filter = ""
			if type(state.mode_filter) == "function" then
				local ok, value = pcall(state.mode_filter)
				if ok and type(value) == "string" then filter = value end
			end
			if live() then pcall(state.populate_modes, filter) end
		end
		if live() and ui and type(ui.refresh_keybinds) == "function" then pcall(ui.refresh_keybinds) end
		local switched = false
		if live() and context.x4 and type(context.x4.switch_shape) == "function" then
			local ok, result = pcall(context.x4.switch_shape, entry.name, reloadable)
			switched = ok and result == true
		end
		local message = "Added '" .. entry.name .. "'. "
		if persisted then
			message = message .. "Saved to " .. path .. "."
			if not reloadable then message = message .. " Automatic loading next launch is unavailable in this executor." end
		else
			message = message .. "Available for this session only: " .. tostring(save_error) .. "."
		end
		return true, { name = entry.name, persisted = persisted, reloadable = reloadable, path = persisted and path or nil,
			message = message, switched = switched }
	end

	function manager.add(raw_name, raw_source)
		if busy then return false, "A custom shape is already being added." end
		busy = true
		local ran, ok, result = pcall(add, raw_name, raw_source)
		busy = false
		if not ran then return false, "Could not add the shape: " .. tostring(ok) end
		return ok, result
	end

	return manager
end

return M
