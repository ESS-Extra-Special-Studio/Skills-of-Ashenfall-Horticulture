# Skills of Ashenfall: Horticulture

A new skill for RuneScape: Dragonwilds, levels 1 to 25. Graft a cutting onto something you planted and see what's there at dawn. An ash tree full of potatoes, say, or an oak with cabbages in it.

Horticulture is the second Skills of Ashenfall skill. It stays locked, greyed out with a padlock, until you earn it.

## Requires

- ESL:DragonWilds 1.0.0 or later (Required Dependency)
- Skills of Ashenfall: Historian 1.0.0 or later (Required Dependency)
- UE4SS for RuneScape: Dragonwilds (3.0.1, the "UE4SS Steam (latest)" build)

Action Wheel: ESL:DragonWilds 1.0.0 includes it, so nothing more to install. Hold Z to choose Horticulture's actions from a wheel; see [Action Wheel](#action-wheel). Horticulture works the same with the wheel turned off.

## Install

Put the `SkillsOfAshenfallHorticulture` folder in the game's `~mods` folder, beside `ESLDragonWilds` and `SkillsOfAshenfallHistorian`:

```
RSDragonwilds\RSDragonwilds\Content\Paks\~mods\
    ESLDragonWilds\
    SkillsOfAshenfallHistorian\
    SkillsOfAshenfallHorticulture\
```

The folder ships with `enabled.txt`. If you use a `mods.txt` instead, list it after the other two:

```
ESLDragonWilds : 1
SkillsOfAshenfallHistorian : 1
SkillsOfAshenfallHorticulture : 1
```

If `Binaries\Win64\ue4ss\Mods\mods.txt` names one of these mods, that line wins over `enabled.txt`: `: 0` there keeps the mod off.

The folder also holds the mod's own pak, `SoAHorticulture_P.pak`, `.ucas` and `.utoc` (about 24 MB): the Horticulture skill badge, the stalks hybrid fruit hangs from, the Primelets' faces, the Mini Brassica Prime's cabbage head, and fruit baked onto each ash, oak and willow tree shape so it sways with the branches. The game loads it from `~mods` by itself. Keep the three files together beside `Scripts`. Without them Horticulture still works: the skill shows without its badge, fruit sits against the bark instead of hanging from a stalk, and the Primelets have no faces. Besides the pak, the folder has `enabled.txt`, the Lua scripts in `Scripts`, and `README.txt`, `CHANGELOG.txt` and `LICENSE.txt`.

## Unlocking Horticulture

1. Reach Historian 25 and Farming 25.
2. Find the **Annotated Hymnal** by the wild cabbage patch north-west of the Wise Old Man in Bramblemead Valley, where his farming lessons begin.
3. Read it. Its prompt reads "Lore", like every lore item in the game, with the Historian 25 requirement beside it. Below Historian 25 the second script between its lines cannot be made out.

Horticulture then appears in your skills menu and on the character select screen, and the reading itself takes you to level 2. The hymnal stays where it is, so you can read it again; Shift+End also rereads it anywhere once you have.

## Splicing

1. **Take a cutting.** Aim at a crop growing in one of your farm plots, a sapling or a tree and press **G**. The cutting goes into your satchel (six at most). Wild crops won't give one, nor will a crop sown today. One cutting per plant per day; a cutting wilts after two dawns.
2. **Graft it.** Aim at a crop, sapling or tree **you planted** and press **G** again. Crop cuttings take on crops and on trees; tree cuttings take on trees, never on a crop. A plant cannot take a graft of its own kind, except cabbage, which the Brassicans thought worth trying.
   - **Prime cuttings.** A tree only takes a *prime* crop cutting: one from a crop that is watered **and** composted, in a plot of at least its own tier (an ash plot for cabbage or potato, an oak plot for onion, tomato or dwellberry). A plot gives one prime cutting per crop cycle; the card says "PRIME CUTTING". A prime cutting, a watered plot and a composted plot also raise any graft's chance.
