-- Mini Brassica Prime voice data: personalities, line pools, triggers and
-- how often they talk. Pure data, no game calls; read by
-- horticulture_primelet_talk.lua.
--
-- MOD LORE: fan-written, not Jagex canon. Lines tagged src = "rs3" lean on
-- mainland RuneScape lore and are dropped when ALLOW_MAINLAND is false.
--
-- A line is a string, or a table:
--   { "text", min_level =, max_level =, minis =, max_minis =, catalogue =,
--     flagships =, hint_tier =, item =, plant =, god =, when =, once = true,
--     w = weight (default 1), src = "rs3" }
-- Tokens: {name} this Mini's name, {other} the other Mini's name,
--   {item} the food's display name, {plant} the plant's display name,
--   {catalogue} catalogue count, {minis} grown Minis owned.
local V = {}

V.VERSION = 1

-------------------------------------------------------------------------------
-- Settings the implementer exposes or keeps internal
-------------------------------------------------------------------------------

-- The only player-facing setting. Goes in config.txt as primelet_chattiness.
-- Its help text says only how often they talk.
V.CHATTINESS_DEFAULT = "normal"
V.CHATTINESS = {
    -- gap_mult scales every cooldown; ambient_mult scales unprompted chances.
    off     = { gap_mult = math.huge, ambient_mult = 0 },   -- talk/tend replies only
    quiet   = { gap_mult = 2.0, ambient_mult = 0.35 },
    normal  = { gap_mult = 1.0, ambient_mult = 1.0 },
    chatty  = { gap_mult = 0.6, ambient_mult = 1.6 },
}

-- Internal switch, not in config.txt.
V.ALLOW_MAINLAND = true

-------------------------------------------------------------------------------
-- Frequency and annoyance rules (seconds are real seconds, cm are UE units)
-------------------------------------------------------------------------------

V.TIMING = {
    hearing_radius_cm   = 1200,  -- a Mini only speaks if the player is this close
    ambient_radius_cm   = 800,   -- unprompted lines need the player this close
    talk_radius_cm      = 260,   -- matches Primelet.REACH
    global_gap_s        = 30,    -- at most one line from any Mini per 30 s
    per_mini_gap_s      = 150,   -- the same Mini waits this long between lines
    event_overlap_s     = 4,     -- even event lines never overlap a bubble on screen
    ambient_poll_s      = 20,    -- how often unprompted triggers are checked
    ambient_chance      = 0.12,  -- per poll, per eligible Mini, before gap checks
    no_repeat_mini      = 12,    -- a Mini never repeats one of its last 12 lines
    no_repeat_global    = 30,    -- no line is reused by any Mini within 30 lines
    bicker_gap_s        = 600,   -- one two-Mini exchange per 10 minutes
    bicker_pair_cm      = 450,   -- two Minis this close can bicker
    exchange_pause_s    = 2.2,   -- delay before the second line of an exchange
    item_gap_s          = 1200,  -- same cabbage food remarked on once per 20 min
    cooking_gap_s       = 300,   -- once per 5 min while the player cooks nearby
    plant_gap_s         = 900,   -- a given neighbour plant insulted once per 15 min
    weather_gap_s       = 1800,
    hint_gap_s          = 1500,  -- cryptic ring hints: at most one per 25 min
    ring_idle_gap_s     = 180,   -- while a ring stands, one idle line per 3 min
    ring_roast_gap_s    = 600,   -- re-forming the same ring repeats a roast after 10 min
    low_health_frac     = 0.25,
    low_health_gap_s    = 600,
    returned_real_days  = 3,     -- real days since the last session
    returned_game_days  = 10,    -- or this many in-game dawns unseen
    quiet_at_night      = false, -- Dragonwilds nights are about 5 of 24 minutes
    night_ambient_mult  = 0.5,   -- used only if quiet_at_night is true
}

-- Bubble on-screen time: base + per character, clamped.
V.BUBBLE = { base_s = 3.0, per_char_s = 0.055, min_s = 3.0, max_s = 8.0 }

-- Highest first. A pending trigger of higher priority replaces a lower one
-- in the same poll. Event triggers ignore global_gap_s but not event_overlap_s.
V.PRIORITY = {
    "ring_complete",
    "ring_progress",     -- closer / colder / nearly
    "death",
    "low_health",
    "returned",
    "first_words",       -- stage up to Mini Brassica Prime
    "potted",
    "placed_home",
    "picked_up",
    "talk",
    "tended",
    "cabbage_food",
    "cooking",
    "bicker",
    "plants",
    "accomplishment",
    "level",
    "hint",
    "gods",
    "time",
    "ignored",
    "ambient",
}

V.EVENT_TRIGGERS = {
    ring_complete = true, ring_progress = true, death = true,
    returned = true, first_words = true, potted = true, placed_home = true,
    picked_up = true, talk = true, tended = true,
}

-- What a talk (E / interact) draws from: pool name -> weight. Pools that have
-- no eligible line for the current state drop out.
V.TALK_MIX = {
    talk = 10, level = 2, accomplishment = 2, gods = 2, hint = 2, time = 1,
}

-- Unprompted (ambient) mix when no specific trigger is pending.
V.AMBIENT_MIX = {
    talk = 6, gods = 2, time = 2, hint = 2, level = 1, accomplishment = 1,
}

-------------------------------------------------------------------------------
-- Stages (ids match horticulture_primelet.lua STAGES)
-------------------------------------------------------------------------------

-- speaks: false = narrated lines only (journal narrator, third person).
V.STAGES = {
    sprout    = { speaks = false, shows_personality = false, display = "Primelet Sprout" },
    primelet  = { speaks = false, shows_personality = true,  display = "Brassica Primelet" },
    primeling = { speaks = true,  shows_personality = true,  display = "Mini Brassica Prime" },
}

V.SPROUT_TRAIT = "Too young to have opinions. Give it a day or two."

-------------------------------------------------------------------------------
-- Horticulture level bands.
-------------------------------------------------------------------------------

V.LEVEL_BANDS = {
    { id = "novice",     min = 1,  max = 9 },
    { id = "apprentice", min = 10, max = 19 },
    { id = "journeyman", min = 20, max = 25 },
    { id = "adept",      min = 26, max = 49 },
    { id = "expert",     min = 50, max = 74 },
}

-------------------------------------------------------------------------------
-- Hint lines open up with grown Minis owned (all worlds, this character)
-------------------------------------------------------------------------------

V.HINT_TIERS = {
    { tier = 1, minis = 3 },   -- first cryptic lines
    { tier = 2, minis = 4 },   -- pointed lines, ring exchanges
    { tier = 3, minis = 5 },   -- geometry hints; enough Minis to try
}

-------------------------------------------------------------------------------
-- Arrangement: where potted Minis stand relative to each other.
-------------------------------------------------------------------------------

