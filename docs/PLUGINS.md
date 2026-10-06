# Shape plugin guide

[Website homepage](../index.html) · [Website guide](plugins/index.html) · [Full LLM prompt](plugins/plugin-prompt.txt) · [Starter module](plugins/starter.lua)

Save a module as `GravityShapes/<Shape Name>.lua` in your executor's workspace and run Project Gravity again. Local plugins appear in the shape selector. The **PROJECT UAI** button launches [Project UAI](https://github.com/CarlDV/ProjectUAI) on demand; you can also take the prompt above to another AI.

## Module contract

```lua
local M = {}
local NAME = "My Shape"

function M.px(t, c, x6, x9, x1) -- optional, once per formation frame
    x6.pre = x6.pre or {}
    x6.pre[NAME] = x6.pre[NAME] or {}
end

function M.f2(p, cen, d, t, c, x1, x6, x9)
    local target = cen + Vector3.new(0, 20, 0)
    return (target - p.Position) * (x1.k10 * x9.c1), target
end

function M.cleanup(x6, x1)
    if x6.pre then x6.pre[NAME] = nil end
end

M.Controls = {}
return M
```

| Argument | Meaning |
| --- | --- |
| `p` | The held BasePart. |
| `cen` | Current center, including target/anchor movement. |
| `d` | Persistent per-part record; use a named subtable for private data. |
| `t` | Formation time, which can pause, slow down or reverse. |
| `c` | This shape's settings, indexed by control Key. |
| `x1` | Global engine settings, including pull gain k10. |
| `x6` | Runtime state: pre, held parts, mobile input and motion offset. |
| `x9` | Runtime constants, including feedback multiplier c1. |

The first result is a **velocity correction**; the second is the **exact target position** used for tracking. Avoid arbitrary huge multipliers. Cache frame-wide calculations in `px`; derive center-dependent positions in `f2`, since `px` does not receive `cen`.

Use `d.slot or d.id or 1` for stable placement and `d.slot_n` for an optional sorted slot count. Parts arrive late and may only be processed every few frames. Timed actions should subtract a captured shared timestamp instead of adding one frame's delta on every `f2` call. `d.claim_t` is wall time, so do not subtract it from scaled `t`.

Own one namespaced `x6.pre[NAME]` entry and remove it in cleanup. Give private per-part records an owner reference to that shared state so a fresh state invalidates old records on re-entry. Cleanup can run more than once, including during failed initialization.

## Controls, including real buttons

| Type | Required fields | Optional fields / defaults |
| --- | --- | --- |
| Slider | Name, Key, Min, Max | Default, Div, IntOnly, ExactMax, Desc |
| Toggle | Name, Key | Boolean Default (otherwise false), Desc |
| TextBox | Name, Key | String Default (otherwise empty), MaxChars, Desc |
| Button | Name, Callback | Optional stable Key; no saved value |

```lua
{ Type = "Button", Name = "Regrab", Key = "regrab", Callback = function(c, x6, x1)
    local st = x6.pre and x6.pre[NAME]
    if st then st.generation = (st.generation or 0) + 1 end
end }
```

Each click/tap runs the callback once. Building or refreshing the panel never invokes it. Buttons do not create entries in `c` or saved settings. Use them for actions, and Toggles for persistent on/off preferences. Callbacks should finish quickly without yielding; errors are contained and reported, and a second click cannot duplicate an in-progress callback.

Slider Min/Max are in display units; Default is already in stored units. For `Div = 10, Default = 1.6`, the panel displays **16** and the shape reads **1.6**. IntOnly rounds the display. A label containing “speed” extends its maximum by 300 unless `ExactMax = true`. Clamp your math to its supported range. Built-in modules need matching non-button defaults in config.lua; local imports use Controls.

## Natural release and impulses

The engine applies these optional requests after f2 on desktop and mobile:

