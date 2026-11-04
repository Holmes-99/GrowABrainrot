--[[
    TradeClient — the 🤝 Trade menu: pick a player, accept/decline requests,
    and the two-sided trade window. Opened by LabClient's Trade button (TradeUI.Toggle).
    Server side: ServerScriptService.TradeSystem.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local TradeEvent = Remotes:WaitForChild("TradeEvent")

local new, label, button, corner, stroke, clear, fmt = UIKit.new, UIKit.label, UIKit.button, UIKit.corner, UIKit.stroke, UIKit.clear, UIKit.fmt
local GOLD, PANEL, PANEL2, PANEL3, WHITE, MUTED = UIKit.GOLD, UIKit.PANEL, UIKit.PANEL2, UIKit.PANEL3, UIKit.WHITE, UIKit.MUTED
local RARITY_COLOR = {}
for r, rgb in Config.RarityColors do RARITY_COLOR[r] = Config.Color(rgb) end
local SLOT_ICON = { Head = "👤", Torso = "👕", Arms = "💪", Legs = "🦵", Weapon = "🗡️" }

local gui = new("ScreenGui", { Name = "TradeUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 15, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
local toggleEvent = new("BindableEvent", { Name = "Toggle", Parent = gui })

local state = nil
Remotes:WaitForChild("StateUpdate").OnClientEvent:Connect(function(st) state = st end)

local function closeButton(parent, fn)
    return button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(46, 46), Text = "X", TextSize = 22, BackgroundColor3 = PANEL3, TextColor3 = WHITE, ZIndex = 5, Parent = parent }, fn)
end

-------------------------------------------------
-- player picker
-------------------------------------------------
local picker = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(400, 440),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.03, Visible = false, Parent = gui,
}, { corner(18), stroke(GOLD, 0.2, 2) })
UIKit.autoScale(picker)
label({ Size = UDim2.new(1, -60, 0, 36), Position = UDim2.fromOffset(18, 12), Text = "🤝 TRADE", TextColor3 = GOLD, FontFace = UIKit.HEAD, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, Parent = picker })
label({ Size = UDim2.new(1, -36, 0, 34), Position = UDim2.fromOffset(18, 48), Text = "Swap parts, creatures and cash with another player. Both of you must press Ready before anything moves.", TextColor3 = MUTED, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = picker })
closeButton(picker, function() picker.Visible = false end)
local pickList = new("ScrollingFrame", {
    Size = UDim2.new(1, -36, 1, -100), Position = UDim2.fromOffset(18, 88), BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = picker,
}, { new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.Name }) })

local function renderPicker()
    clear(pickList)
    local n = 0
    for _, p in Players:GetPlayers() do
        if p ~= player then
            n += 1
            local row = new("Frame", { Name = p.DisplayName, Size = UDim2.new(1, -8, 0, 52), BackgroundColor3 = PANEL2, Parent = pickList }, { corner(12) })
            label({ Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(14, 0), Text = p.DisplayName, FontFace = UIKit.HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
            button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(124, 38), Text = "Send request", TextSize = 16, Parent = row }, function()
                Request:FireServer("TradeRequest", p.UserId)
            end)
        end
    end
    if n == 0 then
        label({ Size = UDim2.new(1, 0, 0, 60), Text = "Nobody else is in this server yet. Invite a friend!", TextColor3 = MUTED, TextSize = 15, Parent = pickList })
    end
end
Players.PlayerAdded:Connect(function() if picker.Visible then renderPicker() end end)
Players.PlayerRemoving:Connect(function() if picker.Visible then task.defer(renderPicker) end end)

-------------------------------------------------
-- incoming request
-------------------------------------------------
local reqCard = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(380, 124),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.03, Visible = false, ZIndex = 10, Parent = gui,
}, { corner(16), stroke(GOLD, 0.1, 3) })
UIKit.autoScale(reqCard)
local reqText = label({ Size = UDim2.new(1, -24, 0, 50), Position = UDim2.fromOffset(12, 8), Text = "", FontFace = UIKit.HEAD, TextSize = 21, ZIndex = 11, Parent = reqCard })
local reqBarBack = new("Frame", { Size = UDim2.new(1, -24, 0, 6), Position = UDim2.fromOffset(12, 60), BackgroundColor3 = PANEL3, ZIndex = 11, Parent = reqCard }, { corner(3) })
local reqBar = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = GOLD, ZIndex = 12, Parent = reqBarBack }, { corner(3) })
local pending = nil -- { from, expires, ttl }
local function respond(accept)
    if not pending then return end
    Request:FireServer("TradeRespond", { from = pending.from, accept = accept })
    pending = nil
    reqCard.Visible = false
