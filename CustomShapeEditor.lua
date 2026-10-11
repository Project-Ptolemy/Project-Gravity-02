-- One editor for desktop and touch. Its instances belong to the session ScreenGui;
-- hiding the overlay preserves a draft, destroying the ScreenGui releases it.
return function(context, parent)
	local x6 = context.x6
	local colors = {
		panel = Color3.fromRGB(15, 15, 18), field = Color3.fromRGB(25, 25, 31),
		text = Color3.fromRGB(245, 245, 250), muted = Color3.fromRGB(166, 166, 180),
		accent = Color3.fromRGB(80, 83, 220), error = Color3.fromRGB(255, 151, 151),
		success = Color3.fromRGB(133, 221, 172),
	}
	local function create(class, name, owner, props)
		local item = Instance.new(class)
		item.Name = name
		for key, value in pairs(props or {}) do item[key] = value end
		item.Parent = owner
		return item
	end
	local function round(item, radius)
		create("UICorner", "Corner", item, { CornerRadius = UDim.new(0, radius or 8) })
	end
	local function padding(item, amount)
		create("UIPadding", "Padding", item, {
			PaddingLeft = UDim.new(0, amount), PaddingRight = UDim.new(0, amount),
			PaddingTop = UDim.new(0, amount), PaddingBottom = UDim.new(0, amount),
		})
	end
	local function label(name, owner, text, size)
		return create("TextLabel", name, owner, {
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = text,
			TextColor3 = colors.muted, Font = Enum.Font.Gotham, TextSize = size or 13,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 203,
		})
	end
	local function button(name, owner, text)
		local item = create("TextButton", name, owner, {
			BackgroundColor3 = colors.field, BorderSizePixel = 0, Text = text,
			TextColor3 = colors.text, Font = Enum.Font.GothamBold, TextSize = 14,
			AutoButtonColor = true, ZIndex = 204,
		})
		round(item)
		return item
	end
	local function input(name, owner, placeholder, value, multiline)
		local item = create("TextBox", name, owner, {
			BackgroundColor3 = colors.field, BorderSizePixel = 0, Text = value or "",
			PlaceholderText = placeholder, PlaceholderColor3 = colors.muted,
			TextColor3 = colors.text, Font = Enum.Font.Code, TextSize = 14,
			ClearTextOnFocus = false, MultiLine = multiline == true, TextWrapped = multiline == true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
			Size = UDim2.new(1, 0, 0, multiline and 300 or 44), ZIndex = 204,
		})
		round(item)
		padding(item, 10)
		return item
	end
	local overlay = create("TextButton", "CustomShapeEditor", parent, {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.35, BorderSizePixel = 0, Text = "", Visible = false,
		Active = true, Selectable = false, AutoButtonColor = false, Modal = true, ZIndex = 200,
	})
	local dialog = create("Frame", "CustomShapeDialog", overlay, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, -24, 1, -24), BackgroundColor3 = colors.panel,
		BorderSizePixel = 0, Active = true, ZIndex = 201,
	})
	create("UISizeConstraint", "ViewportLimit", dialog, { MaxSize = Vector2.new(620, 700) })
	create("UIStroke", "Outline", dialog, { Color = Color3.fromRGB(57, 57, 69), Thickness = 1 })
	round(dialog, 12)
	local heading = label("EditorTitle", dialog, "Custom shape", 19)
	heading.Font = Enum.Font.GothamBold
	heading.TextColor3 = colors.text
	heading.Position = UDim2.new(0, 18, 0, 18)
	heading.Size = UDim2.new(1, -120, 0, 28)
	heading.AutomaticSize = Enum.AutomaticSize.None
	local close = button("CloseShapeEditor", dialog, "Close")
	close.Position = UDim2.new(1, -86, 0, 10)
	close.Size = UDim2.new(0, 72, 0, 44)

	local body = create("ScrollingFrame", "EditorFields", dialog, {
		Position = UDim2.new(0, 18, 0, 62), Size = UDim2.new(1, -36, 1, -196),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageColor3 = colors.muted, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0), ScrollingDirection = Enum.ScrollingDirection.Y,
		Active = true, ZIndex = 202,
	})
	create("UIPadding", "ScrollPadding", body, { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 12) })
	create("UIListLayout", "FieldLayout", body, {
		Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local nameLabel = label("NameLabel", body, "Shape name")
	nameLabel.LayoutOrder = 1
	local name = input("ShapeName", body, "e.g. Orbit bloom")
	name.Font = Enum.Font.Gotham
	name.LayoutOrder = 2
	local luaHelp = label("LuaHelp", body,
		"Paste the complete .lua export from Shape Maker, or a compatible shape script that returns a table with f2. Check and Add run the module to validate it.")
	luaHelp.LayoutOrder = 3
	local luaSource = input("LuaSource", body, "Paste your complete Lua shape script here...", "", true)
	luaSource.LayoutOrder = 4
	luaSource.AutomaticSize = Enum.AutomaticSize.Y

	-- Long compiler errors remain readable without covering the action buttons.
	local statusArea = create("ScrollingFrame", "ShapeStatusArea", dialog, {
		Position = UDim2.new(0, 18, 1, -122), Size = UDim2.new(1, -36, 0, 58),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 202,
	})
	local status = label("ShapeStatus", statusArea, "Name your shape, paste its script, then add it to your modes.", 12)
	status.Size = UDim2.new(1, -8, 0, 0)
	local check = button("CheckShape", dialog, "Check")
	check.Position = UDim2.new(0, 18, 1, -58)
	check.Size = UDim2.new(0.38, -22, 0, 44)
	local add = button("AddShape", dialog, "Add & use")
	add.Position = UDim2.new(0.38, 4, 1, -58)
	add.Size = UDim2.new(0.62, -22, 0, 44)
	add.BackgroundColor3 = colors.accent

	local busy, saved = false, false
	local function alive()
		return not x6.torn_down and overlay.Parent ~= nil
	end
	local function setStatus(message, kind)
		status.Text = tostring(message)
		status.TextColor3 = colors[kind] or colors.muted
		statusArea.CanvasPosition = Vector2.new(0, 0)
	end
	local function buttons()
		add.Active, check.Active = not busy and not saved, not busy and not saved
		add.AutoButtonColor, check.AutoButtonColor = not busy and not saved, not busy and not saved
		add.Text = busy and "Working..." or (saved and "Added" or "Add & use")
		add.BackgroundColor3 = saved and Color3.fromRGB(43, 106, 75) or colors.accent
		check.TextColor3 = (busy or saved) and colors.muted or colors.text
	end
	local function edited()
		if busy then return end
		saved = false
		buttons()
		setStatus("Check the script, or add and use the shape.")
	end
	for _, field in ipairs({ name, luaSource }) do
		field:GetPropertyChangedSignal("Text"):Connect(edited)
	end
	local function run(adding)
		if busy or saved or not alive() then return end
		local requestedName, requestedSource = name.Text, luaSource.Text
		busy = true
		buttons()
		setStatus(adding and "Adding shape..." or "Checking shape...")
		local ok, success, result = pcall(function()
			local manager = context.custom_shapes
			if not manager then
				local module = context.load_module("CustomShapes.lua")
				if not module then return false, "Could not load custom shapes. Try again." end
				if not alive() then return false, "Session has ended." end
				manager = module.create(context)
				context.custom_shapes = manager
			end
			if not alive() then return false, "Session has ended." end
			if adding then return manager.add(requestedName, requestedSource) end
			return manager.validate(requestedName, requestedSource)
		end)
		busy = false
		if not alive() then return end
		if not ok then
			setStatus(success, "error")
		elseif not success then
			setStatus(result, "error")
		elseif adding then
			saved = name.Text == requestedName and luaSource.Text == requestedSource
			local shapeName = result.name or requestedName
			local message = result.message
			if not message or message == "" then
				message = 'Added "' .. shapeName .. '". '
					.. (result.persisted and "Saved for next launch." or "Available for this session only.")
			end
			if result.switched == false then
				message = message .. " Select it from the modes list to use it."
			end
			setStatus(message, "success")
		elseif name.Text ~= requestedName or luaSource.Text ~= requestedSource then
			setStatus("Previous draft checked. Your current changes still need checking.")
		else
			setStatus("Looks good. Add & use will select this shape.", "success")
		end
		buttons()
	end
	check.Activated:Connect(function() run(false) end)
	add.Activated:Connect(function() run(true) end)
	local function closeEditor()
		if not alive() then return end
		for _, field in ipairs({ name, luaSource }) do
			if field:IsFocused() then field:ReleaseFocus() end
		end
		overlay.Visible = false
	end
	close.Activated:Connect(closeEditor)
	return {
		root = overlay,
		open = function() if alive() then overlay.Visible = true end end,
		close = closeEditor,
	}
end
