-- Retained draft -> review -> add. Screen pixels keep touch targets independent
-- of the main panel's UI scale; keyboard overlap only reduces the scroll area.
return function(context, parent)
	local x6, inputService = context.x6, context.v1
	-- The same charcoal surfaces, indigo selection and mint field focus as UI.lua
	-- and UI_elements.lua. This window lives directly under the ScreenGui so the
	-- main panel's scale cannot inflate it beyond a phone's available viewport.
	local colors = {
		panel = Color3.fromRGB(15, 15, 18), field = Color3.fromRGB(20, 20, 25),
		raised = Color3.fromRGB(25, 25, 30), button = Color3.fromRGB(30, 30, 35),
		text = Color3.fromRGB(255, 255, 255), muted = Color3.fromRGB(150, 150, 160),
		accent = Color3.fromRGB(40, 40, 180), line = Color3.fromRGB(40, 40, 45),
		focus = Color3.fromRGB(0, 255, 200), error = Color3.fromRGB(255, 120, 120),
		success = Color3.fromRGB(80, 255, 150),
	}
	local touch = context.is_mobile or (inputService and inputService.TouchEnabled) or false
	local sourceMode = "paste"
	local connections, closed = {}, false
	local function connect(signal, callback)
		local connection = signal:Connect(callback)
		connections[#connections + 1] = connection
	end
	local hoverMotion = context.ANIM and context.ANIM.HOVER
		or TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function tint(item, props)
		if context.v6 then context.v6:Create(item, hoverMotion, props):Play()
		else for key, value in pairs(props) do item[key] = value end end
	end
	local function create(class, name, owner, props)
		local item = Instance.new(class)
		item.Name = name
		for key, value in pairs(props or {}) do item[key] = value end
		item.Parent = owner
		return item
	end
	local function round(item, radius)
		create("UICorner", "Corner", item, { CornerRadius = UDim.new(0, radius or 6) })
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
			TextColor3 = colors.muted, Font = Enum.Font.Gotham, TextSize = size or 12,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order or 0, ZIndex = 203,
		})
	end
	local function button(name, owner, text, primary)
		local base = primary and colors.accent or colors.button
		local item = create("TextButton", name, owner, {
			BackgroundColor3 = base, BorderSizePixel = 0, Text = text,
			TextColor3 = colors.text, Font = Enum.Font.GothamMedium, TextSize = 13,
			TextWrapped = true, AutoButtonColor = false, ZIndex = 204,
		})
		round(item)
		local outline = create("UIStroke", "ButtonOutline", item, {
			Color = primary and Color3.fromRGB(70, 70, 200) or Color3.fromRGB(50, 50, 55),
			Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
		local function restore()
			tint(item, { BackgroundColor3 = base })
			tint(outline, { Transparency = 0 })
		end
		connect(item.MouseEnter, function()
			if item.Active then tint(item, { BackgroundColor3 = primary and Color3.fromRGB(55, 55, 200) or Color3.fromRGB(40, 40, 45) }) end
		end)
		connect(item.MouseLeave, restore)
		connect(item.MouseButton1Down, function() if item.Active then tint(outline, { Transparency = 0.65 }) end end)
		connect(item.MouseButton1Up, restore)
		return item
	end
	local function field(name, owner, placeholder, multiline)
		return create("TextBox", name, owner, {
			BackgroundColor3 = colors.field, BorderSizePixel = 0, Text = "",
			PlaceholderText = placeholder, PlaceholderColor3 = colors.muted,
			TextColor3 = colors.text, Font = multiline and Enum.Font.Code or Enum.Font.Gotham,
			TextSize = multiline and 12 or 14, ClearTextOnFocus = false,
			MultiLine = multiline == true, TextWrapped = true, TextEditable = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
			Size = UDim2.new(1, 0, 0, multiline and 100 or (touch and 44 or 36)), ZIndex = 204,
		})
	end
	local overlay = create("TextButton", "CustomShapeEditor", parent, {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.35, BorderSizePixel = 0, Text = "", Visible = false,
		Active = true, Selectable = false, AutoButtonColor = false, Modal = true, ZIndex = 200,
	})
	local dialog = create("Frame", "CustomShapeDialog", overlay, {
		BackgroundColor3 = colors.panel, BorderSizePixel = 0, Active = true, ZIndex = 201, ClipsDescendants = true,
	})
	create("UIStroke", "Outline", dialog, { Color = colors.line, Thickness = 1 })
	round(dialog, 10)
	local brand = label("EditorBrand", dialog, "PROJECT GRAVITY", 10)
	brand.Font = Enum.Font.GothamBold
	brand.Position, brand.Size = UDim2.new(0, 16, 0, 12), UDim2.new(1, -76, 0, 12)
	brand.AutomaticSize = Enum.AutomaticSize.None
	local heading = label("EditorTitle", dialog, "Custom shape", 19)
	heading.Font, heading.TextColor3 = Enum.Font.GothamBold, colors.text
	heading.Position, heading.Size = UDim2.new(0, 16, 0, 28), UDim2.new(1, -76, 0, 24)
	heading.AutomaticSize = Enum.AutomaticSize.None
	local close = create("TextButton", "CloseShapeEditor", dialog, {
		BackgroundTransparency = 1, Text = "", BorderSizePixel = 0, Active = true,
		Position = UDim2.new(1, -52, 0, 8), Size = UDim2.new(0, 44, 0, 44), ZIndex = 204,
	})
	local closeGlyph = create("TextLabel", "CloseGlyph", close, {
		BackgroundColor3 = Color3.fromRGB(200, 60, 60), BorderSizePixel = 0,
		Position = UDim2.new(0.5, -11, 0.5, -11), Size = UDim2.new(0, 22, 0, 22),
		Text = "\195\151", TextColor3 = colors.text, Font = Enum.Font.GothamBold, TextSize = 15, ZIndex = 205,
	})
	round(closeGlyph, 11)
	connect(close.MouseEnter, function() tint(closeGlyph, { BackgroundColor3 = Color3.fromRGB(220, 90, 90) }) end)
	connect(close.MouseLeave, function() tint(closeGlyph, { BackgroundColor3 = Color3.fromRGB(200, 60, 60) }) end)
	local steps = create("Frame", "ImportSteps", dialog, {
		BackgroundTransparency = 1, Position = UDim2.new(0, 16, 0, 64), Size = UDim2.new(1, -32, 0, 30), ZIndex = 202,
	})
	local importStep = label("ImportStep", steps, "1   Import Lua", 12)
	local reviewStep = label("ReviewStep", steps, "2   Review & add", 12)
	for index, item in ipairs({ importStep, reviewStep }) do
		item.Position, item.Size = UDim2.new((index - 1) * 0.5, index == 1 and 0 or 4, 0, 0), UDim2.new(0.5, -4, 1, 0)
		item.AutomaticSize, item.Font = Enum.AutomaticSize.None, Enum.Font.GothamBold
		item.TextYAlignment, item.TextXAlignment = Enum.TextYAlignment.Center, Enum.TextXAlignment.Center
		item.BackgroundTransparency = 0
		round(item)
	end
	local body = create("ScrollingFrame", "EditorFields", dialog, {
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageColor3 = colors.muted, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0), CanvasPosition = Vector2.new(0, 0),
		ScrollingDirection = Enum.ScrollingDirection.Y, Active = true, ZIndex = 202,
	})
	create("UIPadding", "ScrollPadding", body, { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 10) })
	create("UIListLayout", "FieldLayout", body, { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder })
	local status = label("ShapeStatus", body, "", 12, 0)
	status.Visible = false
	status.BackgroundTransparency, status.BackgroundColor3 = 0, colors.raised
	round(status); padding(status, 10)
	local form = stack("ImportForm", body, 1, 12)
	local details = stack("ImportDetails", form, 1, 10)
	local nameGroup = stack("NameGroup", details, 1, 6)
	local nameLabel = label("NameLabel", nameGroup, "SHAPE NAME", 10, 1)
	nameLabel.TextColor3, nameLabel.Font = colors.text, Enum.Font.GothamBold
	local name = field("ShapeName", nameGroup, "e.g. Orbit bloom", false)
	name.LayoutOrder = 2
	round(name); padding(name, 10)
	local nameOutline = create("UIStroke", "FieldOutline", name, { Color = colors.line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local help = label("LuaHelp", details, "Export Lua from Shape Studio, then paste your script here.", 12, 2)
	local draftHint = label("DraftHelp", details, "Your draft is kept when you close this window.", 11, 3)
	local sourceGroup = stack("SourceGroup", form, 2, 8)
	local sourceLabel = label("SourceLabel", sourceGroup, "LUA SCRIPT", 10, 1)
	sourceLabel.TextColor3, sourceLabel.Font = colors.text, Enum.Font.GothamBold
	local sourceModes = create("Frame", "ImportSourceMode", sourceGroup, {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, touch and 44 or 36), LayoutOrder = 2, ZIndex = 203,
	})
	local pasteMode = button("PasteSourceMode", sourceModes, "Paste Lua")
	pasteMode.Size = UDim2.new(0.5, -4, 1, 0)
	local fileMode = button("FileSourceMode", sourceModes, "Local file")
	fileMode.Position, fileMode.Size = UDim2.new(0.5, 4, 0, 0), UDim2.new(0.5, -4, 1, 0)
	local pasteActions = create("Frame", "PasteActions", sourceGroup, {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, touch and 44 or 32), LayoutOrder = 3, ZIndex = 203,
	})
	local paste = button("PasteShape", pasteActions, "Paste clipboard")
	paste.Size = UDim2.new(0.62, -4, 1, 0)
	local nativePaste = label("NativePasteHint", pasteActions, touch and "Press & hold to paste" or "Paste into the field below", 11)
	nativePaste.Size, nativePaste.AutomaticSize = UDim2.new(1, -112, 1, 0), Enum.AutomaticSize.None
	nativePaste.TextYAlignment = Enum.TextYAlignment.Center
	local selectAll = button("SelectShapeSource", pasteActions, "Select all")
	selectAll.Position, selectAll.Size = UDim2.new(0.62, 4, 0, 0), UDim2.new(0.38, -4, 1, 0)
	local codeScroll = create("ScrollingFrame", "ShapeCodeScroll", sourceGroup, {
		BackgroundColor3 = colors.field, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 200),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0),
		CanvasPosition = Vector2.new(0, 0), ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 5, ScrollBarImageColor3 = colors.muted, Active = true, LayoutOrder = 4, ZIndex = 203,
	})
	round(codeScroll); padding(codeScroll, 10)
	local sourceOutline = create("UIStroke", "FieldOutline", codeScroll, { Color = colors.line, Thickness = 1 })
	local luaSource = field("LuaSource", codeScroll, touch and "Press and hold to paste your Lua export." or "Paste your complete Lua export here.", true)
	luaSource.AutomaticSize, luaSource.BackgroundTransparency = Enum.AutomaticSize.Y, 1
	local fileGroup = stack("FileSourceGroup", sourceGroup, 4, 8)
	fileGroup.Visible = false
	local filePath = field("ShapeFilePath", fileGroup, "e.g. GravityShapes/My formation.lua", false)
	filePath.LayoutOrder = 1
	round(filePath); padding(filePath, 10)
	local fileOutline = create("UIStroke", "FileOutline", filePath, { Color = colors.line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local fileHelp = label("FileSourceHelp", fileGroup,
		"Enter a Lua file path in your executor's workspace. Large exports load directly without pasting or restarting.", 12, 2)
	local sourceInfo = label("ShapeSourceInfo", sourceGroup, "No script pasted yet", 11, 5)
	local review = stack("ShapeReview", body, 2, 12)
	review.Visible = false
	local function card(name, owner, order)
		local item = stack(name, owner, order, 8)
		item.BackgroundColor3, item.BackgroundTransparency = colors.raised, 0
		round(item); padding(item, 12)
		create("UIStroke", "Outline", item, { Color = colors.line, Thickness = 1 })
		return item
	end
	local summary = card("ReviewSummary", review, 1)
	local reviewTitle = label("ReviewShapeName", summary, "", 20, 1)
	reviewTitle.Font, reviewTitle.TextColor3 = Enum.Font.GothamBold, colors.text
	local reviewDetails = label("ReviewDetails", summary, "", 12, 2)
	local controlCard = card("ReviewControlCard", review, 2)
	local controlTitle = label("ReviewControlTitle", controlCard, "INCLUDED CONTROLS", 10, 1)
	controlTitle.Font = Enum.Font.GothamBold
	local reviewControls = label("ReviewControls", controlCard, "", 13, 2)
	reviewControls.TextColor3 = colors.text
	local reviewStorage = label("ReviewStorage", review, "", 12, 3)
	label("ReviewHelp", review, "Add & use selects this shape. Its controls will appear in the main panel.", 12, 4)
	local complete = card("ShapeAdded", body, 3)
	complete.Visible = false
	local addedTitle = label("AddedShapeName", complete, "", 20, 1)
	addedTitle.Font, addedTitle.TextColor3 = Enum.Font.GothamBold, colors.success
	local addedHelp = label("AddedShapeHelp", complete, "", 13, 2)
	local footer = create("Frame", "EditorActions", dialog, {
		BackgroundColor3 = colors.panel, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 76),
		Position = UDim2.new(0, 0, 1, -76), ZIndex = 203,
	})
	create("Frame", "ActionDivider", footer, { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = colors.line, BorderSizePixel = 0, ZIndex = 203 })
	local back = button("BackShapeEditor", footer, "Back")
	local check = button("CheckShape", footer, "Review shape", true)
	local add = button("AddShape", footer, "Add & use", true)
	local another = button("AnotherShape", footer, "Add another")
	local done = button("DoneShapeEditor", footer, "Done", true)

	local stage, busy, changing, reviewed = "import", false, false, nil
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
	local function fileReader()
		if type(readfile) == "function" then return readfile end
		if type(getgenv) == "function" then
			local ok, globals = pcall(getgenv)
			if ok and globals and type(globals.readfile) == "function" then return globals.readfile end
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
		for _, item in ipairs({ check, add, back, paste, selectAll, another, pasteMode, fileMode }) do
			item.Active, item.AutoButtonColor = not busy, false
			item.TextTransparency = busy and 0.4 or 0
		end
		add.Active = not busy and stage == "review"
		check.Text, add.Text = busy and "Checking..." or "Review shape", busy and "Adding..." or "Add & use"
		name.TextEditable, luaSource.TextEditable, filePath.TextEditable = not busy, not busy, not busy
		importStep.TextColor3 = stage == "import" and colors.text or colors.muted
		reviewStep.TextColor3 = stage ~= "import" and colors.success or colors.muted
		importStep.BackgroundColor3 = stage == "import" and colors.accent or colors.raised
		reviewStep.BackgroundColor3 = stage ~= "import" and colors.raised or colors.field
		local canPaste = clipboardReader() ~= nil
		paste.Visible, nativePaste.Visible = canPaste, not canPaste
		selectAll.Position = canPaste and UDim2.new(0.62, 4, 0, 0) or UDim2.new(1, -100, 0, 0)
		selectAll.Size = canPaste and UDim2.new(0.38, -4, 1, 0) or UDim2.new(0, 100, 1, 0)
		local file = sourceMode == "file"
		pasteActions.Visible, codeScroll.Visible, fileGroup.Visible = not file, not file, file
		pasteMode.TextColor3, fileMode.TextColor3 = file and colors.muted or colors.focus, file and colors.focus or colors.muted
		sourceLabel.Text = file and "SOURCE FILE" or "LUA SCRIPT"
		help.Text = file and "Export Lua from Shape Studio, then enter its saved file path."
			or "Export Lua from Shape Studio, then paste your script here."
		fileHelp.Text = fileReader() and "Enter a Lua file path in your executor's workspace. Large exports load directly without pasting or restarting."
			or "This executor cannot read local files. Choose Paste Lua to import your script."
		local length = #luaSource.Text
		sourceInfo.Text = file and "The complete file is read when you choose Review shape."
			or (length == 0 and "No script pasted yet" or (bytes(length) .. " pasted  /  Lua module"))
	end
	local function releaseFocus()
		for _, item in ipairs({ name, luaSource, filePath }) do if item:IsFocused() then item:ReleaseFocus() end end
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
		local margin = keyboardTop and 4 or (width < 480 and 8 or 16)
		local landscape = width >= 560 and height < 480
		local w = math.max(0, math.min(landscape and 740 or 600, width - margin * 2))
		local h = math.max(0, math.min(620, height - margin * 2))
		dialog.Size, dialog.Position = UDim2.new(0, w, 0, h), UDim2.new(0, (width - w) * 0.5, 0, (height - h) * 0.5)
		local compact = h < 440
		steps.Visible = not compact
		brand.Visible = not compact
		heading.Position = UDim2.new(0, 16, 0, compact and 16 or 28)
		close.Position = UDim2.new(1, -52, 0, compact and 4 or 8)
		local actionHeight = touch and 44 or 36
		local top, bottom = compact and 56 or 106, actionHeight + 20
		-- In the smallest landscape keyboard area, keep the focused field and
		-- Close reachable. The action row returns when the keyboard is dismissed.
		footer.Visible = h >= 150
		if not footer.Visible then bottom = 0 end
		footer.Size, footer.Position = UDim2.new(1, 0, 0, bottom), UDim2.new(0, 0, 1, -bottom)
		body.Position, body.Size = UDim2.new(0, 16, 0, top), UDim2.new(1, -32, 0, math.max(0, h - top - bottom))
		-- Put the name and guidance beside the script in landscape. All fields stay
		-- in the same scrolling body, preserving drafts and keyboard focus on rotate.
		local columns = compact and w >= 500
		form.Layout.FillDirection = columns and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
		details.Size = columns and UDim2.new(0.34, -8, 0, 0) or UDim2.new(1, 0, 0, 0)
		sourceGroup.Size = columns and UDim2.new(0.66, -4, 0, 0) or UDim2.new(1, 0, 0, 0)
		help.Visible, draftHint.Visible = true, not compact
		codeScroll.Size = UDim2.new(1, 0, 0, columns and math.max(110, h - top - bottom - 100)
			or math.max(128, math.min(210, h - 386)))
		heading.TextSize = w < 360 and 17 or 19
		back.Position, back.Size = UDim2.new(0, 16, 0, 10), UDim2.new(0.34, -20, 0, actionHeight)
		check.Position, check.Size = UDim2.new(0, 16, 0, 10), UDim2.new(1, -32, 0, actionHeight)
		add.Position, add.Size = UDim2.new(0.34, 4, 0, 10), UDim2.new(0.66, -20, 0, actionHeight)
		another.Position, another.Size = UDim2.new(0, 16, 0, 10), UDim2.new(0.5, -20, 0, actionHeight)
		done.Position, done.Size = UDim2.new(0.5, 4, 0, 10), UDim2.new(0.5, -20, 0, actionHeight)
	end
	local function showField(item)
		if not overlay.Visible or stage ~= "import" then return end
		-- Scroll only when a field is clipped. Looking at the source viewport
		-- rather than the growing TextBox avoids jumping to the end of a long file.
		local target = item == luaSource and codeScroll or item
		local top = target.AbsolutePosition.Y - body.AbsolutePosition.Y
		local available = body.AbsoluteSize.Y
		if available <= 0 then return end
		local bottom = top + math.min(target.AbsoluteSize.Y, available)
		local offset = top < 0 and top or (bottom > available and bottom - available or 0)
		if offset ~= 0 then body.CanvasPosition = Vector2.new(0, math.max(0, body.CanvasPosition.Y + offset)) end
	end
	connect(body:GetPropertyChangedSignal("AbsoluteSize"), function()
		if luaSource:IsFocused() then showField(luaSource) elseif filePath:IsFocused() then showField(filePath)
		elseif name:IsFocused() then showField(name) end
	end)
	local function edited()
		if changing then return end
		stage, reviewed = "import", nil
		nameOutline.Color = name:IsFocused() and colors.focus or colors.line
		sourceOutline.Color = luaSource:IsFocused() and colors.focus or colors.line
		fileOutline.Color = filePath:IsFocused() and colors.focus or colors.line
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
	connect(filePath:GetPropertyChangedSignal("Text"), function()
		if changing then return end
		if name.Text:match("^%s*$") then
			local suggested = filePath.Text:match("([^/\\]+)%.[Ll][Uu][Aa]%s*$")
				or filePath.Text:match("([^/\\]+)%.[Tt][Xx][Tt]%s*$")
			if suggested and #suggested <= 80 then changing = true; name.Text = suggested; changing = false end
		end
		edited()
	end)
	for _, item in ipairs({ name, luaSource, filePath }) do
		local outline = item == name and nameOutline or (item == filePath and fileOutline or sourceOutline)
		connect(item.Focused, function() tint(outline, { Color = colors.focus }); layout(); showField(item) end)
		connect(item.FocusLost, function() tint(outline, { Color = colors.line }) end)
	end
	connect(name.FocusLost, function(enterPressed)
		if enterPressed and overlay.Visible and stage == "import" and not busy then
			(sourceMode == "file" and filePath or luaSource):CaptureFocus()
		end
	end)
	local function closeEditor()
		if not alive() then return end
		releaseFocus(); overlay.Visible = false
	end
	local function run(adding)
		if busy or not alive() or (adding and stage ~= "review") or (not adding and stage ~= "import") then return end
		local requestedName, requestedMode = name.Text, sourceMode
		local requestedSource = requestedMode == "file" and filePath.Text or luaSource.Text
		local function sameDraft()
			return requestedName == name.Text and requestedMode == sourceMode
				and requestedSource == (sourceMode == "file" and filePath.Text or luaSource.Text)
		end
		if adding and (not reviewed or reviewed.name ~= requestedName or reviewed.source ~= requestedSource or reviewed.mode ~= requestedMode) then
			stage, reviewed = "import", nil
			setStatus("Your draft changed. Review it again before adding."); refresh(); return
		end
		releaseFocus(); busy = true; refresh()
		setStatus(adding and "Adding your shape..." or "Checking the module and its controls...")
		local moduleSource = requestedSource
		local ok, success, result = pcall(function()
			local manager = context.custom_shapes
			if not manager then
				local module = context.load_module("CustomShapes.lua")
				if not module then return false, "Could not load custom shapes. Try again." end
				if not alive() then return false, "Session has ended." end
				manager = module.create(context); context.custom_shapes = manager
			end
			if not alive() then return false, "Session has ended." end
			if adding then return manager.add(requestedName, reviewed.moduleSource, reviewed.entry) end
			local sourcePath
			if requestedMode == "file" then
				sourcePath = requestedSource:match("^%s*(.-)%s*$")
				if sourcePath == "" then return false, "Enter the path to your Lua shape file." end
				local reader = fileReader()
				if not reader then return false, "This executor cannot read local files. Choose Paste Lua instead." end
				local read, content = pcall(reader, sourcePath)
				if not alive() then return false, "Session has ended." end
				if not sameDraft() then return false, "Your draft changed while reading. Review the current version again." end
				if not read or type(content) ~= "string" then
					return false, "Could not read that file. Check the path in your executor's workspace. " .. tostring(content)
				end
				moduleSource = content
			end
			return manager.validate(requestedName, moduleSource, sourcePath)
		end)
		busy = false
		if not alive() then return end
		if not ok or not success then
			stage, reviewed = "import", nil
			local message = tostring(ok and result or success)
			setStatus(message, "error")
			if message:lower():find("name", 1, true) then nameOutline.Color = colors.error
			elseif sourceMode == "file" then fileOutline.Color = colors.error else sourceOutline.Color = colors.error end
		elseif adding then
			local draftChanged = not sameDraft()
			stage = draftChanged and "import" or "added"
			reviewed = nil
			local shapeName = result.name or requestedName
			addedTitle.Text = shapeName .. " is added"
			addedHelp.Text = result.switched == false and "Select your new shape from the modes list to use it."
				or "Your shape is active. Close this window to adjust its controls or choose it again from the modes list."
			local message = result.message or (result.persisted and "Saved for next launch." or "Available for this session only.")
			if draftChanged then message = message .. " Your newer draft is still here." end
			setStatus(message, "success")
		elseif not sameDraft() then
			stage, reviewed = "import", nil
			setStatus("Your draft changed while checking. Review the current version again.")
		else
			stage, reviewed = "review", { name = requestedName, source = requestedSource, mode = requestedMode,
				moduleSource = moduleSource, entry = result }
			reviewTitle.Text = result.name
			local controls = result.module and result.module.Controls or {}
			reviewDetails.Text = bytes(#result.source) .. " Lua module  /  " .. tostring(#controls) .. " custom control" .. (#controls == 1 and "" or "s")
			local names = {}
			for index = 1, math.min(8, #controls) do
				local control = controls[index]
				names[#names + 1] = control.Name .. "  /  " .. tostring(control.Type)
			end
			reviewControls.Text = #names > 0 and (table.concat(names, "\n") .. (#controls > 8 and ("\n+ " .. (#controls - 8) .. " more") or "")) or "Uses Gravity's standard shape settings."
			reviewStorage.Text = result.existing_path and ("Uses the existing file at " .. result.existing_path .. ". The file will not be rewritten.")
				or (type(writefile) == "function" and "Gravity will save this shape for your next launch if file access is available."
				or "Available for this session. Your executor does not support saving files.")
			setStatus("Looks good. Ready to add.", "success")
		end
		refresh(); layout()
	end
	connect(check.Activated, function() run(false) end)
	connect(add.Activated, function() run(true) end)
	local function setSourceMode(mode)
		if busy or stage ~= "import" or sourceMode == mode then return end
		releaseFocus(); sourceMode = mode; edited(); layout()
	end
	connect(pasteMode.Activated, function() setSourceMode("paste") end)
	connect(fileMode.Activated, function() setSourceMode("file") end)
	connect(back.Activated, function()
		if busy or stage ~= "review" then return end
		stage = "import"; setStatus(nil); body.CanvasPosition = Vector2.new(0, 0); refresh()
	end)
	connect(another.Activated, function()
		if busy or stage ~= "added" then return end
		changing = true; name.Text, luaSource.Text, filePath.Text = "", "", ""; changing = false
		codeScroll.CanvasPosition = Vector2.new(0, 0)
		body.CanvasPosition = Vector2.new(0, 0)
		edited(); layout()
	end)
	connect(paste.Activated, function()
		if busy or stage ~= "import" or sourceMode ~= "paste" then return end
		local reader = clipboardReader()
		if not reader then return end
		local previousName, previousSource = name.Text, luaSource.Text
		local ok, value = pcall(reader)
		if not alive() then return end
		if stage ~= "import" or sourceMode ~= "paste" or name.Text ~= previousName or luaSource.Text ~= previousSource then return end
		if not ok or type(value) ~= "string" or value:match("^%s*$") then
			setStatus("Clipboard is empty or unavailable. Copy your Lua export, or press and hold in the script field to paste.", "error"); return
		end
		local pasted = pcall(function() luaSource.Text = value end)
		if not pasted or luaSource.Text ~= value then
			changing = true; luaSource.Text, name.Text = previousSource, previousName; changing = false
			setStatus("The script could not fit in this text field. Choose Local file and enter the path to your complete Lua export.", "error")
			refresh(); return
		end
		codeScroll.CanvasPosition = Vector2.new(0, 0)
		setStatus("Script pasted. Review it when you are ready.")
	end)
	connect(selectAll.Activated, function()
		if busy or stage ~= "import" or sourceMode ~= "paste" then return end
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
					if luaSource:IsFocused() then showField(luaSource) elseif filePath:IsFocused() then showField(filePath)
					elseif name:IsFocused() then showField(name) end
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
