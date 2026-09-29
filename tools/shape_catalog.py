"""Six-panel motion gallery order and captions. Names match the Lua filenames."""

NEW_SHAPES = (
    "Abyssal Jellyfish", "Void Cathedral", "Ouroboros", "Hopf Fibration",
    "Celestial Manta", "Megalodon", "World Tree", "Ragnarok Hammer",
    "Eclipse Scythe", "Aegis Bastion", "Singularity Trident", "Ghost Galleon",
    "Infernal Skull", "Chrono Hourglass", "Storm Gyre",
)

DISASTER_GROUPS = (
    ("Breakers and hunters", (
        ("Tsunami", "Twin curling breakers with a sweeping shoreline"),
        ("Killer", "Fast core strikes with bowed reload paths"),
        ("Cataclysm Dragon", "A charging dragon with broad beating wings"),
        ("Thunderbird", "Banking dives with jagged lightning streamers"),
        ("Abyssal Maw", "A huge toothed mouth lunges and bites"),
        ("Dreadnought", "A heavy ram ship plows through a rolling wake"),
    )),
    ("Map-scale disasters", (
        ("Titan Stampede", "Three horned beasts charge with running strides"),
        ("Rift Reaper", "Moving portal mouths launch sweeping scythe arcs"),
        ("Extinction Comet", "A diving comet drags five long braided flames"),
        ("Faultline", "Traveling slabs erupt along a jagged ground ridge"),
        ("Eruption", "A moving crater throws fountains into low lava sweeps"),
        ("Oblivion Drill", "A colossal corkscrew bores along a winding path"),
    )),
)
DISASTER_SHAPES = tuple(name for _, entries in DISASTER_GROUPS for name, _ in entries)

VAST_GROUPS = (
    ("Networks and megastructures", (
        ("Constellation Lattice", "A vast diamond network flexes around moving joints"),
        ("Cosmic Strings", "Long bowed strings sweep and carry traveling ripples"),
        ("Fractal Dominion", "An immense branching structure grows and contracts"),
        ("Nebula Highway", "Three raised crossings carry recirculating debris"),
        ("Event Horizon Array", "Four moving cores pull arcing streams between them"),
        ("Parallax Grid", "A huge checkerboard folds into a traveling wall"),
    )),
    ("Cosmic machinery", (
        ("Astral Clockwork", "Giant hands sweep a turning segmented dial"),
        ("Infinity Weave", "Braided streams cross through a vast figure eight"),
        ("Prism Cascade", "Triangular cages rise and fall along stepped channels"),
        ("Starforge Crucible", "A huge bowl draws in feeds and swings forging arms"),
        ("Continental Conveyor", "A giant belt rolls around two wheel ends"),
        ("Worldbreaker Wheel", "An enormous upright spoked wheel rolls across the map"),
    )),
    ("Moving fortifications", (
        ("Siege Meridian", "An advancing arch carries sweeping battering strikers"),
        ("Iron Procession", "Tall linked walls march along a folding line"),
        ("Crown of Ruin", "A jagged crown widens, sweeps and slams"),
        ("Guillotine Array", "Five giant frames drop their blades in sequence"),
        ("Pendulum Court", "Three monumental pendulums swing in opposed phases"),
        ("Obsidian Causeway", "A long arched bridge advances with a shifting deck"),
    )),
    ("Siege and terrain", (
        ("Bastion Carousel", "Four fortified towers travel on turning cross arms"),
        ("Railstorm Battery", "Three long rails launch recirculating volleys"),
        ("Continental Shelf", "Two huge tectonic plates collide, heave and slide"),
        ("Avalanche Front", "A broad moving slope rolls into a tumbling debris front"),
        ("Floodgate", "A monumental dam drives broad surges through three gates"),
        ("Razorgrass Expanse", "Giant blade rows sweep in traveling waves"),
    )),
    ("Sky and force fields", (
        ("Sandstorm Wall", "A vast upright wind front rolls across the map"),
        ("Thunderhead Armada", "Migrating anvil clouds drag long lightning curtains"),
        ("Meteor Dominion", "Three massive meteors dive along staggered routes"),
        ("Solar Flare", "Enormous flare tongues arc from a broad hemisphere"),
        ("Shockwave Barrage", "Polygonal ground fronts expand in alternating shocks"),
        ("Polar Rift", "Two serrated walls unzip a colossal jagged fissure"),
    )),
)
VAST_SHAPES = tuple(name for _, entries in VAST_GROUPS for name, _ in entries)

