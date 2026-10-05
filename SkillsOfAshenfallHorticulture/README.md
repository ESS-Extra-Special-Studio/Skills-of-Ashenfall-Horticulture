# Skills of Ashenfall: Horticulture

A new skill for RuneScape: Dragonwilds, levels 1 to 25. Coax new things out of old seed: save it, cross it, graft it and feed the soil.

Horticulture is the second Skills of Ashenfall skill. It is hidden until you earn it.

## Requires

- ESL:DragonWilds 1.1.0 or later (Required Dependency)
- Skills of Ashenfall: Historian 1.0.0 or later (Required Dependency)
- UE4SS for RuneScape: Dragonwilds

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

## Unlocking Horticulture

1. Reach Historian 25 and Farming 25.
2. Find the **Annotated Hymnal** by the wild cabbage patch north-west of the Wise Old Man in Bramblemead Valley, where his farming lessons begin.
3. Read it. Below Historian 25 the second script between its lines cannot be made out.

Horticulture then appears in your skills menu and on the character select screen, and the reading itself takes you to level 2. The hymnal stays where it is, so you can read it again; Shift+End also rereads it anywhere once you have.

## Training

Everything you do to a crop pays XP when the plot actually changes, so a failed attempt pays nothing.

| Action | XP |
|--------|----|
| Sow a seed | 30 |
| Water (once per growth stage of each sowing) | 15 |
| Compost (once per sowing) | 30 |
| Clear weeds | 10 |
| Cure blight | 40 |
| Harvest | 70 |
| First sowing of each kind of crop | +50 |
| First harvest of each kind of crop (Discovery Catalogue) | +100 |

With eight plots and four kinds of crop, level 25 arrives around the second harvest.

## Discovery Catalogue

The first time you harvest each kind of crop, it is entered in your Discovery Catalogue, with a card and bonus XP. There are 24 crops to catalogue. End shows the catalogue so far.

## Keys

| Key | Does |
|-----|------|
| End | Shows Horticulture's level, XP and Discovery Catalogue, or what is still needed to unlock it |
| Shift+End | Rereads the Observances of Brassica Prime |

The first run writes `config.txt` next to `enabled.txt`:

| Setting | Default | Does |
|---------|---------|------|
| `status_key` | `END` | The key above, by its UE4SS key name (for example `PAGE_DOWN` or `NUM_ZERO`). Shift with the same key rereads the book. |
| `quiet` | `false` | `true` drops the Discovery Catalogue card and the unlock reminder after reading; XP and level-ups still show. |
| `debug` | `false` | `true` writes every XP award to the UE4SS log. |

End was chosen because F10 opens the console with ConsoleEnabler, Home belongs to the ESL example skill, and F5 to F9 are taken by Historian and the HUD mod.

## Multiplayer

- Each player's Horticulture is their own, kept with their character.
- The hymnal is placed separately on each player's machine and is never saved into the world.
- Playing alone or as host: farming pays only for your own work.
- As a guest: farming pays for plots within reach of your character, since the host's game runs the farming.

## Lore

**MOD LORE.** The Observances of Brassica Prime are fan-written, not Jagex canon. What the book leans on comes from Dragonwilds' own journal: Brassica Prime, Guthix and the druids sowing cabbage across Ashenfall, the fried cabbage, the failed cabbage wine, and a Guthixian druid's memoir of how this land changes things. The author, the scraped hymnal and the Observances themselves are invented for this mod.

## Progress

Your Horticulture progress is kept with the game's saved data by ESL:DragonWilds, as `<Character>.Horticulture.txt` in `%LOCALAPPDATA%\RSDragonwilds\Saved\ESLDragonWilds`. Updating or reinstalling the mod does not touch it.

## Not affiliated

Skills of Ashenfall is a fan project by Extra Special Studio. It is not affiliated with, endorsed by, or sponsored by Jagex Ltd. RuneScape and RuneScape: Dragonwilds are trademarks of Jagex Ltd. See LICENSE.