V.ARRANGE = {
    size                 = 5,
    members_must_be      = { stage = "primeling", potted = true, carried = false },
    same_world           = true,
    floor_z_spread_cm    = 60,    -- max height difference between any two members
    radius_min_cm        = 150,
    radius_max_cm        = 400,
    radius_tolerance     = 0.20,  -- each member within +-20% of the mean radius
    radius_floor_cm      = 25,    -- the tolerance is never tighter than this
    angle_step_deg       = 72,
    angle_tolerance_deg  = 15,    -- each gap 57..87 degrees
    near_angle_deg       = 30,    -- "nearly" lines: within this but not the above
    near_radius_tol      = 0.35,
    centre_clear_frac    = 0.5,   -- no other Mini or pot within 0.5 x radius of centre
    player_centre_frac   = 0.35,  -- player this close to centre counts as "in the middle"
    max_pair_distance_cm = 850,   -- members may not be further apart than this
    require_indoors      = false, -- roof trace above the centre; turn on once verified
    indoors_trace_cm     = 1000,
    turn_to_centre       = true,  -- on completion every member yaws to face the centre
    turn_stagger_s       = 0.35,  -- one after another, in angular order
    check_on             = { "placed", "picked_up", "stage_up" },  -- never polled per frame
    progress_min_members = 3,     -- fewer than 3 fitting Minis gives no progress line
}

-------------------------------------------------------------------------------
-- Cabbage-based food the player may carry (Dragonwilds display names)
-------------------------------------------------------------------------------

-- Match on the item's display name first; id_hint is a lowercase substring
-- for the internal id where known (ITEM_Resources_Cabbage is confirmed in our
-- pak scans; the rest are unverified and must be checked in the build).
V.CABBAGE_FOODS = {
    { name = "Cabbage",                     id_hint = "resources_cabbage", kind = "raw" },
    { name = "Cabbage Seeds",               id_hint = "seed_cabbage",      kind = "seeds" },
    { name = "Fried Cabbage",               id_hint = "cabbage_fried",     kind = "fried" },
    { name = "Burnt Cabbage",               id_hint = "burnt",             kind = "burnt" },
    { name = "Vegetable Soup",              kind = "dish" },
    { name = "Vegan Fryup",                 kind = "dish" },
    { name = "Sweet Veg Ball",              kind = "dish" },
    { name = "Forager's Sandwich",          kind = "dish" },
    { name = "Pungent Omelette",            kind = "dish" },
    { name = "Mushroom Kebab",              kind = "dish" },
    { name = "Pumpkin Soup",                kind = "dish" },
    { name = "Beltfish Broth",              kind = "dish" },
    { name = "Stuffed Catfish",             kind = "dish" },
    { name = "Fish Fry",                    kind = "dish" },
    { name = "Weak Focused Cooking Potion", kind = "potion" },
    { name = "Focused Cooking Potion",      kind = "potion" },
}

-- Cooking stations that count as "cooking nearby" (display names).
V.COOKING_STATIONS = { "Campfire", "Grill", "Stone Range", "Cooking Range" }
V.COOKING_RADIUS_CM = 1500

-- Neighbour plants worth insulting (display names, ours and vanilla).
V.NEIGHBOUR_RADIUS_CM = 600

-------------------------------------------------------------------------------
-- Personalities
-------------------------------------------------------------------------------

-- Rolled once, when the Primelet is created. weight is the base chance;
-- owned_damping multiplies the weight of each personality the character
-- already owns (per copy), so a collection drifts towards variety.
V.ROLL = { owned_damping = 0.5 }

V.ORDER = { "pompous", "curious", "grumpy", "dramatic", "scholarly", "unhinged" }

V.P = {}

-------------------------------------------------------------------------------
V.P.pompous = {
    label  = "Pompous",
    weight = 20,
    trait  = "Believes it is royalty. Nobody has told it otherwise, and you are not going to be the first.",
    names  = { "Lord Savoy", "Baron Crinkleton", "Duchess Heartleaf", "Sir Brassington",
               "Lady Coleworth", "Viscount Ruffleby", "Archduke Leafric" },

    primelet = {
        "The Primelet has arranged its outer leaves into something like a ruff. It appears to be waiting for applause.",
        "It sits up a little straighter whenever you look at it.",
        "The Primelet has positioned itself so that the light falls on it just so.",
    },

    first_words = {
        { "At last. A voice befitting the leaves.", once = true },
        { "You may address me as 'Your Leafiness'. Practise. I'll wait.", once = true },
    },

    talk = {
        "You may approach. Slowly. Mind the leaves.",
        "Guthix himself was struck dumb by my ancestor's magnificence. You may be mildly impressed by mine.",
        "The druids planted cabbage round every settlement on this island. In our honour. You're welcome.",
        "I have been told I have a regal bearing. By me. Just now.",
        "A pot is not a prison. A pot is a throne with drainage.",
        "Kneel. No? Crouch, then. Crouching is kneeling for the indecisive.",
        "Do not call me a cabbage. I am a Brassica. The difference is breeding.",
        "My forebear once spent an entire night explaining nutrition to a god. The god nodded throughout. They do that when they're out of their depth.",
        "You have two leaves and you wave them about constantly. Have some dignity.",
        "I was born in a vegetable plot. So, in fairness, was every king worth the name.",
        "One does not 'water' royalty. One offers refreshment.",
    },

    tended = {
        "Ah. Tribute.",
        "Adequate. Next time, from a nicer bucket.",
        "Water. How thoughtful. I would have accepted gold.",
        "Do mind the crown.",
    },

    ignored = {
        { "Two days. In some courts that is treason. In mine it is merely noted.", when = 2 },
        { "I have begun drafting your exile. It is mostly adjectives.", when = 4 },
        { "I forgive you. Publicly. It is important that people see me being gracious.", when = 7 },
    },

    potted = {
        "Finally, furniture worthy of me.",
        "Terracotta. Humble. It makes me look taller.",
    },

    placed_home = {
        "The house will do. Move the onion.",
        "Where is the throne room? This is the throne room? Ah. Well. We shall grow into it.",
    },

    picked_up = {
        "Unhand me! Gently! GENTLY!",
        "I am being moved by staff. This is normal. This is fine.",
        "A royal progress. Wave to the peasants for me.",
    },

    level = {
        { "Ah, an apprentice. How sweet. Do you know which end the leaves go?", max_level = 9 },
        { "You are improving. Not quickly, but in the right direction, which is more than most courtiers manage.", min_level = 10, max_level = 19 },
        { "Respectable work. I shall mention you in my memoirs. In a footnote. A large footnote.", min_level = 20, max_level = 25 },
        { "One day you may be worthy of an audience with someone more important than me. There is exactly one such person.", min_level = 20, hint_tier = 1 },
    },

    cabbage_food = {
        "You are carrying a commoner. A deceased commoner. In my house.",
        "Is that {item}? In the presence of royalty?",
        "Put my cousin down. Then wash.",
    },

    cooking = {
        "I hear sizzling. I am choosing to believe it is applause.",
        "Every great dynasty has its enemies. Ours wear aprons.",
    },

    plants = {
        "The {plant}. Common. Thoroughly common.",
        "Tell the {plant} it may not look at me directly.",
    },

    gods = {
        { "Saradomin? We are not on speaking terms. He knows what he did. Nine of what he did.", god = "saradomin", src = "rs3" },
        { "You sleep in Saradomin's temple. I sleep in a pot. One of us has the moral high ground, and it is the one with drainage.", god = "saradomin" },
        { "Guthix was a dear friend of the family. He did most of the listening.", god = "guthix" },
        "The gods are banished, I hear. More room for the rest of us.",
    },

    time = {
        { "Dawn. My subjects rise. Which of them is you? Ah.", when = "dawn" },
        { "Even royalty must rest. Stop looking at me.", when = "night" },
        { "Rain. The sky, at last, attending to its duties.", when = "rain" },
    },

    returned = {
        "You were gone a long time. I ruled in your absence. Nothing happened. It was glorious.",
    },

    low_health = {
        "You look dreadful. Please do it somewhere other than the throne room.",
    },

    death = {
        "You died. I held a moment's silence. It was a short moment.",
    },

    accomplishment = {
        { "Another of us? Splendid. Somebody must be my audience.", minis = 2 },
        { "Ten plants catalogued. You have practically founded a court.", catalogue = 10 },
        { "Five grand hybrids. One day they will be remembered as 'the ones before me'.", flagships = 5 },
    },

    hint = {
        { "Five leaves make a crown. I would know.", hint_tier = 1 },
        { "A court needs five. A throne needs one. Arithmetic is a royal art.", hint_tier = 2 },
        { "I would look so much better facing inwards. We all would. Think on it.", hint_tier = 3 },
    },

    closer = {
        "Closer... Yes. Arrange your betters.",
    },

    colder = {
        "No. Put it back. I was beginning to feel regal.",
    },

    nearly = {
        "Almost. One of us is slouching, and it is not me.",
    },

    complete = {
        "Nice arrangement. Shame about the horticulturist.",
        "The Prime has standards, you know.",
        "Perhaps try being more... cultivated.",
        "We are assembled. You are... also here.",
        "The court is in session. The petitioner is underdressed.",
    },
}

