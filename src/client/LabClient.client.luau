--[[
    LabClient.client.lua — Grow a Brainrot (parts edition)
    HUD, toasts, Dr. Mixalot dialogue (skippable), reveal cards, inventory (parts + creatures),
    Assembly Lab, The Forge, Black Market, brewing guide, battle menu + battle viewer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local CreatureBuilder = require(ReplicatedStorage:WaitForChild("CreatureBuilder"))
local PartsLogic = require(ReplicatedStorage:WaitForChild("PartsLogic"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")

local state = nil

-------------------------------------------------
-- Style
-------------------------------------------------
local HEAD = Font.fromEnum(Enum.Font.FredokaOne)
local BODY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
local BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local GOLD = Color3.fromRGB(255, 205, 90)
local PANEL = Color3.fromRGB(22, 17, 32)
local PANEL2 = Color3.fromRGB(36, 28, 52)
local PANEL3 = Color3.fromRGB(52, 42, 72)
local WHITE = Color3.fromRGB(245, 240, 255)
local MUTED = Color3.fromRGB(170, 160, 190)
local DARKTEXT = Color3.fromRGB(30, 20, 10)
local KIND_COLOR = {
    good = Color3.fromRGB(90, 230, 130),
    bad = Color3.fromRGB(255, 95, 95),
    info = Color3.fromRGB(210, 205, 230),
    rare = GOLD,
}
local RARITY_COLOR = {}
for r, rgb in Config.RarityColors do
    RARITY_COLOR[r] = Config.Color(rgb)
end
local SLOT_ICON = { Head = "👤", Torso = "👕", Arms = "💪", Legs = "🦵", Weapon = "🗡️", Any = "🎲" }

local function fmt(n)
    n = math.floor(n or 0)
    local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if s:sub(1, 1) == "," then s = s:sub(2) end
    return (n < 0 and "-" or "") .. s
end

local function partName(p)
    return (p.shiny and "Shiny " or "") .. Config.PartNames[p.slot][p.family]
end

local function new(class, props, children)
    local inst = Instance.new(class)
    for k, v in props do
        if k ~= "Parent" then inst[k] = v end
    end
    for _, c in children or {} do
        c.Parent = inst
    end
    inst.Parent = props.Parent
    return inst
end

local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 12) }) end
local function stroke(color, t, th)
    return new("UIStroke", { Color = color or GOLD, Transparency = t or 0.4, Thickness = th or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function pad(p) return new("UIPadding", { PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p), PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p) }) end

local function label(props, children)
    props.BackgroundTransparency = props.BackgroundTransparency or 1
    props.TextColor3 = props.TextColor3 or WHITE
    props.FontFace = props.FontFace or BODY
    props.TextWrapped = true
    return new("TextLabel", props, children)
end

local function button(props, onClick)
    props.BackgroundColor3 = props.BackgroundColor3 or GOLD
    props.TextColor3 = props.TextColor3 or DARKTEXT
    props.FontFace = props.FontFace or HEAD
    props.AutoButtonColor = true
    local b = new("TextButton", props, { corner(10) })
    if onClick then b.Activated:Connect(onClick) end
    return b
end

local function clear(frame)
    for _, c in frame:GetChildren() do
        if c:IsA("GuiObject") then c:Destroy() end
    end
end

local gui = new("ScreenGui", {
    Name = "LabUI", ResetOnSpawn = false, IgnoreGuiInset = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui"),
})

local openPanels = {}
local function closeAll(except)
    for _, p in openPanels do
        if p ~= except then p.Visible = false end
    end
end

-- a centered panel with a title and a close button; returns panel, title label, body frame
local function panel(name, size, z, maxSize)
    z = z or 5
    local f = new("Frame", {
        Name = name, Size = size, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        BackgroundColor3 = PANEL, BackgroundTransparency = 0.05, Visible = false, ZIndex = z, Parent = gui,
    }, { corner(18), stroke(GOLD, 0.3, 2), new("UISizeConstraint", { MaxSize = maxSize or Vector2.new(900, 620) }) })
    local title = label({ Size = UDim2.new(1, -80, 0, 40), Position = UDim2.fromOffset(20, 10), Text = name:upper(), TextColor3 = GOLD, FontFace = HEAD, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = z + 1, Parent = f })
    button({ Size = UDim2.fromOffset(48, 48), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Text = "X", TextSize = 24, BackgroundColor3 = PANEL2, TextColor3 = WHITE, ZIndex = z + 2, Parent = f }, function() f.Visible = false end)
    local body = new("Frame", { Name = "Body", Size = UDim2.new(1, -32, 1, -66), Position = UDim2.fromOffset(16, 56), BackgroundTransparency = 1, ZIndex = z + 1, Parent = f })
    table.insert(openPanels, f)
    return f, title, body
end

local function scroller(parent, z, layout)
    return new("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = GOLD, ZIndex = z, Parent = parent,
    }, { layout })
end

-------------------------------------------------
-- Toasts
-------------------------------------------------
local toastHolder = new("Frame", {
    Name = "Toasts", Size = UDim2.new(0, 460, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 70), BackgroundTransparency = 1, ZIndex = 50, Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }) })
local toastN = 0
local lastToast = {} -- text -> time shown, so repeats within a few seconds are dropped
local MAX_TOASTS = 2

local function toast(text, kind)
    local now = os.clock()
    if lastToast[text] and now - lastToast[text] < 5 then return end
    lastToast[text] = now
    toastN += 1
    local col = KIND_COLOR[kind] or KIND_COLOR.info
    local t = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = PANEL,
        BackgroundTransparency = 0.12, LayoutOrder = toastN, ZIndex = 50, Parent = toastHolder,
    }, { corner(10), stroke(col, 0.2, 2), pad(10) })
    local l = label({
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = text, TextColor3 = col,
        TextSize = 15, FontFace = BOLD, ZIndex = 51, Parent = t,
    })
    l.TextTransparency = 1
    TweenService:Create(l, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
    task.delay(kind == "rare" and 4.5 or 3, function()
        TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
        TweenService:Create(t, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
        task.wait(0.45)
        t:Destroy()
    end)
    local frames = {}
    for _, c in toastHolder:GetChildren() do
        if c:IsA("Frame") then table.insert(frames, c) end
    end
    if #frames > MAX_TOASTS then
        table.sort(frames, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
        for i = 1, #frames - MAX_TOASTS do frames[i]:Destroy() end
    end
end

Remotes:WaitForChild("Notify").OnClientEvent:Connect(toast)

-------------------------------------------------
-- 3D previews (creatures and single parts)
-------------------------------------------------
local function viewport(parent, parts, opts, z)
    local vp = new("ViewportFrame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = Color3.fromRGB(170, 160, 190),
        LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1), ZIndex = z or 7, Parent = parent,
    })
    local world = new("WorldModel", { Parent = vp })
    local ok, model = pcall(CreatureBuilder.BuildFromParts, parts, opts or {})
    if not ok or #model:GetChildren() <= 1 then return vp end
    model:PivotTo(CFrame.new())
    model.Parent = world
    local cf, size = model:GetBoundingBox()
    local radius = math.max(size.X, size.Y, size.Z) * 0.5
    local dist = radius / math.tan(math.rad(20)) + 1
    local cam = new("Camera", { FieldOfView = 40, Parent = vp })
    local focus = cf.Position
    cam.CFrame = CFrame.lookAt(focus + Vector3.new(dist * 0.35, dist * 0.2, -dist), focus)
    vp.CurrentCamera = cam
    return vp, model, focus
end

local function partViewport(parent, p, z)
    return viewport(parent, { [p.slot] = p }, { only = p.slot }, z)
end

local function spin(vp, model, focus)
    if not model then return end
    local a = 0
    local conn
    conn = RunService.RenderStepped:Connect(function(dt)
        if not vp.Parent or not model.Parent then conn:Disconnect() return end
        if not vp.Visible or not vp:FindFirstAncestorOfClass("ScreenGui") then return end
        a += dt * 0.8
        model:PivotTo(CFrame.new(focus) * CFrame.Angles(0, a, 0) * CFrame.new(-focus))
    end)
end

-- small coloured card for a part
local function partCard(parent, p, order, z, buttons)
    local col = RARITY_COLOR[p.rarity] or WHITE
    local card = new("Frame", { BackgroundColor3 = PANEL2, LayoutOrder = order, ZIndex = z, Parent = parent }, { corner(10), stroke(col, 0.15, 2) })
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 78), BackgroundTransparency = 1, ZIndex = z, Parent = card })
    partViewport(holder, p, z + 1)
    label({ Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(4, 4), Text = SLOT_ICON[p.slot], TextScaled = true, ZIndex = z + 2, Parent = card })
    label({ Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 78), Text = partName(p), TextColor3 = col, FontFace = HEAD, TextScaled = true, ZIndex = z + 1, Parent = card })
    local perk = Config.PartPerks[p.slot][p.family]
    label({ Size = UDim2.new(1, -8, 0, 14), Position = UDim2.fromOffset(4, 96), Text = p.rarity:upper() .. " · " .. perk.icon .. " " .. perk.title, TextColor3 = MUTED, FontFace = BOLD, TextScaled = true, ZIndex = z + 1, Parent = card })
    for i, b in buttons or {} do
        button({ Size = UDim2.new(1, -8, 0, 22), Position = UDim2.new(0, 4, 1, -26 * i), Text = b[1], TextSize = 14, ZIndex = z + 3, BackgroundColor3 = b[3] or GOLD, Parent = card }, b[2])
    end
    return card
end

