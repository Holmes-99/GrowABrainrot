--[[
    Monetization — Robux game passes, developer products, timed boosts,
    daily login rewards and the VIP tag.

    IDs and prices live in ReplicatedStorage.ShopConfig.
    * Passes: ownership is checked on join (UserOwnsGamePassAsync) and right after buying.
    * Products: granted in ProcessReceipt. Every PurchaseId is remembered in data.receipts
      and saved straight away, so a purchase is never granted twice or lost.
    * Studio: anything with id = 0 is granted for free when you "buy" it, for testing.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LabAPI = require(script.Parent:WaitForChild("LabAPI"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))

local IS_STUDIO = RunService:IsStudio()

local function today(): number
    return math.floor(os.time() / 86400)
end

local function hasVip(data) return data.passes and data.passes.VIP == true end

-------------------------------------------------
-- VIP name tag
-------------------------------------------------
local function tagCharacter(player, char)
    local data = LabAPI.playerData and LabAPI.playerData[player.UserId]
    local head = char:WaitForChild("Head", 10)
    if not (head and data and hasVip(data)) or head:FindFirstChild("VipTag") then return end
    local bb = Instance.new("BillboardGui")
    bb.Name = "VipTag"
    bb.Size = UDim2.fromOffset(110, 26)
    bb.StudsOffset = Vector3.new(0, 2.6, 0)
    bb.MaxDistance = 80
    bb.AlwaysOnTop = false
    bb.Parent = head
    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.fromScale(1, 1)
    tl.BackgroundTransparency = 1
    tl.Text = "⭐ VIP"
    tl.TextScaled = true
    tl.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
    tl.TextColor3 = Color3.fromRGB(255, 205, 60)
    tl.TextStrokeTransparency = 0.2
    tl.Parent = bb
end

-------------------------------------------------
-- passes
-------------------------------------------------
local function grantPass(player, data, pass, announce)
    if data.passes[pass.key] then return end
    data.passes[pass.key] = true
    if pass.key == "VIP" and player.Character then
        task.spawn(tagCharacter, player, player.Character)
    end
    if announce then
        LabAPI.notify(player, ("%s %s unlocked! Thank you!"):format(pass.icon, pass.name), "rare")
        LabAPI.broadcast(("%s just got %s %s!"):format(player.DisplayName, pass.icon, pass.name), "rare", player)
    end
    LabAPI.sendState(player)
end

LabAPI.playerLoaded:Connect(function(player, data)
    data.passes = data.passes or {}
    data.boosts = data.boosts or {}
    data.daily = data.daily or { day = 0, streak = 0 }
    data.receipts = data.receipts or {}
    local returning = data.seenIntro == true -- brand-new players get the intro first, not the calendar
    task.spawn(function()
        for _, pass in ShopConfig.Passes do
            if pass.id ~= 0 then
                local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.id)
                if ok and owns then data.passes[pass.key] = true end
            end
        end
        if player.Character then tagCharacter(player, player.Character) end
        LabAPI.sendState(player)
        -- daily reward popup
        if returning and data.daily.day < today() then
            task.wait(4)
            if player.Parent then LabAPI.openUI(player, "daily") end
        end
    end)
end)

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char) tagCharacter(player, char) end)
end)
for _, p in Players:GetPlayers() do
    p.CharacterAdded:Connect(function(char) tagCharacter(p, char) end)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
    if not purchased then return end
    local data = LabAPI.playerData[player.UserId]
    if not data then return end
    for _, pass in ShopConfig.Passes do
        if pass.id == passId then grantPass(player, data, pass, true) end
    end
end)

-------------------------------------------------
-- products
-------------------------------------------------
local function cashAmount(data, base, minutes)
    -- totalIncome is "per 10 seconds"
    return math.floor(math.max(base, LabAPI.totalIncome(data) / 10 * 60 * minutes))
end

local function addBoost(data, name, minutes)
    data.boosts[name] = math.max(os.time(), data.boosts[name] or 0) + minutes * 60
end

