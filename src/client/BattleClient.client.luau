--[[
    BattleClient — the turn-based battle screen: fighter cards, move buttons,
    the timing bar, the battle log and the result card. Spectators get the same
    view without the controls. Server side: ServerScriptService.BattleSystem.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local BattleMoves = require(ReplicatedStorage:WaitForChild("BattleMoves"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")

local new, label, button, corner, stroke, clear = UIKit.new, UIKit.label, UIKit.button, UIKit.corner, UIKit.stroke, UIKit.clear
local GOLD, PANEL, PANEL2, PANEL3, WHITE, MUTED = UIKit.GOLD, UIKit.PANEL, UIKit.PANEL2, UIKit.PANEL3, UIKit.WHITE, UIKit.MUTED
local RARITY_COLOR = {}
for r, rgb in Config.RarityColors do RARITY_COLOR[r] = Config.Color(rgb) end
local GRADE_COLOR = {
    PERFECT = Color3.fromRGB(255, 215, 70), GREAT = Color3.fromRGB(110, 235, 140),
    GOOD = Color3.fromRGB(150, 200, 255), MISS = Color3.fromRGB(255, 100, 100),
}

local gui = new("ScreenGui", { Name = "BattleUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 20, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })

-------------------------------------------------
-- layout
-------------------------------------------------
local top = new("Frame", {
    Name = "Top", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(860, 128),
    BackgroundTransparency = 1, Visible = false, Parent = gui,
})
UIKit.autoScale(top)

local function makeCard(xAnchor)
    local card = new("Frame", {
        AnchorPoint = Vector2.new(xAnchor, 0), Position = UDim2.fromScale(xAnchor, 0), Size = UDim2.new(0.47, 0, 0, 112),
        BackgroundColor3 = PANEL, BackgroundTransparency = 0.08, Parent = top,
    }, { corner(14), stroke(GOLD, 0.35, 2) })
    local c = { frame = card }
    c.owner = label({ Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 6), Text = "", TextColor3 = MUTED, FontFace = UIKit.BOLD, TextSize = 13, TextXAlignment = xAnchor == 0 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
    c.name = label({ Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 22), Text = "", FontFace = UIKit.HEAD, TextSize = 24, TextXAlignment = xAnchor == 0 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
    local back = new("Frame", { Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 56), BackgroundColor3 = Color3.fromRGB(15, 10, 22), Parent = card }, { corner(8) })
    c.fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = UIKit.GREEN, Parent = back }, { corner(8) })
    c.hp = label({ Size = UDim2.fromScale(1, 1), Text = "", TextColor3 = WHITE, FontFace = UIKit.BOLD, TextSize = 12, ZIndex = 3, Parent = back })
    c.status = label({ Size = UDim2.new(0.62, -10, 0, 22), Position = UDim2.fromOffset(10, 78), Text = "", TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
    c.pips = new("Frame", { AnchorPoint = Vector2.new(1, 0), Size = UDim2.new(0.38, -10, 0, 22), Position = UDim2.new(1, -10, 0, 80), BackgroundTransparency = 1, Parent = card },
        { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 5) }) })
    return c
end
local cards = { left = makeCard(0), right = makeCard(1) }
local vsLabel = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.fromOffset(60, 40), Text = "VS", TextColor3 = GOLD, FontFace = UIKit.HEAD, TextSize = 30, Parent = top })
local hideBtn = button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -30), Size = UDim2.fromOffset(110, 26), Text = "Hide fight", TextSize = 14, BackgroundColor3 = PANEL3, TextColor3 = WHITE, Visible = false, Parent = top })
local spectateTag = label({ AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, 0, 0, -28), Size = UDim2.fromOffset(150, 24), TextStrokeTransparency = 0.3, Text = "👀 SPECTATING", TextColor3 = MUTED, FontFace = UIKit.HEAD, TextSize = 14, Visible = false, Parent = top })

local logBox = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.new(1, 0, 0, 54),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.2, Parent = top,
}, { corner(12) })
local logText = label({ Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), Text = "", RichText = true, TextSize = 16, FontFace = UIKit.BOLD, Parent = logBox })
top.Size = UDim2.fromOffset(860, 180)

