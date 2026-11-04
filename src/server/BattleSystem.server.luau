--[[
    BattleSystem — turn-based Colosseum battles with a timing bar.

    GameManager still decides WHO fights (wild pad, duel pads, ranked queue) and pays out
    rewards through o.onFinish. It hands every fight to LabAPI.runTurnBattle(o):
      o = { kind, players, sides = {[player] = "A"|"B"}, A = units, B = units, titleA, titleB, onFinish }

    One creature per side is out at a time; when it faints the next one steps in.
    Each round both sides pick a move (20s), play the timing bar, then the moves resolve
    (Quick moves first, then the faster creature). Wild teams and AFK players are run by the AI.
    Anyone standing near the arena gets the events too, so they can watch.

    Client protocol (BattleEvent): "tb_start", "tb_turn", "tb_wait", "tb_line", "tb_enter", "tb_bets", "tb_end".
    Requests from the client: "BattleMove" (move index), "BattleTap", "PlaceBet" { side, pct }.

    Betting: spectators (not the fighters) can stake 10/25/50% of their cash on a side,
    once per fight, until round 2 starts. Odds come from team strength with an 8% house edge,
    so underdogs pay more. In-game cash only, never Robux. When the arena sits empty and
    someone is watching, two wild packs play an exhibition match so there's always a fight to bet on.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LabAPI = require(script.Parent:WaitForChild("LabAPI"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local CreatureBuilder = require(ReplicatedStorage:WaitForChild("CreatureBuilder"))
local BattleMoves = require(ReplicatedStorage:WaitForChild("BattleMoves"))
local BattleEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BattleEvent")

local MAX_ROUNDS = 24
local DAMAGE_SCALE = 1.6 -- keeps fights to roughly 3-5 hits per creature
local LINE_DELAY = 1.25  -- seconds between battle log lines
local WATCH_RADIUS = 170
local BET_PCTS = { 0.1, 0.25, 0.5 }
local BET_MIN, BET_MAX = 50, 1000000
local HOUSE_EDGE = 0.92
local BET_WINDOW = 12      -- seconds of betting before round 1 when someone is watching
local EXHIBITION_IDLE = 20 -- empty-arena seconds before an exhibition starts
local lastBattleEnd = os.clock()

local current = nil -- the battle in progress (the Colosseum runs one at a time)

local EFFECT_COLOR = {
    freeze = Color3.fromRGB(150, 220, 255), blind = Color3.fromRGB(90, 60, 140), bleed = Color3.fromRGB(220, 40, 60),
    charm = Color3.fromRGB(255, 205, 60), poison = Color3.fromRGB(120, 220, 80), pump = Color3.fromRGB(255, 120, 30),
    drain = Color3.fromRGB(255, 250, 220), confuse = Color3.fromRGB(255, 120, 210),
}
local RARITY_COLOR = {}
for r, rgb in Config.RarityColors do RARITY_COLOR[r] = Config.Color(rgb) end

-------------------------------------------------
-- who sees the fight
-------------------------------------------------
local function stagePart()
    local arena = workspace:FindFirstChild("Arena")
    return arena and arena:FindFirstChild("Stage")
end

-- the Colosseum was built for a 34-stud stage; everything in a fight scales with the real stage size
local function arenaScale()
    local stage = stagePart()
    return stage and stage.Size.X / 34 or 1
end

local function viewers(b)
    local list, seen = {}, {}
    for _, p in b.players do
        if p.Parent then table.insert(list, p) seen[p] = true end
    end
    local stage = stagePart()
    if stage then
        for _, p in Players:GetPlayers() do
            local root = not seen[p] and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if root and (root.Position - stage.Position).Magnitude < WATCH_RADIUS then table.insert(list, p) end
        end
    end
    return list
end

local function unitView(u)
    return { uid = u.uid, name = u.name, rarity = u.rarity, icon = u.icon, hp = u.hp, maxHp = u.maxHp, atk = u.atk, spd = u.spd, status = u.statusList }
end

-------------------------------------------------
-- betting
-------------------------------------------------
local function strength(team)
    local s = 0
    for _, u in team do s += u.maxHp * u.atk * (1 + (u.spd or 5) / 20) * (1 + #u.moves * 0.04) end
    return math.max(1, s)
end

local function computeOdds(b)
    local a, c = strength(b.A), strength(b.B)
    local pA = a / (a + c)
    local function odds(p) return math.clamp(math.floor(HOUSE_EDGE / p * 100) / 100, 1.1, 6) end
    b.odds = { A = odds(pA), B = odds(1 - pA) }
end

local function betInfo(b, p)
    local pool, count = { A = 0, B = 0 }, 0
    for _, bet in b.bets do
        pool[bet.side] += bet.amount
        count += 1
    end
    local mine = b.bets[p]
    return {
        open = b.betOpen, closesIn = b.betClose and math.max(0, math.ceil(b.betClose - os.clock())) or nil,
        odds = b.odds, pool = pool, count = count, canBet = b.sides[p] == nil,
        mine = mine and { side = mine.side, amount = mine.amount, odds = mine.odds } or nil,
    }
end

local function snapshot(b, p)
    local A, B = {}, {}
    for _, u in b.A do table.insert(A, unitView(u)) end
    for _, u in b.B do table.insert(B, unitView(u)) end
    return {
        kind = b.kind, titleA = b.titleA, titleB = b.titleB, mySide = b.sides[p], A = A, B = B,
        active = { A = b.active.A and b.active.A.uid, B = b.active.B and b.active.B.uid }, round = b.round,
        bets = betInfo(b, p),
    }
end

-- send to fighters + spectators; newcomers get a snapshot first
local function emit(b, kind, data)
    for _, p in viewers(b) do
        if not b.started[p] then
            b.started[p] = true
            BattleEvent:FireClient(p, "tb_start", snapshot(b, p))
        end
        if kind then BattleEvent:FireClient(p, kind, data) end
    end
end

local function pushBets(b)
    for _, p in viewers(b) do
        if b.started[p] then BattleEvent:FireClient(p, "tb_bets", betInfo(b, p)) end
    end
end

LabAPI.requests.PlaceBet = function(player, arg)
    local b = current
    if not (b and b.betOpen) then
        LabAPI.notify(player, "Bets are closed for this fight.", "info")
        return
    end
    if typeof(arg) ~= "table" or (arg.side ~= "A" and arg.side ~= "B") or not table.find(BET_PCTS, arg.pct) then return end
    if b.sides[player] then
        LabAPI.notify(player, "You can't bet on your own fight.", "bad")
        return
    end
    if b.bets[player] then
        LabAPI.notify(player, "You already have a bet on this fight.", "info")
        return
    end
    if not b.started[player] then return end -- has to be watching
    local data = LabAPI.playerData[player.UserId]
    if not data then return end
    local amount = math.min(BET_MAX, math.floor(data.money * arg.pct))
    if amount < BET_MIN then
        LabAPI.notify(player, ("You need at least $%d to bet that much."):format(math.ceil(BET_MIN / arg.pct)), "bad")
        return
    end
    data.money -= amount
    b.bets[player] = { side = arg.side, amount = amount, odds = b.odds[arg.side] }
    local title = arg.side == "A" and b.titleA or b.titleB
    LabAPI.notify(player, ("💰 Bet $%s on %s at x%.2f. Win pays $%s."):format(LabAPI.fmt(amount), title, b.odds[arg.side], LabAPI.fmt(math.floor(amount * b.odds[arg.side]))), "good")
    LabAPI.sendState(player)
    pushBets(b)
end

local function settleBets(b, winner, refund)
    local lines = {}
    for p, bet in b.bets do
        local data = LabAPI.playerData[p.UserId]
        if data and p.Parent then
            if refund then
                data.money += bet.amount
                lines[p] = ("Your $%s bet was refunded."):format(LabAPI.fmt(bet.amount))
            elseif bet.side == winner then
                local win = math.floor(bet.amount * bet.odds)
                data.money += win
                lines[p] = ("💰 Your bet WON! +$%s (staked $%s at x%.2f)"):format(LabAPI.fmt(win), LabAPI.fmt(bet.amount), bet.odds)
                if win >= 50000 then
                    LabAPI.broadcast(("💰 %s won $%s betting at the Colosseum!"):format(p.DisplayName, LabAPI.fmt(win)), "rare", p)
                end
            else
                lines[p] = ("💸 Your bet lost. -$%s"):format(LabAPI.fmt(bet.amount))
            end
            LabAPI.sendState(p)
        end
    end
    b.bets = {}
    return lines
end

-------------------------------------------------
-- stage visuals
-------------------------------------------------
local function burst(part, color, count)
    if not (part and part.Parent) then return end
    local a = Instance.new("Attachment")
    a.Parent = part
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    pe.Color = ColorSequence.new(color)
    pe.Size = NumberSequence.new(1.2, 0)
    pe.Lifetime = NumberRange.new(0.4, 0.8)
    pe.Speed = NumberRange.new(6, 14)
    pe.SpreadAngle = Vector2.new(180, 180)
    pe.LightEmission = 1
    pe.Rate = 0
    pe.Parent = a
    pe:Emit(count)
    task.delay(1.2, function() a:Destroy() end)
end

local function bodyOf(model)
    return model and (model:FindFirstChild("Torso") or model:FindFirstChild("Head") or model.PrimaryPart)
end

local function nameTag(model, text, color)
    local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not root then return end
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(150, 22)
    bb.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("Height") or 6) * model:GetScale() + 1.5, 0) -- above the (scaled) head
    bb.MaxDistance = 160
    bb.Adornee = root
    bb.Parent = model
    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.fromScale(1, 1)
    tl.BackgroundTransparency = 1
    tl.Text = text
    tl.TextScaled = true
    tl.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
    tl.TextColor3 = color
    tl.TextStrokeTransparency = 0.3
    tl.Parent = bb
end

local function slotCFrame(b, side, index, isActive)
    local stage = stagePart()
    if not stage then return nil end
    local base = stage.CFrame * CFrame.new(0, stage.Size.Y / 2, 0)
    local sx = side == "A" and -1 or 1
    local k = arenaScale()
    local pos
    if isActive then
        pos = (base * CFrame.new(sx * 6 * k, 0, 0)).Position
    else
        pos = (base * CFrame.new(sx * 15 * k, 0, (index - 2) * 6 * k)).Position
    end
    return CFrame.lookAt(pos, pos - base.RightVector * sx)
end

local function placeModels(b)
    local stage = stagePart()
    if not stage then return end
    b.folder = Instance.new("Folder")
    b.folder.Name = "BattleUnits"
    b.folder.Parent = stage.Parent
    for _, side in { "A", "B" } do
        for i, u in b[side] do
            local ok, m = pcall(CreatureBuilder.BuildFromParts, u.parts, { name = u.name })
            if ok and m then
                m:ScaleTo(m:GetScale() * arenaScale()) -- big fighters for the big Colosseum
                m:PivotTo(slotCFrame(b, side, i, false))
                nameTag(m, u.name, RARITY_COLOR[u.rarity] or Color3.new(1, 1, 1))
                m.Parent = b.folder
                m:SetAttribute("Uid", u.uid) -- lets clients find the fighter for hit reactions
                b.models[u.uid] = m
            end
        end
    end
end

local function moveModel(b, u, cf, t)
    local m = b.models[u.uid]
    local root = m and m.PrimaryPart
    if root and cf then
        TweenService:Create(root, TweenInfo.new(t or 0.5, Enum.EasingStyle.Quad), { CFrame = cf }):Play()
    end
end

local function stepIn(b, side)
    local u = b.active[side]
    if not u then return end
    b.home[u.uid] = slotCFrame(b, side, u.index, true)
    moveModel(b, u, b.home[u.uid], 0.6)
end

local function lunge(b, from, to)
    local m, v = b.models[from.uid], b.models[to.uid]
    local root = m and m.PrimaryPart
    local home = b.home[from.uid]
    if not (root and v and v.PrimaryPart and home) then return end
    local target = v.PrimaryPart.Position
    TweenService:Create(root, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.lookAt(home.Position:Lerp(target, 0.6), target) }):Play()
    task.delay(0.24, function()
        if root.Parent then TweenService:Create(root, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { CFrame = home }):Play() end
    end)
