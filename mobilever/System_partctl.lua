return function(context, x7)
	local v1, v4, v8 = context.v1, context.v4, context.v8
	local x1, x6, x2 = context.x1, context.x6, context.x2
	local get_shape = context.get_shape
	local ShapePhysics = context.shape_physics or context.load_module("ShapePhysics.lua")

	x6.pc_selected = x6.pc_selected or setmetatable({}, { __mode = "k" })
	x6.pc_highlights = x6.pc_highlights or setmetatable({}, { __mode = "k" })
	x6.pc_offsets = x6.pc_offsets or setmetatable({}, { __mode = "k" })
	x6.pc_mods = x6.pc_mods or {}
	x6.pc_api_version = 1 -- guarded external assignments and complete release_all

	local RIDE_PHYSICS = PhysicalProperties.new(0.7, 0.5, 0.3, 1, 1)
	local LIGHT_PHYSICS = PhysicalProperties.new(0.001, 0, 0, 0, 0)
	local function pc_apply_physics(part, d)
		ShapePhysics.apply_collisions(part, d, x1)
		if x1.Disabled or d.free_physics then
			part.CustomPhysicalProperties = d.original_properties
		elseif d.pc_ride then
			part.CustomPhysicalProperties = d.original_properties or RIDE_PHYSICS
		else
			part.CustomPhysicalProperties = LIGHT_PHYSICS
		end
	end
	local HL_COLOR = Color3.fromRGB(255, 170, 0)
	-- Selected, and what it is doing. The panel could only ever say "3 selected,
	-- 7 overridden"; the colour is what tells you which of the boxes in front of you
	-- is pinned, which is being dragged, and which a shape is driving.
	local MODE_COLOR = {
		pin = Color3.fromRGB(255, 80, 80),
		manual = Color3.fromRGB(80, 170, 255),
		shape = Color3.fromRGB(190, 110, 255),
	}
	-- How far the finger has to travel before a tap becomes a drag. Larger than the
	-- desktop tree's 6 px because a touch never holds still. Without a threshold every
	-- tap was a drag and every drag latched an override, so merely selecting a part
	-- pinned it -- including with the panel's own mode row reading "Normal (No
	-- Override)".
	local DRAG_PX = 10
	-- A ceiling on the selection. Every selected part carries its own SelectionBox, so
	-- a bulk select over a five-thousand-part claim would build five thousand
	-- adornments in a single frame -- a visible hitch, and far more parts than anyone
	-- is going to place by hand on a phone.
	local MAX_SELECT = 512

	-- The panel shows a live selection count and tints the active mode, so every
	-- path that changes either has to say so. One hook rather than a signal per
	-- field: the UI only ever wants "something changed, re-read x6".
	local function pc_changed()
		if x6.pc_on_change then
			pcall(x6.pc_on_change)
		end
	end

	-- The colour is read off the part's own record rather than passed in, so every
	-- path that changes a mode only has to repaint; it does not have to know what
	-- the mode became.
	local function pc_highlight_color(part)
		local d = x6.a and x6.a[part]
		return (d and d.pc_mode and MODE_COLOR[d.pc_mode]) or HL_COLOR
	end

	local function pc_paint_highlight(part)
		local highlight = x6.pc_highlights[part]
		if not highlight then
			return
		end
		local col = pc_highlight_color(part)
		if highlight.Color3 ~= col then
			highlight.Color3 = col
			highlight.SurfaceColor3 = col
		end
	end

	local function pc_add_highlight(part)
		if x6.pc_highlights[part] then
			pc_paint_highlight(part)
			return
		end
		local col = pc_highlight_color(part)
		local highlight = Instance.new("SelectionBox")
		highlight.Adornee = part
		highlight.Color3 = col
		highlight.LineThickness = 0.05
		highlight.SurfaceTransparency = 0.8
		highlight.SurfaceColor3 = col
		highlight.Parent = part
		x6.pc_highlights[part] = highlight
	end

	local function pc_remove_highlight(part)
		if x6.pc_highlights[part] then
			pcall(function()
				x6.pc_highlights[part]:Destroy()
			end)
			x6.pc_highlights[part] = nil
		end
	end

	-- One owner for the refcount, called from both pc_assign and pc_release. It
	-- used to be inlined in both, so clearing a mode ran it twice for the same
	-- part: pc_assign decremented before dispatching, then pc_release decremented
	-- again, and cleanup fired while other parts were still driving the module.
	local function pc_unref_mod(d)
		local mod = d.pc_mod
		if not mod then
			return
		end
		local n = x6.pc_mods[mod]
		if not n then
			return
		end
		n = n - 1
		if n > 0 then
			x6.pc_mods[mod] = n
			return
		end
		x6.pc_mods[mod] = nil
		-- Held only so the px pre-pass can find the assignment's own config; a
		-- live reference to a config table outlives the last part without this.
		mod.pc_cfg_ref = nil
		if mod.cleanup then
			pcall(mod.cleanup, x6, x1)
		end
	end

	local function pc_release(part)
		local d = x6.a and x6.a[part]
		if not d then
			return
		end
		pc_unref_mod(d)
		if d.pc_mode and x7.reset_scratch then x7.reset_scratch(d) end
		d.pc_mode = nil
		d.pc_target = nil
		d.pc_shape = nil
		d.pc_mod = nil
		d.pc_cfg = nil
		d.pc_phys = nil
		d.pc_ride = nil
		pcall(pc_apply_physics, part, d)
		-- Back to plain selection orange. A released part that is still selected has
		-- to stop claiming it is pinned.
		pc_paint_highlight(part)
	end
	x6.pc_release = pc_release

	-- Deselecting is not releasing: a pinned part stays pinned when the user taps
	-- elsewhere, which is the whole point of pinning it. pc_clear used to
	-- table.clear(pc_mods) instead, which dropped every refcount without calling
	-- a single cleanup and left the parts with pc_mode still set -- permanently
	-- exempt from the update bucket and the radius cull, driving a module whose
	-- px was no longer being called, and unreachable because the selection they
	-- would have been released through was gone.
	local function pc_clear_highlights()
		if x6.pc_highlights then
			for part, highlight in pairs(x6.pc_highlights) do
				if highlight and highlight.Parent then
					pcall(function()
						highlight:Destroy()
					end)
				end
			end
			table.clear(x6.pc_highlights)
		end
		if x6.pc_selected then
			table.clear(x6.pc_selected)
		end
		if x6.pc_offsets then
			table.clear(x6.pc_offsets)
		end
		x6.pc_dragging = false
		x6.pc_drag_target = nil
		x6.pc_drag_distance = nil
		x6.pc_drag_size = nil
		-- The pending press too, or a tap whose gesture is cancelled by a panel
		-- teardown leaves a part armed to start a drag on the next finger move.
		x6.pc_press = nil
		pc_changed()
	end
	x6.pc_clear = pc_clear_highlights

	-- Walks x6.a rather than the selection, because the parts that most need
	-- releasing are the ones no longer selected. Used by the panel's Release All,
	-- by a shape switch (the module a part is assigned to is torn down with it)
	-- and by teardown.
	local function pc_release_all()
		if not x6.a then
			return 0
		end
		local n = 0
		local arr = x6.active_array
		if arr then
			for i = #arr, 1, -1 do
				local p = arr[i]
				local d = p and x6.a[p]
				if d and (d.pc_mode or d.pc_ride or d.pc_phys) then
					pc_release(p)
					n = n + 1
				end
			end
		end
		-- active_array is the fast path but it is not authoritative: a part can be
		-- in x6.a without having made it into the dense array yet.
		for p, d in pairs(x6.a) do
			if d.pc_mode or d.pc_ride or d.pc_phys then
				pc_release(p)
				n = n + 1
			end
		end
		if x6.pc_mods then
			table.clear(x6.pc_mods)
		end
		if n > 0 then
			pc_changed()
		end
		return n
	end
	x6.pc_release_all = pc_release_all

	local function pc_select(part, add_to_selection)
		if not add_to_selection then
			for p, _ in pairs(x6.pc_selected) do
				pc_remove_highlight(p)
			end
			table.clear(x6.pc_selected)
			table.clear(x6.pc_offsets)
		end
		if part and x6.a and x6.a[part] then
			x6.pc_selected[part] = true
			pc_add_highlight(part)
		end
		pc_changed()
	end
	x6.pc_select = pc_select

	local function pc_deselect(part)
		x6.pc_selected[part] = nil
		x6.pc_offsets[part] = nil
		pc_remove_highlight(part)
		pc_changed()
	end
	x6.pc_deselect = pc_deselect

	-- Also the sweeper. x4.f2 nils x6.a[p] when a part is released, the SelectionBox
	-- is parented to the part, and pc_selected is weak-keyed -- so a part released
	-- while selected kept an orange box for as long as it lived and went on being
	-- counted by the panel with nothing behind it. This is the one function every
	-- panel refresh already calls, so it is where the prune belongs.
	local function pc_count()
		local n = 0
		if x6.pc_selected then
			for part in pairs(x6.pc_selected) do
				if x6.a and x6.a[part] then
					n = n + 1
				else
					x6.pc_selected[part] = nil
					if x6.pc_offsets then
						x6.pc_offsets[part] = nil
					end
					pc_remove_highlight(part)
				end
			end
		end
		return n
	end
	x6.pc_count = pc_count

	-- Bulk selection. This tree has no box-select at all, so these are the only way a
	-- touch user selects more than one part. Walking active_array rather than the weak
	-- hash keeps the order stable and skips entries the sweep has not reaped yet.
	local function pc_each_held(fn)
		local arr = x6.active_array
		if not arr then
			return
		end
		for i = 1, #arr do
			local p = arr[i]
			local d = p and x6.a and x6.a[p]
			if d then
				fn(p, d)
			end
		end
	end

	-- Each of the three returns (added, capped) so the panel can say when it stopped
	-- early rather than silently selecting some of what was asked for.
	local function pc_select_all()
		local n, added, capped = pc_count(), 0, false
		pc_each_held(function(p)
			if n >= MAX_SELECT then
				capped = true
				return
			end
			if not x6.pc_selected[p] then
				n = n + 1
				added = added + 1
			end
			x6.pc_selected[p] = true
			pc_add_highlight(p)
		end)
		pc_changed()
		return added, capped
	end
	x6.pc_select_all = pc_select_all

	-- Deselecting deliberately leaves an override in place, which means a part can be
	-- driven with no selection left to reach it through. Release All is the blunt way
	-- back; this is the one that lets you look at them first.
	local function pc_select_overridden()
		local n, added, capped = pc_count(), 0, false
		pc_each_held(function(p, d)
			if d.pc_mode or d.pc_ride or d.pc_phys then
				if n >= MAX_SELECT then
					capped = true
					return
				end
				if not x6.pc_selected[p] then
					n = n + 1
					added = added + 1
				end
				x6.pc_selected[p] = true
				pc_add_highlight(p)
			end
		end)
		pc_changed()
		return added, capped
	end
	x6.pc_select_overridden = pc_select_overridden

	local function pc_invert()
		local n, added, capped = pc_count(), 0, false
		pc_each_held(function(p)
			if x6.pc_selected[p] then
				x6.pc_selected[p] = nil
				n = n - 1
				if x6.pc_offsets then
					x6.pc_offsets[p] = nil
				end
				pc_remove_highlight(p)
			elseif n >= MAX_SELECT then
				capped = true
			else
				x6.pc_selected[p] = true
				pc_add_highlight(p)
				n = n + 1
				added = added + 1
			end
		end)
		pc_changed()
		return added, capped
	end
	x6.pc_invert = pc_invert

	-- The three modes the per-part loop in System.lua can actually dispatch.
	local VALID_MODES = { pin = true, manual = true, shape = true }

	local function pc_assign(mode, opts)
		if x6.torn_down then return 0 end
		opts = opts or {}
		-- Anything else is a release. "normal" is the panel's name for "no override"
		-- and used to be storable as a literal pc_mode: the loop has no branch for
		-- it, so the part fell through to the global shape but kept a non-nil
		-- pc_mode, which left it exempt from the update bucket and the radius cull
		-- for good.
		if mode ~= nil and not VALID_MODES[mode] then
			mode = nil
		end
		local mod = nil
		local shape_cfg = nil

		if mode == "shape" then
			if opts.shape == "Sculptor" then
				return 0
			end
			mod = get_shape and get_shape(opts.shape)
			if x6.torn_down then return 0 end
			if not mod or not mod.f2 then
				return 0
			end
			shape_cfg = (x2 and x2[opts.shape]) or (context.x2 and context.x2[opts.shape])
			if not shape_cfg and mod.Controls then
				shape_cfg = {}
				for _, ctrl in ipairs(mod.Controls) do
					if ctrl.Key and ctrl.Type ~= "Button" then
						local def = ctrl.Default
						if def == nil then
							if ctrl.Type == "Toggle" then def = false
							elseif ctrl.Type == "TextBox" then def = ""
							else def = (ctrl.Min or 0) / (ctrl.Div or 1) end
						end
						shape_cfg[ctrl.Key] = def
					end
				end
			end
		end

		-- A remote controller may have yielded while loading the shape. Do not
		-- apply its request to a newer session or to a changed selection.
		if opts.guard and not opts.guard() then return 0 end
		if mod then mod.pc_cfg_ref = shape_cfg end

		local count = 0
		for part, _ in pairs(x6.pc_selected) do
			local d = x6.a and x6.a[part]
			if d then
				pc_add_highlight(part)
				if mode == nil then
					-- pc_release owns the unref on this path.
					pc_release(part)
				else
					-- A released shape record must become controllable when pinned or
					-- assigned to another shape; keep free_active for the engine to rearm.
					if (d.pc_mode ~= mode or d.pc_mod ~= mod) and x7.reset_scratch then
						x7.reset_scratch(d)
					end
					if d.pc_mod and (mode ~= "shape" or d.pc_mod ~= mod) then
						pc_unref_mod(d)
						d.pc_mod = nil
					end
					d.pc_mode = mode
					if mode == "pin" then
						d.pc_target = opts.target or part.Position
						d.pc_shape = nil
						d.pc_mod = nil
						d.pc_cfg = nil
					elseif mode == "manual" then
						d.pc_target = opts.target or d.pc_target or part.Position
						d.pc_shape = nil
						d.pc_mod = nil
						d.pc_cfg = nil
					elseif mode == "shape" then
						d.pc_shape = opts.shape
						d.pc_cfg = shape_cfg
						-- Only when it is not already counted. The unref guard above
						-- deliberately skips a re-assignment of the same module, and this
						-- used to increment anyway -- so tapping Assign Shape twice, or
						-- toggling Rideable (which re-assigned), pushed pc_mods[mod] above
						-- the real part count for good. mod.cleanup only runs when the
						-- count reaches zero, so Platform's anchored pad and Raigo's input
						-- connections never came back.
						if d.pc_mod ~= mod then
							d.pc_mod = mod
							x6.pc_mods[mod] = (x6.pc_mods[mod] or 0) + 1
						end
					end

					if opts.phys ~= nil then
						-- false clears the override rather than storing a boolean the
						-- System loop would then index.
						d.pc_phys = (opts.phys ~= false) and opts.phys or nil
					end

					if opts.ride ~= nil then
						d.pc_ride = opts.ride and true or false
						pcall(pc_apply_physics, part, d)
					end
				end
				-- After the mode has settled, so the box takes the colour of what the
				-- part is now doing rather than what it was doing on the way in.
				pc_paint_highlight(part)
				count = count + 1
			end
		end

		if count > 0 then
			pc_changed()
		end
		return count
	end
	x6.pc_assign = pc_assign

	-- Riding is a property of the part, not of the mode. The panel's toggle used to
	-- call pc_assign with x1.PartCtlMode, which meant it did nothing at all while the
	-- mode was "normal" -- and on the other three it re-assigned the mode as a side
	-- effect, which is how a shape re-assignment and its refcount happened every time
	-- somebody flipped this.
	local function pc_set_ride(on)
		on = on and true or false
		local count = 0
		for part, _ in pairs(x6.pc_selected) do
			local d = x6.a and x6.a[part]
			if d then
				d.pc_ride = on
				pcall(pc_apply_physics, part, d)
				count = count + 1
			end
		end
		if count > 0 then
			pc_changed()
		end
		return count
	end
	x6.pc_set_ride = pc_set_ride

	-- Applies a physics override to the current selection without disturbing the
	-- mode. Values are nil to inherit the global setting; an all-nil table is
	-- stored as nil so the System loop's `d.pc_phys and ...` guards short out.
	local function pc_set_phys(phys)
		local live = nil
		if type(phys) == "table" then
			for _, v in pairs(phys) do
				if v ~= nil then
					live = phys
					break
				end
			end
		end
		local count = 0
		for part, _ in pairs(x6.pc_selected) do
			local d = x6.a and x6.a[part]
			if d then
				d.pc_phys = live
				count = count + 1
			end
		end
		if count > 0 then
			pc_changed()
		end
		return count
	end
	x6.pc_set_phys = pc_set_phys

	-- A drag ends by latching the part where it was dropped. It used to promote to
	-- x1.PartCtlMode, which is a *panel* setting and carries two values the per-part
	-- loop cannot honour: "normal" is not a mode at all (the part fell through to the
	-- global shape but kept a non-nil pc_mode, so it stayed exempt from bucketing and
	-- the radius cull for good), and "shape" needs a resolved module that a drag never
	-- attaches.
	--
	-- "normal" maps to manual, not pin. Selecting no longer touches a part's record at
	-- all, so reaching this function means the user physically moved it -- and
	-- "manual" is the mode whose name says that, and the one the panel then reports.
	local function pc_latch_drag()
		local mode = x1.PartCtlMode
		if mode == "shape" then
			local n = pc_assign("shape", { shape = x1.PartCtlShape, ride = x1.PartCtlRide })
			if n > 0 then
				return
			end
			-- Unresolvable shape: fall through to a hold rather than leave the parts
			-- mid-drag with no owner.
		end
		local want = (mode == "pin") and "pin" or "manual"
		for part, _ in pairs(x6.pc_selected) do
			local d = x6.a and x6.a[part]
			if d and d.pc_target then
				-- Deliberately not routed through pc_assign: its pin branch re-reads
				-- part.Position, and a dragged part trails the finger by a frame, so every
				-- drop would snap back by that much. The module unref is pc_assign's other
				-- job, so it has to be done here by hand -- without it a part dragged out
				-- of shape mode went on holding the module's refcount and its cleanup
				-- never ran.
				if d.pc_mod then
					pc_unref_mod(d)
					d.pc_mod = nil
					d.pc_shape = nil
					d.pc_cfg = nil
				end
				d.pc_mode = want
				pc_paint_highlight(part)
			end
		end
		pc_changed()
	end
	x6.pc_latch_drag = pc_latch_drag

	-- Part Control is not a shape, so it cannot gate itself on x1.k6 the way
	-- System_sculptor does (it returns early unless x1.k6 == "Sculptor"). Left
	-- ungated these handlers fired on every left click for every shape, forever:
	-- clicking any held part yanked it into manual mode and pinned it where you
	-- dropped it, and because the core ball is anchored and lives outside x6.a,
	-- every core drag fell through to the else branch and painted a selection
	-- rectangle across the screen. Armed while the panel is open, or permanently
	-- by the toggle.
	--
	-- Only InputBegan is gated. InputChanged and InputEnded are no-ops unless
	-- pc_dragging or pc_box_start is already set, and those can only be set by a
	-- gated InputBegan -- so a gesture that starts armed always finishes, even if
	-- the panel is closed halfway through it.
	local function pc_armed()
		return (x6.pc_active or x1.PartCtlEnabled) and true or false
	end
	x6.pc_armed = pc_armed

	-- Picking, by Include raycast over the held parts. active_array rather than
	-- pairs(x6.a): the dense array makes the candidate list a straight copy, and the
	-- weak hash still holds parts the sweep has not reaped. The RaycastParams is built
	-- once instead of once per tap.
	local pick_params = nil
	local function pc_pick(screen_pos)
		local cam = v4 and v4.CurrentCamera
		local arr = x6.active_array
		if not cam or not arr or #arr == 0 then
			return nil
		end
		if not pick_params then
			pick_params = RaycastParams.new()
			pick_params.FilterType = Enum.RaycastFilterType.Include
		end
		-- A fresh table each pick. FilterDescendantsInstances copies on assignment, so
		-- holding one would save only the allocation, and a stale entry in it would
		-- keep a released part tappable.
		local cand = (table.create and table.create(#arr)) or {}
		for i = 1, #arr do
			cand[i] = arr[i]
		end
		pick_params.FilterDescendantsInstances = cand
		local ray = cam:ViewportPointToRay(screen_pos.X, screen_pos.Y)
		local res = v4:Raycast(ray.Origin, ray.Direction * 2000, pick_params)
		return res and res.Instance or nil
	end

	-- Rounds a drag target onto a stud grid. 0 is off, and anything under a tenth of a
	-- stud is treated as off rather than as a divide by nearly zero.
	local function pc_snap_grid(point)
		local grid = tonumber(x1.PartCtlGridSnap) or 0
		if grid < 0.1 then
			return point
		end
		return Vector3.new(
			math.floor(point.X / grid + 0.5) * grid,
			math.floor(point.Y / grid + 0.5) * grid,
			math.floor(point.Z / grid + 0.5) * grid
		)
	end

	-- Where a drag puts the part. The old projection could only slide it along a
	-- sphere at the distance latched when the touch began -- no way to push it away or
	-- pull it closer, which is the one thing a placement tool has to do, and there is
	-- no scroll wheel here to add one with -- and it ignored the world entirely, so
	-- putting a part on the floor was guesswork.
	--
	-- Surface Snap casts the same ray at everything that is *not* held and drops the
	-- selection where it lands, so depth is controlled by where you point. Missing
	-- everything falls back to the latched distance, which is the old behaviour
	-- exactly, and turning the toggle off restores it outright.
	local drag_params = nil
	local function pc_drag_point(screen_pos, distance, anchor_size)
		local cam = v4 and v4.CurrentCamera
		if not cam then
			return nil
		end
		local ray = cam:ViewportPointToRay(screen_pos.X, screen_pos.Y)
		local point = ray.Origin + (ray.Direction * (distance or 50))

		if x1.PartCtlSurfaceSnap ~= false then
			if not drag_params then
				drag_params = RaycastParams.new()
				drag_params.FilterType = Enum.RaycastFilterType.Exclude
				drag_params.IgnoreWater = true
			end
			local ignore, n = {}, 0
			local char = v8 and v8.Character
			if char then
				n = n + 1
				ignore[n] = char
			end
			-- The core's folder, not the ball: the ball is anchored and sits right under
			-- the finger whenever a drag crosses it.
			if x6.b and x6.b.Parent then
				n = n + 1
				ignore[n] = x6.b.Parent
			end
			-- Held parts are excluded one hit at a time rather than all at once: the
			-- exclude list would otherwise be a copy of the whole claim on every frame
			-- of every drag. Eight passes is enough to get through a wall of them, and
			-- is bounded, which a while-true is not.
			for _ = 1, 8 do
				drag_params.FilterDescendantsInstances = ignore
				local res = v4:Raycast(ray.Origin, ray.Direction * 2000, drag_params)
				if not res then
					break
				end
				if not (x6.a and x6.a[res.Instance]) then
					-- Lifted off the surface by the anchor's own half-extent along the
					-- normal, or the part lands half sunk into whatever it was dropped on.
					local nrm, lift = res.Normal, 0
					if anchor_size then
						lift = (math.abs(nrm.X) * anchor_size.X
							+ math.abs(nrm.Y) * anchor_size.Y
							+ math.abs(nrm.Z) * anchor_size.Z) * 0.5
					end
					point = res.Position + (nrm * lift)
					break
				end
				n = n + 1
				ignore[n] = res.Instance
			end
		end

		return pc_snap_grid(point)
	end

	return function()
		if not v1 or not v1.InputBegan or not x6.c then
			return
		end

		-- Everything a drag needs, in one place, because a touch does not know yet
		-- whether it is going to become one. Nothing here runs on a tap.
		local function begin_drag(anchor)
			local cam = v4 and v4.CurrentCamera
			x6.pc_dragging = true
			x6.pc_drag_distance = cam and (cam.CFrame.Position - anchor.Position).Magnitude or 50
			x6.pc_drag_target = anchor.Position
			x6.pc_drag_size = anchor.Size
			for part, _ in pairs(x6.pc_selected) do
				local d = x6.a and x6.a[part]
				if d then
					x6.pc_offsets[part] = part.Position - anchor.Position
					-- Forced, not `d.pc_mode or "manual"`. A part already assigned to a
					-- shape kept that mode, and the shape branch ignores pc_target -- so
					-- the part sat exactly where the shape wanted it while the finger
					-- dragged nothing. The release re-assigns the shape if that is what
					-- the panel is on.
					d.pc_mode = "manual"
					d.pc_target = part.Position
					pc_paint_highlight(part)
				end
			end
			pc_changed()
		end

		local function move_drag(screen_pos)
			local new_pos = pc_drag_point(screen_pos, x6.pc_drag_distance or 50, x6.pc_drag_size)
			if not new_pos then
				return
			end
			x6.pc_drag_target = new_pos
			for part, _ in pairs(x6.pc_selected) do
				local d = x6.a and x6.a[part]
				if d then
					d.pc_target = new_pos + (x6.pc_offsets[part] or Vector3.zero)
					d.pc_mode = d.pc_mode or "manual"
				end
			end
		end

		table.insert(
			x6.c,
			v1.InputBegan:Connect(function(input, processed)
				if processed or not pc_armed() then
					return
				end

				if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
					local screen = input.Position
					local target = pc_pick(screen)
					local multi = x1.PartCtlMultiSelect == true

					if target and x6.a and x6.a[target] then
						if x6.pc_selected[target] and multi then
							pc_deselect(target)
							return
						end
						if not x6.pc_selected[target] then
							pc_select(target, multi)
						end
						if not multi then
							-- Pending, not started, and nothing on the part's record is
							-- touched. This used to set pc_dragging and write
							-- `d.pc_mode = d.pc_mode or "manual"` here, and InputEnded ran
							-- the latch unconditionally -- so a plain tap pinned the part,
							-- with the panel's own mode row reading "Normal (No Override)".
							-- begin_drag runs from InputChanged, once the finger has
							-- actually moved DRAG_PX.
							x6.pc_press = { part = target, screen = screen }
						end
					end
				end
			end)
		)

		table.insert(
			x6.c,
			v1.InputChanged:Connect(function(input, processed)
				if
					input.UserInputType ~= Enum.UserInputType.Touch
					and input.UserInputType ~= Enum.UserInputType.MouseMovement
				then
					return
				end
				if x6.pc_dragging then
					move_drag(input.Position)
					return
				end
				-- The threshold. A touch that never travels this far stays a selection,
				-- which is what makes tapping a part free of consequences.
				local press = x6.pc_press
				if press then
					local dx, dy = input.Position.X - press.screen.X, input.Position.Y - press.screen.Y
					if (dx * dx + dy * dy) >= DRAG_PX * DRAG_PX then
						x6.pc_press = nil
						if x6.a and x6.a[press.part] then
							begin_drag(press.part)
							move_drag(input.Position)
						end
					end
				end
			end)
		)

		table.insert(
			x6.c,
			v1.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
					-- A touch that never crossed the threshold is a tap, and a tap is a
					-- selection: the latch only runs for a drag that actually happened.
					x6.pc_press = nil
					if x6.pc_dragging then
						x6.pc_dragging = false
						x6.pc_drag_target = nil
						x6.pc_drag_size = nil
						pc_latch_drag()
					end
				end
			end)
		)
	end
end
