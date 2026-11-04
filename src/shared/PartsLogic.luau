--[[
    PartsLogic — shared by server and client: turns a set of parts into
    a creature's name, stats, perks and income (before lab-wide bonuses).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local PartsLogic = {}

local function rarityRank(r) return Config.RarityRank[r] or 1 end
local function rarityAt(rank) return Config.RarityOrder[math.clamp(rank, 1, #Config.RarityOrder)] end

function PartsLogic.power(part)
    if not part then return 0 end
    return (Config.RarityPower[part.rarity] or 1) * (part.shiny and 1.5 or 1)
end

function PartsLogic.creatureName(parts)
    local fams = {}
    for _, p in parts do fams[p.family] = (fams[p.family] or 0) + 1 end
    for fam, k in fams do
        if k >= 5 then return Config.PureNames[fam] end
    end
    local h = parts.Head and parts.Head.family or parts.Torso.family
    local t = parts.Torso and parts.Torso.family or h
    return Config.NamePrefix[h] .. " " .. Config.NameSuffix[t]
end

function PartsLogic.analyze(parts)
    local s = { perks = {}, traits = {} }
    local fams, maxFam, count, rankSum = {}, 0, 0, 0
    for _, p in parts do
        fams[p.family] = (fams[p.family] or 0) + 1
        maxFam = math.max(maxFam, fams[p.family])
        count += 1
        rankSum += rarityRank(p.rarity)
    end
    s.setMult = 1 + ((maxFam >= 5 and Config.SetBonus5) or (maxFam >= 3 and Config.SetBonus3) or 0)
    s.setCount = maxFam
    s.rarity = rarityAt(math.floor(rankSum / math.max(1, count) + 0.5))

    local hp = 40 + 50 * PartsLogic.power(parts.Torso) + 12 * PartsLogic.power(parts.Head) + 10 * PartsLogic.power(parts.Legs)
    local atk = 5 + 6 * PartsLogic.power(parts.Arms) + 8 * PartsLogic.power(parts.Weapon) + 2 * PartsLogic.power(parts.Head)
    local spd = 4 + 1.2 * PartsLogic.power(parts.Legs)
    local income = 0
    for slot, p in parts do
        income += (Config.PartIncome[p.rarity] or 1) * (slot == "Torso" and 2 or 1) * (p.shiny and 1.5 or 1)
    end
    s.crit, s.splash, s.charm, s.lifesteal = 0, 0, 0, 0

    for _, slot in Config.Slots do
        local p = parts[slot]
        if p then
            local perk = Config.PartPerks[slot][p.family]
            table.insert(s.perks, { slot = slot, icon = perk.icon, title = perk.title, desc = perk.desc, rarity = p.rarity })
            if perk.trait then table.insert(s.traits, perk.trait) end
            local f = p.family
            if slot == "Head" then
                if f == "Sigma" then income *= 1.5 end
                if f == "Skibidi" then s.hype = true end
                if f == "Mewing" then income *= 1.25; atk *= 1.15 end
                if f == "Delulu" then income *= 2; hp *= 0.75 end
            elseif slot == "Torso" then
                if f == "Sigma" then s.heal = true end
                if f == "Ohio" then s.guard = true end
                if f == "Rizz" then hp *= 1.4 end
                if f == "Fanum" then s.lifesteal += 0.2 end
                if f == "Mewing" then hp *= 1.2; atk *= 1.1 end
                if f == "Aura" then hp *= 1.2; s.heal = true end
                if f == "Delulu" then income *= 1.25 end
            elseif slot == "Arms" then
                if f == "Sigma" then atk *= 1.15 end
                if f == "Ohio" then s.crit += 0.1 end
                if f == "Skibidi" then atk *= 1.1 end
                if f == "Rizz" then income *= 1.05 end
                if f == "Fanum" then s.grab = true end
                if f == "Mewing" then atk *= 1.25 end
                if f == "Aura" then s.crit += 0.15 end
                if f == "Delulu" then atk *= 1.1; s.charm += 0.1 end
            elseif slot == "Legs" then
                if f == "Sigma" then spd += 2 end
                if f == "Ohio" then s.phase = true end
                if f == "Skibidi" then hp *= 1.25; spd -= 1 end
                if f == "Rizz" then spd += 3 end
                if f == "Fanum" then spd += 1; hp *= 1.1 end
                if f == "Mewing" then hp *= 1.15; spd += 1 end
                if f == "Aura" then s.phase = true; spd += 2 end
                if f == "Delulu" then spd += 4; hp *= 0.9 end
            elseif slot == "Weapon" then
                if f == "Sigma" then s.crit += 0.25 end
                if f == "Ohio" then s.ambush = true end
                if f == "Skibidi" then s.splash = 0.35 end
                if f == "Rizz" then s.charm = 0.2 end
                if f == "Fanum" then s.lifesteal += 0.3 end
                if f == "Mewing" then s.crit += 0.15; s.grab = true end
                if f == "Aura" then s.splash = math.max(s.splash, 0.25); s.lifesteal += 0.1 end
                if f == "Delulu" then s.charm += 0.3 end
            end
        end
    end
    if maxFam >= 3 then
        table.insert(s.perks, { slot = "Set", icon = "🧩", title = ("%d-piece set"):format(maxFam), desc = ("+%d%% stats and income."):format(math.floor((s.setMult - 1) * 100 + 0.5)) })
    end
    s.hp = math.floor(hp * s.setMult)
    s.atk = math.floor(atk * s.setMult)
    s.spd = math.max(1, math.floor(spd * 10 + 0.5) / 10)
    s.baseIncome = income * s.setMult
    s.power = s.hp + s.atk * 4
    return s
end

return PartsLogic
