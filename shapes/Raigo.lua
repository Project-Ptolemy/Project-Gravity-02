local M = { MobileControls = { Action = "LAUNCH", Range = 800 } }

local PHI = 0.6180339887498949
-- A second irrational, for the radius. Reusing PHI would tie a part's radius to
-- the golden angle sphere_pt already derives its azimuth from, and the ball would
-- come out as a spiral sheet rather than filled.
local PSI = 0.7548776662466927
local TAU = 6.283185307179586
local HM = 16777216

local function prng(s, n, ch)
	local v = ((s % 1048576) * 73856093 + n * 19349663 + ch * 83492791) % HM
	v = (v * v + v * 22695477 + 12345) % HM
	return v / HM
end

local function sphere_pt(idx, total)
	total = math.max(1, total)
	-- Wrapped. d.id comes from x6.part_id_counter, which only ever goes up, so it
	-- outruns x6.n the moment anything is released and re-claimed. Unwrapped, y
	-- fell below -1, rad went to zero through the max(), and every part past the
	-- live count piled onto the south pole. d.slot, when slot ordering is on, is
	-- already inside 1..N, so for that case the wrap is a no-op.
	idx = idx % total
	local y = 1 - (idx / total) * 2
	local rad = math.sqrt(math.max(0, 1 - y * y))
	local theta = TAU * PHI * idx
	return Vector3.new(math.cos(theta) * rad, y, math.sin(theta) * rad)
end

-- A deterministic point in a *solid* ball of the given radius. Direction comes
-- from the Fibonacci lattice above, so consecutive ids stay spread apart; the
-- radius is R * cbrt(u), which is the mapping that fills a volume evenly. R * u
-- would put two thirds of the parts in the outer third of the sphere, and using
-- R flat -- which is what this shape used to do for the 55 % of parts it placed
-- on a "sphere" at all -- puts every one of them on one shell.
--
-- fill is how deep the ball goes: 1 is solid, 0 collapses onto the surface, and
-- anything between is a shell of that thickness.
local function ball_pt(idx, total, radius, fill, u)
	local inner = 1 - fill
	return sphere_pt(idx, total) * (radius * (inner + fill * (u ^ (1 / 3))))
end

-- Rotation about Y, applied to an offset rather than to a position. A solid ball
-- has the same silhouette however it is turned, but the parts in it do not --
-- each one runs a circle, which is where the motion comes from.
local function spin_y(v, c, s)
	return Vector3.new(v.X * c - v.Z * s, v.Y, v.X * s + v.Z * c)
end

local function get_cursor_world_hit(cam, uis, dist)
	dist = dist or 500
	local ok, res = pcall(function()
		local plrs = game:GetService("Players")
		local plr = plrs and plrs.LocalPlayer
		local mouse = plr and plr:GetMouse()
		if mouse and mouse.Hit then
			local p = mouse.Hit.Position
			if p and p.Magnitude < 10000 then
				return p
			end
		end
		if not cam or not uis then return nil end
		local ml = uis:GetMouseLocation()
		local ray = cam:ViewportPointToRay(ml.X, ml.Y)
		local cast = workspace:Raycast(ray.Origin, ray.Direction * dist)
		return cast and cast.Position or (ray.Origin + ray.Direction * dist)
	end)
	return (ok and res) or nil
end

