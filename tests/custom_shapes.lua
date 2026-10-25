-- In-game shape registration, validation, and persistence.
-- python tools/test_luau.py --luau PATH_TO_LUAU tests/custom_shapes.lua
package.path = "tests/?.lua;" .. package.path
require("robloxenv")
local controls = assert(loadfile("PluginControls.lua"))()
local custom_shapes = assert(loadfile("CustomShapes.lua"))()
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function count(values) local n = 0; for _ in pairs(values) do n = n + 1 end; return n end
local source = [[
return {
    Controls = {
        { Type = "Slider", Name = "Radius", Key = "radius", Min = 2, Max = 100, Default = 12 },
        { Type = "Toggle", Name = "Wave", Key = "wave" },
        { Type = "TextBox", Name = "Label", Key = "label" },
        { Type = "Button", Name = "Reset", Key = "reset", Callback = function() end },
    },
    f2 = function(p, center) return Vector3.zero, center end,
}
]]

local function rig()
    local calls = { refresh = 0, keys = 0, switch = 0 }
    local context = {
        x1 = { k6 = "Black Hole" }, x2 = { ["Black Hole"] = { original = true } },
        x6 = {}, loaded_shapes = {}, local_shapes = {}, plugin_controls = controls,
    }
    context.x6.populate_modes = function() calls.refresh = calls.refresh + 1 end
    context.x5 = { refresh_keybinds = function() calls.keys = calls.keys + 1 end }
    context.x4 = { switch_shape = function(name, persist)
        calls.switch = calls.switch + 1
        calls.persist = persist
        context.x1.k6 = name
        return true
    end }
    return context, custom_shapes.create(context), calls
end