local function randomRareElixirs(n)
    local t = {}
    for i = 1, n do
        t[i] = ShopConfig.RareElixirs[math.random(1, #ShopConfig.RareElixirs)]
    end
    return t
end

-- returns true when granted
local function grantProduct(player, data, prod)
    local kind = prod.kind
    if kind == "cash" then
        local amount = cashAmount(data, prod.base, prod.minutes)
        data.money += amount
        LabAPI.notify(player, ("%s +$%s! Go cop something nice."):format(prod.icon, LabAPI.fmt(amount)), "rare")
    elseif kind == "boost" then
        addBoost(data, prod.boost, prod.minutes)
        LabAPI.notify(player, ("%s %s active!"):format(prod.icon, prod.name), "rare")
    elseif kind == "hatch" then
        local t = workspace:GetServerTimeNow()
        local n = 0
        for podId, pod in data.pods do
            pod.finish = math.min(pod.finish, t)
            local num = tonumber(podId:match("_Pod(%d+)$"))
            if num and data.plotId then LabAPI.setPodVisual(data.plotId, num, pod) end
            n += 1
        end
        LabAPI.notify(player, n > 0 and ("🥚 %d capsule%s ready to open!"):format(n, n > 1 and "s" or "") or "🥚 No capsules were growing. Brew one first!", n > 0 and "rare" or "info")
    elseif kind == "refill" then
        data.ingredients = randomRareElixirs(Config.SatchelSize)
        LabAPI.notify(player, "🧪 Satchel full of rare elixirs! Go brew at your cauldron.", "rare")
    elseif kind == "restock" then
        LabAPI.refreshMarket()
        LabAPI.broadcast(("🕶️ %s restocked the Black Market! Fresh parts on Market Street."):format(player.DisplayName), "rare")
        for _, p in Players:GetPlayers() do LabAPI.sendState(p) end
    elseif kind == "part" then
        local rarity = prod.rarity
        if prod.mythicChance and math.random() < prod.mythicChance then rarity = "Mythic" end
        local part = LabAPI.randomPart(prod.slot, rarity, prod.shinyChance or Config.ShinyChance)
        LabAPI.revealPart(player, data, part)
    elseif kind == "grow" or kind == "wings" then
        -- goes to the creature whose card was tapped; otherwise to the best creature that can still take it
        local function eligible(c)
            if kind == "grow" then return (c.growth or 0) < Config.Growth.MaxLevel end
            return not c.wings
        end
        local target
        for _, c in data.creatures do
            if c.id == data.productTarget and eligible(c) then target = c end
        end
        if not target then
            for _, c in data.creatures do
                if eligible(c) and (not target or LabAPI.creatureIncome(data, c) > LabAPI.creatureIncome(data, target)) then target = c end
            end
        end
        data.productTarget = nil
        local ok = target and (kind == "grow" and LabAPI.growCreature(player, target.id, true) or kind == "wings" and LabAPI.addWings(player, target.id, true))
        if not ok then
            -- nothing could take it: pay out its cash value instead so the purchase is never wasted
            local refund = kind == "grow" and 25000 or Config.Wings.Cost
            data.money += refund
            LabAPI.notify(player, ("%s No creature could use %s, so you got $%s instead."):format(prod.icon, prod.name, LabAPI.fmt(refund)), "rare")
        end
    elseif kind == "nametags" then
        LabAPI.addNameTags(player, data, prod.count or 3)
    else
        return false
    end
    LabAPI.sendState(player)
    return true
end

MarketplaceService.ProcessReceipt = function(receipt)
    local player = Players:GetPlayerByUserId(receipt.PlayerId)
    local data = player and LabAPI.playerData[receipt.PlayerId]
    if not data then
        return Enum.ProductPurchaseDecision.NotProcessedYet -- they'll get it next time they join
    end
    if table.find(data.receipts, receipt.PurchaseId) then
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end
    local prod
    for _, p in ShopConfig.Products do
        if p.id == receipt.ProductId then prod = p end
    end
    if not prod then
        warn("[Monetization] unknown product " .. tostring(receipt.ProductId))
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    local ok, granted = pcall(grantProduct, player, data, prod)
    if not (ok and granted) then
        warn("[Monetization] grant failed: " .. tostring(granted))
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    table.insert(data.receipts, receipt.PurchaseId)
    while #data.receipts > 60 do table.remove(data.receipts, 1) end
    LabAPI.saveNow(player, false) -- lock the purchase in right away
    return Enum.ProductPurchaseDecision.PurchaseGranted
end

-------------------------------------------------
-- requests from ShopClient
-------------------------------------------------
LabAPI.requests.BuyPass = function(player, key)
    local data = LabAPI.playerData[player.UserId]
    local pass = ShopConfig.pass(key)
    if not (data and pass) then return end
    if data.passes[pass.key] then
        LabAPI.notify(player, "You already own " .. pass.name .. ".", "info")
        return
    end
    if pass.id == 0 then
        if IS_STUDIO then
            grantPass(player, data, pass, true) -- Studio test purchase
        else
            LabAPI.notify(player, pass.name .. " is coming soon!", "info")
        end
        return
    end
    MarketplaceService:PromptGamePassPurchase(player, pass.id)
end

LabAPI.requests.BuyProduct = function(player, arg)
    local data = LabAPI.playerData[player.UserId]
    -- arg is a product key, or { key, target } when bought from a creature card
    local key = typeof(arg) == "table" and arg.key or arg
    local prod = ShopConfig.product(key)
    if not (data and prod) then return end
    data.productTarget = typeof(arg) == "table" and arg.target or nil
    if prod.id == 0 then
        if IS_STUDIO then
            grantProduct(player, data, prod) -- Studio test purchase
        else
            LabAPI.notify(player, prod.name .. " is coming soon!", "info")
        end
        return
    end
    MarketplaceService:PromptProductPurchase(player, prod.id)
end

-------------------------------------------------
-- daily rewards
-------------------------------------------------
local function dailyInfo(data)
    local d = data.daily
    local claimable = d.day < today()
    local nextStreak = (d.day == today() - 1) and (d.streak % #ShopConfig.Daily) + 1 or 1
    if not claimable then nextStreak = d.streak end
    return claimable, nextStreak
end

LabAPI.requests.ClaimDaily = function(player)
    local data = LabAPI.playerData[player.UserId]
    if not data then return end
    local claimable, streak = dailyInfo(data)
    if not claimable then
        LabAPI.notify(player, "Already claimed today. Come back tomorrow!", "info")
        return
    end
    local r = ShopConfig.Daily[streak]
    local mult = hasVip(data) and 2 or 1
    data.daily = { day = today(), streak = streak }
    if r.kind == "cash" then
        local amount = cashAmount(data, r.base, r.minutes) * mult
        data.money += amount
        LabAPI.notify(player, ("Day %d reward: +$%s%s"):format(streak, LabAPI.fmt(amount), mult > 1 and " (VIP x2)" or ""), "rare")
    elseif r.kind == "elixirs" then
        local add = randomRareElixirs(r.count * mult)
        for _, k in add do
            if #data.ingredients < Config.SatchelSize then table.insert(data.ingredients, k) end
        end
        LabAPI.notify(player, ("Day %d reward: rare elixirs in your satchel!"):format(streak), "rare")
    elseif r.kind == "boost" then
        addBoost(data, r.boost, r.minutes * mult)
        LabAPI.notify(player, ("Day %d reward: Lucky boost for %d min!"):format(streak, r.minutes * mult), "rare")
    elseif r.kind == "part" then
        LabAPI.revealPart(player, data, LabAPI.randomPart(nil, r.rarity, Config.ShinyChance * mult))
    end
    LabAPI.sendState(player)
end

table.insert(LabAPI.stateHooks, function(data, st)
    st.passes = data.passes
    local boosts = {}
    for k, v in data.boosts or {} do
        if v > os.time() then boosts[k] = v end
    end
    st.boosts = boosts
    st.serverTime = os.time()
    local claimable, streak = dailyInfo(data)
    st.daily = { claimable = claimable, streak = streak }
end)

if IS_STUDIO then
    local missing = {}
    for _, p in ShopConfig.Passes do if p.id == 0 then table.insert(missing, "pass " .. p.key) end end
    for _, p in ShopConfig.Products do if p.id == 0 then table.insert(missing, "product " .. p.key) end end
    if #missing > 0 then
        print(("[Monetization] %d items still have id = 0 (free in Studio, 'coming soon' live). Paste their IDs into ReplicatedStorage.ShopConfig: %s"):format(#missing, table.concat(missing, ", ")))
    end
end
