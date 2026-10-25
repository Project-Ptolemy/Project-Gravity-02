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
	-- UTF-8 files and clipboard exports may begin with a byte-order mark.
	local source = trim(value:gsub("^\239\187\191", ""))
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

-- File discovery must compile the same source that the import review accepted.
M.normalize_source = clean_source

local function finite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function local_source_path(name, path)
	if type(path) ~= "string" then return nil end
	local normalized = path:gsub("\\", "/"):gsub("^%./", "")
	local extension = normalized:sub(-4):lower()
	-- Discovery derives the registered name from the exact filename. Do not
	-- adopt a differently cased name or a different directory on mobile storage.
	if normalized:sub(1, -5) == DIRECTORY .. "/" .. name and (extension == ".lua" or extension == ".txt") then
		return normalized
	end
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
	local keys = {}
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
			and (type(control.Key) ~= "string" or trim(control.Key) == "" or control.Key:find("%c")) then
			return false, prefix .. "Key must be a nonempty string."
		end
		if control.Key ~= nil then
			if keys[control.Key] then return false, prefix .. "Key '" .. control.Key .. "' is already used by another control." end
			keys[control.Key] = true
		end
		if control.Desc ~= nil and type(control.Desc) ~= "string" then
			return false, prefix .. "Desc must be a string."
		end
		if kind == "Slider" then
			for _, flag in ipairs({ "IntOnly", "ExactMax", "LegacyToggle" }) do
				if control[flag] ~= nil and type(control[flag]) ~= "boolean" then
					return false, prefix .. flag .. " must be true or false."
				end
			end
			if not finite(control.Min) or not finite(control.Max) or control.Max <= control.Min
				or not finite(control.Max - control.Min) then
				return false, prefix .. "Min and Max must be finite numbers, with Max greater than Min."
			end
			local divisor = control.Div == nil and 1 or control.Div
			if not finite(divisor) or divisor <= 0 then return false, prefix .. "Div must be a positive finite number." end
			local maximum = control.Max
			if control.Name:lower():find("speed", 1, true) and not control.ExactMax then maximum = maximum + 300 end
			if not finite(control.Min / divisor) or not finite(maximum / divisor) then
				return false, prefix .. "Min, Max and Div exceed the numeric range."
			end
			if control.Default ~= nil and not finite(control.Default) then
				return false, prefix .. "Default must be a finite number."
			end
			local value = control.Default == nil and control.Min / divisor or control.Default
			if not finite(value) or not finite(value * divisor) then
				return false, prefix .. "Default and Div exceed the numeric range."
			end
			if value < control.Min / divisor or value > maximum / divisor then
				return false, prefix .. "Default must fit the slider range after applying Div."
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

local function validate_module(shape)
	if type(shape) ~= "table" or type(shape.f2) ~= "function" then
		return false, "The module must return a table with an f2 function."
	end
	for _, callback in ipairs({ "px", "cleanup" }) do
		if shape[callback] ~= nil and type(shape[callback]) ~= "function" then
			return false, "The module's " .. callback .. " must be a function."
		end
	end
	for _, flag in ipairs({ "NoBlend", "AlwaysProcess", "ContinuousMotion", "FrameTracking", "Testing" }) do
		if shape[flag] ~= nil and type(shape[flag]) ~= "boolean" then
			return false, "The module's " .. flag .. " must be true or false."
		end
	end
	local mobile = shape.MobileControls
	if mobile ~= nil then
		if type(mobile) ~= "table" then return false, "The module's MobileControls must be a table." end
		if mobile.Action ~= nil and (type(mobile.Action) ~= "string" or trim(mobile.Action) == "") then
			return false, "MobileControls.Action must be a nonempty string."
		end
		if mobile.Range ~= nil and (not finite(mobile.Range) or mobile.Range <= 0) then
			return false, "MobileControls.Range must be a positive finite number."
		end
	end
	return validate_controls(shape.Controls)
end

-- Disk discovery and pasted imports must accept the same module contract.
function M.validate_module(shape)
	local ran, ok, result = pcall(validate_module, shape)
	if not ran then return false, "Could not inspect the module: " .. tostring(ok) end
	return ok, result
end