end

local function faint(b, u)
    local m = b.models[u.uid]
    local root = m and m.PrimaryPart
    if root then
        task.delay(0.4, function()
            if root.Parent then
                TweenService:Create(root, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
                    CFrame = root.CFrame * CFrame.new(0, -8, 0) * CFrame.Angles(0, math.rad(180), 0),
                }):Play()
            end
        end)
    end
end

-------------------------------------------------
-- rules
-------------------------------------------------
local function nextAlive(team)
    for _, u in team do
        if u.hp > 0 then return u end
    end
    return nil
end

local function refreshStatus(u)
    local l = {}
    if u.st.frozen then table.insert(l, "🧊") end
    if u.st.blind then table.insert(l, "🌑") end
    if u.st.bleed > 0 then table.insert(l, "🩸") end
    if u.st.charmed then table.insert(l, "💛") end
    if u.st.poison > 0 then table.insert(l, "☠️") end
    if u.st.pump > 0 then table.insert(l, ("🔥+%d%%"):format(math.floor(u.st.pump * 100 + 0.5))) end
    if u.st.confused then table.insert(l, "🍭") end
    if u.st.shield > 0 then table.insert(l, "🛡️") end
    if u.st.dodge then table.insert(l, "🌀") end
    u.statusList = table.concat(l, " ")
