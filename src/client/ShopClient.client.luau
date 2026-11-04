--[[
    ShopClient — the 💎 Robux shop, the daily reward calendar and the
    active-boost timers at the top of the screen.
    Opened by LabClient's 💎 Shop button (ShopUI.Toggle) or by the server (OpenUI "shop"/"daily").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")

local new, label, button, corner, stroke, pad = UIKit.new, UIKit.label, UIKit.button, UIKit.corner, UIKit.stroke, UIKit.pad
local GOLD, PANEL, PANEL2, PANEL3, WHITE, MUTED = UIKit.GOLD, UIKit.PANEL, UIKit.PANEL2, UIKit.PANEL3, UIKit.WHITE, UIKit.MUTED

local state = nil
local tab = "Passes"
local clockOffset = 0 -- server os.time() - local os.time()

local gui = new("ScreenGui", { Name = "ShopUI", ResetOnSpawn = false, DisplayOrder = 6, Parent = player:WaitForChild("PlayerGui") })
local toggleEvent = new("BindableEvent", { Name = "Toggle", Parent = gui })
local dailyEvent = new("BindableEvent", { Name = "Daily", Parent = gui })

-------------------------------------------------
-- Shop panel
-------------------------------------------------
local shop = new("Frame", {
    Name = "Shop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.92, 0, 0.86, 0),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.03, Visible = false, Parent = gui,
}, { corner(18), stroke(GOLD, 0.2, 2), new("UISizeConstraint", { MaxSize = Vector2.new(860, 600) }) })
UIKit.autoScale(shop)
label({ Size = UDim2.new(1, -80, 0, 40), Position = UDim2.fromOffset(20, 10), Text = "💎 SHOP", TextColor3 = GOLD, FontFace = UIKit.HEAD, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, Parent = shop })
button({ Size = UDim2.fromOffset(48, 48), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Text = "X", TextSize = 24, BackgroundColor3 = PANEL2, TextColor3 = WHITE, Parent = shop }, function()
    shop.Visible = false
end)
local tabsRow = new("Frame", { Size = UDim2.new(1, -40, 0, 36), Position = UDim2.fromOffset(20, 56), BackgroundTransparency = 1, Parent = shop },
    { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }) })
local body = new("ScrollingFrame", {
    Size = UDim2.new(1, -40, 1, -110), Position = UDim2.fromOffset(20, 100), BackgroundTransparency = 1, BorderSizePixel = 0,
    AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarThickness = 6, ScrollBarImageColor3 = GOLD, Parent = shop,
}, { new("UIGridLayout", { CellSize = UDim2.new(0.5, -8, 0, 128), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }) })

local function robuxButton(parent, text, owned, onClick)
    local b = button({
        Size = UDim2.fromOffset(116, 40), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -10),
        Text = text, TextSize = 18, BackgroundColor3 = owned and PANEL3 or UIKit.ROBUX, TextColor3 = WHITE, Parent = parent,
    }, onClick)
    b.AutoButtonColor = not owned
    return b
end

local function card(order, icon, name, desc, accent)
    local f = new("Frame", { BackgroundColor3 = PANEL2, LayoutOrder = order, Parent = body }, { corner(14), stroke(accent or GOLD, 0.5, 2) })
    label({ Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(10, 10), Text = icon, TextSize = 44, Parent = f })
    label({ Size = UDim2.new(1, -90, 0, 26), Position = UDim2.fromOffset(80, 10), Text = name, TextColor3 = accent or GOLD, FontFace = UIKit.HEAD, TextSize = 21, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, Parent = f },
        { new("UITextSizeConstraint", { MaxTextSize = 21 }) })
    label({ Size = UDim2.new(1, -90, 0, 54), Position = UDim2.fromOffset(80, 36), Text = desc, TextSize = 13, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextScaled = true, Parent = f },
        { new("UITextSizeConstraint", { MaxTextSize = 13 }) })
    return f
end

