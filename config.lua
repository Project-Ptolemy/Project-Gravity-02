return {
	x1 = {
		k1 = 2000,
		k2 = Vector3.new(5, 5, 5),
		k3 = Color3.fromRGB(255, 105, 180),
		k4 = math.huge,
		k5 = { "NoAttract", "Character" },
		k6 = "Celestial Ribbon",
		k7 = 4,
		k8 = 0.8,
		k9 = 80,
		k10 = 20,
		k11 = 2,
		k12 = 100,
		k13 = 10,
		k14 = 5,
		k15 = 10,
		k16 = 0.6,
		k17 = 150,
		Targets = {},
		IsLaunching = false,
		Disabled = false,
		TgtActive = false,
		PI_All = false,
		AnchorSelf = false,
		AntiFling = false,
		PreserveCollisions = false,
		PredictiveTracking = true,
		PredictionFactor = 150,
		ShowHUD = true,
		-- load_settings only restores a saved value when a default of the same
		-- type is already here, and reset_config only restores what it snapshotted
		-- from this table. A key the UI writes but this table omits therefore both
		-- forgets itself between sessions and survives "Reset All Settings".
		SimpleMode = false,
		-- Written by the mobile Advanced panel and read by main.lua's setfpscap call.
		-- With no default here load_settings could never restore it -- it only
		-- restores a key that already exists with a matching type -- so the cap
		-- reverted to 60 every launch, and reset_config never snapshotted it either,
		-- so it survived "Reset All Settings". Exactly the failure the note above
		-- describes.
		FPSCap = 60,
		-- The touch substitute for holding Shift in the sculptor. Read by
		-- System_sculptor on the mobile tree; it had no writer and no default at all,
		-- so it was permanently false and a touch user could never deselect a part or
		-- add to a selection.
		SculptorMultiSelect = false,
		PartCtlMultiSelect = false,
		-- Part Control listens on left click, and unlike the Sculptor it is not a
		-- shape, so it has no `x1.k6 == "Sculptor"` to gate itself on. Unarmed it
		-- would hijack every click on a held part and draw a selection rectangle
		-- over every core drag. Armed while the panel is open, or permanently by
		-- this toggle for people who want the panel out of the way.
		PartCtlEnabled = false,
		PartCtlMode = "pin",
		PartCtlShape = "Black Hole",
		PartCtlRide = false,
		-- nil means "inherit the global setting", which is what the System loop's
		-- `d.pc_phys and ...` guards test for. Stored as -1 rather than nil because
		-- the settings file round-trip drops nils, and the panel needs to be able to
		-- show "inherit" as a distinct state from a real value.
		PartCtlPull = -1,
		PartCtlDamping = -1,
		PartCtlSmoothing = -1,
		PartCtlMaxSpeed = -1,
		-- A drag used to be able to move a part only along a sphere at the distance
		-- latched when the press began, so there was no way to push it away or pull it
		-- closer. With this on the drag ray is cast at everything that is not held and
		-- the selection lands on the surface, which puts depth back under the pointer.
		-- Off restores the old fixed-distance projection exactly.
		PartCtlSurfaceSnap = true,
		-- Studs. 0 is off. Rounds a drag target onto a grid, which is the difference
		-- between placing parts and nudging them for a minute.
		PartCtlGridSnap = 0,
		Perf_DisableShadows = false,
		Perf_DisablePostFX = false,
		Perf_PotatoMaterials = false,
		Perf_HideParticles = false,
		SlingshotManual = false,
		AggressiveClaim = false,
		["Force Smooth (Lags)"] = false,
		-- Force Smooth plus always_process: no update bucketing, no radius cull.
		-- A superset, so it implies Force Smooth rather than sitting beside it.
		MaxFidelity = false,
		-- Off by default: the core marker staying visible while paused is the
		-- behaviour people are used to, and some of them park it deliberately.
		HideCoreOnPause = false,
		["Realistic Liftoff"] = false,
		Paused = false,
		Damping = 0.5,
		Ki = 0.1,
		MaxSpeed = 500,
		AngularDamping = 0.5,
		VerticalStiffness = 1.0,
		VoidProtection = true,
		UIScale = 1.0,
		-- Formation controls. Every one of these is inert at the value below, so the
		-- loop takes exactly the path it took before they existed: TimeScale 1 is the
		-- unscaled clock, BlendEnabled false never resolves a second field,
		-- PreviewEnabled false builds no ghosts, SlotMode "Claim" writes no d.slot at
		-- all (so shapes keep indexing by d.id exactly as they did), TargetParts 0 is
		-- no ceiling, and every rule field at 0 or "" is a rule that is not applied.
		--
		-- The types are load-bearing, for the reason the note at the top of this table
		-- gives: SlotMode, SurplusRule, BlendShape and RuleName must stay strings, the
		-- three toggles must stay booleans, and TimeScale must stay a number written
		-- with a decimal point -- load_settings compares typeof against the default,
		-- so a key whose default is missing or the wrong type silently drops the saved
		-- value and survives "Reset All Settings".
		TimeScale = 1.0,
		BlendEnabled = false,
		BlendShape = "Black Hole",
		BlendWeight = 0,
		BlendStagger = 0,
		PreviewEnabled = false,
		PreviewCount = 40,
		PreviewDeviation = false,
		SlotMode = "Claim",
		SlotSeed = 0,
		TargetParts = 0,
		SurplusRule = "Farthest",
		RuleMinSize = 0,
		RuleMaxSize = 0,
		RuleClaimRadius = 0,
		RuleName = "",
		-- Key names, not KeyCodes: an EnumItem does not survive the JSON round
		-- trip, and load_settings only restores a value whose type matches the
		-- default. "" is a real value here and means deliberately unbound.
		-- Shapes maps a shape name to a key that switches straight to it.
		Keybinds = {
			Recenter = "E",
			Reset = "Q",
			Pause = "P",
			Disable = "L",
			Shapes = {},
		},
	},
	x2 = {
		-- Vast structures, machines and disaster fields.
		["Constellation Lattice"] = { k11 = 860, k12 = 310, k13 = 18, k14 = 55, k15 = 27, k16 = 90 },
		["Cosmic Strings"] = { k11 = 960, k12 = 145, k13 = 22, k14 = 560, k15 = 45, k16 = 55 },
		["Fractal Dominion"] = { k11 = 860, k12 = 150, k13 = 17, k14 = 14, k15 = 18, k16 = 30 },
		["Nebula Highway"] = { k11 = 960, k12 = 80, k13 = 24, k14 = 95, k15 = 16, k16 = 40 },
		["Event Horizon Array"] = { k11 = 740, k12 = 64, k13 = 20, k14 = 220, k15 = 80, k16 = 90 },
		["Parallax Grid"] = { k11 = 880, k12 = 310, k13 = 18, k14 = 6, k15 = 12, k16 = 20 },
		["Astral Clockwork"] = { k11 = 455, k12 = 35, k13 = 20, k14 = 24, k15 = 28, k16 = 18, k17 = 95 },
		["Infinity Weave"] = { k11 = 1000, k12 = 120, k13 = 24, k14 = 28, k15 = 4, k16 = 100 },
		["Prism Cascade"] = { k11 = 190, k12 = 95, k13 = 20, k14 = 220, k15 = 110, k16 = 55, k17 = 80 },
		["Starforge Crucible"] = { k11 = 325, k12 = 180, k13 = 20, k14 = 520, k15 = 110, k16 = 24, k17 = 20 },
		["Continental Conveyor"] = { k11 = 720, k12 = 100, k13 = 18, k14 = 240, k15 = 230, k16 = 110 },
		["Worldbreaker Wheel"] = { k11 = 330, k12 = 180, k13 = 18, k14 = 520, k15 = 8 },
		["Siege Meridian"] = { k11 = 900, k12 = 410, k13 = 20, k14 = 110, k15 = 280, k16 = 280 },
		["Iron Procession"] = { k11 = 1080, k12 = 290, k13 = 18, k14 = 38, k15 = 48, k16 = 300 },
		["Crown of Ruin"] = { k11 = 370, k12 = 220, k13 = 22, k14 = 25, k15 = 170, k16 = 260 },
		["Guillotine Array"] = { k11 = 1000, k12 = 360, k13 = 19, k14 = 260, k15 = 260, k16 = 90 },
		["Pendulum Court"] = { k11 = 960, k12 = 340, k13 = 22, k14 = 95, k15 = 60, k16 = 250 },
		["Obsidian Causeway"] = { k11 = 1000, k12 = 180, k13 = 16, k14 = 200, k15 = 40, k16 = 270 },
		["Bastion Carousel"] = { k11 = 350, k12 = 260, k13 = 18, k14 = 145, k15 = 220, k16 = 45 },
		["Railstorm Battery"] = { k11 = 440, k12 = 440, k13 = 30, k14 = 440, k15 = 230, k16 = 120 },
		["Continental Shelf"] = { k11 = 350, k12 = 560, k13 = 10, k14 = 115, k15 = 105, k16 = 35 },
		["Avalanche Front"] = { k11 = 820, k12 = 530, k13 = 12, k14 = 340, k15 = 85, k16 = 30 },
		["Floodgate"] = { k11 = 800, k12 = 330, k13 = 10, k14 = 540, k15 = 80, k16 = 30 },
		["Razorgrass Expanse"] = { k11 = 860, k12 = 650, k13 = 12, k14 = 250, k15 = 125, k16 = 15 },
		["Sandstorm Wall"] = { k11 = 940, k12 = 440, k13 = 11, k14 = 115, k15 = 210, k16 = 15 },
		["Thunderhead Armada"] = { k11 = 940, k12 = 470, k13 = 10, k14 = 390, k15 = 155, k16 = 0 },
		["Meteor Dominion"] = { k11 = 110, k12 = 540, k13 = 10, k14 = 250, k15 = 160, k16 = 290 },
		["Solar Flare"] = { k11 = 320, k12 = 360, k13 = 11, k14 = 185, k15 = 6, k16 = 45 },
		["Shockwave Barrage"] = { k11 = 460, k12 = 90, k13 = 10, k14 = 3, k15 = 8, k16 = 15 },
		["Polar Rift"] = { k11 = 650, k12 = 760, k13 = 10, k14 = 160, k15 = 70, k16 = 20 },
		-- Large moving formations for Natural Disaster Survival debris.
		["Tsunami"] = { k11 = 220, k12 = 180, k13 = 24, k14 = 300, k15 = 70, k16 = 110, k17 = -20 },
		["Killer"] = { k11 = 240, k12 = 8, k13 = 36, k14 = 18, k15 = 150, k16 = 100, k17 = 8 },
		["Cataclysm Dragon"] = { k11 = 420, k12 = 230, k13 = 20, k14 = 36, k15 = 125, k16 = 190, k17 = 65 },
		["Thunderbird"] = { k11 = 245, k12 = 280, k13 = 24, k14 = 38, k15 = 145, k16 = 210, k17 = 85 },
		["Abyssal Maw"] = { k11 = 135, k12 = 380, k13 = 26, k14 = 65, k15 = 80, k16 = 105, k17 = 180 },
		["Dreadnought"] = { k11 = 420, k12 = 180, k13 = 18, k14 = 110, k15 = 55, k16 = 170, k17 = 150 },
		["Titan Stampede"] = { k11 = 110, k12 = 165, k13 = 26, k14 = 85, k15 = 90, k16 = 210, k17 = 60 },
		["Rift Reaper"] = { k11 = 100, k12 = 240, k13 = 12, k14 = 210, k15 = 220, k16 = 135, k17 = 6 },
		["Extinction Comet"] = { k11 = 70, k12 = 310, k13 = 16, k14 = 95, k15 = 230, k16 = 180, k17 = 50 },
		["Faultline"] = { k11 = 480, k12 = 140, k13 = 12, k14 = 90, k15 = 210, k16 = 0, k17 = 11 },
		["Eruption"] = { k11 = 85, k12 = 250, k13 = 10, k14 = 300, k15 = 75, k16 = 160, k17 = 0 },
		["Oblivion Drill"] = { k11 = 105, k12 = 380, k13 = 20, k14 = 3, k15 = 250, k16 = 95, k17 = 65 },
		["Black Hole v2"] = {
			rwNoclip = true, rwPull = 60, rwSpin = 14, rwBallSpin = 720,
			rwBall = 12, rwRing = 0, rwRingWidth = 3, rwTilt = 25,
			rwForce = 400, rwExplodeTime = 1.6,
		},
		["Ghost Galleon"] = { k11 = 155, k12 = 52, k13 = 5, k14 = 170, k15 = 80, k16 = 115, k17 = 3, k24 = 55 },
		["Infernal Skull"] = { k11 = 95, k12 = 55, k13 = 6, k14 = 115, k15 = 60, k16 = 210, k17 = 30, k24 = 55 },
		["Chrono Hourglass"] = { k11 = 95, k12 = 240, k13 = 7, k14 = 6, k15 = 14, k16 = 200, k17 = 18, k24 = 55 },
		["Storm Gyre"] = { k11 = 100, k12 = 230, k13 = 8, k14 = 3, k15 = 105, k16 = 65, k17 = 150, k24 = 55 },
		["Ragnarok Hammer"] = { k11 = 85, k12 = 42, k13 = 6, k14 = 220, k15 = 125, k16 = 220, k17 = 20, k24 = 55 },
		["Eclipse Scythe"] = { k11 = 115, k12 = 38, k13 = 6, k14 = 260, k15 = 110, k16 = 230, k17 = -15, k24 = 55 },
		["Aegis Bastion"] = { k11 = 140, k12 = 100, k13 = 5, k14 = 32, k15 = 75, k16 = 190, k17 = 18, k24 = 55 },
		["Singularity Trident"] = { k11 = 95, k12 = 22, k13 = 6, k14 = 240, k15 = 150, k16 = 220, k17 = 3, k24 = 55 },
		["Celestial Manta"] = { k11 = 80, k12 = 170, k13 = 8, k14 = 200, k15 = 35, k16 = 180, k17 = 70, k24 = 55 },
		["Megalodon"] = { k11 = 140, k12 = 38, k13 = 7, k14 = 100, k15 = 30, k16 = 160, k17 = 100, k18 = 55, k19 = 20, k20 = 75, k24 = 55 },
		["World Tree"] = { k11 = 135, k12 = 250, k13 = 5, k14 = 7, k15 = 55, k16 = true, k17 = 80, k24 = 55 },
		["Abyssal Jellyfish"] = { k11 = 100, k12 = 12, k13 = 10, k14 = 240, k15 = 35, k16 = 1.5, k17 = 280, k18 = 45, k24 = 55 },
		["Void Cathedral"] = { k11 = 125, k12 = 6, k13 = 5, k14 = 240, k15 = 65, k16 = 8, k17 = 55, k18 = 1.8, k24 = 55 },
		["Ouroboros"] = { k11 = 145, k12 = 20, k13 = 8, k14 = 28, k15 = 32, k16 = 35, k17 = 210, k18 = 35, k19 = 18, k24 = 55 },
		["Hopf Fibration"] = { k11 = 85, k12 = 8, k13 = 6, k14 = 55, k15 = 35, k16 = 1.5, k17 = 210, k18 = 25, k24 = 55 },
		["Astral Kraken"] = { k11 = 38, k12 = 8, k13 = 8, k14 = 180, k15 = 1.5, k16 = 7, k17 = 120 },
		["Cosmic Lotus"] = { k11 = 130, k12 = 8, k13 = 6, k14 = 3, k15 = 75, k16 = 40, k17 = true },
		["Phoenix Ascendant"] = { k11 = 160, k12 = 14, k13 = 24, k14 = 180, k15 = 45, k16 = 100, k17 = 45, k18 = 250, k20 = 120, k21 = 25, k22 = 65, k23 = 65 },
		["Rift Gate"] = { k11 = 100, k12 = 220, k13 = 8, k14 = 9, k15 = 65, k16 = 3, k17 = 130, k18 = true, k19 = 3, k20 = 320, k21 = 0, k22 = 0, k23 = 0 },
		["Reality Shatter"] = { k11 = 90, k12 = 130, k13 = 12, k14 = 160, k15 = 24, k16 = 120, k17 = true },
		["Hypercube Nexus"] = { k11 = 95, k12 = 4, k13 = 7, k14 = 20, k15 = 150, k16 = 2, k17 = 3 },
		["Pulsar Vortex"] = { k11 = 200, k12 = 8, k13 = 10, k14 = 0, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Big Ring Things"] = { k12 = 100, k13 = 10, k14 = 5, k16 = 0.6, k15 = 10, k11 = 2, k17 = 150, k23 = false },
		["Celestial Ribbon"] = { k12 = 0, k13 = 15, k14 = 30, k16 = 0.4, k11 = 1, k17 = 150, k18 = false, k19 = 2, k23 = false },
		["Hollow Worm"] = { k12 = 0, k13 = 15, k14 = 35, k16 = 0.4, k15 = 10, k11 = 15, k17 = 150, k23 = false },
		["Cosmic Comet"] = { k12 = 50, k13 = 20, k14 = 20, k16 = 0.5, k15 = 5, k11 = 5, k17 = 150, k23 = false },
		["Point Impact"] = {},
		["Domain Expansion Infinite Void"] = { k11 = 90, k12 = 0, k13 = 15, k14 = 0, k15 = 0, k16 = 0, k23 = false, k18 = true, k19 = true },
		["Vortex Funnel"] = { k11 = 50, k12 = 300, k13 = 30, k14 = 400, k15 = 5, k16 = 0, k23 = false },
		["Quantum Atoms"] = { k11 = 60, k12 = 0, k13 = 15, k14 = 0, k15 = 3, k16 = 0, k23 = false },
		["Halo Ring"] = { k11 = 40, k12 = 0, k13 = 5, k14 = 80, k15 = 0, k16 = 0, k17 = 50, k23 = false },
		["Slingshot"] = { k11 = 50, k12 = 3, k13 = 100, k14 = 0, k15 = 5, k16 = 0, k17 = 100, k23 = false },
		["Gods Call"] = { k11 = 10, k12 = 0, k13 = 0, k14 = 0, k15 = 0, k16 = 0, k17 = 50, k23 = false },
		["Shield Wall"] = { k11 = 20, k12 = 25, k13 = 20, k14 = 50, k15 = 10, k16 = 0, k17 = 50, k23 = false },
		["Sculptor"] = { k11 = 0, k12 = 0, k13 = 0, k14 = 0, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Torus Knot"] = { k11 = 3, k12 = 2, k13 = 10, k14 = 50, k15 = 20, k16 = 0, k17 = 0, k23 = false },
		["Möbius Strip"] = { k11 = 50, k12 = 20, k13 = 15, k14 = 0, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["DNA Helix"] = { k11 = 20, k12 = 80, k13 = 10, k14 = 50, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Black Hole"] = { k11 = 40, k12 = 100, k13 = 15, k14 = 50, k15 = 5, k16 = 0, k17 = 0, k23 = false },
		["Dense Spin"] = { k11 = 50, k12 = 2 },
		["Tesseract"] = { k11 = 40, k12 = 80, k13 = 10, k14 = 50, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Klein Bottle"] = { k11 = 60, k12 = 20, k13 = 20, k14 = 0, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Space Station"] = { k11 = 80, k12 = 30, k13 = 10, k14 = 150, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Supernova"] = { k11 = 15, k12 = 100, k13 = 25, k14 = 50, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Dyson Sphere"] = { k11 = 150, k12 = 8, k13 = 10, k14 = 0, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Seraphim"] = { k11 = 80, k12 = 4, k13 = 15, k14 = 40, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Alien Mothership"] = { k11 = 120, k12 = 40, k13 = 15, k14 = 200, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Cursed Technique Red"] = { k12 = 100 },
		["ROOM Ope Ope no Mi"] = { k11 = 150, k12 = 2, k13 = 1.5, k14 = 20, k18 = true },
		["Light Light no Mi"] = { k11 = 150, k12 = 400, k13 = 3, k14 = 2, k18 = true },
		["Goro Goro no Mi"] = {
			k11 = 200, k12 = 18, k13 = 14, k14 = 12, k15 = 3,
			k16 = 0.3, k17 = 0.4, k18 = 2, k19 = true, k20 = false, k21 = false,
		},
		-- k21 is Shell Fill as a percentage (100 = a solid ball) and k22 is Surface
		-- Jitter in studs, 0 for an exact sphere. Deliberately *new* keys rather than
		-- the k16/k17 that used to be Arc Count and Arc Jaggedness: load_settings
		-- restores any saved value whose type matches, so reusing them would have handed
		-- an existing user's Arc Count of 8 to Shell Fill and left them with a thin,
		-- rough shell -- exactly the form this shape was changed to stop being. k16 and
		-- k17 are gone, so a saved value for them is dropped on load. k20 was a Neon
		-- Glow toggle that repainted every part's Material and Color with nothing to
		-- restore them from -- x4.f1 never snapshots either -- so it is gone rather than
		-- defaulted off.
		["Raigo"] = {
			k11 = 8, k12 = 250, k13 = 80, k14 = 0.7, k15 = 12,
			k18 = true, k19 = true, k21 = 100, k22 = 0,
		},
		["Quantum Core"] = { k11 = 100, k12 = 30, k13 = 40, k14 = 50, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Galactic Web"] = { k11 = 400, k12 = 10, k13 = 5, k14 = 0, k15 = 0, k16 = 0, k17 = 0, k23 = false, k24 = 200 },
		-- k14/k15/k16 carry Div = 10, so the value here is what the shape reads and
		-- the panel shows it ten times larger. Written pre-multiplied these were
		-- ten times too big: 3 displayed as 30 against a 1..20 slider, so the first
		-- time the panel opened UI.lua:1287-1289 clamped it and wrote back 2.
		["Quantum Entanglement"] = { k11 = 50, k12 = 100, k13 = 200, k14 = 0.3, k15 = 0.2, k16 = 0.5 },
		["Meteor Shower"] = { k11 = 500, k12 = 300, k13 = 150, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["World Serpent"] = { k11 = 400, k12 = 100, k13 = 20, k14 = 20, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Aurora Borealis"] = { k11 = 600, k12 = 300, k13 = 15, k14 = 100, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Arcane Orrery"] = { k11 = 120, k12 = 4, k13 = 8, k14 = 200, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Maelstrom Spire"] = { k11 = 30, k12 = 200, k13 = 15, k14 = 6, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Eldritch Binding"] = { k11 = 100, k12 = 200, k13 = 5, k14 = 8, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Graviton Engine"] = { k11 = 4, k12 = 60, k13 = 12, k14 = 200, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Fractal Web"] = { k11 = 40, k12 = 3, k13 = 3, k14 = 5, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Leviathan Coil"] = { k11 = 50, k12 = 15, k13 = 8, k14 = 250, k15 = 0, k16 = 0, k17 = 0, k23 = false },
		["Spinning Cube"] = { k11 = 40, k12 = 200, k13 = false, k14 = false, k15 = true },
		["Twin Core Beam"] = { k11 = 80, k12 = 15, k13 = 150, k14 = 900, k15 = 4, k18 = false },
		-- k18 must stay a string: load_settings only restores a saved value when the
		-- default has the same type, so a number here would silently drop the message.
		["Hover Text"] = { k18 = "HELLO", k11 = 6, k12 = 30, k13 = 15, k14 = 0.8, k15 = 2, k16 = 0, k19 = true },
		-- Every key a shape's Controls touch has to exist here with its final
		-- type: load_settings only restores a saved value when the default has
		-- the same type, so a missing key can never be restored and a boolean
		-- written as a number silently drops. k19..k22, k32, k48, k55, k57 and
		-- k58 are toggles and must stay booleans.
		["Platform"] = {
			k11 = 8, k12 = -3, k13 = 12, k14 = 3, k15 = 0, k16 = 1, k17 = 0, k18 = 1,
			k19 = true, k20 = false, k21 = false, k22 = true,
			k23 = 1.0, k24 = 0, k25 = 0, k26 = 0.6, k27 = 6, k28 = 0,
			k29 = 1.2, k30 = 1.0, k31 = 0, k32 = false, k33 = 1, k34 = 0, k35 = 0.6,
			k36 = 1, k37 = 1, k38 = 0, k39 = 80, k40 = 5, k41 = 6, k42 = 250, k43 = 24,
			k44 = 0, k45 = 100, k46 = 0, k47 = 1, k48 = false, k49 = 60, k50 = 3,
			k51 = 0, k52 = 16, k53 = 0.5, k54 = 0.5, k55 = false, k56 = 60,
			k57 = false, k58 = false, k59 = 0,
		},
		-- k12/k13/k20 are enum pickers rendered as integer sliders (no Dropdown
		-- control exists), k21 is a toggle and must stay a boolean, and k14 carries
		-- Div = 10, so the value stored here is what the shape reads -- the UI
		-- multiplies by Div for display and divides on the way back, so a default
		-- written pre-multiplied would be ten times too big.
		["Rocket Engine"] = {
			k11 = 120, k12 = 1, k13 = 1, k14 = 15, k15 = 10, k16 = 18,
			k17 = 45, k18 = 60, k19 = 10, k20 = 1, k21 = false, k22 = 4,
		},
		-- k14 and k15 are toggles and must stay booleans. k11 carries Div = 10.
		-- k18 (Motion Gain) and k19 (Tilt Track) carry Div = 100, so 1 here is the
		-- 100 the panel shows: the mech mirrors your live pose exactly. They used to
		-- drive a synthetic walk cycle, which is what stopped the suit from tracking
		-- the character.
		["Mech Suit"] = {
			k11 = 2, k12 = 30, k13 = 2, k14 = false, k15 = true, k16 = 1200,
			k17 = 0, k18 = 1, k19 = 1,
		},
		["Big Bad Broom"] = {
			k11 = 60, k12 = 30, k13 = 35, k14 = 25, k15 = 1,
			k16 = 2, k17 = 8, k18 = 10, k19 = 3,
		},
		-- Lag Tree pair. k14 and k16 on Meteor Hammer carry Div = 10, so the
		-- stored 0.8 and 1.2 show as 8 and 12 on the panel (UI.lua:1287-1289).
		["Meteor Hammer"] = {
			k11 = 90, k13 = 60, k14 = 0.8, k15 = 60, k16 = 1.2,
			k17 = 16, k18 = 4, k19 = 55,
		},
		["Mochi Mochi no Mi"] = {
			k11 = 60, k12 = 26, k13 = 45, k14 = 0, k15 = 22,
			k16 = 70, k17 = 62,
		},
		["Ymir's Flesh"] = {
			k13 = 300, k14 = 140, k15 = 110, k16 = 4, k17 = 1,
			k18 = 1, k20 = 40, k21 = 60, k22 = 120,
		}
	},
}