end

local function aiPick(u)
    local options = {}
    for i, mv in u.moves do
        if (u.cd[i] or 0) <= 0 then
            local w = mv.kind == "attack" and (mv.power * 10) or 4
            if mv.kind == "guard" and u.hp / u.maxHp < 0.5 then w = 14 end
            table.insert(options, { i = i, w = w })
        end
    end
    local total = 0
    for _, o in options do total += o.w end
    local r = math.random() * total
    for _, o in options do
        r -= o.w
        if r <= 0 then return o.i end
    end
    return options[1] and options[1].i or 1
end

local function aiGrade()
    local r = math.random()
    if r < 0.15 then return BattleMoves.ZONES[1] elseif r < 0.5 then return BattleMoves.ZONES[2] elseif r < 0.85 then return BattleMoves.ZONES[3] end
    return BattleMoves.MISS
end

local function hps(b)
    local t = {}
    for _, side in { "A", "B" } do
        for _, u in b[side] do
            refreshStatus(u)
            t[u.uid] = { hp = u.hp, status = u.statusList }
        end
    end
    return t
end

-- one unit acting; returns a list of log lines
local function act(b, u, plan, log)
    local foe = b.active[u.side == "A" and "B" or "A"]
    if u.hp <= 0 or not foe then return end
    local mv = u.moves[plan.move]
    local g = plan.grade
    u.cd[plan.move] = mv.cooldown + 1

    if u.st.frozen then
        u.st.frozen = false
        table.insert(log, { text = ("🧊 %s is frozen solid and can't move!"):format(u.name), fx = { uid = u.uid, color = EFFECT_COLOR.freeze } })
        return
    end

    local head = ("%s %s used <b>%s</b>  [%s]"):format(mv.icon, u.name, mv.name, g.name)

    if mv.kind == "guard" then
        local gd = BattleMoves.GUARDS[mv.family]
        local q = g.mult
        local bits = {}
        if gd.gamble then
            if math.random() < 0.5 then gd = { heal = 0.3 } else gd = { dodge = true } end
        end
        if gd.heal then
            local before = u.hp
            u.hp = math.min(u.maxHp, u.hp + math.floor(u.maxHp * gd.heal * q))
            table.insert(bits, ("+%d HP"):format(u.hp - before))
        end
        if gd.cleanse then
            u.st.bleed, u.st.poison, u.st.blind, u.st.charmed, u.st.confused = 0, 0, false, false, false
            table.insert(bits, "cleansed")
        end
        if gd.shield then
            u.st.shield = math.min(0.9, gd.shield * q)
            u.st.counter = gd.counter or 0
            table.insert(bits, ("blocks %d%% of the next hit"):format(math.floor(u.st.shield * 100)))
        end
        if gd.dodge then u.st.dodge = true table.insert(bits, "will dodge the next hit") end
        if gd.pump then
            u.st.pump = math.min(0.45, u.st.pump + gd.pump * q)
            table.insert(bits, "attack up")
        end
        table.insert(log, { text = head .. " · " .. table.concat(bits, ", "), fx = { uid = u.uid, color = Color3.fromRGB(120, 220, 255) }, guard = u.uid })
        return
    end

    -- attacks
    if u.st.confused then
        u.st.confused = false
        if math.random() < 0.5 then
            local d = math.max(1, math.floor(u.atk * 0.5))
            u.hp = math.max(0, u.hp - d)
            table.insert(log, { text = ("🍭 %s is confused and bonks itself for %d!"):format(u.name, d), fx = { uid = u.uid, color = EFFECT_COLOR.confuse } })
            return
        end
    end
    if u.st.blind then
        u.st.blind = false
        if math.random() < 0.5 then
            table.insert(log, { text = head .. " · 🌑 blinded, it MISSED!", from = u.uid, to = foe.uid })
            return
        end
    end
    if foe.st.dodge then
        foe.st.dodge = false
        table.insert(log, { text = head .. (" · 🌀 %s dodged it!"):format(foe.name), from = u.uid, to = foe.uid, fx = { uid = foe.uid, color = Color3.fromRGB(200, 200, 255) } })
        return
    end

    local dmg = u.atk * DAMAGE_SCALE * mv.power * g.mult * (1 + u.st.pump) * (0.9 + math.random() * 0.2)
    local tags = {}
    if u.crit and u.crit > 0 and math.random() < u.crit then dmg *= 1.5 table.insert(tags, "CRIT") end
    if u.st.charmed then u.st.charmed = false dmg *= 0.5 table.insert(tags, "charmed, half damage") end
    local blocked = 0
    if foe.st.shield > 0 then
        blocked = dmg * foe.st.shield
        dmg -= blocked
        foe.st.shield = 0
        table.insert(tags, "blocked " .. math.floor(blocked))
    end
    dmg = math.max(1, math.floor(dmg))
    foe.hp = math.max(0, foe.hp - dmg)
    local line = head .. (" · <b>%d</b> damage"):format(dmg)
    if #tags > 0 then line ..= " (" .. table.concat(tags, ", ") .. ")" end

    if foe.st.counter and foe.st.counter > 0 and blocked > 0 and foe.hp > 0 then
        local c = math.max(1, math.floor(blocked * foe.st.counter))
        u.hp = math.max(0, u.hp - c)
        line ..= (" · 🛡️ countered for %d"):format(c)
        foe.st.counter = 0
    end
    if u.lifesteal and u.lifesteal > 0 then
        local h = math.floor(dmg * u.lifesteal)
        if h > 0 then u.hp = math.min(u.maxHp, u.hp + h) line ..= (" · +%d HP"):format(h) end
    end

    -- side effect
    local fxColor = Color3.fromRGB(255, 90, 90)
    local fx = BattleMoves.EFFECTS[mv.family]
    if fx and math.random() < mv.chance then
        local id = fx.id
        fxColor = EFFECT_COLOR[id] or fxColor
        if id == "pump" then
            u.st.pump = math.min(0.45, u.st.pump + 0.15)
            line ..= " · 🔥 attack up"
        elseif id == "drain" then
            local before = u.hp
            u.hp = math.min(u.maxHp, u.hp + math.floor(dmg * 0.35))
            line ..= (" · ✨ drained %d HP"):format(u.hp - before)
        elseif foe.hp > 0 then
            if id == "freeze" then foe.st.frozen = true line ..= " · 🧊 FROZEN"
            elseif id == "blind" then foe.st.blind = true line ..= " · 🌑 blinded"
            elseif id == "bleed" then foe.st.bleed = 3 line ..= " · 🩸 bleeding"
            elseif id == "charm" then foe.st.charmed = true line ..= " · 💛 charmed"
            elseif id == "poison" then foe.st.poison = 3 line ..= " · ☠️ poisoned"
            elseif id == "confuse" then foe.st.confused = true line ..= " · 🍭 confused"
            end
        end
    end
    if foe.hp <= 0 then line ..= (" · <b>%s fainted!</b>"):format(foe.name) end
    table.insert(log, { text = line, from = u.uid, to = foe.uid, grade = g.name, fx = { uid = foe.uid, color = fxColor, big = g.name == "PERFECT" }, ko = foe.hp <= 0 and foe.uid or nil, selfKo = u.hp <= 0 and u.uid or nil })
