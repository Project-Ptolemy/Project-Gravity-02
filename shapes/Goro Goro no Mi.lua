local M = { MobileControls = { Action = "FIRE", Range = 800 } }

local PHI1 = 0.6180339887498949
local PHI2 = 0.7548776662466927
local HM = 16777216

local function h(seed, node, chan)
	local x = ((seed % 1048576) * 73856093 + node * 19349663 + chan * 83492791) % HM
	x = (x * x + x * 22695477 + 12345) % HM
	return x / HM
end
M._h = h

local function basis(dir)
	local u = Vector3.new(-dir.Z, 0, dir.X)
	if u.Magnitude < 1e-4 then
		u = Vector3.new(1, 0, 0)
	else
		u = u.Unit
	end
	return u, dir:Cross(u).Unit
end

local function sin_taper(j, n)
	return math.sin(math.pi * j / n)
end

local function tip_taper(j, n)
	return 1 - j / n
end

local function on_path(origin, dir, len, n, amp, seed, chan, taper, f)
	local u, v = basis(dir)
	local function node(j)
		local w = taper(j, n)
		return origin + dir * ((j / n) * len)
			+ u * (amp * w * (2 * h(seed, j, chan) - 1))
			+ v * (amp * w * (2 * h(seed, j, chan + 1) - 1))
	end
	local q = f * n
	local j = math.floor(q)
	if j >= n then j = n - 1 end
	if j < 0 then j = 0 end
	return node(j) + (node(j + 1) - node(j)) * (q - j), u, v
end

local function resolve_aim(cen, c, x6)
	local length = c.k11 or 200
	local mobile = x6 and x6.mobile_input
	if mobile and mobile.active and mobile.shape == "Goro Goro no Mi" and mobile.direction then
		return cen + mobile.direction * length
	end

	if c.k19 then
		local ok, hit = pcall(function()
			local plrs = game:GetService("Players")
			local plr = plrs and plrs.LocalPlayer
			local mouse = plr and plr:GetMouse()
			if mouse and mouse.Hit then
				local pos = mouse.Hit.Position
				if pos and pos.Magnitude < 10000 then
					return pos
				end
			end
			local cam = workspace.CurrentCamera
			if not cam then return nil end
			local uis = game:GetService("UserInputService")
			local ml = uis:GetMouseLocation()
			local ray = cam:ViewportPointToRay(ml.X, ml.Y)
			local res = workspace:Raycast(ray.Origin, ray.Direction * 1000)
			return res and res.Position or (ray.Origin + ray.Direction * length)
		end)
		if ok and hit then
			return hit
		end
	end

	local ok2, look = pcall(function()
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame and cam.CFrame.LookVector or nil
	end)
	local dir = Vector3.new(0, 0, 1)
	if ok2 and look and look.Magnitude > 0.1 then
		dir = look.Unit
	end
	return cen + dir * length
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local nodes = math.clamp(math.floor(c.k12 or 18), 4, 64)
	-- Clamped to their own sliders' bounds, like nodes and flicker already were. A
	-- config file is not bound by the panel's Min/Max, and a negative amp mirrors
	-- the noise instead of removing it.
	local amp = math.clamp(c.k13 or 14, 0, 100)
	local flicker = math.clamp(c.k14 or 12, 1, 300)

	local st = x6.pre and x6.pre["Goro Goro no Mi"]
	if not st then
		st = { seed = 1, last_gen = -1, next_roll = 0 }
		if x6.pre then
			x6.pre["Goro Goro no Mi"] = st
		end
	end

	-- Read by the input handlers, which are made once and outlive a toggle change,
	-- so the live value has to reach them through the state table. Without this,
	-- turning Hold To Fire off mid-hold left st.holding latched true forever and
	-- the bolt never stopped.
	local hold_mode = c.k20 and true or false
	st.hold_enabled = hold_mode
	if not hold_mode then
		st.holding = false
		st.tap_locked = false
	end

	if not st.conns then
		st.conns = {}
		local ok = pcall(function()
			local uis = game:GetService("UserInputService")
			st.touch_mode = uis.TouchEnabled and not uis.KeyboardEnabled
			st.conns[#st.conns + 1] = uis.InputBegan:Connect(function(inp, gpe)
				if gpe or not st.hold_enabled or (x6.mobile_input and x6.mobile_input.active) then return end
				if inp.UserInputType == Enum.UserInputType.MouseButton1 then
					st.holding = true
				elseif inp.UserInputType == Enum.UserInputType.Touch then
					if st.touch_mode then
						st.tap_locked = not st.tap_locked
					else
						st.holding = true
					end
				end
			end)
			st.conns[#st.conns + 1] = uis.InputEnded:Connect(function(inp)
				-- Not gated on hold_enabled: a release always has to clear the flag,
				-- or turning the toggle off between press and release strands it.
				if inp.UserInputType == Enum.UserInputType.MouseButton1 then
					st.holding = false
				elseif inp.UserInputType == Enum.UserInputType.Touch and not st.touch_mode then
					st.holding = false
				end
			end)
		end)
		if not ok then
			st.conns = nil
		end
	end

	local et = math.max(1, math.floor(x1.k7 or 1))
	local gen = math.floor((x6.f or 0) / et)
	if st.last_gen ~= gen then
		st.last_gen = gen
		if t >= st.next_roll then
			st.seed = st.seed + 1
			st.next_roll = t + 1 / flicker
		end
		st.aim = resolve_aim(cen, c, x6)
	end
	if not st.aim then
		st.aim = resolve_aim(cen, c, x6)
	end

	local seed = st.seed
	local aim = st.aim

	local firing = true
	if hold_mode then
		firing = st.holding or st.tap_locked or x1.IsLaunching or false
		local mobile = x6.mobile_input
		if mobile and mobile.active and mobile.shape == "Goro Goro no Mi" then
			firing = mobile.held or x1.IsLaunching or false
		end
	end

	if not firing then
		local id0 = d.slot or d.id or 1
		-- Same clamp as thick below, since this reads the same control and the
		-- idle cloud collapses to a point at 0 otherwise.
		local rad = 6 + math.clamp(c.k18 or 2, 0, 20)
		local cloud = cen + Vector3.new(
			(2 * h(seed, id0, 11) - 1) * rad,
			(2 * h(seed, id0, 12) - 1) * rad,
			(2 * h(seed, id0, 13) - 1) * rad)
		return (cloud - p.Position) * (x1.k10 * x9.c1), cloud
	end

	local rel = aim - cen
	local len = rel.Magnitude
	if len < 1e-3 then
		return Vector3.zero, cen
	end
	local dir = rel.Unit

	local branches = math.clamp(math.floor(c.k15 or 3), 0, 12)
	local share = math.clamp(c.k16 or 0.3, 0, 0.8)
	local bfrac = math.clamp(c.k17 or 0.4, 0.1, 1.0)
	local thick = math.clamp(c.k18 or 2, 0, 20)

	local id = d.slot or d.id or 1
	local f1 = (id * PHI1) % 1
	local f2 = (id * PHI2) % 1

	local pos, u, v
	if branches > 0 and f2 < share then
		local q = f2 / share * branches
		local bi = math.floor(q)
		if bi >= branches then bi = branches - 1 end

		local bnodes = math.max(2, math.floor(nodes / 3))
		local bu, bv = basis(dir)
		local bdir = (dir
			+ bu * ((2 * h(seed, bi, 4) - 1) * 0.9)
			+ bv * ((2 * h(seed, bi, 5) - 1) * 0.9)).Unit
		local blen = len * bfrac * (0.5 + 0.5 * h(seed, bi, 6))

		local root_j = 1 + math.floor(h(seed, bi, 3) * (nodes - 1))
		local root = on_path(cen, dir, len, nodes, amp, seed, 1, sin_taper, root_j / nodes)

		pos, u, v = on_path(root, bdir, blen, bnodes, amp * 0.6, seed + 991 + bi, 1,
			tip_taper, q - bi)
	else
		pos, u, v = on_path(cen, dir, len, nodes, amp, seed, 1, sin_taper, f1)
	end

	pos = pos
		+ u * ((2 * h(seed, id, 7) - 1) * thick)
		+ v * ((2 * h(seed, id, 8) - 1) * thick)

	if c.k21 then
		local want = x1.k3 or Color3.fromRGB(0, 255, 255)
		if p.Material ~= Enum.Material.Neon then
			p.Material = Enum.Material.Neon
		end
		if p.Color ~= want then
			p.Color = want
		end
	end

	return (pos - p.Position) * (x1.k10 * x9.c1), pos
