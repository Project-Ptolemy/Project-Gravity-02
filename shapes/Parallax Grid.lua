-- An immense checkerboard folds into a traveling upright wave, including its rails.
local M = { ContinuousMotion = true, AlwaysProcess = true }
local NAME = "Parallax Grid"
local TAU = math.pi * 2
local PHI = 0.6180339887498949

function M.px(t, c, x6, x9)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then st = { phase = 0, t = t }; x6.pre[NAME] = st end
    st.phase = st.phase + (t - st.t) * math.clamp(c.k13 or 18, 0, 60) * x9.c2
    st.t = t
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local slot = d.slot or d.id or 1
    local u, v = (slot * PHI) % 1, (slot * 0.8191725133961645) % 1
    local st = x6.pre and x6.pre[NAME]
    local phase = st and st.phase or 0
    local span = math.clamp(c.k11 or 880, 400, 1400)
    local fold = math.clamp(c.k12 or 310, 60, 550)
    local cells = math.clamp(math.floor(c.k14 or 6), 4, 10)
    local railWidth = math.clamp(c.k15 or 12, 2, 35)
    local base = math.clamp(c.k16 or 20, -100, 250)
    local x, z
    if slot % 10 < 7 then
        local line = math.floor((slot - 1) / 10) % ((cells + 1) * 2)
        local q = (1 - math.cos(u * TAU + phase * 0.22)) * 0.5
        if line <= cells then
            x, z = (line / cells - 0.5) * span, (q - 0.5) * span
        else
            x, z = (q - 0.5) * span, ((line - cells - 1) / cells - 0.5) * span
        end
        local offset = (v - 0.5) * railWidth
        if line <= cells then x = x + offset else z = z + offset end
    else
        -- Diagonal fill occurs only in alternating squares, preserving open cells.
        local square = math.floor((slot - 1) / 10) % math.ceil(cells * cells / 2)
        local row, column
        if cells % 2 == 0 then
            row = math.floor(square / (cells / 2))
            column = (square % (cells / 2)) * 2 + row % 2
        else
            row, column = math.floor(square * 2 / cells), (square * 2) % cells
        end
        local q = (1 - math.cos(u * TAU + phase * 0.32)) * 0.5
        x = ((column + q) / cells - 0.5) * span
        z = ((row + q) / cells - 0.5) * span
    end
    local a = z / span * TAU - phase * 0.7
    local crest = (1 + math.sin(a)) * 0.5
    local y = base + fold * crest ^ 3
    -- The compressed leading face and extended trailing face visibly fold the grid.
    z = z + fold * 0.43 * math.cos(a)
    x = x + span * 0.045 * math.sin(a) * math.sin(x / span * math.pi)
    local target = cen + Vector3.new(x, y, z)
    if x6.motion_offset then target = target + x6.motion_offset end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {
    { Type = "Slider", Name = "Grid Span", Min = 400, Max = 1400, Key = "k11", Default = 880 },
    { Type = "Slider", Name = "Traveling Fold", Min = 60, Max = 550, Key = "k12", Default = 310 },
    { Type = "Slider", Name = "Fold Speed", Min = 0, Max = 60, Key = "k13", Default = 18, ExactMax = true },
    { Type = "Slider", Name = "Grid Cells", Min = 4, Max = 10, Key = "k14", Default = 6, IntOnly = true },
    { Type = "Slider", Name = "Rail Width", Min = 2, Max = 35, Key = "k15", Default = 12 },
    { Type = "Slider", Name = "Grid Height", Min = -100, Max = 250, Key = "k16", Default = 20 },
}

return M
