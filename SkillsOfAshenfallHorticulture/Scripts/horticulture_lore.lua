-- The Brassica Prime book: fan-written mod lore, not Jagex canon. Claims and
-- sources are listed in the Dragonwilds docs, LORE_VERIFICATION.md.
local Lore = {}

-- Shown on the world prompt, and on the popup until the reader can make out
-- the second script.
Lore.PROMPT_NAME = "Annotated Hymnal"

Lore.TITLE = "Observances of Brassica Prime"

-- One line, in the pattern of the game's own tome descriptions.
Lore.DESCRIPTION = "A hymnal to Saradomin, with an older text about cabbages written between the lines."

Lore.BODY = table.concat({
    "Set down by Kalestix, once of the circle, now of the cabbage patch.",
    "The First Observance. On the moors, beneath a moonlit waterfall, our lord taught Guthix the secrets of a balanced diet. The druids were told to sow cabbage around every settlement, and they did. Not one of them asked the cabbage what it wanted.",
    "I asked. It wants to be eaten, so that its seed may travel. So save the seed: dry it on the hearthstone, label the jar, and keep it from the mice.",
    "The Second Observance. Lay the pollen of the hardiest plant upon the flower of the sweetest. Their children will be hardy, or sweet, or neither. Write down which. Our lord delights in difference, but the soil does not forgive a poor memory.",
    "The Third Observance. A cutting bound to a living root will take, as a guest takes to a good table. The root gives strength; the cutting gives fruit. My old circle called this meddling. I call it introductions.",
    "The Fourth Observance. Feed the soil before you ask anything of it. Ash, dung and patience. Mostly patience.",
    "Other gods hoard their secrets. Ours wants them shared, so I have written these between the lines of a hymnal, in the old druid hand. The priests burn our pages. No priest reads the spaces.",
    "The Fifth Observance. Do not make the wine.",
}, "\r\n\r\n")

-- What a reader below Historian 25 sees.
Lore.LOCKED_BODY = table.concat({
    "Hymns to Saradomin, copied in a careful hand.",
    "Between the lines runs a second script, smaller and much older, that you cannot yet make sense of. Whoever wrote it pressed hard, as if they meant every word.",
    "Someone has drawn a cabbage in the margin. Several cabbages.",
}, "\r\n\r\n")

return Lore
