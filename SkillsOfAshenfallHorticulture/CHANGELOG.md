# Changelog

## 1.0.0 (2026-10-05)

The first release. Needs ESL:DragonWilds 1.0.0 and Skills of Ashenfall: Historian 1.0.0.

### Features

**The skill**

- Horticulture, levels 1 to 25 (3,152 XP).
- Locked until you have Historian 25 and Farming 25 and have read the Observances of Brassica Prime.
- The Annotated Hymnal lies on the grass by the wild cabbage patch near the Wise Old Man in Bramblemead Valley. It opens in the game's own lore popup. Below Historian 25 you can't read the older writing under the hymns. Reading it takes you to level 2.
- End shows your level, XP, satchel and Discovery Catalogue. Shift+End rereads the Observances.

**Splicing**

- Aim at a plant and press G. It takes a cutting, or grafts your selected cutting onto a crop, sapling or tree you planted. Alt+G always takes a cutting. Shift+G selects the next one in your satchel.
- The satchel holds six cuttings. One cutting per plant per day, and a cutting wilts after two dawns.
- Crop cuttings only come from your farm plots. Wild crops and crops sown today won't give one.
- Crop cuttings take on crops and trees. Tree cuttings only take on trees, and you need a logging axe in hand that could fell the tree.
- New cuttings and hosts open from Horticulture 1 to 22. Each plant also needs a vanilla level for its tier: Farming 1 for ash-plot crops and Farming 10 for oak-plot crops; Woodcutting 1, 10 or 20 for ash, oak or willow, plus Farming 20 for any tree. Greyed wheel slices and refusal cards tell you what's missing.
- At dawn each graft takes or is rejected. Your first graft always takes. After that it's about 60%, a little better for every level you are above the cutting's.
- **Prime cuttings.** A watered, composted crop in a plot of its own tier or better gives a prime cutting, once per crop cycle. Trees only take prime crop cuttings. A prime cutting, a watered plot and a composted plot each raise a graft's chance.

**Hybrids**

- A graft that takes changes the plant you see. There are five flagships (Tuberwood Ash, Brassitato, Brassica-Oak, Sheaf Ash and, from Horticulture 20, Weeping Oak) and three more to find. Each of the 150 pairings that open by level 25 has its own look and catalogue entry.
- Everything grows at natural size. Crops nestle among a crop's leaves or hang from a tree's branches, and a tree cutting grows as a limb.
- Each hybrid's leaves take on a mutated colour. The flagships' are hand-picked (Tuberwood Ash goes deep blue-violet). Every other pair gets one of eight colours, always the same for the same pair.
- Fruit on hybrid trees sways with the wind. Where the mod's pak has a baked fruit layer for that tree, the fruit moves with the tree's own leaves.
- Hybrid trees show their own name in the game's prompt: "Tuberwood Ash", not "Ash Tree".
- Each new hybrid gets a Discovery Catalogue card and bonus XP. Discovery cards wait until the game's level-up banner has gone.

**Harvesting**

- Pick a hybrid tree once a day with G, or with E at a grown tree.
- A crop on a tree gives about one plot harvest of that crop per pick, plus one for every 10 Farming levels. It never gives more than half a watered, composted plot's harvest.
- Tree picks also pay a little Farming XP: a quarter of what the same plot harvest pays, at most 8.
- After four picks the tree goes dormant ("Tuberwood Ash (dormant)"). Graft another prime cutting of the same crop to wake it for four more.
- A tree on a tree, such as Weeping Oak, gives no wood by itself. Your first chop each day with an axe that could fell every wood in it (iron for Weeping Oak) drops bonus wood. After four bonus chops it goes dormant until you graft a fresh cutting of the same wood, from a living tree. G, the prompt and the wheel say which axe it needs and how many chops are left.
- A crop on a crop adds the cutting's crop to the plot's normal harvest. The game's compost and water bonuses apply when the plot is of that crop's tier, and a prime cutting adds one more. A prime Brassitato in a watered, composted plot gives 6 cabbages on top of the potatoes.
- Felling a hybrid tree ends it. It keeps its look as it falls, and if it had a pick left that day, one pick's worth of produce drops where the canopy lands. A tree on a tree also needs the axe its bonus chops need. Felling pays no XP.

**The Brassica Primelet**

