-- Capture, spiral inward, and pack the parts into a densely churning ball.
-- Released parts have no active actuators.
local M = { AlwaysProcess = true, NoBlend = true, FrameTracking = true }
local NAME = "Black Hole v2"
local TAU = math.pi * 2
local UP = Vector3.new(0, 1, 0)
local PRECESSION = 0.6

local function state(x6)
    x6.pre = x6.pre or {}
    local st = x6.pre[NAME]
    if not st then
        st = { clock = 0, pull_distance = 0, spiral_distance = 0, ball_angle = 0, ball_spin = 0,
            ball_cos = 1, ball_sin = 0, precession_cos = 1, precession_sin = 0,
            state = "grab", gen = 0, explosion = 0 }
        x6.pre[NAME] = st
    end
    return st
end

local function seed(d, st)
    local r = d.black_hole_v2
    if not r or r.owner ~= st then
        local id = d.slot or d.id or 1
        local y = 2 * ((id * 0.8191725133961645) % 1) - 1
        local a = TAU * ((id * 0.5698402909980532) % 1)
        local flat = math.sqrt(math.max(0, 1 - y * y))
        local hy = 2 * ((id * 0.7548776662466927) % 1) - 1
        local ha = TAU * ((id * 0.4142135623730951) % 1)
        local hf = math.sqrt(math.max(0, 1 - hy * hy))
        r = {
            owner = st, roll = (id * 0.6180339887498949) % 1,
            phase = a, dir = Vector3.new(math.cos(a) * flat, y, math.sin(a) * flat),
            rad = ((id * 0.438579021) % 1) ^ (1 / 3),
            orbit_hint = Vector3.new(math.cos(ha) * hf, hy, math.sin(ha) * hf),
        }
        d.black_hole_v2 = r
    end
    return r
end

local function explode(p, cen, d, r, st, c)
    d.free_physics = true
    d.angular_velocity = nil
    d.collisions = c.rwNoclip == false
    if r.explosion ~= st.explosion then
        r.explosion = st.explosion
        local away = p.Position - cen
        away = away.Magnitude > 0.5 and away.Unit or r.dir
        local dir = away + r.dir * 0.22 + UP * 0.12
        local speed = math.clamp(c.rwForce or 400, 50, 1500) * (0.75 + r.roll * 0.5)
        d.launch_velocity = dir.Unit * speed
    end
end

local function command(action)
    return function(c, x6, x1)
        local st = state(x6)
        st.state = action
        if action == "grab" then st.gen = st.gen + 1 end
        if action == "explode" then
            st.explosion = st.explosion + 1
            st.explode_at = st.clock
        end
        -- Release also works while paused. The engine owns the actuators;
        -- preview markers never enter this table.
        for p, d in pairs(x6.a or {}) do
            if not d.pc_mode then
                if action == "release" then
                    d.free_physics, d.collisions, d.launch_velocity = true, nil, nil
                    d.angular_velocity = nil
                elseif action == "explode" then
                    local r = seed(d, st)
                    local cen = r.center or (x6.b and x6.b.Position) or p.Position
                    explode(p, cen, d, r, st, c)
                end
                if action ~= "grab" and x6.apply_shape_physics then
                    pcall(x6.apply_shape_physics, p, d)
                end
            end
        end
    end
end