end

function M.cleanup(x6, x1)
	if not x6 or not x6.pre then
		return
	end
	local st = x6.pre["Goro Goro no Mi"]
	if st and st.conns then
		for _, conn in ipairs(st.conns) do
			pcall(function()
				conn:Disconnect()
			end)
		end
		-- Emptied as well as disconnected: cleanup can run while the same state
		-- table is still reachable (Part Control unrefs a module without dropping
		-- x6.pre), and a second pass would then Disconnect dead connections.
		table.clear(st.conns)
		st.conns = nil
		st.hold_enabled = false
		st.holding = false
		st.tap_locked = false
	end
	x6.pre["Goro Goro no Mi"] = nil
end

M.Controls = {
	{ Type = "Slider", Name = "Bolt Length", Min = 20, Max = 1000, Key = "k11", Default = 200 },
	{ Type = "Slider", Name = "Node Count", Min = 4, Max = 64, Key = "k12", Default = 18, IntOnly = true },
	{ Type = "Slider", Name = "Jaggedness", Min = 0, Max = 100, Key = "k13", Default = 14 },
	{ Type = "Slider", Name = "Flicker Rate", Min = 1, Max = 300, Key = "k14", Default = 12, ExactMax = true },
	{ Type = "Slider", Name = "Branch Count", Min = 0, Max = 12, Key = "k15", Default = 3, IntOnly = true },
	{ Type = "Slider", Name = "Branch Share", Min = 0, Max = 80, Key = "k16", Default = 30, Div = 100 },
	{ Type = "Slider", Name = "Branch Length", Min = 10, Max = 100, Key = "k17", Default = 40, Div = 100 },
	{ Type = "Slider", Name = "Core Thickness", Min = 0, Max = 20, Key = "k18", Default = 2 },
	{ Type = "Toggle", Name = "Aim At Cursor", Key = "k19", Default = true },
	{ Type = "Toggle", Name = "Hold To Fire", Key = "k20", Default = false },
	{ Type = "Toggle", Name = "Neon Recolour", Key = "k21", Default = false },
}

return M
