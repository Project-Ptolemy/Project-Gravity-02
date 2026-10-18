-- Retained draft -> review -> add. Screen pixels keep touch targets independent
-- of the main panel's UI scale; keyboard overlap only reduces the scroll area.
return function(context, parent)
	local x6, inputService = context.x6, context.v1
	local colors = {
		panel = Color3.fromRGB(17, 20, 29), field = Color3.fromRGB(25, 30, 42),
		text = Color3.fromRGB(243, 247, 255), muted = Color3.fromRGB(168, 180, 200),
		accent = Color3.fromRGB(83, 101, 235), line = Color3.fromRGB(54, 66, 88),
		error = Color3.fromRGB(255, 160, 160), success = Color3.fromRGB(127, 226, 181),
	}
	local function create(class, name, owner, props)
		local item = Instance.new(class)
		item.Name = name
		for key, value in pairs(props or {}) do item[key] = value end
		item.Parent = owner
		return item
	end
	local function round(item, radius)
		create("UICorner", "Corner", item, { CornerRadius = UDim.new(0, radius or 10) })
	end
	local function padding(item, amount)
		create("UIPadding", "Padding", item, {
			PaddingLeft = UDim.new(0, amount), PaddingRight = UDim.new(0, amount),
			PaddingTop = UDim.new(0, amount), PaddingBottom = UDim.new(0, amount),
		})
	end
	local function stack(name, owner, order, gap)
		local item = create("Frame", name, owner, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, ZIndex = 202,
		})
		create("UIListLayout", "Layout", item, { Padding = UDim.new(0, gap or 10), SortOrder = Enum.SortOrder.LayoutOrder })
		return item
	end
	local function label(name, owner, text, size, order)
		return create("TextLabel", name, owner, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = text,
			TextColor3 = colors.muted, Font = Enum.Font.Gotham, TextSize = size or 14,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order or 0, ZIndex = 203,
		})
	end
	local function button(name, owner, text)
		local item = create("TextButton", name, owner, {
			BackgroundColor3 = colors.field, BorderSizePixel = 0, Text = text,
			TextColor3 = colors.text, Font = Enum.Font.GothamBold, TextSize = 14,
			TextWrapped = true, AutoButtonColor = true, ZIndex = 204,
		})
		round(item)
		return item
	end
	local function field(name, owner, placeholder, multiline)
		return create("TextBox", name, owner, {
			BackgroundColor3 = colors.field, BorderSizePixel = 0, Text = "",
			PlaceholderText = placeholder, PlaceholderColor3 = colors.muted,
			TextColor3 = colors.text, Font = multiline and Enum.Font.Code or Enum.Font.Gotham,
			TextSize = multiline and 14 or 16, ClearTextOnFocus = false,
			MultiLine = multiline == true, TextWrapped = true, TextEditable = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
			Size = UDim2.new(1, 0, 0, multiline and 168 or 52), ZIndex = 204,
		})
	end
	local overlay = create("TextButton", "CustomShapeEditor", parent, {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.28, BorderSizePixel = 0, Text = "", Visible = false,
		Active = true, Selectable = false, AutoButtonColor = false, Modal = true, ZIndex = 200,
	})
	local dialog = create("Frame", "CustomShapeDialog", overlay, {
		BackgroundColor3 = colors.panel, BorderSizePixel = 0, Active = true, ZIndex = 201, ClipsDescendants = true,
	})
	create("UIStroke", "Outline", dialog, { Color = colors.line, Thickness = 1 })
	round(dialog, 16)
	local heading = label("EditorTitle", dialog, "Add a custom shape", 21)
	heading.Font, heading.TextColor3 = Enum.Font.GothamBold, colors.text
	heading.Position, heading.Size = UDim2.new(0, 18, 0, 18), UDim2.new(1, -116, 0, 30)
	heading.AutomaticSize = Enum.AutomaticSize.None
	local close = button("CloseShapeEditor", dialog, "Close")
	close.Position, close.Size = UDim2.new(1, -86, 0, 10), UDim2.new(0, 72, 0, 48)
	local steps = create("Frame", "ImportSteps", dialog, {
		BackgroundTransparency = 1, Position = UDim2.new(0, 18, 0, 66), Size = UDim2.new(1, -36, 0, 32), ZIndex = 202,
	})
	local importStep = label("ImportStep", steps, "01  Import script", 13)
	local reviewStep = label("ReviewStep", steps, "02  Review & add", 13)
	for index, item in ipairs({ importStep, reviewStep }) do
		item.Position, item.Size = UDim2.new((index - 1) * 0.5, 0, 0, 0), UDim2.new(0.5, -4, 1, 0)
		item.AutomaticSize, item.Font = Enum.AutomaticSize.None, Enum.Font.GothamBold
		item.TextYAlignment = Enum.TextYAlignment.Center
	end
	local body = create("ScrollingFrame", "EditorFields", dialog, {
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageColor3 = colors.muted, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0), CanvasPosition = Vector2.new(0, 0),
		ScrollingDirection = Enum.ScrollingDirection.Y, Active = true, ZIndex = 202,
	})
	create("UIPadding", "ScrollPadding", body, { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 16) })
	create("UIListLayout", "FieldLayout", body, { Padding = UDim.new(0, 16), SortOrder = Enum.SortOrder.LayoutOrder })
	local status = label("ShapeStatus", body, "", 14, 0)
	status.Visible = false
	local form = stack("ImportForm", body, 1, 16)
	label("LuaHelp", form, "Copy the Lua export from Shape Studio, then paste it below. Your draft stays here when you close this window.", 14, 1)
	local nameGroup = stack("NameGroup", form, 2, 8)
	local nameLabel = label("NameLabel", nameGroup, "Shape name", 14, 1)
	nameLabel.TextColor3, nameLabel.Font = colors.text, Enum.Font.GothamBold
	local name = field("ShapeName", nameGroup, "e.g. Orbit bloom", false)
	name.LayoutOrder = 2
	round(name); padding(name, 12)
	local nameOutline = create("UIStroke", "FieldOutline", name, { Color = colors.line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local sourceGroup = stack("SourceGroup", form, 3, 8)
	local sourceLabel = label("SourceLabel", sourceGroup, "Lua script", 14, 1)
	sourceLabel.TextColor3, sourceLabel.Font = colors.text, Enum.Font.GothamBold
	local pasteActions = create("Frame", "PasteActions", sourceGroup, {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 2, ZIndex = 203,
	})
	local paste = button("PasteShape", pasteActions, "Paste clipboard")
	paste.Size = UDim2.new(0.62, -4, 1, 0)
	local selectAll = button("SelectShapeSource", pasteActions, "Select all")
	selectAll.Position, selectAll.Size = UDim2.new(0.62, 4, 0, 0), UDim2.new(0.38, -4, 1, 0)
	local codeScroll = create("ScrollingFrame", "ShapeCodeScroll", sourceGroup, {
		BackgroundColor3 = colors.field, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 200),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0),
		CanvasPosition = Vector2.new(0, 0), ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 5, ScrollBarImageColor3 = colors.muted, Active = true, LayoutOrder = 3, ZIndex = 203,
	})
	round(codeScroll); padding(codeScroll, 12)
	local sourceOutline = create("UIStroke", "FieldOutline", codeScroll, { Color = colors.line, Thickness = 1 })
	local luaSource = field("LuaSource", codeScroll, "Paste the complete .lua script here.\n\nOn a phone, press and hold to paste.", true)
	luaSource.AutomaticSize, luaSource.BackgroundTransparency = Enum.AutomaticSize.Y, 1
	local sourceInfo = label("ShapeSourceInfo", sourceGroup, "No script pasted yet", 12, 4)
	label("ValidationHelp", form, "Review checks the Lua module and its controls. Review and Add both run the module.", 12, 4)
	local review = stack("ShapeReview", body, 2, 16)
	review.Visible = false
	local reviewTitle = label("ReviewShapeName", review, "", 24, 1)
	reviewTitle.Font, reviewTitle.TextColor3 = Enum.Font.GothamBold, colors.text
	local reviewDetails = label("ReviewDetails", review, "", 14, 2)
	local reviewControls = label("ReviewControls", review, "", 14, 3)
	local reviewStorage = label("ReviewStorage", review, "", 14, 4)
	label("ReviewHelp", review, "Add & use puts this shape in your modes and selects it immediately. Your other shapes stay available.", 14, 5)
	local complete = stack("ShapeAdded", body, 3, 16)
	complete.Visible = false
	local addedTitle = label("AddedShapeName", complete, "", 24, 1)
	addedTitle.Font, addedTitle.TextColor3 = Enum.Font.GothamBold, colors.success
	local addedHelp = label("AddedShapeHelp", complete, "", 14, 2)
	local footer = create("Frame", "EditorActions", dialog, {
		BackgroundColor3 = colors.panel, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 76),
		Position = UDim2.new(0, 0, 1, -76), ZIndex = 203,
	})
	create("Frame", "ActionDivider", footer, { Size = UDim2.new(1, -36, 0, 1), Position = UDim2.new(0, 18, 0, 0), BackgroundColor3 = colors.line, BorderSizePixel = 0, ZIndex = 203 })
	local back = button("BackShapeEditor", footer, "Back")
	back.Position, back.Size = UDim2.new(0, 18, 0, 12), UDim2.new(0.34, -22, 0, 48)
	local check = button("CheckShape", footer, "Review shape")
	check.Position, check.Size = UDim2.new(0, 18, 0, 12), UDim2.new(1, -36, 0, 48)
	local add = button("AddShape", footer, "Add & use")
	add.Position, add.Size = UDim2.new(0.34, 4, 0, 12), UDim2.new(0.66, -22, 0, 48)
	local another = button("AnotherShape", footer, "Add another")
	another.Position, another.Size = UDim2.new(0, 18, 0, 12), UDim2.new(0.5, -22, 0, 48)
	local done = button("DoneShapeEditor", footer, "Done")
	done.Position, done.Size = UDim2.new(0.5, 4, 0, 12), UDim2.new(0.5, -22, 0, 48)
	check.BackgroundColor3, add.BackgroundColor3, done.BackgroundColor3 = colors.accent, colors.accent, colors.accent

	local connections, closed = {}, false
	local stage, busy, changing, reviewed = "import", false, false, nil
	local function connect(signal, callback)
		local connection = signal:Connect(callback)
		connections[#connections + 1] = connection
	end
	local function alive() return not closed and not x6.torn_down and overlay.Parent ~= nil end
	local function setStatus(message, kind)
		status.Text, status.Visible = tostring(message or ""), message ~= nil and message ~= ""
		status.TextColor3 = colors[kind] or colors.muted
		if message ~= nil and message ~= "" then body.CanvasPosition = Vector2.new(0, 0) end
	end
	local function clipboardReader()
		if type(getclipboard) == "function" then return getclipboard end
		if type(getgenv) == "function" then
			local ok, globals = pcall(getgenv)
			if ok and globals and type(globals.getclipboard) == "function" then return globals.getclipboard end
		end
	end
	local function bytes(size)
		if size >= 1024 * 1024 then return string.format("%.1f MiB", size / (1024 * 1024)) end
		if size >= 1024 then return string.format("%.1f KiB", size / 1024) end
		return tostring(size) .. " bytes"
	end
	local function refresh()
		form.Visible, review.Visible, complete.Visible = stage == "import", stage == "review", stage == "added"
		check.Visible, add.Visible, back.Visible = stage == "import", stage == "review", stage == "review"
		another.Visible, done.Visible = stage == "added", stage == "added"
		for _, item in ipairs({ check, add, back, paste, selectAll, another }) do
			item.Active, item.AutoButtonColor = not busy, not busy
			item.TextTransparency = busy and 0.4 or 0
		end
		add.Active = not busy and stage == "review"
		check.Text, add.Text = busy and "Checking..." or "Review shape", busy and "Adding..." or "Add & use"
		name.TextEditable, luaSource.TextEditable = not busy, not busy
		importStep.TextColor3 = stage == "import" and colors.text or colors.muted
		reviewStep.TextColor3 = stage ~= "import" and colors.success or colors.muted
		local canPaste = clipboardReader() ~= nil
		paste.Visible = canPaste
		selectAll.Position = canPaste and UDim2.new(0.62, 4, 0, 0) or UDim2.new(0, 0, 0, 0)
		selectAll.Size = canPaste and UDim2.new(0.38, -4, 1, 0) or UDim2.new(1, 0, 1, 0)
		local length = #luaSource.Text
		sourceInfo.Text = length == 0 and "No script pasted yet" or (bytes(length) .. " pasted  /  Lua module")
	end
	local function releaseFocus()
		for _, item in ipairs({ name, luaSource }) do if item:IsFocused() then item:ReleaseFocus() end end
	end
	local function layout()
		if not alive() then return end
		local size, origin = overlay.AbsoluteSize, overlay.AbsolutePosition
		local width, height = size.X, size.Y
		if width <= 0 or height <= 0 then return end
		-- Keyboard coordinates include the ScreenGui's safe inset.
		local keyboardTop
		if overlay.Visible and inputService then
			pcall(function()
				if inputService.OnScreenKeyboardVisible == true then
					local keyboardPosition = inputService.OnScreenKeyboardPosition
					if keyboardPosition.Y > 0 then keyboardTop = keyboardPosition.Y - origin.Y end
					if not keyboardTop then keyboardTop = height - inputService.OnScreenKeyboardSize.Y end
				end
			end)
		end
		if keyboardTop then height = math.min(height, math.max(0, keyboardTop)) end
		local margin = keyboardTop and 4 or (width < 480 and 8 or 18)
		local w, h = math.min(660, width - margin * 2), math.min(760, height - margin * 2)
		dialog.Size, dialog.Position = UDim2.new(0, w, 0, h), UDim2.new(0, (width - w) * 0.5, 0, (height - h) * 0.5)
		local compact = h < 450
		steps.Visible = not compact
		local top, bottom = compact and 62 or 110, compact and 68 or 78
		-- In the smallest landscape keyboard area, keep the focused field and
		-- Close reachable. The action row returns when the keyboard is dismissed.
		footer.Visible = h >= 150
		if not footer.Visible then bottom = 0 end
		footer.Size, footer.Position = UDim2.new(1, 0, 0, bottom), UDim2.new(0, 0, 1, -bottom)
		body.Position, body.Size = UDim2.new(0, 18, 0, top), UDim2.new(1, -36, 0, math.max(0, h - top - bottom))
		codeScroll.Size = UDim2.new(1, 0, 0, compact and 164 or 220)
		heading.TextSize = w < 360 and 17 or 21
	end
	local function showField(item)
		if not overlay.Visible or stage ~= "import" then return end
		local relative = item.AbsolutePosition.Y - body.AbsolutePosition.Y + body.CanvasPosition.Y
		body.CanvasPosition = Vector2.new(0, math.max(0, relative - 10))
	end
	local function edited()
		if changing then return end
		stage, reviewed = "import", nil
		nameOutline.Color, sourceOutline.Color = colors.line, colors.line
		setStatus(nil); refresh()
	end
	connect(name:GetPropertyChangedSignal("Text"), edited)
	connect(luaSource:GetPropertyChangedSignal("Text"), function()
		if changing then return end
		-- Only suggest a builder name when the user has not supplied one.
		if name.Text:match("^%s*$") then
			local suggested = luaSource.Text:sub(1, 512):match("^%s*%-%- Project Gravity Shape Builder \194\183 ([^\r\n]+)")
			if suggested and #suggested <= 80 and not suggested:find('[<>:"/\\|?*]') then
				changing = true; name.Text = suggested; changing = false
			end
		end
		edited()
	end)
	for _, item in ipairs({ name, luaSource }) do connect(item.Focused, function() layout(); showField(item) end) end
	connect(name.FocusLost, function(enterPressed)
		if enterPressed and overlay.Visible and stage == "import" and not busy then luaSource:CaptureFocus() end
	end)
	local function closeEditor()
		if not alive() then return end
		releaseFocus(); overlay.Visible = false
	end
	local function run(adding)
		if busy or not alive() or (adding and stage ~= "review") or (not adding and stage ~= "import") then return end
		local requestedName, requestedSource = name.Text, luaSource.Text
		if adding and (not reviewed or reviewed.name ~= requestedName or reviewed.source ~= requestedSource) then
			stage, reviewed = "import", nil
			setStatus("Your draft changed. Review it again before adding."); refresh(); return
		end
		releaseFocus(); busy = true; refresh()
		setStatus(adding and "Adding your shape..." or "Checking the module and its controls...")
		local ok, success, result = pcall(function()
			local manager = context.custom_shapes
			if not manager then
				local module = context.load_module("CustomShapes.lua")
				if not module then return false, "Could not load custom shapes. Try again." end
				if not alive() then return false, "Session has ended." end
				manager = module.create(context); context.custom_shapes = manager
			end
			if not alive() then return false, "Session has ended." end
			if adding then return manager.add(requestedName, requestedSource) end
			return manager.validate(requestedName, requestedSource)
		end)
		busy = false
		if not alive() then return end
		if not ok or not success then
			stage, reviewed = "import", nil
			local message = tostring(ok and result or success)
			setStatus(message, "error")
			if message:lower():find("name", 1, true) then nameOutline.Color = colors.error else sourceOutline.Color = colors.error end
		elseif adding then
			local draftChanged = requestedName ~= name.Text or requestedSource ~= luaSource.Text
			stage = draftChanged and "import" or "added"
			reviewed = nil
			local shapeName = result.name or requestedName
			addedTitle.Text = shapeName .. " is added"
			addedHelp.Text = result.switched == false and "Select your new shape from the modes list to use it."
				or "Your shape is active. Close this window to adjust its controls or choose it again from the modes list."
			local message = result.message or (result.persisted and "Saved for next launch." or "Available for this session only.")
			if draftChanged then message = message .. " Your newer draft is still here." end
			setStatus(message, "success")
		elseif requestedName ~= name.Text or requestedSource ~= luaSource.Text then
			stage, reviewed = "import", nil
			setStatus("Your draft changed while checking. Review the current version again.")
		else
			stage, reviewed = "review", { name = requestedName, source = requestedSource }
			reviewTitle.Text = result.name
			local controls = result.module and result.module.Controls or {}
			reviewDetails.Text = "Lua module checked  /  " .. bytes(#result.source) .. "\n" .. tostring(#controls) .. " custom control" .. (#controls == 1 and "" or "s")
			local names = {}
			for index = 1, math.min(8, #controls) do names[#names + 1] = controls[index].Name end
			reviewControls.Text = #names > 0 and ("Controls: " .. table.concat(names, ", ") .. (#controls > 8 and ", ..." or "")) or "This module has no custom controls."
			reviewStorage.Text = type(writefile) == "function"
				and "Gravity will try to save this shape for future launches. The result will show whether it was saved."
				or "This executor has no file saving. The shape will be available for this session."
			setStatus("Looks good. Ready to add.", "success")
		end
		refresh(); layout()
	end
	connect(check.Activated, function() run(false) end)
	connect(add.Activated, function() run(true) end)
	connect(back.Activated, function()
		if busy or stage ~= "review" then return end
		stage = "import"; setStatus(nil); body.CanvasPosition = Vector2.new(0, 0); refresh()
	end)
	connect(another.Activated, function()
		if busy or stage ~= "added" then return end
		changing = true; name.Text, luaSource.Text = "", ""; changing = false
		codeScroll.CanvasPosition = Vector2.new(0, 0)
		body.CanvasPosition = Vector2.new(0, 0)
		edited(); layout()
	end)
	connect(paste.Activated, function()
		if busy or stage ~= "import" then return end
		local reader = clipboardReader()
		if not reader then return end
		local previousName, previousSource = name.Text, luaSource.Text
		local ok, value = pcall(reader)
		if not alive() then return end
		if stage ~= "import" or name.Text ~= previousName or luaSource.Text ~= previousSource then return end
		if not ok or type(value) ~= "string" or value:match("^%s*$") then
			setStatus("Clipboard is empty or unavailable. Copy your Lua export, or press and hold in the script field to paste.", "error"); return
		end
		local pasted = pcall(function() luaSource.Text = value end)
		if not pasted or luaSource.Text ~= value then
			changing = true; luaSource.Text, name.Text = previousSource, previousName; changing = false
			setStatus("The script could not fit in this text field. Save the full export in GravityShapes as a .lua file, then restart Gravity.", "error")
			refresh(); return
		end
		codeScroll.CanvasPosition = Vector2.new(0, 0)
		setStatus("Script pasted. Review it when you are ready.")
	end)
	connect(selectAll.Activated, function()
		if busy or stage ~= "import" then return end
		luaSource:CaptureFocus()
		luaSource.SelectionStart, luaSource.CursorPosition = 1, #luaSource.Text + 1
	end)
	connect(close.Activated, closeEditor)
	connect(done.Activated, closeEditor)
	connect(overlay:GetPropertyChangedSignal("AbsoluteSize"), layout)
	connect(overlay:GetPropertyChangedSignal("AbsolutePosition"), layout)
	if inputService then
		for _, property in ipairs({ "OnScreenKeyboardVisible", "OnScreenKeyboardPosition", "OnScreenKeyboardSize" }) do
			pcall(function()
				connect(inputService:GetPropertyChangedSignal(property), function()
					layout()
					if luaSource:IsFocused() then showField(luaSource) elseif name:IsFocused() then showField(name) end
				end)
			end)
		end
		connect(inputService.InputBegan, function(input, processed)
			if not processed and overlay.Visible and input.KeyCode == Enum.KeyCode.Escape then closeEditor() end
		end)
	end
	connect(overlay.Destroying, function()
		closed = true
		for _, connection in ipairs(connections) do connection:Disconnect() end
		table.clear(connections)
	end)
	refresh(); layout()
	return {
		root = overlay,
		open = function() if alive() then overlay.Visible = true; refresh(); layout() end end,
		close = closeEditor,
	}
end
