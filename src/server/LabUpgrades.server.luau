--[[
    LabUpgrades — upgrades you buy right in your lab (no menu needed).

    * Incubators 4 and 5 (PlotN_Pod4/5) sit behind glass. Walk up and hold the prompt to unlock
      the next one (Config.LabUpgrades.PodCost). Saved in data.labUp.pods (0-2 extra pods).
    * The Auto-Stirrer stand beside the cauldron upgrades a spinning paddle (3 levels). Each level
      cuts capsule cook time by Config.LabUpgrades.StirrerSpeed. Saved in data.labUp.stirrer.
    * GameManager asks LabAPI.podCount(data) and LabAPI.growMult(data) when brewing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LabAPI = require(script.Parent:WaitForChild("LabAPI"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
LabAPI.waitReady()

local U = Config.LabUpgrades
local MAX_EXTRA = Config.MaxPodsPerPlot - U.StartPods

local function ensure(data)
    data.labUp = data.labUp or {}
    data.labUp.pods = math.clamp(tonumber(data.labUp.pods) or 0, 0, MAX_EXTRA)
    data.labUp.stirrer = math.clamp(tonumber(data.labUp.stirrer) or 0, 0, #U.StirrerCost)
    return data.labUp
end

function LabAPI.podCount(data)
    return U.StartPods + ensure(data).pods
end
function LabAPI.growMult(data)
    return 1 - U.StirrerSpeed * ensure(data).stirrer
end

local function plotOf(id) return id and workspace.PlayerPlots:FindFirstChild("Plot" .. id) end

-- draw one plot; data = nil means nobody owns it
local function draw(plotId, data)
    local plot = plotOf(plotId)
    if not plot then return end
    local up = data and ensure(data) or { pods = 0, stirrer = 0 }
    local have = U.StartPods + up.pods
    for k = U.StartPods + 1, Config.MaxPodsPerPlot do
        local pod = plot:FindFirstChild(("Plot%d_Pod%d"):format(plotId, k))
        local lock = pod and pod:FindFirstChild("PodLock")
        if lock then
            local open = k <= have
            local nextUp = data ~= nil and k == have + 1
            lock.Transparency = open and 1 or 0.55
            lock.CanCollide = not open
            lock.LockTag.Enabled = not open
            lock.LockTag.Text.Text = nextUp and ("🔒 INCUBATOR %d\n<font color='#FFCD5A'>$%s</font>"):format(k, LabAPI.fmt(U.PodCost[k]))
                or ("🔒 INCUBATOR %d"):format(k)
            lock.UnlockPrompt.Enabled = nextUp
            lock.UnlockPrompt.ActionText = nextUp and ("Unlock · $" .. LabAPI.fmt(U.PodCost[k])) or "Unlock"
            local egg = pod:FindFirstChild("PodEgg")
            local open_ = egg and egg:FindFirstChildWhichIsA("ProximityPrompt")
            if open_ then open_.Enabled = open end
        end
    end
    local lvl = up.stirrer
    local paddle = plot:FindFirstChild("Stirrer")
    if paddle then
        for _, p in paddle:GetChildren() do
            if p:IsA("BasePart") and p.Name ~= "Hub" then p.Transparency = lvl > 0 and 0 or 1 end
        end
        paddle:SetAttribute("Speed", lvl * 2.5)
    end
    local stand = plot:FindFirstChild("StirrerStand")
    if stand then
        local cost = U.StirrerCost[lvl + 1]
        local cut = math.floor(U.StirrerSpeed * lvl * 100 + 0.5)
        local text = ("⚙ AUTO-STIRRER %d/%d"):format(lvl, #U.StirrerCost)
        if lvl > 0 then text ..= ("\n<font color='#7CFF8C'>capsules cook %d%% faster</font>"):format(cut) end
        if data and cost then text ..= ("\n<font color='#FFCD5A'>next: $%s</font>"):format(LabAPI.fmt(cost)) end
        if data and not cost then text ..= "\n<font color='#FFCD5A'>MAXED</font>" end
        stand.StirTag.Text.Text = text
        stand.UpgradePrompt.Enabled = data ~= nil and cost ~= nil
        stand.UpgradePrompt.ActionText = cost and ("Upgrade · $" .. LabAPI.fmt(cost)) or "Upgrade"
    end
end

local function owner(plotId)
    for _, p in Players:GetPlayers() do
        local d = LabAPI.playerData[p.UserId]
        if d and d.plotId == plotId then return p, d end
    end
end

local function buy(player, plotId, what)
    local data = LabAPI.playerData[player.UserId]
    if not (data and data.plotId == plotId) then
        if data then LabAPI.notify(player, "That's someone else's lab.", "bad") end
        return
    end
    local up = ensure(data)
    local cost, msg
    if what == "pod" then
        local k = U.StartPods + up.pods + 1
        cost = U.PodCost[k]
        if not cost then return end
        msg = ("Incubator %d unlocked! You can grow %d capsules at once now."):format(k, k)
    else
        cost = U.StirrerCost[up.stirrer + 1]
        if not cost then return end
        msg = ("Auto-Stirrer level %d! Capsules cook %d%% faster."):format(up.stirrer + 1, math.floor(U.StirrerSpeed * (up.stirrer + 1) * 100 + 0.5))
    end
    if data.money < cost then
        LabAPI.notify(player, ("You need $%s for that. You have $%s."):format(LabAPI.fmt(cost), LabAPI.fmt(data.money)), "bad")
        return
    end
    data.money -= cost
    if what == "pod" then up.pods += 1 else up.stirrer += 1 end
    LabAPI.notify(player, msg, "good")
    draw(plotId, data)
    LabAPI.sendState(player)
end

-- wire prompts once
for _, plot in workspace.PlayerPlots:GetChildren() do
    local plotId = tonumber(plot.Name:match("^Plot(%d+)$"))
    if plotId then
        for k = U.StartPods + 1, Config.MaxPodsPerPlot do
            local pod = plot:FindFirstChild(("Plot%d_Pod%d"):format(plotId, k))
            local lock = pod and pod:FindFirstChild("PodLock")
            if lock then lock.UnlockPrompt.Triggered:Connect(function(p) buy(p, plotId, "pod") end) end
        end
        local stand = plot:FindFirstChild("StirrerStand")
        if stand then stand.UpgradePrompt.Triggered:Connect(function(p) buy(p, plotId, "stirrer") end) end
        draw(plotId, nil)
    end
end

-- spin every active stirrer paddle
RunService.Heartbeat:Connect(function(dt)
    for _, plot in workspace.PlayerPlots:GetChildren() do
        local paddle = plot:FindFirstChild("Stirrer")
        local speed = paddle and paddle:GetAttribute("Speed") or 0
        if speed > 0 and paddle.PrimaryPart then
            paddle:PivotTo(paddle:GetPivot() * CFrame.Angles(0, speed * dt, 0))
        end
    end
end)

LabAPI.playerLoaded:Connect(function(player, data)
    ensure(data)
    if data.plotId then draw(data.plotId, data) end
end)
LabAPI.playerLeaving:Connect(function(player, data)
    if data and data.plotId then draw(data.plotId, nil) end
end)
for _, p in Players:GetPlayers() do
    local d = LabAPI.playerData[p.UserId]
    if d and d.plotId then draw(d.plotId, d) end
end

table.insert(LabAPI.stateHooks, function(data, st)
    local up = ensure(data)
    st.labUp = { pods = up.pods, stirrer = up.stirrer, podCount = U.StartPods + up.pods }
end)

print("[LabUpgrades] ready")
