local M = {}

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local wp = p.Position
	local Spread = c.k11 or 400
	local SpinSpeed = (c.k12 or 2) * x9.c2
	local DriftTime = c.k13 or 1

	-- Each part gets its own random axis so the web scatters in 3D instead of
	-- orbiting as one flat disc. The calm comes from low speeds, not shared axes.
	if not d.rot_axis then
		local rx, ry, rz = math.random() - 0.5, math.random() - 0.5, math.random() - 0.5
		local len = math.sqrt(rx * rx + ry * ry + rz * rz)
		if len == 0 then
			rx, ry, rz, len = 0, 1, 0, 1
		end
		d.rot_axis = Vector3.new(rx / len, ry / len, rz / len)
	end

	if not d.v1 then
		d.v1 = (math.random() - 0.5) * 2
	end
	if not d.v2 then
		d.v2 = (math.random() - 0.5) * 2
	end
	if not d.v3 then
		d.v3 = (math.random() - 0.5) * 2
	end
	if not d.v4 then
		d.v4 = math.random() * math.pi * 2
	end
	if not d.v5 then
		d.v5 = (math.random() - 0.5) * 2
	end

	local dt = t - (d.last_t or t)
	d.last_t = t
	d.phase = (d.phase or 0) + (dt * SpinSpeed)
	d.phase2 = (d.phase2 or 0) + (dt * DriftTime)
	local phase = d.phase + d.v4
	local drift_phase = d.phase2 + d.v4

	local px = d.v1 * Spread
	local py = d.v2 * Spread
	local pz = d.v3 * Spread

	local p_vec = Vector3.new(px, py, pz)
	local k = d.rot_axis
	local cos_p = math.cos(phase)
	local sin_p = math.sin(phase)

	local cross = k:Cross(p_vec)
	local dot = k:Dot(p_vec)
	local rotated = p_vec * cos_p + cross * sin_p + k * (dot * (1 - cos_p))

	-- Slow, small drift so the web breathes instead of shaking.
	local drift_scale = Spread * 0.08
	local drift_x = math.sin(drift_phase) * d.v5 * drift_scale
	local drift_y = math.cos(drift_phase * 0.8) * d.v5 * drift_scale
	local drift_z = math.sin(drift_phase * 1.2) * d.v5 * drift_scale

	local rx = rotated.X + drift_x
	local rz = rotated.Z + drift_z

	local h_lim = c.k24 or 200
	local vertical_scale = h_lim / math.max(1, Spread)
	local final_y = rotated.Y * vertical_scale + drift_y

	if c.k23 then
		final_y = math.abs(final_y)
	end

	local target_pos = cen + Vector3.new(rx, final_y, rz)
	return (target_pos - wp) * (x1.k10 * x9.c1), target_pos
end

M.Controls = {
	{ Type = "Slider", Name = "Radius Spread", Min = 50, Max = 1500, Key = "k11", Default = 400 },
	{ Type = "Slider", Name = "Spin Speed", Min = 0, Max = 20, Key = "k12", Div = 10, Default = 10 },
	{ Type = "Slider", Name = "Drift Speed", Min = 0, Max = 10, Key = "k13", Default = 5 },
	{ Type = "Slider", Name = "Web Height Limit", Min = 0, Max = 1500, Key = "k24", Default = 200 },
	{ Type = "Toggle", Name = "Cut In Half", Key = "k23", Default = false }
}



return M