function M.px(t, c, x6, x9, x1)
    local st = state(x6)
    local dt = st.last_t and math.clamp(t - st.last_t, -0.25, 0.25) or 0
    st.last_t = t
    st.clock = st.clock + math.abs(dt)
    -- Shrinking the core or changing its tilt should reshape the flow, not jump
    -- every target. These are shared so all parts see the same geometry.
    local alpha = 1 - math.exp(-math.abs(dt) * 8)
    local ball = math.clamp(c.rwBall or 12, 0, 70)
    local tilt = math.rad(math.clamp(c.rwTilt or 25, 0, 80))
    local width = math.clamp(c.rwRingWidth or 3, 0, 20)
    st.ball = st.ball and st.ball + (ball - st.ball) * alpha or ball
    st.tilt = st.tilt and st.tilt + (tilt - st.tilt) * alpha or tilt
    st.width = st.width and st.width + (width - st.width) * alpha or width
    st.pull_distance = st.pull_distance + math.max(dt, 0) * math.clamp(c.rwPull or 60, 0, 400)
    st.spiral_distance = st.spiral_distance + dt * math.clamp(c.rwSpin or 14, 0, 30) * 12
    st.ball_spin = math.rad(math.clamp(c.rwBallSpin or 720, 0, 1440))
    -- Each particle has its own tilted orbit, plus a shared precession like
    -- Dense Spin. Bound their combined speed and leave room for center motion.
    local scale = math.abs(x1 and x1.TimeScale or 1)
    local limit = x1 and x1.MaxSpeed or 500
    if limit > 0 and scale > 0 then
        st.ball_spin = math.min(st.ball_spin, limit * 0.75 / math.max(st.ball, 1) / scale / (1 + PRECESSION))
    end
    -- Unwrapped shared integrals let even a skipped part consume the entire
    -- interval. Updating a speed slider never rewrites an existing phase.
    st.ball_angle = st.ball_angle + st.ball_spin * dt
    st.ball_cos, st.ball_sin = math.cos(st.ball_angle % TAU), math.sin(st.ball_angle % TAU)
    local precession = (st.ball_angle * PRECESSION) % TAU
    st.precession_cos, st.precession_sin = math.cos(precession), math.sin(precession)
    if st.state == "explode" and st.clock - st.explode_at >= math.clamp(c.rwExplodeTime or 1.6, 0, 5) then
        -- Restore collisions even for a bucketed part whose ownership changed.
        command("release")(c, x6, x1)
    end
end

local function smooth(s) return s * s * s * (s * (s * 6 - 15) + 10) end

local function core_weight(s)
    return smooth(math.clamp((s - 0.5) * 2, 0, 1))
end

local function rotate_disc(v, tilt)
    local cs, sn = math.cos(tilt), math.sin(tilt)
    return Vector3.new(v.X, v.Y * cs - v.Z * sn, v.Y * sn + v.Z * cs)
end

local function core_target(r, st, cen, ball)
    -- No per-part trigonometry, normalization, or angular-motor writes in the
    -- settled hot path. Independent orbit planes keep the center moving in 3D.
    local a, b, cs, sn = r.core, r.tangent, st.ball_cos, st.ball_sin
    local vx, vy, vz = a.X * cs + b.X * sn, a.Y * cs + b.Y * sn, a.Z * cs + b.Z * sn
    local pc, ps = st.precession_cos, st.precession_sin
    return cen + Vector3.new(vx * pc + vz * ps, vy, -vx * ps + vz * pc) * ball
end

