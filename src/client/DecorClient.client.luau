--[[
    DecorClient — the "Decorate your lab" mode.
    Pick an item from the catalog bar, see a green/red preview on your plot,
    rotate it, place it. "Move / Sell" lets you tap an existing decoration.
    Works with mouse (click to place, R rotate, Q cancel) and touch (tap a spot, then ✅).
    Opened from LabClient's 🏡 Decorate button (fires DecorUI.Toggle).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local DecorLogic = require(ReplicatedStorage:WaitForChild("DecorLogic"))
local Templates = ReplicatedStorage:WaitForChild("DecorTemplates")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")

local new, label, button, corner, stroke, pad = UIKit.new, UIKit.label, UIKit.button, UIKit.corner, UIKit.stroke, UIKit.pad
local GOLD, PANEL, PANEL2, PANEL3, WHITE, MUTED = UIKit.GOLD, UIKit.PANEL, UIKit.PANEL2, UIKit.PANEL3, UIKit.WHITE, UIKit.MUTED

local state = nil
local active = false
local mode = nil        -- "place" | "move" | "pick"
local item = nil        -- item id being placed/moved
local moving = nil      -- decor entry being moved
local target = { x = 0, z = 40, r = 0 }
local ghost, highlight
local category = "Epic"

-------------------------------------------------
-- UI
-------------------------------------------------
local gui = new("ScreenGui", { Name = "DecorUI", ResetOnSpawn = false, DisplayOrder = 3, Enabled = true, Parent = player:WaitForChild("PlayerGui") })
local toggleEvent = new("BindableEvent", { Name = "Toggle", Parent = gui })

local bar = new("Frame", {
    Name = "Catalog", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -20, 0, 214),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.05, Visible = false, Parent = gui,
}, { corner(16), stroke(GOLD, 0.3, 2), new("UISizeConstraint", { MaxSize = Vector2.new(980, 214) }) })
UIKit.autoScale(bar)

local title = label({ Size = UDim2.new(0.5, 0, 0, 30), Position = UDim2.fromOffset(14, 8), Text = "🏡 DECORATE YOUR LAB", TextColor3 = GOLD, FontFace = UIKit.HEAD, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, Parent = bar })
local moneyLbl = label({ Size = UDim2.new(0, 160, 0, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -260, 0, 8), Text = "$0", TextColor3 = GOLD, FontFace = UIKit.HEAD, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Right, Parent = bar })
local pickBtn = button({ Size = UDim2.fromOffset(120, 32), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -126, 0, 8), Text = "✋ Move / Sell", TextSize = 16, BackgroundColor3 = PANEL3, TextColor3 = WHITE, Parent = bar })
local doneBtn = button({ Size = UDim2.fromOffset(104, 32), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Text = "✅ Done", TextSize = 18, Parent = bar })

local tabs = new("Frame", { Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 44), BackgroundTransparency = 1, Parent = bar },
    { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
local list = new("ScrollingFrame", {
    Size = UDim2.new(1, -24, 0, 126), Position = UDim2.fromOffset(12, 80), BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(),
    ScrollBarThickness = 5, ScrollBarImageColor3 = GOLD, Parent = bar,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

-- floating action buttons above the bar
local actions = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -236), Size = UDim2.fromOffset(0, 50), AutomaticSize = Enum.AutomaticSize.X,
    BackgroundTransparency = 1, Visible = false, Parent = gui,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }) })