end

local function endOfRound(b, log)
    for _, side in { "A", "B" } do
        local u = b.active[side]
        if u and u.hp > 0 then
            for _, kind in { "bleed", "poison" } do
                if u.st[kind] > 0 then
                    local d = math.max(1, math.floor(u.maxHp * (kind == "bleed" and 0.05 or 0.06)))
                    u.hp = math.max(0, u.hp - d)
                    u.st[kind] -= 1
                    table.insert(log, { text = ("%s %s takes %d %s damage%s"):format(kind == "bleed" and "🩸" or "☠️", u.name, d, kind, u.hp <= 0 and (" and fainted!") or ""), fx = { uid = u.uid, color = EFFECT_COLOR[kind] }, ko = u.hp <= 0 and u.uid or nil })
                end
            end
        end
        if u then
            for i, v in u.cd do if v > 0 then u.cd[i] = v - 1 end end
        end
    end
end

-------------------------------------------------
-- player input
-------------------------------------------------
LabAPI.requests.BattleMove = function(player, idx)
    local b = current
    if not (b and b.phase == "choose") then return end
    local side = b.sides[player]
    local plan = side and b.plans[side]
    local u = side and b.active[side]
    if not (plan and u) or plan.move then return end
    idx = tonumber(idx)
    if not idx or not u.moves[idx] or (u.cd[idx] or 0) > 0 then return end
    plan.move = idx
    plan.at = os.clock()