local function settle(r, angle)
    -- Anchor the new orbit at the exact arrival phase, even when a bucketed
    -- evaluation spans that moment. Capturing the live phase avoids a slot snap.
    local pc, ps = math.cos(angle * PRECESSION), math.sin(angle * PRECESSION)
    local flat = math.sqrt(math.max(0, 1 - r.dir.Y * r.dir.Y))
    local vx, vy, vz = math.cos(r.angle) * flat, r.dir.Y, -math.sin(r.angle) * flat
    local radial = Vector3.new(vx * pc - vz * ps, vy, vx * ps + vz * pc)
    local tangent = r.orbit_hint - radial * r.orbit_hint:Dot(radial)
    if tangent:Dot(tangent) < 1e-8 then
        tangent = radial:Cross(math.abs(radial.Y) < 0.9 and UP or Vector3.new(1, 0, 0))
    end
    tangent = tangent.Unit * r.rad
    radial = radial * r.rad
    local cs, sn = math.cos(angle), math.sin(angle)
    r.core = radial * cs - tangent * sn
    r.tangent = radial * sn + tangent * cs
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local st = state(x6)
    local r = seed(d, st)
    r.center = cen
    if st.state == "release" then
        d.free_physics, d.collisions = true, nil
        d.angular_velocity = nil
        return p.AssemblyLinearVelocity, p.Position
    elseif st.state == "explode" then
        explode(p, cen, d, r, st, c)
        return d.launch_velocity or p.AssemblyLinearVelocity, p.Position
    end
    d.free_physics, d.launch_velocity = nil, nil
    -- Gathering follows the global collision policy. Noclip is an explosion
    -- option; disabling it must never re-enable contacts throughout the core.
    d.collisions, d.angular_velocity = nil, nil
    local ball = st.ball or math.clamp(c.rwBall or 12, 0, 70)
    local tilt = st.tilt or math.rad(math.clamp(c.rwTilt or 25, 0, 80))
    local width = st.width or math.clamp(c.rwRingWidth or 3, 0, 20)
    local role = r.roll < math.clamp((c.rwRing or 0) / 100, 0, 0.6) and 1 or 0
    if r.gen ~= st.gen or r.role ~= role then
        r.gen, r.role = st.gen, role
        r.core = nil
        r.pull_start = st.pull_distance
        r.pull_last = st.pull_distance
        -- Capture in the tilted disc's frame so even a part directly above the
        -- center starts at its actual position, with no teleport or zero basis.
        local off = rotate_disc(p.Position - cen, -tilt)
        r.distance = off.Magnitude
        r.duration_distance = math.max(r.distance, ball, 1)
        r.latitude = r.distance > 1e-6 and math.asin(math.clamp(off.Y / r.distance, -1, 1)) or 0
        r.angle = math.atan2(-off.Z, off.X)
        r.progress, r.spiral_start, r.ball_start = 0, st.spiral_distance, st.ball_angle
    end
    local s = math.clamp((st.pull_distance - r.pull_start) / r.duration_distance, 0, 1)
    if r.core then
        r.angle = r.angle + st.ball_angle - r.ball_start
        r.ball_start, r.spiral_start = st.ball_angle, st.spiral_distance
        local target = core_target(r, st, cen, ball)
        return (target - p.Position) * (x1.k10 * x9.c1), target
    end
    local pull = smooth(s)
    local bw = core_weight(s)
    local final_radius = ball * r.rad
    local final_latitude = math.asin(r.dir.Y)
    if role == 1 then
        local ring_radius = math.max(ball * 2.5 + 4 + r.dir.X * width, ball + 2)
        local ring_height = r.dir.Y * width * 0.35
        final_radius = math.sqrt(ring_radius * ring_radius + ring_height * ring_height)
        final_latitude = math.atan2(ring_height, ring_radius)
    end

    -- Integrate a single, consistently directed orbit. Tangential speed is
    -- roughly constant outside the horizon, so turns tighten as radius shrinks.
    -- Subdivide progress, not render frames, to handle sparse updates as well.
    local previous = r.progress
    local ball_angle, spiral_distance = st.ball_angle, st.spiral_distance
    if role == 0 and s >= 1 and st.pull_distance > r.pull_last then
        local fraction = math.clamp((r.pull_start + r.duration_distance - r.pull_last)
            / (st.pull_distance - r.pull_last), 0, 1)
        ball_angle = r.ball_start + (ball_angle - r.ball_start) * fraction
        spiral_distance = r.spiral_start + (spiral_distance - r.spiral_start) * fraction
    end
    local steps = math.max(1, math.ceil(math.abs(s - previous) * 64))
    local spiral_step = (spiral_distance - r.spiral_start) / steps
    local ball_step = (ball_angle - r.ball_start) / steps
    for i = 1, steps do
        local mid = previous + (s - previous) * ((i - 0.5) / steps)
        local radius = r.distance + (final_radius - r.distance) * smooth(mid)
        local lock = role == 0 and core_weight(mid) or 0
        r.angle = r.angle + spiral_step / math.max(radius, ball, 4) * (1 - lock) + ball_step * lock
    end
    -- Spread arrivals around their orbits even when a pile of debris starts at
    -- one position. This changes angle only; a part never cuts through the core
    -- on a chord to reach an unrelated slot on the other side of the sphere.
    r.angle = r.angle + r.phase * (pull - smooth(previous))
    r.progress, r.spiral_start, r.ball_start = s, st.spiral_distance, st.ball_angle
    r.pull_last = st.pull_distance

    local radius = r.distance + (final_radius - r.distance) * pull
    local flatten = smooth(math.clamp(s / 0.5, 0, 1))
    local latitude = r.latitude * (1 - flatten) + final_latitude * bw
    local horizontal = math.cos(latitude) * radius
    local offset = Vector3.new(math.cos(r.angle) * horizontal, math.sin(latitude) * radius,
        -math.sin(r.angle) * horizontal)
    -- Untilt the inlet before each part joins its own dense core orbit.
    offset = rotate_disc(offset, tilt * (role == 0 and (1 - bw) or 1))
    local target = cen + offset
    if role == 0 and s >= 1 then
        settle(r, ball_angle)
        target = core_target(r, st, cen, ball)
    end
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

