# Skills of Ashenfall: Horticulture

A new skill for RuneScape: Dragonwilds, levels 1 to 25. Take cuttings, graft them onto the crops and trees you planted, and see what grows by dawn: an ash with potatoes at its roots, an oak hung with cabbages.

Horticulture is the second Skills of Ashenfall skill. It is hidden until you earn it.

## Requires

- ESL:DragonWilds 1.0.0 or later (Required Dependency)
- Skills of Ashenfall: Historian 1.0.0 or later (Required Dependency)
- UE4SS for RuneScape: Dragonwilds (3.0.1, the "UE4SS Steam (latest)" build)

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

## Unlocking Horticulture

1. Reach Historian 25 and Farming 25.
2. Find the **Annotated Hymnal** by the wild cabbage patch north-west of the Wise Old Man in Bramblemead Valley, where his farming lessons begin.
3. Read it. Its prompt reads "Lore", like every lore item in the game, with the Historian 25 requirement beside it. Below Historian 25 the second script between its lines cannot be made out.

Horticulture then appears in your skills menu and on the character select screen, and the reading itself takes you to level 2. The hymnal stays where it is, so you can read it again; Shift+End also rereads it anywhere once you have.

## Splicing

1. **Take a cutting.** Aim at a growing crop, a sapling or a tree and press **G**. The cutting goes into your satchel (six at most). One cutting per plant per day; a cutting wilts after two dawns.
2. **Graft it.** Aim at a crop, sapling or tree **you planted** and press **G** again. Crop cuttings take on crops and on trees; tree cuttings take on trees, never on a crop. A plant cannot take a graft of its own kind.
3. **Wait for dawn.** At 06:00 in game (sleeping through it counts) the graft takes or is rejected. Your first graft always takes; after that the chance is about 60%, better the further you are above the cutting's level and worse when a crop is grafted onto a weaker host.
4. **The hybrid.** A graft that takes changes the plant you can see, and the first of each pairing enters your **Discovery Catalogue**.
5. **Harvest it.** Hybrid trees can be picked once a day (aim and press G). A hybrid crop adds the cutting's crop to its normal harvest. Felling a hybrid tree ends it, with a last handful.

Tree cuttings need a logging axe in your hand that could fell that tree, as the game asks when you chop it: stone for ash, bronze for oak, iron for willow.

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
| Tuberwood Ash | Potato onto ash | 5 | 3 potatoes a day, from the roots |
| Brassitato | Cabbage onto potato | 5 | 2 cabbages with the potato harvest |
| Brassica-Oak | Cabbage onto oak | 8 | 3 cabbages a day, from the canopy |
| Sheaf Ash | Wheat onto ash | 10 | 4 wheat a day |
| Weeping Oak | Willow onto oak | 20 | willow and oak wood every day |

Three more are waiting to be found, and every other pairing makes a hybrid of its own with a tint, a scale and a catalogue line.

## Training

| Action | XP |
|--------|----|
| Take a cutting | 8 |
| Make a graft | 20 |
| A graft takes / is rejected | 45 / 10 |
| A new hybrid (first time each pairing) | +50 |
| A new flagship hybrid | +200 |
| Pick from a hybrid tree (once a day) or harvest a hybrid crop | 25 |
| Reading the Observances | 33, once |

Ordinary farming still pays a little: sowing 10, watering 5, composting 10, weeding 3, curing 13, harvesting 23, and +17 / +33 for the first sowing and first harvest of each kind of crop. With eight plots and a few planted trees, level 25 takes four to six in-game days.

## Discovery Catalogue

End shows your satchel, the hybrids you have found and the **Vanilla Plants** section: the first harvest of each of the game's 24 crops.

## Keys

| Key | Does |
|-----|------|
| G | Aim at a plant: picks from a hybrid when it is ready, grafts your selected cutting onto a plant you grew, otherwise takes a cutting |
| Ctrl+G | Always takes a cutting from what you aim at |
| Shift+G | Selects the next cutting in your satchel |
| End | Shows Horticulture's level, XP, satchel and Discovery Catalogue, or what is still needed to unlock it |
| Shift+End | Rereads the Observances of Brassica Prime |

The first run writes `config.txt` next to `enabled.txt`:

| Setting | Default | Does |
|---------|---------|------|
| `status_key` | `END` | The key above, by its UE4SS key name (for example `PAGE_DOWN` or `NUM_ZERO`). Shift with the same key rereads the book. |
| `action_key` | `G` | The splicing key, by its UE4SS key name. Ctrl and Shift with it take a cutting and select the next one. |
| `quiet` | `false` | `true` drops Horticulture's own cards (cuttings, grafts, the catalogue, the unlock reminder); XP and level-ups still show. |
| `debug` | `false` | `true` writes every XP award to the UE4SS log. |

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
