--[[
    Config.lua — Grow a Brainrot
    Lives in ReplicatedStorage so both server and client can read it.

    GAME LOOP
      1. Buy elixirs at Maison Mixalot (the boutique).
      2. Brew 2-5 DIFFERENT elixirs at the cauldron in YOUR lab.
         The combo is the recipe -> it decides which creature you get.
      3. The egg incubates in one of your 3 pods (rarer = longer).
      4. Hatch it. The creature lives in your lab, earns cash every 10s,
         and has a TRAIT that does something (tax rivals, guard, boost...).
      5. Take your best 3 to the Ohio Colosseum: fight wild brainrots or duel players.
      6. Rebirth at the shrine for a permanent income multiplier.
]]

local Config = {}

-- ============================================
-- INGREDIENTS (the boutique's elixirs)
-- Keys are used in recipes; part names in the shop map to them.
-- ============================================
Config.Ingredients = {
    Sigma   = { name = "Frostmind Tonic",    tagline = "Ice-blue and ice-cold. Brews sharp, calculating HEADS.",       price = 150,  color = {40, 210, 255}, image = "rbxassetid://102139306711533" },
    Ohio    = { name = "Voidwalk Draught",   tagline = "A swirling purple void in a bottle. Brews eerie LEGS.",        price = 150,  color = {170, 80, 255}, image = "rbxassetid://95087436938013" },
    Skibidi = { name = "Crimson Grip Serum", tagline = "Red, fizzy and twitchy. Brews grabby ARMS.",                   price = 200,  color = {255, 60, 95}, image = "rbxassetid://110483628280430" },
    Rizz    = { name = "Liquid Gold Nectar", tagline = "Shimmering 24k gold. Brews dripped-out TORSOS.",               price = 300,  color = {255, 200, 40}, image = "rbxassetid://71450875602062" },
    Fanum   = { name = "Venomfang Brew",     tagline = "Toxic green with a bite. Brews nasty WEAPONS.",                price = 500,  color = {40, 235, 150}, image = "rbxassetid://127363341960260" },
    Mewing  = { name = "Ember Jaw Elixir",   tagline = "Burning orange, smells like a gym. Brews chiselled HEADS.",    price = 750,  color = {255, 115, 25}, image = "rbxassetid://114038142064281", premium = true },
    Aura    = { name = "Halo Mist",          tagline = "Pearl-white light that hums. Brews blessed TORSOS.",           price = 1200, color = {225, 238, 255}, image = "rbxassetid://83135495979370", premium = true },
    Delulu  = { name = "Dreamcandy Syrup",   tagline = "Pink, sparkly, completely unhinged. Brews ANY part.",          price = 2000, color = {255, 110, 200}, image = "rbxassetid://87765288439724", premium = true },
}
Config.IngredientOrder = { "Sigma", "Ohio", "Skibidi", "Rizz", "Fanum", "Mewing", "Aura", "Delulu" }
Config.SatchelSize = 10

-- Map bottle part names (in the shop) -> ingredient keys
Config.BottleToIngredient = {
    SigmaExtract   = "Sigma",
    OhioJuice      = "Ohio",
    SkibidiEssence = "Skibidi",
    RizzPowder     = "Rizz",
    FanumFluid     = "Fanum",
    MewingTonic    = "Mewing",
    AuraMist       = "Aura",
    DeluluSyrup    = "Delulu",
}

-- ============================================
-- RECIPES: sorted ingredient keys joined with "+"
-- ============================================
Config.Recipes = {
    -- 2-ingredient combos
    ["Ohio+Sigma"]     = { name = "Blobby",      rarity = "Common" },
    ["Ohio+Skibidi"]   = { name = "Mudling",     rarity = "Common" },
    ["Sigma+Skibidi"]  = { name = "Glowfin",     rarity = "Uncommon" },
    ["Ohio+Rizz"]      = { name = "Chomper",     rarity = "Uncommon" },
    ["Rizz+Sigma"]     = { name = "Sparky",      rarity = "Uncommon" },
    ["Fanum+Sigma"]    = { name = "Crystalwing", rarity = "Rare" },
    ["Fanum+Ohio"]     = { name = "Voidling",    rarity = "Rare" },
    ["Rizz+Skibidi"]   = { name = "Flameboi",    rarity = "Rare" },
    ["Fanum+Skibidi"]  = { name = "Thunderpup",  rarity = "Rare" },
    ["Fanum+Rizz"]     = { name = "Icefang",     rarity = "Rare" },

    -- 3-ingredient combos
    ["Ohio+Sigma+Skibidi"]  = { name = "Skibidi Dragon",    rarity = "Epic" },
    ["Rizz+Sigma+Skibidi"]  = { name = "Sigma Wolf",        rarity = "Epic" },
    ["Ohio+Rizz+Sigma"]     = { name = "Ohio Beast",        rarity = "Epic" },
    ["Fanum+Ohio+Sigma"]    = { name = "Gyatt Golem",       rarity = "Epic" },
    ["Fanum+Sigma+Skibidi"] = { name = "Rizz Tiger",        rarity = "Epic" },
    ["Fanum+Ohio+Rizz"]     = { name = "Duke Dennis Titan", rarity = "Legendary" },
    ["Fanum+Ohio+Skibidi"]  = { name = "Kai Cenat Kraken",  rarity = "Legendary" },
    ["Ohio+Rizz+Skibidi"]   = { name = "Fanum Tax Phoenix", rarity = "Legendary" },
    ["Fanum+Rizz+Sigma"]    = { name = "Baby Gronk",        rarity = "Legendary" },
    ["Fanum+Rizz+Skibidi"]  = { name = "The Rizzler",       rarity = "Mythic" },

    -- SECRET 5-ingredient combo
    ["Fanum+Ohio+Rizz+Sigma+Skibidi"] = { name = "Lil Bro Supreme", rarity = "Mythic" },
}

-- When the combo doesn't match any recipe
Config.FailCreature = { name = "Mystery Goop", rarity = "Common" }
Config.TotalRecipes = 21

-- ============================================
-- RARITY
-- ============================================
Config.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
Config.RarityRank = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }
Config.RarityColors = {
    Common    = {200, 200, 210},
    Uncommon  = {90, 230, 120},
    Rare      = {70, 170, 255},
    Epic      = {190, 90, 255},
    Legendary = {255, 190, 40},
    Mythic    = {255, 80, 170},
}