-- move picker
local picker = new("Frame", {
    Name = "Moves", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(860, 200),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.06, Visible = false, Parent = gui,
}, { corner(16), stroke(GOLD, 0.3, 2) })
UIKit.autoScale(picker)
local pickTitle = label({ Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 6), Text = "", TextColor3 = GOLD, FontFace = UIKit.HEAD, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Parent = picker })
local pickTimer = label({ AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(80, 30), Position = UDim2.new(1, -12, 0, 6), Text = "", TextColor3 = WHITE, FontFace = UIKit.HEAD, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Right, Parent = picker })
local grid = new("Frame", { Size = UDim2.new(1, -24, 1, -48), Position = UDim2.fromOffset(12, 40), BackgroundTransparency = 1, Parent = picker })
local gridLayout = new("UIGridLayout", { CellPadding = UDim2.fromOffset(8, 8), CellSize = UDim2.new(0.2, -7, 1, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })

-- timing bar
local timing = new("Frame", {
    Name = "Timing", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(560, 190),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.04, Visible = false, Parent = gui,
}, { corner(16), stroke(GOLD, 0.2, 3) })
UIKit.autoScale(timing)
local timingTitle = label({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 8), Text = "", TextColor3 = GOLD, FontFace = UIKit.HEAD, TextSize = 22, Parent = timing })
local barBack = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46), Size = UDim2.new(1, -40, 0, 40), BackgroundColor3 = Color3.fromRGB(14, 10, 20), ClipsDescendants = true, Parent = timing }, { corner(10) })
local zoneFrames = {}
for i = #BattleMoves.ZONES, 1, -1 do
    local z = BattleMoves.ZONES[i]
    zoneFrames[i] = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromScale(z.within * 2, 1), BackgroundColor3 = GRADE_COLOR[z.name], BackgroundTransparency = 0.05 + (i - 1) * 0.2, BorderSizePixel = 0, ZIndex = 2 + (#BattleMoves.ZONES - i), Parent = barBack })
end
local needle = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 6, 1, 8), Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = WHITE, ZIndex = 8, Parent = barBack }, { corner(3) })
local tapBtn = button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(260, 56), Text = "STOP!", TextSize = 30, Parent = timing })
label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.new(1, -40, 0, 20), Text = "Stop the needle in the gold for a PERFECT hit (x1.5). Space, click or tap.", TextColor3 = MUTED, TextSize = 13, Parent = timing })

local gradePop = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(500, 90), Text = "", FontFace = UIKit.HEAD, TextSize = 64, TextStrokeTransparency = 0.2, Visible = false, ZIndex = 20, Parent = gui })

-- result card
local result = new("Frame", {
    Name = "Result", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(440, 230),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.03, Visible = false, ZIndex = 30, Parent = gui,
}, { corner(18), stroke(GOLD, 0.1, 3) })
UIKit.autoScale(result)
local resultTitle = label({ Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 14), Text = "", FontFace = UIKit.HEAD, TextSize = 48, ZIndex = 31, Parent = result })
local resultText = label({ Size = UDim2.new(1, -40, 0, 70), Position = UDim2.fromOffset(20, 78), Text = "", TextSize = 16, ZIndex = 31, Parent = result })
button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(180, 44), Text = "OK", TextSize = 22, ZIndex = 32, Parent = result }, function()
    result.Visible = false
end)

-- betting (spectators)
local betPanel = new("Frame", {
    Name = "Bets", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.58, 0), Size = UDim2.fromOffset(300, 270),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.04, Visible = false, Parent = gui,
}, { corner(16), stroke(GOLD, 0.2, 2) })
UIKit.autoScale(betPanel)
label({ Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 8), Text = "💰 PLACE A BET", TextColor3 = GOLD, FontFace = UIKit.HEAD, TextSize = 22, Parent = betPanel })
local betSub = label({ Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 36), Text = "", TextColor3 = MUTED, TextSize = 13, Parent = betPanel })
local betBody = new("Frame", { Size = UDim2.new(1, -20, 1, -64), Position = UDim2.fromOffset(10, 58), BackgroundTransparency = 1, Parent = betPanel })
local poolLabel = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 178), Size = UDim2.fromOffset(560, 20), Text = "", TextColor3 = GOLD, FontFace = UIKit.BOLD, TextSize = 15, TextStrokeTransparency = 0.15, Visible = false, Parent = top })

