-- Max Fidelity has to be honoured in BOTH runtime trees. mobilever/System.lua is a
-- near-verbatim second copy of System.lua, so the natural failure is a change that
-- lands in one and not the other. This checks the wiring at every site in both
-- trees; physics_controls.lua also exercises the actual constraint loop.
--
-- The switch is specified as "give up every accuracy-for-speed shortcut", so the
-- list below is the list of shortcuts. It replaces an earlier check that counted
-- `max_fid` occurrences and asserted exactly four: a count is satisfied by a
-- comment, cannot say *which* site is missing, and can only ever be right for one
-- revision.
--
--   luajit tests/fidelity_lint.lua      (from the repo root)

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

-- The default has to be a boolean and it has to be in the x1 block, or load_settings
-- can never restore it and reset_config never snapshots it. config.lua:31-35 records
-- that failure shipping once already.
do
	local cfg = assert(loadfile("config.lua"))
	local stub = function() return setmetatable({}, { __index = function() return 0 end }) end
	Vector3 = { new = stub, zero = stub() }
	Color3 = { new = stub, fromRGB = stub }
	local x1 = cfg().x1
	check(x1.MaxFidelity ~= nil, "config.lua x1 declares MaxFidelity")
	check(type(x1.MaxFidelity) == "boolean",
		("MaxFidelity is a boolean, not a %s"):format(type(x1.MaxFidelity)))
	check(x1.MaxFidelity == false, "MaxFidelity defaults to off")
end

for _, path in ipairs({ "System.lua", "mobilever/System.lua" }) do
	local src = slurp(path)

	-- Fidelity controls update frequency and caching; damping remains an
	-- independent setting in every quality mode.
	check(src:find("local max_fid%s*=%s*x1%.MaxFidelity") ~= nil,
		path .. ": declares `local max_fid = x1.MaxFidelity`")
	check(src:find('local%s+force_smooth%s*=%s*x1%["Force Smooth %(Lags%)"%]%s+or%s+max_fid') ~= nil,
		path .. ": force_smooth folds in max_fid at the declaration")
	check(src:find("if%s+force_smooth%s+or%s+max_fid%s+then") == nil,
		path .. ": no leftover `force_smooth or max_fid` branch beside the declaration")

	-- Shortcuts 1 and 2: the part-count ladder and the k7 bucket, both collapsed by
	-- pinning dt and et to 1.
	check(src:find("if%s+force_smooth%s+then%s*\n%s*dt%s*=%s*1%s*\n%s*et%s*=%s*1") ~= nil,
		path .. ": force_smooth pins both dt and et to 1")
	-- Shortcuts 3 and 4: the radius cull and the deadzone, both via always_process.
	check(src:find("local%s+always_process%s*=[^\n]*max_fid") ~= nil,
		path .. ": always_process includes max_fid")
	check(src:find("local%s+always_process%s*=[^\n]*is_drop_shape") ~= nil,
		path .. ": always_process still honours is_drop_shape")
	check(src:find("local%s+always_process%s*=[^\n]*is_self_bounded_shape") ~= nil,
		path .. ": always_process still honours is_self_bounded_shape")
	-- Shortcut 5: velocity smoothing.
	check(src:find("if%s+force_smooth%s+then%s*\n%s*sm_alpha%s*=%s*1") ~= nil,
		path .. ": force_smooth pins sm_alpha to 1")
	-- Damping is a physics setting, not an accuracy shortcut.
	check(src:find("local%s+default_damping%s*=[^\n]*not%s+cur_no_damp") ~= nil
		and src:find("local%s+default_damping%s*=[^\n]*force_smooth") == nil,
		path .. ": damping remains active with Force Smooth and Max Fidelity")

	-- Shortcut 8: the NetworkOwnerV3 re-read stride. This one gates whether a part
	-- is driven at all, so a cached value meant a part whose ownership had just come
	-- to us stayed skipped for up to 0.15s -- the longest-lived stale read in the
	-- loop.
	check(src:find("local%s+no3_interval%s*=%s*max_fid%s+and%s+0%s+or") ~= nil,
		path .. ": the NetworkOwnerV3 stride collapses to 0 under max_fid")
	-- Shortcut 9: the 1 Hz target/marker rebuild.
	check(src:find("if%s+max_fid%s+or%s+ft%s*>%s*x6%.pi_timer%s+then") ~= nil,
		path .. ": the target-list rebuild runs every frame under max_fid")
	-- Shortcut 10: the 1 Hz water-level probe.
	check(src:find("if%s+max_fid%s+or%s+x6%.f%s*%%%s*60%s*==%s*0") ~= nil,
		path .. ": the water-level probe runs every frame under max_fid")
	-- Shortcut 11: the 1 Hz character-set rebuild. Outside f3_body, so it reads the
	-- field rather than the local -- and it rebuilds per frame rather than per call,
	-- because x7.e runs it once per candidate part and the claim budget lets thousands
	-- through in a frame.
	check(src:find("x1%.MaxFidelity%s+and%s+x6%.f%s*~=%s*char_set_f") ~= nil,
		path .. ": the character set is rebuilt once per frame under Max Fidelity")
	check(src:find("or%s+now%s*%-%s*char_set_t%s*>%s*1%s+then") ~= nil,
		path .. ": with the 1 Hz floor kept, since x6.f stalls while paused")
	-- Shortcut 12: the claim-queue budget, all three ceilings.
	check(src:find("cap_processed%s*=%s*max_fid%s+and") ~= nil,
		path .. ": the claim budget's item ceiling is widened")
	check(src:find("cap_claimed%s*=%s*max_fid%s+and") ~= nil,
		path .. ": the claim budget's claim ceiling is widened")
	check(src:find("cap_seconds%s*=%s*max_fid%s+and") ~= nil,
		path .. ": the claim budget's time ceiling is widened")
	check(src:find("processed%s*>=%s*cap_processed%s+or%s+claimed%s*>=%s*cap_claimed") ~= nil,
		path .. ": and the break test reads the ceilings rather than literals")
	-- Shortcut 13: the paused anti-sleep nudge, 20 Hz.
	check(src:find("if%s+not%s+x1%.MaxFidelity%s+and%s+x6%.pause_tick%s*%%%s*3%s*~=%s*0%s+then") ~= nil,
		path .. ": the paused anti-sleep nudge runs every frame under Max Fidelity")
	-- Shortcut 14: the anti-fling collision sweep, 20 Hz.
	check(src:find("if%s+not%s+x1%.MaxFidelity%s+and%s+af_tick%s*%%%s*3%s*~=%s*0%s+then") ~= nil,
		path .. ": the anti-fling sweep runs every frame under Max Fidelity")

	-- Bypass the tests, never the settings, so turning the switch off restores the
	-- previous behaviour exactly. In particular Max Fidelity must not be implemented
	-- by writing the narrower flag: that would be saved, and turning Max Fidelity
	-- off would leave Force Smooth on.
	check(src:find("k1_sq%s*=%s*k1%s*%*%s*k1") ~= nil, path .. ": k1 still drives the cull radius")
	check(src:find("c7_sq%s*=%s*c7%s*%*%s*c7") ~= nil, path .. ": c7 still drives the deadzone")
	check(src:find("et,%s*ft%s*=%s*x1%.k7") ~= nil, path .. ": k7 still seeds the update bucket")
	check(src:find('x1%["Force Smooth %(Lags%)"%]%s*=') == nil,
		path .. ": the runtime never writes the Force Smooth setting")