-- Grow time in seconds
Config.GrowTime = {
    Common    = 15,
    Uncommon  = 30,
    Rare      = 60,
    Epic      = 120,
    Legendary = 240,
    Mythic    = 480,
}

-- Passive income per creature (coins per 10 seconds), before traits/multipliers
Config.IncomeInterval = 10
Config.CreatureIncome = { -- cash per creature every IncomeInterval
    Common    = 12,
    Uncommon  = 30,
    Rare      = 80,
    Epic      = 220,
    Legendary = 600,
    Mythic    = 1800,
}

-- Cash you get for selling one at the Trading Post
Config.SellValue = {
    Common    = 150,
    Uncommon  = 400,
    Rare      = 1200,
    Epic      = 3500,
    Legendary = 10000,
    Mythic    = 30000,
}

-- ============================================
-- TRAITS: what each creature actually DOES
-- ============================================
Config.Traits = {
    Grinder    = { icon = "💼", title = "Grinder",     desc = "Earns +50% cash. Hits 15% harder in battle." },
    Brewmaster = { icon = "⚗️", title = "Brewmaster",  desc = "Your incubators grow 15% faster (stacks to 45%). Heals its team in battle." },
    LuckyCharm = { icon = "🍀", title = "Lucky Charm", desc = "+2% mutation chance on your brews (stacks to +10%). 25% crit chance in battle." },
    FanumTaxer = { icon = "💸", title = "Fanum Taxer", desc = "Every 60s it raids a rival lab and taxes 4% of their cash. Bodyguards can block it. Lifesteal in battle." },
    Bodyguard  = { icon = "🛡️", title = "Bodyguard",   desc = "Each one blocks 50% of tax raids on your lab. +40% HP and draws enemy hits in battle." },
    RizzMagnet = { icon = "😏", title = "Rizz Magnet", desc = "Boutique prices -8% (stacks to -32%). Can charm enemies into skipping a turn." },
    Imposter   = { icon = "🥸", title = "Imposter",    desc = "Raids in disguise every 90s for 3%. Bodyguards can't see it and the victim never learns who. Dodges the first hit and ambushes for 2x." },
    HypeBeast  = { icon = "📣", title = "Hype Beast",  desc = "+10% income to all your other creatures (stacks to +50%). Hypes its team +10% ATK in battle." },
    Goop       = { icon = "😵", title = "Mystery Goop",desc = "Does nothing... but has a 2% chance every minute to evolve into a random Rare." },
}