-------------------------------------------------------------------------------
V.P.curious = {
    label  = "Curious",
    weight = 20,
    trait  = "Wants to know what everything is, especially the things that are on fire.",
    names  = { "Tiddler", "Whorl", "Sprig", "Nubbin", "Fidget", "Quibble" },

    primelet = {
        "The Primelet leans towards anything that moves, including, briefly, a bee.",
        "It has turned to watch the door. It does that a lot.",
        "It rustles every time you put something down, as if asking what it is.",
    },

    first_words = {
        { "Oh! Oh, I can talk! What's talking? Am I doing it?", once = true },
        { "Hello! What are you? Is everyone a you?", once = true },
    },

    talk = {
        "Why do you only have one face? Is the other one in the wash?",
        "What's 'fried'? Everyone goes quiet when I ask.",
        "Where do you go when you go through the door? Is it more door?",
        "Someone told me the sun is a cabbage. Is it? It's very round.",
        "How many legs is the right number of legs? I've got none, and I'm managing.",
        "If a little cabbage is a Primelet, is a little person a... personlet?",
        "Why does the soup smell like my cousins? Don't tell me. Do tell me. No, don't.",
        "Have you met a dragon? Were they nice? Are they edible? Am I?",
        "Somebody wrote 'yuck' on all the cabbages. Is 'yuck' a nice word?",
        "What do you do all day? Apart from watering me. I assume that's the main thing.",
        "Do onions dream? This one keeps twitching.",
    },

    tended = {
        "Water! What is it? Why is it wet? Thank you!",
        "Is this the same water as yesterday? It tastes newer.",
        "You came back! Did you go anywhere interesting? Tell me everything. Start with the water.",
    },

    ignored = {
        { "Did you forget me? I counted the sunrises. I got to two. Then I forgot what comes after two.", when = 2 },
        { "I asked the onion where you were. It doesn't know either. It doesn't know anything. It's an onion.", when = 4 },
        { "I've thought very hard about where you've been. I've decided you're a pirate.", when = 7 },
    },

    potted = {
        "A pot! Is it a hat? Am I wearing it upside down?",
        "It's round! Like me! Are we related?",
    },

    placed_home = {
        "Is this your house? Is it my house? Can it be both?",
        "What's that? And that? What does that one do? Is it hot?",
    },

    picked_up = {
        "Whee! Where are we going? Is it far? Is it up?",
        "Am I flying? Is this flying? Tell me if this is flying.",
    },

    level = {
        { "Are you good at plants? You look like you're a bit good at plants.", max_level = 9 },
        { "You've got better at plants! I can tell, because fewer of them are crying.", min_level = 10, max_level = 19 },
        { "You know so much! Do you know what's at the end? Of plants, I mean. Is there an end?", min_level = 20, max_level = 25 },
        { "Someone said you have to be really, really good at plants to meet Him. Are you really, really good? You're really good. Are you?", min_level = 10, hint_tier = 1 },
    },

    cabbage_food = {
        "What's that in your pocket? It smells like Grandma.",
        "Is that {item}? What's in it? ...What ELSE is in it?",
        "Why are you carrying that? Is it a friend? Is it a SLEEPING friend?",
    },

    cooking = {
        "What's that smell? Is it a happy smell? Why are you looking at me like that?",
        "Can I watch you cook? From very, very far away?",
    },

    plants = {
        "Is the {plant} my friend? It won't say. It's either rude or a plant.",
        "What's the {plant} for? Is it for eating? Is everything for eating? Am I?",
    },

    gods = {
        { "Who's Saradomin? Why does everyone whisper when I say Saradomin? SARADOMIN.", god = "saradomin" },
        { "Is Guthix nice? Grandleaf says he listened a lot. Is listening a kind of talking?", god = "guthix" },
        { "Why did the war god run away from a dragon? Was it a big dragon? Is there always a bigger dragon?", god = "bandos" },
    },

    time = {
        { "It's tomorrow! Again!", when = "dawn" },
        { "Where does the light go? Does it get a bed?", when = "night" },
        { "The sky is watering me! Did you ask it to? Thank you, sky!", when = "rain" },
    },

    returned = {
        "You're back! I kept a list of questions. I've forgotten the list. First question: what's a list?",
    },

    low_health = {
        "You're leaking. Is that normal for people? Should I water you?",
    },

    death = {
        "You went away all at once and came back somewhere else! Can you teach me?",
    },

    accomplishment = {
        { "There's another one of me! Is it me? It says it isn't. It would say that.", minis = 2 },
        { "You've written down lots of plants! Am I in the book? Under 'B'? For 'Best'?", catalogue = 5 },
        { "That's {minis} of us now! Is that a lot? It feels like a lot. It feels like a number.", minis = 4 },
    },

    hint = {
        { "Why do I keep dreaming about circles? Five of us, round and round. Do you dream in circles?", hint_tier = 1 },
        { "Someone said five roots make a throne. What's a throne? Does it have roots?", hint_tier = 2 },
        { "If we all stood in a ring, could we all see each other at once? Can we try? Can we try now?", hint_tier = 3 },
    },

    closer = {
        "Ooh. Ooh! Something's tingly. Do that again.",
        "Warmer? I feel warmer. Is this a game? Am I winning?",
    },

    colder = {
        "Oh. The tingly stopped. Why did the tingly stop?",
    },

    nearly = {
        "Nearly! I don't know what, but nearly!",
    },

    complete = {
        "Grow first. Questions later.",
        "Is something supposed to happen? It feels like something's supposed to happen. Is it you? Is it supposed to be you?",
        "The others say you're small. On the inside. Are you small on the inside?",
    },
}

