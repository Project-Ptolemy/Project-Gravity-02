-- Every Controls entry must have a config.lua default of the matching final type.
-- Explicit module defaults must also match so importing the same module under a
-- custom name does not silently start it with different settings.
--
-- load_settings (main.lua) only restores a saved value when a default of the
-- same type already exists, and reset_config only restores what it snapshotted
-- from that table. So a key a shape's Controls touch but config omits will
-- silently forget itself between sessions and survive "Reset All Settings" --
-- and a boolean stored as a number drops just as quietly. That is a whole class
-- of bug that never throws, so nothing surfaces it but a check like this.
--
--   luajit tests/controls_lint.lua      (from the repo root)

-- config.lua builds value types at load; the shapes need a couple of Luau
-- builtins LuaJIT lacks.
local function stub() return setmetatable({}, { __index = function() return 0 end }) end
Vector3 = { new = stub, zero = stub(), xAxis = stub(), yAxis = stub() }
Color3 = { new = stub, fromRGB = stub }
CFrame = { new = stub, identity = stub(), fromAxisAngle = stub }
Enum = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return 0 end }) end })
game = { GetService = function() return setmetatable({}, { __index = function() return function() end end }) end }
workspace = {}
if not table.create then
	table.create = function() return {} end
end
if not math.clamp then
	math.clamp = function(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end
end

local x2 = assert(loadfile("config.lua"))().x2

local names = {}
local pf = assert(io.popen("ls shapes"))
for line in pf:lines() do
	names[#names + 1] = (line:gsub("%.lua$", ""))
end
pf:close()

local problems, checked, covered = 0, 0, 0
for _, name in ipairs(names) do
	local fh = assert(io.open("shapes/" .. name .. ".lua"))
	local src = fh:read("a")
	fh:close()
	-- `continue` is Luau-only and LuaJIT cannot parse it; the substitution keeps
	-- the surrounding structure intact, which is all this check needs.
	-- The continue -> "do end" rewrite that used to be here is gone: current LuaJIT
	-- parses Luau's continue natively, and the rewrite turned a skip into a fall-
	-- through, so any shape using it was linted as different code than it ships.

	local chunk = load(src, name)
	if not chunk then
		print(("PARSE FAIL   %s"):format(name))
		problems = problems + 1
	else
		local ok, M = pcall(chunk)
		if not ok then
			print(("LOAD FAIL    %s: %s"):format(name, tostring(M)))
			problems = problems + 1
		elseif type(M) == "table" and M.Controls then
			covered = covered + 1
			local defaults = x2[name]
			if not defaults then
				print(("NO x2 BLOCK  %s"):format(name))
				problems = problems + 1
			else
				for _, ctl in ipairs(M.Controls) do
					if ctl.Key and ctl.Type ~= "Button" then
						checked = checked + 1
						local want = (ctl.Type == "Toggle") and "boolean"
							or (ctl.Type == "TextBox") and "string"
							or "number"
						local got = defaults[ctl.Key]
						if got == nil then
							print(("MISSING      %-26s %-5s %s"):format(name, ctl.Key, tostring(ctl.Name)))
							problems = problems + 1
						elseif type(got) ~= want then
							print(("TYPE         %-26s %-5s want %s, got %s"):format(name, ctl.Key, want, type(got)))
							problems = problems + 1
						elseif ctl.Default ~= nil and got ~= ctl.Default then
							print(("DEFAULT      %-26s %-5s config %s, module %s"):format(name, ctl.Key, tostring(got), tostring(ctl.Default)))
							problems = problems + 1
						end
					end
				end
			end
		end
	end
end

print(("\n%d controls across %d shapes; %d problems"):format(checked, covered, problems))
os.exit(problems == 0 and 0 or 1)