local function render()
    UIKit.clear(tabsRow)
    for _, t in { "Passes", "Boosts & Items", "Cash" } do
        button({ Size = UDim2.fromOffset(t == "Boosts & Items" and 160 or 110, 34), Text = t, TextSize = 17,
            BackgroundColor3 = t == tab and GOLD or PANEL3, TextColor3 = t == tab and UIKit.DARKTEXT or WHITE, Parent = tabsRow }, function()
            tab = t
            render()
        end)
    end
    UIKit.clear(body)
    local passes = state and state.passes or {}
    if tab == "Passes" then
        for i, p in ShopConfig.Passes do
            local owned = passes[p.key] == true
            local f = card(i, p.icon, p.name, p.desc, p.key == "VIP" and Color3.fromRGB(255, 200, 60) or nil)
            robuxButton(f, owned and "OWNED ✅" or ("R$ " .. p.robux), owned, function()
                if not owned then Request:FireServer("BuyPass", p.key) end
            end)
        end
    else
        local i = 0
        for _, key in ShopConfig.ProductOrder do
            local p = ShopConfig.product(key)
            local isCash = p.kind == "cash"
            if (tab == "Cash") == isCash then
                i += 1
                local desc = p.desc
                if isCash and state then
                    local amount = math.floor(math.max(p.base, (state.income or 0) / 10 * 60 * p.minutes))
                    desc = ("You get: $%s\n"):format(UIKit.fmt(amount)) .. desc
                end
                if p.kind == "boost" and state and state.boosts and state.boosts[p.boost] then
                    local left = state.boosts[p.boost] - (os.time() + clockOffset)
                    if left > 0 then desc = ("ACTIVE · %d:%02d left\n"):format(left // 60, left % 60) .. desc end
                end
                local f = card(i, p.icon, p.name, desc, isCash and UIKit.GREEN or nil)
                robuxButton(f, "R$ " .. p.robux, false, function()
                    Request:FireServer("BuyProduct", p.key)
                end)
            end
        end
    end
end

local function openShop(which)
    if which then tab = which end
    render()
    shop.Visible = true
end

-------------------------------------------------
-- Daily rewards
-------------------------------------------------
local daily = new("Frame", {
    Name = "Daily", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(700, 300),
    BackgroundColor3 = PANEL, Visible = false, Parent = gui,
}, { corner(18), stroke(GOLD, 0.2, 2) })
UIKit.autoScale(daily)
label({ Size = UDim2.new(1, -80, 0, 40), Position = UDim2.fromOffset(20, 10), Text = "🎁 DAILY REWARDS", TextColor3 = GOLD, FontFace = UIKit.HEAD, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, Parent = daily })
button({ Size = UDim2.fromOffset(48, 48), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Text = "X", TextSize = 24, BackgroundColor3 = PANEL2, TextColor3 = WHITE, Parent = daily }, function()
    daily.Visible = false
end)
local dailySub = label({ Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(20, 50), Text = "", TextSize = 14, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Parent = daily })
local days = new("Frame", { Size = UDim2.new(1, -40, 0, 130), Position = UDim2.fromOffset(20, 80), BackgroundTransparency = 1, Parent = daily },
    { new("UIGridLayout", { CellSize = UDim2.new(1 / 7, -8, 1, 0), CellPadding = UDim2.fromOffset(8, 0), SortOrder = Enum.SortOrder.LayoutOrder }) })
local claimBtn = button({ Size = UDim2.fromOffset(220, 48), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Text = "CLAIM", TextSize = 24, Parent = daily }, function()
    Request:FireServer("ClaimDaily")
end)

local function renderDaily()
    UIKit.clear(days)
    local d = state and state.daily or { claimable = false, streak = 1 }
    local vip = state and state.passes and state.passes.VIP
    dailySub.Text = "Log in every day to keep your streak. Miss a day and it starts over." .. (vip and "  ⭐ VIP: double rewards!" or "")
    for i, r in ShopConfig.Daily do
        local done = i < d.streak or (i == d.streak and not d.claimable)
        local today = d.claimable and i == d.streak
        local f = new("Frame", { BackgroundColor3 = today and Color3.fromRGB(80, 60, 20) or PANEL2, LayoutOrder = i, Parent = days },
            { corner(12), stroke(today and GOLD or PANEL3, today and 0 or 0.4, today and 3 or 2) })
        label({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 6), Text = "Day " .. i, TextColor3 = today and GOLD or MUTED, FontFace = UIKit.HEAD, TextSize = 16, Parent = f })
        label({ Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 30), Text = done and "✅" or r.icon, TextSize = 34, Parent = f })
        label({ Size = UDim2.new(1, -6, 0, 40), Position = UDim2.fromOffset(3, 78), Text = r.text, TextSize = 12, FontFace = UIKit.BOLD, TextScaled = true, Parent = f },
            { new("UITextSizeConstraint", { MaxTextSize = 13 }) })
    end
    claimBtn.Text = d.claimable and ("CLAIM DAY " .. d.streak) or "COME BACK TOMORROW"
    claimBtn.BackgroundColor3 = d.claimable and GOLD or PANEL3
    claimBtn.TextColor3 = d.claimable and UIKit.DARKTEXT or MUTED
end

-------------------------------------------------
-- active boost chips (top middle)
-------------------------------------------------
local chips = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X,
    BackgroundTransparency = 1, Parent = gui,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })
UIKit.autoScale(chips)
local BOOST_LABEL = { Cash = "💸 2x Cash", Luck = "🍀 Lucky", FastBrew = "⏩ Fast Brew" }

local function renderChips()
    UIKit.clear(chips)
    if not (state and state.boosts) then return end
    local now = os.time() + clockOffset
    for k, untilT in state.boosts do
        local left = untilT - now
        if left > 0 then
            label({ Size = UDim2.fromOffset(150, 28), Text = ("%s %d:%02d"):format(BOOST_LABEL[k] or k, left // 60, left % 60), TextSize = 15, FontFace = UIKit.BOLD,
                BackgroundTransparency = 0.15, BackgroundColor3 = PANEL, TextColor3 = UIKit.GREEN, Parent = chips }, { corner(14), stroke(UIKit.GREEN, 0.4, 1.5) })
        end
    end
end

task.spawn(function()
    while true do
        task.wait(1)
        renderChips()
    end
end)

-------------------------------------------------
-- wiring
-------------------------------------------------
Remotes:WaitForChild("StateUpdate").OnClientEvent:Connect(function(s)
    state = s
    if s.serverTime then clockOffset = s.serverTime - os.time() end
    if shop.Visible then render() end
    if daily.Visible then renderDaily() end
end)

Remotes:WaitForChild("OpenUI").OnClientEvent:Connect(function(what)
    if what == "shop" then
        openShop()
    elseif what == "daily" then
        renderDaily()
        daily.Visible = true
    end
end)

toggleEvent.Event:Connect(function(which)
    if shop.Visible then shop.Visible = false else openShop(which) end
end)
dailyEvent.Event:Connect(function()
    renderDaily()
    daily.Visible = not daily.Visible
end)