UIKit.autoScale(actions)
local rotBtn = button({ Size = UDim2.fromOffset(110, 46), Text = "🔄 Rotate", TextSize = 18, BackgroundColor3 = PANEL3, TextColor3 = WHITE, LayoutOrder = 1, Parent = actions })
local placeBtn = button({ Size = UDim2.fromOffset(140, 46), Text = "✅ Place", TextSize = 20, BackgroundColor3 = UIKit.GREEN, LayoutOrder = 2, Parent = actions })
local sellBtn = button({ Size = UDim2.fromOffset(140, 46), Text = "💰 Sell", TextSize = 18, BackgroundColor3 = UIKit.RED, TextColor3 = WHITE, LayoutOrder = 3, Visible = false, Parent = actions })
local cancelBtn = button({ Size = UDim2.fromOffset(110, 46), Text = "❌ Cancel", TextSize = 18, BackgroundColor3 = PANEL2, TextColor3 = WHITE, LayoutOrder = 4, Parent = actions })
for _, b in { rotBtn, placeBtn, sellBtn, cancelBtn } do stroke(Color3.new(0, 0, 0), 0.5, 2).Parent = b end

local hint = label({
    AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(560, 34), Text = "", TextSize = 16, FontFace = UIKit.BOLD,
    BackgroundTransparency = 0.25, BackgroundColor3 = PANEL, Visible = false, Parent = gui,
}, { corner(10) })
UIKit.autoScale(hint)

local function setHint(text) hint.Text = text; hint.Visible = text ~= "" end

-------------------------------------------------
-- helpers
-------------------------------------------------
local function myPlot()
    if not (state and state.plotId) then return nil end
    return workspace.PlayerPlots:FindFirstChild("Plot" .. state.plotId)
end

local function isVip() return state and state.passes and state.passes.VIP == true end

local function clearGhost()
    if ghost then ghost:Destroy() end
    ghost, highlight = nil, nil
end

local function makeGhost(id)
    clearGhost()
    local t = Templates:FindFirstChild(id)
    if not t then return end
    ghost = t:Clone()
    for _, d in ghost:GetDescendants() do
        if d:IsA("BasePart") then
            d.CanCollide = false
            d.CanQuery = false
            d.CanTouch = false
            d.Transparency = math.max(d.Transparency, 0.35)
        elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
            d.Enabled = false
        end
    end
    highlight = new("Highlight", { FillTransparency = 0.65, OutlineTransparency = 0.2, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Parent = ghost })
    ghost.Parent = workspace.CurrentCamera
end

local function validNow()
    if not (state and item) then return false, "" end
    local it = DecorLogic.Items[item]
    if mode == "place" then
        if it.vip and not isVip() then return false, "VIP only — get VIP in the 💎 Shop" end
        if state.money < it.price then return false, "Not enough cash" end
    end
    return DecorLogic.canPlace(state.decor or {}, item, target.x, target.z, target.r, moving and moving.id)
end

local function updateGhost()
    local plot = myPlot()
    if not (ghost and plot) then return end
    target.x, target.z = DecorLogic.snap(item, target.r, target.x, target.z)
    ghost:PivotTo(DecorLogic.worldCFrame(plot, target.x, target.z, target.r))
    local ok, why = validNow()
    highlight.FillColor = ok and UIKit.GREEN or UIKit.RED
    highlight.OutlineColor = ok and UIKit.GREEN or UIKit.RED
    placeBtn.AutoButtonColor = ok
    placeBtn.BackgroundTransparency = ok and 0 or 0.5
    if mode == "place" or mode == "move" then
        local it = DecorLogic.Items[item]
        local base = (mode == "move") and ("Moving " .. it.name) or (it.name .. (it.price > 0 and (" · $" .. UIKit.fmt(it.price)) or ""))
        setHint(ok and base or (base .. "  —  " .. (why or "")))
    end
end

-- screen point -> plot-local x/z on the ground plane
local function screenToPlot(pos)
    local plot = myPlot()
    if not plot then return nil end
    local frame = DecorLogic.plotFrame(plot)
    local ray = workspace.CurrentCamera:ViewportPointToRay(pos.X, pos.Y)
    if math.abs(ray.Direction.Y) < 1e-4 then return nil end
    local t = (frame.Position.Y - ray.Origin.Y) / ray.Direction.Y
    if t < 0 then return nil end
    local hit = ray.Origin + ray.Direction * t
    local l = frame:PointToObjectSpace(hit)
    return math.clamp(l.X, -24, 24), math.clamp(l.Z, -24, 68)