end
button({ Position = UDim2.fromOffset(12, 76), Size = UDim2.new(0.5, -18, 0, 38), Text = "✅ Accept", TextSize = 18, BackgroundColor3 = UIKit.GREEN, ZIndex = 11, Parent = reqCard }, function() respond(true) end)
button({ Position = UDim2.new(0.5, 6, 0, 76), Size = UDim2.new(0.5, -18, 0, 38), Text = "Decline", TextSize = 18, BackgroundColor3 = PANEL3, TextColor3 = WHITE, ZIndex = 11, Parent = reqCard }, function() respond(false) end)

-------------------------------------------------
-- trade window
-------------------------------------------------
local win = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(900, 560),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.02, Visible = false, ZIndex = 2, Parent = gui,
}, { corner(18), stroke(GOLD, 0.15, 3) })
UIKit.autoScale(win)
local winTitle = label({ Size = UDim2.new(1, -80, 0, 36), Position = UDim2.fromOffset(18, 10), Text = "", TextColor3 = GOLD, FontFace = UIKit.HEAD, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3, Parent = win })
closeButton(win, function() Request:FireServer("TradeCancel") end)

local function offerColumn(x, title)
    local col = new("Frame", { Position = UDim2.new(x, x == 0 and 18 or 6, 0, 52), Size = UDim2.new(0.5, -24, 0, 236), BackgroundColor3 = PANEL2, ZIndex = 3, Parent = win }, { corner(14) })
    local c = { frame = col }
    c.title = label({ Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 6), Text = title, TextColor3 = WHITE, FontFace = UIKit.HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, Parent = col })
    c.ready = label({ AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(140, 26), Position = UDim2.new(1, -10, 0, 6), Text = "", FontFace = UIKit.HEAD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4, Parent = col })
    c.grid = new("Frame", { Size = UDim2.new(1, -20, 0, 150), Position = UDim2.fromOffset(10, 36), BackgroundTransparency = 1, ZIndex = 4, Parent = col },
        { new("UIGridLayout", { CellSize = UDim2.new(0.25, -6, 0.5, -4), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
    c.cash = label({ Size = UDim2.new(0.6, -10, 0, 22), Position = UDim2.new(0, 10, 1, -32), Text = "", TextColor3 = UIKit.GREEN, FontFace = UIKit.HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, Parent = col })
    c.value = label({ AnchorPoint = Vector2.new(1, 0), Size = UDim2.new(0.4, -10, 0, 22), Position = UDim2.new(1, -10, 1, -32), Text = "", TextColor3 = MUTED, FontFace = UIKit.BOLD, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4, Parent = col })
    return c
end
local mine = offerColumn(0, "YOUR OFFER")
local theirs = offerColumn(0.5, "THEIR OFFER")

-- your stuff
local bag = new("Frame", { Position = UDim2.fromOffset(18, 298), Size = UDim2.new(1, -36, 0, 170), BackgroundColor3 = PANEL2, ZIndex = 3, Parent = win }, { corner(14) })
local bagTab = "Parts"
local tabBtns = {}
local render -- defined below
for i, name in { "Parts", "Creatures" } do
    tabBtns[name] = button({ Position = UDim2.fromOffset(10 + (i - 1) * 118, 8), Size = UDim2.fromOffset(110, 30), Text = name, TextSize = 16, ZIndex = 4, Parent = bag }, function()
        bagTab = name
        render()
    end)
end
label({ Position = UDim2.fromOffset(250, 8), Size = UDim2.new(1, -260, 0, 30), Text = "Tap an item to add it. Tap it in your offer to take it back.", TextColor3 = MUTED, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, Parent = bag })
local bagList = new("ScrollingFrame", {
    Position = UDim2.fromOffset(10, 44), Size = UDim2.new(1, -20, 1, -52), BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 6, ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), ZIndex = 4, Parent = bag,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

-- cash + ready
local cashBox = new("TextBox", {
    Position = UDim2.new(0, 18, 1, -78), Size = UDim2.fromOffset(170, 44), Text = "", PlaceholderText = "Cash to add", ClearTextOnFocus = false,
    BackgroundColor3 = PANEL3, TextColor3 = WHITE, PlaceholderColor3 = MUTED, FontFace = UIKit.HEAD, TextSize = 18, ZIndex = 4, Parent = win,
}, { corner(10) })
button({ Position = UDim2.new(0, 196, 1, -78), Size = UDim2.fromOffset(110, 44), Text = "💵 Set cash", TextSize = 16, BackgroundColor3 = UIKit.GREEN, ZIndex = 4, Parent = win }, function()
    local n = tonumber((cashBox.Text:gsub("[^%d]", ""))) or 0
    Request:FireServer("TradeCash", n)
end)
local status = label({ Position = UDim2.new(0, 318, 1, -82), Size = UDim2.new(1, -560, 0, 52), Text = "", RichText = true, TextSize = 14, FontFace = UIKit.BOLD, ZIndex = 4, Parent = win })
local readyBtn = button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 1, -82), Size = UDim2.fromOffset(220, 52), Text = "READY", TextSize = 24, BackgroundColor3 = UIKit.GREEN, ZIndex = 4, Parent = win })

local view = nil       -- latest "update" from the server
local countdownEnd = nil

local function card(parent, item, order, onClick, highlight)
    local col = RARITY_COLOR[item.rarity] or WHITE
    local b = button({ Size = UDim2.fromOffset(112, 112), LayoutOrder = order, Text = "", BackgroundColor3 = highlight and PANEL3 or PANEL, AutoButtonColor = onClick ~= nil, ZIndex = 5, Parent = parent }, onClick)
    stroke(col, highlight and 0 or 0.35, 2).Parent = b
    local icon = item.kind == "creature" and "🐾" or (SLOT_ICON[item.slot] or "🧩")
    label({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 4), Text = icon .. (item.shiny and "✨" or ""), TextSize = 26, ZIndex = 6, Parent = b })
    label({ Size = UDim2.new(1, -8, 0, 34), Position = UDim2.fromOffset(4, 40), Text = item.name, TextColor3 = col, FontFace = UIKit.HEAD, TextScaled = true, ZIndex = 6, Parent = b })
    label({ Size = UDim2.new(1, -8, 0, 16), Position = UDim2.fromOffset(4, 76), Text = string.upper(item.rarity or ""), TextColor3 = col, FontFace = UIKit.BOLD, TextSize = 11, ZIndex = 6, Parent = b })
    label({ Size = UDim2.new(1, -8, 0, 16), Position = UDim2.fromOffset(4, 92), Text = "≈ $" .. fmt(item.value or 0), TextColor3 = MUTED, TextSize = 11, ZIndex = 6, Parent = b })
    return b
end

local function fillOffer(c, side, clickable)
    clear(c.grid)
    for i, item in side.items do
        local b = card(c.grid, item, i, clickable and function()
            Request:FireServer("TradeOffer", { kind = item.kind, id = item.id, add = false })
        end or nil, false)
        b.Size = UDim2.fromScale(1, 1)
    end
    c.cash.Text = side.cash > 0 and ("+ $" .. fmt(side.cash)) or ""
    c.value.Text = "Value ≈ $" .. fmt(side.value)
    c.ready.Text = side.ready and "✅ READY" or "not ready"
    c.ready.TextColor3 = side.ready and UIKit.GREEN or MUTED
end

function render()
    if not view then return end
    winTitle.Text = "🤝 Trading with " .. view.them.name
    theirs.title.Text = string.upper(view.them.name) .. "'S OFFER"
    fillOffer(mine, view.me, true)
    fillOffer(theirs, view.them, false)
    for name, b in tabBtns do
        b.BackgroundColor3 = name == bagTab and GOLD or PANEL3
        b.TextColor3 = name == bagTab and UIKit.DARKTEXT or WHITE
    end
    -- what you can still add
    clear(bagList)
    local offered = {}
    for _, item in view.me.items do offered[item.kind .. item.id] = true end
    local n = 0
    if state then
        if bagTab == "Parts" then
            for _, p in state.parts or {} do
                if not offered["part" .. p.id] then
                    n += 1
                    local item = { kind = "part", id = p.id, name = (p.shiny and "Shiny " or "") .. Config.PartNames[p.slot][p.family], rarity = p.rarity, slot = p.slot, shiny = p.shiny, value = (Config.PartSell[p.rarity] or 20) * (p.shiny and 2 or 1) }
                    card(bagList, item, -Config.RarityRank[p.rarity] * 1000 + n, function()
                        Request:FireServer("TradeOffer", { kind = "part", id = p.id, add = true })
                    end, false)
                end
            end
        else
            for _, c in state.creatures or {} do
                if not offered["creature" .. c.id] then
                    n += 1
                    card(bagList, { kind = "creature", id = c.id, name = c.name, rarity = c.rarity, value = c.sell }, -Config.RarityRank[c.rarity] * 1000 + n, function()
                        Request:FireServer("TradeOffer", { kind = "creature", id = c.id, add = true })
                    end, false)
                end
            end
        end
    end
    if n == 0 then
        label({ Size = UDim2.fromOffset(400, 100), Text = bagTab == "Parts" and "No parts left to offer." or "No creatures left to offer.", TextColor3 = MUTED, TextSize = 15, ZIndex = 5, Parent = bagList })
    end

    -- status + warnings
    countdownEnd = view.countdown and (os.clock() + view.countdown) or nil
    local lines = {}
    local give, get = view.me.value, view.them.value
    if give > 0 and give > get * 2 + 500 then
        table.insert(lines, ("<font color='#FF6B6B'>⚠️ You're giving about $%s more than you get.</font>"):format(fmt(give - get)))
    end
    if view.me.ready and not view.them.ready then table.insert(lines, "Waiting for " .. view.them.name .. " to press Ready...") end
    if not view.me.ready and view.them.ready then table.insert(lines, view.them.name .. " is ready. Check their offer, then press Ready.") end
    status.Text = table.concat(lines, "\n")
    readyBtn.Text = view.me.ready and "UNREADY" or "READY"
    readyBtn.BackgroundColor3 = view.me.ready and PANEL3 or UIKit.GREEN
    readyBtn.TextColor3 = view.me.ready and WHITE or UIKit.DARKTEXT
end

readyBtn.Activated:Connect(function()
    if view then Request:FireServer("TradeReady", not view.me.ready) end
end)

RunService.RenderStepped:Connect(function()
    if pending then
        local left = pending.expires - os.clock()
        reqBar.Size = UDim2.fromScale(math.clamp(left / pending.ttl, 0, 1), 1)
        if left <= 0 then pending = nil reqCard.Visible = false end
    end
    if win.Visible and countdownEnd then
        local left = math.max(0, math.ceil(countdownEnd - os.clock()))
        status.Text = ("<font color='#5AE682'>Both ready! Trading in %d...</font>\nAny change cancels it."):format(left)
    end
end)

-------------------------------------------------
-- events
-------------------------------------------------
toggleEvent.Event:Connect(function()
    if win.Visible then return end
    picker.Visible = not picker.Visible
    if picker.Visible then renderPicker() end
end)

TradeEvent.OnClientEvent:Connect(function(kind, data)
    if kind == "request" then
        pending = { from = data.from, expires = os.clock() + data.ttl, ttl = data.ttl }
        reqText.Text = ("🤝 %s wants to trade!"):format(data.name)
        reqCard.Visible = true
    elseif kind == "open" then
        picker.Visible = false
        reqCard.Visible = false
        pending = nil
        bagTab = "Parts"
        cashBox.Text = ""
        win.Visible = true
    elseif kind == "update" then
        view = data
        win.Visible = true
        render()
    elseif kind == "closed" then
        win.Visible = false
        view, countdownEnd = nil, nil
    end
end)

-- refresh the bag when your inventory changes mid-trade
Remotes.StateUpdate.OnClientEvent:Connect(function()
    if win.Visible then render() end
end)