M.Controls = {
    { Type = "Button", Name = "Regrab All Parts", Key = "rwRegrab", Callback = command("grab") },
    { Type = "Button", Name = "Stop Grabbing", Key = "rwRelease", Callback = command("release") },
    { Type = "Button", Name = "Explode", Key = "rwExplode", Callback = command("explode") },
    { Type = "Toggle", Name = "Explosion Noclip", Key = "rwNoclip", Default = true,
        Desc = "Suppress contacts during the explosion interval unless Preserve Collisions is enabled. Gathering uses the global collision setting." },
    { Type = "Slider", Name = "Pull In Speed", Min = 0, Max = 400, Key = "rwPull", Default = 60, ExactMax = true,
        Desc = "Nominal studs per second toward the core, with a smooth arrival. Zero holds the current spiral radius." },
    { Type = "Slider", Name = "Spiral Speed", Min = 0, Max = 30, Key = "rwSpin", Default = 14, ExactMax = true,
        Desc = "Speed of the incoming swirl. Parts turn faster as they approach the sphere." },
    { Type = "Slider", Name = "Ball Spin Speed (deg/s)", Min = 0, Max = 1440, Key = "rwBallSpin", Default = 720, IntOnly = true, ExactMax = true,
        Desc = "Dense motion through independent tilted orbits. Large spheres respect the global Max Speed limit." },
    { Type = "Slider", Name = "Ball Radius", Min = 0, Max = 70, Key = "rwBall", Default = 12,
        Desc = "Radius of the packed sphere. Zero draws every part all the way to the center." },
    { Type = "Slider", Name = "Accretion Ring %", Min = 0, Max = 60, Key = "rwRing", Default = 0, IntOnly = true,
        Desc = "Fraction of parts that form a flat orbiting ring instead of joining the ball." },
    { Type = "Slider", Name = "Ring Width", Min = 0, Max = 20, Key = "rwRingWidth", Default = 3 },
    { Type = "Slider", Name = "Disc Tilt", Min = 0, Max = 80, Key = "rwTilt", Default = 25,
        Desc = "Tilt of the incoming spiral and optional ring. The core spins through all three dimensions." },
    { Type = "Slider", Name = "Explosion Force", Min = 50, Max = 1500, Key = "rwForce", Default = 400, IntOnly = true },
    { Type = "Slider", Name = "Explosion Noclip Time", Min = 0, Max = 50, Div = 10, Key = "rwExplodeTime", Default = 1.6 },
}

function M.cleanup(x6)
    if x6.pre then x6.pre[NAME] = nil end
end

return M