end

local function pickDecor(pos)
    local plot = myPlot()
    local folder = plot and plot:FindFirstChild("Decorations")
    if not folder then return nil end
    local ray = workspace.CurrentCamera:ViewportPointToRay(pos.X, pos.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { folder }
    local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
    local m = hit and hit.Instance
    while m and m.Parent ~= folder do m = m.Parent end
    if not m then
        -- fallback: nearest decoration to the tapped ground point
        local x, z = screenToPlot(pos)
        if not x then return nil end
        local best, bd = nil, 6
        for _, e in state.decor or {} do
            local d = math.sqrt((e.x - x) ^ 2 + (e.z - z) ^ 2)
            if d < bd then best, bd = e, d end
        end
        return best
    end
    local id = m:GetAttribute("DecorId")
    for _, e in state.decor or {} do
        if e.id == id then return e end
    end
    return nil
end

-------------------------------------------------
-- modes
-------------------------------------------------
local function idle()
    mode, item, moving = nil, nil, nil
    clearGhost()
    actions.Visible = false
    pickBtn.Text = "✋ Move / Sell"
    setHint(UIKit.device() == "desktop" and "Pick something below, then click your plot to place it." or "Pick something below, then tap your plot.")
end

local function startPlace(id)
    mode, item, moving = "place", id, nil
    makeGhost(id)
    actions.Visible = true
    sellBtn.Visible = false
    placeBtn.Text = UIKit.device() == "desktop" and "✅ Place (click)" or "✅ Place"
    updateGhost()
end

local function startPick()
    mode, item, moving = "pick", nil, nil
    clearGhost()
    actions.Visible = false
    pickBtn.Text = "❌ Stop moving"
    setHint("Click / tap a decoration to move or sell it.")
end

local function startMove(entry)
    mode, item, moving = "move", entry.item, entry
    target.x, target.z, target.r = entry.x, entry.z, entry.r
    makeGhost(entry.item)
    actions.Visible = true
    sellBtn.Visible = true
    local it = DecorLogic.Items[entry.item]
    sellBtn.Text = ("💰 Sell $%s"):format(UIKit.fmt(math.floor(it.price * DecorLogic.SellBack)))
    placeBtn.Text = "✅ Move here"
    updateGhost()
end

local function confirm()
    if mode == "place" then
        local ok = validNow()
        if ok then
            Request:FireServer("PlaceDecor", { item = item, x = target.x, z = target.z, r = target.r })
        end
    elseif mode == "move" then
        local ok = validNow()
        if ok then
            Request:FireServer("MoveDecor", { id = moving.id, x = target.x, z = target.z, r = target.r })
            idle()
        end
    end
end

local function rotate()
    target.r = (target.r + 1) % 4
    updateGhost()
end

rotBtn.Activated:Connect(rotate)
placeBtn.Activated:Connect(confirm)
cancelBtn.Activated:Connect(idle)
sellBtn.Activated:Connect(function()
    if moving then
        Request:FireServer("SellDecor", moving.id)
        idle()
    end
end)
pickBtn.Activated:Connect(function()
    if mode == "pick" then idle() else startPick() end
end)

-------------------------------------------------
-- catalog
-------------------------------------------------
local function renderCatalog()
    UIKit.clear(tabs)
    for i, cat in DecorLogic.Categories do
        local b = button({ Size = UDim2.fromOffset(cat == "VIP" and 86 or 104, 28), Text = (cat == "VIP" and "⭐ " or cat == "Epic" and "🔥 " or "") .. cat, TextSize = 15, LayoutOrder = i,
            BackgroundColor3 = cat == category and GOLD or PANEL3, TextColor3 = cat == category and UIKit.DARKTEXT or WHITE, Parent = tabs })
        b.Activated:Connect(function()
            category = cat
            renderCatalog()
        end)
    end
    UIKit.clear(list)
    local order = 0
    for _, id in DecorLogic.Order do
        local it = DecorLogic.Items[id]
        if it.cat == category then
            order += 1
            local afford = state and ((it.vip and isVip()) or (not it.vip and state.money >= it.price))
            local card = button({
                Size = UDim2.fromOffset(122, 118), Text = "", LayoutOrder = order, BackgroundColor3 = (item == id and mode == "place") and PANEL3 or PANEL2, Parent = list,
            })
            stroke(it.vip and Color3.fromRGB(255, 120, 255) or GOLD, item == id and 0 or 0.6, 2).Parent = card
            label({ Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 4), Text = it.icon or "❓", TextSize = 34, Parent = card })
            label({ Size = UDim2.new(1, -8, 0, 32), Position = UDim2.fromOffset(4, 48), Text = it.name, TextSize = 14, FontFace = UIKit.BOLD, Parent = card })
            local priceText = it.vip and (isVip() and "FREE · VIP" or "⭐ VIP ONLY") or ("$" .. UIKit.fmt(it.price))
            label({ Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 80), Text = priceText, TextSize = 14, FontFace = UIKit.HEAD,
                TextColor3 = afford and GOLD or UIKit.RED, Parent = card })
            if it.cage then
                label({ Size = UDim2.new(1, -8, 0, 16), Position = UDim2.fromOffset(4, 98), Text = ("+%d%% cash"):format(math.floor(it.cage * 100)), TextSize = 13, FontFace = UIKit.BOLD, TextColor3 = UIKit.GREEN, Parent = card })
            end
            card.Activated:Connect(function()
                startPlace(id)
                renderCatalog()
            end)
        end
    end
