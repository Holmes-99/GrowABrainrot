--[[
    Showcase — money pedestals on every plot.

    * Each plot has 8 pedestals (workspace.PlayerPlots.PlotN.Showcase). The first few are free,
      the rest unlock for cash (Config.ShowcaseUnlock). Saved in data.showcase (count unlocked).
    * Your best creatures that aren't in a cage stand on the unlocked pedestals and earn
      Config.ShowcaseBonus times their normal income into a cash pile on the pedestal's pad.
    * Step on the pad to collect. A pile stops growing at Config.ShowcaseCapSeconds of earnings.
    * Everything else keeps paying straight into the wallet (GameManager calls LabAPI.payIncome).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LabAPI = require(script.Parent:WaitForChild("LabAPI"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
LabAPI.waitReady()

local COUNT = #Config.ShowcaseUnlock
local FREE = 0
for _, c in Config.ShowcaseUnlock do if c == 0 then FREE += 1 end end

local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local function rarityColor(r)
    local rgb = Config.RarityColors and Config.RarityColors[r]
    return rgb and Config.Color(rgb) or Color3.fromRGB(90, 95, 110)
end

local displayed = {} -- userId -> { [index] = creatureId }

local function sets(plotId)
    local plot = LabAPI.getPlot(plotId)
    local f = plot and plot:FindFirstChild("Showcase")
    return f
end

local function setOf(plotId, i)
    local f = sets(plotId)
    return f and f:FindFirstChild("Showcase" .. i)
end

local function ensure(data)
    data.showcase = math.clamp(tonumber(data.showcase) or FREE, FREE, COUNT)
    if type(data.piles) ~= "table" then data.piles = {} end
    for i = 1, COUNT do data.piles[i] = tonumber(data.piles[i]) or 0 end
end

local function rate(data, c) -- cash per second on a pedestal
    return LabAPI.creatureIncome(data, c) * Config.ShowcaseBonus / Config.IncomeInterval
end

local function creatureById(data, id)
    for _, c in data.creatures do if c.id == id then return c end end
end

local function rateTag(set)
    local top = set:FindFirstChild("Top")
    local bb = top:FindFirstChild("RateTag")
    if not bb then
        bb = Instance.new("BillboardGui")
        bb.Name = "RateTag"
        bb.Size = UDim2.fromOffset(120, 30)
        bb.MaxDistance = 60
        bb.Parent = top
        local tl = Instance.new("TextLabel")
        tl.Name = "Text"
        tl.Size = UDim2.fromScale(1, 1)
        tl.BackgroundTransparency = 1
        tl.TextScaled = true
        tl.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
        tl.TextColor3 = Color3.fromRGB(120, 255, 140)
        tl.TextStrokeTransparency = 0.2
        tl.Parent = bb
    end
    return bb
end

-- coin pile grows with the amount, the label shows it
local function drawPile(set, amount, cap)
    local coins = set:FindFirstChild("Coins")
    local label = set.CollectPad.PileTag.Amount
    if amount < 1 then
        label.Text = ""
        if coins then
            for _, p in coins:GetDescendants() do
                if p:IsA("BasePart") then p.Transparency = 1 end
                if p:IsA("Decal") then p.Transparency = 1 end
            end
        end
        return
    end
    local full = cap > 0 and amount >= cap
    label.Text = (full and "FULL! " or "") .. "$" .. LabAPI.fmt(math.floor(amount))
    label.TextColor3 = full and Color3.fromRGB(255, 110, 90) or Color3.fromRGB(255, 225, 90)
    if coins then
        for _, p in coins:GetDescendants() do
            if p:IsA("BasePart") then p.Transparency = 0 end
            if p:IsA("Decal") then p.Transparency = 0 end
        end
        local base = coins:GetAttribute("BaseScale") or 1
        local fill = cap > 0 and math.clamp(amount / cap, 0, 1) or 0
        local want = base * (0.45 + 0.55 * math.sqrt(fill))
        if math.abs(coins:GetScale() - want) > base * 0.03 then
            local pad = set.CollectPad
            coins:ScaleTo(want)
            local _, sz = coins:GetBoundingBox()
            coins:PivotTo(pad.CFrame * CFrame.new(0, 0.15 + sz.Y / 2, 0))
        end
    end
end

-- put a plot's pedestals back to the "nobody here" look
local function resetPlot(plotId)
    local f = sets(plotId)
    if not f then return end
    for _, set in f:GetChildren() do
        local i = set:GetAttribute("Index")
        set.Lock.Transparency = 0.55
        set.Lock.LockTag.Text.Text = "🔒"
        set.Lock.UnlockPrompt.Enabled = false
        set.Ring.Color = Color3.fromRGB(90, 95, 110)
        set.CollectPad.Color = Color3.fromRGB(70, 80, 90)
        rateTag(set).Enabled = false
        drawPile(set, 0, 0)
    end
end

local function refresh(player)
    local data = LabAPI.playerData[player.UserId]
    if not (data and data.plotId) then return end
    ensure(data)
    local mine = {}
    displayed[player.UserId] = mine

    -- creatures not living in a cage, best earners first
    local free = {}
    for _, c in data.creatures do
        local entry = LabAPI.creatureModels[LabAPI.modelKey(player.UserId, c.id)]
        if entry and not entry.caged then table.insert(free, { c = c, entry = entry }) end
        if entry then entry.pinned = nil end
    end
    table.sort(free, function(a, b) return LabAPI.creatureIncome(data, a.c) > LabAPI.creatureIncome(data, b.c) end)

    for i = 1, COUNT do
        local set = setOf(data.plotId, i)
        if set then
            local unlocked = i <= data.showcase
            local lock = set.Lock
            lock.Transparency = unlocked and 1 or 0.55
            lock.LockTag.Enabled = not unlocked
            local nextUp = i == data.showcase + 1
            lock.LockTag.Text.Text = unlocked and ""
                or (nextUp and ("🔒 UNLOCK\n<font color='#7CFF8C'>$" .. LabAPI.fmt(Config.ShowcaseUnlock[i]) .. "</font>") or "🔒")
            lock.UnlockPrompt.Enabled = nextUp
            lock.UnlockPrompt.ActionText = "Unlock · $" .. LabAPI.fmt(Config.ShowcaseUnlock[i])
            set.CollectPad.Color = unlocked and Color3.fromRGB(80, 230, 120) or Color3.fromRGB(70, 80, 90)

            local pick = unlocked and free[1]
            if pick then
                table.remove(free, 1)
                mine[i] = pick.c.id
                pick.entry.pinned = true
                local model = pick.entry.model
                local top = set.Top
                local function put()
                    if not model.Parent then return end
                    model:PivotTo(top.CFrame)
                    -- grown creatures are taller: stand the feet on the podium, not sunk into it
                    local cf, size = model:GetBoundingBox()
                    local lift = (top.Position.Y - top.Size.Y / 2) - (cf.Position.Y - size.Y / 2)
                    if lift > 0 then model:PivotTo(top.CFrame + Vector3.new(0, lift, 0)) end
                end
                put()
                task.delay(4.2, put) -- a wander tween may still be finishing
                set.Ring.Color = rarityColor(pick.c.stats.rarity)
                local tag = rateTag(set)
                tag.Enabled = true
                tag.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("Height") or 4) * model:GetScale() + 2.2, 0)
                tag.Text.Text = "+$" .. LabAPI.fmt(math.max(1, math.floor(rate(data, pick.c) + 0.5))) .. "/s"
            else
                set.Ring.Color = Color3.fromRGB(90, 95, 110)
                rateTag(set).Enabled = unlocked
                rateTag(set).StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
                rateTag(set).Text.Text = unlocked and "EMPTY" or ""
            end
            local c = mine[i] and creatureById(data, mine[i])
            drawPile(set, data.piles[i], c and rate(data, c) * Config.ShowcaseCapSeconds or 0)
        end
    end
end

-- GameManager's 10s income tick: pay the wallet for everything NOT on a pedestal
LabAPI.payIncome = function(player, data)
    local mine = displayed[player.UserId] or {}
    local onShow = {}
    for _, id in mine do onShow[id] = true end
    local t = 0
    for _, c in data.creatures do
        if not onShow[c.id] then t += LabAPI.creatureIncome(data, c) end
    end
    return t
end

-- piles grow every second
task.spawn(function()
    while true do
        task.wait(1)
        for _, player in Players:GetPlayers() do
            local data = LabAPI.playerData[player.UserId]
            local mine = displayed[player.UserId]
            if data and data.plotId and mine then
                ensure(data)
                for i, id in mine do
                    local c = creatureById(data, id)
                    local set = setOf(data.plotId, i)
                    if c and set then
                        local r = rate(data, c)
                        local cap = r * Config.ShowcaseCapSeconds
                        data.piles[i] = math.min(cap, data.piles[i] + r)
                        drawPile(set, data.piles[i], cap)
                    end
                end
            end
        end
    end
end)

local function popText(pad, text)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(200, 50)
    bb.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Parent = pad
    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.fromScale(1, 1)
    tl.BackgroundTransparency = 1
    tl.TextScaled = true
    tl.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
    tl.TextColor3 = Color3.fromRGB(255, 225, 90)
    tl.TextStrokeTransparency = 0
    tl.Text = text
    tl.Parent = bb
    TweenService:Create(bb, TweenInfo.new(1.1), { StudsOffsetWorldSpace = Vector3.new(0, 8, 0) }):Play()
    TweenService:Create(tl, TweenInfo.new(1.1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
    task.delay(1.2, function() bb:Destroy() end)
end

local function collect(player, plotId, i, pad)
    local data = LabAPI.playerData[player.UserId]
    if not (data and data.plotId == plotId) then return end
    ensure(data)
    local amount = math.floor(data.piles[i])
    if amount < 1 then return end
    data.piles[i] -= amount
    data.money += amount
    popText(pad, "+$" .. LabAPI.fmt(amount))
    local set = setOf(plotId, i)
    if set then drawPile(set, data.piles[i], 0) end
    LabAPI.sendState(player)
end

local function unlock(player, plotId, i)
    local data = LabAPI.playerData[player.UserId]
    if not (data and data.plotId == plotId) then
        if data then LabAPI.notify(player, "That's someone else's pedestal.", "bad") end
        return
    end
    ensure(data)
    if i ~= data.showcase + 1 then return end
    local cost = Config.ShowcaseUnlock[i]
    if data.money < cost then
        LabAPI.notify(player, ("You need $%s to unlock this pedestal."):format(LabAPI.fmt(cost)), "bad")
        return
    end
    data.money -= cost
    data.showcase = i
    LabAPI.notify(player, ("Pedestal %d unlocked! Your next-best creature moves onto it."):format(i), "good")
    refresh(player)
    LabAPI.sendState(player)
end

-- wire every plot's pads and lock prompts once
local touchCd = {}
for _, plot in workspace.PlayerPlots:GetChildren() do
    local plotId = tonumber(plot.Name:match("%d+"))
    local f = plot:FindFirstChild("Showcase")
    if plotId and f then
        for _, set in f:GetChildren() do
            local i = set:GetAttribute("Index")
            set.CollectPad.Touched:Connect(function(hit)
                local player = Players:GetPlayerFromCharacter(hit.Parent)
                if not player then return end
                local k = player.UserId .. "_" .. plotId .. "_" .. i
                if touchCd[k] and os.clock() - touchCd[k] < 0.5 then return end
                touchCd[k] = os.clock()
                collect(player, plotId, i, set.CollectPad)
            end)
            set.Lock.UnlockPrompt.Triggered:Connect(function(player) unlock(player, plotId, i) end)
        end
        resetPlot(plotId)
    end
end

LabAPI.playerLoaded:Connect(function(player, data)
    ensure(data)
    task.delay(1, refresh, player)
end)
LabAPI.creaturesChanged:Connect(function(player)
    task.defer(refresh, player)
end)
LabAPI.playerLeaving:Connect(function(player, data)
    displayed[player.UserId] = nil
    if data and data.plotId then resetPlot(data.plotId) end
end)
for _, p in Players:GetPlayers() do task.defer(refresh, p) end

table.insert(LabAPI.stateHooks, function(data, st)
    st.showcase = data.showcase
end)

LabAPI.showcaseRefresh = refresh
print("[Showcase] ready")