3. **Wait for dawn.** At 06:00 in game (sleeping through it counts) the graft takes or is rejected. Your first graft always takes; after that the chance is about 60%, better the further you are above the cutting's level and worse when a crop is grafted onto a weaker host.
4. **The hybrid.** A graft that takes changes the plant you can see, and the first of each pairing enters your **Discovery Catalogue**.
5. **Harvest it.** Hybrid trees can be picked once a day (aim and press G, or E at a grown tree). The fruit hangs at its natural size and sways with the branches.
   - **A crop on a tree** gives about one plot harvest of that crop a pick, never more than half a watered, composted plot's, and a little Farming XP (a quarter of what the plot harvest pays, at most 8). After four picks the scion rests: the tree goes **dormant** ("Tuberwood Ash (dormant)") until you graft another prime cutting of the same crop onto it, which wakes it at once for four more.
   - **A tree on a tree** (Weeping Oak) gives no wood on its own, so it doesn't replace Woodcutting. Chop it with an axe that could fell every wood in it (iron for Weeping Oak) and your first chop each day drops bonus wood on top of the normal logs. After four bonus chops it goes **dormant** until you graft a fresh cutting of the same wood onto it, cut from a living tree, which wakes it at once.
   - **A crop on a crop** adds the cutting's crop to the plot's normal harvest, and the game's own compost and water bonuses apply to that extra when the plot is of the crop's tier: about 14 to 16 for a tended plot with a hybrid against 10 without. Farming XP is the game's, as for any harvest.
   - **Felling** a hybrid tree ends it, with one pick's worth among the logs if it had a pick left that day (no XP for it). For a tree on a tree that also needs the axe its bonus chops need.

Tree cuttings need a logging axe in your hand that could fell that tree, as the game asks when you chop it: stone for ash, bronze for oak, iron for willow.

Splicing also asks for a vanilla level, set by the tier the game uses for that plant. A crop needs the Farming level for the farm plot it grows in: Farming 1 for the ash plot (cabbage, potato, wheat, redberry, flax, harralander, marrentill, kwuarm), Farming 10 for the oak plot (onion, tomato, dwellberry). A tree needs the Woodcutting level for the axe that fells it: Woodcutting 1 for ash (stone axe), 10 for oak (bronze), 20 for willow (iron); trees also need Farming 20, where the game teaches Tree Farming. This applies to taking a cutting, and to both plants in a graft. The game itself unlocks plots and axes by finding their materials, not at a level, so the level for each tier is Horticulture's: the first at 1, ten levels a tier after that. A greyed wheel slice or a refusal card says what is missing ("Needs Woodcutting 10 for oak").

| Horticulture | New cuttings and hosts |
|-------------:|------------------------|
| 1 | Cabbage, Ash |
| 5 | Potato |
| 8 | Oak |
| 10 | Wheat, Redberry |
| 13 | Flax |
| 15 | Harralander, Marrentill |
| 18 | Onion, Tomato |
| 20 | Willow |
| 22 | Kwuarm, Dwellberry |

### Flagship hybrids

| Hybrid | Graft | From | Gives |
|--------|-------|-----:|-------|
| Tuberwood Ash | Potato onto ash | 5 | 5 potatoes a pick, from the branches (four picks a prime cutting) |
| Brassitato | Cabbage onto potato | 5 | 2 cabbages with the potato harvest; 4 in a watered, composted plot, 6 from a prime cutting |
| Brassica-Oak | Cabbage onto oak | 8 | 5 cabbages a pick, from the canopy (four picks a prime cutting) |
| Sheaf Ash | Wheat onto ash | 10 | 5 wheat a pick (four picks a prime cutting) |
| Weeping Oak | Willow onto oak | 20 | 2 willow and 1 oak wood on your first chop each day with an iron axe (four chops a fresh willow cutting) |

Three more are waiting to be found, and every other pairing (all 150 that open by Horticulture 25) makes a hybrid of its own with a look and a catalogue line: crops nestle among the host crop's leaves, hang from a tree's branches, and a tree cutting grows as a limb of its host. Everything grows at its natural size.

### Spoiler: the Brassica Primelet

Very rarely (1.5% of the time, `primelet_chance`), a cabbage grafted onto a cabbage does not become a Doubled Cabbage. A small crowned cabbage climbs out of the plot instead, and a secret entry opens in the Discovery Catalogue.
- **Raising it:** tend it once a day (E or G beside it). It grows from Sprout to Brassica Primelet to **Mini Brassica Prime** over five tended days.
- **Its personality:** every Primelet is born with one (Pompous, Curious, Grumpy, Dramatic, Scholarly or, now and then, Completely Unhinged) and a name to suit, which shows from the Brassica Primelet stage: "Lord Savoy the Pompous".
- **Talking:** a Mini Brassica Prime talks. Press E beside it after tending it for the day and it answers; it also speaks up now and then when you are nearby, comments on being moved, notices when you cook nearby, has opinions on your Cooking level, and has views on the other Minis and on your hybrids. Lines show in a speech bubble above it. `primelet_chattiness` sets how often.
- **Moving it:** Alt+G picks it up into your satchel. Select it with Shift+G and press G to set it down wherever home is. A Mini takes a pot the first time it is set down and keeps it.
- **More than one:** each is raised, named and saved on its own.
- **Saving:** it is kept with your character and redrawn where you left it. Primelets from earlier saves get their personality and name the first time they load.