-------------------------------------------------
-- HUD
-------------------------------------------------
local hud = new("Frame", {
    Name = "HUD", Size = UDim2.fromOffset(300, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.new(0, 14, 0, 14),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.15, Parent = gui,
}, { corner(14), stroke(GOLD, 0.45, 2), pad(12), new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local moneyLabel = label({ Size = UDim2.new(1, 0, 0, 34), Text = "$0", TextColor3 = GOLD, FontFace = HEAD, TextSize = 32, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Parent = hud })
local incomeLabel = label({ Size = UDim2.new(1, 0, 0, 18), Text = "", TextColor3 = KIND_COLOR.good, FontFace = BOLD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, Parent = hud })
local statsLabel = label({ Size = UDim2.new(1, 0, 0, 16), Text = "", TextColor3 = MUTED, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3, Parent = hud })

local satchelTitle = label({ Size = UDim2.new(1, 0, 0, 18), Text = "SATCHEL", TextColor3 = MUTED, FontFace = HEAD, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 4, Parent = hud })
local satchel = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 5, Parent = hud },
    { new("UIGridLayout", { CellSize = UDim2.fromOffset(52, 24), CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })
local emptyBtn = button({ Size = UDim2.new(1, 0, 0, 26), Text = "Empty satchel (50% refund)", TextSize = 14, BackgroundColor3 = PANEL2, TextColor3 = MUTED, LayoutOrder = 6, Parent = hud }, function()
    Request:FireServer("EmptySatchel")
end)

local objective = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = PANEL2, LayoutOrder = 7, Parent = hud }, { corner(10), pad(8) })
local objectiveLabel = label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = "", TextColor3 = WHITE, FontFace = BOLD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, RichText = true, Parent = objective })

local menu = new("Frame", {
    Size = UDim2.fromOffset(150, 0), AutomaticSize = Enum.AutomaticSize.Y, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
    BackgroundTransparency = 1, Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

-------------------------------------------------
-- Dialogue: Dr. Mixalot
-------------------------------------------------
local DIALOGUE = {
    intro = {
        pages = {
            "Ah, fresh blood! Welcome to Grow a Brainrot. I'm Dr. Mixalot, and that tower behind me is Maison Mixalot, the finest elixir house in Ohio.",
            "You don't BUY creatures here. You BUILD them. Brew elixirs into part capsules, then snap a head, torso, arms, legs and a weapon together.",
        },
        choices = { { "How do I get parts?", "brew" }, { "How do I build?", "build" }, { "What do parts do?", "perks" }, { "Battles?", "battle" }, { "Let me cook", "bye" } },
    },
    brew = {
        pages = {
            "Cop at least two elixirs, then press Brew at YOUR cauldron. Your name is on your lab's gate.",
            "Each elixir leans toward a slot. Frostmind Tonic and Ember Jaw: heads. Liquid Gold and Halo Mist: torsos. Crimson Grip: arms. Voidwalk: legs. Venomfang: weapons. Dreamcandy Syrup: anything! The family (the look and the power) also comes from the elixirs you pour. Want a sure thing? Grab a Body Draught at the 🧬 Body Bar next to the shop. It locks your next brew to that body part.",
            "Want rarer parts? Pour more expensive elixirs. Every $600 in one brew is an extra rarity roll, and the best roll wins. A Legendary capsule takes a while to grow, so check back.",
        },
        choices = { { "How do I build?", "build" }, { "What do parts do?", "perks" }, { "Got it", "bye" } },
    },
    build = {
        pages = {
            "Open a ready capsule and the part goes into your bag. Then head to the Assembly Lab on Market Street, east of my shop.",
            "Pick a part for each slot. Head and Torso are required; arms, legs and a weapon make it way stronger. Press BUILD and your creature moves into your lab.",
            "Got three of the same part and rarity? The Forge fuses them into one of the next rarity. The Black Market sells rare parts, and stock rotates every 5 minutes.",
        },
        choices = { { "What do parts do?", "perks" }, { "Battles?", "battle" }, { "Got it", "bye" } },
    },
    perks = {
        pages = {
            "HEADS give the big lab quirk. Boccone Gnam raids rival labs and steals cash. Teschio Vortello does it in disguise. Testa Ghiacciolo earns +50%. Corona Bling Bling gets you shop discounts. Gremlo Capoccia hypes your whole lab.",
            "TORSOS: Cuore Spettrolo blocks raids, Pancia Frigorina speeds up brewing, Corazza Crimsona gives you extra rarity rolls. ARMS, LEGS and WEAPONS are all about battle: crits, ambushes, splash, charm and life-steal.",
            "Three parts of one family give a set bonus. All five? That's a PURE creature: +50% everything and a fancy aura.",
        },
        choices = { { "How do I get parts?", "brew" }, { "Battles?", "battle" }, { "Got it", "bye" } },
    },
    battle = {
        pages = {
            "Step into the Battle Portal in the hub (you need at least one creature) and you'll land at the Ohio Colosseum. Your three strongest creatures fight one at a time, turn by turn.",
            "Every part gives a move: Heads have a signature move, Arms strike, Legs go first, Weapons hit hardest and Torsos guard or heal. Pick a move, then STOP the needle in the gold zone for a PERFECT hit (x1.5).",
            "Fight WILD brainrots on the green pad for cash, trophies and part drops. Or press Battle and queue for RANKED: you'll be matched and teleported against another player. Winner takes a cash bounty and trophies.",
        },
        choices = { { "How do I build?", "build" }, { "Got it", "bye" } },
    },
    bye = {
        pages = { "Go cook, apprentice. If you forget anything, I'm right here. Press Talk, or Help." },
        choices = {},
    },
}

local dlg = new("Frame", {
    Name = "Dialogue", Size = UDim2.new(0.62, 0, 0, 250), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.05, Visible = false, ZIndex = 20, Parent = gui,
}, { corner(18), stroke(GOLD, 0.2, 3), new("UISizeConstraint", { MaxSize = Vector2.new(820, 260), MinSize = Vector2.new(460, 250) }) })
table.insert(openPanels, dlg)

local portrait = new("Frame", { Size = UDim2.fromOffset(150, 150), Position = UDim2.fromOffset(16, -40), BackgroundColor3 = PANEL2, ZIndex = 21, Parent = dlg }, { corner(75), stroke(GOLD, 0, 3) })
new("ImageLabel", { Size = UDim2.fromScale(0.86, 0.86), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), BackgroundTransparency = 1, Image = "rbxassetid://73880419657932", ScaleType = Enum.ScaleType.Fit, ZIndex = 22, Parent = portrait })
label({ Size = UDim2.new(1, -290, 0, 30), Position = UDim2.fromOffset(180, 10), Text = "DR. MIXALOT", TextScaled = true, TextColor3 = GOLD, FontFace = HEAD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21, Parent = dlg })
local dlgText = label({
    Size = UDim2.new(1, -200, 1, -108), Position = UDim2.fromOffset(180, 44), Text = "", TextScaled = true, FontFace = BODY,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 21, Parent = dlg,
}, { new("UITextSizeConstraint", { MaxTextSize = 19, MinTextSize = 10 }) })
local dlgChoices = new("Frame", { Size = UDim2.new(1, -200, 0, 36), Position = UDim2.new(0, 180, 1, -50), BackgroundTransparency = 1, ZIndex = 21, Parent = dlg },
    { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Wraps = true, SortOrder = Enum.SortOrder.LayoutOrder }) })
local skipBtn = button({ Size = UDim2.fromOffset(90, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Text = "SKIP »", TextSize = 16, BackgroundColor3 = PANEL2, TextColor3 = MUTED, ZIndex = 22, Parent = dlg })

local dlgNode, dlgPage, typing, typeToken = nil, 1, false, 0

local function closeDialogue()
    typeToken += 1
    dlg.Visible = false
end
skipBtn.Activated:Connect(closeDialogue)

local showPage

local function showChoices()
    clear(dlgChoices)
    local node = DIALOGUE[dlgNode]
    if dlgPage < #node.pages then
        button({ Size = UDim2.fromOffset(120, 34), Text = "Next ▸", TextSize = 17, ZIndex = 22, Parent = dlgChoices }, function()
            dlgPage += 1
            showPage()
        end)
    elseif #node.choices == 0 then
        button({ Size = UDim2.fromOffset(120, 34), Text = "Bet.", TextSize = 17, ZIndex = 22, Parent = dlgChoices }, closeDialogue)
    else
        for i, ch in node.choices do
            local bye = ch[2] == "bye"
            local b = button({ Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Text = "  " .. ch[1] .. "  ", TextSize = 14, LayoutOrder = i, ZIndex = 22,
                BackgroundColor3 = bye and PANEL2 or GOLD, TextColor3 = bye and WHITE or DARKTEXT, Parent = dlgChoices }, function()
                dlgNode, dlgPage = ch[2], 1
                showPage()
            end)
            b.FontFace = BOLD
        end
    end
end

function showPage()
    clear(dlgChoices)
    typeToken += 1
    local token = typeToken
    local text = DIALOGUE[dlgNode].pages[dlgPage]
    dlgText.Text = text
    dlgText.MaxVisibleGraphemes = 0
    typing = true
    task.spawn(function()
        local n = utf8.len(text) or #text
        for i = 1, n, 2 do
            if token ~= typeToken then return end
            dlgText.MaxVisibleGraphemes = i
            task.wait(0.012)
        end
        if token ~= typeToken then return end
        dlgText.MaxVisibleGraphemes = -1
        typing = false
        showChoices()
    end)
end

local clickCatcher = new("TextButton", { Size = UDim2.new(1, -200, 1, -108), Position = UDim2.fromOffset(180, 44), BackgroundTransparency = 1, Text = "", ZIndex = 23, Parent = dlg })
clickCatcher.Activated:Connect(function()
    if typing then
        typeToken += 1
        typing = false
        dlgText.MaxVisibleGraphemes = -1
        showChoices()
    end
end)

local function openDialogue(node)
    closeAll(dlg)
    dlgNode, dlgPage = node or "intro", 1
    dlg.Visible = true
    showPage()
end

-------------------------------------------------
-- Inventory (creatures + parts), also the Trading Post sell screen
-------------------------------------------------
local inv, invTitle, invBody = panel("Inventory", UDim2.fromScale(0.74, 0.76))
local invTab, sellMode = "Creatures", false
local invTabs = new("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, ZIndex = 7, Parent = invBody },
    { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }) })