GROUPS = (
    ("Creatures", (
        ("Phoenix Ascendant", "Banking flight, wingbeats and flowing tails"),
        ("Astral Kraken", "Breathing mantle and curling tentacles"),
        ("Abyssal Jellyfish", "Pulsing bell and trailing oral ribbons"),
        ("Celestial Manta", "Rolling wing waves and a streaming tail"),
        ("Megalodon", "Swimming body, swept fins and a beating tail"),
        ("Ouroboros", "An undulating serpent biting its own tail"),
    )),
    ("Monuments", (
        ("Rift Gate", "Twin irises around a twisting wormhole"),
        ("Void Cathedral", "Gothic arches and a counter-rotating halo"),
        ("Aegis Bastion", "A floating shield with flexing winglets"),
        ("Ghost Galleon", "Rocking hull, billowing sails and a wake"),
        ("World Tree", "Twisting roots and a breathing canopy"),
        ("Infernal Skull", "Turning horns and an opening jaw"),
    )),
    ("Relics and storms", (
        ("Ragnarok Hammer", "A turning hammer with orbiting debris"),
        ("Eclipse Scythe", "Sweeping blade, shaft and crescent halo"),
        ("Singularity Trident", "Three prongs, a wrapped grip and orbiting halo"),
        ("Chrono Hourglass", "Circulating sand inside an hourglass cage"),
        ("Storm Gyre", "Braided funnels beneath a turning storm cloud"),
        ("Cosmic Lotus", "Opening petals in counter-rotating layers"),
    )),
    ("Mathematical forms", (
        ("Hopf Fibration", "Linked circles from a Hopf projection"),
        ("Torus Knot", "Even-speed motion around a torus knot"),
        ("Klein Bottle", "A continuous figure-eight immersion"),
        ("Möbius Strip", "Two turns traverse both sides of the strip"),
        ("Hypercube Nexus", "A rotating 5D cube projected into 3D"),
        ("Tesseract", "Nested rotating cubes and connecting edges"),
    )),
    ("Orbital machines", (
        ("Arcane Orrery", "Orbiting rings, arms and a central axis"),
        ("Graviton Engine", "Stacked turbine rings and flowing particles"),
        ("Quantum Core", "A spinning core with surrounding particles"),
        ("Quantum Atoms", "Particles on tilted intersecting orbits"),
        ("Space Station", "A turning station ring and central body"),
        ("Alien Mothership", "A rotating saucer above a downward beam"),
    )),
    ("Sky phenomena", (
        ("Aurora Borealis", "Traveling waves across a broad curtain"),
        ("Black Hole", "Differential rotation in a warped disk"),
        ("Dyson Sphere", "Orbiting debris over a spherical shell"),
        ("Supernova", "Repeated expansion from a central star"),
        ("Meteor Shower", "Falling streams of debris"),
        ("Cosmic Comet", "An orbiting head with a trailing tail"),
    )),
    ("Serpents and ribbons", (
        ("Celestial Ribbon", "Ribbon bodies following a shared path"),
        ("Hollow Worm", "A hollow tube traveling along a curve"),
        ("World Serpent", "A long winding serpent of debris"),
        ("Leviathan Coil", "A coiled body with animated appendages"),
        ("Eldritch Binding", "Winding tendrils around a central column"),
        ("Seraphim", "Turning rings and a feathered wing array"),
    )),
    ("Currents and webs", (
        ("Vortex Funnel", "A widening column of spiraling debris"),
        ("Pulsar Vortex", "Twisting streams through a broad vortex"),
        ("Maelstrom Spire", "Spiral jets around a rising spire"),
        ("Galactic Web", "Rotating nodes joined by a web"),
        ("Fractal Web", "Breathing branches of repeated geometry"),
        ("DNA Helix", "Rotating strands and connecting rungs"),
    )),
    ("Spins and transformations", (
        ("Big Ring Things", "Separated rings rotating at different rates"),
        ("Halo Ring", "Continuous circulation around a tilted halo"),
        ("Spinning Cube", "A rigid cube rotating on its chosen axes"),
        ("Reality Shatter", "Triangular shards burst apart and reform"),
        ("Quantum Entanglement", "Paired particles drift, collapse and release"),
        ("Dense Spin", "Fast circulation inside a dense small ball"),
    )),
    ("Energy abilities", (
        ("Goro Goro no Mi", "Branching lightning follows the cursor"),
        ("Raigo", "An orb launches, expands and returns"),
        ("Light Light no Mi", "Beam heads bounce with persistent trails"),
        ("ROOM Ope Ope no Mi", "A rotating dome with shuffled part slots"),
        ("Twin Core Beam", "Orbiting cores switch into aimed streams"),
        ("Domain Expansion Infinite Void", "Rotating debris throughout a void sphere"),
    )),
    ("Tools and puppets", (
        ("Mech Suit", "Debris follows the walking avatar's pose"),
        ("Platform", "A moving pad follows the avatar"),
        ("Hover Text", "Glyphs hover with a traveling wave"),
        ("Sculptor", "Selected debris follows a scripted drag"),
        ("Shield Wall", "A sweeping wall of orbiting debris"),
        ("Big Bad Broom", "Click extension and a cursor-driven sweep"),
    )),
    ("Launches and impacts", (
        ("Rocket Engine", "A flying engine with streaming exhaust"),
        ("Meteor Hammer", "An orbiting hammer and trailing chain"),
        ("Mochi Mochi no Mi", "An elastic blob stretches behind the core"),
        ("Cursed Technique Red", "The moving core repels nearby debris"),
        ("Point Impact", "Loose debris converges on a moving core"),
        ("Slingshot", "An outer charge collapses toward the core"),
    )),
    ("World probes and review shapes", (
        ("Gods Call", "Loose debris rises at a constant speed"),
        ("Ymir's Flesh", "A breathing envelope fitted to a room"),
        ("Dragons Teeth", "Ground-fitted teeth around the caster"),
        ("Mugen Train", "A moving train of debris carriages"),
        ("Yamata no Orochi", "Multiple heads probe a room and doorway"),
        ("Drop", "Reselect, release and fall onto a fixture floor"),
    )),
)

