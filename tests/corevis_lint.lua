-- The core marker's visibility. Three call sites used to decide it
-- independently -- creation, apply_disabled, and nothing at all for pause -- so
-- adding "hide it while paused" needed a single owner first. These checks pin
-- that owner down and pin down every path that flips Paused, because a pause
-- route that skips the repaint is exactly the bug that would come back.
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

do
	local cfg = assert(loadfile("config.lua"))
	local stub = function() return setmetatable({}, { __index = function() return 0 end }) end
	Vector3 = { new = stub, zero = stub() }
	Color3 = { new = stub, fromRGB = stub }
	local x1 = cfg().x1
	check(x1.HideCoreOnPause ~= nil, "config.lua x1 declares HideCoreOnPause")
	check(type(x1.HideCoreOnPause) == "boolean",
		("HideCoreOnPause is a boolean, not a %s"):format(type(x1.HideCoreOnPause)))
	-- The marker staying visible while paused is what people are used to, and at
	-- least one of them parks it deliberately, so this defaults off.
	check(x1.HideCoreOnPause == false, "HideCoreOnPause defaults to off")
	check(x1.Paused == false, "Paused still starts down")
end

for _, path in ipairs({ "System.lua", "mobilever/System.lua" }) do
	local src = slurp(path)

	check(src:find("local function refresh_core_visual%(%)") ~= nil,
		path .. ": the visibility rule has one owner")
	check(src:find("x4%.refresh_core_visual%s*=%s*refresh_core_visual") ~= nil,
		path .. ": it is published for the UI and runtime controls")

	-- Disabled has to keep hiding it, and the pause reason is additive.
	check(src:find("x1%.Disabled%s+or%s+%(x1%.HideCoreOnPause%s+and%s+x1%.Paused%)") ~= nil,
		path .. ": hidden means Disabled, or paused with the toggle on")

	-- Both halves: the ball's own Transparency and the BillboardGui sprite. Hiding
	-- only the part left the sprite floating in mid-air.
	local body = src:match("local function refresh_core_visual%(%)(.-)\n\tend")
	check(body ~= nil, path .. ": refresh_core_visual is a plain local function")
	check(body == nil or body:find("Transparency") ~= nil, path .. ": it sets Transparency")
	check(body == nil or body:find('FindFirstChild%("Visual"%)') ~= nil,
		path .. ": it reaches the Visual BillboardGui")
	check(body == nil or body:find("visual%.Enabled") ~= nil, path .. ": and toggles it")

	-- No open-coded copies left behind. Both old sites read x9.c7 directly.
	local n = 0
	for _ in src:gmatch("x6%.b%.Transparency%s*=") do n = n + 1 end
	check(n == 1, ("%s: Transparency is written in one place only (%d)"):format(path, n))
	check(src:find("bg%.Enabled%s*=%s*not%s+x1%.Disabled") == nil,
		path .. ": the creation path no longer sets bg.Enabled itself")

	-- Every route that flips Paused has to repaint, or the toggle appears to do
	-- nothing until the next disable.
	for site in src:gmatch("x1%.Paused%s*=%s*not%s+x1%.Paused(.-)end") do
		check(site:find("refresh_core_visual") ~= nil,
			path .. ": a Paused toggle site repaints the core")
	end
	local flips = 0
	for _ in src:gmatch("x1%.Paused%s*=%s*not%s+x1%.Paused") do flips = flips + 1 end
	check(flips >= 1, path .. ": there is still a Paused toggle to check")

	-- Hidden is invisible, not inert: the ball stays anchored and hit-testable so
	-- it can still be dragged, exactly as it already could while disabled.
	check(body == nil or body:find("Anchored") == nil,
		path .. ": hiding does not touch Anchored")
	check(body == nil or body:find("CanCollide") == nil,
		path .. ": hiding does not touch CanCollide")
end

for _, path in ipairs({ "UI.lua", "mobilever/UI.lua" }) do
	local src = slurp(path)
	check(src:find("x1%.HideCoreOnPause%s*=%s*v") ~= nil, path .. ": a toggle writes HideCoreOnPause")
	check(src:find("Hide Core While Paused") ~= nil, path .. ": the toggle is labelled")

	-- Flipped while already paused is the normal case, so the handler has to
	-- repaint rather than wait for the next pause. Bounded by save_settings rather
	-- than a bare `end)`, which the nested `if` would swallow.
	local handler = src:match("x1%.HideCoreOnPause%s*=%s*v(.-)save_settings")
	check(handler ~= nil and handler:find("refresh_core_visual") ~= nil,
		path .. ": the toggle repaints immediately")

	-- The mobile dock is the real pause control on touch, so it needs the repaint
	-- as much as the hotkey does.
	for site in src:gmatch("x1%.Paused%s*=%s*not%s+x1%.Paused(.-)end%)") do
		check(site:find("refresh_core_visual") ~= nil,
			path .. ": a Paused control repaints the core")
	end
end

do
	-- External integrations use the shared runtime effects, including changes
	-- to false: unpausing must repaint just as reliably as pausing.
	local refreshes = 0
	local context = {
		x1 = {}, x6 = {},
		x4 = { refresh_core_visual = function() refreshes = refreshes + 1 end },
	}
	local controls = assert(loadfile("RuntimeControls.lua"))()(context)
	for _, changed in ipairs({ { Paused = true }, { Paused = false },
		{ HideCoreOnPause = true }, { HideCoreOnPause = false } }) do
		local before = refreshes
		controls.apply_settings(changed)
		check(refreshes == before + 1, "runtime pause and visibility changes repaint the core")
	end
	controls.apply_settings({})
	check(refreshes == 4, "unrelated runtime changes do not repaint the core")
end

print(("\n%d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