local myMoney = 0
Remotes:WaitForChild("StateUpdate").OnClientEvent:Connect(function(st)
    if st and st.money then myMoney = st.money end
end)

-------------------------------------------------
-- state
-------------------------------------------------
local units, active, mySide, titles = {}, {}, nil, {}
local betState, betPick = nil, { side = nil, pct = 0.25 }
local turn = nil -- { moves, zone, deadline, chosen, barStart, tapped }

-- side A stands on the left of the stage as seen from the battle camera
local function cardFor(side) return side == "A" and cards.left or cards.right end

-- fighters get a fixed camera facing the stage; spectators keep theirs
local camera = workspace.CurrentCamera
local savedCamType = nil
local function battleCamera(on)
    local arena = workspace:FindFirstChild("Arena")
    local stage = arena and arena:FindFirstChild("Stage")
    if on and stage then
        savedCamType = savedCamType or camera.CameraType
        local k = stage.Size.X / 34 -- the Colosseum may be scaled up
        local focus = (stage.CFrame * CFrame.new(0, 2 * k, -3 * k)).Position
        local eye = (stage.CFrame * CFrame.new(0, 17 * k, 18 * k)).Position
        local target = CFrame.lookAt(eye, focus)
        -- hold the shot every frame so nothing else can pull the camera away mid-fight
        RunService:UnbindFromRenderStep("BattleCam")
        RunService:BindToRenderStep("BattleCam", Enum.RenderPriority.Camera.Value + 1, function(dt)
            camera.CameraType = Enum.CameraType.Scriptable
            camera.CFrame = camera.CFrame:Lerp(target, math.min(1, dt * 5))
        end)
    elseif savedCamType then
        RunService:UnbindFromRenderStep("BattleCam")
        camera.CameraType = savedCamType
        savedCamType = nil
    end
end

-- the lab HUD sits where the fighter cards go, so it steps aside during a fight
local function labHud(visible)
    local lab = player.PlayerGui:FindFirstChild("LabUI")
    if lab then lab.Enabled = visible end
end

local function drawCard(side)
    local c = cardFor(side)
    local u = units[active[side]]
    c.owner.Text = (side == mySide and "⭐ YOU · " or "") .. (titles[side] or "")
    c.owner.TextColor3 = side == mySide and GOLD or MUTED
    c.frame:FindFirstChildOfClass("UIStroke").Transparency = side == mySide and 0 or 0.6
    if not u then
        c.name.Text = "-"
        return
    end
    c.name.Text = (u.icon or "") .. " " .. u.name
    c.name.TextColor3 = RARITY_COLOR[u.rarity] or WHITE
    local frac = math.clamp(u.hp / u.maxHp, 0, 1)
    TweenService:Create(c.fill, TweenInfo.new(0.35), { Size = UDim2.fromScale(frac, 1) }):Play()
    c.fill.BackgroundColor3 = frac > 0.5 and UIKit.GREEN or (frac > 0.2 and Color3.fromRGB(255, 200, 70) or UIKit.RED)
    c.hp.Text = ("%d / %d"):format(u.hp, u.maxHp)
    c.status.Text = u.status or ""
    clear(c.pips)
    for _, id in u.team do
        local t = units[id]
        new("Frame", { Size = UDim2.fromOffset(16, 16), BackgroundColor3 = t.hp > 0 and (RARITY_COLOR[t.rarity] or WHITE) or Color3.fromRGB(70, 60, 80), Parent = c.pips }, { corner(8), stroke(WHITE, id == u.uid and 0 or 0.8, 2) })
    end
end

local function redraw()
    drawCard("A")
    drawCard("B")
end

local function setLog(text)
    logText.Text = text or ""
    logBox.BackgroundTransparency = 0
    TweenService:Create(logBox, TweenInfo.new(0.6), { BackgroundTransparency = 0.2 }):Play()