| Request | Result |
| --- | --- |
| `d.free_physics = true` | Disable both actuators and restore physical properties; retain the record for Regrab. |
| `d.free_physics = nil` | Resume control and clear stale tracking. |
| `d.launch_velocity = velocity` | With free physics, apply one impulse and consume this field. |
| `d.angular_velocity = Vector3.new(x, y, z)` | Set the held part's angular motor in world-space radians/second. Clear to nil for normal behavior. Pause stops it; release disables it. |
| `d.collisions = false / true / nil` | Noclip / original collision setting / engine policy. Free parts normally use original collisions. Preserve Collisions or Disabled always restores the original value, overriding this request. |
| `d.unclaim = true` | Restore properties, remove actuators and forget the record. Defaults to zero release velocity. |
| `d.keep_velocity = true` | Preserve current velocity when unclaiming. |
| `d.release_velocity`, `d.release_spin` | Explicit unclaim velocities; use these instead of keep_velocity. |

Let Roblox simulate gravity after release. Do not keep LinearVelocity active and manually subtract gravity each frame. For an immediate button action, set request fields on a tracked real record and call `x6.apply_shape_physics(p, d)` if available. Normal f2 calls do not need this helper. Leave Part Control overrides (`d.pc_mode`) alone.

`M.NoBlend = true` opts interactive or physics-mutating modules out of blending. `M.AlwaysProcess = true` bypasses distance culling but retains processing buckets. `M.ContinuousMotion = true` supplies a shared real-time `x6.motion_offset`; add it to the target to keep a frozen pose drifting.

`M.FrameTracking = true` evaluates every held part each physics frame and follows its target through the velocity constraint, with global/per-part speed limits. It bypasses ordinary smoothing and integral feedback. Damping softens correction after a displacement while preserving the target's own motion, with consistent recovery across frame rates. Use it with `M.NoBlend = true`, continuous targets and capture from each part's live position; it costs a full part sweep each frame. Cache shared geometry in `px` as Black Hole v2 does. Release, collision policy and pause still apply normally.

## Circular mobile controls

```lua
M.MobileControls = { Action = "FIRE", Range = 600 }
local input = x6.mobile_input -- read inside px or f2
if input and input.active and input.shape == NAME then
    -- input.direction: unit world direction
    -- input.aim: world point; input.base_aim: camera-forward point
    -- input.x / input.y: normalized stick axes
    -- input.yaw / input.pitch: accumulated steering angles in radians
    -- input.held: the action finger is held
    -- input.presses: counter for edge-triggered actions
    -- input.generation: changes whenever the input resets
end
```

Opting in displays a circular stick and separate action button; the shape must read their state to use them. One finger steers while another holds the action. Lifting or canceling either finger only releases its own control. Steering stays where you leave it. Focus loss cancels gestures; stop, pause, disable, shape changes and unload reset the input. Edge-detect actions using both `generation` and `presses`: the counter resets, but generation advances even when shape processing is paused.

```lua
local pressed = input.presses > 0
    and (st.input_generation ~= input.generation or st.input_presses ~= input.presses)
st.input_generation, st.input_presses = input.generation, input.presses
if pressed then -- trigger one action here
end
```

Broom uses the stick to sweep/tilt and **EXTEND** to extend the handle. Twin Core Beam and Goro use **FIRE**; Raigo uses **LAUNCH**. Goro's Hold To Fire setting still determines whether it fires continuously. Automatic formations hide this control. Touch-capable desktops switch back to mouse controls when using the mouse. Keep a desktop fallback and ignore raw touch listeners while the shared interface is active.

## Stop, reset and unload

**Q** stops/resets: release parts and remove the core, leaving the UI and bindings available to restart. **The main UI X fully unloads Project Gravity**: unbind actions, disconnect listeners, remove the core/UI and restore captured properties. Minimizing keeps the session running.

Plugins must disconnect owned connections and destroy owned instances in cleanup. Restore properties you changed and clear only your own state. Do not delete unrelated objects by a name search. A failed plugin cleanup does not prevent the engine from releasing the remaining parts.

## Updated shapes