function M.create(context)
	local manager = {}
	local busy = false
	-- A reviewed module is used as-is when committed. Running its initializer a
	-- second time can duplicate connections or allocate another copy of its data.
	-- Weak keys release abandoned reviews along with their potentially large source.
	local prepared = setmetatable({}, { __mode = "k" })

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
				local found
				for _, path in ipairs(files) do
					if type(path) == "string" then
						local basename = path:match("([^/\\]+)$")
						local lower = basename and basename:lower()
						if lower == name:lower() .. ".lua" or lower == name:lower() .. ".txt" then
							if found then return true, true, nil end
							found = basename
						end
					end
				end
				return true, found ~= nil, found
			end
		end
		if type(isfile) == "function" then
			local found
			for _, extension in ipairs({ ".lua", ".txt" }) do
				local ok, exists = pcall(isfile, DIRECTORY .. "/" .. name .. extension)
				if not ok or type(exists) ~= "boolean" then return false, false end
				if exists then
					if found then return true, true, nil end
					found = name .. extension
				end
			end
			return true, found ~= nil, found
		end
		return false, false
	end

	local function available(name, existing_path)
		if collision(name) then return false, "A shape named '" .. name .. "' already exists. Choose another name." end
		local _, exists, basename = inspect_disk(name)
		local same_file = existing_path and basename and existing_path:match("([^/]+)$"):lower() == basename:lower()
		if exists and not same_file then return false, "A file for '" .. name .. "' already exists. Choose another name." end
		return true
	end

	local function validate(raw_name, raw_source, source_path)
		if not live() then return false, "This Gravity session has ended." end
		if type(context.x2) ~= "table" or type(context.loaded_shapes) ~= "table"
			or type(context.local_shapes) ~= "table" then
			return false, "The shape registry is unavailable."
		end
		local name, name_error = clean_name(raw_name)
		if not name then return false, name_error end
		local source, source_error = clean_source(raw_source)
		if not source then return false, source_error end
		local existing_path = local_source_path(name, source_path)
		local free, duplicate_error = available(name, existing_path)
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
		local valid_module, module_error = M.validate_module(shape)
		if not valid_module then return false, module_error end
		local controls = context.plugin_controls
		if not controls or type(controls.defaults) ~= "function" then
			return false, "Shape controls are unavailable."
		end
		local defaults_ok, defaults = pcall(controls.defaults, shape.Controls)
		if not defaults_ok or type(defaults) ~= "table" then
			return false, "The module's Controls could not load: " .. tostring(defaults)
		end
		if not live() then return false, "This Gravity session has ended." end
		return true, { name = name, source = source, module = shape, defaults = defaults, existing_path = existing_path }
	end

	function manager.validate(raw_name, raw_source, source_path)
		local ran, ok, result = pcall(validate, raw_name, raw_source, source_path)
		if not ran then return false, "Could not validate the shape: " .. tostring(ok) end
		if ok then
			-- Keep the accepted identity private; changing the review summary cannot
			-- redirect its saved filename or substitute unreviewed source/module data.
			prepared[result] = { raw_name = raw_name, raw_source = raw_source,
				name = result.name, source = result.source, module = result.module, existing_path = result.existing_path }
		end
		return ok, result
	end

	local function add(raw_name, raw_source, review)
		if not live() then return false, "This Gravity session has ended." end
		local entry
		if review ~= nil then
			entry = prepared[review]
			if not entry or entry.raw_name ~= raw_name or entry.raw_source ~= raw_source then
				return false, "Your draft changed or its review has expired. Review it again before adding."
			end
		else
			local valid, result = manager.validate(raw_name, raw_source)
			if not valid then return false, result end
			review, entry = result, prepared[result]
		end
		-- A plugin may retain and change its table after initialization. Recheck
		-- the contract and derive fresh defaults without executing its source again.
		local valid_module, module_error = M.validate_module(entry.module)
		if not valid_module then return false, module_error end
		local defaults = context.plugin_controls.defaults(entry.module.Controls)
		-- Module initialization can yield; another import may have taken this name.
		local free, duplicate_error = available(entry.name, entry.existing_path)
		if not free then return false, duplicate_error end
		if not live() then return false, "This Gravity session has ended." end
		local path = entry.existing_path or DIRECTORY .. "/" .. entry.name .. ".lua"
		local persisted, save_error = false, nil
		if entry.existing_path then
			if type(readfile) ~= "function" then return false, "The source file cannot be checked. Paste its script or review another file." end
			local read, current = pcall(readfile, path)
			if not read or current ~= entry.raw_source then
				return false, "The source file changed or could not be read. Review the file again before adding."
			end
			persisted = true -- Register the existing file; never rewrite a reviewed source.
		elseif type(writefile) == "function" then
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
					local wrote, result = pcall(writefile, path, entry.source)
					persisted = wrote and result ~= false
					if not persisted then save_error = wrote and "the file writer reported a failure" or result end
					if persisted and type(readfile) == "function" then
						local read, saved_source = pcall(readfile, path)
						if not read or saved_source ~= entry.source then
							persisted = false
							save_error = read and "the saved file did not match the complete script" or "the saved file could not be verified"
						end
					end
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
		context.x2[entry.name] = defaults
		prepared[review] = nil
		if persisted then context.local_shapes[entry.name] = path end
		-- Saving bytes and discovering local modules on the next launch are
		-- separate capabilities. Match main.lua's local-shape discovery gate.
		local reloadable = persisted and type(listfiles) == "function" and type(readfile) == "function"

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

	function manager.add(raw_name, raw_source, review)
		if busy then return false, "A custom shape is already being added." end
		busy = true
		local ran, ok, result = pcall(add, raw_name, raw_source, review)
		busy = false
		if not ran then return false, "Could not add the shape: " .. tostring(ok) end
		return ok, result
	end

	return manager
end

return M