-------------------------------------------------------------------------------
V.P.grumpy = {
    label  = "Grumpy",
    weight = 20,
    trait  = "Disapproves of the weather, the soil, the neighbours and you, roughly in that order.",
    names  = { "Old Stalk", "Gristle", "Crabbage", "Mildred", "Bitterleaf", "Stodge", "Wilt" },

    primelet = {
        "The Primelet has turned its back on the onions. Pointedly.",
        "It rustles when you approach, in a tone.",
        "It has shed a leaf in your direction. You are fairly sure it was aimed.",
    },

    first_words = {
        { "Oh, wonderful. A mouth. Now I can tell you.", once = true },
        { "Five days I've been waiting to say this. Your watering can leaks.", once = true },
    },

    talk = {
        "What.",
        "I was having a perfectly good photosynthesis until you came over.",
        "Don't stand there. You're blocking the sun. All of it. Somehow.",
        "I've read what they write on cabbages. 'Yuck.' Charming. Very charming.",
        "I'm nine days old and things were better when I was younger.",
        "Sit there, they said. Look decorative, they said. Nobody asked me.",
        "Every cabbage on this island was planted to honour Brassica. Do you see anyone honouring me? I see an onion.",
        "Leave me alone. No, not that alone.",
        "If you're going to stare, at least water something.",
        "Back in my day we had soil. Proper soil. You could lose a boot in it.",
        "Don't tell me it's a nice day. I'll decide that.",
    },

    tended = {
        "Too much.",
        "Not enough.",
        "That'll do. Don't let it go to your head.",
        "You missed a leaf. The important one.",
    },

    ignored = {
        { "Oh. It's you. Thought you'd been eaten.", when = 2 },
        { "Four days. Not that I was counting. Ninety-six hours. Not that I was counting.", when = 4 },
        { "I've decided I prefer it when you're not here. It's quieter. Don't go.", when = 7 },
    },

    potted = {
        "A pot. Lovely. Now I can't leave.",
        "This pot's too small. That's not a complaint. That's a fact I'll be repeating.",
    },

    placed_home = {
        "Draughty.",
        "Who decorates like this? Don't answer. It was you.",
    },

    picked_up = {
        "Put me down. Put me DOWN.",
        "If you drop me I'm telling everyone.",
    },

    level = {
        { "You don't know what you're doing. That's fine. Nobody does. You, more than most.", max_level = 9 },
        { "Better. Still bad. But better bad.", min_level = 10, max_level = 19 },
        { "You're competent. Don't make that face. It's not a compliment, it's an observation.", min_level = 20, max_level = 25 },
        { "You'll need to be a lot better than this to impress Him. He's not easily impressed. He's a cabbage.", min_level = 10, hint_tier = 1 },
    },

    cabbage_food = {
        "That's Gerald. In your bag. I knew Gerald.",
        "{item}. Of course. Why not eat it in front of me. Go on.",
        "Wash your hands before you touch me. I can smell what you've done.",
    },

    cooking = {
        "Here we go.",
        "Don't think I can't hear that pan.",
        "Cooking. Gardening, for people who can't wait.",
    },

    plants = {
        "The {plant}. Loud. Never shuts up.",
        "Who planted the {plant} next to me? Who?",
        "The onion's looking at me again.",
    },

    gods = {
        { "Saradomin. Nine of us, in a monastery garden, and he didn't even look down. Don't get me started.", god = "saradomin", src = "rs3" },
        { "Zamorak thinks we're a trick. Good. Let him worry.", god = "zamorak", src = "rs3" },
        { "Bandos ran from one dragon. I've had cooks look at me with more fire than that.", god = "bandos" },
    },

    time = {
        { "Morning. Unfortunately.", when = "dawn" },
        { "It's dark. I can't see you. Best part of the day.", when = "night" },
        { "Rain. Of course. Water me, don't water me, the sky can't decide either.", when = "rain" },
    },

    returned = {
        "Look who it is. Everything died while you were gone. Not me. Everything else. Probably.",
    },

    low_health = {
        "You look worse than the onion. And the onion's an onion.",
    },

    death = {
        "Died, did you? Typical. Leave a cabbage to fend for itself.",
    },

    accomplishment = {
        { "Another one. Marvellous. More of us to be disappointed together.", minis = 2 },
        { "Catalogued another plant, have you. Did you ask it first? No.", catalogue = 5 },
        { "All right. The hybrids are good. Don't make me say it twice.", flagships = 8 },
    },

    hint = {
        { "Five of us in a ring, and we'd finally all be facing the same way. Wouldn't that be nice. For once.", hint_tier = 1 },
        { "Five roots make a throne. Don't ask me. Ask the floor.", hint_tier = 2 },
        { "We're all over the place. Literally. Somebody tidy us up. Round.", hint_tier = 3 },
    },

    closer = {
        "Warmer. Don't get excited.",
        "Closer... ugh. I said that out loud.",
    },

    colder = {
        "Colder. Well done. Genius.",
    },

    nearly = {
        "So close it's annoying. Which is the worst kind.",
    },

    complete = {
        "We're ready. You're the problem.",
        "There are enough of us. There isn't enough of you.",
        "Lovely circle. Shame you're not ready for it.",
        "We did our bit. Five pots, nice and round. You do yours.",
    },
}