end

-- a fighter that just lost HP flinches (CreatureAnimator watches the HitAt attribute)
local function flinch(uid)
    local arena = workspace:FindFirstChild("Arena")
    local folder = arena and arena:FindFirstChild("BattleUnits")
    if not folder then return end
    for _, m in folder:GetChildren() do
        if m:GetAttribute("Uid") == uid then m:SetAttribute("HitAt", os.clock()) end
    end
end

local function applyHps(hps)
    for uid, v in hps or {} do
        local u = units[uid]
        if u then
            if u.hp and v.hp < u.hp then flinch(uid) end
            u.hp = v.hp
            u.status = v.status
        end
    end
    redraw()
end

local function showGrade(name)
    gradePop.Text = name == "MISS" and "MISS..." or (name .. "!")
    gradePop.TextColor3 = GRADE_COLOR[name] or WHITE
    gradePop.Visible = true
    gradePop.TextSize = 40
    TweenService:Create(gradePop, TweenInfo.new(0.25, Enum.EasingStyle.Back), { TextSize = 72 }):Play()
    task.delay(0.9, function() gradePop.Visible = false end)
end

-------------------------------------------------
-- betting panel
-------------------------------------------------
local function short(n)
    if n >= 1e6 then return ("%.1fM"):format(n / 1e6) elseif n >= 1e4 then return ("%dk"):format(math.floor(n / 1e3)) end
    return UIKit.fmt(n)
end

hideBtn.Activated:Connect(function()
    top.Visible = false
    betPanel.Visible = false
    battleCamera(false)
    local lab = player.PlayerGui:FindFirstChild("LabUI")
    if lab then lab.Enabled = true end
end)

local function renderBets()
    local s = betState
    if not s then
        betPanel.Visible = false
        poolLabel.Visible = false
        return
    end
    poolLabel.Visible = s.count > 0
    poolLabel.Text = ("💰 %d bet%s · $%s on %s · $%s on %s"):format(s.count, s.count == 1 and "" or "s", short(s.pool.A), titles.A or "A", short(s.pool.B), titles.B or "B")
    if not top.Visible or not s.canBet or (not s.open and not s.mine) then
        betPanel.Visible = false
        return
    end
    betPanel.Visible = true
    clear(betBody)
    if s.mine then
        local t = s.mine.side == "A" and titles.A or titles.B
        betSub.Text = s.open and "Locked in. Good luck!" or "Bets are closed. Watch it play out!"
        label({ Size = UDim2.new(1, 0, 1, 0), Text = ("Your bet\n<b>$%s</b> on <b>%s</b>\nat x%.2f\n\nWin pays <font color='#5AE682'><b>$%s</b></font>"):format(UIKit.fmt(s.mine.amount), t, s.mine.odds, UIKit.fmt(math.floor(s.mine.amount * s.mine.odds))), RichText = true, TextSize = 17, Parent = betBody })
        return
    end
    betSub.Text = s.closesIn and ("Round 1 starts in %ds · bets close at round 2"):format(s.closesIn) or "Bets close when round 2 starts"
    for i, side in { "A", "B" } do
        local picked = betPick.side == side
        local b = button({
            Size = UDim2.new(0.5, -4, 0, 70), Position = UDim2.new((i - 1) * 0.5, (i - 1) * 4, 0, 0), Text = "",
            BackgroundColor3 = picked and GOLD or PANEL3, Parent = betBody,
        }, function()
            betPick.side = side
            renderBets()
        end)
        local tc = picked and UIKit.DARKTEXT or WHITE
        label({ Size = UDim2.new(1, -8, 0, 36), Position = UDim2.fromOffset(4, 4), Text = titles[side] or side, TextColor3 = tc, FontFace = UIKit.HEAD, TextScaled = true, Parent = b })
        label({ Size = UDim2.new(1, -8, 0, 24), Position = UDim2.fromOffset(4, 42), Text = ("x%.2f"):format(s.odds[side]), TextColor3 = picked and UIKit.DARKTEXT or GOLD, FontFace = UIKit.HEAD, TextSize = 22, Parent = b })
    end
    for i, pct in { 0.1, 0.25, 0.5 } do
        local picked = betPick.pct == pct
        button({
            Size = UDim2.new(1 / 3, -6, 0, 34), Position = UDim2.new((i - 1) / 3, (i - 1) * 3, 0, 80),
            Text = ("%d%%"):format(pct * 100), TextSize = 18, BackgroundColor3 = picked and Color3.fromRGB(70, 140, 220) or PANEL2, TextColor3 = WHITE, Parent = betBody,
        }, function()
            betPick.pct = pct
            renderBets()
        end)
    end
    local amount = math.min(1000000, math.floor(myMoney * betPick.pct))
    local odds = betPick.side and s.odds[betPick.side]
    button({
        Size = UDim2.new(1, 0, 0, 48), Position = UDim2.fromOffset(0, 124),
        Text = betPick.side and ("BET $%s → win $%s"):format(short(amount), short(math.floor(amount * odds))) or "Pick a side",
        TextSize = 19, BackgroundColor3 = betPick.side and UIKit.GREEN or PANEL3, TextColor3 = betPick.side and UIKit.DARKTEXT or MUTED, Parent = betBody,
    }, function()
        if betPick.side then Request:FireServer("PlaceBet", { side = betPick.side, pct = betPick.pct }) end
    end)
    label({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 176), Text = "In-game cash only. The underdog pays more.", TextColor3 = MUTED, TextSize = 11, Parent = betBody })