end

LabAPI.requests.BattleTap = function(player)
    local b = current
    if not (b and b.phase == "choose") then return end
    local side = b.sides[player]
    local plan = side and b.plans[side]
    if not (plan and plan.move and plan.at) or plan.grade then return end
    local elapsed = os.clock() - plan.at
    if elapsed > BattleMoves.BAR_TIMEOUT + 0.5 then
        plan.grade = BattleMoves.MISS
    else
        plan.grade = BattleMoves.grade(BattleMoves.needle(elapsed), plan.zone)
    end
end

-------------------------------------------------
-- the fight
-------------------------------------------------
local function prepare(u, side, i)
    u.side = side
    u.index = i
    u.moves = BattleMoves.movesFor(u.parts or {})
    u.cd = {}
    u.st = { frozen = false, blind = false, bleed = 0, charmed = false, poison = 0, pump = 0, confused = false, shield = 0, counter = 0, dodge = false }
    refreshStatus(u)
end

local function controller(b, side)
    for p, s in b.sides do
        if s == side and p.Parent then return p end
    end
    return nil
end

local function runTurnBattle(o)
    local b = {
        kind = o.kind, players = o.players, sides = o.sides, A = o.A, B = o.B,
        titleA = o.titleA, titleB = o.titleB, active = {}, models = {}, home = {}, started = {}, round = 0,
        bets = {}, betOpen = true,
    }
    for _, side in { "A", "B" } do
        for i, u in b[side] do prepare(u, side, i) end
        b.active[side] = nextAlive(b[side])
    end
    computeOdds(b)
    current = b
    placeModels(b)
    -- trainers stand at their corner of the stage, out of the camera's way
    local stage = stagePart()
    if stage then
        for p, side in b.sides do
            local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local spot = (stage.CFrame * CFrame.new(side == "A" and -19 or 19, stage.Size.Y / 2 + 3, 13)).Position
                p.Character:PivotTo(CFrame.lookAt(spot, Vector3.new(stage.Position.X, spot.Y, stage.Position.Z)))
            end
        end
    end
    task.wait(0.3)
    stepIn(b, "A")
    stepIn(b, "B")
    emit(b, nil)
    task.wait(2)

    -- betting window: only worth waiting for when somebody other than the fighters is watching
    local watchers = 0
    for _, p in viewers(b) do
        if not b.sides[p] then watchers += 1 end
    end
    if watchers > 0 then
        b.betClose = os.clock() + BET_WINDOW
        while os.clock() < b.betClose do
            emit(b, nil) -- picks up spectators who just walked in
            pushBets(b)
            task.wait(1)
        end
        b.betClose = nil
    end

    local winner
    while not winner do
        b.round += 1
        if b.round > MAX_ROUNDS then break end
        if b.round == 2 and b.betOpen then
            b.betOpen = false
            pushBets(b)
        end
        -- 1) choose
        b.plans = {}
        for _, side in { "A", "B" } do
            local u = b.active[side]
            local plan = { zone = 0.25 + math.random() * 0.6 }
            b.plans[side] = plan
            local p = controller(b, side)
            if p then
                local moves = {}
                for i, mv in u.moves do
                    moves[i] = { name = mv.name, icon = mv.icon, kind = mv.kind, label = mv.label or (mv.kind == "guard" and "Guard" or "Strike"), desc = mv.desc, cd = u.cd[i] or 0, family = mv.family }
                end
                BattleEvent:FireClient(p, "tb_turn", { round = b.round, uid = u.uid, moves = moves, zone = plan.zone, time = BattleMoves.CHOOSE_TIME })
            else
                plan.move = aiPick(u)
                plan.grade = aiGrade()
            end
        end
        b.phase = "choose"
        emit(b, "tb_wait", { round = b.round })
        local deadline = os.clock() + BattleMoves.CHOOSE_TIME
        while true do
            local ready = true
            for _, side in { "A", "B" } do
                local plan = b.plans[side]
                if plan.move and not plan.grade and os.clock() - plan.at > BattleMoves.BAR_TIMEOUT + 0.6 then
                    plan.grade = BattleMoves.MISS
                end
                if not (plan.move and plan.grade) then ready = false end
            end
            if ready or os.clock() > deadline then break end
            task.wait(0.1)
        end
        b.phase = "resolve"
        for _, side in { "A", "B" } do
            local plan = b.plans[side]
            if not plan.move then plan.move = aiPick(b.active[side]) plan.afk = true end
            if not plan.grade then plan.grade = BattleMoves.MISS end
        end

        -- 2) resolve: Quick moves first, then speed
        local order = { b.active.A, b.active.B }
        table.sort(order, function(x, y)
            local px = x.moves[b.plans[x.side].move].priority and 1 or 0
            local py = y.moves[b.plans[y.side].move].priority and 1 or 0
            if px ~= py then return px > py end
            if x.spd ~= y.spd then return x.spd > y.spd end
            return x.side == "A"
        end)
        local log = {}
        for _, u in order do
            act(b, u, b.plans[u.side], log)
            if (b.active.A.hp <= 0) or (b.active.B.hp <= 0) then break end
        end
        endOfRound(b, log)

        -- 3) play it out, one line at a time
        for _, ev in log do
            emit(b, "tb_line", { text = ev.text, grade = ev.grade, hps = hps(b) })
            local from = ev.from and (b.active.A.uid == ev.from and b.active.A or b.active.B)
            local to = ev.to and (b.active.A.uid == ev.to and b.active.A or b.active.B)
            if from and to then lunge(b, from, to) end
            if ev.fx then
                local m = b.models[ev.fx.uid]
                task.delay(0.18, burst, bodyOf(m), ev.fx.color, ev.fx.big and 40 or 18)
            end
            task.wait(LINE_DELAY)
        end

        -- 4) faints and replacements
        for _, side in { "A", "B" } do
            local u = b.active[side]
            if u.hp <= 0 then
                faint(b, u)
                local nextU = nextAlive(b[side])
                b.active[side] = nextU
                if nextU then
                    task.wait(0.6)
                    stepIn(b, side)
                    emit(b, "tb_enter", { side = side, uid = nextU.uid, text = ("%s sends out %s!"):format(side == "A" and b.titleA or b.titleB, nextU.name), hps = hps(b) })
                    task.wait(1)
                end
            end
        end
        local aAlive, bAlive = b.active.A ~= nil, b.active.B ~= nil
        if not aAlive and not bAlive then winner = "B" -- a double KO goes to the defender
        elseif not aAlive then winner = "B"
        elseif not bAlive then winner = "A" end
    end

    if not winner then
        local function pct(team)
            local s, m = 0, 0
            for _, u in team do s += u.hp m += u.maxHp end
            return m > 0 and s / m or 0
        end
        winner = pct(b.A) >= pct(b.B) and "A" or "B"
        emit(b, "tb_line", { text = "⏱️ Time! The team with the most HP left wins.", hps = hps(b) })
        task.wait(1.5)
    end

    b.phase = "done"
    b.betOpen = false
    local ok, results = pcall(o.onFinish, winner)
    results = ok and results or {}
    local betLines = settleBets(b, winner, false)
    local winTitle = winner == "A" and b.titleA or b.titleB
    local sent = {}
    for _, p in viewers(b) do
        sent[p] = true
        local r = results[p]
        if r then
            BattleEvent:FireClient(p, "tb_end", { won = r.won, text = r.text, winner = winTitle })
        else
            BattleEvent:FireClient(p, "tb_end", { spectator = true, text = betLines[p] or "wins the battle!", winner = winTitle })
        end
    end
    for p, line in betLines do -- bettors who wandered off still hear how it went
        if not sent[p] and p.Parent then LabAPI.notify(p, line .. " (" .. winTitle .. " won)", "info") end
    end
    for _, p in b.players do
        if p.Parent then LabAPI.sendState(p) end
    end
    current = nil
    lastBattleEnd = os.clock()
    task.wait(3)
    if b.folder then b.folder:Destroy() end