end

-- Shortcut 7, and the one users actually see. Nine shipped shapes recompute their
-- whole layout once every `et` frames, where `et` is their own copy of the
-- part-count ladder -- and each one pinned it on Force Smooth alone. So with Max
-- Fidelity on and Force Smooth off, the loop ran every part every frame while the
-- shape underneath handed back the same target for ten frames running: exactly the
-- stepping the switch exists to remove, still there, on the heaviest shapes.
do
	local found = 0
	for _, dir in ipairs({ "shapes", "shapes-onreview" }) do
		for _, path in ipairs(listdir(dir)) do
			for line in slurp(path):gmatch("[^\n]+") do
				-- The index expression, not the words: the comment above each of these
				-- sites names Force Smooth too, and a check that cannot tell code from
				-- prose fails on its own documentation.
				if line:find('x1["Force Smooth (Lags)"]', 1, true) then
					found = found + 1
					check(line:find("MaxFidelity", 1, true) ~= nil,
						("%s: the line pinning on Force Smooth also honours MaxFidelity"):format(path))
				end
			end
		end
	end
	check(found >= 12, ("every shape with its own stride is covered (%d found)"):format(found))
end

for _, path in ipairs({ "UI.lua", "mobilever/UI.lua" }) do
	local src = slurp(path)
	check(src:find("x1%.MaxFidelity%s*=%s*v") ~= nil, path .. ": a toggle writes x1.MaxFidelity")
	check(src:find("Max Fidelity") ~= nil, path .. ": the toggle is labelled")
	local fs = src:find("Force Smooth %(Lags%)") or src:find("Force Smooth")
	local mf = src:find("Max Fidelity")
	check(fs ~= nil and mf ~= nil and math.abs(mf - fs) < 900,
		path .. ": Max Fidelity sits next to Force Smooth, not in the Perf group")
end

print(("\n%d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