end

-------------------------------------------------
-- open / close
-------------------------------------------------
local function open()
    if not myPlot() then
        return
    end
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local plot = myPlot()
    if hrp and (hrp.Position - plot.PlotGround.Position).Magnitude > 95 then
        Request:FireServer("GoHome") -- hop back to your lab first
    end
    active = true
    bar.Visible = true
    renderCatalog()
    idle()
end

local function close()
    active = false
    bar.Visible = false
    actions.Visible = false
    setHint("")
    clearGhost()
    mode = nil
end

doneBtn.Activated:Connect(close)
toggleEvent.Event:Connect(function()
    if active then close() else open() end
end)
Remotes:WaitForChild("OpenUI").OnClientEvent:Connect(function(what)
    if what == "decorate" then open() end
end)

Remotes:WaitForChild("StateUpdate").OnClientEvent:Connect(function(s)
    state = s
    if active then
        moneyLbl.Text = "$" .. UIKit.fmt(s.money)
        renderCatalog()
        if ghost then updateGhost() end
    end
end)

-------------------------------------------------
-- input
-------------------------------------------------
RunService.RenderStepped:Connect(function()
    if not (active and ghost) then return end
    if UserInputService.MouseEnabled and UIKit.device() == "desktop" then
        local x, z = screenToPlot(UserInputService:GetMouseLocation() - Vector2.new(0, game:GetService("GuiService"):GetGuiInset().Y))
        if x then
            target.x, target.z = x, z
            updateGhost()
        end
    end
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if not active or processed then return end
    if input.KeyCode == Enum.KeyCode.R then
        rotate()
    elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Escape then
        if mode then idle() else close() end
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        local pos = UserInputService:GetMouseLocation() - Vector2.new(0, game:GetService("GuiService"):GetGuiInset().Y)
        if mode == "pick" then
            local e = pickDecor(pos)
            if e then startMove(e) end
        elseif mode then
            confirm()
        end
    end
end)

-- touch: a tap moves the preview there (then press ✅), or picks a decoration
UserInputService.TouchTap:Connect(function(positions, processed)
    if not active or processed or not positions[1] then return end
    local pos = positions[1]
    if mode == "pick" then
        local e = pickDecor(pos)
        if e then startMove(e) end
    elseif mode then
        local x, z = screenToPlot(pos)
        if x then
            target.x, target.z = x, z
            updateGhost()
        end
    end
end)
