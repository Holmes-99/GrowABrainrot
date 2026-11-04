--[[
    BattleMoves — turn-based battle rules shared by the server (BattleSystem) and the client (BattleClient).

    Every part a creature wears gives it one move. The SLOT decides what kind of move it is,
    the FAMILY (the potion it was brewed from) decides its name and its side effect:

      Head   → Signature  power 0.75, effect always triggers, 2-turn cooldown
      Torso  → Guard      no damage; shields, heals or buffs the user, 2-turn cooldown
      Arms   → Strike     power 1.0, 30% effect chance
      Legs   → Quick      power 0.65, always goes first, 25% effect chance
      Weapon → Heavy      power 1.5, 50% effect chance, 2-turn cooldown

    Timing bar: picking a move starts a needle sweeping across a bar. Stop it inside the
    zone: PERFECT x1.5, GREAT x1.2, GOOD x1.0, otherwise MISS x0.7. The server times the tap
    itself (it measures from when your move arrived to when your tap arrived).
]]

local BattleMoves = {}

BattleMoves.SLOT_KIND = {
    Head =   { kind = "attack", power = 0.75, chance = 1.0,  cooldown = 2, label = "Signature" },
    Torso =  { kind = "guard",  power = 0,    chance = 1.0,  cooldown = 2, label = "Guard" },
    Arms =   { kind = "attack", power = 1.0,  chance = 0.3,  cooldown = 0, label = "Strike" },
    Legs =   { kind = "attack", power = 0.65, chance = 0.25, cooldown = 0, label = "Quick", priority = true },
    Weapon = { kind = "attack", power = 1.5,  chance = 0.5,  cooldown = 2, label = "Heavy" },
}
BattleMoves.SLOT_ORDER = { "Head", "Arms", "Legs", "Weapon", "Torso" }

-- side effect each family's ATTACKS can cause
BattleMoves.EFFECTS = {
    Sigma =   { id = "freeze",  icon = "🧊", text = "Freeze: the target loses its next move." },
    Ohio =    { id = "blind",   icon = "🌑", text = "Blind: the target's next attack has a 50% chance to miss." },
    Skibidi = { id = "bleed",   icon = "🩸", text = "Bleed: 5% max HP damage for 3 turns." },
    Rizz =    { id = "charm",   icon = "💛", text = "Charm: the target's next attack deals half damage." },
    Fanum =   { id = "poison",  icon = "☠️", text = "Poison: 6% max HP damage for 3 turns." },
    Mewing =  { id = "pump",    icon = "🔥", text = "Pump: the user gets +15% attack (stacks to +45%)." },
    Aura =    { id = "drain",   icon = "✨", text = "Drain: the user heals 35% of the damage dealt." },
    Delulu =  { id = "confuse", icon = "🍭", text = "Confuse: the target's next move may hit itself." },
}

-- what each family's TORSO (guard) move does
BattleMoves.GUARDS = {
    Sigma =   { shield = 0.6,                 text = "Blocks 60% of the next hit." },
    Ohio =    { dodge = true,                 text = "Dodges the next hit completely." },
    Skibidi = { shield = 0.4, counter = 0.6,  text = "Blocks 40% of the next hit and throws 60% of it back." },
    Rizz =    { shield = 0.5, pump = 0.1,     text = "Blocks 50% of the next hit and +10% attack." },
    Fanum =   { heal = 0.22,                  text = "Heals 22% of max HP." },
    Mewing =  { shield = 0.2, pump = 0.25,    text = "+25% attack and blocks 20% of the next hit." },
    Aura =    { heal = 0.18, cleanse = true,  text = "Heals 18% of max HP and removes bad effects." },
    Delulu =  { gamble = true,                text = "50/50: heal 30% of max HP, or dodge the next hit." },
}