local function disk()
    local files, folders = {}, {}
    local writes = 0
    isfolder = function(path) return folders[path] == true end
    makefolder = function(path) folders[path] = true end
    isfile = function(path) return files[path:gsub("\\", "/")] ~= nil end
    listfiles = function(path)
        local paths = {}
        for name in pairs(files) do
            if name:sub(1, #path + 1) == path .. "/" then paths[#paths + 1] = name end
        end
        return paths
    end
    writefile = function(path, value)
        assert(folders["GravityShapes"], "missing folder")
        writes = writes + 1
        files[path:gsub("\\", "/")] = value
    end
    readfile = function(path) return assert(files[path:gsub("\\", "/")], "missing file") end
    return files, function() return writes end
end

-- A successful check gives useful defaults but changes no selection or registry.
do
    disk()
    writefile = nil
    local context, manager, calls = rig()
    local ok, value = manager.validate("  My Orbit.lua  ", "```lua\n" .. source .. "\n```")
    check(ok and value.name == "My Orbit" and type(value.module.f2) == "function", "check accepts a named Lua module and pasted code fence")
    check(value.defaults.radius == 12 and value.defaults.wave == false and value.defaults.label == "" and value.defaults.reset == nil,
        "control defaults retain value types and omit button actions")
    check(count(context.x2) == 1 and next(context.loaded_shapes) == nil and calls.switch == 0 and calls.refresh == 0,
        "checking does not register, select, or rebuild shapes")
    ok, value = manager.add("  My Orbit.lua  ", source)
    check(ok and value.name == "My Orbit" and value.persisted == false and value.path == nil,
        "creation works for this session when file writing is unavailable")
    check(type(context.loaded_shapes["My Orbit"].f2) == "function" and context.x2["My Orbit"].radius == 12,
        "creation registers the module and its defaults together")
    check(context.x1.k6 == "My Orbit" and calls.switch == 1 and calls.refresh == 1 and calls.keys == 1,
        "creation immediately switches shape and refreshes selectors and keybinds")
    check(type(value.message) == "string" and #value.message > 0, "session-only creation reports its persistence status")
end

-- Rejected inputs must leave the existing shape, settings, selection, and disk intact.
do
    local _, written = disk()
    local context, manager, calls = rig()
    context.loaded_shapes.Cached = { f2 = function() end }
    context.local_shapes.Saved = "GravityShapes/Saved.lua"
    local original = context.x2["Black Hole"]
    local cases = {
        { "", source }, { "   ", source }, { "../Escape", source }, { "Bad/Path", source },
        { "Bad\\Path", source }, { "Bad:Name", source }, { "CON", source }, { "Trailing.", source },
        { string.rep("x", 81), source }, { "black hole", source }, { "cached", source }, { "SAVED", source },
        { "Broken", "return {" }, { "Broken", "error('invalid module')" }, { "Broken", "return 42" },
        { "Broken", "return {}" }, { "Broken", "return { f2 = true }" }, { "Broken", "" },
        { "Broken", string.rep(" ", 64 * 1024 * 1024 + 1) },
    }
    for _, input in ipairs(cases) do
        local ok, err = manager.add(input[1], input[2])
        check(not ok and type(err) == "string" and #err > 0, "invalid custom shape is rejected: " .. input[1])
        check(count(context.x2) == 1 and context.x2["Black Hole"] == original and count(context.loaded_shapes) == 1
            and count(context.local_shapes) == 1 and context.x1.k6 == "Black Hole" and written() == 0,
            "rejection leaves registrations, settings, selection and saved files unchanged")
    end
    check(calls.switch == 0 and calls.refresh == 0, "rejected adds do not switch or refresh")
end

-- Malformed Controls would crash panel construction after registration.
do
    local _, written = disk()
    local context, manager = rig()
    for _, controls_source in ipairs({
        "false", "{ false }", "{ { Type='Unknown', Name='Bad', Key='bad' } }",
        "{ [2]={ Type='Toggle', Name='Bad', Key='bad' } }",
        "{ { Type='Toggle', Name='Bad', Key='  ' } }",
        "{ { Type='Toggle', Name='First', Key='same' }, { Type='Slider', Name='Second', Key='same', Min=0, Max=1 } }",
        "{ { Type='Slider', Name='Bad', Key='bad', Min=0, Max=0 } }",
        "{ { Type='Slider', Name='Bad', Key='bad', Min=0, Max=100, Div=0 } }",
        "{ { Type='Slider', Name='Bad', Key='bad', Min=0, Max=100, Default=0/0 } }",
        "{ { Type='Slider', Name='Bad', Key='bad', Min=0, Max=1e300, Div=1e-300 } }",
        "{ { Type='Slider', Name='Bad', Key='bad', Min=0, Max=100, Div=10, Default=20 } }",
        "{ { Type='Slider', Name='Bad', Key='bad', Min=0, Max=100, ExactMax='false' } }",
        "{ { Type='Toggle', Name='Bad', Key='bad', Default='false' } }",
        "{ { Type='TextBox', Name='Bad', Key='bad', Default=12 } }",
        "{ { Type='Button', Name='Bad', Key='bad' } }",
    }) do
        local ok, err = manager.add("Broken controls", "return {f2=function() end, Controls=" .. controls_source .. "}")
        check(not ok and type(err) == "string" and context.x2["Broken controls"] == nil
            and next(context.loaded_shapes) == nil and written() == 0, "invalid Controls are rejected before registration and writing")
    end
end

-- Metadata consumed outside f2 must not crash the per-frame or touch handlers.
do
    local _, written = disk()
    local context, manager = rig()
    for _, metadata in ipairs({
        "px=true", "cleanup={}", "FrameTracking='false'", "NoBlend=0", "MobileControls=false",
        "MobileControls={Action=42}", "MobileControls={Range='far'}", "MobileControls={Range=0/0}",
    }) do
        local ok, err = manager.add("Invalid metadata", "return { f2=function() end, " .. metadata .. " }")
        check(not ok and type(err) == "string" and context.x2["Invalid metadata"] == nil and written() == 0,
            "invalid module metadata is rejected before activation: " .. metadata)
    end
    local ok = custom_shapes.validate_module({ f2 = function() end, px = function() end, cleanup = function() end,
        FrameTracking = true, NoBlend = true, MobileControls = { Action = "FIRE", Range = 600 } })
    check(ok, "the reusable module validator accepts supported callbacks and mobile controls")
end

-- Review and Add commit the exact initialized module once, including renamed
-- exports/code fences, while stale, forged and foreign review handles cannot pass.
do
    disk()
    writefile = nil
    local context, manager, calls = rig()
    getgenv()._REVIEW_IMPORT_RUNS = 0
    local reviewed_source = "getgenv()._REVIEW_IMPORT_RUNS = getgenv()._REVIEW_IMPORT_RUNS + 1;\n" .. source
    local raw_source = "\239\187\191```luau\n" .. reviewed_source .. "\n```"
    local ok, review = manager.validate("  Reviewed Orbit.lua ", raw_source)
    check(ok and getgenv()._REVIEW_IMPORT_RUNS == 1 and review.source == reviewed_source:match("^%s*(.-)%s*$"),
        "review initializes a BOM-prefixed fenced export exactly once")
    local reviewed_module = review.module
    local _, other_manager = rig()
    check(not other_manager.add("  Reviewed Orbit.lua ", raw_source, review), "reviews belong to their original manager")
    check(not manager.add("Renamed", raw_source, review), "a renamed draft needs another review")
    check(not manager.add("  Reviewed Orbit.lua ", raw_source .. "\n", review), "an edited draft needs another review")
    check(not manager.add("Forged", source, { name = "Forged", source = source, module = reviewed_module }),
        "an unrecognized review cannot bypass validation")
    review.name, review.source, review.module, review.defaults = "Tampered", "error('tampered')", {}, { radius = 999 }
    local added, value = manager.add("  Reviewed Orbit.lua ", raw_source, review)
    check(added and value.name == "Reviewed Orbit" and context.loaded_shapes["Reviewed Orbit"] == reviewed_module
        and context.x2["Reviewed Orbit"].radius == 12 and context.x2.Tampered == nil,
        "changing review presentation data cannot replace its accepted name, source, module or defaults")
    check(getgenv()._REVIEW_IMPORT_RUNS == 1 and calls.switch == 1,
        "adding a reviewed shape activates the same module without repeating its initializer")
    check(not manager.add("  Reviewed Orbit.lua ", raw_source, review), "a committed review is consumed")
    getgenv()._REVIEW_IMPORT_RUNS = nil
end

do
    disk()
    writefile = nil
    local context, manager = rig()
    local ok, review = manager.validate("Mutated controls", source)
    check(ok, "review accepts the original control contract")
    review.module.Controls[1].Div = 0
    local added, err = manager.add("Mutated controls", source, review)
    check(not added and type(err) == "string" and context.x2["Mutated controls"] == nil,
        "metadata changed after review is revalidated before registration")
end

do
    local files, written = disk()
    local context, manager = rig()
    local ok, value = manager.add("Saved Orbit", source)
    check(ok and value.persisted and value.reloadable and value.path == "GravityShapes/Saved Orbit.lua", "a supported executor saves a named Lua shape")
    check(written() == 1 and files[value.path] == source:match("^%s*(.-)%s*$") and context.local_shapes["Saved Orbit"] == value.path,
        "the source is written once and registered at its saved path")
    files["GravityShapes/Existing.TXT"] = source
    local before = count(context.x2)
    ok, value = manager.add("existing", source)
    check(not ok and type(value) == "string" and written() == 1 and count(context.x2) == before,
        "a case-insensitive file collision cannot overwrite an unregistered saved shape")
end

do
    isfolder, makefolder, listfiles, readfile = nil, nil, nil, nil
    local saved = {}
    isfile = function(path) return saved[path] ~= nil end
    writefile = function(path, text) saved[path] = text end
    local context, manager, calls = rig()
    local ok, value = manager.add("Partial disk support", source)
    check(ok and value.persisted and not value.reloadable and saved[value.path] ~= nil,
        "writing a file is distinguished from support for loading it next launch")
    check(value.message:find("Automatic loading next launch is unavailable", 1, true) ~= nil and calls.persist == false
        and context.x1.k6 == "Partial disk support", "partial file support reports the limitation and keeps the selection session-only")
end

for _, failure in ipairs({ "write", "folder", "unsupported_probe" }) do
    local files, written = disk()
    if failure == "write" then writefile = function() error("disk full") end end
    if failure == "folder" then makefolder = function() error("folder unavailable") end end
    if failure == "unsupported_probe" then isfile, listfiles, isfolder = nil, nil, nil end
    local context, manager = rig()
    local ok, value = manager.add("Temporary Orbit", source)
    check(ok and not value.persisted and value.path == nil and context.x2["Temporary Orbit"] ~= nil,
        failure .. " failure still adds a usable session shape with accurate save status")
    check(next(files) == nil and written() == 0, failure .. " does not pretend a file was saved")
end

for _, failure in ipairs({ "false_return", "truncated", "readback" }) do
    local files = disk()
    if failure == "false_return" then writefile = function() return false end end
    if failure == "truncated" then writefile = function(path, text) files[path] = text:sub(1, 20) end end
    if failure == "readback" then readfile = function() error("read unavailable") end end
    local context, manager = rig()
    local ok, value = manager.add("Unverified save", source)
    check(ok and not value.persisted and not value.reloadable and value.path == nil
        and context.local_shapes["Unverified save"] == nil and context.x2["Unverified save"] ~= nil,
        failure .. " does not report an incomplete or unverifiable write as saved")
    check(value.message:find("session only", 1, true), failure .. " still leaves a usable session import")
end

do
    local files = disk()
    files["GravityShapes/existing.lua"] = source
    isfolder, makefolder = nil, nil
    writefile = function(path, value) files[path] = value end
    local _, manager, calls = rig()
    local ok, value = manager.add("No folder helpers", source)
    check(ok and value.persisted and value.reloadable and calls.persist,
        "existing directories reload successfully with readfile/listfiles but no folder helpers")
end

-- Reading a file can import large exports without sending their bytes through a
-- TextBox. Files already placed in GravityShapes can be registered in place.
do
    local files, written = disk()
    makefolder("GravityShapes")
    local path = "GravityShapes/Already saved.lua"
    local original = "\239\187\191" .. source
    files[path] = original
    local context, manager = rig()
    local ok, review = manager.validate("Already saved", original, "./" .. path)
    check(ok and review.existing_path == path, "a matching source file can be reviewed without a destination collision")
    local added, value = manager.add("Already saved", original, review)
    check(added and value.persisted and value.reloadable and value.path == path
        and context.local_shapes["Already saved"] == path and files[path] == original and written() == 0,
        "an existing source is registered in place with no rewrite or duplicate initialization")
end

do
    local files, written = disk()
    makefolder("GravityShapes")
    files["GravityShapes/Original Case.lua"] = source
    local context, manager = rig()
    local ok, err = manager.validate("original case", source, "GravityShapes/Original Case.lua")
    check(not ok and type(err) == "string" and context.x2["original case"] == nil and written() == 0,
        "an in-place import cannot register a name that changes spelling on next discovery")
end

do
    local files, written = disk()
    files["gravityshapes/Case sensitive directory.LUA"] = source
    local context, manager = rig()
    local name = "Case sensitive directory"
    local ok, review = manager.validate(name, source, "gravityshapes/Case sensitive directory.LUA")
    check(ok and review.existing_path == nil, "a differently cased source directory is treated as an external file")
    local added, value = manager.add(name, source, review)
    check(added and value.path == "GravityShapes/Case sensitive directory.lua" and written() == 1
        and context.local_shapes[name] == value.path and files[value.path] ~= nil,
        "external directory imports save into the exact directory used by next-launch discovery")
end

do
    local files, written = disk()
    makefolder("GravityShapes")
    local path = "GravityShapes/Uppercase extension.TXT"
    files[path] = source
    local _, manager = rig()
    local ok, review = manager.validate("Uppercase extension", source, path)
    check(ok and review.existing_path == path, "an uppercase file extension retains the same discoverable shape name")
    local added, value = manager.add("Uppercase extension", source, review)
    check(added and value.path == path and written() == 0, "supported uppercase extensions can still register in place")
end

for _, failure in ipairs({ "changed", "missing", "unreadable", "duplicate" }) do
    local files, written = disk()
    makefolder("GravityShapes")
    local path = "GravityShapes/Local source.lua"
    files[path] = source
    local context, manager = rig()
    local ok, review = manager.validate("Local source", source, path)
    check(ok, "an existing source reviews before " .. failure)
    if failure == "changed" then files[path] = source .. "\n-- updated"
    elseif failure == "missing" then files[path] = nil
    elseif failure == "unreadable" then readfile = nil
    else files["GravityShapes/Local source.txt"] = source end
    local added, err = manager.add("Local source", source, review)
    check(not added and type(err) == "string" and context.x2["Local source"] == nil and written() == 0,
        failure .. " source prevents an in-place import without changing the file")
end

do
    local files, written = disk()
    local context, manager = rig()
    files["exports/Original.lua"] = source
    local ok, review = manager.validate("Copied export", source, "exports/Original.lua")
    check(ok and review.existing_path == nil, "an external source keeps an independent destination name")
    local added, value = manager.add("Copied export", source, review)
    check(added and value.path == "GravityShapes/Copied export.lua" and written() == 1
        and files["exports/Original.lua"] == source and context.local_shapes["Copied export"] == value.path,
        "an external file is copied into GravityShapes without changing its original")
end

-- Module initializers may yield; an old editor cannot register into a closed session.
for _, invalidation in ipairs({ "teardown", "replacement" }) do
    local _, written = disk()
    local context, manager, calls = rig()
    context.session_id = "custom-shape-test"
    getgenv()._GRAVITY_SESSION_ID = context.session_id
    local result, detail
    local thread = coroutine.create(function()
        result, detail = manager.add("Slow Orbit", "coroutine.yield('initializing'); " .. source)
    end)
    local ok, yielded = coroutine.resume(thread)
    check(ok and yielded == "initializing", "shape validation can yield during initialization")
    local second, second_error = manager.add("Concurrent Orbit", source)
    check(not second and type(second_error) == "string" and context.x2["Concurrent Orbit"] == nil,
        "a second add cannot race a yielding import")
    if invalidation == "teardown" then context.x6.torn_down = true else getgenv()._GRAVITY_SESSION_ID = "new-session" end
    check(coroutine.resume(thread) and coroutine.status(thread) == "dead", "cancelled initialization returns safely")
    check(result == false and type(detail) == "string" and count(context.x2) == 1 and next(context.loaded_shapes) == nil
        and written() == 0 and calls.switch == 0, invalidation .. " stops late registration and persistence")
    getgenv()._GRAVITY_SESSION_ID = nil
end

-- A prepared review must still recheck session identity and on-disk collisions.
for _, invalidation in ipairs({ "teardown", "replacement", "disk_collision" }) do
    local files, written = disk()
    local context, manager, calls = rig()
    context.session_id = "review-session"
    getgenv()._GRAVITY_SESSION_ID = context.session_id
    local ok, review = manager.validate("Delayed add", source)
    check(ok, "review succeeds before " .. invalidation)
    if invalidation == "teardown" then context.x6.torn_down = true
    elseif invalidation == "replacement" then getgenv()._GRAVITY_SESSION_ID = "replacement-session"
    else makefolder("GravityShapes"); files["GravityShapes/Delayed add.lua"] = "original" end
    local added, err = manager.add("Delayed add", source, review)
    check(not added and type(err) == "string" and context.x2["Delayed add"] == nil and written() == 0 and calls.switch == 0,
        invalidation .. " prevents committing a previously reviewed module")
    getgenv()._GRAVITY_SESSION_ID = nil
end

print(checks .. " custom shape registration checks passed")
