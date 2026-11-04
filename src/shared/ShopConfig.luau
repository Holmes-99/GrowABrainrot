--[[
    ShopConfig — everything sold for Robux, plus the daily login rewards.

    ▶ HOW TO HOOK UP REAL ROBUX:
      1. Publish the game (File > Publish to Roblox).
      2. Creator Hub > your game > Monetization:
           - Passes: create one pass per entry in ShopConfig.Passes
           - Developer Products: create one product per entry in ShopConfig.Products
      3. Copy each new ID into the matching `id = 0` below, and set the same Robux price.
      While an id is 0, buying it in Studio just gives it to you for free (for testing).
      In a live server an id of 0 shows "coming soon" instead.
]]

local ShopConfig = {}

-- Game passes: bought once, owned forever
ShopConfig.Passes = {
    { key = "VIP",         id = 2068687815, robux = 399, icon = "⭐", name = "VIP",
      desc = "+10% cash, gold VIP tag, DOUBLE daily rewards, and VIP-only decorations: Royal Habitat (+150% cash), Golden Statue, Dream Crystal." },
    { key = "DoubleCash",  id = 2068273847, robux = 499, icon = "💰", name = "2x Cash",
      desc = "Every creature earns double cash. Forever." },
    { key = "LuckyBrewer", id = 0, robux = 349, icon = "🍀", name = "Lucky Brewer",
      desc = "+2 rarity rolls on every brew and +3% shiny chance. Way more Legendaries." },
    { key = "FastBrew",    id = 0, robux = 249, icon = "⚡", name = "Fast Brew",
      desc = "Capsules grow twice as fast. Forever." },
    { key = "BigLab",      id = 0, robux = 199, icon = "🏠", name = "Big Lab",
      desc = "+6 creature slots and +40 part slots." },
}

-- Developer products: buy as many times as you like
-- kind: cash (amount scales with your income), boost (minutes), hatch, restock, refill, part
ShopConfig.Products = {
    { key = "Cash1",          id = 3728060974, robux = 49,  icon = "💵", name = "Pocket Cash",        kind = "cash", base = 5000,   minutes = 10,
      desc = "$5,000 or 10 minutes of your income, whichever is more." },
    { key = "Cash2",          id = 0, robux = 149, icon = "💼", name = "Briefcase of Cash",  kind = "cash", base = 30000,  minutes = 45,
      desc = "$30,000 or 45 minutes of your income, whichever is more." },
    { key = "Cash3",          id = 0, robux = 449, icon = "🏦", name = "Vault of Cash",      kind = "cash", base = 200000, minutes = 180,
      desc = "$200,000 or 3 hours of your income, whichever is more." },
    { key = "CashBoost",      id = 0, robux = 99,  icon = "💸", name = "2x Cash · 30 min",   kind = "boost", boost = "Cash", minutes = 30,
      desc = "Double cash for 30 minutes. Stacks: buy again to add more time." },
    { key = "LuckBoost",      id = 0, robux = 79,  icon = "🍀", name = "Lucky Hour · 30 min", kind = "boost", boost = "Luck", minutes = 30,
      desc = "+2 rarity rolls and +3% shiny for 30 minutes. Stacks." },
    { key = "SpeedBoost",     id = 0, robux = 49,  icon = "⏩", name = "Fast Brew · 30 min", kind = "boost", boost = "FastBrew", minutes = 30,
      desc = "Capsules grow 2x faster for 30 minutes. Stacks." },
    { key = "InstantHatch",   id = 0, robux = 29,  icon = "🥚", name = "Instant Hatch",      kind = "hatch",
      desc = "Every capsule in your incubators is ready to open right now." },
    { key = "SatchelRefill",  id = 0, robux = 59,  icon = "🧪", name = "Elixir Refill",      kind = "refill",
      desc = "Fills your satchel with 10 RARE elixirs (Ember Jaw, Halo Mist, Dreamcandy...)." },
    { key = "MarketRestock",  id = 0, robux = 39,  icon = "🕶️", name = "Black Market Restock", kind = "restock",
      desc = "Brand-new Black Market stock right now, for the whole server." },
    { key = "LegendaryCrate", id = 0, robux = 199, icon = "🗡️", name = "Legendary Weapon",   kind = "part", slot = "Weapon", rarity = "Legendary", mythicChance = 0.1,
      desc = "A guaranteed LEGENDARY weapon (10% chance it's MYTHIC)." },
    { key = "MythicBox",      id = 0, robux = 499, icon = "🌌", name = "Mythic Part Box",    kind = "part", rarity = "Mythic", shinyChance = 0.15,
      desc = "A guaranteed MYTHIC part of any slot. 15% chance it's shiny." },
    -- creature upgrades: bought from a creature's card (it goes to that creature), or from the shop (your best one)
    { key = "GrowPotion",     id = 0, robux = 39,  icon = "🧪", name = "Growth Potion",      kind = "grow",
      desc = "Your creature grows one size bigger right away: +20% size and +35% cash." },
    { key = "Wings",          id = 0, robux = 149, icon = "🪽", name = "Legendary Wings",    kind = "wings",
      desc = "Flapping Sky Wings for your creature: +20% HP and ATK, +50% speed, +25% cash." },
    { key = "NameTags",       id = 0, robux = 29,  icon = "🏷️", name = "Name Tags x3",       kind = "nametags", count = 3,
      desc = "Give 3 creatures their own names. Tap NAME IT on a creature card." },
}

ShopConfig.ProductOrder = { "GrowPotion", "Wings", "NameTags", "CashBoost", "LuckBoost", "SpeedBoost", "InstantHatch", "SatchelRefill", "MarketRestock", "LegendaryCrate", "MythicBox", "Cash1", "Cash2", "Cash3" }

-- Daily rewards: a 7-day streak. Missing a day resets to day 1. VIP doubles cash and boosts.
ShopConfig.Daily = {
    { icon = "💵", text = "Cash",           kind = "cash",   base = 1000,  minutes = 3 },
    { icon = "🧪", text = "3 Rare Elixirs", kind = "elixirs", count = 3 },
    { icon = "💵", text = "Cash",           kind = "cash",   base = 5000,  minutes = 8 },
    { icon = "🍀", text = "Lucky 15 min",   kind = "boost",  boost = "Luck", minutes = 15 },
    { icon = "🟣", text = "Epic Part",      kind = "part",   rarity = "Epic" },
    { icon = "💼", text = "Big Cash",       kind = "cash",   base = 20000, minutes = 20 },
    { icon = "🟡", text = "LEGENDARY Part", kind = "part",   rarity = "Legendary" },
}

ShopConfig.RareElixirs = { "Rizz", "Fanum", "Mewing", "Aura", "Delulu" }

function ShopConfig.pass(key)
    for _, p in ShopConfig.Passes do
        if p.key == key then return p end
    end
end

function ShopConfig.product(key)
    for _, p in ShopConfig.Products do
        if p.key == key then return p end
    end
end

return ShopConfig
