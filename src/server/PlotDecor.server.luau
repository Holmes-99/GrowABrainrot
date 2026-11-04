--[[
    PlotDecor — decorating your lab.

    * Players buy decorations (trees, lamps, fountains...) and place them on their plot,
      mostly in the big back yard. They're saved in data.decor (plot-local positions),
      so they come back on whatever plot you get next time.
    * Cages: each creature moves into the best free cage and earns that cage's bonus
      (c.cageBonus, read by GameManager's creatureIncome).
    * Trophy pedestals show off your rarest spare parts.
    Placement rules live in ReplicatedStorage.DecorLogic (shared with the client preview).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LabAPI = require(script.Parent:WaitForChild("LabAPI"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local DecorLogic = require(ReplicatedStorage:WaitForChild("DecorLogic"))
local CreatureBuilder = require(ReplicatedStorage:WaitForChild("CreatureBuilder"))
local Templates = ReplicatedStorage:WaitForChild("DecorTemplates")

local Items = DecorLogic.Items
local spawned = {} -- userId -> { [decorId] = model }

local function rarityColor(r)
    local rgb = Config.RarityColors[r]
    return rgb and Config.Color(rgb) or Color3.new(1, 1, 1)
end

local function decorFolder(plot)
    local f = plot:FindFirstChild("Decorations")
    if not f then
        f = Instance.new("Folder")
        f.Name = "Decorations"
        f.Parent = plot
    end
    return f
end

local function spawnItem(player, data, entry)
    local plot = LabAPI.getPlot(data.plotId)
    local template = Templates:FindFirstChild(entry.item)
    if not (plot and template) then return end
    local m = template:Clone()
    m:PivotTo(DecorLogic.worldCFrame(plot, entry.x, entry.z, entry.r))
    m:SetAttribute("DecorId", entry.id)
    m:SetAttribute("Item", entry.item)
    m:SetAttribute("Owner", player.UserId)
    m.Parent = decorFolder(plot)
    spawned[player.UserId] = spawned[player.UserId] or {}
    spawned[player.UserId][entry.id] = m
    return m
end

local function clearSpawned(player)
    for _, m in spawned[player.UserId] or {} do
        m:Destroy()
    end
    spawned[player.UserId] = {}
end

-------------------------------------------------
-- cages + pedestals
-------------------------------------------------
local function setPlate(cage, text)
    local plate = cage:FindFirstChild("NamePlate")
    local tl = plate and plate:FindFirstChild("Text", true)
    if tl then tl.Text = text end
end

local function refresh(player, data)
    if not data or not data.plotId then return end
    local mine = spawned[player.UserId] or {}

    -- best cages first, best earners first
    local cages = {}
    for _, e in data.decor do
        local it = Items[e.item]
        if it and it.cage and mine[e.id] then
            table.insert(cages, { e = e, bonus = it.cage, model = mine[e.id] })
        end
    end
    table.sort(cages, function(a, b) return a.bonus > b.bonus end)
    local creatures = table.clone(data.creatures)
    table.sort(creatures, function(a, b) return a.stats.baseIncome > b.stats.baseIncome end)

    for i, c in creatures do
        local entry = LabAPI.creatureModels[LabAPI.modelKey(player.UserId, c.id)]
        local cage = cages[i]
        c.cageBonus = cage and cage.bonus or nil
        if entry then
            if cage then
                entry.caged = true
                local slot = cage.model:FindFirstChild("Slot")
                local function put()
                    if entry.model.Parent and slot then
                        entry.model:PivotTo(CFrame.new(slot.Position - Vector3.new(0, 0.5, 0)) * cage.model:GetPivot().Rotation)
                    end
                end
                put()
                task.delay(4.2, put) -- a wander tween may still be finishing
                setPlate(cage.model, ("<b>%s</b>\n+%d%% cash"):format(c.name, math.floor(cage.bonus * 100)))
            else
                entry.caged = nil
            end
        end
    end
    for i = #creatures + 1, #cages do
        setPlate(cages[i].model, "EMPTY\n<font size='14'>build a creature!</font>")
    end

    -- pedestals: rarest spare parts
    local parts = table.clone(data.parts)
    table.sort(parts, function(a, b)
        local ra, rb = Config.RarityRank[a.rarity] or 0, Config.RarityRank[b.rarity] or 0
        if ra ~= rb then return ra > rb end
        return (a.shiny and 1 or 0) > (b.shiny and 1 or 0)
    end)
    local k = 0
    for _, e in data.decor do
        local m = mine[e.id]
        if e.item == "Pedestal" and m then
            k += 1
            local p = parts[k]
            local sig = p and (p.id .. ":" .. p.rarity) or "none"
            if m:GetAttribute("Showing") ~= sig then
                m:SetAttribute("Showing", sig)
                local old = m:FindFirstChild("Display")
                if old then old:Destroy() end
                if p then
                    local show = CreatureBuilder.BuildFromParts({ [p.slot] = p }, { only = p.slot, scale = 0.9 })
                    show.Name = "Display"
                    show:PivotTo(CFrame.new())
                    local bcf, bsize = show:GetBoundingBox()
                    local top = m:GetPivot() * CFrame.new(0, 3.75, 0)
                    show:PivotTo(CFrame.new(top.Position + Vector3.new(-bcf.Position.X, bsize.Y / 2 - bcf.Position.Y, -bcf.Position.Z)) * m:GetPivot().Rotation)
                    show.Parent = m
                    local bb = Instance.new("BillboardGui")
                    bb.Size = UDim2.fromOffset(160, 40)
                    bb.StudsOffsetWorldSpace = Vector3.new(0, bsize.Y + 1, 0)
                    bb.MaxDistance = 60
                    bb.Adornee = show.PrimaryPart
                    bb.Parent = show
                    local tl = Instance.new("TextLabel")
                    tl.Size = UDim2.fromScale(1, 1)
                    tl.BackgroundTransparency = 1
                    tl.TextScaled = true
                    tl.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
                    tl.TextStrokeTransparency = 0.3
                    tl.TextColor3 = rarityColor(p.rarity)
                    tl.Text = (p.shiny and "✨ " or "") .. p.rarity .. "\n" .. LabAPI.partName(p)
                    tl.Parent = bb
                end
            end
        end
    end
end

-------------------------------------------------
-- player lifecycle
-------------------------------------------------
LabAPI.playerLoaded:Connect(function(player, data)
    data.decor = data.decor or {}
    -- the yard lost its back strip to the money pedestals: refund anything left outside it
    for i = #data.decor, 1, -1 do
        local e = data.decor[i]
        if Items[e.item] and not DecorLogic.canPlace({}, e.item, e.x, e.z, e.r) then
            data.money += Items[e.item].price
            table.remove(data.decor, i)
        end
    end
    clearSpawned(player)
    if not data.plotId then return end
    local plot = LabAPI.getPlot(data.plotId)
    if plot then decorFolder(plot) end
    for _, e in data.decor do
        if Items[e.item] then spawnItem(player, data, e) end
    end
    refresh(player, data)
end)

LabAPI.playerLeaving:Connect(function(player)
    clearSpawned(player)
    spawned[player.UserId] = nil
end)

LabAPI.creaturesChanged:Connect(function(player, data)
    task.defer(refresh, player, data)
end)

table.insert(LabAPI.stateHooks, function(data, st)
    st.decor = data.decor
end)

-- pedestals follow your parts bag
task.spawn(function()
    while true do
        task.wait(6)
        for _, p in Players:GetPlayers() do
            local data = LabAPI.playerData and LabAPI.playerData[p.UserId]
            if data then refresh(p, data) end
        end
    end
end)

-------------------------------------------------
-- requests from DecorClient
-------------------------------------------------
local function onMyPlot(player, data)
    local plot = data and data.plotId and LabAPI.getPlot(data.plotId)
    if not plot then
        LabAPI.notify(player, "You need a lab to decorate.", "bad")
        return nil
    end
    if not LabAPI.near(player, plot.PlotGround, 95) then
        LabAPI.notify(player, "Go to your lab to decorate it.", "bad")
        return nil
    end
    return plot
end

local function cleanArgs(arg)
    if typeof(arg) ~= "table" then return nil end
    local r = tonumber(arg.r) or 0
    if r ~= math.floor(r) or r < 0 or r > 3 then return nil end
    local x, z = tonumber(arg.x), tonumber(arg.z)
    if not (x and z) then return nil end
    return x, z, r
end

LabAPI.requests.PlaceDecor = function(player, arg)
    local data = LabAPI.playerData[player.UserId]
    local plot = onMyPlot(player, data)
    if not plot then return end
    local x, z, r = cleanArgs(arg)
    local item = typeof(arg) == "table" and arg.item
    local it = Items[item]
    if not (x and it) or it.retired then return end
    x, z = DecorLogic.snap(item, r, x, z)
    if #data.decor >= DecorLogic.MaxItems then
        LabAPI.notify(player, ("Your lab is full of decorations (%d max). Sell some first."):format(DecorLogic.MaxItems), "bad")
        return
    end
    if it.max then
        local n = 0
        for _, e in data.decor do if e.item == item then n += 1 end end
        if n >= it.max then
            LabAPI.notify(player, ("You can have %d %ss at most."):format(it.max, it.name), "bad")
            return
        end
    end
    if it.vip and not (data.passes and data.passes.VIP) then
        LabAPI.notify(player, "That's a VIP decoration. Get the VIP pass in the 💎 Shop.", "bad")
        LabAPI.openUI(player, "shop")
        return
    end
    if data.money < it.price then
        LabAPI.notify(player, ("%s costs $%s."):format(it.name, LabAPI.fmt(it.price)), "bad")
        return
    end
    local ok, why = DecorLogic.canPlace(data.decor, item, x, z, r)
    if not ok then
        LabAPI.notify(player, why, "bad")
        return
    end
    data.money -= it.price
    local entry = { id = LabAPI.newId(data), item = item, x = x, z = z, r = r }
    table.insert(data.decor, entry)
    spawnItem(player, data, entry)
    refresh(player, data)
    LabAPI.notify(player, ("Placed %s%s."):format(it.name, it.price > 0 and (" for $" .. LabAPI.fmt(it.price)) or ""), "good")
    LabAPI.sendState(player)
end

LabAPI.requests.MoveDecor = function(player, arg)
    local data = LabAPI.playerData[player.UserId]
    local plot = onMyPlot(player, data)
    if not plot then return end
    local x, z, r = cleanArgs(arg)
    if not x then return end
    for _, e in data.decor do
        if e.id == arg.id then
            x, z = DecorLogic.snap(e.item, r, x, z)
            local ok, why = DecorLogic.canPlace(data.decor, e.item, x, z, r, e.id)
            if not ok then
                LabAPI.notify(player, why, "bad")
                return
            end
            e.x, e.z, e.r = x, z, r
            local m = spawned[player.UserId] and spawned[player.UserId][e.id]
            if m then m:PivotTo(DecorLogic.worldCFrame(plot, x, z, r)) end
            refresh(player, data)
            LabAPI.sendState(player)
            return
        end
    end
end

LabAPI.requests.SellDecor = function(player, id)
    local data = LabAPI.playerData[player.UserId]
    if not onMyPlot(player, data) then return end
    for i, e in data.decor do
        if e.id == id then
            local it = Items[e.item]
            local refund = math.floor((it and it.price or 0) * DecorLogic.SellBack)
            table.remove(data.decor, i)
            local m = spawned[player.UserId] and spawned[player.UserId][e.id]
            if m then m:Destroy() end
            spawned[player.UserId][e.id] = nil
            data.money += refund
            refresh(player, data)
            LabAPI.notify(player, ("Sold %s%s."):format(it and it.name or "it", refund > 0 and (" for $" .. LabAPI.fmt(refund)) or ""), "info")
            LabAPI.sendState(player)
            return
        end
    end
end

LabAPI.requests.GoHome = function(player)
    local data = LabAPI.playerData[player.UserId]
    local plot = data and data.plotId and LabAPI.getPlot(data.plotId)
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if plot and hrp then
        -- land in the back yard, facing the lab
        local cf = DecorLogic.plotFrame(plot) * CFrame.new(0, 3, 30)
        player.Character:PivotTo(CFrame.lookAt(cf.Position, (DecorLogic.plotFrame(plot) * CFrame.new(0, 3, 0)).Position))
    end
end
