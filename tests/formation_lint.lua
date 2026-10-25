-- The six formation controls have to be wired identically in both runtime trees and
-- exposed identically in both panels. mobilever/ is a near-verbatim second copy of
-- System.lua and UI.lua, so the natural failure mode for a change this wide is landing
-- in one tree and not the other -- a desktop-only or mobile-only bug that no behavioural
-- test can see, because each tree is only ever loaded on one kind of device.
--
-- tests/formation_smoke.lua covers what these features *decide*, by calling the published
-- functions directly. This covers what calls them, which is the half no harness can reach:
-- newEvent() in tests/robloxenv.lua drops its callbacks, so Heartbeat never fires and
-- f3_body is unreachable. Same split, and the same honesty about it, as
-- tests/fidelity_lint.lua.
--
--   luajit tests/formation_lint.lua      (from the repo root)

local fails, checks = 0, 0
local function check(cond, msg)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("  FAIL  " .. msg)
	end
end
local function slurp(path)
	local f = assert(io.open(path), "cannot open " .. path)
	local s = f:read("a")
	f:close()
	return s
end
local function listdir(dir)
	local out = {}
	local pf = assert(io.popen("ls '" .. dir .. "'"))
	for line in pf:lines() do
		if line:match("%.lua$") then
			out[#out + 1] = dir .. "/" .. line
		end
	end
	pf:close()
	return out
end

-- ── config defaults ─────────────────────────────────────────────────────────────────
-- load_settings only restores a saved value when a default of the matching type is
-- already in x1, and reset_config only snapshots what that table holds, so a key the UI
-- writes and config.lua omits both forgets itself between sessions and survives "Reset
-- All Settings". config.lua:31-47 is that bug's own comment.
do
	local cfg = assert(loadfile("config.lua"))
	local stub = function()
		return setmetatable({}, { __index = function() return 0 end })
	end
	Vector3 = { new = stub, zero = stub() }
	Color3 = { new = stub, fromRGB = stub }
	local x1 = cfg().x1

	-- Every one of these has to be inert at its default: that is what makes six
	-- features landing in one pass safe, and tests/formation_smoke.lua proves the
	-- runtime actually treats them that way.
	local expected = {
		{ "TimeScale", "number", 1 },
		{ "BlendEnabled", "boolean", false },
		{ "BlendShape", "string", nil },
		{ "BlendWeight", "number", 0 },
		{ "BlendStagger", "number", 0 },
		{ "PreviewEnabled", "boolean", false },
		{ "PreviewCount", "number", nil },
		{ "PreviewDeviation", "boolean", false },
		{ "SlotMode", "string", "Claim" },
		{ "SlotSeed", "number", 0 },
		{ "TargetParts", "number", 0 },
		{ "SurplusRule", "string", "Farthest" },
		{ "RuleMinSize", "number", 0 },
		{ "RuleMaxSize", "number", 0 },
		{ "RuleClaimRadius", "number", 0 },
		{ "RuleName", "string", "" },
	}
	for _, row in ipairs(expected) do
		local key, want_type, want_value = row[1], row[2], row[3]
		check(x1[key] ~= nil, "config.lua x1 declares " .. key)
		check(type(x1[key]) == want_type,
			("%s is a %s, not a %s"):format(key, want_type, type(x1[key])))
		if want_value ~= nil then
			check(x1[key] == want_value,
				("%s defaults to %s (found %s)"):format(key, tostring(want_value), tostring(x1[key])))
		end
	end
	-- The blend shape has to name a shape that exists, or the feature is inert in a way
	-- that looks like a bug rather than a default.
	local x2 = cfg().x2
	check(x2[x1.BlendShape] ~= nil, "the default BlendShape is a registered shape")
	check(x1.PreviewCount >= 4 and x1.PreviewCount <= 200,
		"PreviewCount's default is inside the range the runtime clamps to")
end

-- ── both runtime trees ──────────────────────────────────────────────────────────────
for _, path in ipairs({ "System.lua", "mobilever/System.lua" }) do
	local src = slurp(path)
	local function has(pat, msg)
		check(src:find(pat) ~= nil, path .. ": " .. msg)
	end
	local function hasnt(pat, msg)
		check(src:find(pat) == nil, path .. ": " .. msg)
	end

	-- Time Scale. The shapes' clock and the loop's clock are different clocks, and the
	-- whole feature is which one reaches which call.
	has("local function advance_clock%(real_dt%)", "declares advance_clock")
	has("x7%.advance_clock = advance_clock", "publishes it on x7 so it can be tested")
	has("local sclock = advance_clock%(real_dt%)", "f3_body advances the shape clock once per frame")
	has("advance_motion%(real_dt%)", "real-time motion advances independently of the pattern clock")
	has("x6%.motion_offset = Vector3%.new", "publishes the shared bounded orbit for shapes and previews")
	has("x6%.shape_clock", "the clock is carried on x6, so it survives across frames")
	has("scale > 8", "an out-of-range scale is clamped up")
	has("scale < %-8", "and down, since a hand-edited settings file is not the slider")
	has("scale ~= scale", "and NaN is caught, because it fails its own equality test")
	-- The four shape-facing sites, all of which have to be on the scaled clock.
	has("pcall%(cur_shape_mod%.px, sclock", "the primary shape's pre-pass runs on the shape clock")
	has("pcall%(mod%.px, sclock", "so does each assigned module's")
	has("pcall%(bmod%.px, sclock", "and the blend shape's")
	has("ShapePhysics%.evaluate%(d%.pc_mod%.f2, p, active_c, d, sclock", "a Part Control shape runs on the shape clock")
	has("ShapePhysics%.evaluate%(shape_f2, p, active_c, d, sclock", "and so does the formation")
	-- The wall-clock sites, all of which have to be left alone. A Time Scale of 0 that
	-- also froze these would stop the target list rebuilding and the shape-switch ease
	-- finishing, which is not what the control says it does.
	has("local et, ft = x1%.k7 or dt, time%(%)", "ft is still wall time")
	has("d%.sys_last_t = ft", "the target-velocity term still measures a real interval")
	has("ft > x6%.pi_timer", "the target-list rebuild is still on a real clock")
	has("local age = ft %- d%.claim_t", "and so is Realistic Liftoff's part age")

	-- Shape Blend.
	has("x1%.BlendEnabled", "reads the blend toggle")
	has("bn ~= shape_name", "refuses to blend a shape with itself")
	has("bd = { id = d%.id, integral = ZERO_VECTOR }", "gives the blend shape its own scratch record")
	has("ShapePhysics%.evaluate%(blend_f2, p, active_c, bd, sclock", "and calls it with that record, not with d")
	hasnt("ShapePhysics%.evaluate%(blend_f2, p, active_c, d,", "never hands the blend shape the primary's record")
	has("x6%.bl_f2, x6%.bl_cfg, x6%.bl_w, x6%.bl_s", "publishes the resolved blend for the preview")
	has("if blend_ok and bd%.unclaim then", "a blend shape can still release a part")
	has("x6%.last_blend", "tracks the blend shape so it can be handed its instances back")
	has("prev_blend ~= shape_name", "but never tears down the shape that is now primary")
	has("elseif bw >= 1 then", "a pure target survives only at full weight or from both shapes")
	-- Every blend invocation is guarded: a later part can fail after the first
	-- succeeds. physics_robustness.lua exercises that case through Heartbeat.
	hasnt("local blend_checked", "there is no unguarded blend fast path")
	has("ShapePhysics%.evaluate%(blend_f2, p, active_c, bd, sclock", "every blend call is guarded")
	has("x6%.bl_failed", "and a blend shape that fails is remembered rather than retried")
	has("physics_error%(blend_name", "and the failure is announced")

	-- Formation Preview.
	has("GRV_GHOST = true", "the ghost name is in EXCLUDED_NAMES")
	has("part%.Anchored = true", "a ghost is anchored, which is what keeps x7.e off it")
	has("folder%.Parent = x6%.b%.Parent or v4", "the pool lives under the core's own folder")
	has("x6%.preview_clear = x4%.preview_clear", "the clear is reachable from the loader's teardown")
	has("if x1%.PreviewEnabled then\n%s*x4%.preview_step", "f3_body steps the preview")
	has("x4%.preview_clear%(%)\n%s*end", "and clears it when the toggle goes off")
	has("nx ~= nx or ny ~= ny or nz ~= nz", "a NaN never reaches a marker's Position")
	has('typeof%(pure%) == "Vector3"', "and neither does a shape that hands back the wrong type")
	has("GHOST_LIMIT", "and a runaway marker is held to a radius")

	-- Slot Assignment.
	has("function x4%.reindex_slots%(%)", "declares reindex_slots")
	has("d%.slot, d%.slot_n = i, m", "which writes a dense slot and the live population")
	has("d%.slot, d%.slot_n = nil, nil", "and Claim mode clears them rather than numbering")
	has("if not SLOT_MODES%[mode%] then", "an unrecognised mode falls back rather than guessing")
	has("local function shuffle_key%(id, seed%)", "the shuffle is a hash of the id and the seed")
	has("slot_ids%[a%] or 0%) < %(slot_ids%[b%] or 0%)", "every sort breaks ties on the claim id")
	has("x6%.slot_dirty = true\n%s*return true", "f1 marks the population dirty")
	has("x6%.n = math%.max%(0, x6%.n %- 1%)\n%s*x6%.slot_dirty = true", "and so does f2")
	-- The stride widens with the part-count ladder, exactly as no3_interval does: the sort
	-- is O(n log n) with a property read per part, so a fixed quarter second is right at a
	-- few hundred parts and wrong at five thousand. Max Fidelity gives it up with the rest.
	has("ft %- %(x6%.slot_t or %-1%) > 0%.25 %* %(dt > 4 and 4 or dt%)",
		"the reindex stride scales with the part-count ladder")
	has("if x6%.slot_dirty and %(max_fid or", "and Max Fidelity gives the stride up")
	has("x4%.enforce_part_cap%(%)\n%s*x4%.reindex_slots%(%)",
		"the ceiling runs before the reindex, so the slots describe what is left")
	has("function x4%.reroll_seeds%(%)", "declares reroll_seeds")

	-- Both sort scratch arrays hold parts strongly and both functions return early in the
	-- common case, so the clear has to sit above the early return or the last population
	-- stays pinned against the weak table built to let it go.
	local reindex = src:match("function x4%.reindex_slots%(%)(.-)\n\tend")
	check(reindex ~= nil, path .. ": reindex_slots is findable")
	reindex = reindex or ""
	local clear_at, return_at = reindex:find("table%.clear%(slot_parts%)"), reindex:find("return 0")
	check(clear_at ~= nil and return_at ~= nil and clear_at < return_at,
		path .. ": reindex_slots drops its scratch before its early return")
	local cap_fn = src:match("function x4%.enforce_part_cap%(%)(.-)\n\tend")
	check(cap_fn ~= nil, path .. ": enforce_part_cap is findable")
	cap_fn = cap_fn or ""
	local cap_clear, cap_return = cap_fn:find("table%.clear%(cap_parts%)"), cap_fn:find("return 0")
	check(cap_clear ~= nil and cap_return ~= nil and cap_clear < cap_return,
		path .. ": and so does enforce_part_cap")

	-- The scratch list has exactly one owner. It had already drifted between the trees
	-- once -- the desktop cleared d.f/d.u/d.v/d.rot_axis/d.red_direction and the mobile
	-- tree did not -- and two callers now need the identical list.
	has("local function reset_scratch%(d%)", "declares reset_scratch")
	has("x7%.reset_scratch = reset_scratch", "and publishes it")
	has("for _, d in pairs%(x6%.a%) do\n%s*reset_scratch%(d%)", "the shape switch goes through it")
	hasnt("\n%s*d%.hover_anchor = nil\n%s*d%.cursed_hover_mode = nil\n",
		"no open-coded copy of the scratch list is left behind")
	has("d%.bd = nil", "and the list includes the blend's own record")

	-- Target Part Count. The ceiling withholds the claim; it must not break the walk.
	has("local cap = x1%.TargetParts or 0", "ProcessQueue reads the ceiling")
	has("instance:IsA%(\"BasePart\"%) and %(cap <= 0 or x6%.n < cap%)", "and withholds the claim at it")
	has("for _, child in ipairs%(instance:GetChildren%(%)%) do\n%s*n = n %+ 1",
		"while the descendant walk stays unconditional, or whole branches are lost")
	has("function x4%.enforce_part_cap%(%)", "declares enforce_part_cap")
	has("d%.pc_mode == nil then", "a hand-placed part is never surplus")
	has("x4%.f2%(p, true, k%)", "and the surplus is released with its velocity zeroed")

	-- Claim Rules.
	has("local function rule_reject%(p, with_radius%)", "declares rule_reject")
	has("x7%.rule_reject = rule_reject", "and publishes it")
	has("if rule_reject%(p, true%) then", "x7.e applies the rules, radius included")
	has("rule_reject%(p, false%) then", "and the recheck applies them without the radius")
	has("function x4%.recheck_rules%(%)", "declares recheck_rules")
	has("string%.find%(name, pat, 1, true%)",
		"the name filter is a plain find, so a name with pattern characters cannot throw")
	has("string%.find%(name, ex, 1, true%)", "and so is an exclusion")
	has("local function part_size%(p%)", "one owner for what a part's size means")
	has("x7%.part_size = part_size", "published, so the test can pin it")

	-- x7 goes out with x4 and x8, or none of the above can be tested at all.
	has("return { x4 = x4, x8 = x8, x7 = x7 }", "publishes x7 alongside x4 and x8")

	-- Teardown. Both of these own instances and neither has an owner that runs while the
	-- loop is stopped.
	local disabled_block = src:match("function x4%.apply_disabled%(disabled%)(.-)\n\t\tif x6%.b then")
	check(disabled_block ~= nil, path .. ": apply_disabled's head is findable")
	disabled_block = disabled_block or ""
	check(disabled_block:find("x4%.preview_clear%(%)") ~= nil,
		path .. ": disabling clears the preview")
	check(disabled_block:find("cleanup_shape%(x6%.last_blend%)") ~= nil,
		path .. ": and hands the blend shape its instances back")
	-- Preview and blend cleanup precede destruction of the explicitly owned core.
	local f5_block = src:match("function x4%.f5%(%)(.-)\n\t\tlocal core, holder =")
	check(f5_block ~= nil, path .. ": f5's head is findable")
	f5_block = f5_block or ""
	check(f5_block:find("x4%.preview_clear%(%)") ~= nil, path .. ": stopping clears the preview")
	check(f5_block:find("cleanup_shape%(x6%.last_blend%)") ~= nil,
		path .. ": and hands the blend shape its instances back")
end

-- ── both panels ─────────────────────────────────────────────────────────────────────
for _, path in ipairs({ "UI.lua", "mobilever/UI.lua" }) do
	local src = slurp(path)
	local function has(pat, msg)
		check(src:find(pat) ~= nil, path .. ": " .. msg)
	end

	-- The two new sections. panels_lint.lua asserts the existing six the same way, and
	-- for the same reason: a header in one tree only is how the panels drift.
	has('eh%(ac, "Formation"%)', "Advanced groups the formation controls under a header")
	has('eh%(ac, "Preview"%)', "and the preview controls under one")

	-- Every control writes its key. A label with no write is a control that does nothing,
	-- which is exactly what a copy-paste between two trees produces.
	for _, key in ipairs({
		"TimeScale", "SlotMode", "BlendEnabled", "BlendShape", "BlendWeight", "BlendStagger",
		"PreviewEnabled", "PreviewCount", "PreviewDeviation", "TargetParts", "SurplusRule",
		"RuleMinSize", "RuleMaxSize", "RuleClaimRadius", "RuleName",
	}) do
		-- An assignment, not a comparison: the trailing [^=] is what keeps `x1.SlotMode ==`
		-- from satisfying a check that the control *writes* the key.
		has("x1%." .. key .. "%s*=%s*[^=]", "a control writes x1." .. key)
	end
	has("x1%.k5 = list", "and the ignore-tag list is editable at last")

	-- Ranges, in both trees, because both write the same key into the same settings file:
	-- a slider that stops at a different number in one tree silently clamps the other
	-- tree's saved value on the next open. panels_lint.lua pins the FPS cap for this
	-- reason already.
	has('"Time Scale", %-3, 3', "Time Scale has the same range in both trees")
	has('"Blend Weight", 0, 100', "and Blend Weight")
	has('"Blend Stagger", 0, 100', "and Blend Stagger")
	has('"Ghost Count", 4, 200', "and Ghost Count")
	has('"Target Parts", 0, 5000', "and Target Parts")
	has('"Min Part Size", 0, 200', "and Min Part Size")
	has('"Max Part Size", 0, 500', "and Max Part Size")
	has('"Claim Radius", 0, 2000', "and Claim Radius")

	-- The three helpers the new controls need, none of which existed before.
	has("local function cycle_btn%(parent, label, values, get, set, desc%)",
		"enums are cycling buttons rather than integer sliders")
	has("local function resolve_shape_name%(typed%)", "the blend shape is resolved from what was typed")
	has('adv_notify%("Blend"', "and an unmatched name says so rather than going quiet")
	has("local function rules_changed%(%)", "a rule change is routed through one place")
	has("x4%.recheck_rules%(%)", "which rechecks the parts already held")
	has("x4%.preview_clear%(%)", "and the preview toggle collects its own markers")
	has("x4%.reroll_seeds%(%)", "the re-roll button reaches the runtime")

	-- The HUD. The PARTS fragment is what panels_lint.lua reads, and the deviation field
	-- has to fold into the same change detect or the label is rewritten every frame.
	has("PARTS: %%d", "the HUD still carries the part count")
	has("DEV: %%%.1f / %%%.1f", "and gains the deviation readout")
	has("dev ~= hud_dev", "which is part of the change detect rather than an extra write")
end

-- ── the loader's teardown ───────────────────────────────────────────────────────────
-- The ghost pool lives inside the core's AS folder, which destroy() takes out anyway --
-- but that makes their removal incidental to something else, and this is the path that
-- runs on re-execution, where anything left in the world stays there.
do
	local src = slurp("main.lua")
	check(src:find("pcall%(x6%.preview_clear%)") ~= nil,
		"main.lua's destroy() collects the preview's markers")
end

-- ── the shapes' index ───────────────────────────────────────────────────────────────
-- Slot Assignment is only real if the shapes read it. Every line in shapes/ that reads
-- d.id has to prefer d.slot, and while d.slot is nil -- which is the default -- the
-- expression is exactly what it was before. Checked line by line rather than by count,
-- so a failure names the file that was missed.
do
	local found = 0
	for _, path in ipairs(listdir("shapes")) do
		for line in slurp(path):gmatch("[^\n]+") do
			-- Code, not prose: several of these lines have a comment above them that
			-- names d.id too, and a check that cannot tell the two apart fails on its own
			-- documentation.
			local code = line:match("^%s*%-%-") and "" or line
			if code:find("d.id", 1, true) then
				found = found + 1
				check(code:find("d.slot", 1, true) ~= nil,
					("%s: the line indexing by d.id prefers d.slot"):format(path))
			end
		end
	end
	check(found >= 15, ("every shape that indexes by d.id is covered (%d found)"):format(found))
end

print(("\n%d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)



