return function(context)
	local v1, v2, v3, v4, v5, v6, v7, v8, v9 = context.v1, context.v2, context.v3, context.v4, context.v5, context.v6, context.v7, context.v8, context.v9
	local x1, x2, x6, x9 = context.x1, context.x2, context.x6, context.x9
	local x5 = context.x5
	local get_shape = context.get_shape
	local load_module = context.load_module
	local ShapePhysics = context.shape_physics or load_module("ShapePhysics.lua")
	context.shape_physics = ShapePhysics
	local SUB_DIR = context.SUB_DIR or ""

	local x4, x8 = {}, {}
	x6.apply_shape_physics = function(p, d)
		if not x6.torn_down then return ShapePhysics.apply(p, d, x1) end
	end
	x6.refresh_collisions = function()
		if x6.torn_down then return end
		for p, d in pairs(x6.a) do ShapePhysics.apply_collisions(p, d, x1) end
	end
	local x7 = {}
	local ANTI_SLEEP = Vector3.new(0, 0.01, 0)
	local ZERO_VECTOR = Vector3.zero
	local LIGHT_PHYSICS = PhysicalProperties.new(0.001, 0, 0, 0, 0)
	-- How hard Part Control's pin and manual modes hold their target, as a rate: the
	-- offset is solved over roughly a twelfth of a second. See the per-part dispatch in
	-- f3_body for why this is not x1.k10.
	local PC_GRIP = 12

	-- Releasing a part has to take its Part Control selection with it. The
	-- SelectionBox is parented to the part and x6.pc_selected is weak-keyed, so a part
	-- released while selected kept an orange box for as long as it lived and went on
	-- being counted by the panel with nothing behind it. Both release paths -- x4.f2
	-- and the sweep's own dead-part branch -- come through here.
	local function drop_pc_selection(p)
		if x6.pc_selected and x6.pc_selected[p] and x6.pc_deselect then
			pcall(x6.pc_deselect, p)
		end
	end

	function x7.n(t, x, d)
		-- prefer the in-panel toast so notifications match the rest of the UI;
		-- fall back to the Roblox notification when the panel is not up yet
		local ui = context.x5
		if ui and ui.toast and ui.toast(t, x, nil, d) then
			return
		end
		pcall(function()
			v5:SetCore("SendNotification", { Title = t, Text = x, Duration = d or 3 })
		end)
	end

	-- The panel needs somewhere to send a rejected-keybind message, and x7 is
	-- local to this module. main.lua:577 calls this unguarded on the startup
	-- Testing notice, so leaving it off the mobile tree took the whole script
	-- down on any device whose saved shape was still in testing.
	x8.notify = x7.n

	local EXCLUDED_NAMES = {
		Baseplate = true,
		HumanoidRootPart = true,
		Terrain = true,
		Handle = true,
		Head = true,
		Torso = true,
		["Left Arm"] = true,
		["Right Arm"] = true,
		["Left Leg"] = true,
		["Right Leg"] = true,
		UpperTorso = true,
		LowerTorso = true,
		LeftUpperArm = true,
		LeftLowerArm = true,
		LeftHand = true,
		RightUpperArm = true,
		RightLowerArm = true,
		RightHand = true,
		LeftUpperLeg = true,
		LeftLowerLeg = true,
		LeftFoot = true,
		RightUpperLeg = true,
		RightLowerLeg = true,
		RightFoot = true,
		-- The preview's ghost markers. They are anchored, so x7.e already refuses
		-- them -- but "anchored parts are never claimed" is a property of today's
		-- filter rather than a law, and a preview that grabs itself would be a very
		-- confusing bug to find.
		GRV_GHOST = true,
	}

	-- Character models, rebuilt at most once a second. Membership is checked as a
	-- plain hash read during the ancestor walk below, which short-circuits before
	-- the two FindFirstChildOfClass calls: a player character is by far the most
	-- common reason a part is excluded, so the common case now costs one Lua table
	-- read instead of an IsA plus up to two engine-side child searches per level.
	local char_set, char_set_t, char_set_f = {}, 0, -1
	local function characters()
		local now = time()
		-- Max Fidelity gives this stride up with the rest of them -- but per *frame*,
		-- not per call. x7.e runs this once per candidate part and the claim budget lets
		-- a few thousand through in a frame, so a per-call rebuild would be thousands of
		-- GetPlayers() walks a frame: slower, not more accurate. The 1 Hz floor stays as
		-- the `or` clause, because x6.f does not advance while the loop is paused.
		if (x1.MaxFidelity and x6.f ~= char_set_f) or now - char_set_t > 1 then
			char_set_t = now
			char_set_f = x6.f
			table.clear(char_set)
			for _, pl in ipairs(v2:GetPlayers()) do
				local ch = pl.Character
				if ch then
					char_set[ch] = true
				end
			end
		end
		return char_set
	end

	-- The part's largest axis, in studs. One owner, because three separate features
	-- compare part sizes and they have to agree about what "size" means: the slot sort,
	-- the claim rules and the surplus release rule. Largest axis rather than volume or
	-- Magnitude because that is what a big part looks like -- a 200x1x1 slab reads as
	-- big and its volume does not. 0 means the size could not be read, which every
	-- caller treats as "unknown" rather than "small".
	local function part_size(p)
		local s = p.Size
		if typeof(s) ~= "Vector3" then
			return 0
		end
		local m = s.X
		if s.Y > m then m = s.Y end
		if s.Z > m then m = s.Z end
		return m
	end
	x7.part_size = part_size

	-- The clock the shapes see, which is deliberately not the clock the loop runs on.
	-- Everything that measures wall time -- d.claim_t ageing, the no3_interval stride,
	-- x6.pi_timer, x6.transition_time, d.sys_last_t -- keeps reading time(); only the
	-- value handed to a shape is scaled. Mixing the two would mean a Time Scale of 0
	-- froze the target-list rebuild and the shape-switch ease along with the formation.
	--
	-- Seeded from time() rather than 0 so the first frame does not hand every shape a
	-- clock that jumped backwards by the whole session's uptime, which the universal
	-- `local dt = t - (d.last_t or t)` idiom would read as one enormous negative step.
	-- Clamped independently of the slider's range, because a hand-edited settings file
	-- is the one path that can put anything at all in here.
	local function advance_clock(real_dt)
		local scale = x1.TimeScale
		-- nil, a string from a mangled save, or NaN (which fails its own equality test)
		if type(scale) ~= "number" or scale ~= scale then
			scale = 1
		elseif scale > 8 then
			scale = 8
		elseif scale < -8 then
			scale = -8
		end
		local c = x6.shape_clock
		if type(c) ~= "number" then
			c = time()
		end
		c = c + (real_dt * scale)
		x6.shape_clock = c
		return c
	end
	x7.advance_clock = advance_clock

	-- A shared, bounded orbit keeps debris formations in motion even when their
	-- pattern clock is frozen. One offset for the entire formation preserves its
	-- silhouette; using real time also keeps Time Scale and shape speed independent.
	local function advance_motion(real_dt)
		local step = real_dt or 1 / 60
		if step ~= step or step < 0 then step = 0 end
		step = math.min(step, 0.25)
		x6.motion_clock = ((x6.motion_clock or 0) + step * 1.2) % (math.pi * 2)
		local a = x6.motion_clock
		x6.motion_offset = Vector3.new(6 * (math.cos(a) - 1), 1.5 * math.sin(a * 2), 6 * math.sin(a))
		return x6.motion_offset
	end
	x7.advance_motion = advance_motion

	-- One part's blend weight. At stagger 0 every part carries the global weight. At
	-- stagger 1 the weight is a front that crosses the formation as the global weight
	-- goes 0 -> 1, so the parts convert progressively instead of all together -- which
	-- needs the part's normalised position in the formation, and is therefore only a
	-- sweep at all while slot ordering is on. Pure, so the test can check the corners.
	local function blend_w(weight, stagger, frac)
		local w = weight * (1 + stagger) - (stagger * frac)
		if w < 0 then
			return 0
		elseif w > 1 then
			return 1
		end
		return w
	end
	x7.blend_w = blend_w

	-- Every per-part scratch field a shape may have seeded, in one place. Two callers
	-- need the identical list -- f3_body when it notices x1.k6 moved, and
	-- x4.reroll_seeds -- and the list had already drifted once before there was one
	-- owner: the desktop tree cleared d.f/d.u/d.v/d.rot_axis/d.red_direction and the
	-- mobile tree did not, so on mobile Spinning Cube's axes, Galactic Web's rotation
	-- axis and Cursed Technique Red's direction survived a shape switch and the next
	-- shape to reuse one of those names inherited it.
	--
	-- d.v10 joins the list for the same reason: two shapes read it and nothing was
	-- clearing it. d.bd is the blend's side record, which is scratch for a whole second
	-- shape and has to go with the rest of it.
	local function reset_scratch(d)
		d.v1, d.v2, d.v3, d.v4, d.v5 = nil, nil, nil, nil, nil
		d.v6, d.v7, d.v8, d.v9, d.v10 = nil, nil, nil, nil, nil
		d.nx, d.ny, d.nz = nil, nil, nil
		d.phase, d.phase2, d.radial_phase = nil, nil, nil
		d.last_t, d.sys_last_t, d.last_target_pos = nil, nil, nil
		d.hit_wall, d.hover_anchor, d.cursed_hover_mode = nil, nil, nil
		-- room_slot is the field ROOM Ope Ope no Mi actually parks; the two names after
		-- it are left over from an earlier version of that shape and are written by
		-- nothing, so the original list was clearing the dead names and missing the live
		-- one.
		d.room_slot, d.room_target, d.room_orbit_phase = nil, nil, nil
		d.pika_direction, d.pika_redirect_at = nil, nil
		d.light_direction, d.light_redirect_at = nil, nil
		d.f, d.u, d.v = nil, nil, nil
		d.rot_axis, d.red_direction = nil, nil
		d.bd = nil
		d.black_hole_v2, d.drop = nil, nil
		d.free_physics, d.collisions, d.launch_velocity = nil, nil, nil
		d.angular_velocity = nil
		d.unclaim, d.keep_velocity, d.release_velocity, d.release_spin = nil, nil, nil, nil
		d.integral = Vector3.zero
	end
	x7.reset_scratch = reset_scratch

	-- The claim rules, ordered so the cheapest rejection comes first. Each test is
	-- skipped outright at its off value, so with the shipped defaults this costs four
	-- table reads per candidate part on top of the structural filter in x7.e.
	--
	-- with_radius is passed true only from the claim path. The core moves, so a radius
	-- that also evicted parts already held would release and re-claim them every time
	-- the player walked: the radius decides what gets picked up, and x1.k1 still decides
	-- what gets driven.
	local function rule_reject(p, with_radius)
		local min_sz = x1.RuleMinSize or 0
		local max_sz = x1.RuleMaxSize or 0
		if min_sz > 0 or max_sz > 0 then
			local sz = part_size(p)
			if sz > 0 then
				if min_sz > 0 and sz < min_sz then
					return true
				end
				if max_sz > 0 and sz > max_sz then
					return true
				end
			end
		end
		local filter = x1.RuleName
		if type(filter) == "string" and filter ~= "" then
			local name = string.lower(p.Name)
			local includes, matched = 0, false
			for entry in string.gmatch(filter, "[^,]+") do
				-- Trimmed, lowercased, and matched with a plain find rather than as a Lua
				-- pattern: a user typing Part(1) should get a substring match, not a
				-- malformed-pattern error thrown out of the claim filter.
				local pat = string.lower((string.gsub(entry, "^%s*(.-)%s*$", "%1")))
				if pat ~= "" then
					if string.sub(pat, 1, 1) == "-" then
						local ex = string.sub(pat, 2)
						if ex ~= "" and string.find(name, ex, 1, true) then
							return true
						end
					else
						includes = includes + 1
						if string.find(name, pat, 1, true) then
							matched = true
						end
					end
				end
			end
			-- An include list narrows; a list of nothing but exclusions does not.
			if includes > 0 and not matched then
				return true
			end
		end
		if with_radius then
			local r = x1.RuleClaimRadius or 0
			if r > 0 and x6.b then
				local off = p.Position - x6.b.Position
				if off:Dot(off) > r * r then
					return true
				end
			end
		end
		return false
	end
	x7.rule_reject = rule_reject

	function x7.e(p)
		if not p:IsA("BasePart") then
			return true
		end
		if p.Anchored then
			return true
		end
		if EXCLUDED_NAMES[p.Name] then
			return true
		end
		-- The user's own rules go here, ahead of the tag loop and the ancestor walk:
		-- those are the expensive half of this filter (engine child searches, one to
		-- three per level) and a part the rules already reject should not pay for them.
		if rule_reject(p, true) then
			return true
		end
		-- p.Parent used to be re-read from the engine once per tag in k5, and
		-- again to seed the ancestor walk. One read up front covers all of it.
		local parent = p.Parent
		for _, t in ipairs(x1.k5) do
			if p:FindFirstChild(t) or (parent and parent:FindFirstChild(t)) then
				return true
			end
		end
		local chars = characters()
		-- The walk starts at the parent, not at p: p is always a BasePart here,
		-- so testing it against Model/Accessory/Tool was three guaranteed-false
		-- engine calls per candidate part.
		local target = parent
		while target and target ~= v4 and target ~= game do
			-- ordered cheapest-to-dearest: Lua table read, then a bare IsA, then
			-- the child searches. The Accessory/Tool test used to sit after the
			-- Model test, so accessories paid for two child searches first.
			if chars[target] then
				return true
			end
			if target:IsA("Accessory") or target:IsA("Tool") then
				return true
			end
			if
				target:IsA("Model")
				and (target:FindFirstChildOfClass("Humanoid") or target:FindFirstChildOfClass("AnimationController"))
			then
				return true
			end
			target = target.Parent
		end
		return false
	end

	-- Both the core tracker and the multi-target sweep want the same thing from a
	-- character, and both used to inline it twice per call.
	local function root_of(char)
		if not char then
			return nil
		end
		return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
	end

	local function get_predicted_pos(root, factor)
		local pos = root.Position
		local vel = root.AssemblyLinearVelocity
		-- squared compare first: Magnitude's sqrt is only worth paying when the
		-- velocity actually needs clamping. .Unit would then sqrt the same number
		-- a second time, so scale by the root we already have instead.
		local vel_sq = vel:Dot(vel)
		if vel_sq > 62500 then
			vel = vel * (250 / math.sqrt(vel_sq))
		end
		local y_vel = math.clamp(vel.Y, -50, 15)
		vel = Vector3.new(vel.X, y_vel, vel.Z)
		return pos + (vel * (factor / 1000))
	end

	local no_damp = { ["Slingshot"] = true, ["Point Impact"] = true, ["Light Light no Mi"] = true }

	-- NetworkOwnerV3 values that mean somebody else is simulating the part. One
	-- hash lookup instead of a four-way comparison chain, per part per frame.
	local NO3_SKIP = { [-1] = true, [1] = true, [2] = true, [3] = true }

	-- Most shapes are pure functions of the part and the clock, but one that owns
	-- an instance -- Platform's anchored pad -- needs somewhere to give it back, or
	-- it outlives the shape that made it. Read straight out of loaded_shapes rather
	-- than through get_shape: this runs on the disable and stop paths, and
	-- get_shape would happily block on an HTTP fetch for a shape that never loaded.
	-- A shape with no cleanup costs one nil check.
	local function cleanup_shape(name)
		local cache = context.loaded_shapes
		local mod = name and cache and cache[name]
		if mod and mod.cleanup then
			pcall(mod.cleanup, x6, x1)
		end
	end

	-- Forward-declared: f3_body's drop branch restores a part whose Parent went away,
	-- and the definition lives further down next to x4.f2. Without this the name
	-- resolved to a nil global inside f3_body and the pcall around it swallowed the
	-- failure, so the restore silently did nothing.
	local f2_restore

	-- The hot loop lives in its own function so the per-frame pcall does not have
	-- to allocate a fresh closure sixty times a second.
	local function f3_body(real_dt)
			local c = x6.b.Position
			x6.f = x6.f + 1
			if x6.last_shape ~= x1.k6 then
				cleanup_shape(x6.last_shape)
				x6.last_shape = x1.k6
				-- Part Control assignments are torn down with the switch: a part
				-- assigned to a shape holds that module and its x6.pre state, both of
				-- which the switch invalidates. Releasing first also clears pc_mode,
				-- which the per-part reset below does not reach.
				if x6.pc_release_all then
					pcall(x6.pc_release_all)
				end
				for _, d in pairs(x6.a) do
					reset_scratch(d)
				end
			end
			local dt = x6.n > 5000 and 10 or (x6.n > 2500 and 6 or (x6.n > 1000 and 3 or 1))
			local et, ft = x1.k7 or dt, time()
			-- Time Scale. Advanced once per frame here and handed to the shapes in place
			-- of ft at the four shape-facing call sites below; ft itself stays wall time
			-- for everything that measures a real interval. See advance_clock.
			local sclock = advance_clock(real_dt)
			advance_motion(real_dt)
			if x1.k6 == "Light Light no Mi" then
				et = 1
			end
			-- Max Fidelity adds uncached reads and a complete sweep to Force Smooth.
			-- Both remove update delays; the separate Damping control still applies.
			local max_fid = x1.MaxFidelity and true or false
			local force_smooth = x1["Force Smooth (Lags)"] or max_fid
			if force_smooth then
				dt = 1
				et = 1
			end
			local i = 0
			local update_bucket = x6.f % et
			-- The target list and the billboard markers are rebuilt at 1 Hz; the
			-- per-frame tracking below reads target_positions, so the stride only delays
			-- *membership* -- a player who has just become a valid target waits up to a
			-- second to be picked up. Max Fidelity does not wait.
			if max_fid or ft > x6.pi_timer then
				x6.pi_timer = ft + 1
				local pi = x6.pi_targets
				table.clear(pi)
				local target_set = x6.pi_set
				if not target_set then
					target_set = {}
					x6.pi_set = target_set
				else
					table.clear(target_set)
				end
				if x1.PI_All then
					for _, pl in ipairs(v2:GetPlayers()) do
						if pl ~= v8 and pl.Character and root_of(pl.Character) then
							pi[#pi + 1] = pl
							target_set[pl] = true
						end
					end
				else
					if x1.Targets and #x1.Targets > 0 then
						for _, tgt in ipairs(x1.Targets) do
							if tgt and tgt.Parent and tgt.Character and root_of(tgt.Character) then
								pi[#pi + 1] = tgt
								target_set[tgt] = true
							end
						end
					end
				end

				for _, pl in ipairs(v2:GetPlayers()) do
					-- pl.Character was read twice and the Head lookup was thrown
					-- away and re-fetched as a property; two engine crossings per
					-- player per second for values we already had in hand.
					local char = pl.Character
					local head = char and char:FindFirstChild("Head")
					if head then
						local is_tgt = target_set[pl] == true
						local marker = head:FindFirstChild("GravityTargetMarker")

						-- Built bottom-up and parented last. Instance.new(class,
						-- parent) attaches before the properties are assigned, so
						-- every set after it schedules a layout/render pass the
						-- engine then throws away; assembling off-tree and
						-- parenting once costs a single pass for the whole marker.
						if is_tgt and not marker then
							local txt = Instance.new("TextLabel")
							txt.BackgroundTransparency = 1
							txt.Size = UDim2.new(1, 0, 1, 0)
							txt.Text = "▼"
							txt.TextColor3 = Color3.fromRGB(255, 60, 60)
							txt.TextScaled = true
							txt.Font = Enum.Font.GothamBlack

							local str = Instance.new("UIStroke")
							str.Color = Color3.fromRGB(0, 0, 0)
							str.Thickness = 2
							str.Parent = txt

							local bg = Instance.new("BillboardGui")
							bg.Name = "GravityTargetMarker"
							bg.Size = UDim2.new(1.5, 0, 1.5, 0)
							bg.StudsOffset = Vector3.new(0, 2.5, 0)
							bg.AlwaysOnTop = true
							txt.Parent = bg
							bg.Parent = head
						elseif not is_tgt and marker then
							marker:Destroy()
						end
					end
				end
			end
			local shape_name = x1.k6
			local cur_shape_mod = get_shape(shape_name)
			if x6.torn_down or not x6.b then return end
			local cur_shape_cfg = x1.S[shape_name] or {}
			if cur_shape_mod and cur_shape_mod.px then
				cur_shape_mod.px(sclock, cur_shape_cfg, x6, x9, x1)
			end
			local pc_mods = x6.pc_mods
			if pc_mods then
				for mod, _ in pairs(pc_mods) do
					if mod.px then
						pcall(mod.px, sclock, mod.pc_cfg_ref or cur_shape_cfg, x6, x9, x1)
					end
				end
			end
			if x1.k6 ~= shape_name then
				shape_name = x1.k6
				cur_shape_mod = get_shape(shape_name)
				if x6.torn_down or not x6.b then return end
				cur_shape_cfg = x1.S[shape_name] or {}
			end
			local cur_no_damp = no_damp[shape_name]

			-- Shape Blend. B is resolved once per frame and only when it can actually
			-- contribute: the toggle on, a weight above zero, a shape that is registered
			-- and loads, and a different shape from A -- blending a shape with itself
			-- costs two evaluations to produce the field it already had.
			--
			-- Published on x6 as well as held locally: the sweep reads the locals because
			-- it reads them per part, and the preview reads x6 so a ghost cannot show a
			-- different field from the one the parts are being driven to.
			local blend_f2, blend_cfg, blend_base, blend_stag, blend_name = nil, nil, 0, 0, nil
			-- Whether this frame has already made its one guarded call into the blend
			-- shape; see the sweep for why that is once a frame and not once a part.
			local blend_checked = false
			if x1.BlendEnabled and not (cur_shape_mod and cur_shape_mod.NoBlend) then
				local bn = x1.BlendShape
				if type(bn) == "string" and bn ~= "" and bn ~= shape_name and x2[bn] then
					local bw = (x1.BlendWeight or 0) / 100
					-- get_shape does not cache a failure, so a registered name whose module
					-- cannot be fetched would re-attempt a synchronous HTTP request from
					-- inside this frame, every frame, for as long as the blend is on.
					-- Remembering the name that failed costs one string compare and turns a
					-- permanent stall into a single warn. Cleared by the panel when the
					-- blend shape is changed, so retrying is a deliberate act.
					if bw > 0 and bn ~= x6.bl_failed then
						local bmod = get_shape(bn)
						if x6.torn_down or not x6.b then return end
						if not (bmod and bmod.f2) then
							x6.bl_failed = bn
						end
						if bmod and bmod.f2 and not bmod.NoBlend then
							blend_name, blend_f2 = bn, bmod.f2
							blend_cfg = x1.S[bn] or {}
							blend_base = bw > 1 and 1 or bw
							blend_stag = math.clamp((x1.BlendStagger or 0) / 100, 0, 1)
							if bmod.px then
								-- Safe to run both pre-passes: x6.pre is namespaced by shape
								-- name at every site that touches it (x6.pre["Platform"],
								-- x6.pre["Celestial Ribbon_meta"]), so two shapes' pre-pass
								-- state cannot collide. That one fact is what lets any pair
								-- of shapes be blended without a compatibility list.
								pcall(bmod.px, sclock, blend_cfg, x6, x9, x1)
							end
						end
					end
				end
			end
			x6.bl_f2, x6.bl_cfg, x6.bl_w, x6.bl_s = blend_f2, blend_cfg, blend_base, blend_stag
			-- A blend shape that owns an instance has to be handed it back when the blend
			-- moves off it, exactly as x6.last_shape does for the primary: without this,
			-- blending with Platform leaves its anchored pad in the world with nothing
			-- updating it. Never the shape that is now primary -- a blend that moved onto
			-- the selected shape would otherwise tear down the live one's instance.
			if x6.last_blend ~= blend_name then
				local prev_blend = x6.last_blend
				x6.last_blend = blend_name
				if prev_blend and prev_blend ~= shape_name then
					cleanup_shape(prev_blend)
				end
			end

			local target_positions = x6.target_positions
			if not target_positions then
				target_positions = {}
				x6.target_positions = target_positions
			else
				table.clear(target_positions)
			end
			local valid_targets = 0
			-- v4 is already the (cloneref'd) Workspace service, so reaching it as
			-- an upvalue is a register read where `workspace` is an _ENV hash
			-- lookup. Same instance, three fewer global lookups per frame.
			local fallen_height = v4.FallenPartsDestroyHeight + 50
			if #x6.pi_targets > 0 then
				local predictive = x1.PredictiveTracking
				local pfactor = x1.PredictionFactor or 150
				local void_off = x1.VoidProtection == false
				for _, tgt in ipairs(x6.pi_targets) do
					local root = tgt and root_of(tgt.Character)
					if root then
						local pos = root.Position
						if void_off or (pos.Y > fallen_height) then
							if predictive then
								pos = get_predicted_pos(root, pfactor)
							end
							valid_targets = valid_targets + 1
							target_positions[valid_targets] = pos
						end
					end
				end
			end
			-- Slot ordering and the part-count ceiling both walk the whole population, so
			-- they run on a stride rather than per frame. During the opening claim sweep
			-- the population changes thousands of times and a per-frame re-sort would have
			-- parts trading places continuously. A mode, seed or ceiling change is applied
			-- at once instead, since that is a deliberate action taken with the panel open
			-- and looking at the result is the point.
			--
			-- The stride widens with the part-count ladder, the same way no3_interval does
			-- and for the same reason: a quarter second is right at a few hundred parts and
			-- the sort is O(n log n) with an engine property read per part, so at five
			-- thousand it becomes a full second. Max Fidelity gives the stride up entirely,
			-- with the rest of them.
			--
			-- Cap first, then the reindex, so the slots describe the population that is
			-- actually left rather than one that includes parts about to be released.
			local slot_mode_now = x1.SlotMode or "Claim"
			local cap_now = x1.TargetParts or 0
			if
				x6.slot_mode_last ~= slot_mode_now
				or x6.slot_seed_last ~= x1.SlotSeed
				or x6.cap_last ~= cap_now
			then
				x6.slot_mode_last = slot_mode_now
				x6.slot_seed_last = x1.SlotSeed
				x6.cap_last = cap_now
				x6.slot_dirty = true
				x6.slot_t = nil
			end
			if x6.slot_dirty and (max_fid or ft - (x6.slot_t or -1) > 0.25 * (dt > 4 and 4 or dt)) then
				x6.slot_t = ft
				x6.slot_dirty = false
				x4.enforce_part_cap()
				x4.reindex_slots()
			end

			-- Deviation readout: how far the parts actually are from the targets they were
			-- given, which is the only honest answer to "is this shape not working or is
			-- the tracking not keeping up". Gated, because it is a Magnitude per part per
			-- frame and it only means anything for shapes that hand back an exact target.
			local dev_on = x1.PreviewDeviation and true or false
			local dev_sum, dev_max, dev_n = 0, 0, 0

			local k1 = x1.k1
			local c7 = x9.c7
			local k1_sq = k1 * k1
			local c7_sq = c7 * c7
			local ki = x1.Ki or 0
			local damping = x1.Damping or 0
			local max_speed = x1.MaxSpeed
			local vert_stiff = x1.VerticalStiffness or 1
			local vert_mult = vert_stiff ~= 1 and Vector3.new(1, vert_stiff, 1) or nil
			local dt_mult = real_dt * 60 * dt

			local smoothing = (shape_name == "Point Impact" and 1) or x1.k8
			if x1.DramaMode and shape_name == "Point Impact" then
				smoothing = 1
			end
			local sm_alpha = smoothing >= 1 and 1 or (1 - math.exp(-dt_mult * -math.log(math.max(0.001, 1 - smoothing))))
			-- force_smooth already folds in max_fid (line 224).
			if force_smooth then
				sm_alpha = 1
			end

			local ang_damp_mult = 1
			if x1.AngularDamping and x1.AngularDamping > 0 then
				local damp_rate = -60 * math.log(math.max(0.001, 1 - math.clamp(x1.AngularDamping, 0, 0.99)))
				ang_damp_mult = math.exp(-damp_rate * real_dt * dt)
			end

			local trans_ease = 1
			local in_transition = false
			if x6.transition_time and x6.transition_time > 0 then
				in_transition = true
				local alpha = math.clamp((ft - x6.transition_time) / x6.transition_dur, 0, 1)
				if alpha < 1 then
					trans_ease = alpha * alpha * (3 - 2 * alpha)
				else
					x6.transition_time = 0
					in_transition = false
				end
			end
			
			-- 1 Hz, because a WaterLevel part almost never moves -- but "almost never"
			-- is the kind of assumption Max Fidelity exists to drop.
			if max_fid or x6.f % 60 == 0 or x6.water_level == nil then
				local water_part = v4:FindFirstChild("WaterLevel")
				if water_part and water_part:IsA("BasePart") then
					x6.water_level = water_part.Position.Y + (water_part.Size.Y / 2) + 5
				else
					x6.water_level = false
				end
			end
			local water_level = x6.water_level ~= false and x6.water_level or nil
			local ghp = gethiddenproperty
			local workspace_gravity = v4.Gravity or 196.2
			local shape_f2 = cur_shape_mod and cur_shape_mod.f2
			local shape_frame_tracking = cur_shape_mod and cur_shape_mod.FrameTracking and not blend_f2
			local is_drop_shape = cur_shape_mod and cur_shape_mod.Drop
			local is_self_bounded_shape = shape_name == "ROOM Ope Ope no Mi" or shape_name == "Light Light no Mi"
			local aggressive_root = nil
			if x1.AggressiveClaim and v8.Character then
				aggressive_root = root_of(v8.Character)
			end

			-- Everything below is constant for the whole sweep. Reading it once
			-- here instead of once per part removes a few thousand hash lookups
			-- and string comparisons per frame at high part counts.
			local aggressive_claim = x1.AggressiveClaim and true or false
			local realistic_liftoff = x1["Realistic Liftoff"] and true or false
			local is_point_impact = shape_name == "Point Impact"
			local is_light_shape = shape_name == "Light Light no Mi"
			local is_cursed_red = shape_name == "Cursed Technique Red"
			local always_process = (is_drop_shape or is_self_bounded_shape or max_fid or (cur_shape_mod and cur_shape_mod.AlwaysProcess)) and true or false
			local base_limit = is_light_shape and 1000 or ((max_speed and not cur_no_damp) and max_speed or 3300)
			local check_no3 = (not is_drop_shape) and (not aggressive_claim) and ghp ~= nil
			local default_damping = not cur_no_damp and math.clamp(damping, 0, 5) or 0
			local damping_scale = 1 / (1 + default_damping)
			local tracking_response = 1 - (1 - damping_scale) ^ (real_dt * 60)
			local integral_on = ki > 0

			-- The sweep reached both of these through x6 on every single
			-- iteration: at 5000 parts that was ~20k extra hash lookups a frame,
			-- 1.2M a second, for two fields that cannot change mid-sweep. Nothing
			-- outside main.lua's teardown ever reassigns them (shapes and the
			-- sculptor only read), so holding them as locals is safe.
			local arr = x6.active_array
			local data = x6.a
			-- gethiddenproperty is one of the pricier executor calls and this was
			-- refreshing every 0.15s per part no matter the load: ~33k pcall+read
			-- pairs a second at 5000 parts. Widening it with the same part-count
			-- stride the sweep already uses cuts that ~4x, capped at 0.6s so an
			-- ownership change is still picked up quickly.
			--
			-- 0 under Max Fidelity: a cached value is a stale answer, and this one
			-- decides whether the part is driven at all, so a part whose ownership has
			-- just come to us sat skipped for up to 0.15s. That is the longest-lived
			-- stale read in the loop.
			local no3_interval = max_fid and 0 or (0.15 * (dt > 4 and 4 or dt))

			for k = #arr, 1, -1 do
				local p = arr[k]
				local d = data[p]

				if not d or not p.Parent then
					if d then
						-- d holds the only copy of this part's original CanCollide,
						-- Anchored and CustomPhysicalProperties. Dropping it without
						-- restoring is unrecoverable: plenty of games pool parts by
						-- setting Parent = nil and putting them back later, and the
						-- DescendantAdded hook then re-queues the part, at which point
						-- x4.f1 re-snapshots the *forced* values -- CanCollide false and
						-- LIGHT_PHYSICS -- as if they were the originals. That part can
						-- never be restored again by any release path, including
						-- teardown. Deliberately not guarded on p.Parent -- this branch
						-- fires *because* Parent is nil, and an unparented part still
						-- accepts property writes, which is the whole point. The pcall
						-- covers the other case, where the part was fully destroyed and
						-- there is nothing left to write to.
						pcall(f2_restore, p, d, false)
						if d.at and d.at.Parent then d.at:Destroy() end
						if d.lv and d.lv.Parent then d.lv:Destroy() end
						if d.av and d.av.Parent then d.av:Destroy() end
						data[p] = nil
						drop_pc_selection(p)
					end
					local last = #arr
					if k ~= last then
						arr[k] = arr[last]
					end
					arr[last] = nil
					x6.n = math.max(0, x6.n - 1)
					continue
				end
				i = i + 1
				local frame_tracking = (d.pc_mode == nil and shape_frame_tracking)
					or (d.pc_mode == "shape" and d.pc_mod and d.pc_mod.FrameTracking)
				if d.pc_mode == nil and i % et ~= update_bucket and not frame_tracking then
					continue
				end
				if check_no3 then
					if d.no3_val == nil or ft - (d.no3_tick or 0) > no3_interval then
						d.no3_tick = ft
						local success, no3_val = pcall(ghp, p, 'NetworkOwnerV3')
						d.no3_val = success and no3_val or 0
					end
					if NO3_SKIP[d.no3_val] then
						continue
					end
				end
				local active_c = c
				if valid_targets > 0 then
					active_c = target_positions[(d.id % valid_targets) + 1]
				end
				local p_pos = p.Position
				local tc = active_c - p_pos
				local distance_sq = tc:Dot(tc)
				if distance_sq > k1_sq and not (always_process or d.pc_mode or d.free_active or d.collision_active or d.angular_active) then
					-- Skipping the part leaves its LinearVelocity alone, and with MaxForce
					-- at k4 the constraint keeps applying it: anything that overshoots the
					-- radius coasts outward for good, and it can never come back because
					-- this same test culls it before the shape runs again. Park it once on
					-- the way out instead. The flag keeps that from becoming a physics
					-- property write per out-of-range part per frame, and clearing d.vl
					-- means a part that does drift back in starts from a standstill rather
					-- than resuming the velocity that threw it out.
					if not d.parked and d.lv then
						d.parked = true
						d.vl = ZERO_VECTOR
						d.lv.VectorVelocity = ZERO_VECTOR
					end
					continue
				end
				if d.parked then
					d.parked = nil
				end
				if distance_sq > c7_sq or always_process or d.pc_mode or is_cursed_red or d.free_active or d.collision_active or d.angular_active then
					local target_pos_delta = ANTI_SLEEP
					local pure_target_pos = nil
					local pc = d.pc_mode
					if pc == "pin" or pc == "manual" then
						local tgt = d.pc_target or p_pos
						pure_target_pos = tgt
						-- Pin and manual are a placement, not an attraction: the part is
						-- meant to go where it was put and stay there. Driven at the global
						-- k10 pull -- 20 * c1, so 3 studs/s per stud of error -- a pin took
						-- about a second to settle and visibly trailed the finger through a
						-- drag, which is most of why this tool felt vague. PC_GRIP solves the
						-- offset over roughly a twelfth of a second instead. An explicit
						-- per-part Pull Strength still wins, because that slider exists to
						-- say otherwise.
						local gain = (d.pc_phys and d.pc_phys.k10) and (d.pc_phys.k10 * x9.c1) or PC_GRIP
						-- A velocity actuator told to cover more than the remaining distance
						-- in one step overshoots and comes back, which is oscillation rather
						-- than a hold. real_dt, not the fixed step, so the cap is right at 30
						-- fps and at 240.
						local max_gain = 1 / (real_dt > 1 / 240 and real_dt or 1 / 240)
						if gain > max_gain then
							gain = max_gain
						end
						target_pos_delta = (tgt - p_pos) * gain
					elseif pc == "shape" and d.pc_mod and d.pc_mod.f2 then
						target_pos_delta, pure_target_pos =
							d.pc_mod.f2(p, active_c, d, sclock, d.pc_cfg or cur_shape_cfg, x1, x6, x9)
					elseif shape_f2 then
						target_pos_delta, pure_target_pos = shape_f2(p, active_c, d, sclock, cur_shape_cfg, x1, x6, x9)
						-- The blend, inline rather than through a shared helper: this is the
						-- per-part path and the rest of this loop hoists everything it can
						-- out of it, so the preview keeps its own copy of these fifteen
						-- lines instead of both going through one call per part.
						--
						-- Not reachable for a part under Part Control: those come out of the
						-- branches above. A part placed by hand is not part of the formation
						-- being mixed.
						if blend_f2 then
							-- B runs against its own scratch record. d.v1..d.v10, d.phase,
							-- d.last_t and the rest are seeded lazily under `if not d.X`
							-- guards, so two shapes sharing one record do not blend -- they
							-- each re-seed the other's cached axes, phases and timestamps
							-- every frame, which is two shapes fighting rather than a mix.
							-- Only the identity fields a shape may legitimately read are
							-- carried across; the system-owned terms (d.vl, d.integral,
							-- d.last_target_pos, d.sys_last_t) stay on d and are computed
							-- from the blended result further down.
							local bd = d.bd
							if not bd then
								bd = { id = d.id, integral = ZERO_VECTOR }
								d.bd = bd
							end
							bd.slot, bd.slot_n, bd.claim_t = d.slot, d.slot_n, d.claim_t
							local frac = 0
							if d.slot and d.slot_n and d.slot_n > 1 then
								frac = (d.slot - 1) / (d.slot_n - 1)
							end
							local bw = blend_w(blend_base, blend_stag, frac)
							if bw > 0 then
								local b_delta, b_pure
								if blend_checked then
									b_delta, b_pure = blend_f2(p, active_c, bd, sclock, blend_cfg, x1, x6, x9)
								else
									-- One guarded call per frame, then bare ones. A blend shape
									-- that throws would otherwise take the whole sweep with it
									-- through f3's pcall: the primary formation stops dead
									-- because of a shape that is only a passenger, every frame,
									-- silently. This costs one pcall a frame rather than one per
									-- part, and turns that into the blend switching itself off
									-- and saying so.
									blend_checked = true
									local blend_ok
									blend_ok, b_delta, b_pure =
										pcall(blend_f2, p, active_c, bd, sclock, blend_cfg, x1, x6, x9)
									if not blend_ok then
										x6.bl_failed = blend_name
										x6.bl_f2 = nil
										x7.n("Blend", tostring(blend_name) .. " errored -- blend off", 4)
										blend_f2, b_delta, b_pure = nil, nil, nil
									end
								end
								if b_delta and target_pos_delta then
									target_pos_delta = target_pos_delta:Lerp(b_delta, bw)
								elseif b_delta then
									target_pos_delta = b_delta
								end
								-- Both or neither. Half a mixed position is a target neither
								-- shape asked for, and the loop differentiates pure targets
								-- into a velocity term -- so a fabricated one is not a
								-- harmless approximation, it is injected speed.
								if pure_target_pos and b_pure then
									pure_target_pos = pure_target_pos:Lerp(b_pure, bw)
								elseif bw >= 1 then
									pure_target_pos = b_pure
								else
									pure_target_pos = nil
								end
								if bd.unclaim then
									d.unclaim = true
								end
							end
						end
					end
					
					if d.unclaim then
						x4.f2(p, not d.keep_velocity, k)
						continue
					end
					if d.free_physics or d.free_active or d.collisions ~= nil or d.collision_active or d.angular_velocity ~= nil or d.angular_active then
						if ShapePhysics.apply(p, d, x1) then continue end
					end
					if vert_mult then
						target_pos_delta = target_pos_delta * vert_mult
					end
					if integral_on and d.integral and not frame_tracking then
						local ig = d.integral + (target_pos_delta * dt_mult)
						local ig_sq = ig:Dot(ig)
						if ig_sq > 10000 then
							ig = ig * (100 / math.sqrt(ig_sq))
						end
						d.integral = ig
						target_pos_delta = target_pos_delta + (ig * ki)
					end
					local tv = target_pos_delta
					local liftoff_limit = nil

					if realistic_liftoff and d.claim_t then
						local age = ft - d.claim_t
						if age < 4 then
							local p_factor = math.clamp(age / 4, 0, 1)
							local g_bias = Vector3.new(0, -workspace_gravity, 0) * (1 - p_factor)
							local kick = Vector3.new(0, 60, 0) * math.clamp(1 - (age / 0.8), 0, 1)
							tv = tv + g_bias + kick
							liftoff_limit = 8 + ((max_speed or 3300) - 8) * (p_factor ^ 4)
						end
					end
					
					if dev_on and pure_target_pos then
						local dev_off = p_pos - pure_target_pos
						local dev = dev_off.Magnitude
						dev_sum = dev_sum + dev
						dev_n = dev_n + 1
						if dev > dev_max then
							dev_max = dev
						end
					end

					local target_velocity = ZERO_VECTOR
					if pure_target_pos then
						if d.last_target_pos and d.sys_last_t then
							local actual_dt = ft - d.sys_last_t
							if actual_dt > 0.001 then
								-- This differentiates a target that shapes only restamp once per
								-- bucket cycle, so it means something only while the target moves
								-- continuously. A control change that re-seats parts onto
								-- different targets teleports it instead: Hover Text's message box
								-- reshuffles the whole part-id -> pixel map, so every part's
								-- target jumps most of the banner width in one step, and dividing
								-- that by a ~0.066s cycle injects thousands of studs/s. Parts
								-- thrown past k1 then fail the distance test above and are parked
								-- out of range, so the banner never recovers. Capping the term at
								-- the part's own speed limit keeps the smoothing for real motion
								-- and turns a re-seat into a fast glide instead of a fling.
								local step = frame_tracking and math.max(real_dt, 1 / 240) or actual_dt
								local tvel = (pure_target_pos - d.last_target_pos) / step
								local tvel_sq = tvel:Dot(tvel)
								if tvel_sq > base_limit * base_limit then
									tvel = tvel * (base_limit / math.sqrt(tvel_sq))
								end
								target_velocity = tvel
							end
						end
						d.last_target_pos = pure_target_pos
						d.sys_last_t = ft
					else
						d.last_target_pos = nil
						d.sys_last_t = nil
					end
					
					local cur_damping_scale, cur_tracking_response = damping_scale, tracking_response
					local pc_damping = d.pc_phys and d.pc_phys.Damping
					if pc_damping ~= nil then
						cur_damping_scale = 1 / (1 + math.clamp(pc_damping, 0, 5))
						if frame_tracking then
							cur_tracking_response = 1 - (1 - cur_damping_scale) ^ (real_dt * 60)
						end
					end
					-- Solve drag implicitly: subtracting last frame's measured velocity
					-- makes damping above 1 reverse direction and amplify oscillation.
					-- Dampen positional correction, retaining the target's own motion.
					tv = tv * cur_damping_scale + target_velocity

					-- Mirrors the global sm_alpha derivation above, including its
					-- `>= 1 means snap` case: without that branch a per-part
					-- smoothing of 1 fell into math.log(math.max(0.001, 0)) and
					-- produced a finite alpha instead of following the target exactly.
					local cur_sm = sm_alpha
					local pc_sm = d.pc_phys and d.pc_phys.k8
					if pc_sm then
						if pc_sm >= 1 or force_smooth then
							cur_sm = 1
						else
							cur_sm = 1 - math.exp(-dt_mult * -math.log(math.max(0.001, 1 - pc_sm)))
						end
					end
					local vl = d.vl and d.vl:Lerp(tv, cur_sm) or tv
					if frame_tracking and pure_target_pos then
						-- Follow the orbit's movement exactly while damping only recovery
						-- from displacement. Exponential response keeps that recovery
						-- consistent across frame rates without flattening the sphere.
						local correction = (pure_target_pos - p_pos) / math.max(real_dt, 1 / 240) - target_velocity
						vl = target_velocity + correction * cur_tracking_response
						d.integral, d.trans_vl = ZERO_VECTOR, nil
					elseif in_transition and d.trans_vl then
						if trans_ease < 1 then
							vl = d.trans_vl:Lerp(vl, trans_ease)
						else
							d.trans_vl = nil
						end
					end

					if is_point_impact then
						local impact_delta = active_c - p_pos
						local id_sq = impact_delta:Dot(impact_delta)
						-- one sqrt instead of Magnitude's plus Unit's
						vl = id_sq > 0 and (impact_delta * (10000 / math.sqrt(id_sq))) or ZERO_VECTOR
					else
						-- An explicit per-part cap is a cap. The 15300 floor exists so a
						-- shape that hands back an exact position is not fought by the
						-- global speed limit, but pin and manual always hand one back, so
						-- applying it unconditionally made the per-part Max Speed slider
						-- do nothing in the two modes it is most useful in.
						local pc_limit = d.pc_phys and d.pc_phys.MaxSpeed
						local limit = pc_limit or base_limit
						if pure_target_pos and not pc_limit and not frame_tracking then limit = math.max(limit, 15300) end
						if liftoff_limit then limit = math.min(limit, liftoff_limit) end
						local vl_sq = vl:Dot(vl)
						if vl_sq > limit * limit then
							vl = vl * (limit / math.sqrt(vl_sq))
						end

						if water_level then
							local current_y = p_pos.Y
							if current_y < water_level then
								local depth = water_level - current_y
								vl = Vector3.new(vl.X, math.max(vl.Y, 0) + (depth * 5), vl.Z)
							end
						end
					end

					d.vl = vl
					d.lv.VectorVelocity = vl

					if ang_damp_mult ~= 1 and not d.angular_velocity then
						p.AssemblyAngularVelocity = p.AssemblyAngularVelocity * ang_damp_mult
					end

					if aggressive_claim and not is_point_impact and p.ReceiveAge > 0 then
						local base_pos = aggressive_root and aggressive_root.Position or active_c
						if not d.claim_offset then
							d.claim_offset = Vector3.new(math.sin(d.id) * 20, 15 + (d.id % 15), math.cos(d.id) * 20)
						end
						p.CFrame = CFrame.new(base_pos + d.claim_offset)
						d.lv.VectorVelocity = ZERO_VECTOR
					end
				end
			end

			if dev_on then
				x6.dev_n = dev_n
				x6.dev_mean = dev_n > 0 and (dev_sum / dev_n) or 0
				x6.dev_max = dev_max
			end

			-- Last, and outside the sweep: the preview is the one part of this function
			-- that has to run with nothing claimed at all, which is most of why it exists.
			if x1.PreviewEnabled then
				x4.preview_step(sclock, c, shape_f2, cur_shape_cfg, real_dt)
			elseif x6.ghosts or x6.ghost_folder then
				x4.preview_clear()
			end
	end

	local function f3(real_dt)
		real_dt = real_dt or (1 / 60)
		if x6.torn_down or not x6.b or x1.Disabled then
			return
		end
		if x1.Paused then
			-- ANTI_SLEEP is a constant, so the old code wrote the same value to
			-- every constraint 60 times a second: 300k physics property writes a
			-- second at 5000 parts, all of them no-ops. 20 Hz is enough to keep
			-- assemblies from sleeping, and at 0.01 studs/s nothing drifts
			-- visibly between nudges. f3_body does not run while paused, so this
			-- needs its own counter rather than x6.f.
			--
			-- Max Fidelity nudges every frame. "Enough to keep an assembly awake" is a
			-- judgement about the engine's sleep heuristic, and this is the switch for
			-- people who would rather not rely on one.
			x6.pause_tick = (x6.pause_tick or 0) + 1
			if not x1.MaxFidelity and x6.pause_tick % 3 ~= 0 then
				return
			end
			-- walking the dense array beats iterating the weak part table
			local arr = x6.active_array
			local data = x6.a
			for i = #arr, 1, -1 do
				local d = data[arr[i]]
				if d and d.lv then
					d.lv.VectorVelocity = ANTI_SLEEP
				end
				if d and d.av and d.angular_active then d.av.AngularVelocity = ZERO_VECTOR end
			end
			return
		end
		pcall(f3_body, real_dt)
	end

	function x4.ProcessQueue()
		if x6.torn_down then return  end
		local queue = x6.claim_queue
		-- Luau's # is a binary search, not a stored field, and the old loop paid
		-- for it four times per item (the while test, the read, the clear, and
		-- once inside every table.insert). Carrying the length in a local drops
		-- all of them. This runs every frame during the initial workspace sweep,
		-- when the queue is thousands of entries deep, so it is the difference
		-- between a smooth start and a stutter.
		local n = #queue
		if n == 0 then
			return
		end
		-- The budget is the claim throttle, and a throttle is the trade Max Fidelity
		-- refuses: it spends a smooth start to have every part in hand sooner. The
		-- three ceilings stay finite so a queue of a hundred thousand descendants
		-- still cannot hang the frame outright.
		local max_fid = x1.MaxFidelity and true or false
		local cap_processed = max_fid and 4000 or 100
		local cap_claimed = max_fid and 400 or 8
		local cap_seconds = max_fid and 0.008 or 0.001
		local start = os.clock()
		local processed = 0
		local claimed = 0
		-- Target Part Count. The ceiling withholds the claim and nothing else: the queue
		-- is a DFS stack of *instances*, not of parts, so bailing out of the walk would
		-- abandon the traversal and quietly lose whole branches of the workspace for the
		-- rest of the session -- including every part inside them if the ceiling is later
		-- raised. Descendants keep being enumerated either way.
		local cap = x1.TargetParts or 0
		while n > 0 do
			if processed >= cap_processed or claimed >= cap_claimed or os.clock() - start > cap_seconds then
				break
			end
			local instance = queue[n]
			queue[n] = nil
			n = n - 1
			processed = processed + 1
			if instance and instance:IsDescendantOf(v4) then
				for _, child in ipairs(instance:GetChildren()) do
					n = n + 1
					queue[n] = child
				end
				if instance:IsA("BasePart") and (cap <= 0 or x6.n < cap) then
					if x4.f1(instance) then
						claimed = claimed + 1
					end
				end
			end
		end
	end

	local function f4(real_dt)
		real_dt = real_dt or (1/60)
		if x6.torn_down or not x6.b or x1.Disabled then
			return
		end
		-- One root lookup, one copy of the "move the core onto it" code. The
		-- fall-through rules are unchanged: a selected-but-unreachable target
		-- parks the core, an unreachable self-anchor falls back to dragging.
		local track = nil
		if x1.TgtActive and x1.Targets and #x1.Targets > 0 then
			local tgt = x1.Targets[1]
			local root = root_of(tgt and tgt.Character)
			if not (root and ((x1.VoidProtection == false) or (root.Position.Y > v4.FallenPartsDestroyHeight + 50))) then
				return
			end
			track = root
		elseif x1.AnchorSelf then
			track = root_of(v8.Character)
		end
		if track then
			local pos = track.Position
			if x1.PredictiveTracking then
				pos = get_predicted_pos(track, x1.PredictionFactor or 150)
			end
			x6.b.Position = pos
			x6.b.AssemblyLinearVelocity = ZERO_VECTOR
			return
		end
		if x6.d then
			local c = v4.CurrentCamera
			if not c then
				return
			end
			x6.p = x6.p or (x6.b.Position - c.CFrame.Position).Magnitude
			local mp = v1:GetMouseLocation()
			local r = c:ViewportPointToRay(mp.X, mp.Y)
			local tp = r.Origin + (r.Direction * x6.p)
			local alpha = x9.c8 >= 1 and 1 or (1 - math.exp(-60 * real_dt * -math.log(math.max(0.001, 1 - x9.c8))))
			x6.b.Position = x6.b.Position:Lerp(tp, alpha)
			x6.b.AssemblyLinearVelocity = ZERO_VECTOR
		end
	end

	function x4.f1(p)
		if x6.torn_down then return false end
		if not p:IsA("BasePart") or x7.e(p) or x6.a[p] then
			return false
		end
		local old_attachment = p:FindFirstChild("GRV_ATT")
		local old_linear_velocity = p:FindFirstChild("GRV_LV")
		local old_angular_velocity = p:FindFirstChild("GRV_AV")
		if old_attachment then old_attachment:Destroy() end
		if old_linear_velocity then old_linear_velocity:Destroy() end
		if old_angular_velocity then old_angular_velocity:Destroy() end
		local original_can_collide = p.CanCollide
		local original_anchored = p.Anchored
		local original_properties = p.CustomPhysicalProperties
		-- A part claimed while the script is disabled has to land in the same state
		-- as the ones already held, or it would hang frozen in mid-air with its
		-- collision stripped until the next enable. x4.apply_disabled re-applies
		-- all three of these to every part when the flag flips.
		if not (x1.PreserveCollisions or x1.Disabled) then
			p.CanCollide = false
		end
		p.Anchored = false
		if not x1.Disabled then
			p.CustomPhysicalProperties = LIGHT_PHYSICS
		end
		-- Parent last: every property set on an already-parented instance costs a
		-- replication/physics update the engine then has to throw away.
		local a = Instance.new("Attachment")
		a.Name = "GRV_ATT"

		local lv = Instance.new("LinearVelocity")
		lv.Name = "GRV_LV"
		lv.MaxForce = x1.Disabled and 0 or x1.k4
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.Attachment0 = a

		local av = Instance.new("AngularVelocity")
		av.Name = "GRV_AV"
		av.MaxTorque = x1.Disabled and 0 or math.huge
		av.RelativeTo = Enum.ActuatorRelativeTo.World
		av.AngularVelocity = Vector3.zero
		av.Attachment0 = a

		a.Parent = p
		lv.Parent = p
		av.Parent = p

		x6.part_id_counter = (x6.part_id_counter or 0) + 1
		x6.a[p] = {
			at = a,
			lv = lv,
			av = av,
			integral = Vector3.zero,
			claim_t = time(),
			id = x6.part_id_counter,
			original_can_collide = original_can_collide,
			original_anchored = original_anchored,
			original_properties = original_properties,
		}
		table.insert(x6.active_array, p)
		x6.n = x6.n + 1
		-- The population changed, so the slot ordering and the part-count ceiling both
		-- have work to do. Set here rather than computed in the loop because this is the
		-- only place that knows it happened; f3_body then services it on a stride.
		x6.slot_dirty = true
		return true
	end

	-- Hoisted out of x4.f2 so releasing a few thousand parts does not allocate a
	-- few thousand closures on the way out.
	function f2_restore(p, d, drop_release)
		if d then
			p.CanCollide = d.original_can_collide
			p.Anchored = d.original_anchored
			p.CustomPhysicalProperties = d.original_properties
		end
		if drop_release then
			p.AssemblyLinearVelocity = (d and d.release_velocity) or ZERO_VECTOR
			p.AssemblyAngularVelocity = (d and d.release_spin) or ZERO_VECTOR
		end
	end

	function x4.f2(p, drop_release, active_index)
		local d = x6.a[p]
		pcall(f2_restore, p, d, drop_release)
		if d then
			if d.at and d.at.Parent then
				d.at:Destroy()
			end
			if d.lv and d.lv.Parent then
				d.lv:Destroy()
			end
			if d.av and d.av.Parent then
				d.av:Destroy()
			end
			x6.a[p] = nil
			drop_pc_selection(p)
		end
		local idx = active_index
		if not idx or x6.active_array[idx] ~= p then
			idx = table.find(x6.active_array, p)
		end
		if idx then
			local arr = x6.active_array
			local last = #arr
			if idx ~= last then
				arr[idx] = arr[last]
			end
			-- the element being dropped is always the last one by this point, so
			-- table.remove's shift machinery and return value are pure overhead.
			-- Releasing a few thousand parts at once is where it showed up as a
			-- visible hitch; this matches what the sweep loop already does.
			arr[last] = nil
			x6.n = math.max(0, x6.n - 1)
			x6.slot_dirty = true
		end
	end

	function x4.f3()
		if x6.torn_down then return end
		local originals = setmetatable({}, { __mode = "k" })
		local anti_fling_cache = setmetatable({}, { __mode = "k" })
		local anti_fling_conns = setmetatable({}, { __mode = "k" })
		local function read_property(obj, key, hidden)
			if hidden and gethiddenproperty then return gethiddenproperty(obj, key) end
			return obj[key]
		end
		local function write_property(obj, key, value, hidden)
			if hidden and sethiddenproperty then sethiddenproperty(obj, key, value)
			else obj[key] = value end
		end
		local function remember_set(obj, key, value, hidden)
			local saved = originals[obj]
			if not saved then saved = {}; originals[obj] = saved end
			if not saved[key] then
				local ok, original = pcall(read_property, obj, key, hidden)
				if not ok then return end
				saved[key] = { value = original, hidden = hidden }
			end
			write_property(obj, key, value, hidden)
		end
		function x4.restore_environment()
			for _, conn in pairs(anti_fling_conns) do pcall(function() conn:Disconnect() end) end
			table.clear(anti_fling_conns)
			table.clear(anti_fling_cache)
			for obj, saved in pairs(originals) do
				for key, original in pairs(saved) do
					pcall(write_property, obj, key, original.value, original.hidden)
				end
			end
			table.clear(originals)
		end
		local function suppress_player(p)
			remember_set(p, "MaximumSimulationRadius", 0)
			remember_set(p, "SimulationRadius", 0, true)
		end
		local function wake_self() remember_set(v8, "NetworkIsSleeping", false, true) end
		local function raise_max_radius() remember_set(v8, "MaximumSimulationRadius", 9e9) end
		local function raise_sim_radius() remember_set(v8, "SimulationRadius", 9e9, true) end
		local function focus_replication() remember_set(v8, "ReplicationFocus", x6.b) end
		local function keep_awake() remember_set(settings().Physics, "AllowSleep", false) end

		local last_upd = 0
		table.insert(
			x6.c,
			v3.Heartbeat:Connect(function()
				if x6.torn_down or not x6.o then return end
				local now = time()
				if now - last_upd > 0.5 then
					last_upd = now
					-- Only while the engine is actually running. This writes to *other*
					-- players, and x4.f5 does not drain x6.c (it cannot -- the hotkey
					-- listeners live there too, so draining it would make the script
					-- unrestartable), so without this gate "Stop" left every other
					-- player pinned at SimulationRadius 0 for the rest of the session.
					if x6.o then
						for _, p in ipairs(v2:GetPlayers()) do
							if p ~= v8 then
								pcall(suppress_player, p)
							end
						end
					end
					pcall(wake_self)
					pcall(keep_awake)
					pcall(raise_max_radius)
					pcall(raise_sim_radius)
					pcall(focus_replication)
				end
			end)
		)
		-- Targets hold live Player objects and nothing ever pruned them. A player who
		-- leaves stays in the list: the HUD keeps reading DisplayName off a destroyed
		-- instance and reports ACTIVE forever, and f3_body tracks Targets[1] -- whose
		-- root is now nil -- so it returns before the AnchorSelf and mouse-drag
		-- fallbacks and the core parks with no explanation. Worse on rejoin, since
		-- Roblox issues a *new* Player object: table.find misses, the row draws
		-- unselected, and clicking it appends alongside the phantom, so the panel
		-- reads "Multi-Target (2)" for one person.
		table.insert(
			x6.c,
			v2.PlayerRemoving:Connect(function(pl)
				local tg = x1.Targets
				if type(tg) ~= "table" then
					return
				end
				local idx = table.find(tg, pl)
				while idx do
					table.remove(tg, idx)
					idx = table.find(tg, pl)
				end
				x1.TgtActive = #tg > 0
				local ui = context.x5
				if ui and ui.up then
					pcall(ui.up)
				end
			end)
		)
		-- The DescendantAdded hook lives here, keyed weakly by character, instead
		-- of in x6.c. x6.c is a strong list only emptied on full teardown, so
		-- every respawn added an entry whose closure pinned that character's part
		-- array -- which is exactly why the weak cache above could never actually
		-- collect anything. A long session leaked one connection and one array
		-- per respawn. Held weakly, both go away with the character (Destroy
		-- severs the signal on its own).
		local function connect_parts(char, parts)
			return char.DescendantAdded:Connect(function(desc)
				if desc:IsA("BasePart") then
					parts[#parts + 1] = desc
				end
			end)
		end
		local af_tick = 0
		table.insert(
			x6.c,
			v3.Stepped:Connect(function()
				if not x6.o or not x1.AntiFling or x1.PreserveCollisions then
					return
				end
				-- 20 Hz is plenty. The server is what re-enables collisions, and it
				-- does not do it every frame, so sweeping every frame was paying
				-- roughly twenty thousand property reads a second for nothing.
				-- Max Fidelity does sweep every frame: "the server does not do it
				-- every frame" is an assumption about somebody else's code.
				af_tick = af_tick + 1
				if not x1.MaxFidelity and af_tick % 3 ~= 0 then
					return
				end
				for _, p in ipairs(v2:GetPlayers()) do
					-- p.Character was re-read five times per player per tick, each
					-- one an engine crossing. Now read once.
					local char = p ~= v8 and p.Character or nil
					if char then
						local parts = anti_fling_cache[char]
						if not parts then
							parts = {}
							for _, part in ipairs(char:GetDescendants()) do
								if part:IsA("BasePart") then
									parts[#parts + 1] = part
								end
							end
							anti_fling_cache[char] = parts
							local ok, conn = pcall(connect_parts, char, parts)
							if ok then
								anti_fling_conns[char] = conn
							end
						end
						for i = #parts, 1, -1 do
							local part = parts[i]
							if part and part.Parent then
								if part.CanCollide then
									remember_set(part, "CanCollide", false)
								end
							else
								table.remove(parts, i)
							end
						end
					end
				end
			end)
		)
	end

	-- Whether the core ball is shown, in one place. Three call sites used to
	-- decide it independently (creation, apply_disabled, and nothing at all for
	-- pause), which is why adding a second reason to hide it needed a single
	-- owner. Hidden means invisible, not inert: the part stays anchored where it
	-- is and a tap still finds it, so dragging the core around while it is hidden
	-- keeps working exactly as it already did while Disabled.
	local function refresh_core_visual()
		if not x6.b then
			return
		end
		local hidden = x1.Disabled or (x1.HideCoreOnPause and x1.Paused) or false
		x6.b.Transparency = hidden and 1 or x9.c7
		local visual = x6.b:FindFirstChild("Visual")
		if visual then
			visual.Enabled = not hidden
		end
	end
	x4.refresh_core_visual = refresh_core_visual

	function x4.f4(pos)
		if x6.torn_down then return  end
		if x6.b then
			v6:Create(x6.b, TweenInfo.new(x9.c7), { Position = pos }):Play()
			return
		end
		local f = Instance.new("Folder", v4)
		f.Name = "AS"
		x6.core_folder = f
		x6.b = Instance.new("Part", f)
		x6.b.Size = x1.k2
		x6.b.Shape = "Ball"
		x6.b.Color = x1.k3
		x6.b.Anchored = true
		x6.b.CanCollide = false
		x6.b.Material = "Neon"
		x6.b.Position = pos
		local bg = Instance.new("BillboardGui", x6.b)
		bg.Name = "Visual"
		bg.Adornee = x6.b
		bg.Size = UDim2.new(0, 20, 0, 20)
		bg.AlwaysOnTop = true
		local img = Instance.new("ImageLabel", bg)
		img.BackgroundTransparency = 1
		img.Size = UDim2.new(1, 0, 1, 0)
		img.Image = "rbxassetid://3570695787"
		img.ImageColor3 = x1.k3
		-- Disabled survives a restart through the settings file, so the core has to
		-- come up already hidden in that case rather than showing a visible marker
		-- for something that is not driving anything. After the BillboardGui exists,
		-- so the one call covers both the part and the sprite.
		refresh_core_visual()
		v6
			:Create(
				x6.b,
				TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Size = x1.k2 * 1.2 }
			)
			:Play()
		table.clear(x6.claim_queue)
		for _, child in ipairs(v4:GetChildren()) do
			if child ~= f then
				table.insert(x6.claim_queue, child)
			end
		end

		x6.run_connections = x6.run_connections or {}
		table.insert(
			x6.run_connections,
			v4.DescendantAdded:Connect(function(v)
				if v:IsA("BasePart") then
					table.insert(x6.claim_queue, v)
				end
			end)
		)
		x6.o = true
		x7.n("Sys", "Started", 3)
		-- Refresh the panel if it is open; do not resurrect it if the user closed it.
		-- x5.st() rebuilds from scratch whenever x5.g is nil, and the panel's X button
		-- nils it (UI.lua sg.Destroying) -- so pressing Recenter after closing the
		-- panel used to rebuild the whole thing, and every rebuild strands another
		-- five service-level connections in x6.c that only full teardown clears.
		if x5.g then
			x5.st()
		end
		table.insert(
			x6.run_connections,
			v3.Heartbeat:Connect(function(real_dt)
				f3(real_dt)
				f4(real_dt)
				x4.ProcessQueue()
			end)
		)
	end

	-- Release every claimed part but leave the core where it is. The action dock
	-- has always called this; it just never existed until now.
	function x4.clean_physics()
		-- The old loop took the array length three times per part (the while
		-- test, the index, and the argument), and # is a binary search in Luau.
		-- A plain descending index removes ~15k probes on a 5000 part release.
		-- f2 always drops the element at the index it is handed, which is the
		-- current last, so walking downward stays in step with the shrinking array.
		local arr = x6.active_array
		local released = #arr
		for k = released, 1, -1 do
			x4.f2(arr[k], true, k)
		end
		table.clear(x6.claim_queue)
		x7.n("Sys", released .. " parts released", 2)
	end

	-- Slot Assignment. Which part goes where.
	--
	-- A part's place in a pattern comes from d.id today, and d.id is the claim counter:
	-- the formation is ordered by the accident of which part the workspace walk reached
	-- first, and the numbering is sparse and only ever rises -- shapes/Raigo.lua:19
	-- records what an unbounded index does to a shape that maps it onto a sphere.
	-- d.slot is dense, 1..N, and stable for as long as the population is.
	--
	-- "Claim" mode writes nil rather than slots in claim order, deliberately: nil is
	-- what the shapes saw before any of this existed, so the default mode is provably
	-- the old path and no shape can pick up an index it did not have.
	local slot_parts = {}
	local slot_keys = setmetatable({}, { __mode = "k" })
	local slot_ids = setmetatable({}, { __mode = "k" })
	local function slot_less(a, b)
		local ka, kb = slot_keys[a], slot_keys[b]
		if ka == kb then
			-- Every comparator breaks ties on the claim id, so a set that has not changed
			-- sorts identically on every call. Without it table.sort's ordering of equal
			-- keys is unspecified, and parts trade places on the stride for no reason --
			-- which on a map of uniform bricks is every part, every quarter second.
			return (slot_ids[a] or 0) < (slot_ids[b] or 0)
		end
		return ka < kb
	end

	-- A deterministic hash rather than math.random: a fresh roll per stride is not a
	-- shuffle, it is noise. Both multiplies stay well inside 2^53, so the arithmetic is
	-- exact in a double and the same (id, seed) pair always lands on the same key.
	local function shuffle_key(id, seed)
		local x = (id * 2654435 + seed * 40503 + 1) % 1048573
		return (x * 1103515 + 12345) % 1048573
	end

	local SLOT_MODES = {
		Claim = true,
		["Size Desc"] = true,
		["Size Asc"] = true,
		Distance = true,
		Shuffle = true,
	}
	local SURPLUS_RULES = {
		Farthest = true,
		Nearest = true,
		Newest = true,
		Oldest = true,
		Smallest = true,
		Largest = true,
	}

	function x4.reindex_slots()
		local arr = x6.active_array
		local data = x6.a
		local mode = x1.SlotMode or "Claim"
		-- A hand-edited or half-migrated settings file is the one path that can put an
		-- unrecognised string in here, and the safe reading of one is the inert mode --
		-- not whatever the comparison chain below happens to fall through to.
		if not SLOT_MODES[mode] then
			mode = "Claim"
		end
		-- Cleared up here rather than beside the sort, so it happens on the Claim path
		-- too. slot_parts is a plain array of parts and this function lives for the whole
		-- session: left populated on the early return, it pinned every part of the last
		-- sorted population -- destroyed or not -- for as long as the mode stayed Claim.
		-- x6.a is weak-keyed to make exactly that collectable. The other two are
		-- weak-keyed themselves and are cleared here only to keep the three in step.
		table.clear(slot_parts)
		table.clear(slot_keys)
		table.clear(slot_ids)
		local n = #arr
		if mode == "Claim" then
			for i = 1, n do
				local d = data[arr[i]]
				if d then
					d.slot, d.slot_n = nil, nil
				end
			end
			return 0
		end
		local cen = x6.b and x6.b.Position or nil
		local seed = x1.SlotSeed or 0
		local m = 0
		for i = 1, n do
			local p = arr[i]
			local d = p and data[p]
			if d then
				m = m + 1
				slot_parts[m] = p
				slot_ids[p] = d.id or i
				local key
				if mode == "Size Desc" then
					key = -part_size(p)
				elseif mode == "Size Asc" then
					key = part_size(p)
				elseif mode == "Distance" then
					-- Squared, not the distance: monotone, so the ordering is identical
					-- and it saves a sqrt per part per stride.
					if cen then
						local off = p.Position - cen
						key = off:Dot(off)
					else
						key = 0
					end
				else
					key = shuffle_key(d.id or i, seed)
				end
				slot_keys[p] = key
			end
		end
		if m > 1 then
			table.sort(slot_parts, slot_less)
		end
		for i = 1, m do
			local d = data[slot_parts[i]]
			if d then
				d.slot, d.slot_n = i, m
			end
		end
		return m
	end

	-- Re-roll. Clears the per-part scratch for every held part, which makes every shape
	-- that seeds a random phase lazily (`if not d.v6 then d.v6 = math.random() * ... end`
	-- is the idiom, in 32 places) re-seed on its next frame: a new scatter of the same
	-- shape without dropping the claim. Bumping the seed re-orders Shuffle at the same
	-- time, so one action means "lay this out again" whichever mechanism is doing it.
	function x4.reroll_seeds()
		local arr = x6.active_array
		local data = x6.a
		local n = 0
		for k = 1, #arr do
			local d = data[arr[k]]
			if d then
				reset_scratch(d)
				n = n + 1
			end
		end
		x1.SlotSeed = ((x1.SlotSeed or 0) + 1) % 100000
		x6.slot_dirty = true
		return n
	end

	-- Target Part Count and Claim Rules share this walk. Both pick a set of held parts and
	-- release it, and both have to do it without the O(n^2) that a table.find per release
	-- would cost on a few thousand parts.
	--
	-- Descending, and x4.f2 is handed the index: f2 fills the hole by moving the array's
	-- last element into it, and every index above k has already been visited by the time we
	-- get to k, so the element that moves down is one this walk is finished with. The length
	-- shrinks under us, which is why arr[k] is re-read and nil-checked rather than captured.
	--
	-- No count ceiling here, deliberately: the mark set *is* the ceiling. Each part appears
	-- in active_array once (x4.f1 refuses a part it already holds), so the walk cannot
	-- release more than was marked, and a `released >= limit` break would be a branch that
	-- can never be taken -- which mutation testing duly proved it was.
	local function release_marked(mark)
		local arr = x6.active_array
		local released = 0
		for k = #arr, 1, -1 do
			local p = arr[k]
			if p and mark[p] then
				-- drop_release: zero the velocity on the way out so the part falls where
				-- it was instead of keeping whatever the constraint last wrote to it.
				x4.f2(p, true, k)
				released = released + 1
			end
		end
		if released > 0 then
			x6.slot_dirty = true
		end
		return released
	end

	local cap_parts = {}
	local cap_keys = setmetatable({}, { __mode = "k" })
	local cap_ids = setmetatable({}, { __mode = "k" })
	local function cap_less(a, b)
		local ka, kb = cap_keys[a], cap_keys[b]
		if ka == kb then
			return (cap_ids[a] or 0) < (cap_ids[b] or 0)
		end
		return ka < kb
	end

	-- Every key below is a release priority, sorted ascending, so the first `over`
	-- entries are the ones that go. Parts under Part Control are never surplus: they were
	-- placed by hand, and a ceiling that quietly deletes a pinned assembly is not a
	-- ceiling.
	function x4.enforce_part_cap()
		-- Cleared before the early returns, for the reason reindex_slots gives: cap_parts
		-- is a plain array of parts, and the common case is returning early with the
		-- ceiling off, which would otherwise leave the last enforced population pinned
		-- against a weak table built to let it go.
		table.clear(cap_parts)
		table.clear(cap_keys)
		table.clear(cap_ids)
		local cap = x1.TargetParts or 0
		if cap <= 0 then
			return 0
		end
		local arr = x6.active_array
		local data = x6.a
		local over = #arr - cap
		if over <= 0 then
			return 0
		end
		local rule = x1.SurplusRule or "Farthest"
		if not SURPLUS_RULES[rule] then
			rule = "Farthest"
		end
		local cen = x6.b and x6.b.Position or nil
		local m = 0
		for i = 1, #arr do
			local p = arr[i]
			local d = p and data[p]
			if d and d.pc_mode == nil then
				m = m + 1
				cap_parts[m] = p
				cap_ids[p] = d.id or i
				local key = 0
				if rule == "Newest" then
					key = -(d.id or i)
				elseif rule == "Oldest" then
					key = d.id or i
				elseif rule == "Smallest" then
					key = part_size(p)
				elseif rule == "Largest" then
					key = -part_size(p)
				elseif cen then
					local off = p.Position - cen
					local d2 = off:Dot(off)
					key = rule == "Nearest" and d2 or -d2
				end
				cap_keys[p] = key
			end
		end
		if m == 0 then
			return 0
		end
		if m > 1 then
			table.sort(cap_parts, cap_less)
		end
		if over > m then
			over = m
		end
		local mark = {}
		for i = 1, over do
			mark[cap_parts[i]] = true
		end
		return release_marked(mark)
	end

	-- Editing a rule has to do something to the formation in front of you, not only to
	-- the next claim. The radius rule is excluded on purpose: the core moves, so a radius
	-- that evicted held parts would release and re-claim continuously as you walked.
	function x4.recheck_rules()
		local arr = x6.active_array
		local mark = nil
		for i = 1, #arr do
			local p = arr[i]
			if p and rule_reject(p, false) then
				mark = mark or {}
				mark[p] = true
			end
		end
		if not mark then
			return 0
		end
		return release_marked(mark)
	end

	-- Formation Preview. Ghost markers that run the selected shape's math and show where
	-- the formation would put parts, with nothing claimed and nothing grabbed -- which is
	-- the only way to tune a shape, or to author one, in a game with nothing unanchored
	-- in it.
	--
	-- The markers live in a Folder inside the core's own AS folder, so both teardown
	-- paths already reach them: x4.f5 destroys x6.b.Parent and main.lua's destroy()
	-- destroys the same holder. preview_clear is called from the toggle, from f5 and from
	-- apply_disabled as well; the parenting is the backstop, because a missed call should
	-- still not be able to leave parts in somebody's game.
	local GHOST_SIZE = Vector3.new(1.6, 1.6, 1.6)
	local GHOST_LIMIT = 4000

	function x4.preview_clear()
		local g = x6.ghosts
		if g then
			for i = #g, 1, -1 do
				local part = g[i]
				if part then
					pcall(part.Destroy, part)
				end
				g[i] = nil
			end
		end
		if x6.ghost_folder then
			pcall(x6.ghost_folder.Destroy, x6.ghost_folder)
		end
		x6.ghosts, x6.ghost_pos, x6.ghost_d, x6.ghost_folder = nil, nil, nil, nil
	end
	x6.preview_clear = x4.preview_clear

	function x4.preview_step(clock, cen, f2, cfg, real_dt)
		if not f2 or not x6.b or not cen then
			x4.preview_clear()
			return 0
		end
		local want = x1.PreviewCount
		if type(want) ~= "number" or want ~= want then
			want = 40
		end
		want = math.floor(math.clamp(want, 4, 200))

		local folder = x6.ghost_folder
		if folder and not folder.Parent then
			-- The holder went away under us -- a stop, or a re-execution -- and took the
			-- parts with it, so drop the pool rather than writing to dead instances.
			x4.preview_clear()
			folder = nil
		end
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "GRV_PREVIEW"
			folder.Parent = x6.b.Parent or v4
			x6.ghost_folder = folder
		end
		local ghosts, pos, recs = x6.ghosts, x6.ghost_pos, x6.ghost_d
		if not ghosts or not pos or not recs then
			ghosts, pos, recs = {}, {}, {}
			x6.ghosts, x6.ghost_pos, x6.ghost_d = ghosts, pos, recs
		end

		for i = #ghosts, want + 1, -1 do
			local part = ghosts[i]
			if part then
				pcall(part.Destroy, part)
			end
			ghosts[i], pos[i], recs[i] = nil, nil, nil
		end
		for i = #ghosts + 1, want do
			local part = Instance.new("Part")
			part.Name = "GRV_GHOST"
			part.Size = GHOST_SIZE
			-- Anchored is not decoration: x7.e refuses an anchored part, which is what
			-- keeps the claim sweep running beside these from picking them up.
			part.Anchored = true
			part.CanCollide = false
			part.CastShadow = false
			part.Massless = true
			part.Material = Enum.Material.SmoothPlastic
			part.Color = x1.k3
			part.Transparency = 0.6
			part.Position = cen
			part.Parent = folder
			ghosts[i] = part
			pos[i] = cen
			recs[i] = { id = i, integral = ZERO_VECTOR }
		end
		return x4.preview_run(ghosts, pos, recs, want, clock, cen, f2, cfg, real_dt)
	end

	-- The step itself, split out so the pool management above and the field evaluation
	-- here can be tested separately -- and because this is the half that has to mirror
	-- the sweep's blend, which is the thing most likely to drift.
	function x4.preview_run(ghosts, pos, recs, want, clock, cen, f2, cfg, real_dt)
		local step = real_dt or (1 / 60)
		local bf2, bcfg, bwb, bs = x6.bl_f2, x6.bl_cfg, x6.bl_w or 0, x6.bl_s or 0
		for i = 1, want do
			local part = ghosts[i]
			local rec = recs[i]
			if part and rec then
				rec.slot, rec.slot_n = i, want
				local pt = pos[i] or cen
				-- Written before the shape runs, so a shape that reads p.Position sees the
				-- position this preview is actually tracking. The authoritative copy stays
				-- in Lua: reading it back off the instance would integrate whatever the
				-- engine rounded into the next step.
				part.Position = pt
				local ok, delta, pure = pcall(f2, part, cen, rec, clock, cfg, x1, x6, x9)
				if not ok then
					delta, pure = nil, nil
				end
				if bf2 then
					local frac = want > 1 and ((i - 1) / (want - 1)) or 0
					local bw = blend_w(bwb, bs, frac)
					if bw > 0 then
						local bd = rec.bd
						if not bd then
							bd = { id = rec.id, integral = ZERO_VECTOR }
							rec.bd = bd
						end
						bd.slot, bd.slot_n = i, want
						local bok, b_delta, b_pure = pcall(bf2, part, cen, bd, clock, bcfg, x1, x6, x9)
						if bok then
							if typeof(b_delta) == "Vector3" and typeof(delta) == "Vector3" then
								delta = delta:Lerp(b_delta, bw)
							elseif typeof(b_delta) == "Vector3" then
								delta = b_delta
							end
							if typeof(pure) == "Vector3" and typeof(b_pure) == "Vector3" then
								pure = pure:Lerp(b_pure, bw)
							elseif bw >= 1 then
								pure = b_pure
							else
								pure = nil
							end
						end
					end
				end
				-- typeof rather than a truth test, and only here: the preview is the path
				-- most likely to be pointed at a half-written shape (the AI writes local
				-- ones straight into GravityShapes), and a shape that hands back a number
				-- instead of a Vector3 would otherwise throw out of the arithmetic below,
				-- past the pcall that guards the call itself, and take the frame with it.
				local np = pt
				if typeof(pure) == "Vector3" then
					np = pure
				elseif typeof(delta) == "Vector3" then
					-- The same Euler step the LinearVelocity constraint takes on a real
					-- part: what a shape hands back is a velocity, so this is what the part
					-- this marker stands for would do with it.
					np = pt + (delta * step)
				end
				-- A shape handed a population of zero -- which is the normal case for the
				-- preview -- can divide by it and hand back a NaN, and writing one into a
				-- Position is an engine error rather than a wrong picture. Checked before
				-- the radius clamp, because clamping an infinity produces a NaN of its own.
				local nx, ny, nz = np.X, np.Y, np.Z
				if
					nx ~= nx or ny ~= ny or nz ~= nz
					or nx > 1e18 or nx < -1e18
					or ny > 1e18 or ny < -1e18
					or nz > 1e18 or nz < -1e18
				then
					np = cen
				end
				-- Ghosts are driven by a field that a real part's mass and the loop's speed
				-- limit would damp, and neither applies here, so an unconstrained shape can
				-- walk one out of the world. Held to a radius rather than a speed, since
				-- that is the failure that matters for something you are looking at.
				local off = np - cen
				local d2 = off:Dot(off)
				if d2 > GHOST_LIMIT * GHOST_LIMIT then
					np = cen + (off * (GHOST_LIMIT / math.sqrt(d2)))
				end
				pos[i] = np
				part.Position = np
			end
		end
		return want
	end

	-- Disabling is clean_physics without giving up the claim: the constraints stay
	-- on the part so enabling picks up instantly, but nothing drives it and it gets
	-- its collision back, so it falls and lands like a released part in the
	-- meantime. Enabling reverses both halves. Hoisted out of the loop below so a
	-- 5000 part toggle does not allocate a closure per part for pcall.
	local function apply_disabled_part(p, d, disabled)
		if d.free_physics then ShapePhysics.apply(p, d, x1); return end
		if d.lv then
			d.lv.MaxForce = disabled and 0 or x1.k4
		end
		if d.av then
			d.av.MaxTorque = disabled and 0 or math.huge
		end
		ShapePhysics.apply_collisions(p, d, x1)
		-- LIGHT_PHYSICS is what lets the constraints throw a part around; at 0.001
		-- density a disabled part would be shoved across the map by the first thing
		-- that touched it instead of resting where it landed. Anchored is left alone
		-- because x7.e refuses to claim an anchored part in the first place.
		-- Not an `and/or` chain: original_properties is nil on any part that never
		-- overrode its material defaults, and nil is falsy, so that would hand every
		-- such part LIGHT_PHYSICS back on the disable branch.
		if disabled then
			p.CustomPhysicalProperties = d.original_properties
		elseif d.pc_ride then
			p.CustomPhysicalProperties = d.original_properties or PhysicalProperties.new(0.7, 0.5, 0.3, 1, 1)
		else
			p.CustomPhysicalProperties = LIGHT_PHYSICS
			-- Parts fall while disabled, so every cached smoothing term now
			-- describes a position they have long since left. d.last_target_pos in
			-- particular is differentiated against the live target, and dividing a
			-- whole fall's worth of displacement by one frame injects thousands of
			-- studs/s -- the same re-seat fling f3_body's target-velocity clamp
			-- exists to stop. Clearing them makes enabling a fresh lift-off.
			d.vl = nil
			d.trans_vl = nil
			d.last_target_pos = nil
			d.sys_last_t = nil
			d.parked = nil
			d.integral = Vector3.zero
			-- The cached terms above are Lua-side; these are the live properties the
			-- engine is still holding. f3 returns early while disabled, so nothing
			-- overwrites them, and MaxForce goes back to x1.k4 (math.huge) here --
			-- before the sweep next reaches this part, which is only once every
			-- x1.k7 frames. Left armed, the part is driven at its pre-disable
			-- velocity at infinite force for those frames: exactly the fling the
			-- comment above is about.
			if d.lv then
				d.lv.VectorVelocity = ZERO_VECTOR
			end
			if d.av then
				d.av.AngularVelocity = ZERO_VECTOR
			end
		end
	end

	-- The one entry point for the flag: the L hotkey, the UI toggle, the mobile
	-- action dock and the AI tool all come through here, so none of them can leave
	-- the parts half-switched. The core visuals are handled whether or not the
	-- panel is open.
	function x4.apply_disabled(disabled)
		disabled = disabled and true or false
		x1.Disabled = disabled
		if disabled then
			-- A shape-owned instance is part of the shape running. Platform's pad in
			-- particular would otherwise be left as a solid slab hanging in the air
			-- with nothing updating it. px rebuilds it on the first enabled frame.
			cleanup_shape(x1.k6)
			-- The blend shape owns instances on exactly the same terms, and f3_body -- the
			-- only thing that tracks x6.last_blend -- returns early while disabled, so it
			-- cannot notice the blend went inert.
			if x6.last_blend and x6.last_blend ~= x1.k6 then
				cleanup_shape(x6.last_blend)
			end
			x6.last_blend = nil
			-- Ghosts are markers for a formation that is not being driven any more, and
			-- f3_body's own clear is unreachable from here for the same reason.
			x4.preview_clear()
		end
		if x6.b then
			refresh_core_visual()
		end
		-- the dense array again, rather than iterating the weak part table
		local arr = x6.active_array
		local data = x6.a
		for k = #arr, 1, -1 do
			local p = arr[k]
			local d = p and data[p]
			if d then
				pcall(apply_disabled_part, p, d, disabled)
			end
		end
	end

	function x4.clear_target_markers()
		for _, pl in ipairs(v2:GetPlayers()) do
			local ch = pl.Character
			local head = ch and ch:FindFirstChild("Head")
			local marker = head and head:FindFirstChild("GravityTargetMarker")
			if marker then
				pcall(function()
					marker:Destroy()
				end)
			end
		end
	end

	function x4.f5()
		x6.o, x6.d = false, false
		if x4.restore_environment then x4.restore_environment() end
		if x6.mobile_reset then x6.mobile_reset() end
		-- Before the core folder goes, so a shape-owned instance living inside it is
		-- released deliberately rather than only incidentally.
		cleanup_shape(x1.k6)
		-- Both of these live under the core folder too, and both have an owner that only
		-- runs inside f3_body: x6.last_blend is what hands a blended shape its instance
		-- back, and the ghost pool is destroyed with its folder either way. Explicit here
		-- so "Stop" is a full stop rather than a race with the next frame.
		if x6.last_blend and x6.last_blend ~= x1.k6 then
			cleanup_shape(x6.last_blend)
		end
		x6.last_blend = nil
		x4.preview_clear()
		local core, holder = x6.b, x6.core_folder
		x6.b, x6.core_folder = nil, nil
		if core then pcall(function() core:Destroy() end) end
		if holder then pcall(function() holder:Destroy() end) end
		-- same descending walk as clean_physics: three length probes per part
		-- became none, which is what made stopping with a large claim hitch.
		local arr = x6.active_array
		for k = #arr, 1, -1 do
			x4.f2(arr[k], false, k)
		end
		for _, connection in ipairs(x6.run_connections or {}) do
			connection:Disconnect()
		end
		table.clear(x6.run_connections or {})
		table.clear(x6.claim_queue)
		x6.o = false
		-- Target markers are BillboardGuis parented onto other players' heads, and the
		-- only code that removed one lived inside f3_body's once-a-second block --
		-- which stops running the moment the engine stops. So stopping, pausing or
		-- disabling left the red marker floating over whoever was targeted.
		x4.clear_target_markers()
		-- Sculptor selections are per-run: the SelectionBoxes are parented to world
		-- parts, so leaving them adorned after "Stop" leaves cyan boxes in the map.
		if x6.sculptor_clear then
			pcall(x6.sculptor_clear)
		end
		if x6.pc_clear then
			pcall(x6.pc_clear)
		end
		if x6.sculptor_selected then
			table.clear(x6.sculptor_selected)
		end
		if x6.pc_selected then
			table.clear(x6.pc_selected)
		end
		x6.pc_active = false
		-- Same as f4: refresh an open panel, never rebuild a closed one.
		if x5.g then
			x5.st()
		end
		x7.n("Sys", "Stopped", 2)
	end

	-- Desktop/mobile share the same shape and hotkey behavior.
	function x4.switch_shape(name, persist)
		if x6.torn_down then return false end
		if not name or not x2[name] then
			return false
		end
		local mod = get_shape(name)
		if x6.torn_down then return false end
		if not mod then
			x7.n("Sys", "Could not load " .. tostring(name), 3)
			return false
		end
		-- Shapes still being tuned announce themselves. A module flag rather than
		-- a name list here, following M.Drop (System.lua:376), so a shape carries
		-- its own status and nothing central has to be edited to promote one.
		if mod.Testing then
			x7.n("Testing", name .. " is still in testing.", 4)
		end
		x1.k6 = name
		x6.transition_time = time()
		x6.transition_dur = 1.5
		-- f3_body clears the rest of the per-part scratch when it notices k6
		-- moved; trans_vl is the one it cannot derive, because it needs the
		-- velocity from before the switch to ease out of.
		for _, d in pairs(x6.a) do
			d.trans_vl = d.vl or Vector3.zero
			d.v1, d.v2, d.v3, d.v4, d.v5, d.v6, d.v7, d.v8, d.v9 = nil, nil, nil, nil, nil, nil, nil, nil, nil
			d.integral = Vector3.zero
		end
		if persist ~= false and context.save_settings then
			context.save_settings()
		end
		local ui = context.x5
		if ui then
			if ui.sync_shape then
				pcall(ui.sync_shape, name)
			end
			if ui.up then
				pcall(ui.up)
			end
		end
		return true
	end

	-- Every hotkey the script owns. One list so binding, unbinding, the conflict
	-- check and the Keybinds window all read the same source; the order here is
	-- the order the window lists them in.
	local CORE_ACTIONS = {
		{ id = "Recenter", label = "Recenter Core", desc = "Move the gravity core to your cursor." },
		{ id = "Reset", label = "Stop / Reset", desc = "Release parts and remove the core. The X button fully unloads." },
		{ id = "Pause", label = "Pause Physics", desc = "Freeze held parts where they are." },
		{ id = "Disable", label = "Disable Gravity", desc = "Let parts fall without giving up the claim." },
	}
	x8.core_actions = CORE_ACTIONS
	-- Keep the mobile action IDs used by existing input consumers.
	local core_ids = { Recenter = "C", Reset = "R", Pause = "P", Disable = "Disable" }

	local core_handlers = {
		Recenter = function()
			x4.f4(v9.Hit.p)
		end,
		Reset = function()
			x4.f5()
		end,
		Pause = function()
			x1.Paused = not x1.Paused
			-- Hide Core While Paused is toggled here as well as in the panel, and
			-- the hotkey is the only way to pause at all, so this is the call site
			-- that actually matters.
			refresh_core_visual()
			x7.n("Sys", x1.Paused and "Paused" or "Resumed", 2)
		end,
		Disable = function()
			-- this used to be gated on the UI toggle existing, which meant the
			-- hotkey silently did nothing whenever the panel was closed
			x4.apply_disabled(not x1.Disabled)
			x7.n("Sys", "Script " .. (x1.Disabled and "Disabled" or "Enabled"), 2)
			-- Repaint, or the panel's "Disable Gravity" toggle keeps the state it was
			-- built with: UI_elements M.t holds its value in a private local and
			-- nothing refreshes it, so after a hotkey press the toggle read the
			-- opposite of the truth and the next click on it was a no-op that only
			-- changed its own colour. Deliberately here and not inside
			-- apply_disabled -- the panel toggle calls that itself, and rebuilding the
			-- panel from inside a toggle's own handler would destroy it mid-callback.
			local ui = context.x5
			if ui and ui.up then
				pcall(ui.up)
			end
		end,
	}

	-- Keybinds are stored as key *names* so they survive the JSON round trip.
	-- Enum.KeyCode[name] throws on anything that is not a member, so a settings
	-- file edited by hand cannot take the script down with it.
	local function key_from_name(name)
		if type(name) ~= "string" or name == "" then
			return nil
		end
		local ok, code = pcall(function()
			return Enum.KeyCode[name]
		end)
		if ok and typeof(code) == "EnumItem" and code ~= Enum.KeyCode.Unknown then
			return code
		end
		return nil
	end
	x8.key_from_name = key_from_name

	-- Kept so the old two-action dispatch still works if anything reaches for it.
	function x8.h(n, s, o)
		if x6.torn_down or s ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if n == "C" then
			core_handlers.Recenter()
			return Enum.ContextActionResult.Sink
		elseif n == "R" then
			core_handlers.Reset()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end

	local bound_actions = {}

	function x8.unbind_all()
		for i = #bound_actions, 1, -1 do
			pcall(function()
				v7:UnbindAction(bound_actions[i])
			end)
			bound_actions[i] = nil
		end
	end

	local function bind(action_name, key_code, fn)
		local ok = pcall(function()
			v7:BindAction(action_name, function(_, state)
				if x6.torn_down or state ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Pass
				end
				fn()
				return Enum.ContextActionResult.Sink
			end, false, key_code)
		end)
		if ok then
			bound_actions[#bound_actions + 1] = action_name
		end
	end

	-- Rebuilds every binding from x1.Keybinds. Called on startup and after any
	-- change in the Keybinds window, so there is never a partial state to reason
	-- about: everything the script owns comes off, then goes back on.
	function x8.rebind_all()
		x8.unbind_all()
		if x6.torn_down then return end
		local kb = x1.Keybinds
		if type(kb) ~= "table" then
			return
		end
		-- ContextActionService resolves a duplicate key to whichever action bound
		-- it last, which would make a hand-edited collision depend on pairs()
		-- order. Claiming keys in a fixed order instead -- core actions first,
		-- then shapes alphabetically -- makes the outcome the same every launch.
		local claimed = {}
		for _, entry in ipairs(CORE_ACTIONS) do
			local key_name = kb[entry.id]
			local code = key_from_name(key_name)
			if code and not claimed[key_name] then
				claimed[key_name] = true
				bind(core_ids[entry.id], code, core_handlers[entry.id])
			end
		end
		local shapes = kb.Shapes
		if type(shapes) == "table" then
			local names = {}
			for shape_name in pairs(shapes) do
				names[#names + 1] = shape_name
			end
			table.sort(names)
			for _, shape_name in ipairs(names) do
				local key_name = shapes[shape_name]
				local code = key_from_name(key_name)
				-- A binding for a shape that is no longer installed would sink a
				-- key into a permanent failure notice, so skip it rather than
				-- bind it. The entry stays in the file in case the shape returns.
				if code and not claimed[key_name] and x2[shape_name] then
					claimed[key_name] = true
					bind("Gravity_Shape_" .. shape_name, code, function()
						if x1.k6 == shape_name then
							return
						end
						x4.switch_shape(shape_name)
					end)
				end
			end
		end
	end

	-- What already owns a key, as a label for the rejection notice. exclude_id is
	-- the row asking, so re-picking the key it already holds is not a conflict:
	-- a core action passes its id, a shape row passes "shape:<name>".
	function x8.find_conflict(key_name, exclude_id)
		if type(key_name) ~= "string" or key_name == "" then
			return nil
		end
		local kb = x1.Keybinds
		if type(kb) ~= "table" then
			return nil
		end
		for _, entry in ipairs(CORE_ACTIONS) do
			if entry.id ~= exclude_id and kb[entry.id] == key_name then
				return entry.label
			end
		end
		local shapes = kb.Shapes
		if type(shapes) == "table" then
			for shape_name, bound in pairs(shapes) do
				-- Only shapes that are actually installed, matching rebind_all. A
				-- saved binding can name a shape that has since been folded away
				-- (main.lua:322 names Deflect), and x1.Keybinds is restored wholesale,
				-- so reporting the phantom as a conflict made its key impossible to
				-- reassign -- rebind_all refuses to bind it, and the Keybinds window
				-- lists rows from pairs(x2), so the row is not there to clear either.
				if x2[shape_name] and ("shape:" .. shape_name) ~= exclude_id and bound == key_name then
					return shape_name
				end
			end
		end
		return nil
	end

	-- Touch does not drive Mouse.Target, so acquiring the core by finger needs a real
	-- raycast -- the same thing System_sculptor in this tree already does. Accepting
	-- Touch while still testing v9.Target made core dragging unreliable on the only
	-- devices that load this file.
	local function pick_at(input)
		local cam = v4.CurrentCamera
		if not cam or not input or not input.Position then
			return nil
		end
		local ray = cam:ViewportPointToRay(input.Position.X, input.Position.Y)
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { v8.Character }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, rp)
		return hit and hit.Instance
	end

	function x8.i()
		if x6.torn_down then return  end
		local kb = x1.Keybinds or {}
		x8.rebind_all()
		table.insert(
			x6.c,
			v1.InputBegan:Connect(function(i, p)
				if p or not x6.b then
					return
				end
				local touch = i.UserInputType == Enum.UserInputType.Touch
				if touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
					local target = touch and pick_at(i) or v9.Target
					if target == x6.b then
						x6.d = true
						x6.p = (v4.CurrentCamera and (x6.b.Position - v4.CurrentCamera.CFrame.Position).Magnitude) or 50
					end
				end
			end)
		)
		table.insert(
			x6.c,
			v1.InputEnded:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
					x6.d = false
				end
			end)
		)

		local sculptor_builder = load_module(SUB_DIR .. "System_sculptor.lua")
		if x6.torn_down then return end
		if sculptor_builder then
			local binder = sculptor_builder(context, x7)
			if binder then
				binder()
			end
		end

		local partctl_builder = load_module(SUB_DIR .. "System_partctl.lua")
		if x6.torn_down then return end
		if partctl_builder then
			local binder = partctl_builder(context, x7)
			if binder then
				binder()
			end
		end

		-- Announce the key that is actually bound, not a literal. The dock is the
		-- real entry point on touch, so say that when there is no key at all.
		local recenter = kb.Recenter
		if type(recenter) == "string" and recenter ~= "" then
			x7.n("Rdy", "Press '" .. recenter .. "' or tap PLC", 5)
		else
			x7.n("Rdy", "Tap PLC to place the core", 5)
		end
	end

	-- x7 goes out with the other two. It was already handed to the sculptor and Part
	-- Control binders above, and the formation controls put their pure decisions on it
	-- (advance_clock, blend_w, rule_reject, part_size, reset_scratch) precisely so they
	-- can be exercised without the loop -- which no harness can drive, because the stub
	-- Roblox environment's events drop their callbacks.
	return { x4 = x4, x8 = x8, x7 = x7 }
end
