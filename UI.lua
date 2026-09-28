return function(context)
	local v1, v2, v3, v4, v5, v6, v7, v8, v9 = context.v1, context.v2, context.v3, context.v4, context.v5, context.v6, context.v7, context.v8, context.v9
	local x1, x2, x6, x9 = context.x1, context.x2, context.x6, context.x9
	local favorites, save_favs, save_settings = context.favorites, context.save_favs, context.save_settings
	local get_shape = context.get_shape
	local load_module = context.load_module
	local PluginControls = context.plugin_controls or load_module("PluginControls.lua")
	local MobileControls
	if context.is_mobile or v1.TouchEnabled then MobileControls = load_module("MobileControls.lua") end
	-- Shared motion vocabulary from main.lua; see the ANIM table there for why
	-- each curve is what it is. Fallback keeps this module loadable standalone.
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
	local UI_elements_builder = load_module("UI_elements.lua")
	if not UI_elements_builder then
		error("Failed to load UI_elements", 0)
	end
	local UI_elements = UI_elements_builder(context)
	-- Project UAI is launched on demand; repeated clicks share the in-flight load.
	local ai_loading = false
	local es, et, eb, eh = UI_elements.s, UI_elements.t, UI_elements.b, UI_elements.h
	local etb = UI_elements.tb
	local ekb = UI_elements.kb

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
		-- 60/-70 pair was really HEADER_H + gap, written out by hand.
		local PANEL_W = 320
		local PANEL_H = 500
		local HEADER_H = 50
		local PILL_SIZE = 44
		local CONTENT_GAP = 10

		-- Advanced, Keybinds and Part Control are the same kind of window and all
		-- open in the same slot beside Main, so they share one geometry rather than
		-- each carrying its own literals. That drift is what left Part Control at
		-- 300x470 with a 50px header next to Keybinds' 300x440 with a 44px one, and
		-- what made three panels stack on the same coordinates.
		local SIDE_W = 300
		local SIDE_H = 440
		local SIDE_HEADER_H = 44
		local SIDE_X = 360
		-- Bottom margin under a side panel's content frame, matching CONTENT_GAP.
		local SIDE_GAP = 10

		-- Roblox honours one UIScale per GuiObject, so the open/close pop and the
		-- user's UI Scale setting have to share it. Every scalable window is
		-- registered here and its scale is always (pop factor * app scale):
		-- toggle_window used to tween the single UIScale straight to 1, which is
		-- what silently threw away the Advanced window's saved scale the first
		-- time it was opened.
		-- Weak keys, because registration outlives the window. The reset-confirm
		-- dialog is registered on open and Destroy()ed on dismiss, and
		-- TargetListContainer is torn down and rebuilt on every refresh -- each
		-- one used to leave a strong reference to a dead Instance behind here.
		-- Nothing swept them: the only prune is the win.Parent check inside
		-- apply_ui_scale, which runs only when the scale setting changes, so the
		-- table grew for the whole session and pinned every corpse it held. A
		-- window that is still parented is kept alive by its parent, so weak keys
		-- drop exactly the dead ones and nothing else.
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
		-- cannot snap a closed window to full size. Nested windows (the mode
		-- selector and target list live under Main) must not carry the app scale
		-- on their own UIScale as well: their parent's UIScale already applies
		-- it, and applying it twice compounds to scale-squared.
		local function register_window(win, pop, nested)
			local scale = win:FindFirstChild("UIScale")
			if not scale then
				scale = Instance.new("UIScale", win)
			end
			pop = pop or 1
			scale.Scale = pop * ((nested and 1) or app_scale())
			scaled_windows[win] = { scale = scale, pop = pop, nested = nested or false }
			return scale
		end

		local function set_pop(win, pop, tween_info, nested)
			local entry = scaled_windows[win]
			if not entry then
				register_window(win, pop, nested)
				entry = scaled_windows[win]
			end
			entry.pop = pop
			local target = pop * ((entry.nested and 1) or app_scale())
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
					if not entry.nested then
						v6:Create(entry.scale, A.RESCALE, { Scale = entry.pop * s }):Play()
					end
				else
					scaled_windows[win] = nil
				end
			end
		end
		x5.apply_ui_scale = apply_ui_scale

		local function toggle_window(win, state, nested)
			if not scaled_windows[win] then
				register_window(win, win.Visible and 1 or 0.8, nested)
			end
			local prop = win:IsA("CanvasGroup") and "GroupTransparency" or "BackgroundTransparency"
			if state then
				win.Visible = true
				v6:Create(win, A.OPEN, {[prop] = 0}):Play()
				set_pop(win, 1, A.OPEN_POP, nested)
			else
				local tw = v6:Create(win, A.CLOSE, {[prop] = 1})
				set_pop(win, 0.8, A.CLOSE_POP, nested)
				local conn
				conn = tw.Completed:Connect(function()
					if win.Parent and win[prop] >= 0.99 then win.Visible = false end
					if conn then conn:Disconnect() end
				end)
				tw:Play()
			end
		end

		-- The side panels all open in the same slot beside Main, so opening one has
		-- to close the others: stacked they are unreadable, and the one underneath
		-- still takes clicks wherever the top one does not cover it. Part Control
		-- carries an on_close because closing it also has to disarm the click
		-- handlers -- otherwise every click keeps hijacking held parts with the
		-- panel out of sight.
		local side_panels = {}
		local function register_side_panel(win, on_close)
			side_panels[win] = on_close or true
		end

		local function close_side_panel(win)
			local on_close = side_panels[win]
			toggle_window(win, false)
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
				toggle_window(win, true)
			else
				close_side_panel(win)
			end
		end

		-- Tinting towards white rather than carrying a second colour literal per button,
		-- so a palette change cannot leave a hover state behind. Written out rather than
		-- using Color3:Lerp because this also has to run under the test harness's
		-- Color3 stub, which has the components but not the methods.
		local function brighten(c, amt)
			return Color3.new(c.R + (1 - c.R) * amt, c.G + (1 - c.G) * amt, c.B + (1 - c.B) * amt)
		end

		-- Every round button in the tree: the four in Main's header and the close on each
		-- side panel. They were bare coloured circles with no glyph, no hover and no
		-- press -- the only clickable things here that gave no feedback at all, and two
		-- of them (minimize and close) were told apart only by colour.
		local function circle_btn(parent, base, glyph, text_size)
			local b = Instance.new("TextButton", parent)
			b.BackgroundColor3 = base
			b.Size = UDim2.new(0, 20, 0, 20)
			b.AutoButtonColor = false
			b.Text = glyph or ""
			b.TextColor3 = Color3.fromRGB(255, 255, 255)
			b.Font = Enum.Font.GothamBold
			b.TextSize = text_size or 12
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

		-- One hover behaviour for every list row and dropdown. There were three: the mode
		-- selector's rows and Part Control's shape rows had none at all, the target list
		-- set BackgroundColor3 directly instead of tweening it on the shared curve, and
		-- the two dropdown buttons had neither. idle is passed in rather than read back
		-- off the object because a selected row carries its own tint and must keep it.
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

		-- Text-only hover, for the transparent buttons layered over a row: a favourite
		-- star, the clear-target ×, the row's own label. AutoButtonColor tints a
		-- background, so on a BackgroundTransparency 1 button it has nothing to work
		-- with -- these were the controls here with no feedback of any kind, engine or
		-- otherwise. Tinting the glyph is the equivalent move.
		local function glyph_hover(obj, idle, hot)
			obj.MouseEnter:Connect(function()
				v6:Create(obj, A.TINT, { TextColor3 = hot }):Play()
			end)
			obj.MouseLeave:Connect(function()
				v6:Create(obj, A.TINT, { TextColor3 = idle }):Play()
			end)
		end

		-- A list row's tint lives on the Frame behind it, but both list rows here are
		-- covered edge to edge by transparent TextButtons, and a button under the
		-- pointer takes the enter/leave for itself. The tint was only reachable on the
		-- few pixels of Frame the buttons leave uncovered -- so the hover added to
		-- those rows was, in practice, not there. Pointing the covering children at
		-- the same paint is what makes it visible anywhere on the row.
		local function hover_proxy(src, target, idle, hot)
			src.MouseEnter:Connect(function()
				v6:Create(target, A.HOVER, { BackgroundColor3 = hot }):Play()
			end)
			src.MouseLeave:Connect(function()
				v6:Create(target, A.HOVER, { BackgroundColor3 = idle }):Play()
			end)
		end

		-- Every window in this tree closes with the same 20x20 red circle. Part
		-- Control used to be the one exception -- a grey text "x", 30x30, at its own
		-- offset -- and Advanced had no close button at all.
		local function side_close(header, cb)
			local b = circle_btn(header, Color3.fromRGB(200, 60, 60), "×", 14)
			b.Position = UDim2.new(1, -30, 0.5, -10)
			b.MouseButton1Click:Connect(cb)
			return b
		end

		-- Dragging, done by hand rather than with the legacy Draggable property.
		-- Draggable applies to the whole frame, so on Main -- which is mostly a tall
		-- scrolling list of sliders and toggles -- a drag that began on the body moved
		-- the window instead of reaching the control under the cursor. Binding the
		-- drag to the header is the actual fix; the clamp is the second half of it,
		-- because Draggable also happily parked a window fully outside the viewport
		-- where nothing could reach it again. Only Main had a rescue for that
		-- (unfold_header), and only by way of minimizing.
		--
		-- Deltas go straight onto Position's offset and stay 1:1 with the cursor even
		-- under UIScale: a UIScale scales the window's own size and its descendants,
		-- while Position still resolves against the parent, which is the ScreenGui.
		-- The scale components are preserved, so a window anchored to the viewport
		-- centre still tracks a resize.
		local KEEP_ON_SCREEN = 60
		local function make_draggable(win, handle)
			handle = handle or win
			-- A transparent Frame header still reports input; Active makes it consume
			-- the press so it cannot fall through to whatever sits behind. Buttons
			-- inside the header consume their own input, so minb and closeb never
			-- start a drag.
			handle.Active = true

			local dragging = false
			local origin, start_pos

			local function commit(delta)
				local parent = win.Parent
				if not parent then
					return
				end
				local avail = parent.AbsoluteSize
				local size = win.AbsoluteSize
				local want_x = start_pos.X.Scale * avail.X + start_pos.X.Offset + delta.X
				local want_y = start_pos.Y.Scale * avail.Y + start_pos.Y.Offset + delta.Y
				-- Leave a grabbable sliver on screen in both axes. Vertically the
				-- floor is 0: a header dragged above the top edge is a window that
				-- can never be picked up again.
				local max_x = avail.X - KEEP_ON_SCREEN
				local min_x = math.min(-(size.X - KEEP_ON_SCREEN), max_x)
				win.Position = UDim2.new(
					start_pos.X.Scale,
					math.clamp(want_x, min_x, max_x) - start_pos.X.Scale * avail.X,
					start_pos.Y.Scale,
					math.clamp(want_y, 0, math.max(0, avail.Y - 30)) - start_pos.Y.Scale * avail.Y
				)
			end

			table.insert(x6.c, handle.InputBegan:Connect(function(input)
				local ty = input.UserInputType
				if ty ~= Enum.UserInputType.MouseButton1 and ty ~= Enum.UserInputType.Touch then
					return
				end
				dragging = true
				origin = input.Position
				start_pos = win.Position
				-- Latched off the input itself rather than a global InputEnded: a
				-- release over another GUI still ends this input, and without it the
				-- window would stay stuck to the cursor.
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
				commit(input.Position - origin)
			end))
		end

		local hud = Instance.new("Frame", sg)
		hud.Name = "StatusHUD"
		hud.BackgroundTransparency = 1
		hud.Position = UDim2.new(0.5, -200, 0, 20)
		hud.Size = UDim2.new(0, 400, 0, 30)

		-- Scaled like every other element. The HUD was the one thing never registered,
		-- so at UI Scale 2.0 every window doubled and the status line stayed at 14px,
		-- against the setting's own description ("Scales the entire interface").
		register_window(hud, 1)

		local hud_l = Instance.new("TextLabel", hud)
		hud_l.BackgroundTransparency = 1
		hud_l.Size = UDim2.new(1, 0, 1, 0)
		hud_l.Font = Enum.Font.GothamBold
		hud_l.TextSize = 14
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
				-- x1.Targets, not x1.Tgt: multi-targeting replaced the single slot and
				-- nothing has written Tgt since, so this field read "NONE" even with
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

		local m = Instance.new("Frame", sg)
		m.Name = "Main"
		m.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
		m.Position = UDim2.new(0, 30, 0.5, -250)
		m.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
		m.Active = true
		-- Dragged by its header only; see make_draggable. The old Draggable made
		-- the whole scrolling body a drag handle.
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
		-- The header is also the whole surface of the collapsed pill, so binding
		-- the drag here keeps the pill draggable without a second code path.
		make_draggable(m, h)

		local t = Instance.new("TextLabel", h)
		t.BackgroundTransparency = 1
		t.Position = UDim2.new(0, 20, 0, 0)
		t.Size = UDim2.new(0.6, 0, 1, 0)
		t.Text = "PROJECT GRAVITY"
		t.TextColor3 = Color3.fromRGB(255, 255, 255)
		t.Font = Enum.Font.GothamBlack
		t.TextSize = 16
		t.TextXAlignment = 0

		local c = Instance.new("ScrollingFrame", m)
		c.BackgroundTransparency = 1
		c.Position = UDim2.new(0, 0, 0, HEADER_H + CONTENT_GAP)
		c.Size = UDim2.new(1, 0, 1, -(HEADER_H + CONTENT_GAP * 2))
		c.ScrollBarThickness = 0
		c.AutomaticCanvasSize = Enum.AutomaticSize.Y
		c.CanvasSize = UDim2.new(0, 0, 0, 0)
		local l = Instance.new("UIListLayout", c)
		l.Padding = UDim.new(0, 12)
		l.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local p = Instance.new("UIPadding", c)
		p.PaddingLeft = UDim.new(0, 20)
		p.PaddingRight = UDim.new(0, 20)
		p.PaddingBottom = UDim.new(0, 20)

		local am = Instance.new("CanvasGroup", sg)
		am.Name = "Advanced"
		am.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
		am.Position = UDim2.new(0, SIDE_X, 0.5, -SIDE_H / 2)
		am.Size = UDim2.new(0, SIDE_W, 0, SIDE_H)
		am.Visible = false
		am.GroupTransparency = 1
		am.Active = true
		Instance.new("UICorner", am).CornerRadius = UDim.new(0, 10)
		local ams = Instance.new("UIStroke", am)
		ams.Color = Color3.fromRGB(40, 40, 45)
		ams.Thickness = 1

		-- Starts hidden, so it starts at the closed pop factor and toggle_window
		-- tweens it up to the app scale rather than to a hardcoded 1.
		register_window(am, 0.8)
		register_side_panel(am)

		local ah = Instance.new("Frame", am)
		ah.BackgroundTransparency = 1
		ah.Size = UDim2.new(1, 0, 0, SIDE_HEADER_H)
		make_draggable(am, ah)
		local at = Instance.new("TextLabel", ah)
		at.BackgroundTransparency = 1
		at.Position = UDim2.new(0, 20, 0, 0)
		at.Size = UDim2.new(0.6, 0, 1, 0)
		at.Text = "ADVANCED"
		at.TextColor3 = Color3.fromRGB(255, 255, 255)
		at.Font = Enum.Font.GothamBold
		at.TextSize = 14
		at.TextXAlignment = 0

		side_close(ah, function()
			close_side_panel(am)
		end)

		local ac = Instance.new("ScrollingFrame", am)
		ac.BackgroundTransparency = 1
		ac.Position = UDim2.new(0, 0, 0, SIDE_HEADER_H)
		ac.Size = UDim2.new(1, 0, 1, -(SIDE_HEADER_H + SIDE_GAP))
		ac.ScrollBarThickness = 0
		ac.AutomaticCanvasSize = Enum.AutomaticSize.Y
		ac.CanvasSize = UDim2.new(0, 0, 0, 0)
		-- Notifications from the Advanced panel go straight through System's x8 rather
		-- than the local notify() further down this file: notify is declared *after*
		-- populate_advanced, so a reference to it from in here resolves to a nil global
		-- and the message goes nowhere.
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
			d.TextSize = 10
			d.TextWrapped = true
			return d
		end

		-- An enum rendered as a button that cycles. config.lua records that shape enums
		-- are integer sliders "(no Dropdown control exists)", which is tolerable for a
		-- three-value shape knob and not for six named release rules: here the label
		-- carries the current value and one click advances it, so there is no number for
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

		-- Rebuildable, so a reset can repaint it. Every control in here caches its
		-- value at build time -- UI_elements M.s keeps `current` as a private local --
		-- and this block used to be built exactly once. After "Reset All Settings" the
		-- knobs therefore kept the old numbers while x1 held the defaults, and nudging
		-- UI Scale committed from the stale value: a reset from 2.0 then one step down
		-- gave 1.9 instead of 1.1.
		local function populate_advanced()
			ac:ClearAllChildren()
			local acl = Instance.new("UIListLayout", ac)
			acl.Padding = UDim.new(0, 10)
			acl.HorizontalAlignment = Enum.HorizontalAlignment.Center
			local ap = Instance.new("UIPadding", ac)
			ap.PaddingLeft = UDim.new(0, 20)
			ap.PaddingRight = UDim.new(0, 20)

			-- Grouped, in the order the controls were already in -- nothing moves. Fifteen
			-- controls in one flat list was the only panel in the tree without headers,
			-- and it is the longest one.
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
					-- Lets the runtime try again: it stops re-fetching a module that failed
					-- to download, and a name change is the deliberate retry.
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
				-- The loop clears the markers itself, but only while it is running: with
				-- the script stopped or disabled nothing would ever come and collect them.
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
				-- Every registered window, not just these two: the mode selector and
				-- the target list are nested under Main and only carry their pop
				-- factor, so Main's UIScale covers them; Advanced, Keybinds and the
				-- dialogs are siblings and used to be missed or overwritten.
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

			-- A rule change has to act on the formation in front of you, not only on the
			-- next claim, or editing one looks like it did nothing at all.
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

			-- x1.k5 has been the one extensible hook in the claim filter since the start
			-- and has never had a way to reach it.
			local function tags_text()
				local t = x1.k5
				if type(t) ~= "table" then
					return ""
				end
				-- Filtered rather than handed straight to table.concat: k5 comes back from
				-- the settings file as whatever was in it, and concat throws on a
				-- non-string entry -- which would take the whole panel build down with it.
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

			-- x1.FPSCap has a default, is saved, and is applied by main.lua at launch --
			-- but only the *mobile* Advanced panel ever wrote it, so on desktop the value
			-- in the settings file was applied once and then unreachable.
			if setfpscap then
				es(ac, "FPS Cap (0=Unc)", 0, 240, x1.FPSCap or 60, function(v)
					x1.FPSCap = v
					setfpscap(v)
					save_settings()
				end, true, "Caps your max FPS. 0 means uncapped.")
			end

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

			-- Each channel slider rebuilds the whole colour, so it has to hand the other
			-- two back as the same integers they came in as. Color3 stores 0-1 floats and
			-- v/255 does not round-trip exactly, so passing the bare product re-quantised
			-- the untouched channels on every drag and walked the colour off over a
			-- session of tweaking.
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
		populate_advanced()
		x5.refresh_advanced = populate_advanced

		local km = Instance.new("CanvasGroup", sg)
		km.Name = "Keybinds"
		km.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
		km.Position = UDim2.new(0, SIDE_X, 0.5, -SIDE_H / 2)
		km.Size = UDim2.new(0, SIDE_W, 0, SIDE_H)
		km.Visible = false
		km.GroupTransparency = 1
		km.Active = true
		Instance.new("UICorner", km).CornerRadius = UDim.new(0, 10)
		local kms = Instance.new("UIStroke", km)
		kms.Color = Color3.fromRGB(40, 40, 45)
		kms.Thickness = 1
		register_window(km, 0.8)
		register_side_panel(km)

		local kh = Instance.new("Frame", km)
		kh.BackgroundTransparency = 1
		kh.Size = UDim2.new(1, 0, 0, SIDE_HEADER_H)
		make_draggable(km, kh)
		local kt = Instance.new("TextLabel", kh)
		kt.BackgroundTransparency = 1
		kt.Position = UDim2.new(0, 20, 0, 0)
		kt.Size = UDim2.new(0.6, 0, 1, 0)
		kt.Text = "KEYBINDS"
		kt.TextColor3 = Color3.fromRGB(255, 255, 255)
		kt.Font = Enum.Font.GothamBold
		kt.TextSize = 14
		kt.TextXAlignment = 0

		side_close(kh, function()
			close_side_panel(km)
		end)

		local ksearch = Instance.new("TextBox", km)
		ksearch.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		ksearch.Position = UDim2.new(0, 20, 0, SIDE_HEADER_H)
		ksearch.Size = UDim2.new(1, -40, 0, 30)
		ksearch.PlaceholderText = "Search shapes..."
		ksearch.PlaceholderColor3 = Color3.fromRGB(110, 110, 120)
		ksearch.Text = ""
		ksearch.TextColor3 = Color3.fromRGB(255, 255, 255)
		ksearch.Font = Enum.Font.Gotham
		ksearch.TextSize = 12
		ksearch.ClearTextOnFocus = false
		Instance.new("UICorner", ksearch).CornerRadius = UDim.new(0, 6)

		local kc = Instance.new("ScrollingFrame", km)
		kc.BackgroundTransparency = 1
		-- The header, then the search row (30) and the gap under it (8).
		kc.Position = UDim2.new(0, 0, 0, SIDE_HEADER_H + 38)
		kc.Size = UDim2.new(1, 0, 1, -(SIDE_HEADER_H + 38 + SIDE_GAP))
		kc.ScrollBarThickness = 0
		kc.AutomaticCanvasSize = Enum.AutomaticSize.Y
		kc.CanvasSize = UDim2.new(0, 0, 0, 0)
		local kcl = Instance.new("UIListLayout", kc)
		kcl.Padding = UDim.new(0, 8)
		kcl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local kcp = Instance.new("UIPadding", kc)
		kcp.PaddingLeft = UDim.new(0, 20)
		kcp.PaddingRight = UDim.new(0, 20)
		kcp.PaddingBottom = UDim.new(0, 20)

		-- Notifications go through System's x7.n when it is up so a rejected key
		-- reads like every other message; before then there is nowhere to show it.
		local function notify(title, text, dur)
			local x8 = context.x8
			if x8 and x8.notify then
				x8.notify(title, text, dur)
				return
			end
			pcall(function()
				v5:SetCore("SendNotification", { Title = title, Text = text, Duration = dur or 3 })
			end)
		end

		local function keybinds_table()
			if type(x1.Keybinds) ~= "table" then
				x1.Keybinds = { Recenter = "E", Reset = "Q", Pause = "P", Disable = "L", Shapes = {} }
			end
			if type(x1.Keybinds.Shapes) ~= "table" then
				x1.Keybinds.Shapes = {}
			end
			return x1.Keybinds
		end

		-- Shared by both kinds of row. exclude_id keeps re-picking the key a row
		-- already holds from being reported as a conflict with itself.
		local function accept_key(key_name, exclude_id, assign)
			local kb = keybinds_table()
			if key_name == "" then
				assign(kb, "")
				save_settings()
				return true
			end
			local x8 = context.x8
			local conflict = x8 and x8.find_conflict and x8.find_conflict(key_name, exclude_id)
			if conflict then
				notify("Keybinds", key_name .. " is already bound to " .. conflict .. ".", 3)
				return false
			end
			assign(kb, key_name)
			save_settings()
			return true
		end

		local function populate_keybinds(filter)
			kc:ClearAllChildren()
			local layout = Instance.new("UIListLayout", kc)
			layout.Padding = UDim.new(0, 8)
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			local pad = Instance.new("UIPadding", kc)
			pad.PaddingLeft = UDim.new(0, 20)
			pad.PaddingRight = UDim.new(0, 20)
			pad.PaddingBottom = UDim.new(0, 20)

			local x8 = context.x8
			filter = (filter or ""):lower()

			if filter == "" then
				eh(kc, "Core")
				local core = (x8 and x8.core_actions) or {}
				for _, entry in ipairs(core) do
					local id = entry.id
					ekb(kc, entry.label, function()
						return keybinds_table()[id]
					end, function(key_name)
						return accept_key(key_name, id, function(kb, v)
							kb[id] = v
						end)
					end, entry.desc)
				end
			end

			eh(kc, filter == "" and "Shapes" or "Shapes matching \"" .. filter .. "\"")
			local names = {}
			for shape_name in pairs(x2) do
				if filter == "" or shape_name:lower():find(filter, 1, true) then
					names[#names + 1] = shape_name
				end
			end
			-- Bound shapes first, then alphabetical, so what the user has set is
			-- at the top of a list this long instead of buried in it.
			table.sort(names, function(a, b)
				local shapes = keybinds_table().Shapes
				local ba = (shapes[a] and shapes[a] ~= "") and 1 or 0
				local bb = (shapes[b] and shapes[b] ~= "") and 1 or 0
				if ba ~= bb then
					return ba > bb
				end
				return a < b
			end)

			if #names == 0 then
				local none = Instance.new("TextLabel", kc)
				none.BackgroundTransparency = 1
				none.Size = UDim2.new(1, 0, 0, 24)
				none.Text = "No shapes match."
				none.TextColor3 = Color3.fromRGB(120, 120, 130)
				none.TextXAlignment = Enum.TextXAlignment.Left
				none.Font = Enum.Font.Gotham
				none.TextSize = 11
			end

			for _, shape_name in ipairs(names) do
				local captured = shape_name
				ekb(kc, captured, function()
					return keybinds_table().Shapes[captured]
				end, function(key_name)
					return accept_key(key_name, "shape:" .. captured, function(kb, v)
						-- "" is how a core action records "unbound", but a shape
						-- with no key does not need an entry at all: dropping it
						-- keeps the settings file from growing a line per shape
						-- the user merely looked at.
						kb.Shapes[captured] = (v ~= "" and v) or nil
					end)
				end)
			end
			-- Same mixed-class list, same fix: the two headings here are TextLabels among
			-- Frames, so by name they sorted below every key row. Rebuilt on each keystroke
			-- in the search box, so the numbering has to be redone here rather than once.
			order_children(kc, layout)
		end

		ksearch:GetPropertyChangedSignal("Text"):Connect(function()
			populate_keybinds(ksearch.Text)
		end)
		x5.refresh_keybinds = function() populate_keybinds(ksearch.Text) end

		local pcm = Instance.new("CanvasGroup", sg)
		pcm.Name = "PartControl"
		pcm.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
		pcm.Position = UDim2.new(0, SIDE_X, 0.5, -SIDE_H / 2)
		pcm.Size = UDim2.new(0, SIDE_W, 0, SIDE_H)
		pcm.Visible = false
		-- The panel is rebuilt closed, and pc_active lives on x6, which outlives a
		-- UI teardown -- so a rebuild would otherwise come up armed with the panel
		-- shut.
		x6.pc_active = false
		pcm.GroupTransparency = 1
		pcm.Active = true
		Instance.new("UICorner", pcm).CornerRadius = UDim.new(0, 10)
		local pcms = Instance.new("UIStroke", pcm)
		pcms.Color = Color3.fromRGB(40, 40, 45)
		pcms.Thickness = 1
		register_window(pcm, 0.8)
		-- Registered with an on_close, so closing the panel through any route --
		-- its own button, another side panel opening over it, or the whole panel
		-- collapsing to the pill -- disarms the click handlers. Left set, every
		-- click keeps hijacking held parts with no visible sign of why.
		register_side_panel(pcm, function()
			x6.pc_active = false
		end)

		local pch = Instance.new("Frame", pcm)
		pch.BackgroundTransparency = 1
		pch.Size = UDim2.new(1, 0, 0, SIDE_HEADER_H)
		make_draggable(pcm, pch)
		local pct = Instance.new("TextLabel", pch)
		pct.BackgroundTransparency = 1
		pct.Position = UDim2.new(0, 20, 0, 0)
		pct.Size = UDim2.new(0.6, 0, 1, 0)
		pct.Text = "PART CONTROL"
		pct.TextColor3 = Color3.fromRGB(255, 255, 255)
		pct.Font = Enum.Font.GothamBold
		pct.TextSize = 14
		pct.TextXAlignment = 0

		side_close(pch, function()
			close_side_panel(pcm)
		end)

		local pcc = Instance.new("ScrollingFrame", pcm)
		pcc.BackgroundTransparency = 1
		pcc.Position = UDim2.new(0, 0, 0, SIDE_HEADER_H)
		pcc.Size = UDim2.new(1, 0, 1, -(SIDE_HEADER_H + SIDE_GAP))
		pcc.ScrollBarThickness = 0
		pcc.AutomaticCanvasSize = Enum.AutomaticSize.Y
		pcc.CanvasSize = UDim2.new(0, 0, 0, 0)

		-- Built once and refreshed in place. This panel used to ClearAllChildren on
		-- every refresh, which had two consequences: the selection count could only
		-- ever be right at the instant the window was opened, and any refresh that
		-- landed while the user was mid-interaction destroyed the control under
		-- their cursor. The one genuinely rebuilt piece is the shape list, and its
		-- search box lives outside it for exactly that reason -- the same split
		-- populate_keybinds uses.
		local pcl = Instance.new("UIListLayout", pcc)
		pcl.Padding = UDim.new(0, 10)
		pcl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local pcp = Instance.new("UIPadding", pcc)
		pcp.PaddingLeft = UDim.new(0, 20)
		pcp.PaddingRight = UDim.new(0, 20)
		-- Main and Keybinds both pad the bottom; without it the last toggle sits
		-- flush against the panel edge.
		pcp.PaddingBottom = UDim.new(0, 20)

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
		count_lbl.Size = UDim2.new(1, 0, 0, 20)
		count_lbl.Text = "Selected: 0  ·  Overridden: 0"
		count_lbl.TextColor3 = Color3.fromRGB(255, 170, 0)
		count_lbl.Font = Enum.Font.GothamBold
		count_lbl.TextSize = 12
		count_lbl.TextXAlignment = 0

		-- "Overridden: 7" does not say what those seven are doing, and the three modes
		-- behave nothing like each other. Hidden when there are none, so the panel does
		-- not carry a row of zeroes for the common case.
		local mode_lbl = Instance.new("TextLabel", pcc)
		mode_lbl.BackgroundTransparency = 1
		mode_lbl.Size = UDim2.new(1, 0, 0, 16)
		mode_lbl.Text = ""
		mode_lbl.TextColor3 = Color3.fromRGB(150, 150, 160)
		mode_lbl.Font = Enum.Font.GothamMedium
		mode_lbl.TextSize = 11
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
		hint_lbl.TextSize = 10
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

		-- Two hints, because the first thing the panel has to answer is whether it
		-- is waiting on a selection. With nothing selected every action below is a
		-- no-op, and the panel used to give no sign of that at all.
		local HINT_EMPTY = "Nothing selected. Click a held part to select it -- selecting on its "
			.. "own changes nothing. Shift-click to add or remove; drag on empty space to box-select."
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

		-- context.x8 rather than a captured local: System publishes notify onto the
		-- context after UI is built, so a local grabbed here would be nil forever.
		local function pc_notify(title, msg, secs)
			local x8 = context.x8
			if x8 and x8.notify then
				x8.notify(title, msg, secs or 2)
			end
		end

		eb(pcc, "Clear Selection", function()
			if x6.pc_clear then
				x6.pc_clear()
			end
		end)

		-- Deselecting deliberately leaves the overrides in place, so there has to be
		-- a way to take them off again once the parts are no longer selected. Before
		-- this, Clear Selection dropped the whole registry and the parts it had been
		-- driving were stranded with no route back.
		eb(pcc, "Release All Overrides", function()
			if x6.pc_release_all then
				local n = x6.pc_release_all()
				pc_notify("Part Control", ("Released %d part%s"):format(n, n == 1 and "" or "s"))
			end
		end)

		-- Box-select is the only bulk gesture and it cannot reach a part that is off
		-- screen or behind you. These can. Select Overridden is also the only way back
		-- to a part that was assigned and then deselected, short of releasing the lot.
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

		-- A radio group painted the way the mode selector paints its rows, rather
		-- than by prefixing the label with a bullet: eb tweens both
		-- BackgroundColor3 and TextColor3 on hover, so an eb button cannot hold a
		-- selected tint -- the cursor crossing the row wipes it. Hand-built rows own
		-- their own hover, so the selection survives it.
		local function mode_row(id)
			local b = Instance.new("TextButton", pcc)
			b.Size = UDim2.new(1, 0, 0, 34)
			b.AutoButtonColor = false
			b.BorderSizePixel = 0
			b.Text = "  " .. MODE_LABELS[id]
			b.Font = Enum.Font.GothamMedium
			b.TextSize = 13
			b.TextXAlignment = Enum.TextXAlignment.Left
			b.TextTruncate = Enum.TextTruncate.AtEnd
			Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
			local str = Instance.new("UIStroke", b)
			str.Thickness = 1

			local hovering = false
			local function paint(instant)
				local on = x1.PartCtlMode == id
				local bg = (on and Color3.fromRGB(40, 40, 180))
					or (hovering and Color3.fromRGB(40, 40, 45))
					or Color3.fromRGB(30, 30, 35)
				local fg = (on or hovering) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 220, 220)
				local edge = (on and Color3.fromRGB(70, 70, 200))
					or (hovering and Color3.fromRGB(70, 70, 78))
					or Color3.fromRGB(50, 50, 55)
				if instant then
					b.BackgroundColor3, b.TextColor3, str.Color = bg, fg, edge
					return
				end
				v6:Create(b, A.TINT, { BackgroundColor3 = bg, TextColor3 = fg }):Play()
				v6:Create(str, A.TINT, { Color = edge }):Play()
			end

			b.MouseEnter:Connect(function()
				hovering = true
				paint()
			end)
			b.MouseLeave:Connect(function()
				hovering = false
				paint()
			end)
			b.MouseButton1Click:Connect(function()
				set_mode(id)
			end)
			UI_elements.press(b)
			paint(true)
			mode_paint[id] = paint
		end

		for _, id in ipairs({ "normal", "pin", "manual", "shape" }) do
			mode_row(id)
		end
		refresh_modes()

		-- A section that folds. Expanded, the shape picker and the four physics
		-- sliders push Options a screen and a half down a 440px panel, and reaching
		-- them means scrolling past a nested scroller -- which on touch fights the
		-- panel's own scroll. The head carries the section's current value, so the
		-- state is still readable while it is shut.
		--
		-- Folding is Visible on the body, not a size tween: UIListLayout skips
		-- invisible children, so the rows below close the gap on their own and
		-- AutomaticCanvasSize re-measures the canvas with them.
		local function collapsible(title, open, value_fn)
			local head = Instance.new("TextButton", pcc)
			head.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
			head.Size = UDim2.new(1, 0, 0, 34)
			head.AutoButtonColor = false
			head.BorderSizePixel = 0
			head.Text = ""
			Instance.new("UICorner", head).CornerRadius = UDim.new(0, 6)
			local hstr = Instance.new("UIStroke", head)
			hstr.Color = Color3.fromRGB(40, 40, 45)
			hstr.Thickness = 1

			local hl = Instance.new("TextLabel", head)
			hl.BackgroundTransparency = 1
			hl.Position = UDim2.new(0, 12, 0, 0)
			hl.Size = UDim2.new(0.5, 0, 1, 0)
			hl.Text = title:upper()
			hl.TextColor3 = Color3.fromRGB(200, 200, 210)
			hl.Font = Enum.Font.GothamBold
			hl.TextSize = 11
			hl.TextXAlignment = Enum.TextXAlignment.Left

			local vl = Instance.new("TextLabel", head)
			vl.BackgroundTransparency = 1
			vl.Position = UDim2.new(0.5, 0, 0, 0)
			vl.Size = UDim2.new(0.5, -30, 1, 0)
			vl.Text = ""
			vl.TextColor3 = Color3.fromRGB(0, 255, 200)
			vl.Font = Enum.Font.GothamMedium
			vl.TextSize = 11
			vl.TextXAlignment = Enum.TextXAlignment.Right
			vl.TextTruncate = Enum.TextTruncate.AtEnd

			local arrow = Instance.new("TextLabel", head)
			arrow.BackgroundTransparency = 1
			arrow.Position = UDim2.new(1, -26, 0, 0)
			arrow.Size = UDim2.new(0, 20, 1, 0)
			arrow.Text = open and "▲" or "▼"
			arrow.TextColor3 = Color3.fromRGB(150, 150, 160)
			arrow.Font = Enum.Font.GothamBold
			arrow.TextSize = 10

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
			head.MouseEnter:Connect(function()
				v6:Create(head, A.HOVER, { BackgroundColor3 = Color3.fromRGB(35, 35, 40) }):Play()
			end)
			head.MouseLeave:Connect(function()
				v6:Create(head, A.HOVER, { BackgroundColor3 = Color3.fromRGB(25, 25, 30) }):Play()
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
		-- typed into. The picker was a single button that cycled one shape per click
		-- through every entry in x2 -- fifty-odd presses to reach the end of the
		-- alphabet. Styled like every other search box in the tree (ksearch, msb,
		-- the target list's): 20/20/25, 30 tall, Gotham 12.
		local pcsearch = Instance.new("TextBox", shape_body)
		pcsearch.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		pcsearch.Size = UDim2.new(1, 0, 0, 30)
		pcsearch.Text = ""
		pcsearch.PlaceholderText = "Search shapes..."
		pcsearch.PlaceholderColor3 = Color3.fromRGB(110, 110, 120)
		pcsearch.TextColor3 = Color3.fromRGB(255, 255, 255)
		pcsearch.Font = Enum.Font.Gotham
		pcsearch.TextSize = 12
		pcsearch.ClearTextOnFocus = false
		Instance.new("UICorner", pcsearch).CornerRadius = UDim.new(0, 6)

		local pcslist = Instance.new("ScrollingFrame", shape_body)
		pcslist.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		pcslist.BorderSizePixel = 0
		pcslist.Size = UDim2.new(1, 0, 0, 160)
		-- 0 like every other scroller in the tree; this list was the only one
		-- showing a bar.
		pcslist.ScrollBarThickness = 0
		pcslist.AutomaticCanvasSize = Enum.AutomaticSize.Y
		pcslist.CanvasSize = UDim2.new(0, 0, 0, 0)
		Instance.new("UICorner", pcslist).CornerRadius = UDim.new(0, 6)

		-- The same widget as the mode selector's rows, down to the favourites star
		-- and the favourites-first ordering, so a shape sits in the same place in
		-- both lists. Only the row height differs -- 34 rather than 40, matching the
		-- button rhythm of the panel this one is inset into.
		local function populate_pc_shapes(filter)
			pcslist:ClearAllChildren()
			local sl = Instance.new("UIListLayout", pcslist)
			sl.Padding = UDim.new(0, 5)
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
				-- Plain find, same as populate_modes: without the flag a typed "(" is
				-- an unfinished Lua capture and throws out of the Text callback after
				-- the list has already been cleared.
				if filter ~= "" and not sn:lower():find(filter:lower(), 1, true) then
					continue
				end
				local row = Instance.new("Frame", pcslist)
				row.Size = UDim2.new(1, -8, 0, 34)
				local row_on = sn == x1.PartCtlShape
				row.BackgroundColor3 = row_on and Color3.fromRGB(40, 40, 180) or Color3.fromRGB(25, 25, 30)
				row.BorderSizePixel = 0
				Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
				-- Hoisted so the two covering buttons can drive the same pair; the
				-- selected row keeps its own tint, which is why idle is passed rather
				-- than read back off the Frame on mouse-out.
				local row_idle = row.BackgroundColor3
				local row_hot = row_on and Color3.fromRGB(55, 55, 200) or Color3.fromRGB(35, 35, 40)
				row_hover(row, row_idle, row_hot)

				local pick = Instance.new("TextButton", row)
				pick.Position = UDim2.new(0, 8, 0, 0)
				pick.Size = UDim2.new(1, -40, 1, 0)
				pick.BackgroundTransparency = 1
				pick.Text = sn
				pick.TextColor3 = Color3.fromRGB(255, 255, 255)
				pick.Font = Enum.Font.GothamBold
				pick.TextSize = 12
				pick.TextXAlignment = Enum.TextXAlignment.Left
				pick.TextTruncate = Enum.TextTruncate.AtEnd
				hover_proxy(pick, row, row_idle, row_hot)

				local star = Instance.new("TextButton", row)
				star.Position = UDim2.new(1, -35, 0, 0)
				star.Size = UDim2.new(0, 35, 1, 0)
				star.BackgroundTransparency = 1
				star.Text = favorites[sn] and "★" or "☆"
				local star_idle = favorites[sn] and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(80, 80, 85)
				star.TextColor3 = star_idle
				star.Font = Enum.Font.GothamBold
				star.TextSize = 14
				-- An unfavourited star is nearly the row's own colour, so without this
				-- there was nothing to say the right end of the row was clickable.
				-- Brightened rather than tinted towards gold: gold on an empty ☆ reads
				-- as already-favourited, which is the one thing hover must not say.
				hover_proxy(star, row, row_idle, row_hot)
				glyph_hover(star, star_idle, brighten(star_idle, 0.35))
				UI_elements.press(star, 0.9)
				star.MouseButton1Click:Connect(function()
					favorites[sn] = not favorites[sn]
					save_favs()
					populate_pc_shapes(pcsearch.Text)
				end)

				pick.MouseButton1Click:Connect(function()
					x1.PartCtlShape = sn
					refresh_shape_head()
					-- Only re-assigns when shape mode is already the live mode, so
					-- browsing the list does not silently retarget the selection.
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
		-- number that does nothing until a button is pressed -- which is what made these
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

		pc_toggle("PartCtlMultiSelect", pcc, "Multi-Select (Click)", x1.PartCtlMultiSelect == true, function(v)
			x1.PartCtlMultiSelect = v
			save_settings()
		end, "Adds to the selection on every click, without holding Shift.")

		pc_toggle("PartCtlEnabled", pcc, "Stay Armed When Closed", x1.PartCtlEnabled == true, function(v)
			x1.PartCtlEnabled = v
			save_settings()
		end, "Keeps click-to-select and drag working after this panel is closed.")

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
		-- And the third mixed-class list: this panel holds headings and hints (TextLabels),
		-- mode rows and folding sections (Frames) and five buttons, so by name its headings
		-- and hints sorted to the bottom too. Its rows are built once, above, so this runs
		-- once here -- refresh_partctl only repaints what already exists.
		order_children(pcc, pcl)
		-- Published for System_partctl: selecting, assigning and releasing all run
		-- from input handlers that know nothing about the panel, and this is what
		-- makes the count and the active-mode marker live rather than a snapshot
		-- taken when the window happened to open.
		x6.pc_on_change = refresh_partctl


		local kb_btn = eb(c, "Keybinds", function()
			local opening = not km.Visible
			open_side_panel(km, opening)
			if opening then
				populate_keybinds(ksearch.Text)
			end
		end)
		kb_btn.Size = UDim2.new(1, 0, 0, 36)

		local ab = eb(c, "Advanced Settings", function()
			open_side_panel(am, not am.Visible)
		end)
		ab.Size = UDim2.new(1, 0, 0, 36)

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
		pcb.Size = UDim2.new(1, 0, 0, 36)

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
		ai_btn.Size = UDim2.new(1, 0, 0, 36)

		local mode_f = Instance.new("Frame", c)
		mode_f.BackgroundTransparency = 1
		mode_f.Size = UDim2.new(1, 0, 0, 44)
		local db = Instance.new("TextButton", mode_f)
		db.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
		db.Size = UDim2.new(1, 0, 1, 0)
		db.Text = "  " .. x1.k6:upper()
		db.TextColor3 = Color3.fromRGB(255, 255, 255)
		db.Font = Enum.Font.GothamBold
		db.TextSize = 13
		db.TextXAlignment = 0
		-- "DOMAIN EXPANSION INFINITE VOID" set uppercase at 13 is wider than this
		-- button, and nothing here clips, so the longest shape names used to run
		-- underneath the ▼. The padding reserves the arrow's column so the truncation
		-- happens before it rather than over it; arr is kept inside db -- so the press
		-- dip still takes the arrow with it -- and re-anchored to the padded edge,
		-- which is the same 30px from the right that it drew at before.
		db.TextTruncate = Enum.TextTruncate.AtEnd
		local ARROW_W = 30
		local dbp = Instance.new("UIPadding", db)
		dbp.PaddingRight = UDim.new(0, ARROW_W)
		Instance.new("UICorner", db).CornerRadius = UDim.new(0, 6)
		local dst = Instance.new("UIStroke", db)
		dst.Color = Color3.fromRGB(40, 40, 45)

		local arr = Instance.new("TextLabel", db)
		arr.BackgroundTransparency = 1
		arr.Position = UDim2.new(1, 0, 0, 0)
		arr.Size = UDim2.new(0, ARROW_W, 1, 0)
		arr.Text = "▼"
		arr.TextColor3 = Color3.fromRGB(150, 150, 160)
		arr.TextSize = 10

		-- The two dropdown buttons were the only large controls in the tree with no
		-- hover at all, which read as them not being buttons.
		row_hover(
			db,
			Color3.fromRGB(25, 25, 30),
			Color3.fromRGB(35, 35, 40),
			dst,
			Color3.fromRGB(40, 40, 45),
			Color3.fromRGB(70, 70, 78)
		)
		UI_elements.press(db, 0.99)

		db.MouseButton1Click:Connect(function()
			if x6.dlst_container then
				local new_state = not x6.dlst_container.Visible
				if m:FindFirstChild("TargetListContainer") and m.TargetListContainer.Visible then
					toggle_window(m.TargetListContainer, false, true)
				end
				toggle_window(x6.dlst_container, new_state, true)
				if new_state and x6.populate_modes then
					-- The typed filter, not a hardcoded "". msb lives outside f1 so its
					-- text persists for the session: reopening the dropdown showed the
					-- full list while the box still read the old search.
					x6.populate_modes(x6.mode_filter and x6.mode_filter() or "")
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

			et(gsc, "Simplified Interface", x1.SimpleMode, function(v)
				x1.SimpleMode = v
				save_settings()
				f1()
			end)

			et(gsc, "Show Status HUD", x1.ShowHUD ~= false, function(v)
				x1.ShowHUD = v
				if hud then hud.Visible = v end
				save_settings()
			end)

			et(gsc, "Preserve Collisions", x1.PreserveCollisions, function(v)
				x1.PreserveCollisions = v
				x6.refresh_collisions()
				save_settings()
			end)

			et(gsc, "Anchor to Self", x1.AnchorSelf, function(v)
				x1.AnchorSelf = v
				if v then
					x1.PI_All = false
					table.clear(x1.Targets)
					x1.TgtActive = false
					f1()
				end
				save_settings()
			end)

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
				save_settings()
			end)

			if not x1.SimpleMode then
				et(gsc, "Target Everyone", x1.PI_All, function(v)
					x1.PI_All = v
					if v then
						x1.AnchorSelf = false
						table.clear(x1.Targets)
						x1.TgtActive = false
						f1()
					end
					save_settings()
				end)
			end

			local l_btn = Instance.new("TextButton", gsc)
			l_btn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
			l_btn.Size = UDim2.new(1, 0, 0, 36)
			l_btn.Text = "FORCE LAUNCH"
			l_btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			l_btn.Font = Enum.Font.GothamBold
			l_btn.TextSize = 13
			l_btn.AutoButtonColor = false
			Instance.new("UICorner", l_btn).CornerRadius = UDim.new(0, 6)
			-- == true, not the bare value: Visible rejects nil, and an unset
			-- SlingshotManual made this whole expression nil whenever Slingshot was
			-- the live shape, which threw here and abandoned the rest of f1 --
			-- taking the target selector, the shape controls and reset with it.
			l_btn.Visible = x1.k6 == "Slingshot" and x1.SlingshotManual == true

			-- The one button here that repaints itself between two states, which is why
			-- row_hover did not fit: that helper captures a single idle tint, and a
			-- captured red would have snapped the armed blue back to red on mouse-out.
			-- The Heartbeat below also rewrote BackgroundColor3 every frame, so a hover
			-- tween would have been overwritten before it landed -- the button was left
			-- on AutoButtonColor's flat engine highlight, the one control in the tree
			-- not on the shared curve. Label and both tints derive from IsLaunching
			-- instead, and the write is skipped while the state has not moved, so the
			-- Heartbeat no longer restarts a tween sixty times a second.
			local LAUNCH_IDLE = Color3.fromRGB(200, 50, 50)
			local LAUNCH_ARMED = Color3.fromRGB(50, 150, 200)
			local l_hover, l_painted = false, nil
			local function paint_launch()
				local armed = x1.IsLaunching and true or false
				local key = tostring(armed) .. tostring(l_hover)
				if l_painted == key then
					return
				end
				l_painted = key
				local base = armed and LAUNCH_ARMED or LAUNCH_IDLE
				l_btn.Text = armed and "RESET SYSTEM" or "FORCE LAUNCH"
				v6:Create(l_btn, A.HOVER, {
					BackgroundColor3 = l_hover and brighten(base, 0.22) or base,
				}):Play()
			end
			-- Runs once here as well, because the constructor above hardcodes the idle
			-- red: opening the panel with IsLaunching already true showed a red button
			-- reading FORCE LAUNCH until the next frame corrected it.
			paint_launch()
			l_btn.MouseEnter:Connect(function()
				l_hover = true
				paint_launch()
			end)
			l_btn.MouseLeave:Connect(function()
				l_hover = false
				paint_launch()
			end)
			UI_elements.press(l_btn)

			l_btn.MouseButton1Click:Connect(function()
				x1.IsLaunching = not x1.IsLaunching
				paint_launch()
			end)

			table.insert(
				x6.f1_connections,
				v3.Heartbeat:Connect(function()
					if x1.k6 == "Slingshot" and x1.SlingshotManual == true then
						l_btn.Visible = true
						paint_launch()
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

			local tdb = Instance.new("TextButton", gsc)
			tdb.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
			tdb.Size = UDim2.new(1, 0, 0, 38)
			tdb.Text = "  " .. tn:upper()
			tdb.TextColor3 = Color3.fromRGB(255, 255, 255)
			tdb.Font = Enum.Font.GothamBold
			tdb.TextSize = 12
			tdb.TextXAlignment = 0
			-- A long DisplayName plus the "TARGET: " prefix reaches the clear × that
			-- appears at the right end whenever a target is set.
			tdb.TextTruncate = Enum.TextTruncate.AtEnd
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

			-- Repaints only what the target list feeds -- this button's label and the
			-- HUD -- so a selection does not have to go through f1(), which destroys
			-- and rebuilds the picker hidden. Re-closed over tdb on every f1, so it
			-- always points at the live button. The × affordance appears on the next
			-- real rebuild, which is enough: clearing is one click on an open list.
			x5.refresh_body = function()
				local label = "Select Target"
				if x1.Targets and #x1.Targets > 0 then
					if #x1.Targets == 1 then
						local t1 = x1.Targets[1]
						label = "Target: " .. (t1.DisplayName or t1.Name)
					else
						label = "Multi-Target (" .. tostring(#x1.Targets) .. ")"
					end
				end
				if tdb and tdb.Parent then
					tdb.Text = "  " .. label:upper()
				end
			end

			if x1.Targets and #x1.Targets > 0 then
				local ctb = Instance.new("TextButton", tdb)
				ctb.BackgroundTransparency = 1
				ctb.Position = UDim2.new(1, -30, 0, 0)
				ctb.Size = UDim2.new(0, 30, 1, 0)
				ctb.Text = "×"
				local ctb_idle = Color3.fromRGB(200, 80, 80)
				ctb.TextColor3 = ctb_idle
				ctb.TextSize = 20
				-- Transparent, so AutoButtonColor had no background to tint and this
				-- gave nothing back at all. It also sits on top of tdb and swallows
				-- that button's hover, so the row tint is driven from here too.
				hover_proxy(ctb, tdb, Color3.fromRGB(25, 25, 30), Color3.fromRGB(35, 35, 40))
				glyph_hover(ctb, ctb_idle, brighten(ctb_idle, 0.3))
				UI_elements.press(ctb, 0.9)
				ctb.MouseButton1Click:Connect(function()
					table.clear(x1.Targets)
					x1.TgtActive = false
					f1()
				end)
			end

			if m:FindFirstChild("TargetListContainer") then
				m.TargetListContainer:Destroy()
			end
			local tdlst = Instance.new("CanvasGroup", m)
			tdlst.Name = "TargetListContainer"
			tdlst.Visible = false
			tdlst.GroupTransparency = 1
			tdlst.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
			tdlst.Position = UDim2.new(1, 15, 0, 0)
			tdlst.Size = UDim2.new(0, 220, 1, 0)
			Instance.new("UICorner", tdlst).CornerRadius = UDim.new(0, 10)
			local ts = Instance.new("UIStroke", tdlst)
			ts.Color = Color3.fromRGB(40, 40, 45)

			local search_bar = Instance.new("TextBox", tdlst)
			search_bar.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
			search_bar.Position = UDim2.new(0, 10, 0, 10)
			search_bar.Size = UDim2.new(1, -20, 0, 34)
			search_bar.PlaceholderText = "Search players..."
			search_bar.Text = ""
			search_bar.TextColor3 = Color3.fromRGB(255, 255, 255)
			search_bar.Font = Enum.Font.Gotham
			search_bar.TextSize = 13
			Instance.new("UICorner", search_bar).CornerRadius = UDim.new(0, 6)

			local scroll_frame = Instance.new("ScrollingFrame", tdlst)
			scroll_frame.BackgroundTransparency = 1
			scroll_frame.Position = UDim2.new(0, 0, 0, 55)
			scroll_frame.Size = UDim2.new(1, 0, 1, -65)
			scroll_frame.ScrollBarThickness = 0
			scroll_frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
			local tdll = Instance.new("UIListLayout", scroll_frame)
			tdll.Padding = UDim.new(0, 5)
			tdll.HorizontalAlignment = Enum.HorizontalAlignment.Center

			local active_highlight = nil
			local function clear_highlight()
				if active_highlight then
					active_highlight:Destroy()
					active_highlight = nil
				end
			end

			local function update_list(filter_text)
				clear_highlight()
				scroll_frame:ClearAllChildren()
				local tdll = Instance.new("UIListLayout", scroll_frame)
				tdll.Padding = UDim.new(0, 5)
				tdll.HorizontalAlignment = Enum.HorizontalAlignment.Center

				for _, pl in ipairs(v2:GetPlayers()) do
					if pl == v8 then
						continue
					end
					if
						filter_text ~= ""
						and not (
							pl.DisplayName:lower():find(filter_text:lower(), 1, true) or pl.Name:lower():find(filter_text:lower(), 1, true)
						)
					then
						continue
					end

					local ib = Instance.new("TextButton", scroll_frame)
					ib.Size = UDim2.new(1, -16, 0, 44)
					ib.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
					ib.Text = ""
					ib.AutoButtonColor = false
					Instance.new("UICorner", ib).CornerRadius = UDim.new(0, 6)
					
					local is_selected = table.find(x1.Targets, pl) ~= nil
					local sel_indicator = Instance.new("Frame", ib)
					sel_indicator.Position = UDim2.new(1, -24, 0.5, -6)
					sel_indicator.Size = UDim2.new(0, 12, 0, 12)
					sel_indicator.BackgroundColor3 = is_selected and Color3.fromRGB(60, 200, 100) or Color3.fromRGB(60, 60, 65)
					Instance.new("UICorner", sel_indicator).CornerRadius = UDim.new(1, 0)

					local pfp = Instance.new("ImageLabel", ib)
					pfp.Size = UDim2.new(0, 32, 0, 32)
					pfp.Position = UDim2.new(0, 6, 0.5, -16)
					pfp.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
					pfp.Image = "rbxthumb://type=AvatarHeadShot&id=" .. pl.UserId .. "&w=48&h=48"
					Instance.new("UICorner", pfp).CornerRadius = UDim.new(1, 0)

					local dname = Instance.new("TextLabel", ib)
					dname.BackgroundTransparency = 1
					dname.Position = UDim2.new(0, 46, 0, 6)
					dname.Size = UDim2.new(1, -54, 0, 16)
					dname.Text = pl.DisplayName
					dname.TextColor3 = Color3.fromRGB(255, 255, 255)
					dname.Font = Enum.Font.GothamBold
					dname.TextSize = 13
					dname.TextXAlignment = 0

					local uname = Instance.new("TextLabel", ib)
					uname.BackgroundTransparency = 1
					uname.Position = UDim2.new(0, 46, 0, 22)
					uname.Size = UDim2.new(1, -54, 0, 14)
					uname.Text = "@" .. pl.Name
					uname.TextColor3 = Color3.fromRGB(150, 150, 150)
					uname.Font = Enum.Font.GothamMedium
					uname.TextSize = 10
					uname.TextXAlignment = 0

					ib.MouseEnter:Connect(function()
						-- Tweened on the shared curve, like every other row. This one set
						-- the colour outright, which is why it read snappier than the rest
						-- of the tree in a way nobody chose.
						v6:Create(ib, A.HOVER, { BackgroundColor3 = Color3.fromRGB(35, 35, 40) }):Play()
						-- Cleared first: moving the pointer fast enough gets the next
						-- row's MouseEnter in before this row's MouseLeave, and the
						-- single-slot handle would otherwise drop the older one
						-- unreachable while it stayed parented to its character.
						clear_highlight()
						if pl.Character then
							local h = Instance.new("Highlight")
							h.FillColor = Color3.fromRGB(255, 255, 255)
							h.OutlineColor = Color3.fromRGB(255, 255, 255)
							-- Adopted by the row rather than the character, so the
							-- teardown below takes it with it. Clicking a row calls
							-- f1(), which Destroy()s this whole list, and a Destroy
							-- fires no MouseLeave -- so a highlight parented to the
							-- character outlived the only handle to it and left that
							-- player glowing for the rest of the session.
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
						-- Repaint the HUD and the panel body, but leave this list alone.
						-- f1() destroys and rebuilds the picker hidden, so selecting three
						-- players meant reopening it three times -- and the two
						-- sel_indicator writes above were dead work, overwritten by a
						-- rebuild microseconds later. Any typed search text survives too.
						if x5.refresh_body then
							x5.refresh_body()
						end
					end)
				end
			end

			table.insert(x6.f1_connections, search_bar:GetPropertyChangedSignal("Text"):Connect(function()
				update_list(search_bar.Text)
			end))
			tdb.MouseButton1Click:Connect(function()
				local new_state = not tdlst.Visible
				if x6.dlst_container and x6.dlst_container.Visible then
					toggle_window(x6.dlst_container, false, true)
				end
				toggle_window(tdlst, new_state, true)
				if new_state then
					update_list("")
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
							-- branches already do. Without it a Toggle whose key is
							-- missing from config.lua draws itself ON from its Default
							-- while the shape keeps reading c[key] as nil and behaves
							-- OFF, and the two only agree once the user clicks it.
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
			reset_btn.Size = UDim2.new(1, 0, 0, 40)
			reset_btn.Text = "⚠ RESET ALL SETTINGS"
			reset_btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			reset_btn.Font = Enum.Font.GothamBold
			reset_btn.TextSize = 13
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
				confirm.Position = UDim2.new(0.5, -160, 0.5, -100)
				confirm.Size = UDim2.new(0, 320, 0, 200)
				confirm.GroupTransparency = 1
				confirm.ZIndex = 100
				Instance.new("UICorner", confirm).CornerRadius = UDim.new(0, 12)
				local confirm_stroke = Instance.new("UIStroke", confirm)
				confirm_stroke.Color = Color3.fromRGB(120, 40, 40)
				confirm_stroke.Thickness = 1

				local warning_icon = Instance.new("TextLabel", confirm)
				warning_icon.BackgroundTransparency = 1
				warning_icon.Position = UDim2.new(0.5, -15, 0, 15)
				warning_icon.Size = UDim2.new(0, 30, 0, 30)
				warning_icon.Text = "⚠"
				warning_icon.TextColor3 = Color3.fromRGB(255, 100, 100)
				warning_icon.TextSize = 24
				warning_icon.ZIndex = 101

				local confirm_title = Instance.new("TextLabel", confirm)
				confirm_title.BackgroundTransparency = 1
				confirm_title.Position = UDim2.new(0, 20, 0, 50)
				confirm_title.Size = UDim2.new(1, -40, 0, 30)
				confirm_title.Text = "RESET ALL SETTINGS?"
				confirm_title.TextColor3 = Color3.fromRGB(255, 255, 255)
				confirm_title.Font = Enum.Font.GothamBold
				confirm_title.TextSize = 16
				confirm_title.ZIndex = 101

				local confirm_desc = Instance.new("TextLabel", confirm)
				confirm_desc.BackgroundTransparency = 1
				confirm_desc.Position = UDim2.new(0, 20, 0, 80)
				confirm_desc.Size = UDim2.new(1, -40, 0, 40)
				confirm_desc.Text = "This will reset all settings and shape configurations to their default values. This cannot be undone."
				confirm_desc.TextColor3 = Color3.fromRGB(150, 150, 160)
				confirm_desc.Font = Enum.Font.Gotham
				confirm_desc.TextSize = 12
				confirm_desc.TextWrapped = true
				confirm_desc.ZIndex = 101

				local cancel_btn = Instance.new("TextButton", confirm)
				cancel_btn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
				cancel_btn.Position = UDim2.new(0, 20, 1, -50)
				cancel_btn.Size = UDim2.new(0.5, -30, 0, 36)
				cancel_btn.Text = "CANCEL"
				cancel_btn.TextColor3 = Color3.fromRGB(200, 200, 210)
				cancel_btn.Font = Enum.Font.GothamBold
				cancel_btn.TextSize = 12
				cancel_btn.AutoButtonColor = false
				cancel_btn.ZIndex = 101
				Instance.new("UICorner", cancel_btn).CornerRadius = UDim.new(0, 6)
				local cancel_stroke = Instance.new("UIStroke", cancel_btn)
				cancel_stroke.Color = Color3.fromRGB(50, 50, 55)
				-- Both of these turned AutoButtonColor off and put nothing in its place,
				-- so the one dialog in the tree where being sure which button is under
				-- the pointer actually matters was also the only pair that gave no
				-- feedback at all. Same helper and same curve as every other button.
				row_hover(
					cancel_btn,
					Color3.fromRGB(30, 30, 35),
					Color3.fromRGB(45, 45, 52),
					cancel_stroke,
					Color3.fromRGB(50, 50, 55),
					Color3.fromRGB(80, 80, 88)
				)
				UI_elements.press(cancel_btn)

				local confirm_reset_btn = Instance.new("TextButton", confirm)
				confirm_reset_btn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
				confirm_reset_btn.Position = UDim2.new(0.5, 10, 1, -50)
				confirm_reset_btn.Size = UDim2.new(0.5, -30, 0, 36)
				confirm_reset_btn.Text = "RESET"
				confirm_reset_btn.TextColor3 = Color3.fromRGB(255, 255, 255)
				confirm_reset_btn.Font = Enum.Font.GothamBold
				confirm_reset_btn.TextSize = 12
				confirm_reset_btn.AutoButtonColor = false
				confirm_reset_btn.ZIndex = 101
				Instance.new("UICorner", confirm_reset_btn).CornerRadius = UDim.new(0, 6)
				local confirm_reset_stroke = Instance.new("UIStroke", confirm_reset_btn)
				confirm_reset_stroke.Color = Color3.fromRGB(120, 30, 30)
				row_hover(
					confirm_reset_btn,
					Color3.fromRGB(180, 40, 40),
					Color3.fromRGB(215, 55, 55),
					confirm_reset_stroke,
					Color3.fromRGB(120, 30, 30),
					Color3.fromRGB(170, 45, 45)
				)
				UI_elements.press(confirm_reset_btn)

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
				-- because a UIScale grows a frame from its top-left corner, which
				-- would walk a centred dialog off-centre as the scale went up.
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

		local dlst_container = Instance.new("CanvasGroup", m)
		dlst_container.Name = "ModeSelector"
		dlst_container.Visible = false
		dlst_container.GroupTransparency = 1
		dlst_container.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
		dlst_container.Position = UDim2.new(1, 15, 0, 0)
		dlst_container.Size = UDim2.new(0, 220, 1, 0)
		Instance.new("UICorner", dlst_container).CornerRadius = UDim.new(0, 10)
		local dls = Instance.new("UIStroke", dlst_container)
		dls.Color = Color3.fromRGB(40, 40, 45)

		local msb = Instance.new("TextBox", dlst_container)
		msb.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		msb.Position = UDim2.new(0, 10, 0, 10)
		msb.Size = UDim2.new(1, -20, 0, 34)
		msb.PlaceholderText = "Search modes..."
		msb.Text = ""
		msb.TextColor3 = Color3.fromRGB(255, 255, 255)
		msb.Font = Enum.Font.Gotham
		msb.TextSize = 13
		Instance.new("UICorner", msb).CornerRadius = UDim.new(0, 6)

		local dlst = Instance.new("ScrollingFrame", dlst_container)
		dlst.BackgroundTransparency = 1
		dlst.Position = UDim2.new(0, 0, 0, 55)
		dlst.Size = UDim2.new(1, 0, 1, -65)
		dlst.ScrollBarThickness = 0
		dlst.AutomaticCanvasSize = Enum.AutomaticSize.Y
		dlst.CanvasSize = UDim2.new(0, 0, 0, 0)

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
				-- Plain search, like populate_keybinds:756. Without the flag the typed
				-- text is a Lua pattern, so a single "(" throws "unfinished capture"
				-- out of the Text callback -- after dlst:ClearAllChildren() has already
				-- run, so the list stays empty and every further keystroke re-errors.
				if filter ~= "" and not mn:lower():find(filter:lower(), 1, true) then
					continue
				end

				local f = Instance.new("Frame", dlst)
				f.Size = UDim2.new(1, -16, 0, 40)
				local row_on = mn == x1.k6
				f.BackgroundColor3 = row_on and Color3.fromRGB(40, 40, 180) or Color3.fromRGB(25, 25, 30)
				Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
				-- idle passed in rather than read back, so the selected row keeps its tint
				-- when the pointer leaves. Hoisted because the label and the star cover
				-- this Frame completely and have to drive the same pair.
				local row_idle = f.BackgroundColor3
				local row_hot = row_on and Color3.fromRGB(55, 55, 200) or Color3.fromRGB(35, 35, 40)
				row_hover(f, row_idle, row_hot)

				local ib = Instance.new("TextButton", f)
				ib.Size = UDim2.new(1, -40, 1, 0)
				ib.Position = UDim2.new(0, 8, 0, 0)
				ib.BackgroundTransparency = 1
				ib.Text = "  " .. mn
				ib.TextColor3 = Color3.fromRGB(255, 255, 255)
				ib.Font = Enum.Font.GothamBold
				ib.TextSize = 12
				ib.TextXAlignment = 0
				-- Part Control's identical row already truncated; this one did not, so
				-- "Domain Expansion Infinite Void" ran straight across the star and out
				-- past the row's right edge -- nothing here clips it.
				ib.TextTruncate = Enum.TextTruncate.AtEnd
				hover_proxy(ib, f, row_idle, row_hot)

				local sb = Instance.new("TextButton", f)
				sb.Position = UDim2.new(1, -35, 0, 0)
				sb.Size = UDim2.new(0, 35, 1, 0)
				sb.BackgroundTransparency = 1
				sb.Text = favorites[mn] and "★" or "☆"
				local sb_idle = favorites[mn] and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(80, 80, 85)
				sb.TextColor3 = sb_idle
				sb.Font = Enum.Font.GothamBold
				sb.TextSize = 14
				hover_proxy(sb, f, row_idle, row_hot)
				glyph_hover(sb, sb_idle, brighten(sb_idle, 0.35))
				UI_elements.press(sb, 0.9)

				sb.MouseButton1Click:Connect(function()
					favorites[mn] = not favorites[mn]
					save_favs()
					populate_modes(filter)
				end)

				ib.MouseButton1Click:Connect(function()
					local x4 = context.x4
					if x4 and x4.switch_shape then
						if x4.switch_shape(mn) and db then
							db.Text = "  " .. mn:upper()
						end
					else
						-- fallback before System is up
						local shape = get_shape(mn)
						if shape then
							-- switch_shape owns this notice on the normal path; repeat it
							-- here because this branch sets k6 itself and never reaches it.
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
							save_settings()
							if x5.up then
								x5.up()
							end
						end
					end
					toggle_window(dlst_container, false, true)
				end)
			end
		end

		msb:GetPropertyChangedSignal("Text"):Connect(function()
			populate_modes(msb.Text)
		end)

		x6.populate_modes = populate_modes
		x6.mode_filter = function()
			return msb and msb.Text or ""
		end
		populate_modes("")

		-- System calls this after every shape switch, including one driven by a
		-- hotkey while the mode list was never opened, so the dropdown label and
		-- the highlighted row cannot fall out of step with x1.k6.
		function x5.sync_shape(name)
			if db then
				db.Text = "  " .. tostring(name):upper()
			end
			if dlst_container and dlst_container.Visible then
				populate_modes(msb.Text)
			end
		end

		-- Declared ahead of the header buttons because their click handlers close
		-- over it: while the panel is a pill every extra is invisible but still
		-- hit-testable, and stacked on top of minb. See set_header_extras below.
		local collapsed = false

		-- All four through circle_btn, so they carry a glyph and the same hover/press
		-- feedback as everything else. Minimize and close were both blank circles before,
		-- told apart only by colour.
		local minb = circle_btn(h, Color3.fromRGB(60, 200, 100), "–", 16)
		minb.Position = UDim2.new(1, -60, 0.5, -10)

		local dcb = circle_btn(h, Color3.fromRGB(88, 101, 242), "D", 11)
		dcb.Position = UDim2.new(1, -120, 0.5, -10)
		dcb.MouseButton1Click:Connect(function()
			if collapsed then return end
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

		local tutb = circle_btn(h, Color3.fromRGB(50, 150, 200), "?", 14)
		tutb.Position = UDim2.new(1, -90, 0.5, -10)

		local tut_container = Instance.new("CanvasGroup", sg)
		tut_container.Name = "Tutorial"
		tut_container.Visible = false
		tut_container.GroupTransparency = 1
		tut_container.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
		tut_container.Position = UDim2.new(0.5, -200, 0.5, -150)
		tut_container.Size = UDim2.new(0, 400, 0, 300)
		tut_container.Active = true
		Instance.new("UICorner", tut_container).CornerRadius = UDim.new(0, 10)
		local tuls = Instance.new("UIStroke", tut_container)
		tuls.Color = Color3.fromRGB(40, 40, 45)

		local tut_header = Instance.new("Frame", tut_container)
		tut_header.BackgroundTransparency = 1
		tut_header.Size = UDim2.new(1, 0, 0, 40)
		make_draggable(tut_container, tut_header)
		
		local tut_title = Instance.new("TextLabel", tut_header)
		tut_title.BackgroundTransparency = 1
		tut_title.Position = UDim2.new(0, 20, 0, 0)
		tut_title.Size = UDim2.new(0.8, 0, 1, 0)
		tut_title.Text = "HOW TO USE PROJECT GRAVITY"
		tut_title.TextColor3 = Color3.fromRGB(255, 255, 255)
		tut_title.Font = Enum.Font.GothamBlack
		tut_title.TextSize = 14
		tut_title.TextXAlignment = 0

		local tut_close = circle_btn(tut_header, Color3.fromRGB(200, 60, 60), "×", 14)
		tut_close.Position = UDim2.new(1, -30, 0.5, -10)
		tut_close.MouseButton1Click:Connect(function()
			toggle_window(tut_container, false)
		end)

		local tut_text = Instance.new("TextLabel", tut_container)
		tut_text.BackgroundTransparency = 1
		tut_text.Position = UDim2.new(0, 20, 0, 50)
		tut_text.Size = UDim2.new(1, -40, 1, -70)
		tut_text.Text = ""
		tut_text.TextColor3 = Color3.fromRGB(200, 200, 205)
		tut_text.Font = Enum.Font.GothamMedium
		tut_text.TextSize = 12
		tut_text.TextXAlignment = 0
		tut_text.TextYAlignment = 0
		tut_text.TextWrapped = true

		-- Built at open time rather than baked in. Every key named here is rebindable and
		-- this text said E/Q/P/L regardless, so it was wrong for anyone who had ever
		-- opened the Keybinds window -- and it predated both tools it now covers.
		local function key_label(id)
			local kb = x1.Keybinds
			local k = type(kb) == "table" and kb[id]
			if type(k) == "string" and k ~= "" then
				return "'" .. k .. "'"
			end
			return "(unbound -- set it in Keybinds)"
		end

		local function refresh_tutorial()
			tut_text.Text = table.concat({
				"• Core: " .. key_label("Recenter") .. " moves the gravity centre to your cursor, "
					.. key_label("Reset") .. " releases every part and removes it. Hold left click on the "
					.. "core itself to drag it around.",
				"• " .. key_label("Pause") .. " freezes held parts where they are. " .. key_label("Disable")
					.. " lets them fall without giving up the claim.",
				"• Targeting: 'Select Target' focuses the pull on one player; Target Everyone spreads the "
					.. "parts across all of them.",
				"• Modes: the selector morphs between formations. Scroll the main panel for that shape's "
					.. "own controls.",
				"• Part Control: click a held part to select it (selecting alone changes nothing), drag it "
					.. "to place it, then pick Pin, Manual or Assign Shape. The box colour is the mode.",
				"• Sculptor: choose it as the shape to arrange parts by hand with box-select and drag.",
				"• Advanced Settings holds the global physics limits, the FPS cap and the performance "
					.. "switches.",
			}, "\n\n")
		end
		refresh_tutorial()

		tutb.MouseButton1Click:Connect(function()
			if collapsed then return end
			local opening = not tut_container.Visible
			if opening then
				-- Re-read the keybinds, in case they changed since the last open.
				refresh_tutorial()
			end
			toggle_window(tut_container, opening)
		end)

		local closeb = circle_btn(h, Color3.fromRGB(200, 60, 60), "×", 14)
		closeb.Name = "UnloadProjectGravity"
		closeb.Position = UDim2.new(1, -30, 0.5, -10)

		-- Minimize runs in two stages: the body rolls up into the header, then
		-- the header folds left into a round pill holding just this button.
		-- Maximize is the inverse, and the order matters -- the header has to be
		-- back at full width before the body rolls down, or the content is laid
		-- out against a 44px frame and every label wraps.
		local im = false
		-- The stages are chained on Completed, so a second click mid-flight would
		-- start the opposite sequence while tweens from the first are still
		-- running and leave the panel stuck at an intermediate size.
		local anim_busy = false
		-- Where the body was scrolled to when the panel collapsed; nil when the
		-- panel is open and there is nothing banked. See roll_up.
		local saved_canvas = nil

		local ROLL, FOLD, UNFOLD = A.ROLL, A.FOLD, A.UNFOLD

		-- The header extras all vanish for the pill and come back with it.
		-- Transparency alone is not enough: a fully transparent TextButton still
		-- takes clicks, and once the panel is pill-width closeb's (1,-30) anchor
		-- lands on top of minb -- so a click meant to restore would tear the UI
		-- down instead. Visible is the only thing that removes them from
		-- hit-testing, but it cannot be driven off the fade alone: the fade runs
		-- 0.4s while the panel is already narrowing underneath it, and the
		-- unfold has to make them visible again up front so they can fade in.
		-- collapsed (declared above the header buttons) is the authority for
		-- hit-testing, flipped the instant the button is pressed.
		local extras = { dcb, tutb, closeb }
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
						-- Not if a fast re-click already started fading them back.
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
			v6:Create(minb, FOLD, { Position = UDim2.new(0.5, -10, 0.5, -10) }):Play()
			-- h carries an absolute height, so it has to come down with the panel
			-- or minb's 0.5 anchor centres against 50px inside a 44px pill.
			v6:Create(h, FOLD, { Size = UDim2.new(1, 0, 0, PILL_SIZE) }):Play()
			v6:Create(mcorner, FOLD, { CornerRadius = UDim.new(0, PILL_SIZE / 2) }):Play()
			local tw = v6:Create(m, FOLD, { Size = UDim2.new(0, PILL_SIZE, 0, PILL_SIZE) })
			local conn
			conn = tw.Completed:Connect(function()
				anim_busy = false
				if conn then conn:Disconnect() end
			end)
			tw:Play()
		end

		local function roll_up()
			-- Clipped rather than hidden, so the body is cut off as the panel
			-- shrinks instead of vanishing a frame before the tween starts.
			m.ClipsDescendants = true
			-- The scroll offset has to be banked before the body shrinks. c is
			-- sized against m, so collapsing drives its height to zero, and a
			-- ScrollingFrame clamps CanvasPosition against its own window size --
			-- at zero height that clamp stops holding the offset anywhere sensible.
			-- Restoring from a stale value is what left the panel reopening onto
			-- the middle of the list, or past the end of it entirely, whenever it
			-- was minimized from anywhere but the very top.
			saved_canvas = c.CanvasPosition
			c.CanvasPosition = Vector2.new(0, 0)
			-- Every side panel, through the registry: Part Control used to be missed
			-- here, so minimising to the pill left it floating on screen with its
			-- click handlers still armed and no panel to disarm them from.
			for win in pairs(side_panels) do
				if win.Visible then
					close_side_panel(win)
				end
			end
			if tut_container.Visible then toggle_window(tut_container, false) end
			if x6.dlst_container and x6.dlst_container.Visible then
				toggle_window(x6.dlst_container, false, true)
			end
			if m:FindFirstChild("TargetListContainer") and m.TargetListContainer.Visible then
				toggle_window(m.TargetListContainer, false, true)
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
				-- The else is unreachable while anim_busy holds across both
				-- stages, but skipping stage 2 without clearing the guard would
				-- wedge the button dead with the panel stranded half-collapsed.
				if im then
					fold_to_pill()
				else
					anim_busy = false
				end
			end)
			tw:Play()
		end

		local function roll_down()
			local tw = v6:Create(m, ROLL, { Size = UDim2.new(0, PANEL_W, 0, PANEL_H) })
			local conn
			conn = tw.Completed:Connect(function()
				if conn then conn:Disconnect() end
				-- Only now: the nested mode selector and target list sit outside
				-- Main's bounds, so leaving this on would clip them away.
				m.ClipsDescendants = false
				-- Put the reader back where they left off, now that the body is at
				-- full height again and the clamp means something. Deferred to the
				-- end of the tween for the same reason.
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
			-- 36px shorter than the viewport, and the expanded panel is
			-- PANEL_* * app_scale() because UIScale grows m from its top-left.
			-- AbsolutePosition and AbsoluteSize are both post-scale and relative
			-- to the real parent, so they carry the inset and the scale already.
			local parent = m.Parent
			local avail = (parent and parent.AbsoluteSize) or Vector2.new(1280, 720)
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
			v6:Create(minb, UNFOLD, { Position = UDim2.new(1, -60, 0.5, -10) }):Play()
			v6:Create(h, UNFOLD, { Size = UDim2.new(1, 0, 0, HEADER_H) }):Play()
			v6:Create(mcorner, UNFOLD, { CornerRadius = UDim.new(0, 10) }):Play()
			local tw = v6:Create(m, UNFOLD, { Size = UDim2.new(0, PANEL_W, 0, HEADER_H) })
			local conn
			conn = tw.Completed:Connect(function()
				if conn then conn:Disconnect() end
				-- As in roll_up: unreachable today, but skipping stage 2 here
				-- would also strand ClipsDescendants on, and that is the one
				-- thing that hides the mode selector on an expanded panel.
				if not im then
					roll_down()
				else
					m.ClipsDescendants = false
					anim_busy = false
				end
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
			-- fold, and this is what makes their handlers ignore the press.
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

		-- The body lives entirely inside f1, so without this the panel comes up
		-- holding only the header buttons and the mode dropdown: no toggles, no
		-- target selector, no shape controls, no reset. It used to fill in only
		-- once something called x5.st() a second time -- recenter or stop -- which
		-- read as the panel being half-built until the first keypress.
		f1()
	end

	return x5
end