local invSub = label({ Size = UDim2.new(1, -260, 0, 38), Position = UDim2.fromOffset(260, 0), Text = "", TextColor3 = MUTED, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7, Parent = invBody })
local invListHolder = new("Frame", { Size = UDim2.new(1, 0, 1, -40), Position = UDim2.fromOffset(0, 40), BackgroundTransparency = 1, ZIndex = 6, Parent = invBody })
local invGrid = new("UIGridLayout", { CellSize = UDim2.fromOffset(176, 236), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder })
local invList = scroller(invListHolder, 6, invGrid)
local renderInventory

local tabButtons = {}
for i, t in { "Creatures", "Parts" } do
    tabButtons[t] = button({ Size = UDim2.fromOffset(120, 38), Text = t, TextSize = 18, LayoutOrder = i, ZIndex = 8, Parent = invTabs }, function()
        invTab = t
        renderInventory()
    end)
end

local function perkLines(perks)
    local lines = {}
    for _, pk in perks do
        table.insert(lines, pk.icon .. " " .. pk.title)
    end
    return table.concat(lines, "  ")
end

local function creatureCard(parent, c, order, z, buttons)
    local col = RARITY_COLOR[c.rarity] or WHITE
    local card = new("Frame", { BackgroundColor3 = PANEL2, LayoutOrder = order, ZIndex = z, Parent = parent }, { corner(12), stroke(col, 0.15, 2) })
    local vpHolder = new("Frame", { Size = UDim2.new(1, 0, 0, 104), BackgroundTransparency = 1, ZIndex = z, Parent = card })
    viewport(vpHolder, c.parts, {}, z + 1)
    label({ Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(6, 104), Text = c.name, TextColor3 = col, FontFace = HEAD, TextScaled = true, ZIndex = z + 1, Parent = card })
    label({ Size = UDim2.new(1, -12, 0, 14), Position = UDim2.fromOffset(6, 126), Text = c.rarity:upper() .. (c.setCount >= 3 and (" · %d-SET"):format(c.setCount) or "") .. ((c.growth or 0) > 0 and (" · SIZE %d"):format(c.growth) or ""), TextColor3 = col, FontFace = BOLD, TextSize = 12, ZIndex = z + 1, Parent = card })
    label({ Size = UDim2.new(1, -12, 0, 40), Position = UDim2.fromOffset(6, 142), Text = perkLines(c.perks), TextColor3 = WHITE, TextSize = 12, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = z + 1, Parent = card })
    label({ Size = UDim2.new(1, -12, 0, 16), Position = UDim2.fromOffset(6, 184), Text = ("$%s/10s · ❤%d ⚔%d ⚡%s"):format(fmt(c.income), c.hp, c.atk, tostring(c.spd)), TextColor3 = KIND_COLOR.good, FontFace = BOLD, TextSize = 12, ZIndex = z + 1, Parent = card })
    for i, b in buttons or {} do
        button({ Size = UDim2.new(1, -12, 0, 24), Position = UDim2.new(0, 6, 1, -28 * i), Text = b[1], TextSize = 14, ZIndex = z + 3, BackgroundColor3 = b[3] or GOLD, Parent = card }, b[2])
    end
    return card
end

local ShopConfigC = require(game:GetService("ReplicatedStorage"):WaitForChild("ShopConfig"))
local ROBUX_GREEN = Color3.fromRGB(0, 190, 120)
local function robuxPrice(key)
    local p = ShopConfigC.product(key)
    return p and ("R$ " .. p.robux) or "R$"
end

local nameDialog
function openNameDialog(c)
    if nameDialog then nameDialog:Destroy() end
    local vip = state and state.passes and state.passes.VIP
    local tags = state and state.nameTags or 0
    local cost = Config.Naming.TagCost
    local how = vip and "⭐ Free for VIP"
        or tags > 0 and ("Uses 1 🏷️ Name Tag (you have %d)"):format(tags)
        or ("Costs $%s, or get 3 Name Tags for %s"):format(fmt(cost), robuxPrice("NameTags"))
    local shade = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, ZIndex = 60, Parent = gui })
    nameDialog = shade
    local box = new("Frame", { Size = UDim2.fromOffset(340, 236), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = PANEL, ZIndex = 61, Parent = shade }, { corner(16), stroke(GOLD, 0.2, 3) })
    label({ Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 10), Text = "🏷️ NAME YOUR CREATURE", FontFace = HEAD, TextScaled = true, TextColor3 = GOLD, ZIndex = 62, Parent = box })
    label({ Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 42), Text = "Now: " .. c.name, TextColor3 = MUTED, TextSize = 14, ZIndex = 62, Parent = box })
    local input = new("TextBox", { Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 66), BackgroundColor3 = PANEL3, TextColor3 = WHITE, PlaceholderText = "Type a name (3-20 letters)", PlaceholderColor3 = MUTED, Text = "", ClearTextOnFocus = false, FontFace = BOLD, TextSize = 18, ZIndex = 62, Parent = box }, { corner(10) })
    label({ Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 110), Text = how, TextColor3 = WHITE, TextSize = 13, ZIndex = 62, Parent = box })
    local canPay = vip or tags > 0 or (state and state.money >= cost)
    button({ Size = UDim2.new(0.5, -18, 0, 36), Position = UDim2.fromOffset(12, 148), Text = "✅ SAVE NAME", TextSize = 16, ZIndex = 62, BackgroundColor3 = canPay and KIND_COLOR.good or PANEL3, Parent = box }, function()
        local name = input.Text
        if utf8.len(name) == nil or #name:gsub("%s", "") < Config.Naming.MinLength then
            toast(("Names need %d to %d letters."):format(Config.Naming.MinLength, Config.Naming.MaxLength), "bad")
            return
        end
        Request:FireServer("RenameCreature", { id = c.id, name = name:sub(1, 60) })
        shade:Destroy()
    end)
    button({ Size = UDim2.new(0.5, -18, 0, 36), Position = UDim2.new(0.5, 6, 0, 148), Text = "🏷️x3 · " .. robuxPrice("NameTags"), TextSize = 16, ZIndex = 62, BackgroundColor3 = ROBUX_GREEN, TextColor3 = WHITE, Parent = box }, function()
        Request:FireServer("BuyProduct", "NameTags")
    end)
    local row = new("Frame", { Size = UDim2.new(1, -24, 0, 28), Position = UDim2.fromOffset(12, 196), BackgroundTransparency = 1, ZIndex = 62, Parent = box })
    if c.named then
        button({ Size = UDim2.new(0.5, -6, 1, 0), Text = "↩ ORIGINAL NAME", TextSize = 13, ZIndex = 62, BackgroundColor3 = PANEL3, TextColor3 = WHITE, Parent = row }, function()
            Request:FireServer("ResetName", c.id)
            shade:Destroy()
        end)
    end
    button({ Size = UDim2.new(0.5, -6, 1, 0), Position = UDim2.new(0.5, 6, 0, 0), Text = "CANCEL", TextSize = 13, ZIndex = 62, BackgroundColor3 = PANEL3, TextColor3 = WHITE, Parent = row }, function()
        shade:Destroy()
    end)
    input:CaptureFocus()
end