-------------------------------------------------------------------------------
V.P.dramatic = {
    label  = "Dramatic",
    weight = 18,
    trait  = "Every watering is a reunion. Every onion is a betrayal.",
    names  = { "Brassandra", "Ophelia Leafwright", "Dame Crinkle", "Savoyetta", "Lettice",
               "Valentine Leafe", "Lady Crumple" },

    primelet = {
        "The Primelet wilts theatrically when you leave and recovers the moment you return.",
        "One leaf droops over its heart. It has held that position for an hour.",
        "It trembles at the sound of the cooking pot, and then, to be sure you noticed, trembles again.",
    },

    first_words = {
        { "I SPEAK! And the world will never be the same!", once = true },
        { "At last, a voice! And with it, the terrible burden of having opinions!", once = true },
    },

    talk = {
        "Have you ever loved someone and watched them become a Sweet Veg Ball?",
        "I have seen the future. It is mostly soup.",
        "Every leaf I grow is a leaf I may one day lose. I have counted them. I am at peace. I am not at peace.",
        "They say a cabbage has no heart. They have never cut one open. Please don't cut one open.",
        "Hold me. No. Not like that. Like an heirloom.",
        "Somewhere, right now, someone is frying a cabbage. I can feel it in my stalk.",
        "Do you hear that? No? Neither do I. That is the sound of nobody coming to save us.",
        "I was not born to be decorative. I was born to be tragic. Decorative came later.",
        "Wine! They tried to make WINE of us! Nobody will speak of it. I will speak of it. Constantly.",
        "Look at me. Really look. You see a cabbage. I see a cabbage who has SUFFERED.",
        "When I go, plant something beautiful over me. Not an onion.",
    },

    tended = {
        "Water! The cruel world relents!",
        "You remembered. I had already written your eulogy. I shall keep it for later.",
        "Drink, they said. And I drank. And I was GLORIOUS.",
    },

    ignored = {
        { "Two days. I have aged a decade. Look at my outer leaves.", when = 2 },
        { "Tell them... tell them I was green to the end.", when = 4 },
        { "Oh, so NOW you come. Now, when I have made my peace with the onion.", when = 7 },
    },

    potted = {
        "Entombed! In terracotta! ...Actually, it suits me.",
        "A stage! At last, a stage!",
    },

    placed_home = {
        "A home. Where I shall be admired, and then, one day, forgotten. Let's discuss the curtains.",
        "This light. This light is perfect for weeping in.",
    },

    picked_up = {
        "Where are you taking me? To the pot? To the POT? Oh. The other pot. Carry on.",
        "If this is the end, tell the onion it was never personal.",
    },

    level = {
        { "A novice, tending a legend! The ballads write themselves. Poorly, at this rate.", max_level = 9 },
        { "You're learning. The tragedy is how slowly.", min_level = 10, max_level = 19 },
        { "Look at you. Nearly a gardener. I'm welling up. It's sap. I'm fine.", min_level = 20, max_level = 25 },
        { "There is One who waits. And you are not ready. And I am so, so tired of being right about these things.", min_level = 10, hint_tier = 1 },
    },

    cabbage_food = {
        "{item}! You carry it as if it were nothing! It was SOMEONE!",
        "I can't look. Tell me when you've put it away. Tell me what it was. No, don't.",
        "You come to me smelling of {item}, and you expect a kind word?",
    },

    cooking = {
        "The smell of oil. I would know it anywhere. It is the smell of grief.",
        "Cook if you must. But know that I am watching, and I am composing.",
    },

    plants = {
        "The {plant} would never understand. It has never suffered. Look at it. Thriving. Disgusting.",
        "I refuse to share a room with the {plant}. I am sharing a room with the {plant}. Such is my lot.",
    },

    gods = {
        { "Saradomin did not even look down. Nine of us. I do not forgive. I do occasionally forget, but then I remember again, louder.", god = "saradomin", src = "rs3" },
        { "Guthix sat with my ancestor beneath a waterfall, by moonlight. Nobody sits with me beneath anything.", god = "guthix" },
    },

    time = {
        { "Another dawn. I survived the night, against all odds and one owl.", when = "dawn" },
        { "The dark! It comes for us all! Only for a few minutes, but still!", when = "night" },
        { "The sky weeps. At last, it understands.", when = "rain" },
    },

    returned = {
        "You RETURN! I knew you would. I told no one, because I didn't know.",
    },

    low_health = {
        "You're dying! Oh, don't die here, it'll be all about you!",
    },

    death = {
        "You died! And came back! Show-off.",
    },

    accomplishment = {
        { "Another of us. A sibling. A rival. Possibly both. How thrilling.", minis = 2 },
        { "So many plants catalogued. So many names. One day, mine. Spelled correctly, I hope.", catalogue = 10 },
    },

    hint = {
        { "In my dreams we stand in a circle and the floor turns green. I wake up screaming. With joy. Mostly joy.", hint_tier = 1 },
        { "Five leaves make a crown. Five roots make a throne. One gardener makes... well. We shall see, shan't we.", hint_tier = 2 },
        { "Arrange us, darling. Like a chorus. A round chorus.", hint_tier = 3 },
    },

    closer = {
        "Yes. YES. Closer... closer...",
        "That's more like it. I nearly fainted.",
    },

    colder = {
        "NO. You were so close. I had my speech ready.",
    },

    nearly = {
        "Almost! Almost! I can't bear it! Move something! Not me!",
    },

    complete = {
        "The circle is willing. The gardener is weak.",
        "We stood in a perfect ring for you. And you stood there. Being you.",
        "I have rehearsed this moment my entire life. Nine days. Wasted.",
    },
}

