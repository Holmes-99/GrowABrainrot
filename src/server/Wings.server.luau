--[[
    Wings — the Legendary Wings upgrade (art: ServerStorage.Tpl_Wings).

    * "AddWings" (creature id) buys wings for one creature: Config.Wings.Cost, once per creature.
      Saved as c.wings. The boost is applied to c.stats once (c.stats.winged marks it).
    * Every winged creature model gets the wings welded to its back, flapping.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local LabAPI = require(script.Parent:WaitForChild("LabAPI"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
LabAPI.waitReady()

local W = Config.Wings
local TPL = ServerStorage:WaitForChild("Tpl_Wings")
local Revealed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Revealed")

local function applyWings(c)
    if not c.wings or c.stats.winged then return end
    local st = c.stats
    st.hp = math.floor(st.hp * (1 + W.Hp))
    st.atk = math.floor(st.atk * (1 + W.Atk))
    st.spd = math.floor(st.spd * (1 + W.Spd) * 10 + 0.5) / 10
    st.baseIncome *= 1 + W.Income
    if st.power then st.power *= 1 + W.Atk end
    table.insert(st.perks, { slot = "Wings", icon = W.Perk.icon, title = W.Perk.title, desc = W.Perk.desc, rarity = "Legendary" })
    st.winged = true
end

-- flapping welds: weld -> { base, rel, side, model, scaleAt }
local flaps = {}
local function scaled(cf, k) return CFrame.new(cf.Position * k) * cf.Rotation end

local function attach(model)
    if model:FindFirstChild("WingSet") then return end
    local torso = model:FindFirstChild("Torso")
    if not torso then return end
    local set = TPL:Clone()
    set.Name = "WingSet"
    local height = (model:GetAttribute("Height") or 6) * model:GetScale()
    set:ScaleTo(set:GetScale() * height * 0.6 / 4.73)
    local root = model.PrimaryPart
    -- centre of the wings: upper back, just behind the torso (creatures face -Z)
    local back = torso.CFrame * CFrame.new(0, torso.Size.Y * 0.25, torso.Size.Z / 2 + 0.15)
    local pivotWorld = CFrame.new(back.Position) * (root and root.CFrame.Rotation or torso.CFrame.Rotation)
    local pivot0 = set:GetPivot()
    for side, name in { [1] = "left wing", [-1] = "right wing" } do
        local wing = set:FindFirstChild(name)
        local geom = wing and wing:FindFirstChildWhichIsA("BasePart", true)
        if geom then
            local rel = pivot0:ToObjectSpace(geom.CFrame)
            local weld = Instance.new("Weld")
            weld.Part0 = torso
            weld.Part1 = geom
            local base = torso.CFrame:ToObjectSpace(pivotWorld)
            weld.C0 = base * rel
            weld.Parent = geom
            flaps[weld] = { base = base, rel = rel, side = side, model = model, scaleAt = model:GetScale() }
        end
    end
    set.Parent = model
end

local function syncAll()
    for key, entry in LabAPI.creatureModels do
        local uid, id = key:match("^(%d+)_(.+)$")
        local data = uid and LabAPI.playerData[tonumber(uid)]
        if data and entry.model and entry.model.Parent then
            for _, c in data.creatures do
                if tostring(c.id) == id and c.wings then attach(entry.model) end
            end
        end
    end
end

RunService.Heartbeat:Connect(function()
    local a = math.sin(os.clock() * 3) * math.rad(28)
    for weld, f in flaps do
        if not weld.Parent or not f.model.Parent then
            flaps[weld] = nil
        else
            local k = f.model:GetScale() / f.scaleAt -- the creature may have grown since
            weld.C0 = scaled(f.base, k) * CFrame.Angles(0, 0, a * f.side) * scaled(f.rel, k)
        end
    end
end)

local function addWings(player, id, free)
    local data = LabAPI.playerData[player.UserId]
    if not data then return end
    local c
    for _, x in data.creatures do if x.id == id then c = x end end
    if not c then return end
    if c.wings then
        LabAPI.notify(player, c.name .. " already has wings!", "info")
        return
    end
    local cost = free and 0 or W.Cost
    if data.money < cost then
        LabAPI.notify(player, ("Legendary Wings cost $%s. You have $%s."):format(LabAPI.fmt(W.Cost), LabAPI.fmt(data.money)), "bad")
        return
    end
    data.money -= cost
    c.wings = true
    applyWings(c)
    syncAll()
    LabAPI.creaturesChanged:Fire(player, data)
    local pub
    for _, x in data.creatures do if x == c then
        pub = { id = c.id, name = c.name, rarity = c.stats.rarity, parts = c.parts, perks = c.stats.perks, hp = c.stats.hp, atk = c.stats.atk,
            spd = c.stats.spd, power = c.stats.power, income = LabAPI.creatureIncome(data, c), setCount = c.stats.setCount, growth = c.growth or 0, wings = true }
    end end
    Revealed:FireClient(player, { kind = "creature", winged = true, creature = pub })
    LabAPI.sendState(player)
    return true
end
LabAPI.requests.AddWings = function(player, id) addWings(player, id, false) end
LabAPI.addWings = addWings -- Robux purchase (Monetization) passes free = true

LabAPI.playerLoaded:Connect(function(player, data)
    for _, c in data.creatures do applyWings(c) end
    task.delay(0.5, syncAll)
    LabAPI.sendState(player)
end)
LabAPI.creaturesChanged:Connect(function(player, data)
    for _, c in data.creatures do applyWings(c) end -- e.g. a winged creature arriving by trade
    task.defer(syncAll)
end)
for _, p in Players:GetPlayers() do
    local d = LabAPI.playerData[p.UserId]
    if d then for _, c in d.creatures do applyWings(c) end end
end
task.defer(syncAll)

print("[Wings] ready")