function renderInventory()
    clear(invList)
    if not state then return end
    for t, b in tabButtons do
        b.BackgroundColor3 = (t == invTab) and GOLD or PANEL2
        b.TextColor3 = (t == invTab) and DARKTEXT or WHITE
    end
    invTitle.Text = sellMode and "TRADING POST · SELL" or "INVENTORY"
    if invTab == "Creatures" then
        invGrid.CellSize = UDim2.fromOffset(176, sellMode and 236 or 292)
        invSub.Text = ("%d / %d in your lab · earning $%s every 10s"):format(#state.creatures, state.maxCreatures, fmt(state.income))
        local list = table.clone(state.creatures)
        table.sort(list, function(a, b) return a.power > b.power end)
        if #list == 0 then
            local f = new("Frame", { BackgroundTransparency = 1, Parent = invList })
            label({ Size = UDim2.fromOffset(520, 60), Text = "No creatures yet. Brew parts, then build one at the Assembly Lab on Market Street.", TextColor3 = MUTED, TextSize = 16, ZIndex = 7, Parent = f })
        end
        for i, c in list do
            local btns
            if sellMode then
                btns = { { "SELL $" .. fmt(c.sell), function() Request:FireServer("SellCreature", c.id) end } }
            elseif c.growCost then
                if state.money >= c.growCost then
                    btns = { { "🧪 GROW BIGGER · $" .. fmt(c.growCost), function() Request:FireServer("GrowCreature", c.id) end, KIND_COLOR.good } }
                else
                    btns = { { "🧪 GROW BIGGER · " .. robuxPrice("GrowPotion"), function() Request:FireServer("BuyProduct", { key = "GrowPotion", target = c.id }) end, ROBUX_GREEN } }
                end
            else
                btns = { { "⭐ MAX SIZE", function() end, PANEL3 } }
            end
            if not sellMode then
                if c.wings then
                    table.insert(btns, { "🪽 HAS WINGS", function() end, PANEL3 })
                else
                    if state.money >= Config.Wings.Cost then
                        table.insert(btns, { "🪽 ADD WINGS · $" .. fmt(Config.Wings.Cost), function() Request:FireServer("AddWings", c.id) end, Color3.fromRGB(255, 215, 120) })
                    else
                        table.insert(btns, { "🪽 ADD WINGS · " .. robuxPrice("Wings"), function() Request:FireServer("BuyProduct", { key = "Wings", target = c.id }) end, ROBUX_GREEN })
                    end
                end
                table.insert(btns, { "🏷️ NAME IT", function() openNameDialog(c) end, Color3.fromRGB(150, 200, 255) })
            end
            creatureCard(invList, c, i, 6, btns)
        end
    else
        invGrid.CellSize = UDim2.fromOffset(140, sellMode and 146 or 116)
        invSub.Text = ("%d / %d parts"):format(#state.parts, state.maxParts)
        local list = table.clone(state.parts)
        table.sort(list, function(a, b)
            local ra, rb = Config.RarityRank[a.rarity], Config.RarityRank[b.rarity]
            if ra ~= rb then return ra > rb end
            if a.slot ~= b.slot then return table.find(Config.Slots, a.slot) < table.find(Config.Slots, b.slot) end
            return a.family < b.family
        end)
        if #list == 0 then
            local f = new("Frame", { BackgroundTransparency = 1, Parent = invList })
            label({ Size = UDim2.fromOffset(520, 60), Text = "No parts yet. Brew elixirs at your cauldron and open the capsules.", TextColor3 = MUTED, TextSize = 16, ZIndex = 7, Parent = f })
        end
        for i, p in list do
            local value = (Config.PartSell[p.rarity] or 20) * (p.shiny and 2 or 1)
            local btns = sellMode and { { "SELL $" .. fmt(value), function() Request:FireServer("SellPart", p.id) end } } or nil
            partCard(invList, p, i, 6, btns)
        end
    end
end

local function openInventory(tab, sell)
    closeAll(inv)
    invTab = tab or invTab
    sellMode = sell and true or false
    inv.Visible = true
    renderInventory()
end

-------------------------------------------------
-- Assembly Lab
-------------------------------------------------
local asm, asmTitle, asmBody = panel("Assembly Lab", UDim2.fromScale(0.8, 0.82))
asmTitle.Text = "ASSEMBLY LAB"
local picks = {}       -- slot -> part id
local activeSlot = "Head"

local asmLeft = new("Frame", { Size = UDim2.new(0.36, -8, 1, 0), BackgroundColor3 = PANEL2, ZIndex = 6, Parent = asmBody }, { corner(12) })
local asmPreview = new("Frame", { Size = UDim2.new(1, 0, 0.5, 0), BackgroundTransparency = 1, ZIndex = 6, Parent = asmLeft })
local asmName = label({ Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 0.5, 0), Text = "", TextColor3 = GOLD, FontFace = HEAD, TextScaled = true, ZIndex = 7, Parent = asmLeft })
local asmStats = label({ Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 8, 0.5, 28), Text = "", TextColor3 = KIND_COLOR.good, FontFace = BOLD, TextSize = 13, ZIndex = 7, Parent = asmLeft })
local asmPerks = label({ Size = UDim2.new(1, -16, 0.5, -100), Position = UDim2.new(0, 8, 0.5, 48), Text = "", TextColor3 = WHITE, TextSize = 12, RichText = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 7, Parent = asmLeft })
local buildBtn = button({ Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 8, 1, -48), Text = "BUILD CREATURE", TextSize = 20, ZIndex = 8, Parent = asmLeft })

local asmRight = new("Frame", { Size = UDim2.new(0.64, 0, 1, 0), Position = UDim2.new(0.36, 8, 0, 0), BackgroundTransparency = 1, ZIndex = 6, Parent = asmBody })
local slotRow = new("Frame", { Size = UDim2.new(1, -8, 0, 96), BackgroundTransparency = 1, ZIndex = 6, Parent = asmRight },
    { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
local asmHint = label({ Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(0, 100), Text = "", TextColor3 = MUTED, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = asmRight })
local asmListHolder = new("Frame", { Size = UDim2.new(1, -8, 1, -230), Position = UDim2.fromOffset(0, 124), BackgroundTransparency = 1, ZIndex = 6, Parent = asmRight })
local asmList = scroller(asmListHolder, 6, new("UIGridLayout", { CellSize = UDim2.fromOffset(128, 140), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }))
label({ Size = UDim2.new(1, -8, 0, 18), Position = UDim2.new(0, 0, 1, -100), Text = "YOUR CREATURES (take apart to get the parts back)", TextColor3 = MUTED, FontFace = HEAD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = asmRight })
local asmCreaturesHolder = new("Frame", { Size = UDim2.new(1, -8, 0, 78), Position = UDim2.new(0, 0, 1, -80), BackgroundTransparency = 1, ZIndex = 6, Parent = asmRight })
local asmCreatures = new("ScrollingFrame", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
    ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 5, ScrollBarImageColor3 = GOLD, ZIndex = 6, Parent = asmCreaturesHolder,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local renderAssembly

local function ownedPart(id)
    if not state then return nil end
    for _, p in state.parts do
        if p.id == id then return p end
    end
    return nil
end

local function pickedParts()
    local parts = {}
    for slot, id in picks do
        local p = ownedPart(id)
        if p then parts[slot] = p else picks[slot] = nil end
    end
    return parts
end

function renderAssembly()
    if not state then return end
    local parts = pickedParts()
    -- preview
    clear(asmPreview)
    local hasCore = parts.Head and parts.Torso
    if next(parts) then
        local vp, model, focus = viewport(asmPreview, parts, {}, 7)
        spin(vp, model, focus)
    else
        label({ Size = UDim2.fromScale(1, 1), Text = "Pick parts on the right ▸", TextColor3 = MUTED, FontFace = HEAD, TextSize = 20, ZIndex = 7, Parent = asmPreview })
    end
    if hasCore then
        local s = PartsLogic.analyze(parts)
        asmName.Text = PartsLogic.creatureName(parts)
        asmName.TextColor3 = RARITY_COLOR[s.rarity] or GOLD
        asmStats.Text = ("%s · ❤ %d  ⚔ %d  ⚡ %s · ~$%s/10s"):format(s.rarity, s.hp, s.atk, tostring(s.spd), fmt(s.baseIncome * state.incomeMultiplier))
        local lines = {}
        for _, pk in s.perks do
            table.insert(lines, ("<b>%s %s</b> — %s"):format(pk.icon, pk.title, pk.desc))
        end
        asmPerks.Text = table.concat(lines, "\n")
        buildBtn.BackgroundColor3 = GOLD
        buildBtn.Text = "BUILD CREATURE"
    else
        asmName.Text = "Needs a Head + Torso"
        asmName.TextColor3 = MUTED
        asmStats.Text = ""
        asmPerks.Text = "Pick at least a Head and a Torso. Arms, Legs and a Weapon make it much stronger in battle."
        buildBtn.BackgroundColor3 = PANEL3
        buildBtn.Text = "BUILD CREATURE"
    end

    -- slot tiles
    clear(slotRow)
    for i, slot in Config.Slots do
        local p = parts[slot]
        local col = p and (RARITY_COLOR[p.rarity] or WHITE) or PANEL3
        local tile = new("TextButton", { Size = UDim2.new(0.2, -5, 1, 0), BackgroundColor3 = slot == activeSlot and PANEL3 or PANEL2, Text = "", AutoButtonColor = true, LayoutOrder = i, ZIndex = 7, Parent = slotRow },
            { corner(10), stroke(slot == activeSlot and GOLD or col, slot == activeSlot and 0 or 0.3, 2) })
        tile.Activated:Connect(function()
            activeSlot = slot
            renderAssembly()
        end)
        local holder = new("Frame", { Size = UDim2.new(1, 0, 1, -22), BackgroundTransparency = 1, ZIndex = 7, Parent = tile })
        if p then
            partViewport(holder, p, 8)
        else
            label({ Size = UDim2.fromScale(1, 1), Text = SLOT_ICON[slot], TextScaled = true, TextTransparency = 0.5, ZIndex = 8, Parent = holder })
        end
        label({ Size = UDim2.new(1, -4, 0, 18), Position = UDim2.new(0, 2, 1, -20), Text = slot:upper() .. ((slot == "Head" or slot == "Torso") and "*" or ""), TextColor3 = p and col or MUTED, FontFace = HEAD, TextScaled = true, ZIndex = 8, Parent = tile })
    end

    -- part list for the active slot
    clear(asmList)
    local list = {}
    for _, p in state.parts do
        if p.slot == activeSlot then table.insert(list, p) end
    end
    table.sort(list, function(a, b) return Config.RarityRank[a.rarity] > Config.RarityRank[b.rarity] end)
    asmHint.Text = (#list == 0) and ("No %s parts. Brew with %s to lean this slot."):format(activeSlot, (function()
        for k, s in Config.SlotBias do if s == activeSlot then return Config.Ingredients[k].name end end
        return "elixirs"
    end)()) or ("Choose a %s (%d owned). Click again to remove."):format(activeSlot, #list)
    for i, p in list do
        local chosen = picks[activeSlot] == p.id
        local card = partCard(asmList, p, i, 7, { { chosen and "✓ EQUIPPED" or "EQUIP", function()
            if picks[activeSlot] == p.id then picks[activeSlot] = nil else picks[activeSlot] = p.id end
            renderAssembly()
        end, chosen and KIND_COLOR.good or GOLD } })
        if chosen then card:FindFirstChildOfClass("UIStroke").Color = KIND_COLOR.good end
    end

    -- existing creatures
    clear(asmCreatures)
    for i, c in state.creatures do
        local col = RARITY_COLOR[c.rarity] or WHITE
        local f = new("Frame", { Size = UDim2.fromOffset(170, 74), BackgroundColor3 = PANEL2, LayoutOrder = i, ZIndex = 7, Parent = asmCreatures }, { corner(10), stroke(col, 0.3, 1) })
        local h = new("Frame", { Size = UDim2.fromOffset(64, 74), BackgroundTransparency = 1, ZIndex = 7, Parent = f })
        viewport(h, c.parts, {}, 8)
        label({ Size = UDim2.new(1, -70, 0, 32), Position = UDim2.fromOffset(66, 4), Text = c.name, TextColor3 = col, FontFace = HEAD, TextScaled = true, ZIndex = 8, Parent = f })
        button({ Size = UDim2.new(1, -72, 0, 24), Position = UDim2.fromOffset(66, 44), Text = "TAKE APART", TextSize = 12, BackgroundColor3 = PANEL3, TextColor3 = WHITE, ZIndex = 9, Parent = f }, function()
            Request:FireServer("Disassemble", c.id)
        end)
    end
end

buildBtn.Activated:Connect(function()
    local parts = pickedParts()
    if not (parts.Head and parts.Torso) then
        toast("Pick at least a Head and a Torso.", "bad")
        return
    end
    Request:FireServer("Assemble", table.clone(picks))
    picks = {}
end)

local function openAssembly()
    closeAll(asm)
    asm.Visible = true
    renderAssembly()
end

-------------------------------------------------
-- The Forge
-------------------------------------------------
local forge, forgeTitle, forgeBody = panel("The Forge", UDim2.fromScale(0.66, 0.72))
forgeTitle.Text = "THE FORGE"
local crateBox = new("Frame", { Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = PANEL2, ZIndex = 6, Parent = forgeBody }, { corner(12) })
label({ Size = UDim2.new(0.6, 0, 0, 26), Position = UDim2.fromOffset(12, 8), Text = "📦 WEAPON CRATE", TextColor3 = GOLD, FontFace = HEAD, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = crateBox })
label({ Size = UDim2.new(0.6, 0, 0, 30), Position = UDim2.fromOffset(12, 34), Text = ("A random weapon with %d rarity rolls."):format(Config.WeaponCrateRolls), TextColor3 = MUTED, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = crateBox })
local crateBtn = button({ Size = UDim2.new(0.35, 0, 0, 44), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Text = "", TextSize = 18, ZIndex = 8, Parent = crateBox }, function()
    Request:FireServer("WeaponCrate")
end)
label({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 80), Text = ("🔥 FUSE: %d parts of the same slot and rarity become 1 part of the next rarity"):format(Config.FuseCount), TextColor3 = WHITE, FontFace = HEAD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = forgeBody })
local fuseHolder = new("Frame", { Size = UDim2.new(1, 0, 1, -110), Position = UDim2.fromOffset(0, 108), BackgroundTransparency = 1, ZIndex = 6, Parent = forgeBody })
local fuseList = scroller(fuseHolder, 6, new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }))