## Training

| Action | XP |
|--------|----|
| Take a cutting | 8 |
| Make a graft | 20 |
| A graft takes / is rejected | 45 / 10 |
| A new hybrid (first time each pairing) | +50 |
| A new flagship hybrid | +200 |
| The Brassica Primelet: found / each stage / tended (once a day, until grown) | +200 once / 30 / 5 |
| Pick from a hybrid tree or chop a wood hybrid for its bonus (once a day), or harvest a hybrid crop | 25 |
| Wake a dormant hybrid tree with a prime cutting (or a fresh wood cutting) | 15 |
| Reading the Observances | 33, once |

Ordinary farming still pays a little: sowing 10, watering 5, composting 10, weeding 3, curing 13, harvesting 23, and +17 / +33 for the first sowing and first harvest of each kind of crop. With eight plots and a few planted trees, level 25 takes four to six in-game days.

## Discovery Catalogue

End shows your satchel, the hybrids you have found and the **Vanilla Plants** section: the first harvest of each of the game's 24 crops.

## Keys

| Key | Does |
|-----|------|
| G | Aim at a plant: picks from a hybrid when it is ready, grafts your selected cutting onto a plant you grew, otherwise takes a cutting |
| Alt+G | Always takes a cutting from what you aim at |
| Shift+G | Selects the next cutting in your satchel |
| E | At a grown hybrid tree: picks from it, as G (trees have no E action of their own; chopping is still a swing). Beside a Brassica Primelet: tends it, and once it has been tended today, talks to it. Only when the game's prompt is not on something else, and never on a shoot, where the game's E destroys it |
| End | Shows Horticulture's level, XP, satchel and Discovery Catalogue, or what is still needed to unlock it. It updates while open |
| Shift+End | Rereads the Observances of Brassica Prime |

The first run writes `config.txt` next to `enabled.txt`:

| Setting | Default | Does |
|---------|---------|------|
| `status_key` | `END` | The key above, by its UE4SS key name (for example `PAGE_DOWN` or `NUM_ZERO`). Shift with the same key rereads the book. |
| `action_key` | `G` | The splicing key, by its UE4SS key name. Alt and Shift with it take a cutting and select the next one. |
| `primelet_chance` | `1.5` | Percent of cabbage-on-cabbage grafts that become a Brassica Primelet once they take. `0` turns it off. |
| `quiet` | `false` | `true` drops Horticulture's own cards (cuttings, grafts, the catalogue, the unlock reminder); XP and level-ups still show. |
| `mutation_tint` | `true` | Each hybrid's leaves (or crop) take on their own mutated colour: Tuberwood Ash a deep blue-violet, Sheaf Ash harvest gold, and so on. Every other combination gets a colour of its own, and the same pair always looks the same. `false` keeps the host plant's natural colours. |
| `name_tag` | `true` | Hybrid trees always name themselves in the game's own prompt ("Tuberwood Ash" instead of "Ash Tree"). This small tag above the prompt names the Brassica Primelet you face, and any hybrid the prompt cannot name. `false` turns the tag off. |
| `primelet_chattiness` | `normal` | How often a Mini Brassica Prime speaks up on its own: `off`, `quiet`, `normal` or `chatty`. With `off` it only answers when you talk to it or tend it. |
| `sway` | `true` | Fruit on hybrid trees sways with the game's wind, like the leaves (the nearest 12 within 30 m). `false` keeps it still. |
| `sway_degrees` | `0.35` | How far that fruit leans at the game's normal wind, in degrees about the trunk base (0 to 3). |
| `wild_cuttings` | `false` | `true` lets crop cuttings come from wild plants too. |
| `vigour_picks` | `4` | Picks a crop on a tree gives before it goes dormant. |
| `wood_chops` | `4` | Bonus chops a tree on a tree gives before it goes dormant. |
| `prime_cooldown_dawns` | `2` | Dawns before the same plot gives another prime cutting. |
| `pick_per_farming_levels` | `10` | A tree pick adds one per this many Farming levels, still capped at half a tended plot's harvest. |
| `pick_farming_xp` | `true` | Tree picks pay a little vanilla Farming XP. |
| `pick_farming_xp_share` / `pick_farming_xp_cap` | `0.25` / `8` | That XP as a share of a plot harvest's, and its most per pick. |
| `compost_multiplier` / `water_multiplier` | `1.5` / `1.15` | The bonuses a crop-on-crop hybrid's extra harvest gets from a composted and a watered plot (the game's own). |
| `prime_share` | `1` | Extra produce a crop-on-crop hybrid from a prime cutting adds, before those bonuses. |
| `farming_scale_cap` | `1.25` | Most a crop-on-crop hybrid's extra grows with Farming (1% a level above 25). |
| `debug` | `false` | `true` writes every XP award to the UE4SS log. |