end

function LabAPI.runTurnBattle(o)
    local ok, err = pcall(runTurnBattle, o)
    if not ok then
        local b = current
        current = nil
        lastBattleEnd = os.clock()
        if b then
            settleBets(b, nil, true) -- something broke: everyone gets their stake back
            if b.folder then b.folder:Destroy() end
            for _, p in viewers(b) do
                if not b.sides[p] then BattleEvent:FireClient(p, "tb_end", { spectator = true, text = "The fight was cancelled. Bets refunded.", winner = "" }) end
            end
        end
        error(err, 0)
    end
end

-- exhibitions: keep the Colosseum busy while people are hanging around it
task.spawn(function()
    LabAPI.waitReady()
    while true do
        task.wait(5)
        local stage = stagePart()
        if stage and not current and LabAPI.startExhibition and not LabAPI.arenaBusy() and os.clock() - lastBattleEnd > EXHIBITION_IDLE then
            local levels, n = 0, 0
            for _, p in Players:GetPlayers() do
                local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                local data = LabAPI.playerData[p.UserId]
                if root and data and (root.Position - stage.Position).Magnitude < WATCH_RADIUS then
                    levels += data.arenaLevel or 1
                    n += 1
                end
            end
            if n > 0 then
                local level = math.clamp(math.floor(levels / n) + math.random(-1, 1), 1, 9)
                if LabAPI.startExhibition(level) then
                    lastBattleEnd = os.clock() -- don't double-start while it spins up
                end
            end
        end
    end
end)