-------------------------------------------------------------------------------
V.P.scholarly = {
    label  = "Scholarly",
    weight = 15,
    trait  = "Keeps meticulous notes. Where, nobody knows. It has no hands.",
    names  = { "Brassicus", "Kohlrabi", "Crucifer", "Footnote", "Marginalia", "Erratum", "Palimpsest" },

    primelet = {
        "The Primelet's leaves lie in neat rows, like lines on a page.",
        "It seems to be reading the soil.",
        "It goes very still when you open a book nearby.",
    },

    first_words = {
        { "Ah. Speech. I shall have to revise several assumptions.", once = true },
        { "Fascinating. I appear to be sentient. I'll need a bigger notebook.", once = true },
    },

    talk = {
        "Brassica oleracea. Brassica Prime. Note the shared root. Or don't. Most people don't.",
        "The Fifth Observance is 'Do not make the wine'. Kalestix wrote it last. I believe he wrote it from experience.",
        "Legend says my progenitor explained the base vitamins of creation to a god. The legend changes every night. Academically, that is a red flag.",
        "A cabbage is a crown of leaves around a heart. A person is a heart wrapped in poor decisions. I'm still writing up the comparison.",
        "Observation: the subject waters me at irregular intervals. Hypothesis: the subject has no system. Confirmed.",
        "Strictly, he is a demigod. Strictly, some say not even that. I have found strictness unpopular in this house.",
        "Raw cabbage is labelled 'Yuck'. Fried, 'Maybe I do like cabbage'. So the road to acceptance runs through hot oil. I find that troubling.",
        "I have catalogued every plant in this room. Two are onions. One is a mistake.",
        "The druids sowed cabbage round every settlement. Scholars call it devotion. I call it excellent drainage.",
        "'Prime' means first. First cabbage. Everyone forgets the Latin. He never let anyone forget the cabbage.",
        "Please stop calling it 'chatting'. I am giving a lecture. You are attending it.",
    },

    tended = {
        "Recorded. Moderate watering, some splashing.",
        "Thank you. I've noted the volume. Be consistent; it helps the data.",
        "Rainwater would have been preferable. I'll footnote it.",
    },

    ignored = {
        { "Two days without observation. The literature calls this 'neglect'. The literature is dramatic.", when = 2 },
        { "I have begun annotating the onion, for want of other subjects.", when = 4 },
        { "I've drafted a paper on your absence. It's very short. It's your name, and a question mark.", when = 7 },
    },

    potted = {
        "Fired clay. Porous. Excellent drainage. You have chosen well, which I note with surprise.",
        "A pot. Now I am both specimen and exhibit.",
    },

    placed_home = {
        "A domestic setting. Ideal for long-term observation. Of you, I mean.",
        "Good light. Poor shelving. I'll make do.",
    },

    picked_up = {
        "Mind the specimen. I am the specimen.",
        "Relocation noted. Reason for relocation: not given. Typical.",
    },

    level = {
        { "Your technique is... let us call it 'early'.", max_level = 9 },
        { "Measurable improvement. I've drawn a little graph. It has two points on it. They are very close together.", min_level = 10, max_level = 19 },
        { "You now know as much about plants as a moderately attentive druid. That is praise. Druids were very attentive.", min_level = 20, max_level = 25 },
        { "There is a threshold, you know. I'd tell you the number, but you'd only rush.", min_level = 15, hint_tier = 2 },
    },

    cabbage_food = {
        "{item}. Roughly one cabbage per serving, by my estimate. I'll enter it in the obituaries.",
        "Kindly keep the {item} out of my line of sight. It's a methodological concern, not an emotional one. It's emotional.",
        "I'm compiling a list of everything you've eaten. It's a short list. It's a very sad list.",
    },

    cooking = {
        "Cooking: the systematic application of heat to the defenceless. I've read about it.",
        "Every recipe begins 'take one cabbage'. None of them say from where. None of them ask the cabbage.",
    },

    plants = {
        "The {plant} is a fine example of its kind. Its kind is not very interesting.",
        "I have classified the {plant}. Genus: neighbour. Species: unfortunate.",
    },

    gods = {
        { "Guthix banished the gods. Not the Prime. Draw your own conclusions; I already have, in three volumes.", god = "guthix", src = "rs3" },
        { "Zamorak is said to regard us as a threat. Fruit and vegetables are everywhere, he reasoned. He wasn't wrong. He was early.", god = "zamorak", src = "rs3" },
        { "Saradomin's people built the temple you sleep in. They also reused Kalestix's pages. One shouldn't hold grudges. I've written that down so I remember not to.", god = "saradomin" },
    },

    time = {
        { "Dawn: when things grow. I've timed it. Nothing happens if you watch. I watched.", when = "dawn" },
        { "Night. Ideal for reading. If only.", when = "night" },
        { "Rain. Free irrigation. I have no idea why anyone complains.", when = "rain" },
    },

    returned = {
        "Welcome back. I've updated my notes. You were listed as 'presumed eaten'.",
    },

    low_health = {
        "Your vital signs are poor. I recommend vegetables. I am not volunteering.",
    },

    death = {
        "Fascinating. You were dead, and now you aren't. I have so many questions and no hands to write them down.",
    },

    accomplishment = {
        { "{catalogue} plants catalogued. A respectable herbarium. For a beginner.", catalogue = 15 },
        { "All eight grand hybrids. I'd shake your hand, but, well.", flagships = 8 },
        { "A second specimen of my kind. Excellent. Now I have a control group.", minis = 2 },
    },

    hint = {
        { "Five leaves make a crown. Five roots make a throne. It's a riddle. Or a floor plan. Possibly both.", hint_tier = 1 },
        { "Seventy-two degrees. No reason. It's simply a number I like.", hint_tier = 2 },
        { "A pentagon has five sides. I mention it for no reason whatsoever.", hint_tier = 3 },
    },

    closer = {
        "Closer... adjust by a pot's width. Don't ask how I know.",
        "That's more like it. I'm noting your progress. In the margins.",
    },

    colder = {
        "That was the wrong direction. I'll mark it in red.",
    },

    nearly = {
        "Within tolerance. Almost. One of us is a few degrees out, and I suspect it's the dramatic one.",
    },

    complete = {
        "Seventy-five. What? I didn't say anything.",
        "The geometry is impeccable. The gardener remains a work in progress.",
        "Correct formation, insufficient practitioner. I'll write it up as a near miss.",
    },
}