Config.CreatureTraits = {
    ["Mystery Goop"]      = "Goop",
    ["Blobby"]            = "Grinder",
    ["Mudling"]           = "Bodyguard",
    ["Glowfin"]           = "LuckyCharm",
    ["Chomper"]           = "FanumTaxer",
    ["Sparky"]            = "Brewmaster",
    ["Crystalwing"]       = "LuckyCharm",
    ["Voidling"]          = "Imposter",
    ["Flameboi"]          = "Grinder",
    ["Thunderpup"]        = "Brewmaster",
    ["Icefang"]           = "Bodyguard",
    ["Skibidi Dragon"]    = "HypeBeast",
    ["Sigma Wolf"]        = "Grinder",
    ["Ohio Beast"]        = "FanumTaxer",
    ["Gyatt Golem"]       = "Bodyguard",
    ["Rizz Tiger"]        = "RizzMagnet",
    ["Duke Dennis Titan"] = "HypeBeast",
    ["Kai Cenat Kraken"]  = "Imposter",
    ["Fanum Tax Phoenix"] = "FanumTaxer",
    ["Baby Gronk"]        = "RizzMagnet",
    ["The Rizzler"]       = "RizzMagnet",
    ["Lil Bro Supreme"]   = "HypeBeast",
}

-- Max cash a single raid can take, by the raider's rarity
Config.TaxCap = { Common = 50, Uncommon = 150, Rare = 400, Epic = 1200, Legendary = 3500, Mythic = 10000 }
Config.TaxMinVictimCash = 1000

-- ============================================
-- LOOKS: features the CreatureBuilder adds on top of the body
-- ============================================
Config.CreatureLooks = {
    ["Mystery Goop"]      = { shape = "slime" },
    ["Blobby"]            = { features = { "antenna" } },
    ["Mudling"]           = { features = { "spikes" } },
    ["Glowfin"]           = { features = { "fin", "glow" } },
    ["Chomper"]           = { features = { "teeth" } },
    ["Sparky"]            = { features = { "antenna", "sparks", "glow" } },
    ["Crystalwing"]       = { features = { "wings", "glow" } },
    ["Voidling"]          = { shape = "ghost", features = { "halo" } },
    ["Flameboi"]          = { features = { "flame", "glow" } },
    ["Thunderpup"]        = { shape = "long", features = { "ears", "tail", "sparks" } },
    ["Icefang"]           = { shape = "long", features = { "ears", "teeth", "tail" } },
    ["Skibidi Dragon"]    = { shape = "long", features = { "wings", "horns", "tail", "spikes" } },
    ["Sigma Wolf"]        = { shape = "long", features = { "ears", "tail", "shades" } },
    ["Ohio Beast"]        = { features = { "horns", "thirdEye", "teeth" } },
    ["Gyatt Golem"]       = { shape = "tall", features = { "spikes", "glow" } },
    ["Rizz Tiger"]        = { shape = "long", features = { "ears", "tail", "shades", "stripes" } },
    ["Duke Dennis Titan"] = { shape = "tall", features = { "crown", "shades" } },
    ["Kai Cenat Kraken"]  = { features = { "tentacles", "helmet" } },
    ["Fanum Tax Phoenix"] = { features = { "wings", "flame", "crest", "glow" } },
    ["Baby Gronk"]        = { features = { "helmet", "shades" } },
    ["The Rizzler"]       = { features = { "crown", "shades", "aura", "glow" } },
    ["Lil Bro Supreme"]   = { features = { "crown", "halo", "wings", "aura", "glow" } },
}
Config.RaritySize = { Common = 2.4, Uncommon = 2.8, Rare = 3.2, Epic = 3.8, Legendary = 4.5, Mythic = 5.2 }

