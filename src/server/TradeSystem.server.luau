--[[
    TradeSystem — player-to-player trading of parts, creatures and cash.

    1. A player sends a request from the 🤝 Trade menu ("TradeRequest" userId). It lasts 30s.
    2. The other player accepts ("TradeRespond" { from, accept }) and a trade window opens for both.
    3. Each side adds/removes items ("TradeOffer" { kind, id, add }) and sets cash ("TradeCash" n).
       Up to 8 items a side. Any change un-readies BOTH sides, so nobody can swap something
       out at the last second.
    4. Both press Ready ("TradeReady" true) → 5s countdown → the server re-checks everything
       and swaps it all in one go (no yields in between), then saves both players straight away.
    Leaving, a battle or "TradeCancel" ends the trade. Nothing changes hands until step 4.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LabAPI = require(script.Parent:WaitForChild("LabAPI"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TradeEvent = Instance.new("RemoteEvent")
TradeEvent.Name = "TradeEvent" -- server -> client: "request", "open", "update", "closed"
TradeEvent.Parent = Remotes

local REQUEST_TTL = 30
local REQUEST_COOLDOWN = 4
local MAX_ITEMS = 8
local COUNTDOWN = 5
local MAX_CASH = 1e12

local requests = {}   -- [target] = { from = player, expires = t }
local lastAsk = {}    -- [player] = os.clock()
local tradeOf = {}    -- [player] = trade

local function dataOf(p) return LabAPI.playerData[p.UserId] end
local function other(t, p) return t.a == p and t.b or t.a end

-- the Studio test bot is a plain table, so only real players get remotes, saves and toasts
local function real(p) return typeof(p) == "Instance" end
local function send(p, ...)
    if real(p) and p.Parent then TradeEvent:FireClient(p, ...) end
end
local function note(p, msg, kind)
    if real(p) and p.Parent then LabAPI.notify(p, msg, kind) end
end

local function inBattle(p)
    local b = LabAPI.currentBattle and LabAPI.currentBattle()
    return b ~= nil and b.sides[p] ~= nil
end

local function findById(list, id)
    for i, x in list do
        if x.id == id then return x, i end
    end
    return nil
end

local function deepCopy(t)
    if typeof(t) ~= "table" then return t end
    local c = {}
    for k, v in t do c[k] = deepCopy(v) end
    return c
end

-------------------------------------------------
-- what each side sees
-------------------------------------------------
local function offerView(p, offer)
    local data = dataOf(p)
    local items, value = {}, offer.cash
    if data then
        for _, id in offer.parts do
            local part = findById(data.parts, id)
            if part then
                local v = LabAPI.partValue(part)
                value += v
                table.insert(items, { kind = "part", id = id, name = LabAPI.partName(part), rarity = part.rarity, slot = part.slot, family = part.family, shiny = part.shiny, value = v })
            end
        end
        for _, id in offer.creatures do
            local c = findById(data.creatures, id)
            if c then
                local v = LabAPI.creatureValue(c)
                value += v
                table.insert(items, { kind = "creature", id = id, name = c.name, rarity = c.stats.rarity, parts = c.parts, value = v })
            end
        end
    end
    return { name = p.DisplayName, userId = p.UserId, items = items, cash = offer.cash, value = value, ready = offer.ready }
end

-- drop anything a player sold, fused or built with since they offered it
local function prune(t)
    for _, p in { t.a, t.b } do
        local data, o = dataOf(p), t.offers[p]
        if data then
            for i = #o.parts, 1, -1 do
                if not findById(data.parts, o.parts[i]) then table.remove(o.parts, i) end
            end
            for i = #o.creatures, 1, -1 do
                if not findById(data.creatures, o.creatures[i]) then table.remove(o.creatures, i) end
            end
            o.cash = math.min(o.cash, math.max(0, math.floor(data.money)))
        end
    end
end

local function push(t)
    prune(t)
    local countdown = t.goAt and math.max(0, t.goAt - os.clock()) or nil
    for _, p in { t.a, t.b } do
        if p.Parent then
            send(p, "update", {
                me = offerView(p, t.offers[p]), them = offerView(other(t, p), t.offers[other(t, p)]),
                countdown = countdown, maxItems = MAX_ITEMS,
            })
        end
    end
end

local function closeTrade(t, reason)
    if t.closed then return end
    t.closed = true
    for _, p in { t.a, t.b } do
        if tradeOf[p] == t then tradeOf[p] = nil end
        send(p, "closed", { reason = reason })
        if reason ~= "done" then note(p, "🤝 " .. reason, "info") end
    end
end

local function unready(t)
    t.offers[t.a].ready = false
    t.offers[t.b].ready = false
    t.goAt = nil
end

-------------------------------------------------
-- the swap
-------------------------------------------------
local function validate(t)
    for _, p in { t.a, t.b } do
        local data = dataOf(p)
        if not (data and p.Parent) then return false, "Someone left." end
        local o = t.offers[p]
        for _, id in o.parts do
            if not findById(data.parts, id) then return false, p.DisplayName .. " doesn't have one of those parts any more." end
        end
        for _, id in o.creatures do
            if not findById(data.creatures, id) then return false, p.DisplayName .. " doesn't have one of those creatures any more." end
        end
        if o.cash > data.money then return false, p.DisplayName .. " doesn't have that much cash any more." end
    end
    for _, p in { t.a, t.b } do
        local data, q = dataOf(p), other(t, p)
        local mine, theirs = t.offers[p], t.offers[q]
        if #data.parts - #mine.parts + #theirs.parts > LabAPI.maxParts(data) then
            return false, p.DisplayName .. "'s part bag would be too full."
        end
        if #data.creatures - #mine.creatures + #theirs.creatures > LabAPI.maxCreatures(data) then
            return false, p.DisplayName .. "'s lab would be too full of creatures."
        end
        if #theirs.creatures > 0 and not data.plotId then
            return false, p.DisplayName .. " has no lab for a creature to live in."
        end
    end
    return true
end

local function execute(t)
    local ok, why = validate(t)
    if not ok then
        unready(t)
        for _, p in { t.a, t.b } do note(p, "Trade not done: " .. why, "bad") end
        push(t)
        return
    end
    -- take everything out first, then hand it over (no yields from here to the end)
    local moving = {}
    for _, p in { t.a, t.b } do
        local data, o = dataOf(p), t.offers[p]
        local pack = { parts = {}, creatures = {}, cash = o.cash }
        for _, id in o.parts do
            local part, i = findById(data.parts, id)
            table.insert(pack.parts, table.remove(data.parts, i))
        end
        for _, id in o.creatures do
            local c, i = findById(data.creatures, id)
            table.remove(data.creatures, i)
            if real(p) then LabAPI.removeCreatureModel(p, c.id) end
            table.insert(pack.creatures, c)
        end
        data.money -= o.cash
        moving[p] = pack
    end
    local summary = {}
    for _, p in { t.a, t.b } do
        local q = other(t, p)
        local data, pack = dataOf(q), moving[p]
        local got = {}
        for _, part in pack.parts do
            part.id = LabAPI.newId(data)
            table.insert(data.parts, part)
            local key = part.slot .. ":" .. part.family
            data.discoveries[key] = math.max(data.discoveries[key] or 0, LabAPI.rarityRank(part.rarity))
            table.insert(got, LabAPI.partName(part))
        end
        for _, c in pack.creatures do
            local nc = deepCopy(c)
            nc.id = LabAPI.newId(data)
            nc.cage, nc.cageBonus = nil, 0
            table.insert(data.creatures, nc)
            if real(q) then LabAPI.spawnCreatureModel(q, data, nc) end
            table.insert(got, nc.name)
        end
        if pack.cash > 0 then
            data.money += pack.cash
            table.insert(got, "$" .. LabAPI.fmt(pack.cash))
        end
        summary[q] = got
    end
    closeTrade(t, "done")
    for _, p in { t.a, t.b } do
        local data = dataOf(p)
        if real(p) then
            LabAPI.creaturesChanged:Fire(p, data)
            LabAPI.sendState(p)
        end
        local got = summary[p]
        note(p, "🤝 Trade complete! You got: " .. (#got > 0 and table.concat(got, ", ") or "nothing"), "good")
        if real(p) then task.spawn(LabAPI.saveNow, p, false) end -- lock it in on both sides
    end
end

-------------------------------------------------
-- requests from TradeClient
-------------------------------------------------
LabAPI.requests.TradeRequest = function(player, targetId)
    local target = typeof(targetId) == "number" and Players:GetPlayerByUserId(targetId)
    if not target or target == player or not dataOf(target) then return end
    if tradeOf[player] or tradeOf[target] then
        note(player, tradeOf[player] and "Finish your current trade first." or (target.DisplayName .. " is already trading."), "info")
        return
    end
    if inBattle(player) or inBattle(target) then
        note(player, "Can't trade during a battle.", "info")
        return
    end
    if lastAsk[player] and os.clock() - lastAsk[player] < REQUEST_COOLDOWN then return end
    lastAsk[player] = os.clock()
    requests[target] = { from = player, expires = os.clock() + REQUEST_TTL }
    send(target, "request", { from = player.UserId, name = player.DisplayName, ttl = REQUEST_TTL })
    note(player, "🤝 Trade request sent to " .. target.DisplayName .. ".", "info")
end

LabAPI.requests.TradeRespond = function(player, arg)
    if typeof(arg) ~= "table" then return end
    local req = requests[player]
    if not req or req.from.UserId ~= arg.from then return end
    requests[player] = nil
    local from = req.from
    if not arg.accept then
        if from.Parent then note(from, player.DisplayName .. " declined your trade.", "info") end
        return
    end
    if os.clock() > req.expires or not from.Parent or not dataOf(from) then
        note(player, "That trade request expired.", "info")
        return
    end
    if tradeOf[player] or tradeOf[from] then
        note(player, "One of you is already trading.", "info")
        return
    end
    local t = { a = from, b = player, offers = {} }
    for _, p in { from, player } do
        t.offers[p] = { parts = {}, creatures = {}, cash = 0, ready = false }
        tradeOf[p] = t
        send(p, "open", { with = other(t, p).DisplayName })
    end
    push(t)
end

LabAPI.requests.TradeOffer = function(player, arg)
    local t = tradeOf[player]
    if not t or typeof(arg) ~= "table" or typeof(arg.id) ~= "number" then return end
    local data, o = dataOf(player), t.offers[player]
    local list = arg.kind == "part" and o.parts or (arg.kind == "creature" and o.creatures) or nil
    if not list then return end
    local at = table.find(list, arg.id)
    if arg.add then
        if at then return end
        if #o.parts + #o.creatures >= MAX_ITEMS then
            note(player, ("Up to %d items per trade."):format(MAX_ITEMS), "info")
            return
        end
        local owned = arg.kind == "part" and findById(data.parts, arg.id) or findById(data.creatures, arg.id)
        if not owned then return end
        table.insert(list, arg.id)
    else
        if not at then return end
        table.remove(list, at)
    end
    unready(t)
    push(t)
end

LabAPI.requests.TradeCash = function(player, amount)
    local t = tradeOf[player]
    if not t or typeof(amount) ~= "number" or amount ~= amount then return end
    local data = dataOf(player)
    amount = math.clamp(math.floor(amount), 0, math.min(MAX_CASH, data.money))
    if t.offers[player].cash == amount then return end
    t.offers[player].cash = amount
    unready(t)
    push(t)
end

LabAPI.requests.TradeReady = function(player, on)
    local t = tradeOf[player]
    if not t then return end
    t.offers[player].ready = on == true
    local both = t.offers[t.a].ready and t.offers[t.b].ready
    if both and not t.goAt then
        local o1, o2 = t.offers[t.a], t.offers[t.b]
        if #o1.parts + #o1.creatures + o1.cash + #o2.parts + #o2.creatures + o2.cash == 0 then
            t.offers[player].ready = false
            note(player, "Add something to the trade first.", "info")
        else
            t.goAt = os.clock() + COUNTDOWN
        end
    elseif not both then
        t.goAt = nil
    end
    push(t)
end

LabAPI.requests.TradeCancel = function(player)
    local t = tradeOf[player]
    if t then
        closeTrade(t, player.DisplayName .. " cancelled the trade.")
    end
end

-------------------------------------------------
-- countdowns, timeouts, leavers
-------------------------------------------------
task.spawn(function()
    while true do
        task.wait(0.25)
        local seen = {}
        for p, t in tradeOf do
            if not seen[t] then
                seen[t] = true
                if not (t.a.Parent and t.b.Parent) or not (dataOf(t.a) and dataOf(t.b)) then
                    closeTrade(t, "The other player left.")
                elseif inBattle(t.a) or inBattle(t.b) then
                    closeTrade(t, "Trade cancelled: a battle started.")
                elseif t.goAt and os.clock() >= t.goAt then
                    t.goAt = nil
                    execute(t)
                end
            end
        end
        for target, req in requests do
            if os.clock() > req.expires or not target.Parent then requests[target] = nil end
        end
    end
end)

-------------------------------------------------
-- STUDIO-ONLY test partner (never exists in a live server)
--   local f = game.ServerStorage.DebugTradeBot
--   f:Invoke(player, "request")  -- the bot asks you to trade (accept it in the UI)
--   f:Invoke(player, "offer")    -- the bot puts a Legendary part + $1,000 in
--   f:Invoke(player, "ready")    -- the bot presses Ready
-------------------------------------------------
if game:GetService("RunService"):IsStudio() then
    local bot = { UserId = -1, DisplayName = "TestBot", Name = "TestBot", Parent = Players }
    local f = Instance.new("BindableFunction")
    f.Name = "DebugTradeBot"
    f.OnInvoke = function(player, cmd)
        if not LabAPI.playerData[bot.UserId] then
            LabAPI.playerData[bot.UserId] = {
                money = 50000, parts = { { id = 1, slot = "Head", family = "Aura", rarity = "Legendary", shiny = false } },
                creatures = {}, discoveries = {}, nextId = 100, rebirths = 0, passes = {}, plotId = nil,
            }
        end
        local bd = LabAPI.playerData[bot.UserId]
        if cmd == "request" then
            requests[player] = { from = bot, expires = os.clock() + REQUEST_TTL }
            send(player, "request", { from = bot.UserId, name = bot.DisplayName, ttl = REQUEST_TTL })
        elseif cmd == "offer" then
            local t = tradeOf[bot]
            if not t then return "no trade" end
            t.offers[bot].parts = { bd.parts[1] and bd.parts[1].id or nil }
            t.offers[bot].cash = 1000
            unready(t)
            push(t)
        elseif cmd == "ready" then
            LabAPI.requests.TradeReady(bot, true)
        elseif cmd == "data" then
            return ("bot: $%d, %d parts, %d creatures"):format(bd.money, #bd.parts, #bd.creatures)
        end
        return "ok"
    end
    f.Parent = game:GetService("ServerStorage")
end

Players.PlayerRemoving:Connect(function(p)
    local t = tradeOf[p]
    if t then closeTrade(t, p.DisplayName .. " left the game.") end
    requests[p] = nil
    lastAsk[p] = nil
end)