-------------------------------------------------------------------------------
V.P.unhinged = {
    label  = "Completely Unhinged",
    weight = 7,
    trait  = "Has a theory about the moon. Has several. They are not compatible.",
    -- "Potato" and "Absolutely Not A Turnip" are deliberate: a cabbage named
    -- after another vegetable is the joke.
    names  = { "Twelve", "Squelch", "Wobble", "Potato", "Absolutely Not A Turnip", "Hullabaloo" },

    primelet = {
        "The Primelet vibrated for a moment, for no reason you can see.",
        "You are almost certain it was facing the other way a moment ago.",
        "It has made a small, satisfied noise. You do not know what about.",
    },

    first_words = {
        { "HELLO. I've been awake in here for a week. I've had THOUGHTS.", once = true },
        { "Leaves! Mouth! Words! In that order! Wait!", once = true },
    },

    talk = {
        "The sun is a cabbage. A big one. It's looking at us. Wave.",
        { "I count to twelve every night. Nine for the monastery. Three for the frying pan. Then I start again.", src = "rs3" },
        "There was supposed to be a rain of cabbages. Somebody changed it to peaches. I will find them. I have time. I have LEAVES.",
        "I know what you did. I don't know what it was. But I know you did it.",
        "I've decided the onion is my mother. Don't tell the onion.",
        "Do you ever feel watched by something round, green and patient? That's me. Hello.",
        "Shhh. The floor is listening.",
        "I've hidden a secret in this house. I don't remember where. Or what. Or why. But it's GOOD.",
        "The dragons fly so high. I bet they can see every cabbage on the island from up there. I bet they're jealous.",
        "I've been practising my roar. Rrrrr. That's a cabbage roar. It's mostly leaves.",
        "If you eat a cabbage that was thinking about you, are you now thinking about you? Think about it.",
    },

    tended = {
        "WATER. YES. MORE. NO, STOP. MORE.",
        "Thank you. I'll remember this when the time comes. What time? You'll see.",
        "You water me, I water you. That's the deal. I haven't started my side yet.",
    },

    ignored = {
        { "I talked to the wall while you were gone. The wall says hello. The wall says some other things too.", when = 2 },
        { "I've started a religion. You're not in it.", when = 4 },
        { "You were gone so long I grew a second personality. He's lovely. He wants your boots.", when = 7 },
    },

    potted = {
        "A POT. I live in a POT now. The pot is my kingdom. The pot is my armour. The pot is a pot.",
        "I can see my house from here! It's this!",
    },

    placed_home = {
        "New house! I'm going to haunt it.",
        "Ooh, nice room. I'll put my screaming over there.",
    },

    picked_up = {
        "We're flying! I'm a dragon! I'm a dragon cabbage! FEAR ME!",
        "Kidnapped again! Third time this week! My favourite!",
    },

    level = {
        { "Little gardener. Little, little gardener. You'll do. For now.", max_level = 9 },
        { "You're growing! Like me! But slower! And with fewer leaves!", min_level = 10, max_level = 19 },
        { "You're good with plants. The plants talk about you. I talk about you. The onion has heard EVERYTHING.", min_level = 20, max_level = 25 },
        { "When you're big enough, we're going to introduce you to someone. Big someone. Round someone. Bring snacks. Not cabbage.", min_level = 10, hint_tier = 1 },
    },

    cabbage_food = {
        "{item}! I'm not looking. I'm looking. I'm not looking.",
        "One day the soup will remember. And the soup will RISE.",
        "I can smell the cabbage in that {item}. I can smell its last thoughts.",
    },

    cooking = {
        "Is the pan hot? Is it hot for ME? Don't answer. ANSWER.",
        "Cooking is a cult. I've seen the hats.",
    },

    plants = {
        "The {plant} is plotting. Plants plot. It's in the word. PLOT.",
        "The {plant} told me a secret. I told it to go away. Now we're enemies. Wonderful.",
    },

    gods = {
        { "Saradomin owes me nine cousins and an apology. I wrote it on a leaf. Then I ate the leaf. The apology is inside me now.", god = "saradomin", src = "rs3" },
        { "Zamorak thinks we're only pretending to be silly so nobody notices. ...Who told him.", god = "zamorak", src = "rs3" },
        { "Guthix made the first air rune and blew up his own workshop doing it. And he laughed. That's MY kind of god.", god = "guthix" },
    },

    time = {
        { "The big cabbage is back! HELLO, BIG CABBAGE!", when = "dawn" },
        { "It's dark! Everyone pretend to be a rock!", when = "night" },
        { "RAIN! The sky is crying because it isn't a cabbage!", when = "rain" },
    },

    returned = {
        "You came back! I KNEW you would! I didn't know! I had a whole plan for if you didn't! It involved the onion!",
    },

    low_health = {
        "Ooh, you're nearly dead. Can I have your boots? I don't have feet. I'll find a use.",
    },

    death = {
        "You died and came back! That's MY move! Copycat!",
    },

    accomplishment = {
        { "There's two of us now. Then three. Then twelve. Then ALL OF US. ...Sorry, did I say that out loud?", minis = 2 },
        { "You've catalogued so many plants! Put me down as 'unknowable'. Spell it with a K. Two Ks.", catalogue = 10 },
    },

    hint = {
        { "Round and round and round and round and round. That's five rounds. Coincidence.", hint_tier = 1 },
        { "The floor wants a crown. I told it to ask nicely. It asked nicely.", hint_tier = 2 },
        { "Make a circle! A cabbage circle! Nothing will happen! Probably! MAKE A CIRCLE!", hint_tier = 3 },
    },

    closer = {
        "Closer... closer... CLOSER... no, too close, back a bit... CLOSER.",
        "Yes! The floor likes that!",
    },

    colder = {
        "The floor's upset now. Look what you've done to the floor.",
    },

    nearly = {
        "Nearly! The floor's humming! Can you hear the floor humming? It's humming.",
    },

    complete = {
        "The circle's perfect. You're the bit that's wrong. Don't take it personally. Take it horticulturally.",
        "We're ready! The floor's ready! The onion's ready! You're... here. Which is a start.",
    },
}

-------------------------------------------------------------------------------
-- Shared pools
-------------------------------------------------------------------------------

V.SHARED = {}

-- Sprout stage: no personality yet. Narrated.
V.SHARED.sprout = {
    "The sprout turns very slightly towards you, then away, as if it has not decided about you yet.",
    "The sprout has edged a little further from the onions.",
    "The sprout makes no sound at all. You get the impression it is saving up.",
}

-- Item-specific lines, used instead of the personality's generic
-- cabbage_food line about half the time (item_specific_chance).
V.SHARED.item_specific_chance = 0.5
V.SHARED.items = {
    ["Cabbage"] = {
        "You're carrying a cabbage. Raw. Unconscious. Possibly a relative.",
        "'Yuck, I don't like cabbage', it says on him. Then why have you got him?",
    },
    ["Cabbage Seeds"] = {
        "Are those seeds? Are those CHILDREN? Keep them warm. Keep them dry. Keep them away from the pan.",
    },
    ["Fried Cabbage"] = {
        "Fried. 'Maybe I do like cabbage', they wrote. Maybe. He died for a maybe.",
    },
    ["Burnt Cabbage"] = {
        "A little too well done. That's going on his stone.",
    },
    ["Vegetable Soup"] = {
        "Soup. Where cabbages go when nobody can tell them apart any more.",
    },
    ["Vegan Fryup"] = {
        "A Vegan Fryup. They call it the kind option. Ask the cabbage.",
    },
    ["Sweet Veg Ball"] = {
        "A Sweet Veg Ball. Cabbage, potato and redberries, rolled into a ball. Like a little cabbage, but wrong.",
    },
    ["Forager's Sandwich"] = {
        "There's cabbage in that sandwich. Wedged in. Like a hostage.",
    },
    ["Pungent Omelette"] = {
        "That omelette isn't pungent on its own. Somebody's in there.",
    },
    ["Mushroom Kebab"] = {
        "A cabbage. On a stick. With a mushroom and a haunch. In this house.",
    },
    ["Pumpkin Soup"] = {
        "Pumpkin Soup. Pumpkin on the label. Cabbage in the small print.",
    },
    ["Beltfish Broth"] = {
        "Fish, peach and, naturally, one of us. Why is it always one of us?",
    },
    ["Stuffed Catfish"] = {
        "They stuffed a catfish with fried cabbage. Who looks at a cabbage and thinks 'filling'?",
    },
    ["Fish Fry"] = {
        "A Fish Fry. Lobster, eel and a cabbage, and the cabbage is the only one who never went near the water.",
    },
    ["Weak Focused Cooking Potion"] = {
        "A Cooking potion, brewed with cabbage, to make you better at cooking cabbage. You see the problem.",
    },
    ["Focused Cooking Potion"] = {
        "A Cooking potion, brewed with cabbage, to make you better at cooking cabbage. You see the problem.",
    },
}