-- ============================================
-- BATTLES (Ohio Colosseum)
-- ============================================
Config.BattleStats = {
    Common    = { hp = 60,  atk = 9,  spd = 5 },
    Uncommon  = { hp = 90,  atk = 13, spd = 6 },
    Rare      = { hp = 140, atk = 19, spd = 7 },
    Epic      = { hp = 220, atk = 29, spd = 8 },
    Legendary = { hp = 340, atk = 44, spd = 9 },
    Mythic    = { hp = 520, atk = 66, spd = 10 },
}
Config.TeamSize = 3
Config.WildCooldown = 15
Config.DuelBountyPct = 0.05
Config.DuelBountyCap = 5000

-- ============================================
-- MUTATION (random bonus on any hatch)
-- ============================================
Config.MutationChance = 0.05       -- 5% chance
Config.MutationMultiplier = 3      -- mutated creature earns 3x, +40% battle stats

-- ============================================
-- ECONOMY & PLOTS
-- ============================================
Config.StartingMoney = 1000
Config.MaxPodsPerPlot = 5 -- pods 4 and 5 are bought as lab upgrades (Config.LabUpgrades)
Config.MaxPlots        = 6
Config.MaxCreatures    = 12  -- +2 per rebirth

-- ============================================
-- REBIRTH
-- ============================================
Config.RebirthCost       = 50000
Config.RebirthMultiplier = 1.5
Config.MaxRebirths       = 10

-- ============================================
-- Derived lookups
-- ============================================
Config.CreatureRecipe = {} -- creature name -> list of ingredient keys
for key, recipe in Config.Recipes do
    Config.CreatureRecipe[recipe.name] = string.split(key, "+")
end
Config.CreaturesByRarity = {}
for _, recipe in Config.Recipes do
    Config.CreaturesByRarity[recipe.rarity] = Config.CreaturesByRarity[recipe.rarity] or {}
    table.insert(Config.CreaturesByRarity[recipe.rarity], recipe.name)
end

function Config.Color(rgb)
    return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

function Config.MakeRecipeKey(list)
    local sorted = table.clone(list)
    table.sort(sorted)
    local unique, prev = {}, nil
    for _, v in sorted do
        if v ~= prev then
            table.insert(unique, v)
            prev = v
        end
    end
    return table.concat(unique, "+"), #unique
end

-- ============================================
-- PARTS SYSTEM
-- The cauldron brews PART CAPSULES. Parts are snapped together at the
-- Assembly Lab into a creature. Every part has a slot, a family (one of the
-- five elixirs) and a rarity. What each part does depends on slot + family.
-- ============================================
Config.Slots = { "Head", "Torso", "Arms", "Legs", "Weapon" }
Config.Families = { "Sigma", "Ohio", "Skibidi", "Rizz", "Fanum", "Mewing", "Aura", "Delulu" }

-- the elixir you add decides which slot the brew leans towards
Config.SlotBias = {
    Sigma = "Head",
    Rizz = "Torso",
    Skibidi = "Arms",
    Ohio = "Legs",
    Fanum = "Weapon",
    Mewing = "Head",
    Aura = "Torso",
    Delulu = "Any", -- random slot
}

-- part names in the same pseudo-Italian brainrot style as the creature names
Config.PartNames = {
    Head   = { Sigma = "Testa Ghiacciolo",   Ohio = "Teschio Vortello",     Skibidi = "Gremlo Capoccia",  Rizz = "Corona Bling Bling", Fanum = "Boccone Gnam",
               Mewing = "Mascellone",         Aura = "Aureolo Testolino",    Delulu = "Bolla Sognella" },
    Torso  = { Sigma = "Pancia Frigorina",   Ohio = "Cuore Spettrolo",      Skibidi = "Corazza Crimsona", Rizz = "Felpa Drippetta",    Fanum = "Pancione Panzerotto",
               Mewing = "Petto Muscolino",    Aura = "Tunica Angelotta",     Delulu = "Nuvola Zuccherina" },
    Arms   = { Sigma = "Braccia Ghiacciate", Ohio = "Artigli Spettrali",    Skibidi = "Pinze Gremline",   Rizz = "Braccialetti Bling", Fanum = "Manone Gnam",
               Mewing = "Bicipiti Flexini",   Aura = "Manine Aureoline",     Delulu = "Spaghetti Braccini" },
    Legs   = { Sigma = "Scarpe Frigorine",   Ohio = "Tentacoli Vortellini", Skibidi = "Zampe Saltarelle", Rizz = "Sneakerini Drip",    Fanum = "Zampone Stomp",
               Mewing = "Gambe Squattini",    Aura = "Nuvoletta Volante",    Delulu = "Molle Boing Boing" },
    Weapon = { Sigma = "Valigetta Bonk",     Ohio = "Lama Spettrola",       Skibidi = "Cannone Splash",   Rizz = "Spezzacuori",        Fanum = "Forchettone",
               Mewing = "Manubrio Pesante",   Aura = "Bastone Aureolo",      Delulu = "Lecca Lecca Mazza" },
}

