# Changelog

## September 29, 2026 - 42 new moving formations

- Add Tsunami's twin curling breakers and Killer's rapid converging rubble volleys from the recommendations sketches.
- Add Cataclysm Dragon, Thunderbird, Abyssal Maw, Dreadnought, Titan Stampede, Rift Reaper, Extinction Comet, Faultline, Eruption and Oblivion Drill.
- Give each formation seven controls, large defaults, active travel, deterministic debris slots, reversible animation and isolated cleanup. Register all twelve for desktop and mobile.
- Use frame tracking and a speed-budgeted animation clock for Killer's fast passes.
- Add thirty more distinct vast formations: branching networks, crossing highways, folding grids, rolling machinery, moving fortifications, tectonic plates and broad disaster fields. Each has five to seven controls; the full set is documented in docs/VAST.md.
- Add mixed-debris previews, sparse galleries and geometry/runtime regression checks. Update the preview catalog for all 117 active shapes and four review modules.

## September 28, 2026 - Effects and physics controls

- Raise Goro Goro no Mi's Flicker Rate slider and runtime limit from 60 to 300.
- Animate Storm Gyre lightning with bounded crackle waves, and keep Alien Mothership's tractor beam attached to its hull without full-length target wraps.
- Change Black Hole v2's core to crossing, tilted orbits inspired by Dense Spin. Cache shared rotation and remove forced per-piece angular spin.
- Make held Black Hole debris follow Preserve Collisions independently of Explosion Noclip. Preservation and disabled physics restore original collision values consistently on desktop and mobile.
- Keep Damping active with Force Smooth, Max Fidelity and frame tracking. Use stable correction damping across the 0?5 range while preserving intended target motion.
- Add desktop/mobile runtime regressions for damping, collision policy, core motion, lightning and beam continuity at multiple frame rates and update strides.

## September 23, 2026 - Black Hole v2 motion

- Replace the spiral-to-core position blend with a continuous inward orbit that tightens into a filled sphere without reversing direction or crossing through the center.
- Spin the settled sphere about a fixed upright axis at 720 degrees per second by default. Ease radius and inlet tilt changes, preserve capture progress during speed changes, and keep an optional accretion ring.
- Add opt-in frame tracking on desktop and mobile so fast orbits hold their geometry through velocity constraints while respecting speed limits. Cache the settled core's shared rotation for large part counts.
- Verify spherical volume, capture continuity, release/regrab behavior and actual commanded motion at 30, 60 and 144 Hz in offline fixtures.

## September 23, 2026 — Project UAI controls

- Connect both desktop and mobile PROJECT UAI buttons to the current Gravity context, enabling native engine, shape, targeting, and plugin tools in UAI 1.6.0.
- Publish `_GRAVITY_CONTEXT` after successful initialization so UAI can discover an already-running Gravity session. Unload clears only that session's own handle; reloads expose the new context.
- Complete native desktop/mobile control hooks for Part Control, core and shape keybindings, favorites, interface and visual performance settings, FPS, core color, ignore tags, manual Slingshot actions, and settings reset. Expose a session ID for stable external part references.
- Add mobile shape-switch and keybinding parity, including conflict checks, runtime rebinding, shape shortcuts, and cleanup while retaining existing mobile input action names.
- Share native settings effects and reset behavior through `RuntimeControls.lua`. Reset restores world visuals, frame cap, HUD, scale, hotkeys and late-registered plugin defaults while preserving live settings-table references.
- Refresh Part Control sliders and toggles without replaying callbacks or rebuilding a control during selection changes. Preserve native collision priorities for free physics, shape requests and ride mode when changing collision settings.
- Guard external part assignments after shape-loading yields. Release All also clears unselected ride/physics overrides without a pin/manual/shape mode.