-- names that match the potion each part came from
BattleMoves.NAMES = {
    Sigma =   { Head = { "Mind Freeze", "🧠" },     Torso = { "Ice Wall", "🧊" },        Arms = { "Frost Jab", "❄️" },     Legs = { "Glacier Glide", "⛸️" },  Weapon = { "Briefcase Blizzard", "💼" } },
    Ohio =    { Head = { "Void Stare", "👁️" },      Torso = { "Phase Out", "🌀" },       Arms = { "Shadow Rake", "🌑" },   Legs = { "Void Step", "👣" },       Weapon = { "Rift Slash", "🗡️" } },
    Skibidi = { Head = { "Crimson Roar", "📣" },    Torso = { "Iron Grip Guard", "🛡️" }, Arms = { "Crimson Grab", "🩸" },  Legs = { "Throne Stomp", "🚽" },    Weapon = { "Plunger Cannon", "💥" } },
    Rizz =    { Head = { "Golden Wink", "😏" },     Torso = { "Gold Plating", "🪙" },    Arms = { "Gilded Slap", "💰" },   Legs = { "Drip Dash", "👟" },       Weapon = { "Heartbreaker Shot", "💘" } },
    Fanum =   { Head = { "Venom Bite", "🐍" },      Torso = { "Snack Break", "🍗" },     Arms = { "Toxic Swipe", "☠️" },   Legs = { "Poison Pounce", "🐾" },   Weapon = { "Fang Fork", "🔱" } },
    Mewing =  { Head = { "Ember Jaw Snap", "🗿" },  Torso = { "Flex Up", "💪" },         Arms = { "Blazing Flex", "🔥" },  Legs = { "Leg Day Kick", "🦵" },    Weapon = { "Dumbbell Slam", "🏋️" } },
    Aura =    { Head = { "Halo Beam", "😇" },       Torso = { "Halo Mend", "💖" },       Arms = { "Light Palm", "✋" },    Legs = { "Cloud Drift", "☁️" },     Weapon = { "Judgement Orb", "🔮" } },
    Delulu =  { Head = { "Sugar Daydream", "💭" },  Torso = { "Daydream", "🌈" },        Arms = { "Noodle Whip", "🍜" },   Legs = { "Boing Bounce", "🦘" },    Weapon = { "Lollipop Crash", "🍭" } },
}

BattleMoves.TACKLE = { slot = "None", family = "None", name = "Tackle", icon = "👊", kind = "attack", power = 0.8, chance = 0, cooldown = 0, desc = "A plain hit." }

-- the move list for a set of parts (slot -> part)
function BattleMoves.movesFor(parts)
    local list = {}
    for _, slot in BattleMoves.SLOT_ORDER do
        local p = parts[slot]
        if p and p.family and BattleMoves.NAMES[p.family] then
            local base = BattleMoves.SLOT_KIND[slot]
            local nm = BattleMoves.NAMES[p.family][slot]
            local mv = {
                slot = slot, family = p.family, name = nm[1], icon = nm[2], kind = base.kind,
                power = base.power * (p.shiny and 1.1 or 1), chance = base.chance, cooldown = base.cooldown,
                priority = base.priority, label = base.label,
            }
            if base.kind == "guard" then
                mv.desc = BattleMoves.GUARDS[p.family].text
            else
                local fx = BattleMoves.EFFECTS[p.family]
                local pct = math.floor(base.chance * 100 + 0.5)
                local odds = pct < 100 and (pct .. "% chance of ") or ""
                mv.desc = ("%s hit x%.2f%s. "):format(base.label, mv.power, base.priority and ", goes first" or "") .. odds .. fx.text
            end
            table.insert(list, mv)
        end
    end
    local attacks = 0
    for _, mv in list do if mv.kind == "attack" then attacks += 1 end end
    if attacks < 2 then table.insert(list, 1, table.clone(BattleMoves.TACKLE)) end
    return list
end

-- timing bar
BattleMoves.SWEEP = 0.8        -- seconds for the needle to cross the bar once
BattleMoves.BAR_TIMEOUT = 3.2  -- no tap by then = MISS
BattleMoves.CHOOSE_TIME = 20   -- seconds to pick a move
BattleMoves.ZONES = {          -- distance from the zone centre (bar is 0..1)
    { name = "PERFECT", within = 0.06, mult = 1.5 },
    { name = "GREAT",   within = 0.14, mult = 1.2 },
    { name = "GOOD",    within = 0.26, mult = 1.0 },
}
BattleMoves.MISS = { name = "MISS", mult = 0.7 }

-- needle position (0..1) after t seconds: bounces back and forth
function BattleMoves.needle(t)
    local p = (t % (BattleMoves.SWEEP * 2)) / BattleMoves.SWEEP
    return p > 1 and 2 - p or p
end

function BattleMoves.grade(pos, center)
    local d = math.abs(pos - center)
    for _, z in BattleMoves.ZONES do
        if d <= z.within then return z end
    end
    return BattleMoves.MISS
end

return BattleMoves
