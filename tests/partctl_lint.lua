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

-- Several checks below are "this identifier must not appear here", and the code they
-- guard is documented with comments that name the very thing being forbidden. A check
-- that cannot tell code from prose fails on its own documentation, so strip the
-- comments first. Line comments only -- this tree has no block comments.
local function code_only(src)
	if not src then
		return nil
	end
	return (src:gsub("%-%-[^\n]*", ""))
end

for _, path in ipairs({ "System.lua", "mobilever/System.lua" }) do
	local src = slurp(path)

	check(src:find("d%.pc_mode%s*==%s*nil%s+and%s+i%s*%%%s*et%s*~=%s*update_bucket") ~= nil,
		path .. ": the bucket skip exempts controlled parts")

	local cull = src:find("distance_sq%s*>%s*k1_sq[^\n]*pc_mode")
	local dead = src:find("distance_sq%s*>%s*c7_sq[^\n]*pc_mode")
	check(cull ~= nil, path .. ": the radius cull exempts controlled parts")
	check(dead ~= nil, path .. ": the deadzone exempts controlled parts")

	check(src:find('pc%s*==%s*"pin"') or src:find('pc%s*==%s*"manual"'),
		path .. ": the dispatch branches on pin/manual")
	-- What this is pinning is the *argument list* an uncontrolled part is still called
	-- with -- the part, the active centre and its own record -- because that is what
	-- Part Control must not disturb. It used to name the clock argument too, which made
	-- it fail on Time Scale renaming that local from ft to sclock: an unrelated feature
	-- breaking a Part Control check tells you nothing about Part Control.
	check(src:find("shape_f2%(p,%s*active_c,%s*d,%s*[%w_]+,%s*cur_shape_cfg") ~= nil,
		path .. ": the normal path still calls shape_f2 unchanged")

	check(src:find("x6%.pc_mods") ~= nil, path .. ": the loop walks the assigned-module registry")
	check(src:find("mod%.px") ~= nil or src:find("m%.px") ~= nil,
		path .. ": it calls px on each assigned module")

	local disabled_path = src:match("local function apply_disabled_part(.-)function x4") or ""
	check(disabled_path:find("ShapePhysics.apply_collisions(p, d, x1)", 1, true) ~= nil,
		path .. ": the disable path uses the shared preservation and ride collision policy")
	check(src:find("pc_ride") ~= nil, path .. ": pc_ride is read in the runtime")

	-- A shape switch tears down the module a part is assigned to and the x6.pre
	-- state behind it, so the assignments have to go with it. Without this the
	-- parts kept pc_mode set and stayed exempt from bucketing and the cull while
	-- driving a module whose px was no longer being called.
	check(src:find("pc_release_all") ~= nil, path .. ": the shape switch releases assignments")
	local switch = src:find("x6%.last_shape%s*~=%s*x1%.k6")
	local rel = src:find("pcall%(x6%.pc_release_all%)")
	check(switch ~= nil and rel ~= nil and rel > switch and rel - switch < 600,
		path .. ": pc_release_all is called from the shape-switch block")

	-- The per-part smoothing override has to reproduce the global path's
	-- "1 means snap" case; math.log(math.max(0.001, 0)) is finite, not infinite.
	check(src:find("pc_sm%s*>=%s*1") ~= nil,
		path .. ": a per-part smoothing of 1 snaps instead of falling into the log")

	-- Pin and manual are a placement, not an attraction. Driven at the global k10
	-- pull (20 * c1 = 3 studs/s per stud of error) a pin took about a second to
	-- settle and trailed the cursor through a drag.
	check(src:find("local PC_GRIP%s*=%s*%d") ~= nil, path .. ": declares a PC_GRIP hold rate")
	check(src:find("d%.pc_phys%.k10%s*%*%s*x9%.c1%)%s*or%s*PC_GRIP") ~= nil,
		path .. ": pin/manual hold at PC_GRIP unless a per-part Pull Strength says otherwise")
	check(src:find("local max_gain%s*=%s*1%s*/%s*%(real_dt") ~= nil,
		path .. ": the hold gain is capped at 1/real_dt so it cannot overshoot in one step")
	check(src:find('local%s+gain%s*=%s*%(d%.pc_phys and d%.pc_phys%.k10%)%s*or%s*x1%.k10') == nil,
		path .. ": the old k10-only gain is gone")

	-- Releasing a part has to take its Part Control selection with it: the
	-- SelectionBox is parented to the part and pc_selected is weak-keyed, so a part
	-- released while selected kept an orange box for as long as it lived and went on
	-- being counted by the panel. Both release paths have to go through it -- x4.f2
	-- and the sweep's own dead-part branch.
	check(src:find("local function drop_pc_selection") ~= nil,
		path .. ": the release-drops-selection hook has one owner")
	local drops = 0
	-- Call sites only: the declaration line starts with `local function`, so anchoring
	-- on the leading newline-and-indent skips it.
	for _ in src:gmatch("\n%s*drop_pc_selection%(p%)") do drops = drops + 1 end
	check(drops == 2, ("%s: both release paths call it (%d/2)"):format(path, drops))