LabAPI.currentBattle = function() return current end

-------------------------------------------------
-- Betting board in the hub: shows the live fight + odds, and "Watch & Bet" seats you in the stands
-------------------------------------------------
local function spectatorSeat()
    local stage = stagePart()
    if not stage then return nil end
    local k = arenaScale()
    -- front stands (the side the battle camera looks from), on top of whatever tier is there
    local above = (stage.CFrame * CFrame.new(0, 60 * k, 34 * k)).Position
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Include
    rp.FilterDescendantsInstances = { workspace.Arena }
    local hit = workspace:Raycast(above, Vector3.new(0, -120 * k, 0), rp)
    local pos = hit and hit.Position or (stage.Position + Vector3.new(0, 4, 0))
    return CFrame.lookAt(pos + Vector3.new(0, 3.5, 0), Vector3.new(stage.Position.X, pos.Y + 3.5, stage.Position.Z))
end

local function watchAndBet(player)
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local seat = spectatorSeat()
    if not (root and seat) then return end
    if current and current.sides[player] then return end
    player.Character:PivotTo(seat)
    if current then
        task.delay(0.5, function()
            if current then emit(current, nil) pushBets(current) end -- show the fight + bet panel right away
        end)
        LabAPI.notify(player, current.betOpen and "🎲 Bets are open! Pick a side on the right." or "👀 This fight is already going. Bets open again for the next one!", "info")
    else
        LabAPI.notify(player, "🎲 Grab a seat! A show match starts in a few seconds. Bet on who wins.", "info")
    end
