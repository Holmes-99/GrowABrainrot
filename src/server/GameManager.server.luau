--[[
    GameManager.server.lua — Grow a Brainrot (parts edition)

    Loop: buy elixirs -> brew at your cauldron -> a PART CAPSULE grows in a pod ->
          open it -> snap parts together at the Assembly Lab -> your creature lives
          in your lab, earns cash, raids rivals and fights at the Ohio Colosseum.

    Market Street: Assembly Lab (build / take apart), The Forge (fuse parts, weapon crates),
                   Black Market (rotating rare parts). Trading Post sells parts & creatures.
    All ProximityPrompts are handled here on the server, so ownership is enforced.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local CreatureBuilder = require(ReplicatedStorage:WaitForChild("CreatureBuilder"))
local RunService = game:GetService("RunService")
local DataService = require(script.Parent:WaitForChild("DataService"))
local LabAPI = require(script.Parent:WaitForChild("LabAPI"))

-- ============================================
-- REMOTE EVENTS
-- ============================================
local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local function makeRemote(name)
    local r = Instance.new("RemoteEvent")
    r.Name = name
    r.Parent = Remotes
    return r
end

local StateUpdate = makeRemote("StateUpdate")  -- server -> client: full player state
local Notify      = makeRemote("Notify")       -- server -> client: toast (text, kind)
local OpenUI      = makeRemote("OpenUI")       -- server -> client: open a panel
local Revealed    = makeRemote("Revealed")     -- server -> client: reveal card (part or creature)
local BattleEvent = makeRemote("BattleEvent")  -- server -> client: "start" / "action" / "end"
local Request     = makeRemote("Request")      -- client -> server: UI actions

-------------------------------------------------
-- Helpers
-------------------------------------------------
local playerData = {}
local plotOwners = {} -- plotId -> userId

local RARITY_COLOR = {}
for rarity, rgb in Config.RarityColors do
    RARITY_COLOR[rarity] = Config.Color(rgb)
end

local function now()
    return workspace:GetServerTimeNow()
end

local function fmt(n: number): string
    n = math.floor(n)
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then
        out = out:sub(2)
    end
    return (n < 0 and "-" or "") .. out
end

local function notify(player: Player, text: string, kind: string?)
    Notify:FireClient(player, text, kind or "info")
end

local function broadcast(text: string, kind: string?, except: Player?)
    for _, p in Players:GetPlayers() do
        if p ~= except then
            notify(p, text, kind)
        end
    end
end

local function getPlot(plotId: number?)
    if not plotId then return nil end
    return workspace.PlayerPlots:FindFirstChild("Plot" .. plotId)
end

local function plotIdOf(inst: Instance): number?
    local m = inst
    while m and m ~= workspace do
        local id = m.Name:match("^Plot(%d+)$")
        if id and m.Parent == workspace.PlayerPlots then
            return tonumber(id)
        end
        m = m.Parent
    end
    return nil
end

local function near(player: Player, part: BasePart?, dist: number): boolean
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    return part ~= nil and hrp ~= nil and (hrp.Position - part.Position).Magnitude <= dist
end

local function findStation(path: { string }): BasePart?
    local inst = workspace
    for _, n in path do
        inst = inst and inst:FindFirstChild(n)
    end
    return inst
end

local function rarityRank(r) return Config.RarityRank[r] or 1 end
local function rarityAt(rank) return Config.RarityOrder[math.clamp(rank, 1, #Config.RarityOrder)] end

-------------------------------------------------
-- Creature analysis: stats, perks, income from the parts
-------------------------------------------------
local PartsLogic = require(ReplicatedStorage:WaitForChild("PartsLogic"))
local power, creatureName, analyze = PartsLogic.power, PartsLogic.creatureName, PartsLogic.analyze

local function hasTrait(c, trait)
    return table.find(c.stats.traits, trait) ~= nil
end

local function countTrait(data, trait: string): number
    local n = 0
    for _, c in data.creatures do
        if hasTrait(c, trait) then n += 1 end
    end
    return n
end

local function shopDiscount(data) return math.min(0.32, 0.08 * countTrait(data, "RizzMagnet")) end
local function growBoost(data)    return math.min(0.45, 0.15 * countTrait(data, "Brewmaster")) end

-- Robux game passes (data.passes, set by the Monetization script) and timed boosts (data.boosts)
local function hasPass(data, name) return data.passes ~= nil and data.passes[name] == true end
local function boostOn(data, name) return (data.boosts and data.boosts[name] or 0) > os.time() end

local function luckRolls(data)
    return math.min(3, countTrait(data, "LuckyCharm"))
        + (hasPass(data, "LuckyBrewer") and 2 or 0) + (boostOn(data, "Luck") and 2 or 0)
end
local function shinyBonus(data)
    return 0.02 * countTrait(data, "LuckyCharm")
        + (hasPass(data, "LuckyBrewer") and 0.03 or 0) + (boostOn(data, "Luck") and 0.03 or 0)
end
local function brewSpeed(data)
    return (hasPass(data, "FastBrew") and 0.5 or 1) * (boostOn(data, "FastBrew") and 0.5 or 1)
end
local function cashMult(data)
    return (hasPass(data, "DoubleCash") and 2 or 1) * (boostOn(data, "Cash") and 2 or 1) * (hasPass(data, "VIP") and 1.1 or 1)
end
local function maxCreatures(data) return Config.MaxCreatures + 2 * data.rebirths + (hasPass(data, "BigLab") and 6 or 0) end
local function maxParts(data) return Config.MaxParts + (hasPass(data, "BigLab") and 40 or 0) end
-- battles/trading/betting stay closed until the player owns Config.UnlockCreatures creatures
local function locked(player: Player, data, what: string): boolean
    local have = #data.creatures
    if have >= Config.UnlockCreatures then return false end
    notify(player, ("🔒 %s unlock when you own %d creatures. You have %d. Build more at the Assembly Lab!"):format(what, Config.UnlockCreatures, have), "bad")
    return true
end
local function price(data, base) return math.floor(base * (1 - shopDiscount(data))) end

local function creatureIncome(data, c): number
    local income = c.stats.baseIncome
    local hype = countTrait(data, "HypeBeast") - (hasTrait(c, "HypeBeast") and 1 or 0)
    income *= 1 + math.min(0.5, 0.1 * hype)
    -- c.cageBonus is set by PlotDecor when the creature lives in a cage
    income *= 1 + Config.Growth.IncomePerLevel * (c.growth or 0)
    return income * data.incomeMultiplier * cashMult(data) * (1 + (c.cageBonus or 0))
end

local function totalIncome(data): number
    local t = 0
    for _, c in data.creatures do
        t += creatureIncome(data, c)
    end
    return t
end

local function partValue(p): number
    return (Config.PartSell[p.rarity] or 20) * (p.shiny and 2 or 1)
end

local function creatureValue(c): number
    local v = 0
    for _, p in c.parts do v += partValue(p) end
    return math.floor(v * 1.2)
end

local function partName(p)
    return (p.shiny and "Shiny " or "") .. Config.PartNames[p.slot][p.family]
end

-------------------------------------------------
-- Black Market (shared rotating stock)
-------------------------------------------------
local market = { seq = 0, offers = {}, refreshAt = 0 }

local function randomPart(slot, rarity, shinyChance)
    return {
        slot = slot or Config.Slots[math.random(1, #Config.Slots)],
        family = Config.Families[math.random(1, #Config.Families)],
        rarity = rarity,
        shiny = math.random() < (shinyChance or 0),
    }
end

local function refreshMarket()
    market.seq += 1
    market.offers = {}
    for i = 1, Config.MarketSlots do
        local r = math.random()
        local rarity = (r < 0.05 and "Legendary") or (r < 0.3 and "Epic") or "Rare"
        local p = randomPart(nil, rarity, 0.08)
        market.offers[i] = { part = p, price = partValue(p) * Config.MarketMarkup }
    end
    market.refreshAt = now() + Config.MarketRefresh
end
refreshMarket()

-------------------------------------------------
-- Ranked queue
-------------------------------------------------
local rankedQueue = {} -- list of players

local function inQueue(p) return table.find(rankedQueue, p) ~= nil end
local function leaveQueue(p)
    local i = table.find(rankedQueue, p)
    if i then table.remove(rankedQueue, i) end
end

-------------------------------------------------
-- State sync
-------------------------------------------------
local function publicCreature(data, c)
    return {
        id = c.id, name = c.name, rarity = c.stats.rarity, parts = c.parts, perks = c.stats.perks,
        hp = c.stats.hp, atk = c.stats.atk, spd = c.stats.spd, power = c.stats.power,
        income = creatureIncome(data, c), sell = creatureValue(c), setCount = c.stats.setCount,
        growth = c.growth or 0, growCost = Config.Growth.Cost[(c.growth or 0) + 1], wings = c.wings == true, named = c.named == true,
    }
end

local function sendState(player: Player)
    local data = playerData[player.UserId]
    if not data then return end

    local creatures = {}
    for _, c in data.creatures do
        table.insert(creatures, publicCreature(data, c))
    end
    local pods = {}
    for podId, p in data.pods do
        pods[podId] = { rarity = p.part.rarity, start = p.start, finish = p.finish }
    end
    local offers = {}
    for i, o in market.offers do
        offers[i] = { part = o.part, price = price(data, o.price), bought = data.marketBought[market.seq .. "_" .. i] == true }
    end

    local st = {
        money = data.money,
        plotId = data.plotId,
        ingredients = data.ingredients,
        pods = pods,
        parts = data.parts,
        creatures = creatures,
        discoveries = data.discoveries,
        rebirths = data.rebirths,
        incomeMultiplier = data.incomeMultiplier,
        trophies = data.trophies,
        arenaLevel = data.arenaLevel,
        wins = data.wins,
        income = totalIncome(data),
        maxCreatures = maxCreatures(data),
        maxParts = maxParts(data),
        discount = shopDiscount(data),
        growBoost = growBoost(data),
        luck = luckRolls(data),
        market = offers,
        marketRefreshAt = market.refreshAt,
        inQueue = inQueue(player),
        queueSize = #rankedQueue,
        draught = data.draught,
    }
    for _, hook in LabAPI.stateHooks do
        hook(data, st)
    end
    StateUpdate:FireClient(player, st)

    local ls = player:FindFirstChild("leaderstats")
    if ls then
        ls.Cash.Value = math.floor(data.money)
        ls.Trophies.Value = data.trophies
    end
end

local function sendAll()
    for _, p in Players:GetPlayers() do sendState(p) end
end

-------------------------------------------------
-- Plot sign
-------------------------------------------------
local function setPlotSign(plotId: number, text: string)
    local plot = getPlot(plotId)
    if not plot then return end
    for _, n in { "PlotSign", "PlotSignBack" } do
        local sign = plot:FindFirstChild(n)
        if sign then
            for _, d in sign:GetDescendants() do
                if d:IsA("TextLabel") then d.Text = text end
            end
        end
    end
end

-------------------------------------------------
-- Creatures living on the plot
-------------------------------------------------
local creatureModels = {} -- [ownerUserId .. "_" .. creatureId] = { model, plotId, nextMove }

local function plotFrame(plotId: number): CFrame
    local g = getPlot(plotId).PlotGround
    local c = Vector3.new(g.Position.X, g.Position.Y + g.Size.Y / 2, g.Position.Z)
    return CFrame.lookAt(c, c + Vector3.new(-math.sign(c.X), 0, 0)) -- -Z faces the main path
end

-- wander zones (plot-local x1,x2,z1,z2): front lawn, around the lab, and the big back yard (twice as likely)
local WANDER = { { -16, 16, -20, -12 }, { -9, 9, 2, 7 }, { -16, 16, 12, 19 }, { -26, 26, 28, 52 }, { -26, 26, 28, 52 } }
local function randomSpot(plotId: number): CFrame
    local r = WANDER[math.random(1, #WANDER)]
    local x = r[1] + math.random() * (r[2] - r[1])
    local z = r[3] + math.random() * (r[4] - r[3])
    return plotFrame(plotId) * CFrame.new(x, 0, z)
end

local function modelKey(userId, id) return userId .. "_" .. id end

local function addNameTag(model: Model, text: string, color: Color3)
    local bb = Instance.new("BillboardGui")
    bb.Name = "NameTag"
    bb.Size = UDim2.fromOffset(200, 34)
    bb.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("Height") or 4) + 0.8, 0)
    bb.MaxDistance = 70
    bb.Parent = model.PrimaryPart
    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.fromScale(1, 1)
    tl.BackgroundTransparency = 1
    tl.Text = text
    tl.TextColor3 = color
    tl.TextScaled = true
    tl.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
    tl.TextStrokeTransparency = 0.3
    tl.Parent = bb
end

local function spawnCreatureModel(player: Player, data, c)
    local plot = getPlot(data.plotId)
    if not plot then return end
    local folder = plot:FindFirstChild("Creatures")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "Creatures"
        folder.Parent = plot
    end
    local model = CreatureBuilder.BuildFromParts(c.parts, { name = c.name })
    if (c.growth or 0) > 0 then model:ScaleTo(model:GetScale() * (1 + Config.Growth.SizePerLevel * c.growth)) end
    addNameTag(model, c.name, RARITY_COLOR[c.stats.rarity])
    model:PivotTo(randomSpot(data.plotId) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
    model.Parent = folder
    creatureModels[modelKey(player.UserId, c.id)] = { model = model, plotId = data.plotId, nextMove = os.clock() + math.random() * 3 }
end

local function removeCreatureModel(player: Player, id)
    local key = modelKey(player.UserId, id)
    local entry = creatureModels[key]
    if entry then
        entry.model:Destroy()
        creatureModels[key] = nil
    end
end

local function removeAllCreatureModels(player: Player)
    local prefix = player.UserId .. "_"
    for key, entry in creatureModels do
        if key:sub(1, #prefix) == prefix then
            entry.model:Destroy()
            creatureModels[key] = nil
        end
    end
end

-- wander: glide to a random spot on the plot every few seconds
task.spawn(function()
    while true do
        task.wait(0.25)
        local t = os.clock()
        for key, entry in creatureModels do
            local root = entry.model.PrimaryPart
            if not (root and entry.model.Parent) then
                creatureModels[key] = nil
            elseif not entry.caged and not entry.pinned and t >= entry.nextMove then
                local from = root.Position
                local target = randomSpot(entry.plotId).Position
                target = Vector3.new(target.X, from.Y, target.Z)
                local dist = (target - from).Magnitude
                if dist > 1.5 then
                    local dur = math.clamp(dist / 5, 0.6, 4)
                    root.CFrame = CFrame.lookAt(from, target)
                    TweenService:Create(root, TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                        CFrame = CFrame.lookAt(target, target + (target - from).Unit),
                    }):Play()
                    entry.nextMove = t + dur + math.random(2, 6)
                else
                    entry.nextMove = t + 2
                end
            end
        end
    end
end)

-------------------------------------------------
-- Incubator visuals (capsule colour, size, countdown)
-------------------------------------------------
local function podParts(plotId: number, podNum: number)
    local plot = getPlot(plotId)
    local pod = plot and plot:FindFirstChild(("Plot%d_Pod%d"):format(plotId, podNum))
    if not pod then return nil end
    local vis = pod:FindFirstChild("IncubatorVisual")
    return pod:FindFirstChild("PodEgg"), vis and vis:FindFirstChild("diamond", true)
end

local function setPodVisual(plotId: number, podNum: number, state)
    local egg, mesh = podParts(plotId, podNum)
    if not egg then return end
    local gui = egg:FindFirstChildOfClass("BillboardGui")
    local label = gui and gui:FindFirstChildWhichIsA("TextLabel")
    local light = egg:FindFirstChildOfClass("PointLight")
    local pe = egg:FindFirstChildOfClass("ParticleEmitter")
    if mesh and not mesh:GetAttribute("BaseSize") then
        mesh:SetAttribute("BaseSize", mesh.Size)
    end
    local base = mesh and mesh:GetAttribute("BaseSize")

    if not state then
        if label then
            label.Text = "Empty"
            label.TextColor3 = Color3.fromRGB(225, 225, 235)
        end
        if light then light.Enabled = false end
        if pe then pe.Enabled = false end
        if mesh then
            mesh.Size = base * 0.75
            mesh.Color = Color3.fromRGB(240, 240, 245)
            mesh.Material = Enum.Material.SmoothPlastic
            mesh.Transparency = 0.55
        end
        return
    end

    local rarity = state.part.rarity
    local col = RARITY_COLOR[rarity] or Color3.new(1, 1, 1)
    local t = now()
    local progress = math.clamp((t - state.start) / math.max(0.1, state.finish - state.start), 0, 1)
    local ready = t >= state.finish
    if label then
        if ready then
            label.Text = "READY! Open me"
        else
            local left = math.ceil(state.finish - t)
            label.Text = ("%s capsule  %d:%02d"):format(rarity, left // 60, left % 60)
        end
        label.TextColor3 = col
    end
    if light then
        light.Enabled = true
        light.Color = col
        light.Brightness = ready and 3 or (1 + progress)
        light.Range = ready and 14 or 8
    end
    if pe then
        pe.Enabled = ready
        pe.Color = ColorSequence.new(col)
    end
    if mesh then
        mesh.Size = base * (0.75 + 0.35 * progress)
        mesh.Color = col
        mesh.Material = ready and Enum.Material.Neon or Enum.Material.SmoothPlastic
        mesh.Transparency = 0
    end
end

local function resetPlotVisuals(plotId: number)
    for i = 1, Config.MaxPodsPerPlot do
        setPodVisual(plotId, i, nil)
    end
end

for i = 1, Config.MaxPlots do
    if getPlot(i) then
        resetPlotVisuals(i)
        setPlotSign(i, ("PLOT %d · FREE"):format(i))
    end
end

local function cauldronFX(plotId: number, color: Color3)
    local plot = getPlot(plotId)
    local fx = plot and plot:FindFirstChild("Decor") and plot.Decor:FindFirstChild("BrewFX")
    local pe = fx and fx:FindFirstChildOfClass("ParticleEmitter")
    if pe then
        local old = pe.Color
        pe.Color = ColorSequence.new(color)
        pe:Emit(45)
        task.delay(1.2, function() pe.Color = old end)
    end
end

-------------------------------------------------
-- Raid beam (coins flying from victim lab to thief lab)
-------------------------------------------------
local function raidBeam(fromPlotId: number?, toPlotId: number?, color: Color3)
    local a, b = getPlot(fromPlotId), getPlot(toPlotId)
    if not (a and b) then return end
    local function anchorAt(plot)
        local p = Instance.new("Part")
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.Transparency = 1
        p.Size = Vector3.new(1, 1, 1)
        p.Position = plot.CauldronBody.Position + Vector3.new(0, 6, 0)
        p.Parent = workspace
        local at = Instance.new("Attachment")
        at.Parent = p
        return p, at
    end
    local p0, a0 = anchorAt(a)
    local p1, a1 = anchorAt(b)
    local beam = Instance.new("Beam")
    beam.Attachment0 = a0
    beam.Attachment1 = a1
    beam.Color = ColorSequence.new(color)
    beam.LightEmission = 1
    beam.Width0 = 1.5
    beam.Width1 = 0.6
    beam.CurveSize0 = 40
    beam.CurveSize1 = -40
    beam.FaceCamera = true
    beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    beam.TextureSpeed = 3
    beam.Parent = p0
    task.delay(3, function()
        p0:Destroy()
        p1:Destroy()
    end)
end

-------------------------------------------------
-- Players join / leave
-------------------------------------------------
local function getFreePlot(): number?
    for i = 1, Config.MaxPlots do
        if not plotOwners[i] then return i end
    end
    return nil
end

local function newId(data)
    local id = data.nextId
    data.nextId += 1
    return id
end

-------------------------------------------------
-- Saving (DataService) — what goes into the DataStore
-------------------------------------------------
local SAVE_FIELDS = {
    "money", "ingredients", "parts", "discoveries", "rebirths", "incomeMultiplier",
    "trophies", "arenaLevel", "wins", "nextId", "decor", "boosts", "daily", "receipts",
    "seenIntro", "stats", "draught", "showcase", "piles", "labUp", "nameTags",
}

local function validPart(p)
    return typeof(p) == "table" and Config.PartNames[p.slot] ~= nil and Config.PartNames[p.slot][p.family] ~= nil
        and Config.RarityRank[p.rarity] ~= nil
end

local function serialize(data)
    local s = { v = 1, lastSeen = os.time() }
    for _, k in SAVE_FIELDS do
        s[k] = data[k]
    end
    s.pods = {}
    for podId, p in data.pods do
        local n = podId:match("_Pod(%d+)$")
        if n then s.pods[n] = { part = p.part, start = p.start, finish = p.finish } end
    end
    for n, p in data.offlinePods or {} do s.pods[n] = p end
    s.creatures = {}
    for _, c in data.creatures do
        table.insert(s.creatures, { id = c.id, name = c.name, parts = c.parts, cage = c.cage, growth = c.growth, wings = c.wings, named = c.named })
    end
    return s
end

local function defaultData(plotId)
    return {
        money = Config.StartingMoney,
        plotId = plotId,
        ingredients = {},
        pods = {},        -- podId -> { part, start, finish }
        parts = {},       -- list of { id, slot, family, rarity, shiny }
        creatures = {},   -- list of { id, name, parts = { slot -> part }, stats }
        discoveries = {}, -- "Slot:Family" -> best rarity rank seen
        marketBought = {},
        rebirths = 0,
        incomeMultiplier = 1,
        trophies = 0,
        arenaLevel = 1,
        wins = 0,
        lastWild = 0,
        nextId = 1,
        decor = {},       -- list of { id, item, x, z, r } in plot-local studs
        boosts = {},      -- boostName -> unix time it runs out
        daily = { day = 0, streak = 0 },
        receipts = {},    -- recent Robux purchase ids (never grant twice)
        stats = { brews = 0, built = 0 },
        passes = {},      -- runtime only: owned game passes
        seenIntro = false,
    }
end

local function applySave(data, s, plotId)
    for _, k in SAVE_FIELDS do
        if s[k] ~= nil then data[k] = s[k] end
    end
    -- parts from content that no longer exists are dropped instead of crashing
    local parts = {}
    for _, p in data.parts do
        if validPart(p) then table.insert(parts, p) end
    end
    data.parts = parts
    for n, p in s.pods or {} do
        if validPart(p.part) then
            if plotId then
                data.pods[("Plot%d_Pod%s"):format(plotId, n)] = p
            else
                data.offlinePods = data.offlinePods or {}
                data.offlinePods[n] = p
            end
        end
    end
    for _, c in s.creatures or {} do
        local ok = typeof(c.parts) == "table" and c.parts.Head and c.parts.Torso
        for _, p in c.parts or {} do
            if not validPart(p) then ok = false end
        end
        if ok then
            c.stats = analyze(c.parts)
            c.name = c.name or creatureName(c.parts)
            c.nextRaid = os.clock() + 30
            table.insert(data.creatures, c)
        end
    end
    data.lastSeen = s.lastSeen
end

local function initPlayerData(player: Player)
    -- reserve a plot before yielding so two players joining together can't get the same one
    local plotId = getFreePlot()
    if plotId then plotOwners[plotId] = player.UserId end

    local loadedOk, saved = DataService.load(player.UserId)
    if not player.Parent then
        if plotId then plotOwners[plotId] = nil end
        return
    end

    local data = defaultData(plotId)
    data.canSave = loadedOk -- never overwrite a save we failed to read
    if saved then applySave(data, saved, plotId) end
    playerData[player.UserId] = data

    local ls = Instance.new("Folder")
    ls.Name = "leaderstats"
    local cash = Instance.new("IntValue")
    cash.Name = "Cash"
    cash.Parent = ls
    local tro = Instance.new("IntValue")
    tro.Name = "Trophies"
    tro.Parent = ls
    ls.Parent = player

    if plotId then
        setPlotSign(plotId, player.DisplayName .. "'s Lab")
        player:SetAttribute("PlotId", plotId)
        for i = 1, Config.MaxPodsPerPlot do
            setPodVisual(plotId, i, data.pods[("Plot%d_Pod%d"):format(plotId, i)])
        end
        for _, c in data.creatures do
            spawnCreatureModel(player, data, c)
        end
    end

    -- other systems (Robux passes, decorations, daily rewards) hook in here
    LabAPI.playerLoaded:Fire(player, data)

    -- offline earnings: 25% of income for up to 2 hours away
    local away = data.lastSeen and math.clamp(os.time() - data.lastSeen, 0, 7200) or 0
    local offline = math.floor(totalIncome(data) / 10 * away * 0.25)
    if offline > 0 then data.money += offline end

    sendState(player)
    task.delay(2, function()
        if not player.Parent then return end
        if plotId then
            notify(player, ("Your lab is Plot %d. Look for your name on the gate."):format(plotId), "good")
        else
            notify(player, "All labs are taken right now. You can still shop, battle and spectate.", "bad")
        end
        if offline > 0 then
            notify(player, ("Welcome back! Your creatures earned $%s while you were gone."):format(fmt(offline)), "rare")
        end
        if not loadedOk then
            if RunService:IsStudio() and not DataService.enabled then
                notify(player, "Studio: saving is OFF. Turn on Game Settings > Security > API Services.", "bad")
            else
                notify(player, "Couldn't reach Roblox saves. Progress this session won't be kept. Try rejoining.", "bad")
            end
        end
        if not data.seenIntro then
            data.seenIntro = true
            OpenUI:FireClient(player, "intro")
        end
    end)
end

local duel = { A = nil, B = nil }

local function saveNow(player: Player, release: boolean?)
    local data = playerData[player.UserId]
    if data and data.canSave then
        DataService.save(player.UserId, serialize(data), release)
    end
end

local function cleanupPlayerData(player: Player)
    local data = playerData[player.UserId]
    if not data then return end
    removeAllCreatureModels(player)
    leaveQueue(player)
    LabAPI.playerLeaving:Fire(player, data)
    if duel.A == player then duel.A = nil end
    if duel.B == player then duel.B = nil end
    saveNow(player, true)
    if data.plotId then
        plotOwners[data.plotId] = nil
        resetPlotVisuals(data.plotId)
        setPlotSign(data.plotId, ("PLOT %d · FREE"):format(data.plotId))
    end
    playerData[player.UserId] = nil
end

-- autosave every 90s
task.spawn(function()
    while true do
        task.wait(90)
        for _, p in Players:GetPlayers() do
            task.spawn(saveNow, p, false)
        end
    end
end)

-- server shutting down: save everyone before it closes
game:BindToClose(function()
    local pending = 0
    for _, p in Players:GetPlayers() do
        pending += 1
        task.spawn(function()
            saveNow(p, true)
            pending -= 1
        end)
    end
    local t = os.clock()
    while pending > 0 and os.clock() - t < 25 do
        task.wait(0.2)
    end
end)

Players.PlayerAdded:Connect(initPlayerData)
Players.PlayerRemoving:Connect(cleanupPlayerData)
for _, p in Players:GetPlayers() do
    task.spawn(initPlayerData, p)
end

-------------------------------------------------
-- BUY ELIXIR (Maison Mixalot)
-------------------------------------------------
local function buyIngredient(player: Player, key: string)
    local data = playerData[player.UserId]
    local ing = Config.Ingredients[key]
    if not (data and ing) then return end
    if #data.ingredients >= Config.SatchelSize then
        notify(player, ("Your satchel is full (%d). Go brew at your lab first."):format(Config.SatchelSize), "bad")
        return
    end
    local cost = price(data, ing.price)
    if data.money < cost then
        notify(player, ("%s costs $%s. You have $%s. Broke behaviour."):format(ing.name, fmt(cost), fmt(data.money)), "bad")
        return
    end
    data.money -= cost
    table.insert(data.ingredients, key)
    local disc = shopDiscount(data) > 0 and (" (Rizz discount -%d%%)"):format(math.floor(shopDiscount(data) * 100)) or ""
    notify(player, ("Copped %s for $%s%s. Leans %s."):format(ing.name, fmt(cost), disc, Config.SlotBias[key]:upper()), "good")
    sendState(player)
end

-- Body Bar: one draught per brew, it locks the slot of the next part
local function buyDraught(player: Player, slot: string)
    local data = playerData[player.UserId]
    local d = Config.Draughts[slot]
    if not (data and d) then return end
    if data.draught == slot then
        notify(player, ("You already have a %s. Go brew!"):format(d.name), "info")
        return
    end
    if data.draught and Config.Draughts[data.draught] then
        notify(player, ("Your satchel already has a %s. Brew it first, or empty your satchel."):format(Config.Draughts[data.draught].name), "bad")
        return
    end
    local cost = price(data, d.price)
    if data.money < cost then
        notify(player, ("%s costs $%s. You have $%s."):format(d.name, fmt(cost), fmt(data.money)), "bad")
        return
    end
    data.money -= cost
    data.draught = slot
    notify(player, ("%s Copped a %s for $%s. Your next brew will be a %s."):format(d.icon, d.name, fmt(cost), slot:upper()), "good")
    sendState(player)
end

-------------------------------------------------
-- BREW (your cauldron) -> part capsule
-------------------------------------------------
local function rollRarity(rolls: number): string
    local best = 1
    for _ = 1, rolls do
        local r, acc = math.random(), 0
        for _, odd in Config.BrewOdds do
            acc += odd[2]
            if r < acc then
                best = math.max(best, rarityRank(odd[1]))
                break
            end
        end
    end
    return rarityAt(best)
end

local function brew(player: Player, prompt: ProximityPrompt)
    local data = playerData[player.UserId]
    if not data then return end
    if not data.plotId then
        notify(player, "You don't have a lab yet. All plots are taken.", "bad")
        return
    end
    if plotIdOf(prompt) ~= data.plotId then
        notify(player, ("That's not your cauldron! Your lab is Plot %d."):format(data.plotId), "bad")
        return
    end
    if #data.ingredients < Config.MinElixirsToBrew then
        notify(player, ("Pour in at least %d elixirs. Cop some at Maison Mixalot."):format(Config.MinElixirsToBrew), "bad")
        return
    end

    local podNum
    local podCount = LabAPI.podCount and LabAPI.podCount(data) or Config.LabUpgrades.StartPods
    for i = 1, podCount do
        if not data.pods[("Plot%d_Pod%d"):format(data.plotId, i)] then
            podNum = i
            break
        end
    end
    if not podNum then
        notify(player, ("All %d incubators are busy. Open a capsule first, or unlock another incubator in your lab."):format(podCount), "bad")
        return
    end

    -- family comes from one elixir, the slot from another (or the same) elixir's lean
    local ings = data.ingredients
    local family = ings[math.random(1, #ings)]
    local slot = Config.SlotBias[ings[math.random(1, #ings)]]
    if slot == "Any" then slot = Config.Slots[math.random(1, #Config.Slots)] end
    local draught = data.draught and Config.Draughts[data.draught]
    if draught then slot = data.draught end
    -- starter help: until battles unlock, brews fill the Head / Torso a player still needs to build a creature
    if not draught and #data.creatures < Config.UnlockCreatures then
        local have = {}
        for _, p in data.parts do have[p.slot] = true end
        for _, pod in data.pods do if pod.part then have[pod.part.slot] = true end end
        if not have.Head then slot = "Head" elseif not have.Torso then slot = "Torso" end
    end
    local value = 0
    for _, k in ings do value += Config.Ingredients[k].price end
    local rolls = 1 + math.min(Config.MaxRolls - 1, math.floor(value / Config.ValuePerRoll)) + luckRolls(data)
    local rarity = rollRarity(rolls)
    local shiny = math.random() < Config.ShinyChance + shinyBonus(data)

    local grow = (Config.GrowTime[rarity] or 30) * (1 - growBoost(data)) * brewSpeed(data) * (LabAPI.growMult and LabAPI.growMult(data) or 1)
    data.stats.brews += 1
    local t = now()
    local podId = ("Plot%d_Pod%d"):format(data.plotId, podNum)
    data.pods[podId] = { part = { slot = slot, family = family, rarity = rarity, shiny = shiny }, start = t, finish = t + grow }
    data.ingredients = {}
    data.draught = nil

    cauldronFX(data.plotId, RARITY_COLOR[rarity])
    setPodVisual(data.plotId, podNum, data.pods[podId])
    notify(player, ("The brew hit! A %s %scapsule is growing in pod %d (%ds). %d rarity roll%s."):format(rarity, draught and (slot:upper() .. " ") or "", podNum, math.ceil(grow), rolls, rolls > 1 and "s" or ""), (rarityRank(rarity) >= 4) and "rare" or "good")
    sendState(player)
end

-------------------------------------------------
-- OPEN CAPSULE (your incubator)
-------------------------------------------------
local function openCapsule(player: Player, podId: string, prompt: ProximityPrompt)
    local data = playerData[player.UserId]
    if not data then return end
    if plotIdOf(prompt) ~= data.plotId then
        notify(player, "That's not your incubator.", "bad")
        return
    end
    local pod = data.pods[podId]
    if not pod then
        notify(player, "This incubator is empty. Brew at your cauldron to fill it.", "info")
        return
    end
    if now() < pod.finish then
        notify(player, ("Still cooking... %ds left."):format(math.ceil(pod.finish - now())), "info")
        return
    end
    if #data.parts >= maxParts(data) then
        notify(player, ("Your parts bag is full (%d). Build, fuse or sell some parts."):format(maxParts(data)), "bad")
        return
    end

    local part = pod.part
    part.id = newId(data)
    table.insert(data.parts, part)
    data.pods[podId] = nil

    local key = part.slot .. ":" .. part.family
    local isNew = data.discoveries[key] == nil
    data.discoveries[key] = math.max(data.discoveries[key] or 0, rarityRank(part.rarity))

    setPodVisual(data.plotId, tonumber(podId:match("_Pod(%d+)$")), nil)
    Revealed:FireClient(player, { kind = "part", part = part, isNew = isNew })
    if rarityRank(part.rarity) >= 5 or (part.shiny and rarityRank(part.rarity) >= 3) then
        broadcast(("%s just pulled a %s %s!"):format(player.DisplayName, part.rarity, partName(part)), "rare", player)
    end
    sendState(player)
end

-------------------------------------------------
-- ASSEMBLY LAB
-------------------------------------------------
local function takePart(data, id)
    for i, p in data.parts do
        if p.id == id then
            return table.remove(data.parts, i)
        end
    end
    return nil
end

local function findPart(data, id)
    for _, p in data.parts do
        if p.id == id then return p end
    end
    return nil
end

local function assemble(player: Player, picks)
    local data = playerData[player.UserId]
    if typeof(picks) ~= "table" then return end
    if not near(player, findStation({ "MarketStreet", "AssemblyLab", "AssemblyBench" }), 30) then
        notify(player, "Go to the Assembly Lab on Market Street to build creatures.", "bad")
        return
    end
    if not data.plotId then
        notify(player, "You need a lab for your creature to live in.", "bad")
        return
    end
    if #data.creatures >= maxCreatures(data) then
        notify(player, ("Your lab is full (%d creatures). Take one apart or sell it."):format(maxCreatures(data)), "bad")
        return
    end
    for _, slot in Config.Slots do
        local id = picks[slot]
        if id ~= nil then
            local p = findPart(data, id)
            if not p or p.slot ~= slot then
                notify(player, "Something's off with those parts. Try again.", "bad")
                return
            end
        end
    end
    if picks.Head == nil or picks.Torso == nil then
        notify(player, "A creature needs at least a Head and a Torso.", "bad")
        return
    end
    local parts = {}
    for _, slot in Config.Slots do
        if picks[slot] ~= nil then
            parts[slot] = takePart(data, picks[slot])
        end
    end
    local c = { id = newId(data), parts = parts, nextRaid = os.clock() + 30 }
    c.name = creatureName(parts)
    c.stats = analyze(parts)
    table.insert(data.creatures, c)
    data.stats.built += 1
    spawnCreatureModel(player, data, c)
    LabAPI.creaturesChanged:Fire(player, data)
    Revealed:FireClient(player, { kind = "creature", creature = publicCreature(data, c) })
    if rarityRank(c.stats.rarity) >= 5 or c.stats.setCount >= 5 then
        broadcast(("%s just built a %s %s!"):format(player.DisplayName, c.stats.rarity, c.name), "rare", player)
    end
    sendState(player)
end

local function disassemble(player: Player, id)
    local data = playerData[player.UserId]
    if not near(player, findStation({ "MarketStreet", "AssemblyLab", "AssemblyBench" }), 30) then
        notify(player, "Take creatures apart at the Assembly Lab on Market Street.", "bad")
        return
    end
    for i, c in data.creatures do
        if c.id == id then
            local n = 0
            for _ in c.parts do n += 1 end
            if #data.parts + n > maxParts(data) then
                notify(player, "Not enough room in your parts bag.", "bad")
                return
            end
            table.remove(data.creatures, i)
            removeCreatureModel(player, c.id)
            for _, slot in Config.Slots do
                if c.parts[slot] then table.insert(data.parts, c.parts[slot]) end
            end
            LabAPI.creaturesChanged:Fire(player, data)
            notify(player, ("Took %s apart. %d parts back in your bag."):format(c.name, n), "info")
            sendState(player)
            return
        end
    end
end

-------------------------------------------------
-- THE FORGE: fuse parts, weapon crates
-------------------------------------------------
local function fuse(player: Player, arg)
    local data = playerData[player.UserId]
    if typeof(arg) ~= "table" then return end
    if not near(player, findStation({ "MarketStreet", "Forge", "ForgeAnvil" }), 30) then
        notify(player, "Fuse parts at The Forge on Market Street.", "bad")
        return
    end
    local slot, rarity = arg.slot, arg.rarity
    if not (Config.PartNames[slot] and Config.RarityRank[rarity]) or rarity == "Mythic" then return end
    local picks = {}
    -- use non-shiny parts first
    for _, wantShiny in { false, true } do
        for _, p in data.parts do
            if #picks < Config.FuseCount and p.slot == slot and p.rarity == rarity and (p.shiny == true) == wantShiny then
                table.insert(picks, p.id)
            end
        end
    end
    if #picks < Config.FuseCount then
        notify(player, ("You need %d %s %s parts to fuse."):format(Config.FuseCount, rarity, slot), "bad")
        return
    end
    local fams, anyShiny = {}, false
    for _, id in picks do
        local p = takePart(data, id)
        fams[p.family] = (fams[p.family] or 0) + 1
        anyShiny = anyShiny or p.shiny
    end
    local bestFam, bestN = nil, 0
    for f, k in fams do
        if k > bestN or (k == bestN and math.random() < 0.5) then bestFam, bestN = f, k end
    end
    local part = { id = newId(data), slot = slot, family = bestFam, rarity = rarityAt(rarityRank(rarity) + 1), shiny = anyShiny and math.random() < 0.5 }
    table.insert(data.parts, part)
    local key = part.slot .. ":" .. part.family
    local isNew = data.discoveries[key] == nil
    data.discoveries[key] = math.max(data.discoveries[key] or 0, rarityRank(part.rarity))
    Revealed:FireClient(player, { kind = "part", part = part, isNew = isNew, fused = true })
    sendState(player)
end

local function weaponCrate(player: Player)
    local data = playerData[player.UserId]
    if not near(player, findStation({ "MarketStreet", "Forge", "ForgeAnvil" }), 30) then
        notify(player, "Weapon crates are sold at The Forge on Market Street.", "bad")
        return
    end
    local cost = price(data, Config.WeaponCrateCost)
    if data.money < cost then
        notify(player, ("A weapon crate costs $%s."):format(fmt(cost)), "bad")
        return
    end
    if #data.parts >= maxParts(data) then
        notify(player, "Your parts bag is full.", "bad")
        return
    end
    data.money -= cost
    local part = randomPart("Weapon", rollRarity(Config.WeaponCrateRolls + luckRolls(data)), Config.ShinyChance)
    part.id = newId(data)
    table.insert(data.parts, part)
    local key = part.slot .. ":" .. part.family
    local isNew = data.discoveries[key] == nil
    data.discoveries[key] = math.max(data.discoveries[key] or 0, rarityRank(part.rarity))
    Revealed:FireClient(player, { kind = "part", part = part, isNew = isNew })
    sendState(player)
end

-------------------------------------------------
-- BLACK MARKET
-------------------------------------------------
local function buyMarket(player: Player, index)
    local data = playerData[player.UserId]
    local offer = market.offers[index]
    if not offer then return end
    if not near(player, findStation({ "MarketStreet", "BlackMarket", "MarketCounter" }), 30) then
        notify(player, "Buy from the Black Market on Market Street.", "bad")
        return
    end
    local tag = market.seq .. "_" .. index
    if data.marketBought[tag] then
        notify(player, "You already copped that one. New stock soon.", "info")
        return
    end
    local cost = price(data, offer.price)
    if data.money < cost then
        notify(player, ("That costs $%s."):format(fmt(cost)), "bad")
        return
    end
    if #data.parts >= maxParts(data) then
        notify(player, "Your parts bag is full.", "bad")
        return
    end
    data.money -= cost
    data.marketBought[tag] = true
    local part = table.clone(offer.part)
    part.id = newId(data)
    table.insert(data.parts, part)
    local key = part.slot .. ":" .. part.family
    data.discoveries[key] = math.max(data.discoveries[key] or 0, rarityRank(part.rarity))
    notify(player, ("Copped %s %s for $%s. Don't ask where it came from."):format(part.rarity, partName(part), fmt(cost)), "good")
    sendState(player)
end

-------------------------------------------------
-- REBIRTH (portal in the hub)
-------------------------------------------------
local function rebirth(player: Player)
    local data = playerData[player.UserId]
    if not data then return end
    if data.rebirths >= Config.MaxRebirths then
        notify(player, "You're already at max rebirth. Absolute unit.", "info")
        return
    end
    if data.money < Config.RebirthCost then
        notify(player, ("Rebirth costs $%s. You have $%s. Keep grinding."):format(fmt(Config.RebirthCost), fmt(data.money)), "bad")
        return
    end
    data.rebirths += 1
    data.incomeMultiplier = Config.RebirthMultiplier ^ data.rebirths
    data.money = Config.StartingMoney
    data.creatures = {}
    data.parts = {}
    data.pods = {}
    data.ingredients = {}
    removeAllCreatureModels(player)
    LabAPI.creaturesChanged:Fire(player, data)
    if data.plotId then resetPlotVisuals(data.plotId) end
    notify(player, ("REBORN! Rebirth %d: all income is now x%.2f and your lab holds %d creatures."):format(data.rebirths, data.incomeMultiplier, maxCreatures(data)), "rare")
    broadcast(("%s just rebirthed (x%.2f)!"):format(player.DisplayName, data.incomeMultiplier), "rare", player)
    sendState(player)
end

-------------------------------------------------
-- TELEPORTS (Battle Portal <-> Colosseum)
-------------------------------------------------
local function teleport(player: Player, cf: CFrame)
    local char = player.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char:PivotTo(cf + Vector3.new(0, 3, 0))
    end
end

local function arenaArrival(): CFrame
    local pad = findStation({ "Arena", "ReturnPortal" })
    if pad then return pad.CFrame * CFrame.new(0, 0, -4.5) end
    return CFrame.new(275, 3, -62)
end

local function hubArrival(): CFrame
    local pad = findStation({ "CentralHub", "BattlePortal" })
    if pad then return pad.CFrame * CFrame.new(0, 0, -6) end
    return CFrame.new(0, 3, 20)
end

-------------------------------------------------
-- BATTLES (Ohio Colosseum)
-------------------------------------------------
local arenaBusy = false

local function getArena()
    return workspace:FindFirstChild("Arena")
end

local function makeUnit(parts, name, stats, side: string, idx: number, scale: number?)
    local k = scale or 1
    local hp = math.floor(stats.hp * k)
    local head = stats.perks[1]
    return {
        uid = side .. idx, side = side, name = name, rarity = stats.rarity, parts = parts,
        icon = head and head.icon or "", hp = hp, maxHp = hp, atk = math.floor(stats.atk * k), spd = stats.spd,
        crit = stats.crit, splash = stats.splash, charm = stats.charm, lifesteal = stats.lifesteal,
        guard = stats.guard, heal = stats.heal, hype = stats.hype, grab = stats.grab,
        dodge = stats.phase, ambush = stats.ambush,
    }
end

local function topTeam(data)
    local list = table.clone(data.creatures)
    table.sort(list, function(a, b) return a.stats.power > b.stats.power end)
    local team = {}
    for i = 1, math.min(Config.TeamSize, #list) do
        team[i] = list[i]
    end
    return team
end

local WILD_TIERS = {
    { "Common", "Common", "Common" },
    { "Common", "Uncommon", "Uncommon" },
    { "Uncommon", "Uncommon", "Rare" },
    { "Rare", "Rare", "Rare" },
    { "Rare", "Rare", "Epic" },
    { "Rare", "Epic", "Epic" },
    { "Epic", "Epic", "Epic" },
    { "Epic", "Epic", "Legendary" },
    { "Legendary", "Legendary", "Legendary" },
    { "Legendary", "Legendary", "Mythic" },
}

local function wildTeam(level: number, size: number)
    local tier = WILD_TIERS[math.min(level, #WILD_TIERS)]
    local scale = (level == 1 and 0.7 or 0.85) + math.max(0, level - #WILD_TIERS) * 0.15
    local team = {}
    for i = 1, size do
        local r = tier[i]
        local parts = {}
        for _, slot in Config.Slots do
            -- weaker tiers bring fewer parts
            if slot == "Head" or slot == "Torso" or math.random() < 0.45 + level * 0.1 then
                parts[slot] = randomPart(slot, r, 0)
            end
        end
        team[i] = { parts = parts, name = "Wild " .. creatureName(parts), stats = analyze(parts), scale = scale }
    end
    return team
end

local function simulate(A, B)
    local log = {}
    local all = {}
    for _, u in A do table.insert(all, u) end
    for _, u in B do table.insert(all, u) end
    local function teamOf(side) return side == "A" and A or B end
    local function enemiesOf(u) return u.side == "A" and B or A end
    local function alive(list)
        local r = {}
        for _, u in list do
            if u.hp > 0 then table.insert(r, u) end
        end
        return r
    end

    for _, team in { A, B } do
        local hype = 0
        for _, u in team do
            if u.hype then hype += 1 end
        end
        if hype > 0 and team[1] then
            local mult = 1 + math.min(0.3, 0.1 * hype)
            for _, u in team do u.atk = math.floor(u.atk * mult) end
            table.insert(log, { type = "hype", side = team[1].side, pct = math.floor((mult - 1) * 100 + 0.5) })
        end
    end

    local winner
    for _ = 1, 25 do
        local order = alive(all)
        table.sort(order, function(a, b)
            if a.spd == b.spd then return a.uid < b.uid end
            return a.spd > b.spd
        end)
        for _, u in order do
            if u.hp <= 0 then continue end
            local foes = alive(enemiesOf(u))
            if #foes == 0 then break end
            if u.charmed then
                u.charmed = false
                table.insert(log, { type = "charmed", unit = u.uid })
                continue
            end
            local guards = {}
            for _, f in foes do
                if f.guard then table.insert(guards, f) end
            end
            local target = (#guards > 0 and math.random() < 0.7) and guards[math.random(1, #guards)] or foes[math.random(1, #foes)]
            local ev = { type = "hit", from = u.uid, to = target.uid }
            if target.dodge then
                target.dodge = false
                ev.type = "dodge"
                table.insert(log, ev)
                continue
            end
            local dmg = u.atk * (0.85 + math.random() * 0.3)
            if u.grab then
                dmg *= 1.2
                u.grab = false
            end
            if u.crit > 0 and math.random() < u.crit then
                dmg *= 2
                ev.crit = true
            end
            if u.ambush then
                dmg *= 2
                u.ambush = false
                ev.ambush = true
            end
            dmg = math.max(1, math.floor(dmg))
            target.hp = math.max(0, target.hp - dmg)
            ev.dmg = dmg
            ev.hp = target.hp
            ev.ko = target.hp <= 0
            if u.splash > 0 then
                ev.splash = {}
                for _, f in foes do
                    if f ~= target and f.hp > 0 then
                        local sd = math.max(1, math.floor(dmg * u.splash))
                        f.hp = math.max(0, f.hp - sd)
                        table.insert(ev.splash, { uid = f.uid, hp = f.hp, dmg = sd })
                    end
                end
            end
            if u.lifesteal > 0 then
                local heal = math.floor(dmg * u.lifesteal)
                u.hp = math.min(u.maxHp, u.hp + heal)
                ev.lifesteal = heal
                ev.fromHp = u.hp
            end
            if u.charm > 0 and target.hp > 0 and math.random() < u.charm then
                target.charmed = true
                ev.charm = true
            end
            if u.heal then
                local allies = alive(teamOf(u.side))
                table.sort(allies, function(a, b) return a.hp / a.maxHp < b.hp / b.maxHp end)
                local ally = allies[1]
                if ally then
                    local h = math.floor(ally.maxHp * 0.08)
                    ally.hp = math.min(ally.maxHp, ally.hp + h)
                    ev.heal = { uid = ally.uid, hp = ally.hp, amount = h }
                end
            end
            table.insert(log, ev)
            if #alive(enemiesOf(u)) == 0 then
                winner = u.side
                break
            end
        end
        if winner then break end
    end
    if not winner then
        local function pct(t)
            local s, m = 0, 0
            for _, u in t do s += u.hp; m += u.maxHp end
            return m > 0 and s / m or 0
        end
        winner = pct(A) >= pct(B) and "A" or "B"
        table.insert(log, { type = "timeout" })
    end
    return log, winner
end

local function serializeTeam(team)
    local out = {}
    for _, u in team do
        table.insert(out, { uid = u.uid, name = u.name, rarity = u.rarity, icon = u.icon, maxHp = u.maxHp, atk = u.atk, spd = u.spd })
    end
    return out
end

local function burst(part: BasePart, color: Color3, count: number)
    local a = Instance.new("Attachment")
    a.Parent = part
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    pe.Color = ColorSequence.new(color)
    pe.Size = NumberSequence.new(1, 0)
    pe.Lifetime = NumberRange.new(0.4, 0.8)
    pe.Speed = NumberRange.new(6, 12)
    pe.SpreadAngle = Vector2.new(180, 180)
    pe.LightEmission = 1
    pe.Rate = 0
    pe.Parent = a
    pe:Emit(count)
    task.delay(1, function() a:Destroy() end)
end

local function bodyOf(model)
    return model:FindFirstChild("Torso") or model:FindFirstChild("Head") or model:FindFirstChildWhichIsA("BasePart")
end

local function runBattle(o)
    -- turn-based battles live in ServerScriptService.BattleSystem
    if LabAPI.runTurnBattle then
        arenaBusy = true
        local ok, err = pcall(LabAPI.runTurnBattle, o)
        if not ok then
            warn("[Battle] " .. tostring(err))
            for _, p in o.players do
                if p.Parent then BattleEvent:FireClient(p, "tb_end", { won = false, text = "The battle glitched out. No trophies lost." }) end
            end
        end
        arenaBusy = false
        return
    end
    arenaBusy = true
    local arena = getArena()
    local stage = arena and arena:FindFirstChild("Stage")
    local folder = Instance.new("Folder")
    folder.Name = "BattleUnits"
    folder.Parent = arena or workspace
    local models, homes = {}, {}

    -- serialize before the fight so everyone starts at full HP
    local startA, startB = serializeTeam(o.A), serializeTeam(o.B)

    if stage then
        local base = stage.CFrame * CFrame.new(0, stage.Size.Y / 2, 0)
        local function place(team, xSign)
            for i, u in team do
                local pos = (base * CFrame.new(xSign * 11, 0, (i - (#team + 1) / 2) * 7)).Position
                local m = CreatureBuilder.BuildFromParts(u.parts, { name = u.name })
                local cf = CFrame.lookAt(pos, pos - base.RightVector * xSign)
                m:PivotTo(cf)
                addNameTag(m, u.name, RARITY_COLOR[u.rarity])
                m.Parent = folder
                models[u.uid] = m
                homes[u.uid] = cf
            end
        end
        place(o.A, -1)
        place(o.B, 1)
    end

    local log, winner = simulate(o.A, o.B)
    for _, p in o.players do
        BattleEvent:FireClient(p, "start", {
            kind = o.kind, mySide = o.sides[p], titleA = o.titleA, titleB = o.titleB, A = startA, B = startB,
        })
    end
    task.wait(2.2)

    for _, ev in log do
        for _, p in o.players do
            if p.Parent then BattleEvent:FireClient(p, "action", ev) end
        end
        local attacker = ev.from and models[ev.from]
        local victim = ev.to and models[ev.to]
        if attacker and victim and homes[ev.from] then
            local root = attacker.PrimaryPart
            local home = homes[ev.from]
            local targetPos = victim.PrimaryPart.Position
            local lunge = home.Position:Lerp(targetPos, 0.6)
            TweenService:Create(root, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.lookAt(lunge, targetPos) }):Play()
            task.delay(0.22, function()
                if root.Parent then
                    TweenService:Create(root, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { CFrame = home }):Play()
                end
            end)
            local body = bodyOf(victim)
            if body then
                task.delay(0.16, function()
                    if ev.type == "dodge" then
                        burst(body, Color3.fromRGB(200, 200, 255), 10)
                    else
                        burst(body, ev.crit and Color3.fromRGB(255, 220, 60) or Color3.fromRGB(255, 90, 90), ev.crit and 30 or 15)
                    end
                end)
            end
            local function ko(model)
                local vroot = model.PrimaryPart
                task.delay(0.4, function()
                    if vroot.Parent then
                        TweenService:Create(vroot, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
                            CFrame = vroot.CFrame * CFrame.new(0, -8, 0) * CFrame.Angles(0, math.rad(180), 0),
                        }):Play()
                    end
                end)
            end
            if ev.ko then ko(victim) end
            for _, s in ev.splash or {} do
                local m = models[s.uid]
                if m then
                    local b = bodyOf(m)
                    if b then task.delay(0.2, burst, b, Color3.fromRGB(120, 200, 255), 10) end
                    if s.hp <= 0 then ko(m) end
                end
            end
        elseif ev.type == "charmed" and models[ev.unit] then
            local body = bodyOf(models[ev.unit])
            if body then burst(body, Color3.fromRGB(255, 120, 200), 20) end
        end
        task.wait(1)
    end

    task.wait(0.8)
    local results = o.onFinish(winner) or {}
    for _, p in o.players do
        if p.Parent then
            local r = results[p] or { won = false, text = "" }
            BattleEvent:FireClient(p, "end", { winner = winner, won = r.won, text = r.text })
            sendState(p)
        end
    end
    task.wait(3)
    folder:Destroy()
    arenaBusy = false
end

local function teamUnits(data, side)
    local units = {}
    for i, c in topTeam(data) do
        units[i] = makeUnit(c.parts, c.name, c.stats, side, i)
    end
    return units
end

local function startWild(player: Player)
    local data = playerData[player.UserId]
    if not data then return end
    if arenaBusy then
        notify(player, "The Colosseum is busy. Watch and place a bet, or wait for this fight to end.", "info")
        return
    end
    if #data.creatures == 0 then
        notify(player, "You need at least one creature. Build one at the Assembly Lab!", "bad")
        return
    end
    local cd = Config.WildCooldown - (os.clock() - data.lastWild)
    if cd > 0 then
        notify(player, ("Your creatures are catching their breath (%ds)."):format(math.ceil(cd)), "info")
        return
    end
    data.lastWild = os.clock()

    local level = data.arenaLevel
    local A = teamUnits(data, "A")
    local B = {}
    for i, w in wildTeam(level, #A) do B[i] = makeUnit(w.parts, w.name, w.stats, "B", i, w.scale) end

    task.spawn(runBattle, {
        kind = "wild", players = { player }, sides = { [player] = "A" },
        A = A, B = B, titleA = player.DisplayName, titleB = ("Wild Brainrots · Tier %d"):format(level),
        onFinish = function(w)
            local d = playerData[player.UserId]
            if not d then return {} end
            if w == "A" then
                local reward = math.floor(150 * 1.65 ^ (level - 1))
                local tro = 1 + math.floor(level / 3)
                d.money += reward
                d.trophies += tro
                d.wins += 1
                d.arenaLevel += 1
                local text = ("Victory! +$%s and +%d trophies. Tier %d unlocked."):format(fmt(reward), tro, d.arenaLevel)
                -- every 3rd tier drops a part
                if level % 3 == 0 and #d.parts < maxParts(d) then
                    local part = randomPart(nil, rollRarity(2 + math.floor(level / 3)), Config.ShinyChance)
                    part.id = newId(d)
                    table.insert(d.parts, part)
                    text ..= (" Dropped: %s %s!"):format(part.rarity, partName(part))
                end
                return { [player] = { won = true, text = text } }
            end
            return { [player] = { won = false, text = "The wild brainrots cooked you. Build stronger creatures and run it back." } }
        end,
    })
end

local function startDuel(pa: Player, pb: Player, ranked: boolean)
    local da, db = playerData[pa.UserId], playerData[pb.UserId]
    if not (da and db) then return end
    if ranked then
        teleport(pa, (findStation({ "Arena", "DuelPadA" }) or { CFrame = CFrame.new(124, 3, -40) }).CFrame)
        teleport(pb, (findStation({ "Arena", "DuelPadB" }) or { CFrame = CFrame.new(166, 3, -40) }).CFrame)
    end
    local A, B = teamUnits(da, "A"), teamUnits(db, "B")
    broadcast(("%s vs %s is LIVE at the Ohio Colosseum!%s"):format(pa.DisplayName, pb.DisplayName, ranked and " (Ranked)" or ""), "rare")
    task.spawn(runBattle, {
        kind = "duel", players = { pa, pb }, sides = { [pa] = "A", [pb] = "B" },
        A = A, B = B, titleA = pa.DisplayName, titleB = pb.DisplayName,
        onFinish = function(w)
            local winP, loseP = (w == "A") and pa or pb, (w == "A") and pb or pa
            local wd, ld = playerData[winP.UserId], playerData[loseP.UserId]
            local bounty, lost = 0, 0
            if wd and ld then
                bounty = math.min(math.floor(ld.money * Config.DuelBountyPct), Config.DuelBountyCap)
                ld.money -= bounty
                wd.money += bounty
                wd.trophies += Config.RankedWin
                wd.wins += 1
                if ranked then
                    lost = math.min(ld.trophies, Config.RankedLoss)
                    ld.trophies -= lost
                end
            end
            return {
                [winP] = { won = true, text = ("You won! +$%s bounty and +%d trophies."):format(fmt(bounty), Config.RankedWin) },
                [loseP] = { won = false, text = ("%s took the W and a $%s bounty.%s"):format(winP.DisplayName, fmt(bounty), lost > 0 and (" -%d trophy."):format(lost) or "") },
            }
        end,
    })
end

local function joinDuel(player: Player, padName: string)
    local data = playerData[player.UserId]
    if not data then return end
    if arenaBusy then
        notify(player, "The Colosseum is busy. Wait for the current battle to end.", "info")
        return
    end
    if #data.creatures == 0 then
        notify(player, "You need at least one creature to duel.", "bad")
        return
    end
    local slot = (padName == "DuelPadA") and "A" or "B"
    local other = (slot == "A") and "B" or "A"
    if duel[other] == player then duel[other] = nil end
    duel[slot] = player
    if duel[other] and duel[other].Parent then
        local pa, pb = duel.A, duel.B
        duel.A, duel.B = nil, nil
        startDuel(pa, pb, false)
    else
        duel[other] = nil
        notify(player, "Ready! Waiting for a challenger on the other duel pad...", "info")
        broadcast(("%s is waiting for a duel at the Ohio Colosseum!"):format(player.DisplayName), "info", player)
    end
end

local function queueRanked(player: Player)
    local data = playerData[player.UserId]
    if not data then return end
    if #data.creatures == 0 then
        notify(player, "Build a creature at the Assembly Lab before queueing.", "bad")
        return
    end
    if inQueue(player) then return end
    table.insert(rankedQueue, player)
    notify(player, ("Queued for Ranked. %d in queue. You'll be teleported when a match is found."):format(#rankedQueue), "info")
    sendAll()
end

-- matchmaker
task.spawn(function()
    while true do
        task.wait(2)
        for i = #rankedQueue, 1, -1 do
            local p = rankedQueue[i]
            if not p.Parent or not playerData[p.UserId] then table.remove(rankedQueue, i) end
        end
        if not arenaBusy and #rankedQueue >= 2 then
            local pa = table.remove(rankedQueue, 1)
            local pb = table.remove(rankedQueue, 1)
            notify(pa, ("Match found vs %s!"):format(pb.DisplayName), "rare")
            notify(pb, ("Match found vs %s!"):format(pa.DisplayName), "rare")
            startDuel(pa, pb, true)
            sendAll()
        end
    end
end)

-------------------------------------------------
-- Prompts (all handled on the server)
-------------------------------------------------
local function setupPrompt(prompt: ProximityPrompt)
    local parent = prompt.Parent
    if not parent or prompt:GetAttribute("Wired") then return end
    prompt:SetAttribute("Wired", true)
    prompt.RequiresLineOfSight = false -- the decor meshes sit on top of the prompt anchors
    local n = parent.Name
    local key = Config.BottleToIngredient[n]

    if prompt.Name == "TalkPrompt" then
        prompt.Triggered:Connect(function(p) OpenUI:FireClient(p, "dialogue") end)
    elseif Config.BottleToDraught[n] then
        local slot = Config.BottleToDraught[n]
        local d = Config.Draughts[slot]
        prompt.ActionText = "Buy · $" .. fmt(d.price)
        prompt.ObjectText = d.name .. " (" .. slot .. ")"
        prompt.HoldDuration = 0
        prompt.Triggered:Connect(function(p) buyDraught(p, slot) end)
    elseif key then
        local ing = Config.Ingredients[key]
        prompt.ActionText = "Buy · $" .. fmt(ing.price)
        prompt.ObjectText = ing.name .. " (" .. Config.SlotBias[key] .. ")"
        -- floating price tag always matches Config
        for _, d in parent:GetDescendants() do
            if d:IsA("TextLabel") and d:FindFirstAncestorOfClass("BillboardGui") then
                d.Text = ing.name:upper():gsub(" ", "\n", 1) .. "\n$" .. fmt(ing.price)
                d.TextColor3 = Config.Color(ing.color)
            end
        end
        prompt.HoldDuration = 0
        prompt.Triggered:Connect(function(p) buyIngredient(p, key) end)
    elseif n == "CauldronBody" then
        prompt.ActionText = "Brew"
        prompt.ObjectText = "Cauldron"
        prompt.MaxActivationDistance = 14
        prompt.Triggered:Connect(function(p) brew(p, prompt) end)
    elseif n == "PodEgg" then
        prompt.ActionText = "Open capsule"
        prompt.ObjectText = "Incubator"
        prompt.Triggered:Connect(function(p) openCapsule(p, parent.Parent.Name, prompt) end)
    elseif n == "RebirthShrine" then
        prompt.ActionText = "Rebirth · $" .. fmt(Config.RebirthCost)
        prompt.ObjectText = "Rebirth Portal"
        prompt.HoldDuration = 1.5
        prompt.Triggered:Connect(rebirth)
    elseif n == "TradeTable" then
        prompt.ActionText = "Sell parts & creatures"
        prompt.ObjectText = "Trading Post"
        prompt.Triggered:Connect(function(p) OpenUI:FireClient(p, "sell") end)
    elseif n == "AssemblyBench" then
        prompt.ActionText = "Build a creature"
        prompt.ObjectText = "Assembly Lab"
        prompt.Triggered:Connect(function(p) OpenUI:FireClient(p, "assembly") end)
    elseif n == "ForgeAnvil" then
        prompt.ActionText = "Fuse & crates"
        prompt.ObjectText = "The Forge"
        prompt.Triggered:Connect(function(p) OpenUI:FireClient(p, "forge") end)
    elseif n == "MarketCounter" then
        prompt.ActionText = "Browse"
        prompt.ObjectText = "Black Market"
        prompt.Triggered:Connect(function(p) OpenUI:FireClient(p, "market") end)
    elseif n == "BattlePortal" then
        prompt.ActionText = "Enter the Colosseum"
        prompt.ObjectText = "Battle Portal"
        prompt.Triggered:Connect(function(p)
            local d = playerData[p.UserId]
            if not d or locked(p, d, "Battles") then
                return
            end
            teleport(p, arenaArrival())
            OpenUI:FireClient(p, "battle")
        end)
    elseif n == "ReturnPortal" then
        prompt.ActionText = "Back to the hub"
        prompt.ObjectText = "Return Portal"
        prompt.Triggered:Connect(function(p) teleport(p, hubArrival()) end)
    elseif n == "WildPad" then
        prompt.ActionText = "Fight wild brainrots"
        prompt.ObjectText = "Ohio Colosseum"
        prompt.Triggered:Connect(startWild)
    elseif n == "DuelPadA" or n == "DuelPadB" then
        prompt.ActionText = "Ready up for a duel"
        prompt.ObjectText = "Ohio Colosseum"
        prompt.Triggered:Connect(function(p) joinDuel(p, n) end)
    end
end

for _, d in workspace:GetDescendants() do
    if d:IsA("ProximityPrompt") then setupPrompt(d) end
end
workspace.DescendantAdded:Connect(function(d)
    if d:IsA("ProximityPrompt") then task.defer(setupPrompt, d) end
end)

-------------------------------------------------
-- Client requests (UI buttons)
-------------------------------------------------
-------------------------------------------------
-- GROWTH POTION
-------------------------------------------------
local function growCreature(player: Player, id, free: boolean?)
    local data = playerData[player.UserId]
    local c
    for _, x in data.creatures do
        if x.id == id then c = x end
    end
    if not c then return end
    local level = c.growth or 0
    if level >= Config.Growth.MaxLevel then
        notify(player, c.name .. " is already as big as it gets!", "info")
        return
    end
    local cost = free and 0 or Config.Growth.Cost[level + 1]
    if data.money < cost then
        notify(player, ("A Growth Potion costs $%s. You have $%s."):format(fmt(cost), fmt(data.money)), "bad")
        return
    end
    data.money -= cost
    c.growth = level + 1
    -- swell the model in place, then let Showcase/PlotDecor re-seat it
    local entry = creatureModels[modelKey(player.UserId, c.id)]
    if entry and entry.model.Parent then
        local m = entry.model
        local from = 1 + Config.Growth.SizePerLevel * level
        local to = 1 + Config.Growth.SizePerLevel * c.growth
        local base = m:GetScale() / from
        local body = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
        if body then burst(body, RARITY_COLOR[c.stats.rarity], 30) end
        task.spawn(function()
            for k = 1, 12 do
                if not m.Parent then return end
                m:ScaleTo(base * (from + (to - from) * k / 12))
                task.wait(0.05)
            end
            LabAPI.creaturesChanged:Fire(player, data) -- re-seat on its pedestal at the final size
        end)
    end
    LabAPI.creaturesChanged:Fire(player, data)
    Revealed:FireClient(player, { kind = "creature", grown = true, creature = publicCreature(data, c) })
    sendState(player)
    return true
end

local function nearTradingPost(player)
    local tt = findStation({ "TradingPost", "TradeTable" })
    if not near(player, tt, 35) then
        notify(player, "Go to the Trading Post to sell.", "bad")
        return false
    end
    return true
end

local lastRequest = {}
Request.OnServerEvent:Connect(function(player: Player, action: string, arg)
    local data = playerData[player.UserId]
    if not data or typeof(action) ~= "string" then return end
    -- light rate limit
    local t = os.clock()
    if lastRequest[player] and t - lastRequest[player] < 0.15 then return end
    lastRequest[player] = t

    -- actions owned by add-on scripts (Monetization, PlotDecor)
    if (action == "TradeRequest" or (action == "TradeRespond" and typeof(arg) == "table" and arg.accept)) and locked(player, data, "Trading") then return end
    if action == "PlaceBet" and locked(player, data, "Betting") then return end
    local ext = LabAPI.requests[action]
    if ext then
        ext(player, arg)
        return
    end

    if action == "SellCreature" then
        if not nearTradingPost(player) then return end
        for i, c in data.creatures do
            if c.id == arg then
                local value = creatureValue(c)
                table.remove(data.creatures, i)
                removeCreatureModel(player, c.id)
                LabAPI.creaturesChanged:Fire(player, data)
                data.money += value
                notify(player, ("Sold %s for $%s."):format(c.name, fmt(value)), "good")
                sendState(player)
                return
            end
        end
    elseif action == "SellPart" then
        if not nearTradingPost(player) then return end
        local p = takePart(data, arg)
        if p then
            local value = partValue(p)
            data.money += value
            notify(player, ("Sold %s for $%s."):format(partName(p), fmt(value)), "good")
            sendState(player)
        end
    elseif action == "Assemble" then
        assemble(player, arg)
    elseif action == "GrowCreature" then
        growCreature(player, arg)
    elseif action == "Disassemble" then
        disassemble(player, arg)
    elseif action == "Fuse" then
        fuse(player, arg)
    elseif action == "WeaponCrate" then
        weaponCrate(player)
    elseif action == "BuyMarket" then
        buyMarket(player, arg)
    elseif action == "QueueRanked" then
        queueRanked(player)
    elseif action == "LeaveQueue" then
        leaveQueue(player)
        notify(player, "Left the Ranked queue.", "info")
        sendAll()
    elseif action == "GoArena" then
        if locked(player, data, "Battles") then return end
        teleport(player, arenaArrival())
    elseif action == "GoHub" then
        teleport(player, hubArrival())
    elseif action == "EmptySatchel" then
        if #data.ingredients == 0 and not data.draught then return end
        local refund = 0
        for _, k in data.ingredients do
            refund += math.floor(Config.Ingredients[k].price * 0.5)
        end
        if data.draught and Config.Draughts[data.draught] then
            refund += math.floor(Config.Draughts[data.draught].price * 0.5)
        end
        data.ingredients = {}
        data.draught = nil
        data.money += refund
        notify(player, ("Emptied your satchel. Refunded $%s (50%%)."):format(fmt(refund)), "info")
        sendState(player)
    elseif action == "Sync" then
        sendState(player)
    end
end)
Players.PlayerRemoving:Connect(function(p) lastRequest[p] = nil end)

-------------------------------------------------
-- Leaderboard (hub)
-------------------------------------------------
local function updateLeaderboard()
    local hub = workspace:FindFirstChild("CentralHub")
    local frame = hub and hub:FindFirstChild("LeaderboardFrame")
    local label = frame and frame:FindFirstChildWhichIsA("TextLabel", true)
    if not label then return end
    local rows = {}
    for _, p in Players:GetPlayers() do
        local d = playerData[p.UserId]
        if d then
            table.insert(rows, { p.DisplayName, d.trophies, #d.creatures, totalIncome(d) })
        end
    end
    table.sort(rows, function(a, b)
        if a[2] == b[2] then return a[4] > b[4] end
        return a[2] > b[2]
    end)
    local lines = { "TOP CHEMISTS", "" }
    for i = 1, 5 do
        local r = rows[i]
        lines[#lines + 1] = r and ("%d. %s  ·  %d trophies"):format(i, r[1], r[2]) or (i .. ". ???")
    end
    label.Text = table.concat(lines, "\n")
end

-------------------------------------------------
-- Main loops
-------------------------------------------------
-- every second: incubator countdowns, raids, duel pad cleanup, market refresh
task.spawn(function()
    while true do
        task.wait(1)
        local list = Players:GetPlayers()

        if now() >= market.refreshAt then
            refreshMarket()
            broadcast("The Black Market just restocked.", "info")
            sendAll()
        end

        for _, p in list do
            local d = playerData[p.UserId]
            if d and d.plotId then
                for i = 1, Config.MaxPodsPerPlot do
                    local pod = d.pods[("Plot%d_Pod%d"):format(d.plotId, i)]
                    if pod then setPodVisual(d.plotId, i, pod) end
                end
            end
        end

        -- raids: Fanum Taxer and Imposter heads steal from rival labs
        for _, thief in list do
            local td = playerData[thief.UserId]
            if not td then continue end
            for _, c in td.creatures do
                local taxer, disguised = hasTrait(c, "FanumTaxer"), hasTrait(c, "Imposter")
                if (taxer or disguised) and os.clock() >= (c.nextRaid or 0) then
                    c.nextRaid = os.clock() + (disguised and 90 or 60)
                    local victims = {}
                    for _, v in list do
                        local vd = playerData[v.UserId]
                        if v ~= thief and vd and vd.money >= Config.TaxMinVictimCash then
                            table.insert(victims, v)
                        end
                    end
                    if #victims == 0 then continue end
                    local victim = victims[math.random(1, #victims)]
                    local vd = playerData[victim.UserId]
                    local amount = math.min(math.floor(vd.money * (disguised and 0.03 or 0.04)), Config.TaxCap[c.parts.Head.rarity] or 100)
                    if not disguised then
                        local guards = countTrait(vd, "Bodyguard")
                        if guards > 0 and math.random() < 1 - 0.5 ^ guards then
                            notify(victim, ("Your Bodyguard blocked %s's %s from taxing you!"):format(thief.DisplayName, c.name), "good")
                            notify(thief, ("%s's Bodyguard blocked your %s's raid."):format(victim.DisplayName, c.name), "bad")
                            amount = 0
                        end
                    end
                    if amount > 0 then
                        vd.money -= amount
                        td.money += amount
                        raidBeam(vd.plotId, td.plotId, disguised and Color3.fromRGB(120, 120, 140) or Color3.fromRGB(90, 255, 140))
                        if disguised then
                            notify(victim, ("Someone in disguise taxed you $%s. Bodyguards never saw it coming."):format(fmt(amount)), "bad")
                            notify(thief, ("Your %s slipped into %s's lab undercover: +$%s"):format(c.name, victim.DisplayName, fmt(amount)), "good")
                        else
                            notify(victim, ("%s's %s hit you with the Fanum Tax: -$%s"):format(thief.DisplayName, c.name, fmt(amount)), "bad")
                            notify(thief, ("Your %s taxed %s for $%s"):format(c.name, victim.DisplayName, fmt(amount)), "good")
                        end
                        sendState(victim)
                        sendState(thief)
                    end
                end
            end
        end

        -- duel pads: drop players who wandered off
        local arena = getArena()
        for _, slot in { "A", "B" } do
            local p = duel[slot]
            local pad = arena and arena:FindFirstChild("DuelPad" .. slot)
            local hrp = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if p and (not hrp or not pad or (hrp.Position - pad.Position).Magnitude > 25) then
                duel[slot] = nil
                if p.Parent then notify(p, "You left the duel pad, so you're out of the queue.", "info") end
            end
        end
    end
end)

-- every 10 seconds: passive income + leaderboard
task.spawn(function()
    while true do
        task.wait(Config.IncomeInterval)
        for _, p in Players:GetPlayers() do
            local d = playerData[p.UserId]
            if d and #d.creatures > 0 then
                -- Showcase takes the pedestal creatures' share; the rest goes straight to the wallet
                d.money += LabAPI.payIncome and LabAPI.payIncome(p, d) or totalIncome(d)
                sendState(p)
            end
        end
        updateLeaderboard()
    end
end)

-------------------------------------------------
-- Dr. Mixalot: idle animation + speech bubble
-------------------------------------------------
task.spawn(function()
    local npc = workspace.IngredientShop:FindFirstChild("DrMixalot")
    local hum = npc and npc:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://180435571" -- R6 idle
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    if ok and track then
        track.Looped = true
        track:Play()
    end

    local head = npc:FindFirstChild("Head") and npc.Head:FindFirstChildWhichIsA("BasePart") or npc.PrimaryPart
    local bb = Instance.new("BillboardGui")
    bb.Name = "Bubble"
    bb.Size = UDim2.fromOffset(260, 60)
    bb.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
    bb.MaxDistance = 45
    bb.Parent = head
    local f = Instance.new("Frame")
    f.Size = UDim2.fromScale(1, 1)
    f.BackgroundColor3 = Color3.fromRGB(250, 246, 255)
    f.Parent = bb
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 14)
    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1, -16, 1, -8)
    tl.Position = UDim2.fromOffset(8, 4)
    tl.BackgroundTransparency = 1
    tl.TextScaled = true
    tl.TextWrapped = true
    tl.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
    tl.TextColor3 = Color3.fromRGB(40, 25, 60)
    tl.Parent = f
    local lines = {
        "Press F to talk, apprentice!",
        "Rare Elixirs next door: Ember Jaw, Halo Mist, Dreamcandy. Pricey. Worth it.",
        "Frostmind Tonic brews heads. Venomfang Brew brews weapons.",
        "More elixirs in one brew = more rarity rolls.",
        "Three parts of one family? Set bonus, baby.",
        "Got three of the same part? The Forge will fuse them.",
        "The Black Market restocks every 5 minutes. Don't tell anyone.",
        "Battle Portal's in the hub. Go get some trophies.",
    }
    local i = 0
    while npc.Parent do
        i = i % #lines + 1
        tl.Text = lines[i]
        bb.Enabled = true
        task.wait(5)
        bb.Enabled = false
        task.wait(3)
    end
end)

-------------------------------------------------
-- STUDIO-ONLY TEST HOOK (never exists in a live server)
-- From the Server command bar:
--   game.ServerStorage.DebugGrant:Invoke(player, { money = 50000, parts = { {slot="Head", family="Rizz", rarity="Epic"} } })
-------------------------------------------------
if game:GetService("RunService"):IsStudio() then
    local grant = Instance.new("BindableFunction")
    grant.Name = "DebugGrant"
    grant.OnInvoke = function(player: Player, opts)
        local data = playerData[player.UserId]
        if not data then return "no data" end
        data.money += opts.money or 0
        for _, p in opts.parts or {} do
            table.insert(data.parts, { id = newId(data), slot = p.slot, family = p.family, rarity = p.rarity or "Common", shiny = p.shiny or false })
        end
        if opts.roundtrip then
            -- simulate leave + rejoin: save table -> JSON -> fresh data
            local json = game:GetService("HttpService"):JSONEncode(serialize(data))
            local fresh = defaultData(data.plotId)
            applySave(fresh, game:GetService("HttpService"):JSONDecode(json), data.plotId)
            fresh.canSave, fresh.passes = data.canSave, data.passes
            removeAllCreatureModels(player)
            playerData[player.UserId] = fresh
            for _, c in fresh.creatures do spawnCreatureModel(player, fresh, c) end
            for i = 1, Config.MaxPodsPerPlot do
                setPodVisual(fresh.plotId, i, fresh.pods[("Plot%d_Pod%d"):format(fresh.plotId, i)])
            end
            LabAPI.playerLoaded:Fire(player, fresh)
            sendState(player)
            return ("%d bytes, %d parts, %d creatures, $%d"):format(#json, #fresh.parts, #fresh.creatures, fresh.money)
        end
        sendState(player)
        return #data.parts
    end
    grant.Parent = game:GetService("ServerStorage")
end

-------------------------------------------------
-- Expose helpers to the add-on scripts (see LabAPI)
-------------------------------------------------
LabAPI.playerData = playerData
LabAPI.growCreature = growCreature
LabAPI.notify = notify
LabAPI.broadcast = broadcast
LabAPI.sendState = sendState
LabAPI.newId = newId
LabAPI.getPlot = getPlot
LabAPI.plotFrame = plotFrame
LabAPI.fmt = fmt
LabAPI.near = near
LabAPI.spawnCreatureModel = spawnCreatureModel
LabAPI.removeCreatureModel = removeCreatureModel
LabAPI.creatureModels = creatureModels
LabAPI.modelKey = modelKey
LabAPI.refreshMarket = refreshMarket
LabAPI.rollRarity = rollRarity
LabAPI.randomPart = randomPart
LabAPI.rarityRank = rarityRank
LabAPI.partName = partName
LabAPI.totalIncome = totalIncome
LabAPI.creatureIncome = creatureIncome
LabAPI.maxParts = maxParts
LabAPI.maxCreatures = maxCreatures
LabAPI.partValue = partValue
LabAPI.creatureValue = creatureValue
LabAPI.setPodVisual = setPodVisual
LabAPI.saveNow = saveNow
LabAPI.openUI = function(player, what, arg) OpenUI:FireClient(player, what, arg) end
LabAPI.revealPart = function(player, data, part)
    part.id = newId(data)
    table.insert(data.parts, part)
    local key = part.slot .. ":" .. part.family
    local isNew = data.discoveries[key] == nil
    data.discoveries[key] = math.max(data.discoveries[key] or 0, rarityRank(part.rarity))
    Revealed:FireClient(player, { kind = "part", part = part, isNew = isNew })
    if rarityRank(part.rarity) >= 5 then
        broadcast(("%s just pulled a %s %s!"):format(player.DisplayName, part.rarity, partName(part)), "rare", player)
    end
end
-- exhibition: two wild packs fight so spectators have something to bet on (BattleSystem starts these)
LabAPI.arenaBusy = function() return arenaBusy end
LabAPI.startExhibition = function(level: number)
    if arenaBusy then return false end
    local A, B = {}, {}
    -- 2v2 keeps an exhibition to about a minute
    for i, w in wildTeam(level, 2) do A[i] = makeUnit(w.parts, w.name, w.stats, "A", i, w.scale) end
    for i, w in wildTeam(level, 2) do B[i] = makeUnit(w.parts, w.name, w.stats, "B", i, w.scale) end
    arenaBusy = true -- claim it now so nobody slips in before the task starts
    task.spawn(function()
        arenaBusy = false
        runBattle({
            kind = "exhibition", players = {}, sides = {}, A = A, B = B,
            titleA = "🔴 Red Pack", titleB = "🔵 Blue Pack",
            onFinish = function() return {} end,
        })
    end)
    return true
end

LabAPI.ready = true

updateLeaderboard()
print("[GameManager] Server ready — parts edition!")