local function renderForge()
    if not state then return end
    crateBtn.Text = "OPEN · $" .. fmt(math.floor(Config.WeaponCrateCost * (1 - state.discount)))
    clear(fuseList)
    local groups = {}
    for _, p in state.parts do
        if p.rarity ~= "Mythic" then
            local k = p.slot .. "|" .. p.rarity
            groups[k] = groups[k] or { slot = p.slot, rarity = p.rarity, n = 0 }
            groups[k].n += 1
        end
    end
    local list = {}
    for _, g in groups do table.insert(list, g) end
    table.sort(list, function(a, b)
        if (a.n >= Config.FuseCount) ~= (b.n >= Config.FuseCount) then return a.n >= Config.FuseCount end
        return Config.RarityRank[a.rarity] > Config.RarityRank[b.rarity]
    end)
    if #list == 0 then
        local f = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = fuseList })
        label({ Size = UDim2.fromScale(1, 1), Text = "No parts to fuse yet.", TextColor3 = MUTED, TextSize = 15, ZIndex = 7, Parent = f })
    end
    for i, g in list do
        local col = RARITY_COLOR[g.rarity] or WHITE
        local nextR = Config.RarityOrder[Config.RarityRank[g.rarity] + 1]
        local can = g.n >= Config.FuseCount
        local row = new("Frame", { Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = PANEL2, LayoutOrder = i, ZIndex = 7, Parent = fuseList }, { corner(10) })
        new("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = col, ZIndex = 8, Parent = row }, { corner(3) })
        label({ Size = UDim2.new(0.55, 0, 1, 0), Position = UDim2.fromOffset(16, 0), Text = ("%s %s %s  ×%d"):format(SLOT_ICON[g.slot], g.rarity, g.slot, g.n), TextColor3 = col, FontFace = HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = row })
        button({ Size = UDim2.new(0.4, 0, 0, 32), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Text = can and ("FUSE → " .. nextR) or ("need %d"):format(Config.FuseCount),
            TextSize = 15, BackgroundColor3 = can and GOLD or PANEL3, TextColor3 = can and DARKTEXT or MUTED, ZIndex = 9, Parent = row }, function()
            if can then Request:FireServer("Fuse", { slot = g.slot, rarity = g.rarity }) end
        end)
    end
end

local function openForge()
    closeAll(forge)
    forge.Visible = true
    renderForge()
end

-------------------------------------------------
-- Black Market
-------------------------------------------------
local mkt, mktTitle, mktBody = panel("Black Market", UDim2.fromScale(0.62, 0.62))
mktTitle.Text = "BLACK MARKET"
local mktTimer = label({ Size = UDim2.new(1, 0, 0, 20), Text = "", TextColor3 = MUTED, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = mktBody })
local mktRow = new("Frame", { Size = UDim2.new(1, 0, 1, -28), Position = UDim2.fromOffset(0, 28), BackgroundTransparency = 1, ZIndex = 6, Parent = mktBody },
    { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }) })

local function renderMarket()
    if not state then return end
    clear(mktRow)
    for i, o in state.market do
        local p = o.part
        local col = RARITY_COLOR[p.rarity] or WHITE
        local card = new("Frame", { Size = UDim2.new(0.31, 0, 1, 0), BackgroundColor3 = PANEL2, LayoutOrder = i, ZIndex = 7, Parent = mktRow }, { corner(12), stroke(col, 0.1, 2) })
        local holder = new("Frame", { Size = UDim2.new(1, 0, 0.5, 0), BackgroundTransparency = 1, ZIndex = 7, Parent = card })
        local vp, model, focus = partViewport(holder, p, 8)
        spin(vp, model, focus)
        label({ Size = UDim2.new(1, -12, 0, 24), Position = UDim2.new(0, 6, 0.5, 0), Text = partName(p), TextColor3 = col, FontFace = HEAD, TextScaled = true, ZIndex = 8, Parent = card })
        local perk = Config.PartPerks[p.slot][p.family]
        label({ Size = UDim2.new(1, -12, 0, 16), Position = UDim2.new(0, 6, 0.5, 26), Text = p.rarity:upper() .. " " .. p.slot:upper(), TextColor3 = col, FontFace = BOLD, TextSize = 12, ZIndex = 8, Parent = card })
        label({ Size = UDim2.new(1, -12, 0.5, -90), Position = UDim2.new(0, 6, 0.5, 44), Text = perk.icon .. " " .. perk.title .. ": " .. perk.desc, TextColor3 = MUTED, TextSize = 12, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 8, Parent = card })
        button({ Size = UDim2.new(1, -12, 0, 34), Position = UDim2.new(0, 6, 1, -40), Text = o.bought and "SOLD OUT" or ("BUY · $" .. fmt(o.price)), TextSize = 16,
            BackgroundColor3 = o.bought and PANEL3 or GOLD, TextColor3 = o.bought and MUTED or DARKTEXT, ZIndex = 9, Parent = card }, function()
            if not o.bought then Request:FireServer("BuyMarket", i) end
        end)
    end
end

local function openMarket()
    closeAll(mkt)
    mkt.Visible = true
    renderMarket()
end

-------------------------------------------------
-- Guide (brewing + collection log)
-------------------------------------------------
local guide, guideTitle, guideBody = panel("Guide", UDim2.fromScale(0.66, 0.78))
guideTitle.Text = "BREWING GUIDE"
local guideList = scroller(guideBody, 6, new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }))