-- the special ability each part brings (heads + torsos give lab quirks, weapons give battle moves)
Config.PartPerks = {
    Head = {
        Sigma   = { trait = "Grinder",    icon = "💼", title = "Grinder",     desc = "This creature earns +50% cash." },
        Ohio    = { trait = "Imposter",   icon = "🥸", title = "Imposter",    desc = "Raids a rival lab in disguise every 90s (3% of their cash). Bodyguards can't see it." },
        Skibidi = { trait = "HypeBeast",  icon = "📣", title = "Hype Beast",  desc = "+10% income for your other creatures (max +50%). +10% team ATK in battle." },
        Rizz    = { trait = "RizzMagnet", icon = "😏", title = "Rizz Magnet", desc = "-8% on all shop prices (max -32%)." },
        Fanum   = { trait = "FanumTaxer", icon = "💸", title = "Fanum Taxer", desc = "Raids a rival lab every 60s for 4% of their cash. Bodyguards can block it." },
        Mewing  = { trait = "Mogger",     icon = "🗿", title = "Mogger",      desc = "+25% cash from this creature and +15% ATK." },
        Aura    = { trait = "LuckyCharm", icon = "😇", title = "Blessed",     desc = "+1 rarity roll on every brew and +2% shiny chance." },
        Delulu  = { trait = "MainCharacter", icon = "✨", title = "Main Character", desc = "Earns DOUBLE cash, but -25% HP." },
    },
    Torso = {
        Sigma   = { trait = "Brewmaster", icon = "⚗️", title = "Brewmaster",  desc = "Capsules grow 15% faster (max 45%). Heals its team in battle." },
        Ohio    = { trait = "Bodyguard",  icon = "🛡️", title = "Bodyguard",   desc = "Blocks 50% of raids on your lab. Draws enemy hits in battle." },
        Skibidi = { trait = "LuckyCharm", icon = "🍀", title = "Lucky Charm", desc = "+1 rarity roll on every brew and +2% shiny chance." },
        Rizz    = { trait = "Tank",       icon = "🧱", title = "Tank",        desc = "+40% HP in battle." },
        Fanum   = { trait = "Glutton",    icon = "🍔", title = "Glutton",     desc = "Heals 20% of the damage it deals." },
        Mewing  = { trait = "GymRat",     icon = "🏋️", title = "Gym Rat",     desc = "+20% HP and +10% ATK." },
        Aura    = { trait = "GuardianAngel", icon = "🕊️", title = "Guardian Angel", desc = "+20% HP and heals its team in battle." },
        Delulu  = { trait = "SweetTooth", icon = "🍭", title = "Sweet Tooth", desc = "+25% cash from this creature." },
    },
    Arms = {
        Sigma   = { icon = "🤝", title = "Closer",     desc = "+15% ATK." },
        Ohio    = { icon = "🎣", title = "Rend",       desc = "+10% crit chance." },
        Skibidi = { icon = "🐙", title = "Suction",    desc = "+10% ATK and steals 5% enemy speed." },
        Rizz    = { icon = "💎", title = "Flex",       desc = "+5% income." },
        Fanum   = { icon = "🧲", title = "Grab",       desc = "+20% ATK on the first hit." },
        Mewing  = { icon = "💪", title = "Flex",       desc = "+25% ATK." },
        Aura    = { icon = "🌟", title = "Holy Touch", desc = "+15% crit chance." },
        Delulu  = { icon = "🌀", title = "Wiggle",     desc = "+10% ATK and 10% chance to charm." },
    },
    Legs = {
        Sigma   = { icon = "👞", title = "Power Walk", desc = "+2 speed." },
        Ohio    = { icon = "👻", title = "Phase",      desc = "Dodges the first hit it takes." },
        Skibidi = { icon = "🧱", title = "Iron Stance", desc = "+25% HP but -1 speed." },
        Rizz    = { icon = "👟", title = "Drip Dash",  desc = "+3 speed." },
        Fanum   = { icon = "🐾", title = "Stomp",      desc = "+1 speed and +10% HP." },
        Mewing  = { icon = "🏃", title = "Leg Day",    desc = "+15% HP and +1 speed." },
        Aura    = { icon = "☁️", title = "Float",      desc = "Dodges the first hit and +2 speed." },
        Delulu  = { icon = "🎈", title = "Boing",      desc = "+4 speed but -10% HP." },
    },
    Weapon = {
        Sigma   = { icon = "💼", title = "Briefcase Bash", desc = "25% chance to crit for 2x." },
        Ohio    = { icon = "🗡️", title = "Backstab",       desc = "Its first hit deals 2x (ambush)." },
        Skibidi = { icon = "💦", title = "Splash Zone",    desc = "Every hit splashes 35% damage onto the other enemies." },
        Rizz    = { icon = "💘", title = "Heartbreaker",   desc = "20% chance to charm the target into skipping a turn." },
        Fanum   = { icon = "🍴", title = "Tax Fork",       desc = "Steals 30% of the damage as HP." },
        Mewing  = { icon = "🏋️", title = "Heavy Set",      desc = "15% crit chance and +20% ATK on the first hit." },
        Aura    = { icon = "🔆", title = "Judgement",      desc = "Hits splash 25% onto other enemies and heal 10%." },
        Delulu  = { icon = "🍭", title = "Sugar Crash",    desc = "30% chance to charm the target into skipping a turn." },
    },
}

