--[[
    Naming — give a creature your own name.

    * "RenameCreature" { id, name }: uses one Name Tag (data.nameTags). With no tags left it buys
      one for Config.Naming.TagCost cash. VIPs rename for free. Name Tag packs are a Robux product.
    * Every name goes through Roblox's text filter (required for names other players can see).
    * "ResetName" id puts the original part-based name back (free).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local LabAPI = require(script.Parent:WaitForChild("LabAPI"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local PartsLogic = require(ReplicatedStorage:WaitForChild("PartsLogic"))
LabAPI.waitReady()

local N = Config.Naming

local function findCreature(data, id)
    for _, c in data.creatures do
        if c.id == id then return c end
    end
end

local function respawn(player, data, c)
    LabAPI.removeCreatureModel(player, c.id)
    LabAPI.spawnCreatureModel(player, data, c)
    LabAPI.creaturesChanged:Fire(player, data)
    LabAPI.sendState(player)
end

local function filter(player, text)
    local ok, result = pcall(function()
        return TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()
    end)
    if not ok then return nil, "The name checker is busy. Try again in a moment." end
    if result ~= text or result:find("#") then return nil, "That name isn't allowed. Try another one!" end
    return result
end

LabAPI.requests.RenameCreature = function(player, arg)
    local data = LabAPI.playerData[player.UserId]
    if not (data and typeof(arg) == "table" and typeof(arg.name) == "string") then return end
    local c = findCreature(data, arg.id)
    if not c then return end
    local name = arg.name:gsub("%s+", " "):match("^%s*(.-)%s*$")
    if utf8.len(name) == nil or utf8.len(name) < N.MinLength or utf8.len(name) > N.MaxLength then
        LabAPI.notify(player, ("Names need %d to %d letters."):format(N.MinLength, N.MaxLength), "bad")
        return
    end
    local vip = data.passes and data.passes.VIP == true
    data.nameTags = data.nameTags or 0
    if not vip and data.nameTags <= 0 and data.money < N.TagCost then
        LabAPI.notify(player, ("You need a 🏷️ Name Tag: $%s, or get a pack in the 💎 Shop."):format(LabAPI.fmt(N.TagCost)), "bad")
        return
    end
    local clean, why = filter(player, name)
    if not clean then
        LabAPI.notify(player, why, "bad")
        return
    end
    -- pay only once the name passed the filter
    local paid
    if vip then
        paid = "free for VIP"
    elseif data.nameTags > 0 then
        data.nameTags -= 1
        paid = ("used a Name Tag, %d left"):format(data.nameTags)
    else
        data.money -= N.TagCost
        paid = "$" .. LabAPI.fmt(N.TagCost)
    end
    c.name = clean
    c.named = true
    LabAPI.notify(player, ("🏷️ Your creature is now called %s! (%s)"):format(clean, paid), "good")
    respawn(player, data, c)
end

LabAPI.requests.ResetName = function(player, id)
    local data = LabAPI.playerData[player.UserId]
    local c = data and findCreature(data, id)
    if not (c and c.named) then return end
    c.name = PartsLogic.creatureName(c.parts)
    c.named = nil
    LabAPI.notify(player, "Back to its original name: " .. c.name, "info")
    respawn(player, data, c)
end

-- Robux pack (Monetization calls this)
function LabAPI.addNameTags(player, data, n)
    data.nameTags = (data.nameTags or 0) + n
    LabAPI.notify(player, ("🏷️ +%d Name Tags! Open 🐾 Creatures and tap NAME IT."):format(n), "rare")
end

table.insert(LabAPI.stateHooks, function(data, st)
    st.nameTags = data.nameTags or 0
end)

print("[Naming] ready")