local function renderGuide()
    if not state then return end
    clear(guideList)
    local order = 0
    local function row(h)
        order += 1
        return new("Frame", { Size = UDim2.new(1, -8, 0, h), BackgroundColor3 = PANEL2, LayoutOrder = order, ZIndex = 7, Parent = guideList }, { corner(10) })
    end
    local intro = row(56)
    label({ Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), Text = ("Pour at least %d elixirs into your cauldron. One elixir picks the FAMILY, another picks the SLOT (by its lean). Every $%d in one brew = +1 rarity roll (max %d)."):format(Config.MinElixirsToBrew, Config.ValuePerRoll, Config.MaxRolls),
        TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = intro })
    for _, key in Config.IngredientOrder do
        local ing = Config.Ingredients[key]
        local r = row(40)
        new("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = Config.Color(ing.color), ZIndex = 8, Parent = r }, { corner(3) })
        if ing.image then
            new("ImageLabel", { Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(12, 2), BackgroundTransparency = 1, Image = ing.image, ScaleType = Enum.ScaleType.Fit, ZIndex = 8, Parent = r })
        end
        label({ Size = UDim2.new(0.4, -36, 1, 0), Position = UDim2.fromOffset(52, 0), Text = ing.name, TextColor3 = Config.Color(ing.color), FontFace = HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = r })
        label({ Size = UDim2.new(0.25, 0, 1, 0), Position = UDim2.fromScale(0.4, 0), Text = "$" .. ing.price, TextColor3 = GOLD, FontFace = BOLD, TextSize = 14, ZIndex = 8, Parent = r })
        label({ Size = UDim2.new(0.35, -8, 1, 0), Position = UDim2.fromScale(0.65, 0), Text = "leans " .. SLOT_ICON[Config.SlotBias[key]] .. " " .. Config.SlotBias[key]:upper(), TextColor3 = WHITE, FontFace = BOLD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = r })
    end
    -- collection grid: slot x family
    local found, total = 0, 0
    local grid = row(6 * 34 + 10)
    local CW = 0.84 / #Config.Families
    for c, fam in Config.Families do
        label({ Size = UDim2.new(CW, 0, 0, 30), Position = UDim2.new(0.16 + CW * (c - 1), 0, 0, 4), Text = Config.NamePrefix[fam], TextColor3 = Config.Color(Config.Ingredients[fam].color), FontFace = HEAD, TextScaled = true, ZIndex = 8, Parent = grid })
    end
    for r, slot in Config.Slots do
        label({ Size = UDim2.new(0.16, 0, 0, 30), Position = UDim2.new(0, 6, 0, 4 + r * 34), Text = SLOT_ICON[slot] .. " " .. slot, TextColor3 = WHITE, FontFace = HEAD, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = grid })
        for c, fam in Config.Families do
            total += 1
            local best = state.discoveries[slot .. ":" .. fam]
            if best then found += 1 end
            local rar = best and Config.RarityOrder[best]
            local cell = new("Frame", { Size = UDim2.new(CW, -4, 0, 30), Position = UDim2.new(0.16 + CW * (c - 1), 2, 0, 4 + r * 34), BackgroundColor3 = rar and RARITY_COLOR[rar] or PANEL3, BackgroundTransparency = rar and 0.55 or 0, ZIndex = 8, Parent = grid }, { corner(6) })
            label({ Size = UDim2.fromScale(1, 1), Text = rar and Config.PartNames[slot][fam] or "???", TextColor3 = rar and WHITE or MUTED, FontFace = BOLD, TextScaled = true, ZIndex = 9, Parent = cell }, { new("UITextSizeConstraint", { MaxTextSize = 12 }) })
        end
    end
    guideTitle.Text = ("BREWING GUIDE · %d / %d parts found"):format(found, total)
end

-------------------------------------------------
-- Battle menu
-------------------------------------------------
local bmenu, bmenuTitle, bmenuBody = panel("Battle", UDim2.fromOffset(420, 360), 5, Vector2.new(420, 360))
bmenuTitle.Text = "OHIO COLOSSEUM"
local bInfo = label({ Size = UDim2.new(1, 0, 0, 54), Text = "", TextColor3 = WHITE, TextSize = 14, RichText = true, ZIndex = 7, Parent = bmenuBody })
local bButtons = new("Frame", { Size = UDim2.new(1, 0, 1, -60), Position = UDim2.fromOffset(0, 60), BackgroundTransparency = 1, ZIndex = 6, Parent = bmenuBody },
    { new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
local rankedBtn = button({ Size = UDim2.new(1, 0, 0, 48), Text = "", TextSize = 20, LayoutOrder = 1, ZIndex = 7, Parent = bButtons }, function()
    if state and state.inQueue then Request:FireServer("LeaveQueue") else Request:FireServer("QueueRanked") end
end)
button({ Size = UDim2.new(1, 0, 0, 44), Text = "🌀 Teleport to the Colosseum", TextSize = 17, LayoutOrder = 2, BackgroundColor3 = PANEL3, TextColor3 = WHITE, ZIndex = 7, Parent = bButtons }, function()
    Request:FireServer("GoArena")
end)
button({ Size = UDim2.new(1, 0, 0, 44), Text = "🏠 Back to the hub", TextSize = 17, LayoutOrder = 3, BackgroundColor3 = PANEL3, TextColor3 = WHITE, ZIndex = 7, Parent = bButtons }, function()
    Request:FireServer("GoHub")
end)
label({ Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 4, Text = "Wild brainrots: stand on the green pad inside. Casual duels: red and blue pads. Ranked: queue here and you'll be teleported when matched.", TextColor3 = MUTED, TextSize = 12, ZIndex = 7, Parent = bButtons })

local function renderBattleMenu()
    if not state then return end
    bInfo.Text = ("🏆 <b>%d trophies</b> · Wild tier %d · %d wins\nRanked queue: %d waiting"):format(state.trophies, state.arenaLevel, state.wins, state.queueSize)
    rankedBtn.Text = state.inQueue and "⏳ In queue... (click to leave)" or "⚔ Queue for RANKED"
    rankedBtn.BackgroundColor3 = state.inQueue and PANEL3 or GOLD
    rankedBtn.TextColor3 = state.inQueue and WHITE or DARKTEXT
end

local function openBattleMenu()
    closeAll(bmenu)
    bmenu.Visible = true
    renderBattleMenu()
end

-------------------------------------------------
-- Reveal card (parts and freshly built creatures)
-------------------------------------------------
local reveal = new("Frame", {
    Name = "Reveal", Size = UDim2.fromOffset(420, 470), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.03, Visible = false, ZIndex = 30, Parent = gui,
}, { corner(18), stroke(GOLD, 0.1, 3) })
table.insert(openPanels, reveal)

-- big reveal moment: screen flash + rarity banner + sound (bigger for rarer pulls)
local REVEAL_SOUNDS = { small = "rbxassetid://9039712090", big = "rbxassetid://9045751375" }
local revealSounds = {}
for k, id in REVEAL_SOUNDS do
    revealSounds[k] = new("Sound", { SoundId = id, Volume = 0.6, Parent = gui })
end
local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 40, Active = false, Parent = gui })
local banner = label({ Size = UDim2.new(1, 0, 0, 90), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.16), Text = "", FontFace = HEAD,
    TextScaled = true, TextStrokeTransparency = 0, TextStrokeColor3 = Color3.new(0, 0, 0), Visible = false, ZIndex = 41, Parent = gui },
    { new("UITextSizeConstraint", { MaxTextSize = 72 }) })
local bannerToken = 0

local function revealMoment(rarity, headline)
    local rank = Config.RarityRank[rarity] or 1
    local col = RARITY_COLOR[rarity] or WHITE
    flash.BackgroundColor3 = col
    flash.BackgroundTransparency = rank >= 4 and 0.15 or 0.55
    TweenService:Create(flash, TweenInfo.new(rank >= 4 and 1.1 or 0.6), { BackgroundTransparency = 1 }):Play()
    local snd = revealSounds[rank >= 4 and "big" or "small"]
    if snd then snd:Play() end
    bannerToken += 1
    local my = bannerToken
    local sparkle = rank >= 5 and "🌟 " or (rank >= 4 and "✨ " or "")
    banner.Text = sparkle .. (headline or (rarity:upper() .. "!")) .. (sparkle ~= "" and (" " .. sparkle) or "")
    banner.TextColor3 = col
    banner.Size = UDim2.new(1, 0, 0, 30)
    banner.Visible = true
    TweenService:Create(banner, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Size = UDim2.new(1, 0, 0, rank >= 4 and 110 or 80) }):Play()
    task.delay(rank >= 4 and 3 or 2, function()
        if my == bannerToken then banner.Visible = false end
    end)
end

Remotes:WaitForChild("Revealed").OnClientEvent:Connect(function(info)
    local keepOpen = asm.Visible or forge.Visible
    if not keepOpen then closeAll(reveal) end
    clear(reveal)
    local rarity, title, sub, desc, extra
    local holder = new("Frame", { Size = UDim2.new(1, -40, 0, 220), Position = UDim2.fromOffset(20, 50), BackgroundColor3 = PANEL2, ZIndex = 31, Parent = reveal }, { corner(14) })
    local vp, model, focus
    if info.kind == "part" then
        local p = info.part
        local perk = Config.PartPerks[p.slot][p.family]
        rarity = p.rarity
        title = (info.fused and "FUSED!") or (info.isNew and "NEW PART DISCOVERED!") or "CAPSULE OPENED!"
        sub = partName(p)
        desc = ("%s %s · %s"):format(p.rarity:upper(), p.slot:upper(), p.shiny and "SHINY (1.5x stats)" or Config.NamePrefix[p.family] .. " family")
        extra = perk.icon .. "  " .. perk.title .. ": " .. perk.desc
        vp, model, focus = partViewport(holder, p, 32)
    else
        local c = info.creature
        rarity = c.rarity
        title = (info.winged and "IT GOT WINGS!") or (info.grown and "IT GREW BIGGER!") or "CREATURE BUILT!"
        sub = c.name
        desc = ("%s · ❤ %d  ⚔ %d  ⚡ %s"):format(c.rarity:upper(), c.hp, c.atk, tostring(c.spd))
        if info.winged then
            extra = ("%s %s: %s\nIt now earns $%s every 10s."):format(Config.Wings.Perk.icon, Config.Wings.Perk.title, Config.Wings.Perk.desc, fmt(c.income))
        elseif info.grown then
            extra = ("Size %d / %d. It now earns $%s every 10s."):format(c.growth, Config.Growth.MaxLevel, fmt(c.income))
                .. (c.growCost and ("\nNext Growth Potion: $%s"):format(fmt(c.growCost)) or "\nThat's the biggest it can get!")
        else
            extra = perkLines(c.perks) .. ("\nEarns $%s every 10s. It's moving into your lab now."):format(fmt(c.income))
        end
        vp, model, focus = viewport(holder, c.parts, {}, 32)
    end
    spin(vp, model, focus)
    local col = RARITY_COLOR[rarity] or WHITE
    reveal:FindFirstChildOfClass("UIStroke").Color = col
    label({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 12), Text = title, TextColor3 = GOLD, FontFace = HEAD, TextSize = 26, ZIndex = 31, Parent = reveal })
    label({ Size = UDim2.new(1, -20, 0, 38), Position = UDim2.fromOffset(10, 276), Text = sub, TextColor3 = col, FontFace = HEAD, TextScaled = true, ZIndex = 31, Parent = reveal })
    label({ Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 316), Text = desc, TextColor3 = col, FontFace = BOLD, TextSize = 14, ZIndex = 31, Parent = reveal })
    label({ Size = UDim2.new(1, -40, 0, 64), Position = UDim2.fromOffset(20, 340), Text = extra, TextColor3 = WHITE, TextSize = 14, ZIndex = 31, Parent = reveal })
    button({ Size = UDim2.new(0, 160, 0, 36), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 418), Text = "NICE", TextSize = 20, ZIndex = 32, Parent = reveal }, function()
        reveal.Visible = false
    end)
    revealMoment(rarity, (info.winged and "WINGS!") or (info.grown and "IT GREW!") or nil)
    reveal.Size = UDim2.fromOffset(380, 420)
    reveal.Visible = true
    TweenService:Create(reveal, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(420, 470) }):Play()
end)

