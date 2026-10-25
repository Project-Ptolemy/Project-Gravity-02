local M = {}

function M.f2(p, cen, d, t, c, x1, x6, x9)
	local radius = c.k11 or 300
	local speed = c.k12 or 350
	local spacing = c.k13 or 3
	local cut_in_half = c.k18 ~= false

	local meta = x6.pre["Light Light no Mi"]
	if not meta then
		meta = {
			last_t = t,
			beams = {}
		}
		x6.pre["Light Light no Mi"] = meta
	end

	local delta_t = t - (meta.last_t or t)
	meta.last_t = t
	if delta_t <= 0 or delta_t > 0.1 then
		delta_t = 1 / 60
	end

	local active_items = x6.active_array
	local total_cnt = #active_items
	if total_cnt == 0 then
		return Vector3.zero, cen
	end

	local beam_count = math.clamp(math.floor(c.k14 or 2), 1, 20)

	if #meta.beams ~= beam_count then
		meta.beams = {}
		for b = 1, beam_count do
			local phi = (b / beam_count) * math.pi * 2
			local y_start = cut_in_half and (0.2 + (b / beam_count) * 0.7) or (1 - 2 * (b / beam_count))
			local r_start = math.sqrt(math.max(0.1, 1 - y_start * y_start))
			
			local init_pos = cen + Vector3.new(r_start * math.cos(phi) * (radius * 0.5), y_start * (radius * 0.5), r_start * math.sin(phi) * (radius * 0.5))
			local init_dir = Vector3.new(math.cos(phi * 3), cut_in_half and math.abs(math.sin(phi * 2)) or math.sin(phi * 2), math.sin(phi * 3)).Unit
			
			meta.beams[b] = {
				pos = init_pos,
				dir = init_dir,
				history = { init_pos, init_pos - init_dir * 10, init_pos - init_dir * 20 }
			}
		end
	end

	if not meta.updated_frame or meta.updated_frame ~= x6.f then
		meta.updated_frame = x6.f
		for b = 1, beam_count do
			local beam = meta.beams[b]
			if beam then
				local step_dist = speed * delta_t
				beam.pos = beam.pos + (beam.dir * step_dist)

				local rel = beam.pos - cen
				local cur_dist = rel.Magnitude
				local bounced = false

				if cur_dist >= radius then
					local norm = rel.Unit
					beam.dir = (beam.dir - norm * (2 * beam.dir:Dot(norm))).Unit
					beam.pos = cen + norm * (radius - 2)
					bounced = true
				end

				if cut_in_half and beam.pos.Y < cen.Y then
					beam.dir = Vector3.new(beam.dir.X, math.abs(beam.dir.Y) + 0.1, beam.dir.Z).Unit
					beam.pos = Vector3.new(beam.pos.X, cen.Y + 2, beam.pos.Z)
					bounced = true
				end

				local ceiling_y = cen.Y + radius
				if beam.pos.Y > ceiling_y then
					beam.dir = Vector3.new(beam.dir.X, -math.abs(beam.dir.Y) - 0.1, beam.dir.Z).Unit
					beam.pos = Vector3.new(beam.pos.X, ceiling_y - 2, beam.pos.Z)
					bounced = true
				end

				if bounced or (beam.history[1] and (beam.pos - beam.history[1]).Magnitude > 12) then
					table.insert(beam.history, 1, beam.pos)
					if #beam.history > 24 then
						table.remove(beam.history)
					end
				end
			end
		end
	end

	local item_idx = d.slot or d.id or 1
	local slot_idx = (item_idx - 1) % total_cnt
	local beam_idx = (slot_idx % beam_count) + 1
	local trail_idx = math.floor(slot_idx / beam_count) + 1

	local beam = meta.beams[beam_idx] or meta.beams[1]
	local target_pos

	if beam then
		local history = beam.history
		local hist_len = #history
		if trail_idx <= hist_len then
			target_pos = history[trail_idx]
		else
			local last_pt = history[hist_len] or beam.pos
			target_pos = last_pt - (beam.dir * ((trail_idx - hist_len) * spacing * 3))
		end
	else
		target_pos = cen
	end

	if cut_in_half and target_pos.Y < cen.Y then
		target_pos = Vector3.new(target_pos.X, cen.Y + math.abs(target_pos.Y - cen.Y), target_pos.Z)
	end

	local ceiling_y = cen.Y + radius
	if target_pos.Y > ceiling_y then
		target_pos = Vector3.new(target_pos.X, ceiling_y - math.abs(target_pos.Y - ceiling_y), target_pos.Z)
	end

	return (target_pos - p.Position) * (x1.k10 * x9.c1), target_pos
end

M.Controls = {
	{ Type = "Slider", Name = "Containment Radius", Min = 25, Max = 800, Key = "k11", Default = 150 },
	{ Type = "Slider", Name = "Light Speed", Min = 50, Max = 1000, Key = "k12", ExactMax = true },
	{ Type = "Slider", Name = "Beam Count", Min = 1, Max = 20, Key = "k14", Default = 2, IntOnly = true },
	{ Type = "Slider", Name = "Beam Spacing", Min = 1, Max = 20, Key = "k13" },
	{ Type = "Toggle", Name = "Cut in Half", Key = "k18", Default = true }
}

-- Beam positions and histories live in x6.pre, which survives a shape switch;
-- a stale meta resumes the beams from an old position and last_t.
function M.cleanup(x6, x1)
	if not x6.pre then
		return
	end
	x6.pre["Light Light no Mi"] = nil
end

return M