-- family labels shown on cards
Config.NamePrefix = { Sigma = "Sigma", Ohio = "Ohio", Skibidi = "Skibidi", Rizz = "Rizzler", Fanum = "Fanum", Mewing = "Mewing", Aura = "Aura", Delulu = "Delulu" }

-- creature names, in sing-song pseudo-Italian brainrot style:
-- first word from the head's family, second from the torso's, and a chant for a full set
Config.BrainrotFirst = { Sigma = "Frigorino", Ohio = "Vortellino", Skibidi = "Gremlino", Rizz = "Brillantino", Fanum = "Gnam Gnam",
                         Mewing = "Mascellone", Aura = "Aureolino", Delulu = "Sognarello" }
Config.BrainrotLast  = { Sigma = "Ghiacciolini", Ohio = "Spettrolo", Skibidi = "Saltarello", Rizz = "Dripperoni", Fanum = "Panzerotto",
                         Mewing = "Muscolino", Aura = "Angelotto", Delulu = "Nuvolina" }
Config.BrainrotPure  = { Sigma = "Brivido Brivido Frigorino", Ohio = "Bumba Bumba Vortellino", Skibidi = "Skrrt Skrrt Gremlino",
                         Rizz = "Bling Bling Dripperoni", Fanum = "Gnam Gnam Gnam Panzerotto", Mewing = "Fuoco Fuoco Mascellone",
                         Aura = "Ding Ding Aureolino", Delulu = "Lalala Sognarella" }

-- how strong a part of each rarity is (multiplies its stats)
Config.RarityPower = { Common = 1, Uncommon = 1.5, Rare = 2.3, Epic = 3.5, Legendary = 5.5, Mythic = 9 }
Config.PartIncome  = { Common = 3, Uncommon = 7, Rare = 18, Epic = 45, Legendary = 120, Mythic = 360 } -- per part, torso counts double
Config.PartSell    = { Common = 40, Uncommon = 100, Rare = 300, Epic = 900, Legendary = 3000, Mythic = 12000 }
Config.PartSize    = { Common = 1, Uncommon = 1.07, Rare = 1.15, Epic = 1.25, Legendary = 1.38, Mythic = 1.55 }