end

-------------------------------------------------
-- choosing + timing
-------------------------------------------------
local function closeTiming()
    timing.Visible = false
end

local function tap()
    if not (turn and turn.barStart) or turn.tapped then return end
    turn.tapped = true
    Request:FireServer("BattleTap")
    local g = BattleMoves.grade(BattleMoves.needle(os.clock() - turn.barStart), turn.zone)
    showGrade(g.name)
    task.delay(0.35, closeTiming)
end
tapBtn.Activated:Connect(tap)
UserInputService.InputBegan:Connect(function(input, processed)
    if not timing.Visible then return end
    if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.ButtonA then
        tap()
    elseif (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and not processed then
        tap()
    end
end)

local function choose(i)
    if not turn or turn.chosen then return end
    local mv = turn.moves[i]
    if not mv or mv.cd > 0 then return end
    turn.chosen = i
    picker.Visible = false
    Request:FireServer("BattleMove", i)
    for j, z in zoneFrames do z.Position = UDim2.fromScale(turn.zone, 0) end
    timingTitle.Text = mv.icon .. " " .. mv.name
    timing.Visible = true
    turn.barStart = os.clock()
end

RunService.RenderStepped:Connect(function()
    if turn and timing.Visible and turn.barStart and not turn.tapped then
        local t = os.clock() - turn.barStart
        needle.Position = UDim2.fromScale(BattleMoves.needle(t), 0.5)
        if t > BattleMoves.BAR_TIMEOUT then
            turn.tapped = true
            showGrade("MISS")
            closeTiming()
        end
    end
    if turn and picker.Visible then
        local left = math.max(0, math.ceil(turn.deadline - os.clock()))
        pickTimer.Text = left .. "s"
        pickTimer.TextColor3 = left <= 5 and UIKit.RED or WHITE
        if left <= 0 then picker.Visible = false end
    end
end)

local function showPicker(data)
    turn = { moves = data.moves, zone = data.zone, deadline = os.clock() + (data.time or 20) }
    local u = units[data.uid]
    pickTitle.Text = ("Round %d · What should %s do?"):format(data.round, u and u.name or "your creature")
    clear(grid)
    local n = #data.moves
    gridLayout.CellSize = UDim2.new(1 / n, -9 + 8 / n, 1, 0)
    for i, mv in data.moves do
        local locked = mv.cd > 0
        local b = button({
            Text = "", LayoutOrder = i, AutoButtonColor = not locked,
            BackgroundColor3 = locked and PANEL3 or (mv.kind == "guard" and Color3.fromRGB(70, 140, 220) or GOLD),
            Parent = grid,
        }, function() choose(i) end)
        local tc = locked and MUTED or (mv.kind == "guard" and WHITE or UIKit.DARKTEXT)
        label({ Size = UDim2.new(1, -10, 0, 30), Position = UDim2.fromOffset(5, 4), Text = mv.icon .. " " .. mv.name, TextColor3 = tc, FontFace = UIKit.HEAD, TextScaled = true, Parent = b })
        label({ Size = UDim2.new(1, -10, 0, 14), Position = UDim2.fromOffset(5, 34), Text = string.upper(mv.label or ""), TextColor3 = tc, FontFace = UIKit.BOLD, TextSize = 11, Parent = b })
        label({ Size = UDim2.new(1, -10, 1, -54), Position = UDim2.fromOffset(5, 50), Text = locked and ("Ready in %d turn%s"):format(mv.cd, mv.cd > 1 and "s" or "") or mv.desc, TextColor3 = tc, TextSize = 13, TextYAlignment = Enum.TextYAlignment.Top, Parent = b })
    end
    picker.Visible = true
    closeTiming()
end

-- small screens: taller picker, two rows
local function fitPicker()
    if UIKit.device() == "phone" then
        picker.Size = UDim2.fromOffset(700, 300)
    else
        picker.Size = UDim2.fromOffset(860, 200)
    end
end
fitPicker()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPicker)