### Action Wheel

With the Action Wheel (part of ESL:DragonWilds 1.0.0; the older standalone `ActionWheel` mod also works), hold **Z** while aiming at a plant, or with nothing aimed at, and choose. The wheel names hybrids and Primelets by their own names; while it shows names, Horticulture's small name tag stands aside.

| Slice | On | Does |
|-------|----|------|
| Pick *hybrid* | a hybrid tree or sapling | As G. Greyed with the reason when it cannot be picked ("Already picked today. More after dawn") |
| Graft › | a crop, sapling or tree you grew | A sub-wheel with one slice per cutting in your satchel; each is greyed with the reason it cannot take there ("Oak hosts need Horticulture 8") |
| Take cutting | a crop, sapling or tree | As Alt+G. Greyed with the reason ("Hold a logging axe…", "Potato cuttings need Horticulture 5") |
| Check graft | a plant with a graft | Shows how the graft is doing: its chance before dawn, or whether the hybrid can be picked |
| Tend (or Talk to) / Pick up *Primelet* | beside your Brassica Primelet | As E and Alt+G beside it |
| Set down *Primelet* | anywhere, with it selected | As G |
| Next cutting, Horticulture | yourself (nothing aimed at) | As Shift+G and End |

Before Horticulture is unlocked, Take cutting shows greyed with what is still needed, and the Horticulture slice shows the same list. G, Alt+G, Shift+G, E and End keep working with the wheel installed.

End was chosen because F10 opens the console with ConsoleEnabler, Home belongs to the ESL example skill, and F5 to F9 are taken by Historian and the HUD mod.

## Multiplayer

- Each player's Horticulture is their own, kept with their character.
- The hymnal is placed separately on each player's machine and is never saved into the world.
- Splicing works when you play alone or host. Hybrid looks are drawn on the host's screen only; guests see the plants as the game draws them.
- Playing alone or as host: farming pays only for your own work.
- As a guest: farming pays for plots within reach of your character, since the host's game runs the farming.

## Lore

**MOD LORE.** The Observances of Brassica Prime, the hybrids' names and their catalogue lines are fan-written, not Jagex canon. What the book leans on comes from Dragonwilds' own journal: Brassica Prime, Guthix and the druids sowing cabbage across Ashenfall, the fried cabbage, the failed cabbage wine, and a Guthixian druid's memoir of how this land changes things. The author, the scraped hymnal and the Observances themselves are invented for this mod.

## Progress

Your Horticulture progress is kept with the game's saved data by ESL:DragonWilds, as `<character id>.Horticulture.txt` in `%LOCALAPPDATA%\RSDragonwilds\Saved\ESLDragonWilds`; your satchel and grafts sit beside it in `<character id>.Horticulture.splicing.txt`. Updating or reinstalling the mod does not touch them. Hybrids are remembered by the mod, not the world save: the plants themselves stay vanilla, so uninstalling leaves ordinary crops and trees behind.

## Uninstall

Delete the `SkillsOfAshenfallHorticulture` folder from `~mods`, or disable it in CurseForge. Horticulture leaves the skills menu, character select and totals; your progress file stays in case you reinstall, and you can delete the `*.Horticulture.txt` files to remove it for good. The game's own saves and farming are never changed.

## Not affiliated

Skills of Ashenfall is a fan project by Extra Special Studio. It is not affiliated with, endorsed by, or sponsored by Jagex Ltd. RuneScape and RuneScape: Dragonwilds are trademarks of Jagex Ltd. See LICENSE.