-- brewing odds: one roll per brew, plus one extra roll per $600 of elixirs used (max 8).
-- the best roll wins.
Config.BrewOdds = {
    { "Mythic", 0.002 },
    { "Legendary", 0.013 },
    { "Epic", 0.045 },
    { "Rare", 0.12 },
    { "Uncommon", 0.27 },
    { "Common", 1 },
}
Config.ValuePerRoll = 600
Config.MaxRolls = 8
Config.ShinyChance = 0.05     -- shiny parts have 1.5x stats and sell for 2x
Config.MinElixirsToBrew = 2
Config.MaxParts = 60          -- part inventory size

Config.SetBonus3 = 0.2        -- 3+ parts of one family: +20% stats and income
Config.SetBonus5 = 0.5        -- all 5 parts of one family: +50%

-- The Forge
Config.FuseCount = 3          -- fuse 3 same-slot same-rarity parts into one of the next rarity
Config.WeaponCrateCost = 2500
Config.WeaponCrateRolls = 3
-- Black Market
Config.MarketSlots = 3
Config.MarketRefresh = 300    -- seconds
Config.MarketMarkup = 3       -- price = sell value x 3

-- Ranked duels
Config.RankedWin = 3
Config.RankedLoss = 1

-- Body Draughts (the Body Bar, next to Maison Mixalot): pour ONE into your satchel and the
-- next brew is guaranteed to be that body part. The family still comes from your elixirs.
Config.Draughts = {
    Head =   { name = "Crown Draught",     price = 600, color = { 185, 120, 255 }, icon = "👤", tagline = "Violet and fizzy. Grows a head with a signature move." },
    Torso =  { name = "Heartcore Draught", price = 450, color = { 50, 215, 190 },  icon = "👕", tagline = "Thick and teal. Grows a torso that guards and heals." },
    Arms =   { name = "Grip Draught",      price = 300, color = { 255, 150, 50 },  icon = "💪", tagline = "Orange pulp. Grows arms for steady strikes." },
    Legs =   { name = "Stride Draught",    price = 300, color = { 150, 230, 70 },  icon = "🦵", tagline = "Lime and zippy. Grows legs that strike first." },
    Weapon = { name = "Blade Draught",     price = 800, color = { 235, 55, 75 },   icon = "🗡️", tagline = "Crimson and sharp. Grows a weapon for heavy hits." },
}
Config.DraughtOrder = { "Head", "Torso", "Arms", "Legs", "Weapon" }
Config.BottleToDraught = { Draught_Head = "Head", Draught_Torso = "Torso", Draught_Arms = "Arms", Draught_Legs = "Legs", Draught_Weapon = "Weapon" }

-- Showcase pedestals on each plot: price to unlock pedestal i (0 = free)
-- Battles, trading and betting open once you own this many creatures (learn the core loop first).
Config.UnlockCreatures = 3

-- Lab upgrades, bought at the plot: extra incubators and an auto-stirrer that cooks capsules faster.
Config.LabUpgrades = {
    StartPods = 3,
    PodCost = { [4] = 8000, [5] = 40000 },
    StirrerCost = { 5000, 25000, 100000 },
    StirrerSpeed = 0.15, -- each stirrer level cuts capsule time by 15%
}

-- Legendary Wings: a one-time upgrade for one creature. More power, plus the Sky Wings quirk.
Config.Wings = {
    Cost = 60000,
    Hp = 0.2, Atk = 0.2, Spd = 0.5, Income = 0.25,
    Perk = { icon = "🪽", title = "Sky Wings", desc = "+20% HP and ATK, +50% speed (strikes first), +25% cash" },
}

-- Naming: renaming a creature uses one Name Tag. Tags cost cash here, or come in Robux packs (ShopConfig).
Config.Naming = { TagCost = 25000, MinLength = 3, MaxLength = 20 }

-- Growth Potion: makes one creature bigger and richer. Cost[n] = price of level n.
Config.Growth = { MaxLevel = 5, SizePerLevel = 0.2, IncomePerLevel = 0.35, Cost = { 1000, 4000, 15000, 50000, 150000 } }

Config.ShowcaseUnlock = { 0, 0, 0, 1500, 6000, 20000, 60000, 150000 }
Config.ShowcaseBonus = 1.5      -- pedestal creatures earn this much more than wandering ones
Config.ShowcaseCapSeconds = 1800 -- a pile stops growing after 30 minutes of earnings
return Config
