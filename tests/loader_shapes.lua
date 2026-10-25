-- Exercise saved plugins and damaged settings through the actual loader.
package.path = "tests/?.lua;" .. package.path
local fixture = require("runtime_fixture")
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local validator = assert(loadfile("CustomShapes.lua"))()
for _, directory in ipairs({ "shapes", "shapes-onreview" }) do
	local listing = assert(io.popen("ls " .. directory))
	for name in listing:lines() do
		if name:match("%.lua$") then
			local shape = assert(loadfile(directory .. "/" .. name))()
			local valid, reason = validator.validate_module(shape)
			check(valid, name .. " follows the import contract: " .. tostring(reason))
		end
	end
	listing:close()
end

local sources, settings_data, favorites_data, failed_module = {}, nil, nil, nil
local warnings, writes = {}, {}
warn = function(message) warnings[#warnings + 1] = message end
game.HttpGet = function(_, url)
	local path = assert(url:match("/main/(.-)%?cb="), url)
	if path == failed_module then return "error('dependency initialization failed')" end
	local file = assert(io.open(path), path)
	local source = file:read("a"); file:close(); return source
end
isfolder, makefolder = nil, nil
listfiles = function()
	local names = {}
	for path in pairs(sources) do names[#names + 1] = path end
	names[#names + 1] = false -- tolerate malformed unrelated list entries
	return names
end
isfile = function(path)
	return sources[path] ~= nil or (path == "GravitySettings_Auto.json" and settings_data ~= nil)
		or (path == "GravityFavorites.json" and favorites_data ~= nil)
end
readfile = function(path) return sources[path] or path end
writefile = function(path, source) writes[path] = source end
local http = fixture.env.svc("HttpService")
http.JSONDecode = function(_, path)
	if path == "GravityFavorites.json" then return favorites_data end
	return settings_data
end
local encoded
http.JSONEncode = function(_, value) encoded = value; return "encoded" end
local original_delay = task.delay
task.delay = function(_, callback) callback() end
local module_source = [[
getgenv()._LOADER_TEST_INITIALIZATIONS = (getgenv()._LOADER_TEST_INITIALIZATIONS or 0) + 1
return { f2 = function() return Vector3.zero end, Controls = {
    { Type = "Slider", Name = "Radius", Key = "radius", Min = 0, Max = 100, Default = 12 }
} }
]]
for _, mobile in ipairs({ false, true }) do
	fixture.input.TouchEnabled, fixture.input.KeyboardEnabled = mobile, not mobile
	getgenv()._LOADER_TEST_INITIALIZATIONS = 0
	sources = {
		["GravityShapes/Valid.lua"] = "\239\187\191" .. module_source,
		["GravityShapes/Valid.txt"] = "error('duplicate must not execute')",
		["GravityShapes/valid.lua"] = "error('case duplicate must not execute')",
		["GravityShapes/Empty.lua"] = "return {}",
		["GravityShapes/Broken.lua"] = "error('broken module')",
		["GravityShapes/Syntax.lua"] = "return {",
		["GravityShapes/Bad controls.lua"] = "return { f2 = function() end, Controls = 'wrong' }",
		["GravityShapes/Fenced.txt"] = "```luau\nreturn { f2 = function() return Vector3.zero end }\n```",
		["GravityShapes/Black Hole.lua"] = "return {}", -- invalid overrides cannot hide built-ins
		["GravityShapes/Celestial Ribbon.lua"] = [[return { f2 = function() return Vector3.zero end,
			Controls = { { Type = "Toggle", Name = "Enabled", Key = "k11", Default = true } } }]],
	}
	settings_data = { x1 = { k6 = "Valid", Damping = { __type = "nan" }, MaxSpeed = { __type = "inf" },
		k4 = { __type = "inf" }, Paused = true, IsLaunching = true, TgtActive = true,
		k5 = { "CustomIgnore", 42, "Second", "Third" },
		Keybinds = { Recenter = "F5", Reset = false, Shapes = { Valid = "F6", Invalid = 3 } } },
		x2 = { Valid = { radius = 31 }, ["Black Hole"] = false, ["Celestial Ribbon"] = { k11 = 40 } } }
	favorites_data = { Valid = true, Bad = "wrong" }
	assert(loadfile("main.lua"))()
	local context = assert(getgenv()._GRAVITY_CONTEXT, "session starts with partially invalid local files")
	check(getgenv()._LOADER_TEST_INITIALIZATIONS == 1, "saved module initializes only once per session")
	check(context.local_shapes.Valid == "GravityShapes/Valid.lua" and context.x1.k6 == "Valid",
		"read-only file APIs discover and select saved custom shapes deterministically")
	check(context.get_shape("Valid") == context.loaded_shapes.Valid and context.x2.Valid.radius == 31,
		"cached plugin retains saved controls")
	check(context.local_shapes.Fenced == "GravityShapes/Fenced.txt" and context.get_shape("Fenced") ~= nil,
		"a fenced source registered in place by the editor can load on the next launch")
	for _, name in ipairs({ "Empty", "Broken", "Syntax", "Bad controls", "valid" }) do
		check(context.x2[name] == nil and context.local_shapes[name] == nil, name .. " cannot claim a selector slot")
	end
	check(context.local_shapes["Black Hole"] == nil and type(context.get_shape("Black Hole").f2) == "function",
		"invalid disk override falls back to the shipped shape")
	check(context.x2["Celestial Ribbon"].k11 == true,
		"a local override's declared control types replace incompatible built-in and saved values")
	check(context.x1.Damping == 0.5 and context.x1.MaxSpeed == 500 and context.x1.k4 == math.huge,
		"nonfinite saved physics numbers use defaults while unlimited force remains valid")
	check(not context.x1.Paused and not context.x1.IsLaunching and not context.x1.TgtActive,
		"old settings cannot restore live pause, launch or targeting state")
	check(context.x1.Keybinds.Recenter == "F5" and context.x1.Keybinds.Reset == "Q"
		and context.x1.Keybinds.Shapes.Valid == "F6" and context.x1.Keybinds.Shapes.Invalid == nil,
		"saved keybind types are validated recursively without losing custom shortcuts")
	check(#context.x1.k5 == 3 and context.x1.k5[3] == "Third", "custom ignore lists preserve valid extra entries")
	check(context.favorites.Valid and context.favorites.Bad == nil, "invalid favorite values are ignored")
	context.save_settings()
	check(writes["GravitySettings_Auto.json"] == "encoded" and encoded.x2.Valid.radius == 31,
		"custom shape settings save normally")
	check(encoded.x1.S == nil and encoded.x1.Targets == nil and encoded.x1.Paused == nil,
		"saved preferences omit registry aliases and session state")
	context.destroy()
end

sources = {}
for _, data in ipairs({ {}, { x1 = false, x2 = 42 }, { x1 = { Keybinds = { Shapes = false } } },
	{ x1 = { k6 = "Missing shape" }, x2 = {} } }) do
	settings_data, favorites_data = data, true
	assert(loadfile("main.lua"))()
	local context = assert(getgenv()._GRAVITY_CONTEXT, "malformed settings must not prevent startup")
	check(context.x1.k6 == "Celestial Ribbon" and type(context.x1.Keybinds.Shapes) == "table",
		"malformed settings retain a working shape and keybindings")
	context.destroy()
end
settings_data, favorites_data = nil, nil
failed_module = "CustomShapes.lua"
assert(loadfile("main.lua"))()
check(getgenv()._GRAVITY_CONTEXT == nil and fixture.find("GravityLoading") == nil,
	"an early dependency exception removes the loading overlay without publishing a session")
check(fixture.run.RenderStepped:count() == 0, "early failure disconnects the loading spinner")
task.delay = original_delay
print(checks .. " loader and catalog validation checks passed")
