-- The Brassica Prime book: MOD LORE, fan-written, not Jagex canon. Every
-- claim and its source (Dragonwilds canon only) is listed in the Dragonwilds
-- docs, LORE_VERIFICATION.md.
local Lore = {}

-- Shown on the world prompt, and on the popup until the reader can make out
-- the older script.
Lore.PROMPT_NAME = "Annotated Hymnal"

Lore.TITLE = "Observances of Brassica Prime"

-- One line, in the pattern of the game's own tome descriptions.
Lore.DESCRIPTION = "A hymnal to Saradomin, written over an older text about cabbages that was not scraped away quite well enough."

local P = "\r\n\r\n"

-- Three leaves. Leaf I ties to the canon Druid's Memoirs (LoreScrap_C2):
-- the land "takes something and twists it", paraphrased, not quoted.
Lore.LEAVES = {
    {
        title = "The First Leaf",
        body = table.concat({
            "Set down by Kalestix, once of the circle, now of the cabbage patch.",
            "On the moors, beneath a waterfall in the moonlight, our lord met Guthix and told him the secret of a balanced diet. Guthix listened. The druids were sent to sow cabbage in every field and round every settlement, and we did. Not one of us asked the cabbage what it wanted.",
            "I asked. It wants to be eaten, so that its seed may travel. That is the whole of the First Observance: save the seed. Dry it on the hearthstone, label the jar, and keep it from the mice.",
            "One of the first of us, who walked beside Guthix, wrote that this land takes a thing and makes it different, and wondered whether it would one day do the same to us. Our lord never wondered. He asked the land to do it on purpose, and to start with cabbages.",
        }, P),
    },
    {
        title = "The Second Leaf",
        body = table.concat({
            "The Second Observance. Lay the pollen of the hardiest plant on the flower of the sweetest. Their children will be hardy, or sweet, or neither. Write down which. Our lord delights in difference, but the soil does not forgive a poor memory.",
            "The Third Observance. A cutting bound to a living root will take, as a guest takes to a good table. The root lends strength, the cutting brings fruit, and the twine keeps them civil until they are friends. My old circle called this meddling. I call it introductions.",
            "The Fourth Observance. Feed the soil before you ask anything of it. Ash, dung and patience. Mostly patience.",
        }, P),
    },
    {
        title = "The Third Leaf",
        body = table.concat({
            "Other gods keep their secrets close. Ours wants his shared, and is happiest when someone enjoys a cabbage. He taught the first settlers to fry them, and was prouder of that than any god has been of a temple.",
            "The circle is gone, and the valley sings other hymns now. Vellum is dear, so the new priests scrape old pages clean and write over them. They scraped this one. They did not scrape it well. If you can read these words beneath their hymns, you have a historian's eye, and our lord would like a word with you about cabbages.",
            "The Fifth Observance. Do not make the wine.",
        }, P),
    },
}

local parts = {}
for i, leaf in ipairs(Lore.LEAVES) do
    parts[#parts + 1] = (i > 1 and "~\r\n\r\n" or "") .. leaf.body
end
-- The whole book in one popup.
Lore.BODY = table.concat(parts, P)

-- One leaf per reading instead, if the popup cannot scroll the whole book.
Lore.SPLIT_LEAVES = false

function Lore.Leaf(i)
    local leaf = Lore.LEAVES[((i - 1) % #Lore.LEAVES) + 1]
    return Lore.TITLE .. ": " .. leaf.title, leaf.body
end

-- What a reader below Historian 25 sees.
Lore.LOCKED_BODY = table.concat({
    "Hymns to Saradomin, copied in a careful hand onto a page that was scraped and used again.",
    "Beneath them, faint as a watermark, runs an older script that you cannot yet make sense of. Whoever wrote it pressed hard, as if they meant every word.",
    "Someone has drawn a cabbage in the margin. Several cabbages.",
}, P)

return Lore