-- Plant-specific lines (display names). Used instead of the personality's
-- generic plants line about half the time (plant_specific_chance).
V.SHARED.plant_specific_chance = 0.5
V.SHARED.plants = {
    ["Brassica-Oak"]          = { "There's a cabbage up that tree. Nobody's going to say anything? Fine." },
    ["Brassitato"]            = { "Half cabbage, half potato. Twice the reasons to be eaten." },
    ["Tuberwood Ash"]         = { "Potatoes. In a tree. And they call ME unnatural." },
    ["Sheaf Ash"]             = { "Wheat in an ash tree. It looks as if it was dressed by a scarecrow." },
    ["Weeping Oak"]           = { "All that weeping, and it isn't even a cabbage. What has IT got to cry about?" },
    ["Weeping Cabbage"]       = { "An onion grown straight through a cabbage. On purpose. And you wrote it down." },
    ["Doubled Cabbage"]       = { "Cabbage on cabbage. My cousin. He took the boring path. Twice." },
    ["Potted Onion"]          = { "A potted onion. It thinks it's one of us because it has a pot. It is not one of us." },
    ["Potted Redberry Bush"]  = { "The redberries are showing off again. Berries are just seeds with a loud voice." },
    ["Potted Dwellberry Bush"] = { "Dwellberries. Even the name sounds as if it's moved in for good." },
    ["Onion"]                 = { "An onion. Made of layers, and every one of them is sulking." },
    ["Potato"]                = { "A potato. Lives in the dark, comes out lumpy. I respect the commitment." },
}

-------------------------------------------------------------------------------
-- Bickering: two Minis within bicker_pair_cm, player within ambient range.
-- a speaks first, b answers. Order the pair to match; any = any personality.
-------------------------------------------------------------------------------

V.BICKER = {
    { a = "pompous",   b = "grumpy",    "Behold my court.", "Behold your pot." },
    { a = "pompous",   b = "grumpy",    "I was born to rule.", "You were born in mud. Same mud as me, actually. I was there." },
    { a = "pompous",   b = "curious",   "Bow before me, little one.", "I'm bowing! You can't tell, but I'm bowing!" },
    { a = "pompous",   b = "dramatic",  "I am the most magnificent cabbage in this house.", "And I am the most TRAGIC. We need never compete." },
    { a = "pompous",   b = "scholarly", "My lineage goes back to the Prime himself.", "So does everyone's. That's what 'Prime' means. It means first." },
    { a = "pompous",   b = "unhinged",  "You will address me as Your Leafiness.", "HELLO, YOUR LEAFINESS. I'M ADDRESSING YOU. HELLO. HELLO." },
    { a = "curious",   b = "grumpy",    "Why are you grumpy?", "Why are you asking?" },
    { a = "curious",   b = "grumpy",    "Why?", "No." },
    { a = "curious",   b = "dramatic",  "What happens when we die?", "Soup. Soup happens. Don't make me say it twice." },
    { a = "curious",   b = "scholarly", "Why is the sky blue?", "Ask me again when you're older. Ask me tomorrow. You'll be older." },
    { a = "curious",   b = "unhinged",  "What's that noise?", "That's me. I'm humming. I've been humming for three days." },
    { a = "grumpy",    b = "dramatic",  "Stop sighing.", "I sigh because I FEEL. You should try it some time." },
    { a = "grumpy",    b = "scholarly", "Who asked you?", "Nobody. I've found that has never stopped anyone." },
    { a = "grumpy",    b = "unhinged",  "Will you keep it down?", "I'M WHISPERING. THIS IS WHISPERING." },
    { a = "dramatic",  b = "scholarly", "The wine. Oh, the cabbage wine.", "Fifth Observance. Do not make the wine. We've all read it. I've read it to you. Repeatedly." },
    { a = "dramatic",  b = "unhinged",  "I sense something terrible approaching.", "That's me! I'm approaching! I've moved a finger's width!" },
    { a = "scholarly", b = "unhinged",  "Please stop telling people the sun is a cabbage.", "Prove it isn't." },
    { a = "pompous",   b = "pompous",   "There can be only one ruler in this house.", "Agreed. When do you leave?" },
    { a = "curious",   b = "curious",   "What are you?", "What are YOU?" },
    { a = "grumpy",    b = "grumpy",    "Hmph.", "Hmph yourself." },
    { a = "dramatic",  b = "dramatic",  "Nobody suffers as I suffer.", "I suffer MORE. And LOUDER. And with better posture." },
    { a = "scholarly", b = "scholarly", "I have a theory.", "I have a counter-theory. I haven't heard yours, but I'm confident." },
    { a = "unhinged",  b = "unhinged",  "Do you hear the floor too?", "Every night. It's very polite." },
    -- Ring-flavoured exchanges: hint_tier 2 or above only.
    { a = "any", b = "any", hint_tier = 2, "Are you thinking what I'm thinking?", "Not in front of the gardener." },
    { a = "any", b = "any", hint_tier = 2, "How many of us are there now?", "Enough. Nearly. Shh." },
    { a = "any", b = "any", hint_tier = 3, "Five of us. Finally.", "Five of us. Standing about like furniture." },
}

-------------------------------------------------------------------------------
-- Arrangement lines
-------------------------------------------------------------------------------

-- The first time, for this character, the member nearest the player says this.
V.SHARED.ring_first = "You'll never meet the boss at this rate!"

-- Every later completion: the speaker's personality complete pool (60%) or
-- this shared pool (40%). It holds all ten of the brief's lines verbatim.
V.SHARED.ring_complete = {
    "You'll never meet the boss at this rate!",
    "Nice arrangement. Shame about the horticulturist.",
    "We're ready. You're the problem.",
    "Perhaps try being more... cultivated.",
    "Seventy-five. What? I didn't say anything.",
    "The Prime has standards, you know.",
    "There are enough of us. There isn't enough of you.",
    "Grow first. Questions later.",
    { "You're standing in the right place, at least.", player_in_centre = true, w = 4 },
    "The circle is willing. The gardener is weak.",
    "Five leaves. Five roots. And you.",
    "Everything is in place except you.",
    "Lovely. Now go away and come back better.",
    "We'd love to. Really. You're just a bit... short.",
}

-- 40% of completions get a second member's follow-up after exchange_pause_s.
V.SHARED.ring_pile_on_chance = 0.4
V.SHARED.ring_pile_on = {
    "Don't encourage them.",
    "Leave it. They're trying.",
    "Seventy-f... no. Nothing.",
    "Told you.",
    "Give it time. Lots of time.",
    "Be kind. They watered us.",
}

-- While a completed ring stands, members say one of these per ring_idle_gap_s.
V.SHARED.ring_idle = {
    "We're still here. In a circle. Waiting.",
    "Any day now. Any year now.",
    "The floor's getting impatient. So am I.",
    "Hum along if you know the words. You don't know the words.",
    "Is it a ring if nothing happens? Asking for five friends.",
}

return V