- **Black Hole v2:** every part follows a tightening spiral into a filled sphere by default, then joins its own tilted orbit with shared precession for Dense Spin style motion. **Pull In Speed** controls the inward rate in nominal studs/second (default 60); **Spiral Speed** controls the incoming swirl (default 14). **Ball Spin Speed (deg/s)** defaults to 720, with a maximum of 1,440. The core uses positional motion without forcing each piece's angular motor to spin. Large spheres limit their combined orbital speed to fit the global Max Speed. **Ball Radius** eases size changes without a jump. Pull speed changes preserve progress; zero holds the current spiral radius. The optional accretion ring starts at zero. Held parts follow Preserve Collisions, and Explosion Noclip applies only while exploding. Regrab/Stop/Explode buttons recapture, release, or apply one outward impulse followed by gravity.
- **Storm Gyre:** bounded waves make the lightning branches crackle without teleporting whole strikes.
- **Alien Mothership:** the tractor beam begins at the underside emitter, with continuous local motion instead of full-length position wraps.
- **Phoenix Ascendant:** a smooth 3D flight path with a leading head, bending body, trailing tail and wingbeats that travel through the feathers. Body Follow Through and Wing Flex tune the response.
- **Megalodon:** a 3D patrol with swoops, tangent-aligned heading, banking and a body that bends into turns. Patrol Swoop Height, Turn Banking and Body Follow Through tune the route.
- **Drop (archive):** gathers a canopy of debris, holds it, then releases a staggered wave. Height, spread, scatter and momentum are configurable. Import shapes-onreview/Drop.lua as a local plugin; it remains in the archive/review folder.

[Watch the creature paths](plugins/creatures-motion.gif) · [Watch Black Hole v2 and Drop](plugins/release-motion.gif)

The clips use 512 mixed pieces and fixed cameras. Controlled positions follow module targets; released pieces use a simple gravity/floor fixture. The Black Hole v2 demo uses Pull In Speed 60 and Explosion Force 70, with a scripted explosion at 3.8 seconds and Regrab at 4.8 seconds. Materials and part orientations are illustrative; constraints, collisions and network ownership are not simulated.

## Validation

Use the standalone [Luau CLI](https://github.com/luau-lang/luau/releases) with Python:

```powershell
python tools/test_luau.py --luau PATH_TO_LUAU tests/plugin_actions.lua
python tools/test_luau.py --luau PATH_TO_LUAU tests/black_hole_motion.lua
python tools/test_luau.py --luau PATH_TO_LUAU tests/mobile_controls.lua
python tools/test_luau.py --luau PATH_TO_LUAU tests/session_lifecycle.lua
python tools/test_luau.py --luau PATH_TO_LUAU tests/insane_shapes_smoke.lua
```

The black hole motion suite checks a 512-part sphere and integrates the real desktop/mobile velocity loops at 30, 60 and 144 Hz with a moving center. These are offline fixtures; live Roblox contacts and network ownership still need an in-game check.

## Publish the website

The website entry point is **`/index.html` at the repository root**. The plugin
guide remains at `/docs/plugins/`, and the builder at `/docs/plugins/builder/`.
All three are ordinary static pages; the homepage does not redirect to the guide.

Connect the repository to **Cloudflare Pages** using Git integration. Select the
branch you want to publish and use these build settings:

| Setting | Value |
| --- | --- |
| Framework preset | None |
| Build command | `exit 0` |
| Build output directory | `.` (the repository root) |
| Root directory | Leave unset (the repository root) |

There are no packages to install or application build steps. Keep `index.html`,
`assets/`, and `docs/plugins/` in their current relative locations. Do not set
`docs/plugins` as the build output directory: that would make the guide the home
page and break the new navigation. Cloudflare handles deployment when the
connected branch is pushed; these instructions do not publish the site.

Before pushing, check the documentation and serve the repository root locally:

```powershell
python tools/sync_plugin_docs.py --check
node tests/plugin_docs.test.js
python -m http.server 8000 --bind 127.0.0.1
```

Visit `http://127.0.0.1:8000/`, `/docs/plugins/`, and `/docs/plugins/builder/`.
After Cloudflare deploys, the selected domain uses those same paths.