-------------------------------------------------
-- Battle viewer
-------------------------------------------------
local battle = new("Frame", {
    Name = "BattleView", Size = UDim2.new(0.7, 0, 0, 190), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
    BackgroundColor3 = PANEL, BackgroundTransparency = 0.08, Visible = false, ZIndex = 15, Parent = gui,
}, { corner(16), stroke(GOLD, 0.3, 2), new("UISizeConstraint", { MaxSize = Vector2.new(900, 220) }) })
local bTitle = label({ Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 8), Text = "", TextColor3 = GOLD, FontFace = HEAD, TextSize = 24, ZIndex = 16, Parent = battle })
local bLog = label({ Size = UDim2.new(1, -20, 0, 24), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Text = "", TextSize = 16, FontFace = BOLD, RichText = true, ZIndex = 16, Parent = battle })
local sideFrames = {}
for _, side in { "A", "B" } do
    sideFrames[side] = new("Frame", {
        Size = UDim2.new(0.48, -10, 0, 120), Position = side == "A" and UDim2.fromOffset(12, 38) or UDim2.new(0.52, -2, 0, 38),
        BackgroundTransparency = 1, ZIndex = 16, Parent = battle,
    }, { new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })
end
local unitBars, unitInfo = {}, {}

local function setBar(uid, hp)
    local u, bar = unitInfo[uid], unitBars[uid]
    if not (u and bar) then return end
    u.hp = hp
    local frac = math.clamp(hp / u.maxHp, 0, 1)
    TweenService:Create(bar.fill, TweenInfo.new(0.3), { Size = UDim2.fromScale(frac, 1) }):Play()
    bar.hpText.Text = ("%d / %d"):format(hp, u.maxHp)
    bar.row.BackgroundTransparency = hp <= 0 and 0.7 or 0.2
end

local function nameOf(uid)
    local u = unitInfo[uid]
    if not u then return "?" end
    local hex = (RARITY_COLOR[u.rarity] or WHITE):ToHex()
    return ('<font color="#%s">%s</font>'):format(hex, u.name)
end

Remotes:WaitForChild("BattleEvent").OnClientEvent:Connect(function(kind, data)
    if kind == "start" then
        closeAll()
        unitBars, unitInfo = {}, {}
        for _, side in { "A", "B" } do
            clear(sideFrames[side])
            for i, u in data[side] do
                u.hp = u.maxHp
                unitInfo[u.uid] = u
                local col = RARITY_COLOR[u.rarity] or WHITE
                local row = new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = PANEL2, BackgroundTransparency = 0.2, LayoutOrder = i, ZIndex = 16, Parent = sideFrames[side] }, { corner(8) })
                label({ Size = UDim2.new(0.6, 0, 0, 18), Position = UDim2.fromOffset(8, 1), Text = (u.icon or "") .. " " .. u.name, TextColor3 = col, FontFace = HEAD, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 17, Parent = row })
                local hpText = label({ Size = UDim2.new(0.4, -12, 0, 18), Position = UDim2.new(0.6, 0, 0, 1), Text = "", TextColor3 = MUTED, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 17, Parent = row })
                local back = new("Frame", { Size = UDim2.new(1, -16, 0, 10), Position = UDim2.fromOffset(8, 21), BackgroundColor3 = Color3.fromRGB(15, 10, 20), ZIndex = 17, Parent = row }, { corner(5) })
                local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = side == data.mySide and KIND_COLOR.good or KIND_COLOR.bad, ZIndex = 18, Parent = back }, { corner(5) })
                unitBars[u.uid] = { fill = fill, hpText = hpText, row = row }
                setBar(u.uid, u.maxHp)
            end
        end
        bTitle.Text = ("%s  VS  %s"):format(data.titleA, data.titleB)
        bTitle.TextColor3 = GOLD
        bLog.Text = data.kind == "duel" and "Duel starting..." or "Wild brainrots approach..."
        battle.Visible = true
    elseif kind == "action" then
        local ev = data
        if ev.type == "hit" then
            setBar(ev.to, ev.hp)
            local extra = {}
            if ev.crit then table.insert(extra, "CRIT") end
            if ev.ambush then table.insert(extra, "BACKSTAB") end
            local txt = ("%s hits %s for <b>%d</b>%s"):format(nameOf(ev.from), nameOf(ev.to), ev.dmg, #extra > 0 and (" (" .. table.concat(extra, ", ") .. ")") or "")
            if ev.splash and #ev.splash > 0 then
                for _, s in ev.splash do setBar(s.uid, s.hp) end
                txt ..= " · SPLASH"
            end
            if ev.lifesteal and ev.lifesteal > 0 then
                setBar(ev.from, ev.fromHp)
                txt ..= (" · taxes %d HP"):format(ev.lifesteal)
            end
            if ev.heal then
                setBar(ev.heal.uid, ev.heal.hp)
                txt ..= (" · +%d HP"):format(ev.heal.amount)
            end
            if ev.charm then txt ..= " · CHARMED" end
            if ev.ko then txt ..= " · <b>KO!</b>" end
            bLog.Text = txt
        elseif ev.type == "dodge" then
            bLog.Text = ("%s attacks, but %s phased out! Dodged."):format(nameOf(ev.from), nameOf(ev.to))
        elseif ev.type == "charmed" then
            bLog.Text = ("%s is too rizzed up to attack."):format(nameOf(ev.unit))
        elseif ev.type == "hype" then
            bLog.Text = ("Hype Beast energy! Team %s hits +%d%% harder."):format(ev.side, ev.pct)
        elseif ev.type == "timeout" then
            bLog.Text = "Time! Highest remaining HP wins."
        end
    elseif kind == "end" then
        bTitle.Text = data.won and "VICTORY" or "DEFEAT"
        bTitle.TextColor3 = data.won and KIND_COLOR.good or KIND_COLOR.bad
        bLog.Text = data.text or ""
        task.delay(4, function()
            battle.Visible = false
            bTitle.TextColor3 = GOLD
        end)
    end
end)

-------------------------------------------------
-- State rendering
-------------------------------------------------
local function renderSatchel()
    clear(satchel)
    local value = 0
    for i = 1, Config.SatchelSize do
        local key = state.ingredients[i]
        local ing = key and Config.Ingredients[key]
        if ing then value += ing.price end
        local chip = new("Frame", { BackgroundColor3 = ing and Config.Color(ing.color) or PANEL2, BackgroundTransparency = ing and 0.1 or 0.4, LayoutOrder = i, Parent = satchel }, { corner(6) })
        if ing and ing.image then
            new("ImageLabel", { Size = UDim2.fromScale(0.9, 0.9), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, Image = ing.image, ScaleType = Enum.ScaleType.Fit, Parent = chip })
            chip.BackgroundTransparency = 0.6
        elseif ing then
            label({ Size = UDim2.fromScale(1, 1), Text = key:upper(), TextColor3 = Color3.new(1, 1, 1), FontFace = HEAD, TextSize = 12, TextStrokeTransparency = 0.4, Parent = chip })
        end
    end
    -- a Body Draught shows as a wide chip after the elixirs
    local d = state.draught and Config.Draughts[state.draught]
    if d then
        local chip = new("Frame", { BackgroundColor3 = Config.Color(d.color), LayoutOrder = Config.SatchelSize + 1, Parent = satchel }, { corner(6), stroke(Color3.new(1, 1, 1), 0.2, 2) })
        label({ Size = UDim2.fromScale(1, 1), Text = d.icon .. " " .. state.draught:upper(), TextColor3 = Color3.new(1, 1, 1), FontFace = HEAD, TextSize = 11, TextStrokeTransparency = 0.4, Parent = chip })
    end
    local rolls = 1 + math.min(Config.MaxRolls - 1, math.floor(value / Config.ValuePerRoll)) + (state.luck or 0)
    local title = #state.ingredients > 0 and ("SATCHEL · %d rarity roll%s"):format(rolls, rolls > 1 and "s" or "") or "SATCHEL"
    if d then title ..= " · makes a " .. state.draught:upper() end
    satchelTitle.Text = title
    emptyBtn.Visible = #state.ingredients > 0 or d ~= nil
end

-- guide arrow: a bouncing ⬇ over the current goal
local guideMark
local function setGuideTarget(inst)
    local part = inst and (inst:IsA("BasePart") and inst or (inst:IsA("Model") and (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true))))
    if not guideMark then
        guideMark = new("BillboardGui", { Size = UDim2.fromOffset(70, 70), StudsOffset = Vector3.new(0, 5, 0), AlwaysOnTop = true, Enabled = false, Parent = gui })
        label({ Size = UDim2.fromScale(1, 1), Text = "⬇", TextScaled = true, TextColor3 = GOLD, TextStrokeTransparency = 0, Parent = guideMark })
        TweenService:Create(guideMark, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { StudsOffset = Vector3.new(0, 6.5, 0) }):Play()
    end
    if not part then
        guideMark.Enabled = false
        return
    end
    guideMark.Adornee = part
    guideMark.Enabled = true
end

