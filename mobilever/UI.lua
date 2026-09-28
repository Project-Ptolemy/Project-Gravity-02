return function(context)
	local v1, v2, v3, v4, v5, v6, v7, v8, v9 = context.v1, context.v2, context.v3, context.v4, context.v5, context.v6, context.v7, context.v8, context.v9
	local x1, x2, x6, x9 = context.x1, context.x2, context.x6, context.x9
	local favorites, save_favs, save_settings = context.favorites, context.save_favs, context.save_settings
	local get_shape = context.get_shape
	local load_module = context.load_module
	local PluginControls = context.plugin_controls or load_module("PluginControls.lua")
	local MobileControls
	if context.is_mobile or v1.TouchEnabled then MobileControls = load_module("MobileControls.lua") end
	local SUB_DIR = context.SUB_DIR or "mobilever/"
	-- Shared motion vocabulary from main.lua; see the ANIM table there for why
	-- each curve is what it is. Fallback keeps this module loadable standalone.
	-- Touch has no hover state, so HOVER here only ever drives the pressed tint.
	local A = context.ANIM or {
		HOVER = TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		TINT = TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		OPEN = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		OPEN_POP = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		CLOSE = TweenInfo.new(0.19, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		CLOSE_POP = TweenInfo.new(0.19, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		ROLL = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		FOLD = TweenInfo.new(0.36, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		UNFOLD = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		RESCALE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	}

	local Lighting = game:GetService("Lighting")
	
	-- Weak keys, the same reason scaled_windows below uses them. These tables are
	-- keyed by every BasePart, PostEffect and emitter in the map, so with strong keys
	-- every one destroyed after the snapshot was pinned until the toggle went off --
	-- in a map with any part churn that is an unbounded leak. The restore functions
	-- already expect entries to go dead (they test part.Parent), so dropping them
	-- early changes nothing they do.
	local PerfOriginals = {
		Shadows = nil,
		FX = setmetatable({}, { __mode = "k" }),
		Materials = setmetatable({}, { __mode = "k" }),
		Particles = setmetatable({}, { __mode = "k" })
	}
	
	local function RestorePerfShadows()
		if PerfOriginals.Shadows ~= nil then
			Lighting.GlobalShadows = PerfOriginals.Shadows
			PerfOriginals.Shadows = nil
		end
	end
	
	local function ApplyPerfShadows(disable)
		if disable then
			if PerfOriginals.Shadows == nil then
				PerfOriginals.Shadows = Lighting.GlobalShadows
			end
			Lighting.GlobalShadows = false
		else
			RestorePerfShadows()
		end
	end
	
	local function RestorePerfPostFX()
		for fx, was_enabled in pairs(PerfOriginals.FX) do
			if fx.Parent then fx.Enabled = was_enabled end
		end
		table.clear(PerfOriginals.FX)
	end
	
	local function ApplyPerfPostFX(disable)
		if disable then
			for _, effect in pairs(Lighting:GetDescendants()) do
				if effect:IsA("PostEffect") then
					if PerfOriginals.FX[effect] == nil then
						PerfOriginals.FX[effect] = effect.Enabled
					end
					effect.Enabled = false
				end
			end
			local camera = workspace.CurrentCamera
			if camera then
				for _, effect in pairs(camera:GetDescendants()) do
					if effect:IsA("PostEffect") then
						if PerfOriginals.FX[effect] == nil then
							PerfOriginals.FX[effect] = effect.Enabled
						end
						effect.Enabled = false
					end
				end
			end
		else
			RestorePerfPostFX()
		end
	end
	
	local function RestorePerfMaterials()
		for part, mat in pairs(PerfOriginals.Materials) do
			if part.Parent then part.Material = mat end
		end
		table.clear(PerfOriginals.Materials)
	end
	
	local function ApplyPerfMaterials(disable)
		if disable then
			for _, part in pairs(workspace:GetDescendants()) do
				if part:IsA("BasePart") then
					if not PerfOriginals.Materials[part] then
						PerfOriginals.Materials[part] = part.Material
					end
					part.Material = Enum.Material.SmoothPlastic
				end
			end
		else
			RestorePerfMaterials()
		end
	end
	
	local function RestorePerfParticles()
		for p, enabled in pairs(PerfOriginals.Particles) do
			if p.Parent then p.Enabled = enabled end
		end
		table.clear(PerfOriginals.Particles)
	end
	
	local function ApplyPerfParticles(disable)
		if disable then
			for _, obj in pairs(workspace:GetDescendants()) do
				if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
					if PerfOriginals.Particles[obj] == nil then
						PerfOriginals.Particles[obj] = obj.Enabled
					end
					obj.Enabled = false
				end
			end
		else
			RestorePerfParticles()
		end
	end

	local function RestoreAllPerf()
		RestorePerfShadows()
		RestorePerfPostFX()
		RestorePerfMaterials()
		RestorePerfParticles()
	end
	-- UI_elements is a hard dependency, so fail with a message that says which
	-- module rather than "attempt to call a nil value" out of load_module's
	-- failure path, the way main.lua:553 does for UI and System.
	local UI_elements_builder = load_module(SUB_DIR .. "UI_elements.lua")
	if not UI_elements_builder then
		error("Failed to load UI_elements", 0)
	end
	local UI_elements = UI_elements_builder(context)
	-- Project UAI is launched on demand; repeated clicks share the in-flight load.
	local ai_loading = false
	local es, et, eb, eh = UI_elements.s, UI_elements.t, UI_elements.b, UI_elements.h
	local etb = UI_elements.tb

	local x5 = {}
	x5.g = nil
	x5.restore_perf = RestoreAllPerf
	x5.performance_effects = {
		Perf_DisableShadows = ApplyPerfShadows, Perf_DisablePostFX = ApplyPerfPostFX,
		Perf_PotatoMaterials = ApplyPerfMaterials, Perf_HideParticles = ApplyPerfParticles,
	}
	x5.s = es
	x5.t = et
	x5.b = eb
	x5.h = eh

	function x5.st()
		if x6.torn_down then return end
		if x5.g and x5.g.Parent and x5.up then
			x5.up()
			return
		end
		if x5.g then
			local old = x5.g
			x5.g, x6.sg = nil, nil
			old:Destroy()
		end
		local sg = Instance.new("ScreenGui")
		sg.Name = "G_" .. math.random(999)
		-- Register ownership before WaitForChild can yield to a replacement session.
		x6.sg, x5.g = sg, sg
		if gethui then
			sg.Parent = gethui()
		elseif syn and syn.protect_gui then
			syn.protect_gui(sg)
			sg.Parent = game:GetService("CoreGui")
		else
			local parent = v8:WaitForChild("PlayerGui")
			if x6.torn_down then sg:Destroy(); return end
			sg.Parent = parent
		end
		x6.sg = sg
		x5.g = sg
		x5.mw(sg)
	end

	function x5.mw(sg)
		if MobileControls then MobileControls(context, sg) end
		-- Panel geometry. The minimize animation tweens between these, so they
		-- cannot stay as literals duplicated between the constructor and the
		-- handler -- that split is what let the two drift apart before.
		-- CONTENT_GAP is the gap under the header: the content frame's old
		-- 40/-50 pair was really HEADER_H + gap, written out by hand.
		-- Smaller than desktop throughout: this panel is 180x250 with a 26px
		-- header and 14px buttons, so the pill is sized to the touch target
		-- rather than to desktop's 44.
		local PANEL_W = 180
		local PANEL_H = 250
		local HEADER_H = 26
		local PILL_SIZE = 34
		local CONTENT_GAP = 14

		-- Roblox honours one UIScale per GuiObject, so the open/close pop and the
		-- user's UI Scale setting have to share it. Every scalable window is
		-- registered here and its scale is always (pop factor * app scale):
		-- toggle_window used to tween the single UIScale straight to 1, which
		-- threw the saved scale away and left the shape selector, target list and
		-- tutorial completely unaffected by the UI Scale slider.
		-- Weak keys, because registration outlives the window. The reset-confirm
		-- dialog is registered on open and Destroy()ed on dismiss -- each one used
		-- to leave a strong reference to a dead Instance behind here. Nothing swept
		-- them: the only prune is the win.Parent check inside apply_ui_scale, which
		-- runs only when the scale setting changes, so the table grew for the whole
		-- session and pinned every corpse it held. A window that is still parented
		-- is kept alive by its parent, so weak keys drop exactly the dead ones.
		local scaled_windows = setmetatable({}, { __mode = "k" })

		local function app_scale()
			local v = tonumber(x1.UIScale) or 1
			if v ~= v or v <= 0 then
				return 1
			end
			return v
		end

		-- pop is where the window sits in its own open/close animation: 1 when
		-- open, 0.8 while hidden. Kept per window so a rescale mid-animation
		-- cannot snap a closed window to full size.
		local function register_window(win, pop)
			local scale = win:FindFirstChild("UIScale")
			if not scale then
				scale = Instance.new("UIScale", win)
			end
			pop = pop or 1
			scale.Scale = pop * app_scale()
			scaled_windows[win] = { scale = scale, pop = pop }
			return scale
		end

		local function set_pop(win, pop, tween_info)
			local entry = scaled_windows[win]
			if not entry then
				register_window(win, pop)
				entry = scaled_windows[win]
			end
			entry.pop = pop
			local target = pop * app_scale()
			if tween_info then
				v6:Create(entry.scale, tween_info, { Scale = target }):Play()
			else
				entry.scale.Scale = target
			end
		end

		-- One place the setting is applied, so a popup can never be left at the
		-- old scale. Tweened rather than snapped, and every window moves together.
		local function apply_ui_scale()
			local s = app_scale()
			for win, entry in pairs(scaled_windows) do
				if win.Parent then
					v6:Create(entry.scale, A.RESCALE, { Scale = entry.pop * s }):Play()
				else
					scaled_windows[win] = nil
				end
			end
		end
		x5.apply_ui_scale = apply_ui_scale

		local function toggle_window(win, state)
			if not scaled_windows[win] then
				register_window(win, win.Visible and 1 or 0.8)
			end
			local prop = win:IsA("CanvasGroup") and "GroupTransparency" or "BackgroundTransparency"
			if state then
				win.Visible = true
				v6:Create(win, A.OPEN, {[prop] = 0}):Play()
				set_pop(win, 1, A.OPEN_POP)
			else
				local tw = v6:Create(win, A.CLOSE, {[prop] = 1})
				set_pop(win, 0.8, A.CLOSE_POP)
				local conn
				conn = tw.Completed:Connect(function() 
					if win.Parent and win[prop] >= 0.99 then win.Visible = false end 
					if conn then conn:Disconnect() end
				end)
				tw:Play()
			end
		end

		-- Both side panels open over the middle of the screen, so opening one has to
		-- close the other: stacked on a phone they cover each other completely, and
		-- the one underneath still takes taps wherever the top one does not reach.
		-- Part Control carries an on_close because closing it also has to disarm the
		-- tap handlers -- otherwise every tap keeps hijacking held parts with the
		-- panel out of sight.
		--
		-- Advanced is a plain Frame and toggles with Visible: toggle_window fades
		-- BackgroundTransparency on a non-CanvasGroup, which fades the panel out from
		-- under its own children. Only the CanvasGroup panels can animate.
		local side_panels = {}
		local function register_side_panel(win, on_close)
			side_panels[win] = on_close or true
		end

		local function set_panel_visible(win, state)
			if win:IsA("CanvasGroup") then
				toggle_window(win, state)
			else
				win.Visible = state and true or false
			end
		end

		local function close_side_panel(win)
			local on_close = side_panels[win]
			set_panel_visible(win, false)
			if type(on_close) == "function" then
				pcall(on_close)
			end
		end

		local function open_side_panel(win, state)
			if state then
				for other in pairs(side_panels) do
					if other ~= win and other.Visible then
						close_side_panel(other)
					end
				end
				set_panel_visible(win, true)
			else
				close_side_panel(win)
			end
		end

		-- Every window in this tree closes with the same 14x14 red circle. Part
		-- Control used to be the one exception: a grey text "x", 30x30, sized for the
		-- desktop tree.
		-- Tinting towards white rather than carrying a second colour literal per button,
		-- so a palette change cannot leave a hover state behind. Written out rather than
		-- using Color3:Lerp because this also has to run under the test harness's
		-- Color3 stub, which has the components but not the methods.
		local function brighten(c, amt)
			return Color3.new(c.R + (1 - c.R) * amt, c.G + (1 - c.G) * amt, c.B + (1 - c.B) * amt)
		end

		-- Every round button in the tree: the two in Main's header, the tutorial close and
		-- the close on each side panel. They were bare coloured circles with no glyph, no
		-- feedback and -- at 14 px on a touch screen -- nothing to tell minimize and close
		-- apart but colour.
		local function circle_btn(parent, base, glyph, text_size, size)
			local b = Instance.new("TextButton", parent)
			b.BackgroundColor3 = base
			size = size or 14
			b.Size = UDim2.new(0, size, 0, size)
			b.AutoButtonColor = false
			b.Text = glyph or ""
			b.TextColor3 = Color3.fromRGB(255, 255, 255)
			b.Font = Enum.Font.GothamBold
			b.TextSize = text_size or 10
			Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
			local hot = brighten(base, 0.28)
			b.MouseEnter:Connect(function()
				v6:Create(b, A.HOVER, { BackgroundColor3 = hot }):Play()
			end)
			b.MouseLeave:Connect(function()
				v6:Create(b, A.HOVER, { BackgroundColor3 = base }):Play()
			end)
			UI_elements.press(b, 0.88)
			return b
		end

		-- One press behaviour for every list row and dropdown. There were three: the mode
		-- selector's rows and Part Control's shape rows had none at all, the target list
		-- set BackgroundColor3 directly instead of tweening it on the shared curve, and
		-- the dropdown buttons had neither. idle is passed in rather than read back off
		-- the object because a selected row carries its own tint and must keep it.
		local function row_hover(obj, idle, hot, stroke, stroke_idle, stroke_hot)
			obj.MouseEnter:Connect(function()
				v6:Create(obj, A.HOVER, { BackgroundColor3 = hot }):Play()
				if stroke and stroke_hot then
					v6:Create(stroke, A.HOVER, { Color = stroke_hot }):Play()
				end
			end)
			obj.MouseLeave:Connect(function()
				v6:Create(obj, A.HOVER, { BackgroundColor3 = idle }):Play()
				if stroke and stroke_idle then
					v6:Create(stroke, A.HOVER, { Color = stroke_idle }):Play()
				end
			end)
		end

		local function side_close(header, cb)
			local b = circle_btn(header, Color3.fromRGB(200, 60, 60), "×", 10)
			b.Position = UDim2.new(1, -22, 0.5, -7)
			b.MouseButton1Click:Connect(cb)
			return b
		end

		-- Replaces the deprecated Frame.Draggable, which was set on the window itself
		-- and so treated the whole surface as a drag handle. On a touch screen that
		-- took the one gesture the body needs: dragging the settings list scrolled
		-- nothing and slid the panel instead. Binding the handle to the title bar
		-- gives the ScrollingFrame its gesture back.
		--
		-- The delta goes onto Position's offset unchanged. A UIScale on the window
		-- scales its size and its descendants, not its Position, which still
		-- resolves against the parent ScreenGui in plain screen pixels -- so the
		-- offset stays 1:1 with the finger at any UI Scale. Position's scale
		-- components are preserved rather than flattened, so a window anchored to
		-- the viewport centre still tracks a rotation or resize.
		local KEEP_ON_SCREEN = 28
		local function make_draggable(win, handle)
			handle = handle or win
			handle.Active = true

			local dragging = false
			local origin, start_pos

			table.insert(x6.c, handle.InputBegan:Connect(function(input)
				local ty = input.UserInputType
				if ty ~= Enum.UserInputType.MouseButton1 and ty ~= Enum.UserInputType.Touch then
					return
				end
				dragging = true
				origin = input.Position
				start_pos = win.Position
				-- Latched off the input itself: a touch that ends outside the handle
				-- still ends this input, and without it the panel would stay stuck to
				-- the next finger that came down.
				local conn
				conn = input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
						if conn then
							conn:Disconnect()
						end
					end
				end)
			end))

			table.insert(x6.c, v1.InputChanged:Connect(function(input)
				if not dragging or not start_pos then
					return
				end
				local ty = input.UserInputType
				if ty ~= Enum.UserInputType.MouseMovement and ty ~= Enum.UserInputType.Touch then
					return
				end
				local parent = win.Parent
				if not parent then
					dragging = false
					return
				end
				local avail = parent.AbsoluteSize
				local size = win.AbsoluteSize
				local delta = input.Position - origin
				local want_x = start_pos.X.Scale * avail.X + start_pos.X.Offset + delta.X
				local want_y = start_pos.Y.Scale * avail.Y + start_pos.Y.Offset + delta.Y
				-- Leave a grabbable strip on screen. The vertical floor is 0: a title
				-- bar dragged above the top edge can never be picked up again.
				local max_x = avail.X - KEEP_ON_SCREEN
				local min_x = math.min(-(size.X - KEEP_ON_SCREEN), max_x)
				win.Position = UDim2.new(
					start_pos.X.Scale,
					math.clamp(want_x, min_x, max_x) - start_pos.X.Scale * avail.X,
					start_pos.Y.Scale,
					math.clamp(want_y, 0, math.max(0, avail.Y - KEEP_ON_SCREEN)) - start_pos.Y.Scale * avail.Y
				)
			end))
		end

		local hud = Instance.new("Frame", sg)
		hud.Name = "StatusHUD"
		hud.BackgroundTransparency = 1
		hud.Position = UDim2.new(0.5, -150, 0, 10)
		hud.Size = UDim2.new(0, 300, 0, 30)

		-- Scaled like every other element; the HUD was the one thing left out.
		register_window(hud, 1)

		local hud_l = Instance.new("TextLabel", hud)
		hud_l.BackgroundTransparency = 1
		hud_l.Size = UDim2.new(1, 0, 1, 0)
		hud_l.Font = Enum.Font.GothamBold
		hud_l.TextSize = 9
		hud_l.TextColor3 = Color3.fromRGB(255, 255, 255)

		local hud_target, hud_state, hud_parts, hud_dev
		local HUD_ACTIVE = Color3.fromRGB(80, 255, 150)
		local HUD_PAUSED = Color3.fromRGB(255, 180, 80)
		local HUD_DISABLED = Color3.fromRGB(255, 80, 80)
		table.insert(
			x6.c,
			v3.RenderStepped:Connect(function()
				if not x5.g then
					return
				end
				-- x1.Targets, not x1.Tgt: multi-targeting replaced the single slot
				-- and nothing has written Tgt since, so this read "NONE" even with
				-- a target locked. main.lua strips Tgt from the save file outright.
				local tgt = "None"
				local sel = x1.Targets
				if x1.PI_All then
					tgt = "Everyone"
				elseif sel and #sel > 0 then
					if #sel == 1 then
						tgt = sel[1].DisplayName or sel[1].Name
					else
						tgt = "Multi (" .. tostring(#sel) .. ")"
					end
				elseif x1.AnchorSelf then
					tgt = "Self"
				end
				local state = x1.Disabled and "DISABLED" or (x1.Paused and "PAUSED" or "ACTIVE")
				-- The claimed-part count, which is the one number that answers "is it
				-- working" and the only one the HUD did not carry. Folded into the same
				-- change detect as the other two, so this is still at most one property
				-- write per change rather than one per frame.
				local parts = x6.n or 0
				-- Deviation, when the readout is on: how far the parts actually are from
				-- the targets their shape gave them, mean then worst. Quantised to a tenth
				-- of a stud and folded into the same change detect as the other three
				-- fields, because the raw number never settles and this label is written at
				-- most once per change rather than once per frame.
				local dev = -1
				if x1.PreviewDeviation and x6.dev_n and x6.dev_n > 0 then
					dev = math.floor((x6.dev_mean or 0) * 10 + 0.5) / 10
				end
				if tgt ~= hud_target or state ~= hud_state or parts ~= hud_parts or dev ~= hud_dev then
					hud_target, hud_state, hud_parts, hud_dev = tgt, state, parts, dev
					local line = string.format("TARGET: %s  |  PARTS: %d  |  STATUS: %s", tgt:upper(), parts, state)
					if dev >= 0 then
						line = line .. string.format("  |  DEV: %.1f / %.1f", dev, x6.dev_max or 0)
					end
					hud_l.Text = line
					hud_l.TextColor3 = x1.Disabled and HUD_DISABLED or (x1.Paused and HUD_PAUSED or HUD_ACTIVE)
				end
			end)
		)

		hud.Visible = x1.ShowHUD ~= false

		-- Advanced and Part Control are the same kind of window and both open over
		-- the middle of the screen, so they share one geometry rather than each
		-- carrying its own literals. Part Control used to be 280x420 with a 40px
		-- header in a tree whose main panel is 180x250 with a 26px one -- half again
		-- as wide as the window it is opened from.
		local SIDE_W = 180
		local SIDE_H = 250
		local SIDE_HEADER_H = 26
		-- Gap under a side panel's header, then the bottom margin: 26/9/10 is what
		-- Advanced already used, written out as 35 and -45.
		local SIDE_CONTENT_GAP = 9
		local SIDE_BOTTOM = 10

		local m = Instance.new("Frame", sg)
		m.Name = "Main"
		m.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
		m.Position = UDim2.new(0.5, -110, 0.5, -160)
		m.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
		m.Active = true
		-- Held onto: the collapse tweens the radius out to a full circle.
		local mcorner = Instance.new("UICorner", m)
		mcorner.CornerRadius = UDim.new(0, 10)
		local ms = Instance.new("UIStroke", m)
		ms.Color = Color3.fromRGB(40, 40, 45)
		ms.Thickness = 1

		-- Main is always open, so it starts at full pop.
		register_window(m, 1)

		local h = Instance.new("Frame", m)
		h.BackgroundTransparency = 1
		h.Size = UDim2.new(1, 0, 0, HEADER_H)
		-- Also the whole surface of the collapsed pill, so the pill stays draggable
		-- without a second code path.
		make_draggable(m, h)

		local t = Instance.new("TextLabel", h)
		t.BackgroundTransparency = 1
		t.Position = UDim2.new(0, 15, 0, 0)
		t.Size = UDim2.new(0.6, 0, 1, 0)
		t.Text = "PROJECT GRAVITY"
		t.TextColor3 = Color3.fromRGB(255, 255, 255)
		t.Font = Enum.Font.GothamBlack
		t.TextSize = 10
		t.TextXAlignment = 0

		local c = Instance.new("ScrollingFrame", m)
		c.BackgroundTransparency = 1
		c.Position = UDim2.new(0, 0, 0, HEADER_H + CONTENT_GAP)
		c.Size = UDim2.new(1, 0, 1, -(HEADER_H + CONTENT_GAP + 10))
		c.ScrollBarThickness = 0
		c.AutomaticCanvasSize = Enum.AutomaticSize.Y
		c.CanvasSize = UDim2.new(0, 0, 0, 0)
		local l = Instance.new("UIListLayout", c)
		l.Padding = UDim.new(0, 10)
		l.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local p = Instance.new("UIPadding", c)
		p.PaddingLeft = UDim.new(0, 15)
		p.PaddingRight = UDim.new(0, 15)
		p.PaddingBottom = UDim.new(0, 15)

		local am = Instance.new("Frame", sg)
		am.Name = "Advanced"
		am.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
		am.Position = UDim2.new(0.5, -SIDE_W / 2, 0.5, -SIDE_H / 2)
		am.Size = UDim2.new(0, SIDE_W, 0, SIDE_H)
		am.Visible = false
		am.Active = true
		Instance.new("UICorner", am).CornerRadius = UDim.new(0, 10)
		local ams = Instance.new("UIStroke", am)
		ams.Color = Color3.fromRGB(40, 40, 45)
		ams.Thickness = 1

		-- Advanced is toggled with plain Visible (no pop animation), so it sits
		-- at full pop but still follows the app scale.
		register_window(am, 1)
		register_side_panel(am)

		local ah = Instance.new("Frame", am)
		ah.BackgroundTransparency = 1
		ah.Size = UDim2.new(1, 0, 0, SIDE_HEADER_H)
		make_draggable(am, ah)
		local at = Instance.new("TextLabel", ah)
		at.BackgroundTransparency = 1
		at.Position = UDim2.new(0, 15, 0, 0)
		at.Size = UDim2.new(0.6, 0, 1, 0)
		at.Text = "ADVANCED"
		at.TextColor3 = Color3.fromRGB(255, 255, 255)
		at.Font = Enum.Font.GothamBold
		at.TextSize = 8
		at.TextXAlignment = 0

		side_close(ah, function()
			close_side_panel(am)
		end)

		local ac = Instance.new("ScrollingFrame", am)
		ac.BackgroundTransparency = 1
		ac.Position = UDim2.new(0, 0, 0, SIDE_HEADER_H + SIDE_CONTENT_GAP)
		ac.Size = UDim2.new(1, 0, 1, -(SIDE_HEADER_H + SIDE_CONTENT_GAP + SIDE_BOTTOM))
		ac.ScrollBarThickness = 0
		ac.AutomaticCanvasSize = Enum.AutomaticSize.Y
		ac.CanvasSize = UDim2.new(0, 0, 0, 0)

		-- Notifications from this panel go straight through System's x8 rather than the
		-- local notify() further down the file, which is declared after this block: a
		-- reference to it from in here resolves to a nil global and the message is lost.
		local function adv_notify(title, text, dur)
			local x8 = context.x8
			if x8 and x8.notify then
				x8.notify(title, text, dur or 3)
			end
		end

		-- eb has no description row, and three of the controls below need one. Same
		-- geometry as the description M.s and M.t draw for themselves.
		local function sub_label(parent, text)
			local d = Instance.new("TextLabel", parent)
			d.BackgroundTransparency = 1
			d.Size = UDim2.new(1, 0, 0, 0)
			d.AutomaticSize = Enum.AutomaticSize.Y
			d.Text = text
			d.TextColor3 = Color3.fromRGB(120, 120, 130)
			d.TextXAlignment = 0
			d.TextYAlignment = 0
			d.Font = Enum.Font.Gotham
			d.TextSize = 8
			d.TextWrapped = true
			return d
		end

		-- An enum rendered as a button that cycles. config.lua records that shape enums
		-- are integer sliders "(no Dropdown control exists)", which is tolerable for a
		-- three-value shape knob and not for six named release rules: here the label
		-- carries the current value and one tap advances it, so there is no number for
		-- the user to map onto a word and still no new element type.
		local function cycle_btn(parent, label, values, get, set, desc)
			local btn
			local function label_now()
				return label .. ": " .. tostring(get())
			end
			btn = eb(parent, label_now(), function()
				local cur, idx = get(), 1
				for i, v in ipairs(values) do
					if v == cur then
						idx = i
						break
					end
				end
				set(values[(idx % #values) + 1])
				btn.Text = label_now()
				save_settings()
			end)
			if desc then
				sub_label(parent, desc)
			end
			return btn
		end

		-- Resolves what was typed into a registered shape name: exact first, then a
		-- prefix, then a substring, over a sorted list so two shapes that both match
		-- always resolve the same way. Returns nil when nothing matches, and the caller
		-- puts the box back to what it was -- silently keeping an unknown name would
		-- leave the blend permanently inert with no way to tell from the panel.
		local function resolve_shape_name(typed)
			typed = tostring(typed or ""):gsub("^%s*(.-)%s*$", "%1")
			if typed == "" then
				return nil
			end
			local names = {}
			for mn in pairs(x2) do
				names[#names + 1] = mn
			end
			table.sort(names)
			local want = typed:lower()
			for _, mn in ipairs(names) do
				if mn:lower() == want then
					return mn
				end
			end
			for _, mn in ipairs(names) do
				if mn:lower():sub(1, #want) == want then
					return mn
				end
			end
			for _, mn in ipairs(names) do
				if mn:lower():find(want, 1, true) then
					return mn
				end
			end
			return nil
		end

		local SLOT_MODES = { "Claim", "Size Desc", "Size Asc", "Distance", "Shuffle" }
		local SURPLUS_RULES = { "Farthest", "Nearest", "Newest", "Oldest", "Smallest", "Largest" }

		-- UIListLayout.SortOrder defaults to **Name**, not LayoutOrder. For a list whose
		-- children are all one class that is harmless: they share a name, the sort is stable,
		-- and the order they were built in survives -- which is why every list in this file
		-- got away with the default. The Advanced panel is the one list that mixes classes.
		-- Sliders, toggles and text boxes are Frames, section headers and descriptions are
		-- TextLabels, and the cycling buttons are TextButtons; sorted by name,
		-- "Frame" < "TextButton" < "TextLabel", so every control floated to the top of the
		-- panel and every heading sank into a single block at the bottom. That is what the
		-- panel has looked like since it gained headers, and adding two more sections, two
		-- buttons and three descriptions is what finally made it unmissable.
		--
		-- Numbering the children in build order and putting the layout into LayoutOrder mode
		-- is the whole fix. It has to run again after any rebuild, because new children arrive
		-- at LayoutOrder 0 and would sort ahead of everything already numbered.
		local LAYOUT_MODIFIERS = {
			UIListLayout = true, UIPadding = true, UICorner = true, UIStroke = true,
			UIGradient = true, UIScale = true, UISizeConstraint = true, UIFlexItem = true,
			UIAspectRatioConstraint = true, UITextSizeConstraint = true,
		}
		local function order_children(container, layout)
			if layout then
				layout.SortOrder = Enum.SortOrder.LayoutOrder
			end
			local n = 0
			for _, child in ipairs(container:GetChildren()) do
				-- ClassName against a list of the modifiers, rather than IsA("GuiObject"):
				-- LayoutOrder does not exist on a UIPadding, and writing a property an
				-- instance does not have is an error rather than a no-op.
				if not LAYOUT_MODIFIERS[child.ClassName] then
					n = n + 1
					child.LayoutOrder = n
				end
			end
			return n
		end

		-- Grouped, in the order the controls were already in -- nothing moves. Fifteen
		-- controls in one flat list was the only panel in the tree without headers, and
		-- it is the longest one, on the smallest screen.
		-- Rebuild cached sliders after an AI settings change or a reset.
		local function populate_advanced()
			ac:ClearAllChildren()
			local acl = Instance.new("UIListLayout", ac)
			acl.Padding = UDim.new(0, 8)
			acl.HorizontalAlignment = Enum.HorizontalAlignment.Center
			local ap = Instance.new("UIPadding", ac)
			ap.PaddingLeft = UDim.new(0, 15)
			ap.PaddingRight = UDim.new(0, 15)
			eh(ac, "Tracking")
			et(ac, "Predictive Tracking", x1.PredictiveTracking ~= false, function(v)
				x1.PredictiveTracking = v
				save_settings()
			end, "Predicts player movement to smooth out parts when targeting them.")
			es(ac, "Prediction Factor", 0, 500, x1.PredictionFactor or 150, function(v)
				x1.PredictionFactor = v
				save_settings()
			end, false, "How far ahead the script predicts the target's movement.")
			eh(ac, "Physics")
			es(ac, "Damping", 0, 5, x1.Damping, function(v)
				x1.Damping = v
				save_settings()
			end, false, "Slows recovery toward the target without slowing its orbit. Higher values settle more gently. Launch and impact modes use their own motion.")
			es(ac, "Integral Gain", 0, 10, x1.Ki, function(v)
				x1.Ki = v
				save_settings()
			end, false, "Helps parts reach their exact target position faster (fixes sagging).")
			es(ac, "Max Speed", 50, 2000, x1.MaxSpeed or 500, function(v)
				x1.MaxSpeed = v
				save_settings()
			end, false, "Caps the maximum velocity of all parts to prevent them from flinging.")
			es(ac, "Angular Damp", 0, 1, x1.AngularDamping or 0.5, function(v)
				x1.AngularDamping = v
				save_settings()
			end, false, "Stops parts from spinning uncontrollably on their own axis.")
			es(ac, "Vert Stiffness", 0.1, 5, x1.VerticalStiffness or 1.0, function(v)
				x1.VerticalStiffness = v
				save_settings()
			end, false, "Multiplies vertical pull to fight Roblox's gravity. Use 1.0 for normal.")

			eh(ac, "Formation")
			es(ac, "Time Scale", -3, 3, x1.TimeScale or 1.0, function(v)
				x1.TimeScale = v
				save_settings()
			end, false, "Speed of the shape's own motion. 1 is normal, 0 freezes the pattern where it is, below 0 runs it backwards.")
			cycle_btn(ac, "Slot Order", SLOT_MODES, function()
				return x1.SlotMode or "Claim"
			end, function(v)
				x1.SlotMode = v
			end, "Which part goes where. Claim is the order they were grabbed in; the rest sort the formation so the biggest, nearest or a shuffled part lands in slot 1. Re-sorted when the population changes or you press Re-roll Layout, not continuously.")
			eb(ac, "Re-roll Layout", function()
				local x4 = context.x4
				if not (x4 and x4.reroll_seeds) then
					return
				end
				local n = x4.reroll_seeds()
				save_settings()
				adv_notify("Formation", n .. " parts re-seeded", 2)
			end)
			sub_label(ac, "Scatters the current shape again without dropping the parts, and re-orders Shuffle.")
			et(ac, "Shape Blend", x1.BlendEnabled, function(v)
				x1.BlendEnabled = v
				save_settings()
			end, "Runs a second shape alongside the selected one and mixes the two.")
			local blend_box
			blend_box = etb(ac, "Blend Shape", x1.BlendShape or "", function(v)
				local resolved = resolve_shape_name(v)
				if resolved then
					x1.BlendShape = resolved
					blend_box.Text = resolved
					-- Lets the runtime try again: it stops re-fetching a module that failed to
					-- download, and a name change is the deliberate retry.
					x6.bl_failed = nil
				else
					-- Keeping an unknown name would leave the blend permanently inert with
					-- nothing in the panel to say why.
					adv_notify("Blend", "No shape matches \"" .. tostring(v) .. "\"", 3)
					blend_box.Text = x1.BlendShape or ""
				end
				save_settings()
			end, "The second shape. Type any part of its name.")
			es(ac, "Blend Weight", 0, 100, x1.BlendWeight or 0, function(v)
				x1.BlendWeight = v
				save_settings()
			end, true, "0 is all the selected shape, 100 is all the blend shape.")
			es(ac, "Blend Stagger", 0, 100, x1.BlendStagger or 0, function(v)
				x1.BlendStagger = v
				save_settings()
			end, true, "Spreads the mix across the formation so it converts part by part. Needs Slot Order set to something other than Claim.")

			eh(ac, "Preview")
			et(ac, "Formation Preview", x1.PreviewEnabled, function(v)
				x1.PreviewEnabled = v
				-- The loop clears the markers itself, but only while it is running: with the
				-- script stopped or disabled nothing would ever come and collect them.
				if not v then
					local x4 = context.x4
					if x4 and x4.preview_clear then
						x4.preview_clear()
					end
				end
				save_settings()
			end, "Shows where the shape would put parts, using markers instead of parts. Works with nothing claimed.")
			es(ac, "Ghost Count", 4, 200, x1.PreviewCount or 40, function(v)
				x1.PreviewCount = v
				save_settings()
			end, true, "How many preview markers to draw.")
			et(ac, "Deviation Readout", x1.PreviewDeviation, function(v)
				x1.PreviewDeviation = v
				save_settings()
			end, "Adds the average and worst distance between a part and the target it was given to the status HUD.")

			eh(ac, "Interface")
			es(ac, "UI Scale", 0.5, 2.0, x1.UIScale or 1.0, function(v)
				x1.UIScale = v
				-- Every registered window, not just Main and Advanced: the shape
				-- selector, target list, tutorial and dialogs are siblings here and
				-- would otherwise be left at the old scale.
				apply_ui_scale()
				save_settings()
			end, false, "Scales the entire interface. 1.0 is default.")

			eh(ac, "Claiming")
			et(ac, "Aggressive Claiming", x1.AggressiveClaim, function(v)
				x1.AggressiveClaim = v
				save_settings()
			end, "WARNING: Spams CFrames into your character to forcefully steal Network Ownership from other scripts.")

			et(ac, "Void Protection", x1.VoidProtection, function(v)
				x1.VoidProtection = v
				save_settings()
			end, "Automatically ignores targets that fall into the void to prevent your parts from being destroyed.")

			-- A rule change has to act on the formation in front of you, not only on the next
			-- claim, or editing one looks like it did nothing at all.
			local function rules_changed()
				save_settings()
				local x4 = context.x4
				if x4 and x4.recheck_rules then
					local n = x4.recheck_rules()
					if n > 0 then
						adv_notify("Claim Rules", n .. " parts released", 2)
					end
				end
			end

			es(ac, "Target Parts", 0, 5000, x1.TargetParts or 0, function(v)
				x1.TargetParts = v
				save_settings()
			end, true, "Holds the formation at this many parts, releasing the surplus. 0 is no limit.")
			cycle_btn(ac, "Surplus Rule", SURPLUS_RULES, function()
				return x1.SurplusRule or "Farthest"
			end, function(v)
				x1.SurplusRule = v
			end, "Which parts go when there are more than Target Parts. Parts held by Part Control are never released this way.")
			es(ac, "Min Part Size", 0, 200, x1.RuleMinSize or 0, function(v)
				x1.RuleMinSize = v
				rules_changed()
			end, false, "Ignores parts whose longest side is under this many studs. 0 is off.")
			es(ac, "Max Part Size", 0, 500, x1.RuleMaxSize or 0, function(v)
				x1.RuleMaxSize = v
				rules_changed()
			end, false, "Ignores parts whose longest side is over this many studs. 0 is off.")
			es(ac, "Claim Radius", 0, 2000, x1.RuleClaimRadius or 0, function(v)
				x1.RuleClaimRadius = v
				save_settings()
			end, false, "Only claims parts within this many studs of the core, measured when they are picked up. 0 is off.")
			etb(ac, "Name Filter", x1.RuleName or "", function(v)
				x1.RuleName = tostring(v or "")
				rules_changed()
			end, "Comma-separated. A plain word claims only parts whose name contains it; a word starting with - never claims a match. Empty is off.", 120)

			-- x1.k5 has been the one extensible hook in the claim filter since the start and
			-- has never had a way to reach it.
			local function tags_text()
				local t = x1.k5
				if type(t) ~= "table" then
					return ""
				end
				-- Filtered rather than handed straight to table.concat: k5 comes back from the
				-- settings file as whatever was in it, and concat throws on a non-string entry
				-- -- which would take the whole panel build down with it.
				local out = {}
				for _, tag in ipairs(t) do
					if type(tag) == "string" then
						out[#out + 1] = tag
					end
				end
				return table.concat(out, ", ")
			end

			etb(ac, "Ignore Tags", tags_text(), function(v)
				local list = {}
				for entry in tostring(v or ""):gmatch("[^,]+") do
					local tag = entry:gsub("^%s*(.-)%s*$", "%1")
					if tag ~= "" then
						list[#list + 1] = tag
					end
				end
				x1.k5 = list
				rules_changed()
			end, "Never claims a part that has a child with one of these names, or whose parent does. Emptying this drops the two defaults; Reset All Settings puts them back.", 120)

			eh(ac, "Performance")
			if setfpscap then
				-- 240, matching the desktop tree's slider. The two panels write the same
				-- x1.FPSCap into the same settings file, and a 144 ceiling here silently
				-- clamped a value set on desktop the first time this panel was opened.
				es(ac, "FPS Cap (0=Unc)", 0, 240, x1.FPSCap or 60, function(v)
					x1.FPSCap = v
					setfpscap(v)
					save_settings()
				end, true, "Caps your max FPS. 0 means uncapped.")
			end

			et(ac, "Disable Shadows", x1.Perf_DisableShadows, function(v)
				x1.Perf_DisableShadows = v
				ApplyPerfShadows(v)
				save_settings()
			end, "Turns off all game shadows to boost your FPS significantly.")
			et(ac, "Disable Post-FX", x1.Perf_DisablePostFX, function(v)
				x1.Perf_DisablePostFX = v
				ApplyPerfPostFX(v)
				save_settings()
			end, "Disables Bloom, Blur, SunRays, and ColorCorrection to save performance.")
			et(ac, "Potato Materials", x1.Perf_PotatoMaterials, function(v)
				x1.Perf_PotatoMaterials = v
				ApplyPerfMaterials(v)
				save_settings()
			end, "Forces all parts in the game to use SmoothPlastic to lower rendering load.")
			et(ac, "Hide Particles", x1.Perf_HideParticles, function(v)
				x1.Perf_HideParticles = v
				ApplyPerfParticles(v)
				save_settings()
			end, "Hides fire, smoke, beams, trails, and particle emitters.")

			ApplyPerfShadows(x1.Perf_DisableShadows)
			ApplyPerfPostFX(x1.Perf_DisablePostFX)
			ApplyPerfMaterials(x1.Perf_PotatoMaterials)
			ApplyPerfParticles(x1.Perf_HideParticles)

			local function update_color()
				if x6.b then
					x6.b.Color = x1.k3
					if x6.b:FindFirstChild("Visual") and x6.b.Visual:FindFirstChildOfClass("ImageLabel") then
						x6.b.Visual:FindFirstChildOfClass("ImageLabel").ImageColor3 = x1.k3
					end
				end
				save_settings()
			end

			-- Each channel slider rebuilds the whole colour, so it has to hand the
			-- other two back as the same integers they came in as. Color3 stores 0-1
			-- floats and v/255 does not round-trip exactly, so the bare product
			-- re-quantised the untouched channels on every drag.
			local function ch(x)
				return math.floor(x * 255 + 0.5)
			end
			eh(ac, "Core Marker")
			es(ac, "Center Color R", 0, 255, ch(x1.k3.R), function(v)
				x1.k3 = Color3.fromRGB(v, ch(x1.k3.G), ch(x1.k3.B))
				update_color()
			end, true)
			es(ac, "Center Color G", 0, 255, ch(x1.k3.G), function(v)
				x1.k3 = Color3.fromRGB(ch(x1.k3.R), v, ch(x1.k3.B))
				update_color()
			end, true)
			es(ac, "Center Color B", 0, 255, ch(x1.k3.B), function(v)
				x1.k3 = Color3.fromRGB(ch(x1.k3.R), ch(x1.k3.G), v)
				update_color()
			end, true)

			-- Last, once every row exists: this is what keeps each control under its own
			-- heading instead of sorted by class name. See order_children.
			order_children(ac, acl)
		end
		x5.refresh_advanced = populate_advanced
		populate_advanced()

		-- A CanvasGroup, unlike Advanced: it is the one side panel that animates, so
		-- it needs a GroupTransparency to fade rather than a BackgroundTransparency
		-- that would fade the panel out from under its own children. It was also
		-- never registered for scaling, which made it the only window in the tree
		-- that ignored the UI Scale setting outright.
		local pcm = Instance.new("CanvasGroup", sg)
		pcm.Name = "PartControl"
		pcm.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
		pcm.Position = UDim2.new(0.5, -SIDE_W / 2, 0.5, -SIDE_H / 2)
		pcm.Size = UDim2.new(0, SIDE_W, 0, SIDE_H)
		pcm.Visible = false
		pcm.GroupTransparency = 1
		-- The panel is rebuilt closed, and pc_active lives on x6, which outlives a
		-- UI teardown -- so a rebuild would otherwise come up armed with the panel
		-- shut.
		x6.pc_active = false
		pcm.Active = true
		Instance.new("UICorner", pcm).CornerRadius = UDim.new(0, 10)
		local pcms = Instance.new("UIStroke", pcm)
		pcms.Color = Color3.fromRGB(40, 40, 45)
		pcms.Thickness = 1
		register_window(pcm, 0.8)
		-- Registered with an on_close, so closing the panel through any route -- its
		-- own button, Advanced opening over it, or the whole panel collapsing to the
		-- pill -- disarms the tap handlers.
		register_side_panel(pcm, function()
			x6.pc_active = false
		end)

		local pch = Instance.new("Frame", pcm)
		pch.BackgroundTransparency = 1
		pch.Size = UDim2.new(1, 0, 0, SIDE_HEADER_H)
		make_draggable(pcm, pch)
		local pct = Instance.new("TextLabel", pch)
		pct.BackgroundTransparency = 1
		pct.Position = UDim2.new(0, 15, 0, 0)
		pct.Size = UDim2.new(0.6, 0, 1, 0)
		pct.Text = "PART CONTROL"
		pct.TextColor3 = Color3.fromRGB(255, 255, 255)
		pct.Font = Enum.Font.GothamBold
		pct.TextSize = 8
		pct.TextXAlignment = 0

		side_close(pch, function()
			close_side_panel(pcm)
		end)

		local pcc = Instance.new("ScrollingFrame", pcm)
		pcc.BackgroundTransparency = 1
		pcc.Position = UDim2.new(0, 0, 0, SIDE_HEADER_H + SIDE_CONTENT_GAP)
		pcc.Size = UDim2.new(1, 0, 1, -(SIDE_HEADER_H + SIDE_CONTENT_GAP + SIDE_BOTTOM))
		pcc.ScrollBarThickness = 0
		pcc.AutomaticCanvasSize = Enum.AutomaticSize.Y
		pcc.CanvasSize = UDim2.new(0, 0, 0, 0)

		-- Built once and refreshed in place, same reasoning as the desktop panel:
		-- rebuilding on every refresh meant the selection count was only ever right
		-- at the instant the window opened, and a refresh landing mid-tap destroyed
		-- the control being tapped. The shape list is the one rebuilt piece, and its
		-- search box sits outside it so a keystroke cannot destroy it.
		local pccl = Instance.new("UIListLayout", pcc)
		pccl.Padding = UDim.new(0, 8)
		pccl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local pcp = Instance.new("UIPadding", pcc)
		pcp.PaddingLeft = UDim.new(0, 15)
		pcp.PaddingRight = UDim.new(0, 15)
		-- Main pads the bottom; without it the last toggle sits flush against the
		-- panel edge, which on touch means the last row is also the hardest to hit.
		pcp.PaddingBottom = UDim.new(0, 15)

		local function pc_notify(title, msg, secs)
			local x8 = context.x8
			if x8 and x8.notify then
				x8.notify(title, msg, secs or 2)
			end
		end

		local pc_sync = {}
		local function pc_slider(key, ...)
			local control, sync = es(...)
			pc_sync[#pc_sync + 1] = function() sync(x1[key]) end
			return control
		end
		local function pc_toggle(key, ...)
			local control, sync = et(...)
			pc_sync[#pc_sync + 1] = function() sync(x1[key]) end
			return control
		end

		local count_lbl = Instance.new("TextLabel", pcc)
		count_lbl.BackgroundTransparency = 1
		count_lbl.Size = UDim2.new(1, 0, 0, 14)
		count_lbl.Text = "Selected: 0  ·  Overridden: 0"
		count_lbl.TextColor3 = Color3.fromRGB(255, 170, 0)
		count_lbl.Font = Enum.Font.GothamBold
		count_lbl.TextSize = 9
		count_lbl.TextXAlignment = 0

		-- "Overridden: 7" does not say what those seven are doing, and the three modes
		-- behave nothing like each other. Hidden when there are none, so the panel does
		-- not carry a row of zeroes for the common case -- which matters more here,
		-- where the whole body is 250px tall.
		local mode_lbl = Instance.new("TextLabel", pcc)
		mode_lbl.BackgroundTransparency = 1
		mode_lbl.Size = UDim2.new(1, 0, 0, 12)
		mode_lbl.Text = ""
		mode_lbl.TextColor3 = Color3.fromRGB(150, 150, 160)
		mode_lbl.Font = Enum.Font.GothamMedium
		mode_lbl.TextSize = 8
		mode_lbl.TextXAlignment = 0
		mode_lbl.Visible = false

		local hint_lbl = Instance.new("TextLabel", pcc)
		hint_lbl.BackgroundTransparency = 1
		hint_lbl.Size = UDim2.new(1, 0, 0, 0)
		hint_lbl.AutomaticSize = Enum.AutomaticSize.Y
		-- Filled by refresh_counts, which owns both wordings; see HINT_EMPTY below.
		hint_lbl.Text = ""
		hint_lbl.TextColor3 = Color3.fromRGB(120, 120, 130)
		hint_lbl.Font = Enum.Font.Gotham
		hint_lbl.TextSize = 8
		hint_lbl.TextWrapped = true
		hint_lbl.TextXAlignment = 0

		local MODE_LABELS = {
			normal = "Normal (No Override)",
			pin = "Pin (Hold Position)",
			manual = "Manual Target",
			shape = "Assign Shape",
		}
		local mode_paint = {}

		local function refresh_modes()
			for _, paint in pairs(mode_paint) do
				paint()
			end
		end

		local function pc_selection()
			return (x6.pc_count and x6.pc_count()) or 0
		end

		-- Two hints, because the first thing the panel has to answer is whether it is
		-- waiting on a selection. With nothing selected every action below is a no-op,
		-- and the panel used to give no sign of that at all.
		local HINT_EMPTY = "Nothing selected. Tap a held part to select it -- selecting on its "
			.. "own changes nothing. Turn on Multi-Select to add or remove."
		local HINT_SELECTED = "Pick a mode below to apply it, or drag a selected part to place it. "
			.. "The box colour is the mode: orange none, red pin, blue manual, violet shape."

		local function refresh_counts()
			local sel = pc_selection()
			local held, pins, manuals, shapes = 0, 0, 0, 0
			if x6.a then
				for _, d in pairs(x6.a) do
					local m = d.pc_mode
					if m or d.pc_ride or d.pc_phys then
						held = held + 1
						if m == "pin" then
							pins = pins + 1
						elseif m == "manual" then
							manuals = manuals + 1
						elseif m == "shape" then
							shapes = shapes + 1
						end
					end
				end
			end
			count_lbl.Text = ("Selected: %d  ·  Overridden: %d"):format(sel, held)
			mode_lbl.Visible = held > 0
			if held > 0 then
				mode_lbl.Text = ("Pin %d  ·  Manual %d  ·  Shape %d"):format(pins, manuals, shapes)
			end
			hint_lbl.Text = (sel > 0) and HINT_SELECTED or HINT_EMPTY
		end

		eb(pcc, "Clear Selection", function()
			if x6.pc_clear then
				x6.pc_clear()
			end
		end)

		-- Deselecting deliberately leaves the overrides in place, so there has to be
		-- a way to take them off once the parts are no longer selected. Before this,
		-- Clear Selection dropped the whole registry and the parts it had been
		-- driving were stranded with no route back.
		eb(pcc, "Release All Overrides", function()
			if x6.pc_release_all then
				local n = x6.pc_release_all()
				pc_notify("Part Control", ("Released %d part%s"):format(n, n == 1 and "" or "s"))
			end
		end)

		-- This tree has no box-select at all, so these are the only bulk selection there
		-- is. Select Overridden is also the only way back to a part that was assigned
		-- and then deselected, short of releasing the lot.
		eb(pcc, "Select All Held", function()
			if x6.pc_select_all then
				local n, capped = x6.pc_select_all()
				pc_notify(
					"Part Control",
					("Selected %d part%s%s"):format(n, n == 1 and "" or "s", capped and " (capped)" or "")
				)
			end
		end)

		eb(pcc, "Select Overridden", function()
			if x6.pc_select_overridden then
				local n, capped = x6.pc_select_overridden()
				if n == 0 then
					pc_notify("Part Control", "Nothing is overridden.", 2)
				else
					pc_notify(
						"Part Control",
						("Selected %d overridden part%s%s"):format(n, n == 1 and "" or "s", capped and " (capped)" or "")
					)
				end
			end
		end)

		eb(pcc, "Invert Selection", function()
			if x6.pc_invert then
				x6.pc_invert()
			end
		end)

		eh(pcc, "Mode")

		local function set_mode(id)
			x1.PartCtlMode = id
			local sel = pc_selection()
			if x6.pc_assign then
				if id == "normal" then
					x6.pc_assign(nil)
				elseif id == "shape" then
					local n = x6.pc_assign("shape", { shape = x1.PartCtlShape or "Black Hole", ride = x1.PartCtlRide })
					if n == 0 and sel > 0 then
						pc_notify("Part Control", tostring(x1.PartCtlShape) .. " cannot drive parts.", 3)
					end
				else
					x6.pc_assign(id, { ride = x1.PartCtlRide })
				end
			end
			-- The mode is also the default the next selection and every drag latch
			-- picks up, so choosing one with nothing selected is not a mistake -- but
			-- it looks like one unless it says so.
			if sel == 0 then
				pc_notify("Part Control", MODE_LABELS[id] .. " will apply to the next selection.", 2)
			end
			refresh_modes()
			save_settings()
		end

		-- A radio group painted the way the mode selector paints its rows, rather than
		-- by prefixing the label with a bullet: eb tweens both BackgroundColor3 and
		-- TextColor3 on press, so an eb button cannot hold a selected tint. Rows are
		-- 22 rather than eb's 20 -- the smallest bump that keeps four of them apart
		-- under a thumb, and the one place this panel deliberately leaves the tree's
		-- button height.
		local function mode_row(id)
			local b = Instance.new("TextButton", pcc)
			b.Size = UDim2.new(1, 0, 0, 22)
			b.AutoButtonColor = false
			b.BorderSizePixel = 0
			b.Text = "  " .. MODE_LABELS[id]
			b.Font = Enum.Font.GothamMedium
			b.TextSize = 9
			b.TextXAlignment = Enum.TextXAlignment.Left
			b.TextTruncate = Enum.TextTruncate.AtEnd
			Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
			local str = Instance.new("UIStroke", b)
			str.Thickness = 1

			local function paint(instant)
				local on = x1.PartCtlMode == id
				local bg = on and Color3.fromRGB(40, 40, 180) or Color3.fromRGB(30, 30, 35)
				local fg = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 220, 220)
				local edge = on and Color3.fromRGB(70, 70, 200) or Color3.fromRGB(50, 50, 55)
				if instant then
					b.BackgroundColor3, b.TextColor3, str.Color = bg, fg, edge
					return
				end
				v6:Create(b, A.TINT, { BackgroundColor3 = bg, TextColor3 = fg }):Play()
				v6:Create(str, A.TINT, { Color = edge }):Play()
			end

			b.MouseButton1Click:Connect(function()
				set_mode(id)
			end)
			UI_elements.press(b, 0.97)
			paint(true)
			mode_paint[id] = paint
		end

		for _, id in ipairs({ "normal", "pin", "manual", "shape" }) do
			mode_row(id)
		end
		refresh_modes()

		-- A section that folds. Expanded, the shape picker and the four physics
		-- sliders run to roughly three times the height of a 250px panel, and
		-- reaching Options means dragging past a nested scroller -- which on touch
		-- steals the gesture from the panel's own scroll and is the single worst
		-- thing about using this panel on a phone. The head carries the section's
		-- current value, so the state is still readable while it is shut.
		--
		-- Folding is Visible on the body, not a size tween: UIListLayout skips
		-- invisible children, so the rows below close the gap on their own and
		-- AutomaticCanvasSize re-measures the canvas with them.
		local function collapsible(title, open, value_fn)
			local head = Instance.new("TextButton", pcc)
			head.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
			head.Size = UDim2.new(1, 0, 0, 22)
			head.AutoButtonColor = false
			head.BorderSizePixel = 0
			head.Text = ""
			Instance.new("UICorner", head).CornerRadius = UDim.new(0, 6)
			local hstr = Instance.new("UIStroke", head)
			hstr.Color = Color3.fromRGB(40, 40, 45)
			hstr.Thickness = 1

			local hl = Instance.new("TextLabel", head)
			hl.BackgroundTransparency = 1
			hl.Position = UDim2.new(0, 8, 0, 0)
			hl.Size = UDim2.new(0.5, 0, 1, 0)
			hl.Text = title:upper()
			hl.TextColor3 = Color3.fromRGB(200, 200, 210)
			hl.Font = Enum.Font.GothamBold
			hl.TextSize = 8
			hl.TextXAlignment = Enum.TextXAlignment.Left

			local vl = Instance.new("TextLabel", head)
			vl.BackgroundTransparency = 1
			vl.Position = UDim2.new(0.5, 0, 0, 0)
			vl.Size = UDim2.new(0.5, -22, 1, 0)
			vl.Text = ""
			vl.TextColor3 = Color3.fromRGB(0, 255, 200)
			vl.Font = Enum.Font.GothamMedium
			vl.TextSize = 8
			vl.TextXAlignment = Enum.TextXAlignment.Right
			vl.TextTruncate = Enum.TextTruncate.AtEnd

			local arrow = Instance.new("TextLabel", head)
			arrow.BackgroundTransparency = 1
			arrow.Position = UDim2.new(1, -20, 0, 0)
			arrow.Size = UDim2.new(0, 16, 1, 0)
			arrow.Text = open and "▲" or "▼"
			arrow.TextColor3 = Color3.fromRGB(150, 150, 160)
			arrow.Font = Enum.Font.GothamBold
			arrow.TextSize = 8

			local body = Instance.new("Frame", pcc)
			body.BackgroundTransparency = 1
			body.Size = UDim2.new(1, 0, 0, 0)
			body.AutomaticSize = Enum.AutomaticSize.Y
			body.Visible = open and true or false
			local bl = Instance.new("UIListLayout", body)
			bl.Padding = UDim.new(0, 8)
			bl.HorizontalAlignment = Enum.HorizontalAlignment.Center

			head.MouseButton1Click:Connect(function()
				body.Visible = not body.Visible
				arrow.Text = body.Visible and "▲" or "▼"
			end)
			UI_elements.press(head, 0.98)

			local function refresh_head()
				if value_fn then
					vl.Text = tostring(value_fn() or "")
				end
			end
			refresh_head()
			return body, refresh_head
		end

		local shape_body, refresh_shape_head = collapsible("Target Shape", false, function()
			return x1.PartCtlShape or "Black Hole"
		end)

		-- Outside the list it filters, so a keystroke cannot destroy the box being
		-- typed into. The picker was a single button that cycled one shape per tap
		-- through every entry in x2 -- unusable on touch with fifty-odd shapes.
		-- Styled like the mode and target searches in this tree: 20/20/25, Gotham.
		local pcsearch = Instance.new("TextBox", shape_body)
		pcsearch.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		pcsearch.Size = UDim2.new(1, 0, 0, 24)
		pcsearch.Text = ""
		pcsearch.PlaceholderText = "Search shapes..."
		pcsearch.PlaceholderColor3 = Color3.fromRGB(110, 110, 120)
		pcsearch.TextColor3 = Color3.fromRGB(255, 255, 255)
		pcsearch.Font = Enum.Font.Gotham
		pcsearch.TextSize = 9
		pcsearch.ClearTextOnFocus = false
		Instance.new("UICorner", pcsearch).CornerRadius = UDim.new(0, 6)

		local pcslist = Instance.new("ScrollingFrame", shape_body)
		pcslist.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		pcslist.BorderSizePixel = 0
		pcslist.Size = UDim2.new(1, 0, 0, 116)
		-- 0 like every other scroller in the tree; this list was the only one showing
		-- a bar, and on touch the bar is not the thing you scroll with anyway.
		pcslist.ScrollBarThickness = 0
		pcslist.AutomaticCanvasSize = Enum.AutomaticSize.Y
		pcslist.CanvasSize = UDim2.new(0, 0, 0, 0)
		Instance.new("UICorner", pcslist).CornerRadius = UDim.new(0, 6)

		-- The same widget as the mode selector's rows, down to the 24px height, the
		-- favourites star and the favourites-first ordering, so a shape sits in the
		-- same place in both lists.
		local function populate_pc_shapes(filter)
			pcslist:ClearAllChildren()
			local sl = Instance.new("UIListLayout", pcslist)
			sl.Padding = UDim.new(0, 4)
			sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
			local names = {}
			for sn, _ in pairs(x2) do
				-- Sculptor is a tool, not a driver; pc_assign refuses it outright.
				if sn ~= "Sculptor" then
					table.insert(names, sn)
				end
			end
			table.sort(names, function(a, b)
				local fa, fb = favorites[a] and 1 or 0, favorites[b] and 1 or 0
				if fa ~= fb then
					return fa > fb
				end
				return a < b
			end)
			filter = filter or ""
			for _, sn in ipairs(names) do
				-- Plain find: without the flag a typed "(" is an unfinished Lua
				-- capture and throws out of the Text callback after the list has
				-- already been cleared.
				if filter ~= "" and not sn:lower():find(filter:lower(), 1, true) then
					continue
				end
				local row = Instance.new("Frame", pcslist)
				row.Size = UDim2.new(1, -8, 0, 24)
				local row_on = sn == x1.PartCtlShape
				row.BackgroundColor3 = row_on and Color3.fromRGB(40, 40, 180) or Color3.fromRGB(25, 25, 30)
				row.BorderSizePixel = 0
				Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
				-- idle passed in rather than read back, so the selected row keeps its tint
				-- when the pointer leaves.
				row_hover(
					row,
					row.BackgroundColor3,
					row_on and Color3.fromRGB(55, 55, 200) or Color3.fromRGB(35, 35, 40)
				)

				local pick = Instance.new("TextButton", row)
				pick.Position = UDim2.new(0, 6, 0, 0)
				pick.Size = UDim2.new(1, -32, 1, 0)
				pick.BackgroundTransparency = 1
				pick.Text = sn
				pick.TextColor3 = Color3.fromRGB(255, 255, 255)
				pick.Font = Enum.Font.GothamBold
				pick.TextSize = 9
				pick.TextXAlignment = Enum.TextXAlignment.Left
				pick.TextTruncate = Enum.TextTruncate.AtEnd

				local star = Instance.new("TextButton", row)
				star.Position = UDim2.new(1, -28, 0, 0)
				star.Size = UDim2.new(0, 28, 1, 0)
				star.BackgroundTransparency = 1
				star.Text = favorites[sn] and "★" or "☆"
				star.TextColor3 = favorites[sn] and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(80, 80, 85)
				star.Font = Enum.Font.GothamBold
				star.TextSize = 11
				star.MouseButton1Click:Connect(function()
					favorites[sn] = not favorites[sn]
					save_favs()
					populate_pc_shapes(pcsearch.Text)
				end)

				pick.MouseButton1Click:Connect(function()
					x1.PartCtlShape = sn
					refresh_shape_head()
					-- Only re-assigns when shape mode is already live, so browsing the
					-- list does not silently retarget the selection.
					if x1.PartCtlMode == "shape" and x6.pc_assign then
						local n = x6.pc_assign("shape", { shape = sn, ride = x1.PartCtlRide })
						if n == 0 and pc_selection() > 0 then
							pc_notify("Part Control", sn .. " cannot drive parts.", 3)
						end
					end
					save_settings()
					populate_pc_shapes(pcsearch.Text)
				end)
			end
		end
		populate_pc_shapes("")
		pcsearch:GetPropertyChangedSignal("Text"):Connect(function()
			populate_pc_shapes(pcsearch.Text)
		end)

		-- The per-part physics fields the System loop already reads (pc_phys.k10,
		-- .Damping, .k8, .MaxSpeed) had no way of being set from anywhere: the
		-- plumbing was there and nothing ever filled it in. Negative means inherit
		-- the global value, which is what the loop's `d.pc_phys and ...` guards
		-- express as nil -- stored as a number because the settings file round-trip
		-- drops nils and the slider needs a position to sit at.
		local INHERIT_HINT = "Below zero inherits the global setting."

		local function pc_phys_table()
			local function pick(v)
				v = tonumber(v)
				-- Any negative reads as inherit, not just exactly -1: the slider snaps
				-- in tenths, so -0.9 is reachable on the two float ranges.
				if not v or v ~= v or v < 0 then
					return nil
				end
				return v
			end
			return {
				k10 = pick(x1.PartCtlPull),
				Damping = pick(x1.PartCtlDamping),
				k8 = pick(x1.PartCtlSmoothing),
				MaxSpeed = pick(x1.PartCtlMaxSpeed),
			}
		end

		local phys_body, refresh_phys_head = collapsible("Physics Override", false, function()
			local t = pc_phys_table()
			-- The head has to distinguish "all four inherit" from "something is
			-- overridden here", which is the only reason to open the section -- and
			-- naming the fields saves opening it to find out which.
			local names = {}
			if t.k10 then names[#names + 1] = "pull" end
			if t.Damping then names[#names + 1] = "damp" end
			if t.k8 then names[#names + 1] = "smooth" end
			if t.MaxSpeed then names[#names + 1] = "speed" end
			if #names == 0 then
				return "inherit"
			end
			return table.concat(names, ", ")
		end)

		-- Committing a slider applies it to whatever is selected, rather than storing a
		-- number that does nothing until a button is tapped -- which is what made these
		-- four look broken. The button stays, because it is how the same values reach a
		-- selection made afterwards.
		local function apply_phys_live()
			refresh_phys_head()
			if x6.pc_set_phys and pc_selection() > 0 then
				x6.pc_set_phys(pc_phys_table())
			end
		end

		pc_slider("PartCtlPull", phys_body, "Pull Strength", -1, 200, tonumber(x1.PartCtlPull) or -1, function(v)
			x1.PartCtlPull = v
			apply_phys_live()
		end, false, INHERIT_HINT)
		pc_slider("PartCtlDamping", phys_body, "Damping", -1, 5, tonumber(x1.PartCtlDamping) or -1, function(v)
			x1.PartCtlDamping = v
			apply_phys_live()
		end, false, INHERIT_HINT)
		pc_slider("PartCtlSmoothing", phys_body, "Smoothing", -1, 1, tonumber(x1.PartCtlSmoothing) or -1, function(v)
			x1.PartCtlSmoothing = v
			apply_phys_live()
		end, false, INHERIT_HINT)
		pc_slider("PartCtlMaxSpeed", phys_body, "Max Speed", -1, 2000, tonumber(x1.PartCtlMaxSpeed) or -1, function(v)
			x1.PartCtlMaxSpeed = v
			apply_phys_live()
		end, false, INHERIT_HINT)

		eb(phys_body, "Apply Physics To Selection", function()
			if x6.pc_set_phys then
				local n = x6.pc_set_phys(pc_phys_table())
				if n == 0 then
					pc_notify("Part Control", "Select a part first.", 2)
				else
					pc_notify("Part Control", ("Physics applied to %d part%s"):format(n, n == 1 and "" or "s"))
				end
			end
			save_settings()
		end)

		eb(phys_body, "Clear Physics Override", function()
			if x6.pc_set_phys then
				x6.pc_set_phys(nil)
			end
		end)

		eh(pcc, "Options")

		pc_toggle("PartCtlRide", pcc, "Rideable", x1.PartCtlRide == true, function(v)
			x1.PartCtlRide = v
			-- pc_set_ride, not pc_assign. Riding is a property of the part, and routing
			-- it through the mode meant this did nothing at all while the mode was
			-- "normal" and re-assigned the mode -- shape module refcount and all -- on
			-- the other three.
			if x6.pc_set_ride then
				x6.pc_set_ride(v)
			end
			save_settings()
		end, "Makes selected parts solid and standable.")

		pc_toggle("PartCtlSurfaceSnap", pcc, "Surface Snap", x1.PartCtlSurfaceSnap ~= false, function(v)
			x1.PartCtlSurfaceSnap = v
			save_settings()
		end, "Drops a dragged part onto whatever you point at. Off slides it along a fixed distance from the camera, which is what a drag used to do.")

		pc_slider("PartCtlGridSnap", pcc, "Grid Snap", 0, 16, tonumber(x1.PartCtlGridSnap) or 0, function(v)
			x1.PartCtlGridSnap = v
		end, false, "Rounds a drag onto a stud grid. 0 is off.")

		pc_toggle("PartCtlMultiSelect", pcc, "Multi-Select Mode", x1.PartCtlMultiSelect == true, function(v)
			x1.PartCtlMultiSelect = v
			save_settings()
		end, "Tapping a part adds it to the selection, or removes it if already in.")

		pc_toggle("PartCtlEnabled", pcc, "Stay Armed When Closed", x1.PartCtlEnabled == true, function(v)
			x1.PartCtlEnabled = v
			save_settings()
		end, "Keeps tap-to-select and drag working after this panel is closed.")

		-- Unhooks itself once the panel is gone. The hook is held by x6, which
		-- outlives a UI teardown, so a rebuilt panel would otherwise leave the old
		-- closure pinning a destroyed CanvasGroup and every control under it.
		local function refresh_partctl()
			if not pcm.Parent then
				if x6.pc_on_change == refresh_partctl then
					x6.pc_on_change = nil
				end
				return
			end
			for _, sync in ipairs(pc_sync) do sync() end
			refresh_counts()
			refresh_modes()
			refresh_shape_head()
			refresh_phys_head()
		end
		refresh_partctl()
		x5.refresh_partctl = refresh_partctl
		-- And the other mixed-class list: this panel holds headings and hints
		-- (TextLabels), mode rows and folding sections (Frames) and its buttons, so by
		-- name its headings and hints sorted to the bottom too. Its rows are built once,
		-- above, so this runs once here -- refresh_partctl only repaints what exists.
		order_children(pcc, pccl)
		-- Published for System_partctl: selecting, assigning and releasing all run
		-- from input handlers that know nothing about the panel, and this is what
		-- makes the count and the active-mode marker live rather than a snapshot
		-- taken when the window happened to open.
		x6.pc_on_change = refresh_partctl


		local ab = eb(c, "Advanced Settings", function()
			open_side_panel(am, not am.Visible)
		end)
		ab.Size = UDim2.new(1, 0, 0, 20)

		local pcb = eb(c, "Part Control", function()
			local opening = not pcm.Visible
			open_side_panel(pcm, opening)
			-- Arming follows the panel, the same way the Sculptor's handlers follow
			-- x1.k6. PartCtlEnabled keeps them armed past a close. The close paths all
			-- run through the on_close registered above; this is the open one.
			x6.pc_active = opening
			if opening and x5.refresh_partctl then
				x5.refresh_partctl()
			end
		end)
		pcb.Size = UDim2.new(1, 0, 0, 20)

		local ai_btn = eb(c, "PROJECT UAI", function()
			if ai_loading then return end
			ai_loading = true
			local ok, err = pcall(function()
				loadstring(game:HttpGet("https://raw.githubusercontent.com/CarlDV/ProjectUAI/main/dist/uai.lua"))({ gravity = context })
			end)
			ai_loading = false
			if not ok then
				warn("Project Gravity: failed to launch Project UAI: " .. tostring(err))
				pcall(function()
					v5:SetCore("SendNotification", {
						Title = "Project UAI", Text = "Could not launch AI. Please try again.", Duration = 5,
					})
				end)
			end
		end)
		ai_btn.Size = UDim2.new(1, 0, 0, 20)

		local dcb = eb(c, "Join Discord Server", function()
			pcall(function()
				if setclipboard then
					setclipboard("https://discord.gg/9xYyyYuKap")
				elseif toclipboard then
					toclipboard("https://discord.gg/9xYyyYuKap")
				end
			end)
			pcall(function()
				v5:SetCore("SendNotification", { Title = "Discord", Text = "Invite link copied to clipboard!", Duration = 3 })
			end)
		end)
		dcb.Size = UDim2.new(1, 0, 0, 20)

		local mode_f = Instance.new("Frame", c)
		mode_f.BackgroundTransparency = 1
		mode_f.Size = UDim2.new(1, 0, 0, 24)
		local db = Instance.new("TextButton", mode_f)
		db.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
		db.Size = UDim2.new(1, 0, 1, 0)
		db.Text = "  " .. x1.k6:upper()
		db.TextColor3 = Color3.fromRGB(255, 255, 255)
		db.Font = Enum.Font.GothamBold
		db.TextSize = 9
		db.TextXAlignment = 0
		Instance.new("UICorner", db).CornerRadius = UDim.new(0, 6)
		local dst = Instance.new("UIStroke", db)
		dst.Color = Color3.fromRGB(40, 40, 45)

		-- The two dropdown buttons were the only large controls in the tree with no
		-- feedback at all, which read as them not being buttons.
		row_hover(
			db,
			Color3.fromRGB(25, 25, 30),
			Color3.fromRGB(35, 35, 40),
			dst,
			Color3.fromRGB(40, 40, 45),
			Color3.fromRGB(70, 70, 78)
		)
		UI_elements.press(db, 0.99)

		local arr = Instance.new("TextLabel", db)
		arr.BackgroundTransparency = 1
		arr.Position = UDim2.new(1, -30, 0, 0)
		arr.Size = UDim2.new(0, 30, 1, 0)
		arr.Text = "▼"
		arr.TextColor3 = Color3.fromRGB(150, 150, 160)
		arr.TextSize = 10

		db.MouseButton1Click:Connect(function()
			if x6.dlst_container then
				local new_state = not x6.dlst_container.Visible
				if x6.tdlst_container and x6.tdlst_container.Visible then
					toggle_window(x6.tdlst_container, false)
				end
				toggle_window(x6.dlst_container, new_state)
				if new_state and x6.populate_modes then
					x6.populate_modes("")
				end
			end
		end)

		local gsc = Instance.new("Frame", c)
		gsc.BackgroundTransparency = 1
		gsc.Size = UDim2.new(1, 0, 0, 0)
		gsc.AutomaticSize = Enum.AutomaticSize.Y
		local gscl = Instance.new("UIListLayout", gsc)
		gscl.Padding = UDim.new(0, 8)
		gscl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local sc = Instance.new("Frame", c)
		sc.BackgroundTransparency = 1
		sc.Size = UDim2.new(1, 0, 0, 0)
		sc.AutomaticSize = Enum.AutomaticSize.Y
		local scl = Instance.new("UIListLayout", sc)
		scl.Padding = UDim.new(0, 8)
		scl.HorizontalAlignment = Enum.HorizontalAlignment.Center

		local function f1()
			if x6.f1_connections then
				for _, conn in ipairs(x6.f1_connections) do
					if conn then conn:Disconnect() end
				end
				table.clear(x6.f1_connections)
			else
				x6.f1_connections = {}
			end
			sc:ClearAllChildren()
			gsc:ClearAllChildren()
			local gscl = Instance.new("UIListLayout", gsc)
			gscl.Padding = UDim.new(0, 10)
			gscl.HorizontalAlignment = Enum.HorizontalAlignment.Center
			local scl = Instance.new("UIListLayout", sc)
			scl.Padding = UDim.new(0, 8)
			scl.HorizontalAlignment = Enum.HorizontalAlignment.Center
			local s = x1.S[x1.k6] or {}


			et(gsc, "Show HUD", x1.ShowHUD ~= false, function(v)
				x1.ShowHUD = v
				if hud then hud.Visible = v end
				save_settings()
			end)

			et(gsc, "Anchor to Self", x1.AnchorSelf, function(v)
				x1.AnchorSelf = v
				if v then
					x1.PI_All = false
					table.clear(x1.Targets)
					x1.TgtActive = false
					if x5.up then x5.up() end
				end
				save_settings()
			end)

			-- The writer for a flag this tree only ever read. SimpleMode round-trips
			-- through the shared settings file, so turning it on from desktop hid
			-- Anti-Fling, Force Smooth, Realistic Liftoff, Target Everyone and the
			-- whole per-shape control block here with no way to turn it back off --
			-- a full RESET ALL SETTINGS was the only escape. Left outside the
			-- SimpleMode gate below on purpose: a toggle you cannot reach is the bug.
			et(gsc, "Simplified Interface", x1.SimpleMode, function(v)
				x1.SimpleMode = v
				save_settings()
				f1()
			end, "Hides the advanced toggles and the per-shape controls.")

			-- The touch stand-in for holding Shift in the sculptor. Read by
			-- System_sculptor on this tree and written nowhere, so tapping could never
			-- deselect a part or add to a selection.
			et(gsc, "Sculptor · Add on Tap", x1.SculptorMultiSelect == true, function(v)
				x1.SculptorMultiSelect = v
				save_settings()
			end, "Tapping adds to the selection instead of replacing it.")

			if not x1.SimpleMode then
				et(gsc, "Anti-Fling", x1.AntiFling, function(v)
					x1.AntiFling = v
					save_settings()
				end)
				et(gsc, "Force Smooth (Lags)", x1["Force Smooth (Lags)"], function(v)
					x1["Force Smooth (Lags)"] = v
					save_settings()
				end, "Updates every part every frame without smoothing delays. Your Damping setting still applies.")
				et(gsc, "Max Fidelity (Every Frame)", x1.MaxFidelity, function(v)
					x1.MaxFidelity = v
					save_settings()
				end, "Force Smooth, plus no part skipping, no distance culling, no cached ownership and no strided shape layout. The heaviest option there is.")
				et(gsc, "Realistic Liftoff", x1["Realistic Liftoff"], function(v)
					x1["Realistic Liftoff"] = v
					save_settings()
				end)
				et(gsc, "Hide Core While Paused", x1.HideCoreOnPause == true, function(v)
					x1.HideCoreOnPause = v
					-- Repaint immediately: the toggle is usually flipped while already
					-- paused, and nothing else would touch the marker until the next
					-- pause or disable.
					if context.x4 and context.x4.refresh_core_visual then
						context.x4.refresh_core_visual()
					end
					save_settings()
				end, "Hides the core marker while paused. It stays draggable, like it does while disabled.")
			end

			x6.disable_btn = et(gsc, "Disable Gravity", x1.Disabled, function(v)
				-- System owns the switch: parts get their collision back and stop
				-- being driven while disabled, and both are undone on enable. Doing
				-- it here as well would only be a second, partial copy.
				if context.x4 and context.x4.apply_disabled then
					context.x4.apply_disabled(v)
				else
					x1.Disabled = v
				end
				if x6.dock_disable_btn then
					x6.dock_disable_btn.BackgroundColor3 = v and Color3.fromRGB(100, 255, 100)
						or Color3.fromRGB(60, 60, 60)
				end
				save_settings()
			end)

			if not x1.SimpleMode then
				et(gsc, "Target Everyone", x1.PI_All, function(v)
					x1.PI_All = v
					if v then
						x1.AnchorSelf = false
						table.clear(x1.Targets)
						x1.TgtActive = false
						if x5.up then x5.up() end
					end
					save_settings()
				end)
			end

			local l_btn = Instance.new("TextButton", gsc)
			l_btn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
			l_btn.Size = UDim2.new(1, 0, 0, 20)
			l_btn.Text = "FORCE LAUNCH"
			l_btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			l_btn.Font = Enum.Font.GothamBold
			l_btn.TextSize = 9
			Instance.new("UICorner", l_btn).CornerRadius = UDim.new(0, 6)
			-- == true, not the bare value: Visible rejects nil, and an unset
			-- SlingshotManual made this nil whenever Slingshot was the live shape,
			-- which threw here and abandoned the rest of f1.
			l_btn.Visible = x1.k6 == "Slingshot" and x1.SlingshotManual == true

			l_btn.MouseButton1Click:Connect(function()
				x1.IsLaunching = not x1.IsLaunching
				l_btn.Text = x1.IsLaunching and "RESET SYSTEM" or "FORCE LAUNCH"
				l_btn.BackgroundColor3 = x1.IsLaunching and Color3.fromRGB(50, 150, 200) or Color3.fromRGB(200, 50, 50)
			end)

			table.insert(
				x6.f1_connections,
				v3.Heartbeat:Connect(function()
					if x1.k6 == "Slingshot" and x1.SlingshotManual == true then
						l_btn.Visible = true
						l_btn.Text = x1.IsLaunching and "RESET SYSTEM" or "FORCE LAUNCH"
						l_btn.BackgroundColor3 = x1.IsLaunching and Color3.fromRGB(50, 150, 200)
							or Color3.fromRGB(200, 50, 50)
					else
						l_btn.Visible = false
					end
				end)
			)

			local tn = "Select Target"
			if x1.Targets and #x1.Targets > 0 then
				if #x1.Targets == 1 then
					tn = "Target: " .. (x1.Targets[1].DisplayName or x1.Targets[1].Name)
				else
					tn = "Multi-Target (" .. tostring(#x1.Targets) .. ")"
				end
			end

			et(gsc, "Preserve Collisions", x1.PreserveCollisions, function(v)
				x1.PreserveCollisions = v
				x6.refresh_collisions()
				save_settings()
			end)

			local tdb = Instance.new("TextButton", gsc)
			tdb.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
			tdb.Size = UDim2.new(1, 0, 0, 22)
			tdb.Text = "  " .. tn:upper()
			tdb.TextColor3 = Color3.fromRGB(255, 255, 255)
			tdb.Font = Enum.Font.GothamBold
			tdb.TextSize = 8
			tdb.TextXAlignment = 0
			Instance.new("UICorner", tdb).CornerRadius = UDim.new(0, 6)
			local dst2 = Instance.new("UIStroke", tdb)
			dst2.Color = Color3.fromRGB(40, 40, 45)

			row_hover(
				tdb,
				Color3.fromRGB(25, 25, 30),
				Color3.fromRGB(35, 35, 40),
				dst2,
				Color3.fromRGB(40, 40, 45),
				Color3.fromRGB(70, 70, 78)
			)
			UI_elements.press(tdb, 0.99)

			if x1.Targets and #x1.Targets > 0 then
				local ctb = Instance.new("TextButton", tdb)
				ctb.BackgroundTransparency = 1
				ctb.Position = UDim2.new(1, -25, 0, 0)
				ctb.Size = UDim2.new(0, 25, 1, 0)
				ctb.Text = "×"
				ctb.TextColor3 = Color3.fromRGB(200, 80, 80)
				ctb.TextSize = 16
				ctb.MouseButton1Click:Connect(function()
					table.clear(x1.Targets)
					x1.TgtActive = false
					f1()
				end)
			end

			tdb.MouseButton1Click:Connect(function()
				if x6.tdlst_container then
					local new_state = not x6.tdlst_container.Visible
					if x6.dlst_container and x6.dlst_container.Visible then
						toggle_window(x6.dlst_container, false)
					end
					toggle_window(x6.tdlst_container, new_state)
					if new_state and x6.update_targets then
						x6.update_targets("")
					end
				end
			end)

			if not x1.SimpleMode then
				local shape_name = x1.k6
				local shape_mod = get_shape(shape_name)
				if x6.torn_down then return end
				if shape_mod and shape_mod.Controls then
					for _, ctrl in ipairs(shape_mod.Controls) do
						local current_val = s[ctrl.Key]
						local p_frame = ctrl.Parent == "gsc" and gsc or sc
						if ctrl.Type == "Button" then
							local button = eb(p_frame, ctrl.Name, function()
								if x6.torn_down or x1.k6 ~= shape_name then return end
								local ok, err = PluginControls.activate(ctrl, x2[shape_name] or s, x6, x1)
								if not ok then
									warn("Project Gravity: " .. tostring(err))
									if context.x8 then context.x8.notify("Shape action", tostring(err), 4) end
								end
							end)
							button.Name = ctrl.Key or ctrl.Name
							button.Size = UDim2.new(1, 0, 0, 44)
						elseif ctrl.Type == "Slider" then
							if ctrl.LegacyToggle and type(current_val) == "boolean" then
								current_val = current_val and 2 or 1
								s[ctrl.Key] = current_val
							end
							if current_val == nil then
								if ctrl.Default ~= nil then
									current_val = ctrl.Default
								else
									current_val = ctrl.Min
								end
							end
							local max_val = ctrl.Max
							if string.find(ctrl.Name:lower(), "speed") and not ctrl.ExactMax then
								max_val = max_val + 300
							end
							if ctrl.Div then current_val = current_val * ctrl.Div end
							current_val = math.clamp(current_val, ctrl.Min, max_val)
							s[ctrl.Key] = ctrl.Div and (current_val / ctrl.Div) or current_val
							es(p_frame, ctrl.Name, ctrl.Min, max_val, current_val, function(v)
								if ctrl.Div then s[ctrl.Key] = v / ctrl.Div else s[ctrl.Key] = v end
							end, ctrl.IntOnly, ctrl.Desc)
						elseif ctrl.Type == "Toggle" then
							if type(current_val) ~= "boolean" then
								current_val = ctrl.Default == true
							end
							-- Seated back into the config like the Slider and TextBox
							-- branches already do, or a Toggle whose key is missing
							-- from config.lua draws ON from its Default while the
							-- shape reads nil and behaves OFF.
							s[ctrl.Key] = current_val
							et(p_frame, ctrl.Name, current_val, function(v)
								s[ctrl.Key] = v
							end, ctrl.Desc)
						elseif ctrl.Type == "TextBox" and etb then
							if type(current_val) ~= "string" then
								current_val = type(ctrl.Default) == "string" and ctrl.Default or ""
							end
							s[ctrl.Key] = current_val
							etb(p_frame, ctrl.Name, current_val, function(v)
								s[ctrl.Key] = v
							end, ctrl.Desc, ctrl.MaxChars)
						end
					end
				end
			end

			local reset_btn = Instance.new("TextButton", sc)
			reset_btn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
			reset_btn.Size = UDim2.new(1, 0, 0, 24)
			reset_btn.Text = "⚠ RESET ALL SETTINGS"
			reset_btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			reset_btn.Font = Enum.Font.GothamBold
			reset_btn.TextSize = 9
			reset_btn.AutoButtonColor = false
			Instance.new("UICorner", reset_btn).CornerRadius = UDim.new(0, 6)
			local reset_stroke = Instance.new("UIStroke", reset_btn)
			reset_stroke.Color = Color3.fromRGB(255, 80, 80)
			reset_stroke.Thickness = 1

			row_hover(
				reset_btn,
				Color3.fromRGB(180, 40, 40),
				Color3.fromRGB(220, 50, 50),
				reset_stroke,
				Color3.fromRGB(255, 80, 80),
				Color3.fromRGB(255, 120, 120)
			)
			UI_elements.press(reset_btn)

			reset_btn.MouseButton1Click:Connect(function()
				if x6.reset_confirm then
					x6.reset_confirm:Destroy()
					x6.reset_confirm = nil
				end

				local confirm = Instance.new("CanvasGroup", sg)
				confirm.Name = "ResetConfirm"
				confirm.BackgroundColor3 = Color3.fromRGB(12, 12, 15)
				confirm.Position = UDim2.new(0.5, -100, 0.5, -60)
				confirm.Size = UDim2.new(0, 200, 0, 120)
				confirm.GroupTransparency = 1
				confirm.ZIndex = 100
				Instance.new("UICorner", confirm).CornerRadius = UDim.new(0, 12)
				local confirm_stroke = Instance.new("UIStroke", confirm)
				confirm_stroke.Color = Color3.fromRGB(120, 40, 40)
				confirm_stroke.Thickness = 1
				local warning_icon = Instance.new("TextLabel", confirm)
				warning_icon.Position = UDim2.new(0.5, -10, 0, 10)
				warning_icon.Size = UDim2.new(0, 20, 0, 20)
				warning_icon.Text = "⚠"
				warning_icon.TextColor3 = Color3.fromRGB(255, 100, 100)
				warning_icon.TextSize = 16
				warning_icon.ZIndex = 101

				local confirm_title = Instance.new("TextLabel", confirm)
				confirm_title.BackgroundTransparency = 1
				confirm_title.Position = UDim2.new(0, 10, 0, 35)
				confirm_title.Size = UDim2.new(1, -20, 0, 20)
				confirm_title.Text = "RESET ALL SETTINGS?"
				confirm_title.TextColor3 = Color3.fromRGB(255, 255, 255)
				confirm_title.Font = Enum.Font.GothamBold
				confirm_title.TextSize = 10
				confirm_title.ZIndex = 101

				local confirm_desc = Instance.new("TextLabel", confirm)
				confirm_desc.BackgroundTransparency = 1
				confirm_desc.Position = UDim2.new(0, 10, 0, 55)
				confirm_desc.Size = UDim2.new(1, -20, 0, 30)
				confirm_desc.Text = "This will reset all settings to default. This cannot be undone."
				confirm_desc.TextColor3 = Color3.fromRGB(150, 150, 160)
				confirm_desc.Font = Enum.Font.Gotham
				confirm_desc.TextSize = 8
				confirm_desc.TextWrapped = true
				confirm_desc.ZIndex = 101

				local cancel_btn = Instance.new("TextButton", confirm)
				cancel_btn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
				cancel_btn.Position = UDim2.new(0, 10, 1, -30)
				cancel_btn.Size = UDim2.new(0.5, -15, 0, 20)
				cancel_btn.Text = "CANCEL"
				cancel_btn.TextColor3 = Color3.fromRGB(200, 200, 210)
				cancel_btn.Font = Enum.Font.GothamBold
				cancel_btn.TextSize = 8
				cancel_btn.AutoButtonColor = false
				cancel_btn.ZIndex = 101
				Instance.new("UICorner", cancel_btn).CornerRadius = UDim.new(0, 4)

				local confirm_reset_btn = Instance.new("TextButton", confirm)
				confirm_reset_btn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
				confirm_reset_btn.Position = UDim2.new(0.5, 5, 1, -30)
				confirm_reset_btn.Size = UDim2.new(0.5, -15, 0, 20)
				confirm_reset_btn.Text = "RESET"
				confirm_reset_btn.TextColor3 = Color3.fromRGB(255, 255, 255)
				confirm_reset_btn.Font = Enum.Font.GothamBold
				confirm_reset_btn.TextSize = 8
				confirm_reset_btn.AutoButtonColor = false
				confirm_reset_btn.ZIndex = 101
				Instance.new("UICorner", confirm_reset_btn).CornerRadius = UDim.new(0, 4)
				local confirm_reset_stroke = Instance.new("UIStroke", confirm_reset_btn)
				confirm_reset_stroke.Color = Color3.fromRGB(120, 30, 30)

				-- Both buttons dismiss the same way, and the destroy has to wait out
				-- the fade -- so the delay is read off the curve rather than
				-- repeating its duration as a literal that drifts when A.CLOSE
				-- changes.
				local function dismiss_confirm()
					v6:Create(confirm, A.CLOSE, { GroupTransparency = 1 }):Play()
					set_pop(confirm, 0.9, A.CLOSE_POP)
					task.delay(A.CLOSE.Time, function()
						if confirm.Parent then confirm:Destroy() end
						if x6.reset_confirm == confirm then x6.reset_confirm = nil end
					end)
				end

				cancel_btn.MouseButton1Click:Connect(dismiss_confirm)

				confirm_reset_btn.MouseButton1Click:Connect(function()
					context.controls.reset()
					dismiss_confirm()
				end)

				x6.reset_confirm = confirm

				-- Registered like every other window so it opens at the user's
				-- scale instead of always at 1. AnchorPoint moves to the middle
				-- because a UIScale grows a frame from its top-left corner.
				confirm.AnchorPoint = Vector2.new(0.5, 0.5)
				confirm.Position = UDim2.new(0.5, 0, 0.5, 0)
				register_window(confirm, 0.9)
				-- Split the way every other window opens: the fade rides OPEN
				-- because transparency has no momentum to overshoot -- Back on it
				-- just drives the value past 0 where it clamps and stalls -- while
				-- the scale gets OPEN_POP, which is where the spring belongs.
				v6:Create(confirm, A.OPEN, { GroupTransparency = 0 }):Play()
				set_pop(confirm, 1, A.OPEN_POP)
			end)
		end
		x5.up = f1

		local dlst_container = Instance.new("CanvasGroup", sg)
		dlst_container.Name = "ModeSelector"
		dlst_container.Visible = false
		dlst_container.GroupTransparency = 1
		dlst_container.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
		dlst_container.Position = UDim2.new(0.5, 90, 0.5, -160)
		dlst_container.Size = UDim2.new(0, 180, 0, 250)
		dlst_container.Active = true
		Instance.new("UICorner", dlst_container).CornerRadius = UDim.new(0, 10)
		local dls = Instance.new("UIStroke", dlst_container)
		dls.Color = Color3.fromRGB(40, 40, 45)

		-- Starts hidden, so it starts at the closed pop factor.
		register_window(dlst_container, 0.8)

		local top_dlst = Instance.new("Frame", dlst_container)
		top_dlst.BackgroundTransparency = 1
		top_dlst.Size = UDim2.new(1, 0, 0, 30)
		top_dlst.ZIndex = 11
		-- The Back button sits inside this bar and consumes its own input, so it
		-- still clicks rather than starting a drag.
		make_draggable(dlst_container, top_dlst)

		local back_dlst = Instance.new("TextButton", top_dlst)
		back_dlst.BackgroundTransparency = 1
		back_dlst.Position = UDim2.new(0, 10, 0, 5)
		back_dlst.Size = UDim2.new(0, 50, 0, 30)
		back_dlst.Text = "◄ Back"
		back_dlst.TextColor3 = Color3.fromRGB(150, 150, 155)
		back_dlst.Font = Enum.Font.GothamBold
		back_dlst.TextSize = 12
		back_dlst.ZIndex = 12
		back_dlst.MouseButton1Click:Connect(function()
			toggle_window(dlst_container, false)
		end)

		local msb = Instance.new("TextBox", dlst_container)
		msb.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		msb.Position = UDim2.new(0, 10, 0, 35)
		msb.Size = UDim2.new(1, -20, 0, 20)
		msb.PlaceholderText = "Search modes..."
		msb.Text = ""
		msb.TextColor3 = Color3.fromRGB(255, 255, 255)
		msb.Font = Enum.Font.Gotham
		msb.TextSize = 9
		msb.ZIndex = 11
		Instance.new("UICorner", msb).CornerRadius = UDim.new(0, 6)

		local dlst = Instance.new("ScrollingFrame", dlst_container)
		dlst.BackgroundTransparency = 1
		dlst.Position = UDim2.new(0, 0, 0, 70)
		dlst.Size = UDim2.new(1, 0, 1, -80)
		dlst.ScrollBarThickness = 0
		dlst.AutomaticCanvasSize = Enum.AutomaticSize.Y
		dlst.CanvasSize = UDim2.new(0, 0, 0, 0)
		dlst.ZIndex = 11

		x6.dlst_container = dlst_container

		local function populate_modes(filter)
			dlst:ClearAllChildren()
			local dll = Instance.new("UIListLayout", dlst)
			dll.Padding = UDim.new(0, 5)
			dll.HorizontalAlignment = Enum.HorizontalAlignment.Center

			local modes = {}
			for mn, _ in pairs(x2) do
				table.insert(modes, mn)
			end

			table.sort(modes, function(a, b)
				local fa, fb = favorites[a] and 1 or 0, favorites[b] and 1 or 0
				if fa ~= fb then
					return fa > fb
				end
				return a < b
			end)

			for _, mn in ipairs(modes) do
				-- Plain search: without the flag the typed text is a Lua pattern, so a
				-- single "(" throws out of the Text callback after ClearAllChildren
				-- has already run, leaving the list permanently empty.
				if filter ~= "" and not mn:lower():find(filter:lower(), 1, true) then
					continue
				end

				local f = Instance.new("Frame", dlst)
				f.Size = UDim2.new(1, -16, 0, 24)
				local row_on = mn == x1.k6
				f.BackgroundColor3 = row_on and Color3.fromRGB(40, 40, 180) or Color3.fromRGB(25, 25, 30)
				f.ZIndex = 12
				Instance.new("UICorner", f).CornerRadius = UDim.new(0, 4)
				-- idle passed in rather than read back, so the selected row keeps its tint
				-- when the pointer leaves.
				row_hover(
					f,
					f.BackgroundColor3,
					row_on and Color3.fromRGB(55, 55, 200) or Color3.fromRGB(35, 35, 40)
				)

				local ib = Instance.new("TextButton", f)
				ib.Size = UDim2.new(1, -40, 1, 0)
				ib.Position = UDim2.new(0, 8, 0, 0)
				ib.BackgroundTransparency = 1
				ib.Text = "  " .. mn
				ib.TextColor3 = Color3.fromRGB(255, 255, 255)
				ib.Font = Enum.Font.GothamBold
				ib.TextSize = 9
				ib.TextXAlignment = 0
				ib.ZIndex = 13

				local sb = Instance.new("TextButton", f)
				sb.Position = UDim2.new(1, -35, 0, 0)
				sb.Size = UDim2.new(0, 35, 1, 0)
				sb.BackgroundTransparency = 1
				sb.Text = favorites[mn] and "★" or "☆"
				sb.TextColor3 = favorites[mn] and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(80, 80, 85)
				sb.Font = Enum.Font.GothamBold
				sb.TextSize = 12
				sb.ZIndex = 13

				sb.MouseButton1Click:Connect(function()
					favorites[mn] = not favorites[mn]
					save_favs()
					populate_modes(filter)
				end)

				ib.MouseButton1Click:Connect(function()
					local shape = get_shape(mn)
					if shape then
						-- This tree has no switch_shape at all, so the testing notice has
						-- to live here. context.x8 is populated after this module is built
						-- (main.lua:565) but long before any click, so it resolves at call
						-- time rather than at build time.
						if shape.Testing and context.x8 and context.x8.notify then
							context.x8.notify("Testing", mn .. " is still in testing.", 4)
						end
						x1.k6 = mn
						x6.transition_time = time()
						x6.transition_dur = 1.5
						for _, d in pairs(x6.a) do
							d.trans_vl = d.vl or Vector3.zero
							d.v1, d.v2, d.v3, d.v4, d.v5, d.v6, d.v7, d.v8, d.v9 = nil, nil, nil, nil, nil, nil, nil, nil, nil
							d.integral = Vector3.zero
						end
						if db then
							db.Text = "  " .. mn:upper()
						end
						toggle_window(dlst_container, false)
						save_settings()
						if x5.up then
							x5.up()
						end
					end
				end)
			end
		end

		msb:GetPropertyChangedSignal("Text"):Connect(function()
			populate_modes(msb.Text)
		end)

		x6.populate_modes = populate_modes
		populate_modes("")

		local tdlst = Instance.new("CanvasGroup", sg)
		tdlst.Name = "TargetListContainer"
		tdlst.Visible = false
		tdlst.GroupTransparency = 1
		tdlst.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
		tdlst.Position = UDim2.new(0.5, 90, 0.5, -160)
		tdlst.Size = UDim2.new(0, 180, 0, 250)
		tdlst.Active = true
		x6.tdlst_container = tdlst
		Instance.new("UICorner", tdlst).CornerRadius = UDim.new(0, 10)
		local ts = Instance.new("UIStroke", tdlst)
		ts.Color = Color3.fromRGB(40, 40, 45)

		register_window(tdlst, 0.8)

		local top_tdlst = Instance.new("Frame", tdlst)
		top_tdlst.BackgroundTransparency = 1
		top_tdlst.Size = UDim2.new(1, 0, 0, 30)
		top_tdlst.ZIndex = 11
		make_draggable(tdlst, top_tdlst)

		local back_tdlst = Instance.new("TextButton", top_tdlst)
		back_tdlst.BackgroundTransparency = 1
		back_tdlst.Position = UDim2.new(0, 10, 0, 5)
		back_tdlst.Size = UDim2.new(0, 50, 0, 30)
		back_tdlst.Text = "◄ Back"
		back_tdlst.TextColor3 = Color3.fromRGB(150, 150, 155)
		back_tdlst.Font = Enum.Font.GothamBold
		back_tdlst.TextSize = 12
		back_tdlst.ZIndex = 12
		back_tdlst.MouseButton1Click:Connect(function()
			toggle_window(tdlst, false)
		end)

		local target_search = Instance.new("TextBox", tdlst)
		target_search.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		target_search.Position = UDim2.new(0, 10, 0, 35)
		target_search.Size = UDim2.new(1, -20, 0, 20)
		target_search.PlaceholderText = "Search players..."
		target_search.Text = ""
		target_search.TextColor3 = Color3.fromRGB(255, 255, 255)
		target_search.Font = Enum.Font.Gotham
		target_search.TextSize = 9
		target_search.ZIndex = 11
		Instance.new("UICorner", target_search).CornerRadius = UDim.new(0, 6)

		local t_scroll = Instance.new("ScrollingFrame", tdlst)
		t_scroll.BackgroundTransparency = 1
		t_scroll.Position = UDim2.new(0, 0, 0, 70)
		t_scroll.Size = UDim2.new(1, 0, 1, -80)
		t_scroll.ScrollBarThickness = 0
		t_scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		t_scroll.ZIndex = 11

		local active_highlight = nil
		local function clear_highlight()
			if active_highlight then
				active_highlight:Destroy()
				active_highlight = nil
			end
		end

		local function update_targets(filter_text)
			clear_highlight()
			t_scroll:ClearAllChildren()
			local tdll = Instance.new("UIListLayout", t_scroll)
			tdll.Padding = UDim.new(0, 5)
			tdll.HorizontalAlignment = Enum.HorizontalAlignment.Center

			for _, pl in ipairs(v2:GetPlayers()) do
				if pl == v8 then continue end
				if filter_text ~= "" and not (pl.DisplayName:lower():find(filter_text:lower(), 1, true) or pl.Name:lower():find(filter_text:lower(), 1, true)) then
					continue
				end

				local ib = Instance.new("TextButton", t_scroll)
				ib.Size = UDim2.new(1, -16, 0, 36)
				ib.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
				ib.Text = ""
				ib.AutoButtonColor = false
				ib.ZIndex = 12
				Instance.new("UICorner", ib).CornerRadius = UDim.new(0, 6)
				
				local is_selected = table.find(x1.Targets, pl) ~= nil
				local sel_indicator = Instance.new("Frame", ib)
				sel_indicator.Position = UDim2.new(1, -20, 0.5, -5)
				sel_indicator.Size = UDim2.new(0, 10, 0, 10)
				sel_indicator.BackgroundColor3 = is_selected and Color3.fromRGB(60, 200, 100) or Color3.fromRGB(60, 60, 65)
				sel_indicator.ZIndex = 12
				Instance.new("UICorner", sel_indicator).CornerRadius = UDim.new(1, 0)

				local pfp = Instance.new("ImageLabel", ib)
				pfp.Size = UDim2.new(0, 26, 0, 26)
				pfp.Position = UDim2.new(0, 6, 0.5, -13)
				pfp.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
				pfp.Image = "rbxthumb://type=AvatarHeadShot&id=" .. pl.UserId .. "&w=48&h=48"
				pfp.ZIndex = 12
				Instance.new("UICorner", pfp).CornerRadius = UDim.new(1, 0)

				local dname = Instance.new("TextLabel", ib)
				dname.BackgroundTransparency = 1
				dname.Position = UDim2.new(0, 38, 0, 4)
				dname.Size = UDim2.new(1, -44, 0, 14)
				dname.Text = pl.DisplayName
				dname.TextColor3 = Color3.fromRGB(255, 255, 255)
				dname.Font = Enum.Font.GothamBold
				dname.TextSize = 10
				dname.TextXAlignment = 0
				dname.ZIndex = 12

				local uname = Instance.new("TextLabel", ib)
				uname.BackgroundTransparency = 1
				uname.Position = UDim2.new(0, 38, 0, 18)
				uname.Size = UDim2.new(1, -44, 0, 12)
				uname.Text = "@" .. pl.Name
				uname.TextColor3 = Color3.fromRGB(150, 150, 150)
				uname.Font = Enum.Font.GothamMedium
				uname.TextSize = 8
				uname.TextXAlignment = 0
				uname.ZIndex = 12

				ib.MouseEnter:Connect(function()
					-- Tweened on the shared curve, like every other row. This one set the
					-- colour outright, which read snappier than the rest of the tree in a
					-- way nobody chose.
					v6:Create(ib, A.HOVER, { BackgroundColor3 = Color3.fromRGB(35, 35, 40) }):Play()
					-- See the desktop copy: cleared first so a fast move between rows
					-- cannot orphan the previous highlight, and parented to the row so
					-- the list teardown takes it along. f1() Destroy()s this list on
					-- click and a Destroy fires no MouseLeave.
					clear_highlight()
					if pl.Character then
						local h = Instance.new("Highlight")
						h.FillColor = Color3.fromRGB(255, 255, 255)
						h.OutlineColor = Color3.fromRGB(255, 255, 255)
						h.Adornee = pl.Character
						h.Parent = ib
						active_highlight = h
					end
				end)
				ib.MouseLeave:Connect(function()
					v6:Create(ib, A.HOVER, { BackgroundColor3 = Color3.fromRGB(25, 25, 30) }):Play()
					clear_highlight()
				end)

				ib.MouseButton1Click:Connect(function()
					local idx = table.find(x1.Targets, pl)
					if idx then
						table.remove(x1.Targets, idx)
						sel_indicator.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
					else
						table.insert(x1.Targets, pl)
						sel_indicator.BackgroundColor3 = Color3.fromRGB(60, 200, 100)
						x1.AnchorSelf = false
						x1.PI_All = false
					end
					x1.TgtActive = (#x1.Targets > 0)
					if x5.up then x5.up() end
				end)
			end
		end
		x6.update_targets = update_targets

		target_search:GetPropertyChangedSignal("Text"):Connect(function()
			update_targets(target_search.Text)
		end)

		-- Declared ahead of the header buttons because their tap handlers close
		-- over it: while the panel is a pill every extra is invisible but still
		-- hit-testable, and stacked on top of minb. See set_header_extras below.
		local collapsed = false

		local minb = circle_btn(h, Color3.fromRGB(60, 200, 100), "–", 11)
		minb.Position = UDim2.new(1, -44, 0.5, -7)

		local tutb = circle_btn(h, Color3.fromRGB(50, 150, 200), "?", 10)
		tutb.Position = UDim2.new(1, -66, 0.5, -7)

		local tut_container = Instance.new("CanvasGroup", sg)
		tut_container.Name = "Tutorial"
		tut_container.Visible = false
		tut_container.GroupTransparency = 1
		tut_container.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
		tut_container.Position = UDim2.new(0.5, -100, 0.5, -120)
		tut_container.Size = UDim2.new(0, 200, 0, 240)
		tut_container.Active = true
		Instance.new("UICorner", tut_container).CornerRadius = UDim.new(0, 10)
		local tuls = Instance.new("UIStroke", tut_container)
		tuls.Color = Color3.fromRGB(40, 40, 45)

		register_window(tut_container, 0.8)

		local tut_header = Instance.new("Frame", tut_container)
		tut_header.BackgroundTransparency = 1
		tut_header.Size = UDim2.new(1, 0, 0, 30)
		make_draggable(tut_container, tut_header)
		
		local tut_title = Instance.new("TextLabel", tut_header)
		tut_title.BackgroundTransparency = 1
		tut_title.Position = UDim2.new(0, 15, 0, 0)
		tut_title.Size = UDim2.new(0.8, 0, 1, 0)
		tut_title.Text = "HOW TO USE"
		tut_title.TextColor3 = Color3.fromRGB(255, 255, 255)
		tut_title.Font = Enum.Font.GothamBlack
		tut_title.TextSize = 10
		tut_title.TextXAlignment = 0

		local tut_close = circle_btn(tut_header, Color3.fromRGB(200, 60, 60), "×", 10)
		tut_close.Position = UDim2.new(1, -22, 0.5, -7)
		tut_close.MouseButton1Click:Connect(function()
			toggle_window(tut_container, false)
		end)

		local tut_text = Instance.new("TextLabel", tut_container)
		tut_text.BackgroundTransparency = 1
		tut_text.Position = UDim2.new(0, 15, 0, 35)
		tut_text.Size = UDim2.new(1, -30, 1, -45)
		-- The two tools were missing outright, and they are the two things nobody works
		-- out from the dock alone.
		tut_text.Text = table.concat({
			"• Core: tap 'PLC' to reposition the gravitational center, 'CLN' to wipe active parts.",
			"• Targeting: use 'Select Target' to focus gravity onto a specific player.",
			"• Elevation: 'UP' and 'DWN' adjust the vertical height of the formation.",
			"• System: 'PAU' pauses physics, 'DIS' disables it without giving up the parts.",
			"• Modes: select a mode to morph between geometry. Scroll the main menu for that shape's own config.",
			"• Part Control: tap a held part to select it (selecting alone changes nothing), drag it to place it, then pick Pin, Manual or Assign Shape. The box colour is the mode.",
			"• Sculptor: pick it as the mode to arrange parts by hand.",
			"• Advanced Settings holds the global physics limits, the FPS cap and the performance switches.",
		}, "\n\n")
		tut_text.TextColor3 = Color3.fromRGB(200, 200, 205)
		tut_text.Font = Enum.Font.GothamMedium
		tut_text.TextSize = 9
		tut_text.TextXAlignment = 0
		tut_text.TextYAlignment = 0
		tut_text.TextWrapped = true

		tutb.MouseButton1Click:Connect(function()
			if collapsed then return end
			toggle_window(tut_container, not tut_container.Visible)
		end)

		local closeb = circle_btn(h, Color3.fromRGB(200, 60, 60), "×", 10)
		closeb.Name = "UnloadProjectGravity"
		closeb.Position = UDim2.new(1, -22, 0.5, -7)

		-- Minimize runs in two stages: the body rolls up into the header, then
		-- the header folds left into a round pill holding just this button.
		-- Maximize is the inverse, and the order matters -- the header has to be
		-- back at full width before the body rolls down, or the content is laid
		-- out against a 34px frame and every label wraps.
		local im = false
		-- Scroll offset held across a collapse, since the body's height goes to
		-- zero in between and the live value stops being meaningful.
		local saved_canvas = nil
		-- The stages are chained on Completed, so a second tap mid-flight would
		-- start the opposite sequence while tweens from the first are still
		-- running and leave the panel stuck at an intermediate size.
		local anim_busy = false

		local ROLL, FOLD, UNFOLD = A.ROLL, A.FOLD, A.UNFOLD

		-- collapsed (declared above the header buttons) is the authority for
		-- hit-testing, flipped the instant the button is pressed. Transparency
		-- alone would not do: a fully transparent TextButton still takes taps,
		-- and once the panel is pill-width closeb's (1,-22) anchor lands on top
		-- of minb, so a tap meant to restore would tear the UI down instead.
		local extras = { tutb, closeb }
		local function set_header_extras(hidden)
			local a = hidden and 1 or 0
			-- Deliberately not UNFOLD on the way back. UNFOLD is Back/Out, and a
			-- transparency has nowhere to overshoot to: the curve drives the value
			-- below 0, Roblox clamps it, and the fade finishes early then sits
			-- frozen for the rest of the tween instead of easing in. The geometry
			-- below still gets UNFOLD -- that is where the spring belongs.
			local info = hidden and FOLD or A.OPEN
			v6:Create(t, info, { TextTransparency = a }):Play()
			for _, b in ipairs(extras) do
				if not hidden then
					b.Visible = true
				end
				local tw = v6:Create(b, info, {
					BackgroundTransparency = a,
					TextTransparency = a,
				})
				if hidden then
					local conn
					conn = tw.Completed:Connect(function()
						if conn then conn:Disconnect() end
						-- Not if a fast re-tap already started fading them back.
						if collapsed then b.Visible = false end
					end)
				end
				tw:Play()
			end
		end

		local function fold_to_pill()
			set_header_extras(true)
			-- 0.5 is resolved against the width as it animates, so the button
			-- curves rather than sliding straight in. Endpoints are what matter.
			v6:Create(minb, FOLD, { Position = UDim2.new(0.5, -7, 0.5, -7) }):Play()
			-- h carries an absolute height, so it has to come down with the panel
			-- or minb's 0.5 anchor centres against 26px inside a 34px pill.
			v6:Create(h, FOLD, { Size = UDim2.new(1, 0, 0, PILL_SIZE) }):Play()
			v6:Create(mcorner, FOLD, { CornerRadius = UDim.new(0, PILL_SIZE / 2) }):Play()
			local tw = v6:Create(m, FOLD, { Size = UDim2.new(0, PILL_SIZE, 0, PILL_SIZE) })
			local conn
			conn = tw.Completed:Connect(function()
				if conn then conn:Disconnect() end
				anim_busy = false
			end)
			tw:Play()
		end

		local function roll_up()
			-- Clipped rather than hidden, so the body is cut off as the panel
			-- shrinks instead of vanishing a frame before the tween starts.
			m.ClipsDescendants = true
			-- Banked before the body shrinks. c is sized against m, so collapsing
			-- drives its height to zero, and a ScrollingFrame clamps CanvasPosition
			-- against its own window size -- at zero height that clamp no longer
			-- holds the offset anywhere sensible. Restoring from the stale value is
			-- what reopened the panel onto the middle of the list, or past the end
			-- of it, whenever it was minimized from anywhere but the very top.
			saved_canvas = c.CanvasPosition
			c.CanvasPosition = Vector2.new(0, 0)
			-- Every side panel, through the registry: Part Control used to be missed
			-- here, so minimizing to the pill left it floating on screen with its tap
			-- handlers still armed and no panel to disarm them from.
			for win in pairs(side_panels) do
				if win.Visible then
					close_side_panel(win)
				end
			end
			if tut_container.Visible then toggle_window(tut_container, false) end
			if x6.dlst_container and x6.dlst_container.Visible then
				toggle_window(x6.dlst_container, false)
			end
			if x6.tdlst_container and x6.tdlst_container.Visible then
				toggle_window(x6.tdlst_container, false)
			end
			-- Dismiss the reset dialog when its owning panel leaves the screen.
			if x6.reset_confirm then
				if x6.reset_confirm.Parent then
					x6.reset_confirm:Destroy()
				end
				x6.reset_confirm = nil
			end
			local tw = v6:Create(m, ROLL, { Size = UDim2.new(0, PANEL_W, 0, HEADER_H) })
			local conn
			conn = tw.Completed:Connect(function()
				if conn then conn:Disconnect() end
				if im then fold_to_pill() else anim_busy = false end
			end)
			tw:Play()
		end

		local function roll_down()
			local tw = v6:Create(m, ROLL, { Size = UDim2.new(0, PANEL_W, 0, PANEL_H) })
			local conn
			conn = tw.Completed:Connect(function()
				if conn then conn:Disconnect() end
				m.ClipsDescendants = false
				-- Put the reader back where they left off, now that the body is at
				-- full height and the clamp means something again.
				if saved_canvas then
					c.CanvasPosition = saved_canvas
					saved_canvas = nil
				end
				anim_busy = false
			end)
			tw:Play()
		end

		local function unfold_header()
			-- The pill is draggable, so it can be anywhere by now. Expanding from
			-- near an edge would put most of the panel off-screen.
			--
			-- Measured, not computed. Deriving the offset from ViewportSize is
			-- wrong twice over: sg does not set IgnoreGuiInset, so the parent is
			-- shorter than the viewport by the topbar, and the expanded panel is
			-- PANEL_* * app_scale() because UIScale grows m from its top-left.
			-- AbsolutePosition and AbsoluteSize are both post-scale and relative
			-- to the real parent, so they carry the inset and the scale already.
			local parent = m.Parent
			local avail = (parent and parent.AbsoluteSize) or Vector2.new(720, 1280)
			local scale = app_scale()
			local pw, ph = PANEL_W * scale, PANEL_H * scale
			local origin = (parent and parent.AbsolutePosition) or Vector2.new(0, 0)
			local ax = m.AbsolutePosition.X - origin.X
			local ay = m.AbsolutePosition.Y - origin.Y
			-- A panel taller than the screen cannot be fully fitted; pin it to the
			-- top edge rather than letting max() shove the header out of reach.
			local cx = math.max(10, math.min(ax, avail.X - pw - 10))
			local cy = math.max(10, math.min(ay, avail.Y - ph - 10))
			if avail.X - pw - 10 < 10 then cx = 10 end
			if avail.Y - ph - 10 < 10 then cy = 10 end
			-- Snapped, not tweened: UNFOLD is Back/Out, and overshoot on a
			-- correction meant to pull the panel on-screen would push it further
			-- off first. The move is hidden by the size tween starting alongside.
			if math.abs(cx - ax) > 0.5 or math.abs(cy - ay) > 0.5 then
				m.Position = UDim2.new(0, cx, 0, cy)
			end

			set_header_extras(false)
			v6:Create(minb, UNFOLD, { Position = UDim2.new(1, -44, 0.5, -7) }):Play()
			v6:Create(h, UNFOLD, { Size = UDim2.new(1, 0, 0, HEADER_H) }):Play()
			v6:Create(mcorner, UNFOLD, { CornerRadius = UDim.new(0, 10) }):Play()
			local tw = v6:Create(m, UNFOLD, { Size = UDim2.new(0, PANEL_W, 0, HEADER_H) })
			local conn
			conn = tw.Completed:Connect(function()
				if conn then conn:Disconnect() end
				if not im then roll_down() else anim_busy = false end
			end)
			tw:Play()
		end

		minb.MouseButton1Click:Connect(function()
			if anim_busy then return end
			anim_busy = true
			im = not im
			-- The glyph follows the state, so the pill says "expand" rather than
			-- repeating "collapse" at something already collapsed.
			minb.Text = im and "+" or "–"
			-- Set before any tween starts: the extras overlap minb for the whole
			-- fold, and this is what makes their handlers ignore the tap.
			collapsed = im
			if im then
				roll_up()
			else
				unfold_header()
			end
		end)

		closeb.MouseButton1Click:Connect(function()
			-- Invisible on the pill but still hit-testable, and stacked over minb.
			if collapsed then return end
			if context.destroy then
				context.destroy()
			else
				RestoreAllPerf()
				if context.x4 and context.x4.f5 then context.x4.f5() end
				sg:Destroy()
			end
		end)
		
		pcall(function()
			sg.Destroying:Connect(function()
				local owns_gui = x6.sg == sg
				RestoreAllPerf()
				if x5.g == sg then x5.g = nil end
				if owns_gui then x6.sg = nil end
				if owns_gui and not x6.torn_down and context.destroy then context.destroy() end
			end)
		end)

		local ctrl_container = Instance.new("Frame", sg)
		ctrl_container.BackgroundTransparency = 1
		ctrl_container.Position = UDim2.new(0, 15, 0.05, 0)
		ctrl_container.Size = UDim2.new(0, 60, 0, 200)

		local hide_btn = Instance.new("TextButton", ctrl_container)
		hide_btn.Size = UDim2.new(0, 14, 0, 14)
		hide_btn.Position = UDim2.new(0, 0, 0, 6)
		hide_btn.BackgroundColor3 = Color3.fromRGB(60, 200, 100)
		hide_btn.Text = ""
		Instance.new("UICorner", hide_btn).CornerRadius = UDim.new(1, 0)

		local ctrl = Instance.new("Frame", ctrl_container)
		ctrl.BackgroundTransparency = 1
		ctrl.Position = UDim2.new(0, 22, 0, 0)
		ctrl.Size = UDim2.new(1, -22, 1, 0)

		local layout = Instance.new("UIListLayout", ctrl)
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder

		local function create_btn(txt, col, order)
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(0, 22, 0, 22)
			b.BackgroundColor3 = col
			b.Text = txt
			b.TextColor3 = Color3.fromRGB(255, 255, 255)
			b.Font = Enum.Font.GothamBold
			b.TextSize = 6
			b.LayoutOrder = order
			Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
			b.Parent = ctrl
			return b
		end

		local btn_place = create_btn("PLC", Color3.fromRGB(50, 150, 200), 2)
		local btn_clean = create_btn("CLN", Color3.fromRGB(200, 80, 80), 3)
		local btn_up = create_btn("UP", Color3.fromRGB(80, 80, 85), 4)
		local btn_down = create_btn("DWN", Color3.fromRGB(80, 80, 85), 5)
		local btn_pause = create_btn("PAU", Color3.fromRGB(200, 150, 50), 6)
		local btn_dis = create_btn("DIS", Color3.fromRGB(60, 60, 60), 7)
		-- the settings panel is rebuilt on every f1(), so the toggle there reaches
		-- the dock through x6 rather than an upvalue that would go stale
		x6.dock_disable_btn = btn_dis
		if x1.Disabled then
			btn_dis.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
		end

		local controls_visible = true
		hide_btn.MouseButton1Click:Connect(function()
			controls_visible = not controls_visible
			hide_btn.BackgroundColor3 = controls_visible and Color3.fromRGB(60, 200, 100) or Color3.fromRGB(200, 60, 60)
			btn_place.Visible = controls_visible
			btn_clean.Visible = controls_visible
			btn_up.Visible = controls_visible
			btn_down.Visible = controls_visible
			btn_pause.Visible = controls_visible
			btn_dis.Visible = controls_visible
		end)

		btn_place.MouseButton1Click:Connect(function()
			if context.x4 and context.x4.f4 then
				local cam = v4.CurrentCamera
				if cam then
					local vp = cam.ViewportSize
					local ray = cam:ViewportPointToRay(vp.X / 2, vp.Y / 2)
					local rp = RaycastParams.new()
					rp.FilterType = Enum.RaycastFilterType.Exclude
					rp.FilterDescendantsInstances = {v8.Character}
					local res = workspace:Raycast(ray.Origin, ray.Direction * 1000, rp)
					local pos = res and res.Position or (ray.Origin + ray.Direction * 20)
					context.x4.f4(pos)
				end
			end
		end)

		btn_clean.MouseButton1Click:Connect(function()
			if context.x4 and context.x4.clean_physics then
				context.x4.clean_physics()
			end
		end)

		local holding_up = false
		btn_up.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				holding_up = true
				task.spawn(function()
					while holding_up and x6.b do
						x6.b.Position = x6.b.Position + Vector3.new(0, 1, 0)
						task.wait()
					end
				end)
			end
		end)
		btn_up.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				holding_up = false
			end
		end)

		local holding_down = false
		btn_down.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				holding_down = true
				task.spawn(function()
					while holding_down and x6.b do
						x6.b.Position = x6.b.Position - Vector3.new(0, 1, 0)
						task.wait()
					end
				end)
			end
		end)
		btn_down.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				holding_down = false
			end
		end)

		btn_pause.MouseButton1Click:Connect(function()
			x1.Paused = not x1.Paused
			btn_pause.BackgroundColor3 = x1.Paused and Color3.fromRGB(255, 200, 80) or Color3.fromRGB(200, 150, 50)
			-- The dock is the real pause control on touch, so Hide Core While Paused
			-- has to be honoured here and not only on the P hotkey.
			if context.x4 and context.x4.refresh_core_visual then
				context.x4.refresh_core_visual()
			end
		end)

		btn_dis.MouseButton1Click:Connect(function()
			-- same single entry point as the settings toggle and the hotkey
			if context.x4 and context.x4.apply_disabled then
				context.x4.apply_disabled(not x1.Disabled)
			else
				x1.Disabled = not x1.Disabled
			end
			btn_dis.BackgroundColor3 = x1.Disabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(60, 60, 60)
			if save_settings then
				save_settings()
			end
		end)

		f1()
	end

	return x5
end