end

for _, path in ipairs({ "System_partctl.lua", "mobilever/System_partctl.lua" }) do
	local src = slurp(path)

	check(src:find("x6%.pc_release_all%s*=%s*pc_release_all") ~= nil,
		path .. ": publishes pc_release_all")
	check(src:find("x6%.pc_count%s*=%s*pc_count") ~= nil, path .. ": publishes pc_count")
	check(src:find("x6%.pc_set_phys%s*=%s*pc_set_phys") ~= nil, path .. ": publishes pc_set_phys")
	check(src:find("x6%.pc_on_change") ~= nil, path .. ": notifies the panel on change")

	-- Deselecting is not releasing. pc_clear used to table.clear(pc_mods), which
	-- dropped every refcount without running a single cleanup and left the parts
	-- it had been driving stranded with pc_mode still set and no selection to
	-- release them through.
	local clear_body = src:match("local function pc_clear_highlights%(%)(.-)\n\tend")
	check(clear_body ~= nil, path .. ": pc_clear_highlights is still a named local")
	check(clear_body == nil or clear_body:find("pc_mods") == nil,
		path .. ": pc_clear does not touch the module registry")

	-- One owner for the refcount. Inlined in both pc_assign and pc_release, the
	-- nil-mode path decremented twice for the same part and fired cleanup while
	-- other parts were still driving the module.
	check(src:find("local function pc_unref_mod") ~= nil, path .. ": the refcount has one owner")
	local n = 0
	for _ in src:gmatch("x6%.pc_mods%[[%w_]+%]%s*=%s*x6%.pc_mods") do n = n + 1 end
	check(n == 0, ("%s: no open-coded refcount decrement left (%d)"):format(path, n))

	-- x1.PartCtlMode is a panel setting that carries two values the per-part loop
	-- cannot honour: "normal" is not a mode, and "shape" needs a resolved module a
	-- drag never attaches. Latching a drag straight to it left parts permanently
	-- exempt from the update bucket with nothing driving them.
	check(src:find('d%.pc_mode%s*=%s*x1%.PartCtlMode') == nil,
		path .. ": a drag does not latch pc_mode straight from x1.PartCtlMode")
	check(src:find("local function pc_latch_drag") ~= nil, path .. ": the drag latch is its own function")

	-- Part Control is not a shape, so it has no `x1.k6 == "Sculptor"` to gate on
	-- the way System_sculptor does. Ungated, these handlers fired on every left
	-- click for every shape: clicking any held part yanked it into manual mode and
	-- pinned it where you dropped it, and since the core ball is anchored and
	-- lives outside x6.a, every core drag fell through to the else branch and
	-- painted a selection rectangle over the screen.
	check(src:find("local function pc_armed") ~= nil, path .. ": the handlers have an arming gate")
	check(src:find("x6%.pc_active%s+or%s+x1%.PartCtlEnabled") ~= nil,
		path .. ": armed by the panel being open, or by the toggle")
	check(src:find("if%s+processed%s+or%s+not%s+pc_armed%(%)%s+then") ~= nil,
		path .. ": InputBegan returns early when unarmed")

	-- Only InputBegan is gated: the other two are no-ops without pc_dragging or
	-- pc_box_start, which only a gated InputBegan can set. Gating them too would
	-- strand an in-flight drag if the panel closed halfway through it.
	local changed = src:match("v1%.InputChanged:Connect%(function%(input, processed%)(.-)\n\t\t\t end")
		or src:match("v1%.InputChanged:Connect%(function%(input, processed%)(.-)end%)\n\t\t%)")
	-- Asserted findable as well as ungated: a pattern that stops matching would make
	-- every check below it pass vacuously.
	check(changed ~= nil, path .. ": the InputChanged body is still findable")
	check(changed == nil or code_only(changed):find("pc_armed") == nil,
		path .. ": InputChanged is not gated, so a live drag still tracks")
	local ended = src:match("v1%.InputEnded:Connect%(function%(input%)(.-)end%)\n\t\t%)")
	check(ended ~= nil, path .. ": the InputEnded body is still findable")
	check(ended == nil or code_only(ended):find("pc_armed") == nil,
		path .. ": InputEnded is not gated, so a live drag always finishes")

	-- Selection is inert. InputBegan used to write `d.pc_mode = d.pc_mode or "manual"`
	-- and set pc_dragging with no movement threshold, and InputEnded ran the latch
	-- unconditionally -- so a plain click pinned the part, with the panel's own mode
	-- row reading "Normal (No Override)". The press is now recorded and nothing on the
	-- part's record is touched until the pointer has actually moved.
	local began = code_only(src:match("v1%.InputBegan:Connect%(function%(input, processed%)(.-)end%)\n\t\t%)"))
	check(began ~= nil, path .. ": the InputBegan body is still findable")
	check(began == nil or began:find("pc_mode") == nil,
		path .. ": InputBegan writes no pc_mode -- selecting a part overrides nothing")
	check(began == nil or began:find("pc_dragging") == nil,
		path .. ": InputBegan does not start a drag either")
	check(src:find("local DRAG_PX%s*=%s*%d") ~= nil, path .. ": declares a drag threshold")
	check(src:find("x6%.pc_press%s*=%s*{%s*part%s*=") ~= nil, path .. ": records a pending press")
	check(src:find("DRAG_PX%s*%*%s*DRAG_PX") ~= nil, path .. ": and compares against it squared")
	check(src:find("local function begin_drag") ~= nil, path .. ": the drag start has one owner")
	check(src:find('d%.pc_mode%s*=%s*"manual"') ~= nil,
		path .. ": begin_drag forces manual, so a shape-assigned part follows the pointer")
	check(src:find("x6%.pc_press%s*=%s*nil") ~= nil, path .. ": and the press is cleared on release")

	-- Picking. Mouse.Target returns whatever is nearest the cursor whether it is held
	-- or not, so a held part behind anything else could not be clicked and the click
	-- landed in the box-select branch -- which clears the selection.
	check(src:find("local function pc_pick") ~= nil, path .. ": picking has one owner")
	check(src:find("Enum%.RaycastFilterType%.Include") ~= nil, path .. ": and it is an Include raycast")
	check(src:find("v9%.Target") == nil, path .. ": Mouse.Target is no longer used to pick")
	check(src:find("cand%[i%]%s*=%s*arr%[i%]") ~= nil,
		path .. ": the candidate list comes from active_array, not the weak hash")

	-- Depth. A drag could only slide a part along a sphere at the distance latched
	-- when the press began.
	check(src:find("local function pc_drag_point") ~= nil, path .. ": the drag projection has one owner")
	check(src:find("x1%.PartCtlSurfaceSnap") ~= nil, path .. ": and it honours Surface Snap")
	check(src:find("local function pc_snap_grid") ~= nil, path .. ": grid snapping has one owner")
	check(src:find("x1%.PartCtlGridSnap") ~= nil, path .. ": and it reads the setting")

	-- The refcount increment has to be guarded the same way the unref above it is, or
	-- re-assigning the same shape counts the part twice and mod.cleanup never runs.
	check(src:find("if d%.pc_mod%s*~=%s*mod then") ~= nil,
		path .. ": the shape refcount only counts a part once")

	-- Riding is a property of the part, not of the mode.
	check(src:find("x6%.pc_set_ride%s*=%s*pc_set_ride") ~= nil, path .. ": publishes pc_set_ride")
	-- Bulk selection, and the only bulk selection the mobile tree has at all.
	check(src:find("x6%.pc_select_all%s*=%s*pc_select_all") ~= nil, path .. ": publishes pc_select_all")
	check(src:find("x6%.pc_select_overridden%s*=%s*pc_select_overridden") ~= nil,
		path .. ": publishes pc_select_overridden")
	check(src:find("x6%.pc_invert%s*=%s*pc_invert") ~= nil, path .. ": publishes pc_invert")
	-- Every selected part carries a SelectionBox, so a bulk select over a large claim
	-- would build thousands of adornments in one frame. All four selection paths share
	-- one ceiling.
	check(src:find("local MAX_SELECT%s*=%s*%d") ~= nil, path .. ": declares a selection ceiling")
	-- Three helpers in both trees, plus box-select in the desktop tree only: the mobile
	-- tree has no marquee at all, which is why Select All Held is its only bulk gesture.
	-- Detected on code, not prose -- the mobile file's own comments discuss pc_box_start.
	local want_caps = code_only(src):find("x6%.pc_box_start") and 4 or 3
	local caps = 0
	for _ in src:gmatch("n%s*>=%s*MAX_SELECT") do caps = caps + 1 end
	check(caps == want_caps,
		("%s: every selection path honours it (%d/%d)"):format(path, caps, want_caps))

	-- The highlight is the only thing that can say what a part is doing; two counters
	-- in a panel cannot.
	check(src:find("local MODE_COLOR") ~= nil, path .. ": highlights carry a per-mode colour")
	check(src:find("local function pc_paint_highlight") ~= nil, path .. ": repainting has one owner")

	-- pc_count is the sweeper for a selection whose parts have been released.
	local count_body = src:match("local function pc_count%(%)(.-)\n\tend")
	check(count_body ~= nil, path .. ": pc_count is still a named local")
	check(count_body == nil or count_body:find("pc_remove_highlight") ~= nil,
		path .. ": pc_count prunes a selection entry whose part has been released")