local function renderObjective()
    if not state then return end
    local plot = state.plotId and workspace.PlayerPlots:FindFirstChild("Plot" .. state.plotId)
    local shop = workspace:FindFirstChild("IngredientShop")
    local target
    local t = workspace:GetServerTimeNow()
    local ready, cooking, soonest = 0, 0, math.huge
    for _, p in state.pods do
        if t >= p.finish then ready += 1 else cooking += 1 soonest = math.min(soonest, p.finish - t) end
    end
    local lab = state.plotId and ("Plot " .. state.plotId) or "your lab"
    local hasHead, hasTorso = false, false
    for _, p in state.parts do
        if p.slot == "Head" then hasHead = true end
        if p.slot == "Torso" then hasTorso = true end
    end
    local text
    if ready > 0 then
        text = ("📦 <font color='#FFCD5A'>%d capsule%s ready!</font> Open at %s."):format(ready, ready > 1 and "s" or "", lab)
        for podId, p in state.pods do
            if t >= p.finish and plot then target = plot:FindFirstChild(podId, true) break end
        end
    elseif #state.ingredients >= Config.MinElixirsToBrew then
        text = ("🧪 Satchel loaded. Go to <font color='#FFCD5A'>%s</font> and Brew at your cauldron."):format(lab)
        target = plot and plot:FindFirstChild("CauldronBody")
    elseif hasHead and hasTorso and #state.creatures == 0 then
        text = "🔧 You have a Head + Torso! Build a creature at the <font color='#FFCD5A'>Assembly Lab</font> on Market Street."
        target = workspace:FindFirstChild("AssemblyBench", true)
    elseif cooking > 0 then
        text = ("⏳ Capsule growing (%ds). Cop more elixirs while you wait."):format(math.ceil(soonest))
    elseif #state.creatures == 0 then
        local need = (not hasHead) and "a HEAD (Frostmind Tonic)" or "a TORSO (Liquid Gold Nectar)"
        text = ("🛍 Brew %s. Buy 2+ elixirs at <font color='#FFCD5A'>Maison Mixalot</font>."):format(need)
        target = shop and shop:FindFirstChild(hasHead and "RizzPowder" or "SigmaExtract")
    elseif #state.creatures < Config.UnlockCreatures then
        local more = Config.UnlockCreatures - #state.creatures
        text = ("💰 Step on the glowing pad by your pedestal to collect cash. Build %d more creature%s to unlock Battles + Trading!"):format(more, more > 1 and "s" or "")
        target = plot and plot:FindFirstChild("Showcase") and plot.Showcase:FindFirstChild("Showcase1") and plot.Showcase.Showcase1:FindFirstChild("CollectPad")
    elseif state.trophies == 0 then
        text = "⚔ Battles are unlocked! Take the <font color='#FFCD5A'>Battle Portal</font> in the hub."
        target = workspace:FindFirstChild("BattlePortal", true)
    else
        text = "🔧 Upgrade: brew rarer parts, fuse at The Forge, check the Black Market."
    end
    objectiveLabel.Text = text
    setGuideTarget(target)
end

local menuButtons = {}
local function render()
    if not state then return end
    moneyLabel.Text = "$" .. fmt(state.money)
    incomeLabel.Text = ("+$%s every 10s · %d/%d creatures · %d parts"):format(fmt(state.income), #state.creatures, state.maxCreatures, #state.parts)
    local bits = { ("🏆 %d"):format(state.trophies), ("Rebirth %d (x%.2f)"):format(state.rebirths, state.incomeMultiplier) }
    if state.discount > 0 then table.insert(bits, ("-%d%% shop"):format(math.floor(state.discount * 100 + 0.5))) end
    if state.growBoost > 0 then table.insert(bits, ("+%d%% grow"):format(math.floor(state.growBoost * 100 + 0.5))) end
    if state.inQueue then table.insert(bits, "⏳ Ranked queue") end
    statsLabel.Text = table.concat(bits, "  ·  ")
    -- 🔒 on Battle/Trade until enough creatures
    local isLocked = #state.creatures < Config.UnlockCreatures
    for _, m in menuButtons do
        if m.text == "Battle" or m.text == "Trade" then
            m.baseIcon = m.baseIcon or m.icon
            local compact = m.button.Text == m.icon
            m.icon = isLocked and "🔒" or m.baseIcon
            m.button.Text = compact and m.icon or (m.icon .. " " .. m.text)
        end
    end
    renderSatchel()
    renderObjective()
    if inv.Visible then renderInventory() end
    if asm.Visible then renderAssembly() end
    if forge.Visible then renderForge() end
    if mkt.Visible then renderMarket() end
    if guide.Visible then renderGuide() end
    if bmenu.Visible then renderBattleMenu() end
end

local lastMoney
Remotes:WaitForChild("StateUpdate").OnClientEvent:Connect(function(s)
    state = s
    if lastMoney and s.money ~= lastMoney then
        moneyLabel.TextColor3 = s.money > lastMoney and KIND_COLOR.good or KIND_COLOR.bad
        TweenService:Create(moneyLabel, TweenInfo.new(0.6), { TextColor3 = GOLD }):Play()
    end
    lastMoney = s.money
    render()
end)

task.spawn(function()
    while true do
        task.wait(1)
        renderObjective()
        if mkt.Visible and state then
            local left = math.max(0, math.ceil(state.marketRefreshAt - workspace:GetServerTimeNow()))
            mktTimer.Text = ("New stock in %d:%02d · one of each per customer"):format(left // 60, left % 60)
        end
    end
end)

Remotes:WaitForChild("OpenUI").OnClientEvent:Connect(function(what)
    if what == "intro" or what == "dialogue" then
        openDialogue("intro")
    elseif what == "sell" then
        openInventory("Parts", true)
    elseif what == "assembly" then
        openAssembly()
    elseif what == "forge" then
        openForge()
    elseif what == "market" then
        openMarket()
    elseif what == "battle" then
        openBattleMenu()
    end
end)

-------------------------------------------------
-- Menu buttons (labelled column on PC, compact icon grid on phones/tablets)
-------------------------------------------------
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local menuLayout = menu:FindFirstChildOfClass("UIListLayout")
local function menuButton(icon, text, order, fn, color)
    local b = button({ Size = UDim2.new(1, 0, 0, 44), Text = icon .. " " .. text, TextSize = 18, LayoutOrder = order, BackgroundColor3 = color, Parent = menu }, fn)
    stroke(Color3.fromRGB(80, 50, 10), 0.3, 2).Parent = b
    table.insert(menuButtons, { button = b, icon = icon, text = text })
    return b
end
local function toggle(p, opener)
    if p.Visible then p.Visible = false else opener() end
end
local function fireUI(guiName, eventName, arg)
    local g = player.PlayerGui:FindFirstChild(guiName)
    local ev = g and g:FindFirstChild(eventName)
    if ev then ev:Fire(arg) end
end
menuButton("🐾", "Creatures", 1, function() toggle(inv, function() openInventory("Creatures", false) end) end)
menuButton("🧩", "Parts", 2, function() toggle(inv, function() openInventory("Parts", false) end) end)
menuButton("🏡", "Decorate", 3, function() closeAll() fireUI("DecorUI", "Toggle") end, Color3.fromRGB(140, 230, 120))
local function lockedFor(what)
    if state and #state.creatures < Config.UnlockCreatures then
        toast(("🔒 %s unlock when you own %d creatures. You have %d."):format(what, Config.UnlockCreatures, #state.creatures), "bad")
        return true
    end
    return false
end
menuButton("⚔", "Battle", 4, function() if lockedFor("Battles") then return end toggle(bmenu, openBattleMenu) end)
menuButton("🤝", "Trade", 5, function() if lockedFor("Trading") then return end closeAll() fireUI("TradeUI", "Toggle") end, Color3.fromRGB(255, 170, 90))
menuButton("💎", "Shop", 6, function() closeAll() fireUI("ShopUI", "Toggle") end, Color3.fromRGB(90, 220, 255))
menuButton("🎁", "Daily", 7, function() fireUI("ShopUI", "Daily") end, Color3.fromRGB(255, 150, 220))
menuButton("📖", "Guide", 8, function() toggle(guide, function() closeAll(guide) guide.Visible = true renderGuide() end) end)
menuButton("❓", "Help", 9, function() if dlg.Visible then closeDialogue() else openDialogue("intro") end end)

local menuGrid = new("UIGridLayout", { CellSize = UDim2.fromOffset(54, 54), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, FillDirectionMaxCells = 2 })

local function layoutMenu(compact)
    if compact then
        menuLayout.Parent = nil
        menuGrid.Parent = menu
        menu.Size = UDim2.fromOffset(114, 0)
        menu.AnchorPoint = Vector2.new(1, 0)
        menu.Position = UDim2.new(1, -10, 0, 44)
        for _, m in menuButtons do
            m.button.Text = m.icon
            m.button.TextSize = 26
        end
    else
        menuGrid.Parent = nil
        menuLayout.Parent = menu
        menu.Size = UDim2.fromOffset(150, 0)
        menu.AnchorPoint = Vector2.new(1, 0.5)
        menu.Position = UDim2.new(1, -14, 0.5, 0)
        for _, m in menuButtons do
            m.button.Text = m.icon .. " " .. m.text
            m.button.TextSize = 18
        end
    end
end

-------------------------------------------------
-- Fit the UI to the screen: PC, tablet, phone
-------------------------------------------------
local scalers = {}
for _, f in { hud, menu, dlg, inv, asm, forge, mkt, guide, bmenu, reveal, battle, toastHolder } do
    table.insert(scalers, new("UIScale", { Parent = f }))
end
-- panels sized as a fraction of the screen on PC; nearly full-screen on small screens
local PANEL_FRACTION = {
    [inv] = Vector2.new(0.74, 0.76), [asm] = Vector2.new(0.8, 0.82), [forge] = Vector2.new(0.66, 0.72),
    [mkt] = Vector2.new(0.62, 0.62), [guide] = Vector2.new(0.66, 0.78),
}
local function rescale()
    local vp = workspace.CurrentCamera.ViewportSize
    local device = UIKit.device()
    local small = device ~= "desktop" or vp.Y < 560 or vp.X < 900
    local s = math.clamp(math.min(vp.X / 1100, vp.Y / 700), 0.55, 1)
    if device == "phone" then s = math.max(s, 0.75) end -- keeps buttons finger-sized
    for _, sc in scalers do sc.Scale = s end
    for p, base in PANEL_FRACTION do
        local f = small and Vector2.new(0.97, 0.94) or base
        p.Size = UDim2.fromScale(f.X / s, f.Y / s)
    end
    -- the HUD loses the "empty satchel" button on phones to save space
    emptyBtn.Visible = device ~= "phone"
    layoutMenu(small)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
rescale()

Request:FireServer("Sync")
print("[LabClient] UI ready")