end
LabAPI.requests.WatchBets = watchAndBet

local board = workspace:FindFirstChild("CentralHub") and workspace.CentralHub:FindFirstChild("BetBoard")
if board then
    local frame = board:FindFirstChild("BoardFrame")
    local prompt = frame and frame:FindFirstChild("WatchPrompt")
    if prompt then prompt.Triggered:Connect(watchAndBet) end
    local screen = frame and frame:FindFirstChild("Screen")
    task.spawn(function()
        while true do
            task.wait(1)
            local b = current
            if screen then
                if b then
                    screen.Match.Text = ("%s <font color='#9A8CC2'>vs</font> %s"):format(b.titleA or "A", b.titleB or "B")
                    screen.Odds.Text = b.odds and ("x%.2f  ·  x%.2f"):format(b.odds.A, b.odds.B) or ""
                    if b.betOpen then
                        local left = b.betClose and math.max(0, math.ceil(b.betClose - os.clock()))
                        screen.Status.Text = left and ("🟢 BETS OPEN · closes in %ds"):format(left) or "🟢 BETS OPEN until round 2"
                    else
                        screen.Status.Text = ("⚔️ Round %d · bets closed"):format(b.round)
                    end
                else
                    screen.Match.Text = "No fight right now"
                    screen.Odds.Text = ""
                    screen.Status.Text = "Tap <b>Watch &amp; Bet</b> to grab a seat. A show match starts soon!"
                end
            end
            -- the Bets board shows when bets are open; no server-wide pop-up every fight
        end
    end)
end