-------------------------------------------------
-- events
-------------------------------------------------
Remotes:WaitForChild("BattleEvent").OnClientEvent:Connect(function(kind, data)
    if kind == "tb_start" then
        units, active, turn = {}, {}, nil
        mySide = data.mySide
        titles = { A = data.titleA, B = data.titleB }
        for _, side in { "A", "B" } do
            local team = {}
            for _, u in data[side] do table.insert(team, u.uid) end
            for _, u in data[side] do
                u.side = side
                u.team = team
                u.status = u.status or ""
                units[u.uid] = u
            end
            active[side] = data.active[side]
        end
        spectateTag.Visible = mySide == nil
        result.Visible = false
        top.Visible = true
        betPick = { side = nil, pct = 0.25 }
        betState = data.bets
        renderBets()
        labHud(false)
        -- fighters always get the stage camera; spectators too while they sit near the Colosseum
        local arena = workspace:FindFirstChild("Arena")
        local stage = arena and arena:FindFirstChild("Stage")
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if mySide or (stage and root and (root.Position - stage.Position).Magnitude < 110) then battleCamera(true) end
        hideBtn.Visible = mySide == nil
        redraw()
        setLog(mySide and (data.kind == "wild" and "🌿 Wild brainrots jump out!" or "⚔️ The duel begins!") or ("👀 Watching %s vs %s"):format(data.titleA, data.titleB))
    elseif kind == "tb_bets" then
        betState = data
        renderBets()
    elseif kind == "tb_turn" then
        showPicker(data)
    elseif kind == "tb_wait" then
        if not picker.Visible then setLog(("Round %d · picking moves..."):format(data.round)) end
    elseif kind == "tb_line" then
        picker.Visible = false
        applyHps(data.hps)
        setLog(data.text)
    elseif kind == "tb_enter" then
        active[data.side] = data.uid
        applyHps(data.hps)
        setLog(data.text)
    elseif kind == "tb_end" then
        turn = nil
        betState = nil
        renderBets()
        picker.Visible = false
        closeTiming()
        if data.spectator then
            resultTitle.Text = data.winner ~= "" and ("🏆 " .. data.winner) or "CANCELLED"
            resultTitle.TextColor3 = GOLD
            resultText.Text = data.text or "wins the battle!"
        else
            resultTitle.Text = data.won and "VICTORY!" or "DEFEAT"
            resultTitle.TextColor3 = data.won and UIKit.GREEN or UIKit.RED
            resultText.Text = data.text or ""
        end
        result.Visible = true
        task.delay(2.5, function()
            top.Visible = false
            battleCamera(false)
            labHud(true)
        end)
        task.delay(8, function() result.Visible = false end)
    end
end)