local function get_touch_world_hit(cam, pos, dist)
	dist = dist or 500
	local ok, res = pcall(function()
		if not cam then return nil end
		local ray = cam:ViewportPointToRay(pos.X, pos.Y)
		local cast = workspace:Raycast(ray.Origin, ray.Direction * dist)
		return cast and cast.Position or (ray.Origin + ray.Direction * dist)
	end)
	return (ok and res) or nil
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local r_orb = math.clamp(c.k11 or 8, 2, 40)
	local v_flight = math.clamp(c.k12 or 250, 40, 1200)
	local r_blast = math.clamp(c.k13 or 80, 15, 400)
	local dur_blast = math.clamp(c.k14 or 0.7, 0.15, 3.0)
	local h_hover = math.clamp(c.k15 or 12, 3, 50)
	-- Shell Fill: how much of the radius the parts are allowed to occupy. 100 is a
	-- solid ball, 0 a hollow surface. Stored 0..100 so the panel can show a
	-- percentage; clamped here because a config file is not bound by the slider.
	--
	-- k21/k22 rather than the k16/k17 these replace: load_settings restores any saved
	-- value whose type matches, so reusing the old Arc Count and Arc Jaggedness keys
	-- would have handed an existing user's 8 and 12 to Shell Fill and Surface Jitter
	-- and left them with a thin, rough shell -- exactly the form this shape was
	-- changed to stop being.
	local fill = math.clamp((c.k21 or 100) / 100, 0, 1)
	-- Clamped like every other control here, and to its own slider's bounds. A
	-- negative jitter mirrors the noise rather than removing it, and a config
	-- file is not bound by the panel's Min/Max.
	local jitter = math.clamp(c.k22 or 0, 0, 50)
	local auto_ret = c.k18 ~= false
	local click_act = c.k19 ~= false

	local st = x6.pre and x6.pre["Raigo"]
	if not st then
		st = {
			phase = "HOVER",
			orb_pos = cen + Vector3.new(0, h_hover, 0),
			start_pos = cen + Vector3.new(0, h_hover, 0),
			dest_pos = nil,
			t_launch = 0,
			t_blast = 0,
			t_ret = 0,
			rot = 0,
			seed = 1,
			last_f = -1,
		}
		if x6.pre then
			x6.pre["Raigo"] = st
		end
	end

	-- Read by the input handler, which outlives a toggle change: the connections
	-- are made once and cannot be re-made, so the live value has to reach them
	-- through the state table rather than through the closure.
	st.click_enabled = click_act

	if not st.conns then
		st.conns = {}
		local ok = pcall(function()
			local uis = game:GetService("UserInputService")
			local cam = workspace.CurrentCamera
			st.conns[#st.conns + 1] = uis.InputBegan:Connect(function(inp, gpe)
				if gpe or not st.click_enabled or (x6.mobile_input and x6.mobile_input.active) then return end
				local hit = nil
				if inp.UserInputType == Enum.UserInputType.MouseButton1 then
					hit = get_cursor_world_hit(cam, uis, 1000)
				elseif inp.UserInputType == Enum.UserInputType.Touch then
					hit = get_touch_world_hit(cam, inp.Position, 1000)
				end
				if hit and (st.phase == "HOVER" or st.phase == "RETURN") then
					st.phase = "LAUNCH"
					st.start_pos = st.orb_pos
					st.dest_pos = hit
					st.t_launch = t
				end
			end)
		end)
		if not ok then
			st.conns = nil
		end
	end

	-- FORCE LAUNCH is a latch, not a pulse: the button's own label flips on it and
	-- Twin Core Beam and Slingshot read it as a held state. Consuming it here
	-- (x1.IsLaunching = false) fired Raigo once and then desynced the button, which
	-- still read "RESET SYSTEM", and stole the flag from every other reader. Edge
	-- detection belongs in this shape's own state.
	local mobile = x6.mobile_input
	if not (mobile and mobile.active and mobile.shape == "Raigo") then mobile = nil end
	local pressed = mobile and mobile.presses > 0
		and (mobile.generation ~= st.mobile_generation or mobile.presses ~= st.mobile_press)
	st.mobile_press = mobile and mobile.presses or nil
	st.mobile_generation = mobile and mobile.generation or nil
	local launching = x1.IsLaunching and true or false
	if (pressed or (launching and not st.last_launch)) and (st.phase == "HOVER" or st.phase == "RETURN") then
		local cam = workspace.CurrentCamera
		local uis = game:GetService("UserInputService")
		local hit = (mobile and mobile.aim) or get_cursor_world_hit(cam, uis, 800)
			or (cen + (cam and cam.CFrame.LookVector or Vector3.new(0, 0, 1)) * 150)
		st.phase = "LAUNCH"
		st.start_pos = st.orb_pos
		st.dest_pos = hit
		st.t_launch = t
	end
	st.last_launch = launching

	local cur_f = x6.f or 0
	if st.last_f ~= cur_f then
		st.last_f = cur_f
		st.seed = st.seed + 1
		st.rot = (st.rot + 0.08) % TAU
	end
	local seed = st.seed
	local rot = st.rot

	local head_pos = cen + Vector3.new(0, h_hover, 0)
	local blast_prog = 0
	local blast_ctr = st.dest_pos or head_pos

	if st.phase == "HOVER" then
		st.orb_pos = st.orb_pos:Lerp(head_pos, 0.15)
	elseif st.phase == "LAUNCH" then
		local dest = st.dest_pos or head_pos
		local total_dist = (dest - st.start_pos).Magnitude
		local flight_time = total_dist / v_flight
		local elapsed = t - st.t_launch
		local alpha = flight_time > 0 and math.clamp(elapsed / flight_time, 0, 1) or 1
		st.orb_pos = st.start_pos:Lerp(dest, alpha)
		if alpha >= 1 or (st.orb_pos - dest).Magnitude < 3 then
			st.phase = "EXPLODE"
			st.t_blast = t
			st.blast_origin = dest
		end
	elseif st.phase == "EXPLODE" then
		blast_ctr = st.blast_origin or st.orb_pos
		local elapsed = t - st.t_blast
		blast_prog = math.clamp(elapsed / dur_blast, 0, 1)
		st.orb_pos = blast_ctr
		if elapsed >= dur_blast then
			if auto_ret then
				st.phase = "RETURN"
				st.t_ret = t
				st.start_pos = blast_ctr
			else
				st.phase = "HOVER"
				st.orb_pos = head_pos
			end
		end
	elseif st.phase == "RETURN" then
		local elapsed = t - st.t_ret
		local ret_dist = (head_pos - st.start_pos).Magnitude
		local ret_time = math.max(0.3, ret_dist / (v_flight * 1.5))
		local alpha = math.clamp(elapsed / ret_time, 0, 1)
		local ease = alpha * alpha * (3 - 2 * alpha)
		st.orb_pos = st.start_pos:Lerp(head_pos, ease)
		if alpha >= 1 or (st.orb_pos - head_pos).Magnitude < 2 then
			st.phase = "HOVER"
			st.orb_pos = head_pos
		end
	end

	local id = d.slot or d.id or 1
	local total_pts = math.max(1, x6.n or 50)
	local orb_center = st.orb_pos

	local final_pos = nil
	-- One distribution for both phases: a solid ball. The blast is the same ball
	-- with an expanding radius. The three-way split that used to be here -- 55 % on
	-- a single shell, 30 % on lat/long "arcs", 15 % on tendrils running out to
	-- 1.8 R, each jittered by an amplitude one and a half times the radius -- is
	-- what made the idle form read as a hollow wisp with spikes instead of a ball.
	local u = (id * PSI) % 1

	if st.phase == "EXPLODE" then
		local exp_ease = 1 - (1 - blast_prog) * (1 - blast_prog)
		local cur_rad = r_orb + (r_blast - r_orb) * exp_ease
		final_pos = blast_ctr + ball_pt(id, total_pts, cur_rad, fill, u)
		-- Jitter fades as the shockwave opens, so the blast starts ragged and
		-- settles into a sphere rather than staying noisy at full radius.
		local amp = jitter * (1 - blast_prog)
		if amp > 0 then
			final_pos = final_pos
				+ Vector3.new(
					(2 * prng(seed, id, 1) - 1) * amp,
					(2 * prng(seed, id, 2) - 1) * amp,
					(2 * prng(seed, id, 3) - 1) * amp
				)
		end
	else
		final_pos = orb_center + spin_y(ball_pt(id, total_pts, r_orb, fill, u), math.cos(rot), math.sin(rot))
		if jitter > 0 then
			final_pos = final_pos
				+ Vector3.new(
					(2 * prng(seed, id, 4) - 1) * jitter,
					(2 * prng(seed, id, 5) - 1) * jitter,
					(2 * prng(seed, id, 6) - 1) * jitter
				)
		end

		if st.phase == "LAUNCH" then
			-- dest and start coincide when the orb is clicked where it already is.
			-- Vector3.zero.Unit is NaN in Roblox, and a NaN offset propagates into
			-- p.Position through the constraint, so the part is gone for good.
			local travel = (st.dest_pos or st.orb_pos) - st.start_pos
			if travel.Magnitude > 1e-3 then
				local trail_len = math.clamp(v_flight * 0.08, 5, 40)
				-- Weighted by the part's own radius fraction, so the ball draws out
				-- into a teardrop behind the direction of travel instead of every
				-- part smearing by the same amount.
				final_pos = final_pos - travel.Unit * (u * trail_len)
			end
		end
	end

	local delta = (final_pos - p.Position) * (x1.k10 * x9.c1)
	return delta, final_pos