- Now and then (1.5% by default), a cabbage grafted onto a cabbage becomes a Brassica Primelet instead of a Doubled Cabbage. It gets a secret catalogue entry.
- Tend it once a day (E or G). Five tended days take it from Sprout to Brassica Primelet to Mini Brassica Prime.
- Each one has its own personality and name, such as "Lord Savoy the Pompous".
- A Mini Brassica Prime talks in a speech bubble above its pot: when you talk to it, when you move it, when you cook nearby, and now and then on its own. Some lines depend on your Cooking level.
- Alt+G picks it up and G sets it down. A grown Mini takes a pot the first time you set it down. Raise as many as you like.

**XP**

- Splicing: cutting 8, graft 20, graft takes 45 (rejected 10), new hybrid +50, new flagship +200, tree pick, bonus chop or hybrid harvest 25, waking a dormant tree 15.
- Brassica Primelet: +200 when found, 30 for each stage, 5 a day for tending until it's grown.
- Ordinary farming still pays a little: sowing 10, watering 5, composting 10, weeding 3, curing 13, harvesting 23. The first sowing and first harvest of each crop pay +17 and +33, and the first harvest of each of the game's 24 crops goes in the catalogue's Vanilla Plants section.

**Action Wheel**

- With the wheel in ESL:DragonWilds (or the older standalone mod), hold Z to pick, graft from a sub-wheel of your cuttings, take a cutting, check a graft or look after a Primelet. Greyed slices say why. The keys still work without it.

**Settings**

- `config.txt` is written on first run: `status_key`, `action_key`, `primelet_chance`, `quiet`, `name_tag`, `mutation_tint`, `primelet_chattiness`, `sway`, `sway_degrees` and `debug`, plus the harvest numbers `wild_cuttings`, `vigour_picks`, `wood_chops`, `prime_cooldown_dawns`, `pick_per_farming_levels`, `pick_farming_xp`, `pick_farming_xp_share`, `pick_farming_xp_cap`, `compost_multiplier`, `water_multiplier`, `prime_share` and `farming_scale_cap`.

### Changes

- Ordinary farming pays about a third of what it did in the test builds. Splicing is now the main source of XP.
- Horticulture isn't hidden before you unlock it any more. It shows greyed out with a padlock on character select and in the skills menu.

### Fixes

- Fixed a crash the first time you picked a farm plot in build mode. Horticulture now pauses its background work while you build and for 3 seconds after, and plots still on the build cursor are left alone.
- Farm plots are read correctly on the current game build, so plot crops give cuttings, take grafts and pay Farming XP.
- The hymnal lies along sloping ground instead of sinking a corner into the hillside.
- The hymnal sits flush on uneven or sloping ground (a root or rock under one edge no longer tips it) and no longer floats above the grass.
- The Horticulture badge no longer goes missing on character select.

### Technical notes

- Skill id `Horticulture`. Progress is in `<character id>.Horticulture.txt` and the satchel and grafts in `<character id>.Horticulture.splicing.txt`, both in `%LOCALAPPDATA%\RSDragonwilds\Saved\ESLDragonWilds`.
- The splicing save (version 2) stores a hybrid as an ordered list of plants, ready for a third graft later. Version 1 files convert on load.
- A bonus chop is seen as a rise in the player's live Woodcutting XP (`SkillComponent`) while aiming at a wood hybrid or standing at its trunk. The swing itself is the game's; nothing is added to it.
- Hybrid looks come from `Scripts\placements\` (the newest version of each file is used), with per-hybrid overrides in `looks\<HybridId>.txt`.
- The mod's pak, `SoAHorticulture_P` (`.pak`, `.ucas`, `.utoc`, about 24 MB together), adds the skill badge (`/Game/Mods/SoAHorticulture/UI/T_HorticultureSkillIcon`, registered by that path), the fruit stalks, the Primelets' faces, the Mini Brassica Prime's own round cabbage head and crown, and the baked fruit layers listed in `Scripts\placements\hort_fruit_layers_vNNN.lua`. Without it, fruit sits against the bark, the Primelets have no faces and the Mini is a plain cabbage in its pot.
- The release holds only file types CurseForge accepts for Dragonwilds UE4SS mods (.txt, .lua, .pak, .utoc, .ucas): the badge is in the pak, and the readme, changelog and licence ship as `.txt`. `tools\package.ps1` refuses any other type.