end

do
	local cfg = assert(loadfile("config.lua"))
	local stub = function() return setmetatable({}, { __index = function() return 0 end }) end
	Vector3 = { new = stub, zero = stub() }
	Color3 = { new = stub, fromRGB = stub }
	local x1 = cfg().x1
	check(x1.PartCtlEnabled == false, "config.lua: Part Control is not armed by default")
	check(type(x1.PartCtlEnabled) == "boolean", "PartCtlEnabled is a boolean")
	-- Both new keys have to be here with their final type, or load_settings can never
	-- restore them and reset_config never snapshots them -- the failure config.lua:31-35
	-- records shipping once already.
	check(type(x1.PartCtlSurfaceSnap) == "boolean",
		("PartCtlSurfaceSnap is a boolean, not a %s"):format(type(x1.PartCtlSurfaceSnap)))
	check(x1.PartCtlSurfaceSnap == true, "Surface Snap is on by default")
	check(type(x1.PartCtlGridSnap) == "number",
		("PartCtlGridSnap is a number, not a %s"):format(type(x1.PartCtlGridSnap)))
	check(x1.PartCtlGridSnap == 0, "Grid Snap is off by default")
end

for _, path in ipairs({ "UI.lua", "mobilever/UI.lua" }) do
	local src = slurp(path)
	check(src:find("pc_assign") ~= nil, path .. ": the panel calls pc_assign")
	check(src:find("pc_clear") ~= nil, path .. ": the panel can clear the selection")
	check(src:find("Part Control") ~= nil, path .. ": the panel is labelled")
	check(src:find("pc_count") ~= nil, path .. ": the panel reads the live selection count")
	check(src:find("pc_release_all") ~= nil, path .. ": the panel can release every override")
	check(src:find("x6%.pc_on_change%s*=") ~= nil, path .. ": the panel registers for change events")
	check(src:find("pc_set_phys") ~= nil, path .. ": the panel can set the physics override")

	-- The count was read once, at build time, inside a function that rebuilt the
	-- whole panel; nothing called it again until the window was reopened.
	check(src:find("pcc:ClearAllChildren") == nil,
		path .. ": the panel body is refreshed in place, not rebuilt")

	-- Opening and closing the panel is what arms and disarms the click handlers,
	-- so every path that changes the panel's visibility has to say so.
	check(src:find("x6%.pc_active%s*=") ~= nil, path .. ": the panel arms the handlers")
	check(src:find("PartCtlEnabled%s*=%s*v") ~= nil, path .. ": the stay-armed toggle is wired")
	local sets = 0
	for _ in src:gmatch("x6%.pc_active%s*=") do sets = sets + 1 end
	-- Construction (reset), the close button, and the panel button.
	check(sets == 3, ("%s: every visibility path sets pc_active (%d/3)"):format(path, sets))

	-- The bulk selection helpers have to be reachable, or they exist and no user can
	-- get at them -- and on the mobile tree they are the only bulk selection there is.
	check(src:find("pc_select_all") ~= nil, path .. ": the panel can select every held part")
	check(src:find("pc_select_overridden") ~= nil, path .. ": the panel can select the overridden ones")
	check(src:find("pc_invert") ~= nil, path .. ": the panel can invert the selection")

	-- Rideable through pc_set_ride, not pc_assign: routing it through the mode meant it
	-- did nothing at all on "normal", and re-assigned the mode -- shape module refcount
	-- and all -- on the other three.
	check(src:find("pc_set_ride") ~= nil, path .. ": the Rideable toggle goes through pc_set_ride")
	check(src:find("pc_assign%(x1%.PartCtlMode") == nil,
		path .. ": and no longer re-assigns the panel mode as a side effect")

	-- Both drag settings need a control, or the defaults are the only values anyone
	-- ever gets.
	check(src:find("x1%.PartCtlSurfaceSnap%s*=%s*v") ~= nil, path .. ": Surface Snap has a toggle")
	check(src:find("x1%.PartCtlGridSnap%s*=%s*v") ~= nil, path .. ": Grid Snap has a slider")

	-- "Overridden: 7" does not say what those seven are doing.
	check(src:find("Pin %%d") ~= nil, path .. ": the panel breaks the override count down by mode")
end

print(("\n%d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