end

function M.cleanup(x6, x1)
	if not x6 or not x6.pre then
		return
	end
	local st = x6.pre["Raigo"]
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
		st.click_enabled = false
	end
	x6.pre["Raigo"] = nil
end

M.Controls = {
	{ Type = "Slider", Name = "Orb Radius", Min = 2, Max = 40, Key = "k11", Default = 8 },
	{ Type = "Slider", Name = "Flight Speed", Min = 40, Max = 1200, Key = "k12", Default = 250 },
	{ Type = "Slider", Name = "Blast Radius", Min = 15, Max = 400, Key = "k13", Default = 80 },
	{ Type = "Slider", Name = "Blast Duration", Min = 2, Max = 30, Key = "k14", Default = 0.7, Div = 10 },
	{ Type = "Slider", Name = "Hover Height", Min = 3, Max = 50, Key = "k15", Default = 12 },
	{
		Type = "Slider",
		Name = "Shell Fill",
		Min = 0,
		Max = 100,
		Key = "k21",
		Default = 100,
		IntOnly = true,
		Desc = "100 is a solid ball. 0 puts every part on the surface.",
	},
	{
		Type = "Slider",
		Name = "Surface Jitter",
		Min = 0,
		Max = 50,
		Key = "k22",
		Default = 0,
		Desc = "Roughens the ball. 0 is an exact sphere.",
	},
	{ Type = "Toggle", Name = "Auto Recall", Key = "k18", Default = true },
	{ Type = "Toggle", Name = "Click To Fire", Key = "k19", Default = true },
}

return M