GROUPS += DISASTER_GROUPS + VAST_GROUPS + (
    ("Gather and release", (("Black Hole v2", "Spiral capture into a dense moving sphere"),)),
)
CAPTIONS = {name: caption for _, entries in GROUPS for name, caption in entries}
VIEWS = {
    "Constellation Lattice": (24, 28), "Cosmic Strings": (18, 35),
    "Fractal Dominion": (15, 52), "Nebula Highway": (20, 42),
    "Parallax Grid": (20, 38), "Astral Clockwork": (10, 58),
    "Infinity Weave": (0, 58), "Starforge Crucible": (22, 35),
    "Tsunami": (8, 10), "Titan Stampede": (45, 18),
    "Rift Gate": (48, 18),
    "Celestial Manta": (15, 42), "Megalodon": (65, 15), "Ghost Galleon": (52, 16),
    "Infernal Skull": (8, 8), "Aegis Bastion": (12, 8), "Void Cathedral": (30, 18),
    "Hover Text": (0, 5), "Möbius Strip": (25, 40), "Torus Knot": (25, 40),
    "Hopf Fibration": (20, 32), "Mech Suit": (15, 8), "Platform": (22, 35),
    "Black Hole": (22, 35), "Halo Ring": (22, 35), "Ouroboros": (18, 25),
    "Big Bad Broom": (62, 18), "Twin Core Beam": (50, 22), "Goro Goro no Mi": (62, 18),
}

# Gallery-only control choices, never written back into config.lua. Keep the
# defaults unless a dense/fast form needs a readable demonstration at GIF fps.
PRESETS = {
    "Phoenix Ascendant": {"k18": 90, "k20": 45},
    "Rift Gate": {"k19": 1},
    "Dense Spin": {"k11": 2, "k12": 20},
    "Light Light no Mi": {"k13": 1, "k14": 6},
}
