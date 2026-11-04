--[[
    CreatureAnimator — brings every creature in the world to life, on this client only.

    Creatures are built on the server as an anchored invisible Root with each part welded to it
    (see CreatureBuilder). Here every root weld is swapped for a Motor6D, grouped by the part's
    Slot attribute, and the motors are driven each frame:
      - idle: breathing, a soft bob, head wobble and nod, arms swaying
      - moving (wandering or a battle lunge): waddle, hop and forward lean
      - hit (HitAt attribute, set by BattleClient): knock back, shake and a red flash
    Each creature also gets a particle effect for its torso family, stronger at higher rarity,
    and Legendary+ Mewing heads (the flaming skull) burn with real fire.
    Nothing here touches the server: saving, wings, growth and battles keep working as before.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local camera = workspace.CurrentCamera
local ANIM_RANGE = 140 -- studs from the camera; creatures further away stay still and their effects pause

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local function famColor(family)
    local ing = Config.Ingredients[family]
    return ing and Config.Color(ing.color) or Color3.fromRGB(220, 220, 220)
end

local function rank(rarity) return Config.RarityRank[rarity] or 1 end

-------------------------------------------------
-- Family effects
-------------------------------------------------
-- texture, rise speed, lifetime, size (x creature height), spread, extra color
local STYLES = {
    Sigma   = { tex = SPARKLE, speed = 0.6, life = 1.6, size = 0.10, spread = 180 },
    Ohio    = { tex = SMOKE,   speed = 0.8, life = 2.0, size = 0.22, spread = 30, transparency = 0.65 },
    Skibidi = { tex = FIRE,    speed = 2.2, life = 0.7, size = 0.07, spread = 25 },
    Rizz    = { tex = SPARKLE, speed = 1.0, life = 1.4, size = 0.12, spread = 180, second = Color3.fromRGB(255, 120, 200) },
    Fanum   = { tex = SPARKLE, speed = 1.4, life = 1.6, size = 0.08, spread = 20 },
    Mewing  = { tex = SPARKLE, speed = 0.5, life = 1.8, size = 0.09, spread = 180, second = Color3.fromRGB(230, 235, 255) },
    Aura    = { tex = SPARKLE, speed = 0.4, life = 2.2, size = 0.14, spread = 180, second = Color3.fromRGB(255, 205, 60) },
    Delulu  = { tex = SPARKLE, speed = 0.7, life = 2.0, size = 0.12, spread = 180, second = Color3.fromRGB(140, 230, 255) },
}

local function emitter(part, offset, props)
    local a = Instance.new("Attachment")
    a.Name = "FxAttachment"
    a.Position = offset
    a.Parent = part
    local pe = Instance.new("ParticleEmitter")
    pe.Name = "CreatureFx"
    pe.LightEmission = 0.6
    pe.LockedToPart = false
    for k, v in props do pe[k] = v end
    pe.Parent = a
    return pe
end

local function familyFx(part, family, rarity, h)
    local s = STYLES[family]
    if not s then return nil end
    local c = famColor(family)
    local r = rank(rarity)
    return emitter(part, Vector3.new(0, part.Size.Y * 0.2, 0), {
        Texture = s.tex,
        Color = ColorSequence.new(c, s.second or c),
        Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.2, s.size * h),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Transparency = NumberSequence.new(s.transparency or 0.15, 1),
        Lifetime = NumberRange.new(s.life * 0.7, s.life),
        Rate = 1.5 + r * 1.2, -- Common 2.7/s up to Mythic 8.7/s
        Speed = NumberRange.new(s.speed * 0.6, s.speed),
        SpreadAngle = Vector2.new(s.spread, s.spread),
        Acceleration = Vector3.new(0, s.speed * 0.6, 0),
        RotSpeed = NumberRange.new(-60, 60),
        Rotation = NumberRange.new(0, 360),
    })
end

local function skullFire(head, h)
    local top = Vector3.new(0, head.Size.Y * 0.35, 0)
    local flames = emitter(head, top, {
        Texture = FIRE,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 150)),
            ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 140, 30)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 40, 20)),
        }),
        Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.18 * h),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Transparency = NumberSequence.new(0.1, 1),
        Lifetime = NumberRange.new(0.4, 0.8),
        Rate = 40,
        Speed = NumberRange.new(1.5, 3),
        SpreadAngle = Vector2.new(15, 15),
        Acceleration = Vector3.new(0, 3, 0),
        RotSpeed = NumberRange.new(-90, 90),
        Rotation = NumberRange.new(0, 360),
        LightEmission = 1,
    })
    local embers = emitter(head, top, {
        Texture = SPARKLE,
        Color = ColorSequence.new(Color3.fromRGB(255, 170, 60)),
        Size = NumberSequence.new(0.05 * h, 0),
        Lifetime = NumberRange.new(0.8, 1.4),
        Rate = 8,
        Speed = NumberRange.new(2, 4),
        SpreadAngle = Vector2.new(35, 35),
        Acceleration = Vector3.new(0, 1.5, 0),
        LightEmission = 1,
    })
    local glow = Instance.new("PointLight")
    glow.Name = "SkullGlow"
    glow.Color = Color3.fromRGB(255, 140, 40)
    glow.Range = 6 * h / 4
    glow.Brightness = 1.6
    glow.Parent = head
    return { flames, embers }
end

-------------------------------------------------
-- Rigging
-------------------------------------------------
local rigs = {} -- model -> rig

local function scaled(cf, k) return CFrame.new(cf.Position * k) * cf.Rotation end

-- bounding box of a set of parts in root space
local function bounds(rootCF, list)
    local mn, mx = Vector3.one * math.huge, -Vector3.one * math.huge
    for _, p in list do
        local cf = rootCF:ToObjectSpace(p.CFrame)
        local hs = p.Size / 2
        for _, sx in { -1, 1 } do
            for _, sy in { -1, 1 } do
                for _, sz in { -1, 1 } do
                    local v = cf * Vector3.new(hs.X * sx, hs.Y * sy, hs.Z * sz)
                    mn = mn:Min(v)
                    mx = mx:Max(v)
                end
            end
        end
    end
    return mn, mx
end

-- where each slot bends: legs and arms hang from their top, the torso and head sit on their bottom
local function pivotFor(slot, mn, mx)
    local c = (mn + mx) / 2
    if slot == "Legs" or slot == "Arms" or slot == "Weapon" then
        return CFrame.new(c.X, mx.Y, c.Z)
    end
    return CFrame.new(c.X, mn.Y, c.Z)
end

local function rootWeld(p, root)
    for _, w in p:GetChildren() do
        if w:IsA("WeldConstraint") and w.Enabled and w.Part0 == root and w.Part1 == p then return w end
    end
    return nil
end

local function attach(rig, p)
    if rig.parts[p] then return end
    local w = rootWeld(p, rig.root)
    if not w then return end -- wings and details welded to other parts follow those parts
    local slot = p:GetAttribute("Slot") or "Torso"
    local g = rig.groups[slot]
    if not g then
        local mn, mx = bounds(rig.root.CFrame, { p })
        g = { pivot = pivotFor(slot, mn, mx), motors = {} }
        rig.groups[slot] = g
    end
    local m = Instance.new("Motor6D")
    m.Name = "AnimJoint"
    m.Part0 = rig.root
    m.Part1 = p
    m.C0 = g.pivot
    m.C1 = rig.root.CFrame:ToObjectSpace(p.CFrame):Inverse() * g.pivot
    m.Parent = p
    w.Enabled = false
    rig.parts[p] = { motor = m, weld = w }
    table.insert(g.motors, m)
end

local function addFx(rig)
    local h = rig.height
    local torso = rig.model:FindFirstChild("Torso")
    if torso and torso:IsA("BasePart") then
        local pe = familyFx(torso, torso:GetAttribute("Family"), torso:GetAttribute("Rarity"), h)
        if pe then table.insert(rig.fx, pe) end
    end
    local head = rig.model:FindFirstChild("Head")
    if head and head:IsA("BasePart") and rank(head:GetAttribute("Rarity")) >= 5 then
        if head:GetAttribute("Family") == "Mewing" then
            for _, pe in skullFire(head, h) do table.insert(rig.fx, pe) end
        else
            local pe = familyFx(head, head:GetAttribute("Family"), head:GetAttribute("Rarity"), h)
            if pe then table.insert(rig.fx, pe) end
        end
    end
end

local function flash(model)
    local hl = Instance.new("Highlight")
    hl.Name = "HitFlash"
    hl.FillColor = Color3.fromRGB(255, 60, 60)
    hl.OutlineTransparency = 1
    hl.FillTransparency = 0.25
    hl.DepthMode = Enum.HighlightDepthMode.Occluded
    hl.Parent = model
    TweenService:Create(hl, TweenInfo.new(0.35), { FillTransparency = 1 }):Play()
    task.delay(0.4, function() hl:Destroy() end)
end

local function unrig(model)
    local rig = rigs[model]
    if not rig then return end
    rigs[model] = nil
    for _, c in rig.conns do c:Disconnect() end
    for p, j in rig.parts do
        if j.motor.Parent then j.motor:Destroy() end
        if j.weld.Parent then j.weld.Enabled = true end
    end
end

local function rig(model)
    if rigs[model] then return end
    local root = model.PrimaryPart
    if not root then return end
    local r = {
        model = model,
        root = root,
        groups = {},
        parts = {},
        fx = {},
        conns = {},
        phase = math.random() * 10,
        rootSize = root.Size.X,
        lastPos = root.Position,
        speed = 0,
        hitAt = -1,
        active = true,
    }
    r.height = (model:GetAttribute("Height") or 4) * root.Size.X
    rigs[model] = r

    -- group pivots come from each slot's full box, so a head bends at its neck, not its middle
    local bySlot = {}
    for _, p in model:GetChildren() do
        if p:IsA("BasePart") and p ~= root and rootWeld(p, root) then
            local slot = p:GetAttribute("Slot") or "Torso"
            bySlot[slot] = bySlot[slot] or {}
            table.insert(bySlot[slot], p)
        end
    end
    for slot, list in bySlot do
        local mn, mx = bounds(root.CFrame, list)
        r.groups[slot] = { pivot = pivotFor(slot, mn, mx), motors = {} }
    end
    -- weapons swing with the arms when there are arms to hold them
    if r.groups.Weapon and r.groups.Arms then r.groups.Weapon.pivot = r.groups.Arms.pivot end
    for _, list in bySlot do
        for _, p in list do attach(r, p) end
    end
    addFx(r)

    -- parts that stream in later join their slot
    table.insert(r.conns, model.ChildAdded:Connect(function(p)
        if p:IsA("BasePart") then task.defer(attach, r, p) end
    end))
    -- growth potions and battles rescale the model on the server: keep the joints in proportion
    table.insert(r.conns, root:GetPropertyChangedSignal("Size"):Connect(function()
        local k = root.Size.X / r.rootSize
        if math.abs(k - 1) < 1e-4 then return end
        r.rootSize = root.Size.X
        r.height *= k
        for _, g in r.groups do
            g.pivot = scaled(g.pivot, k)
            for _, m in g.motors do
                m.C0 = scaled(m.C0, k)
                m.C1 = scaled(m.C1, k)
            end
        end
    end))
    table.insert(r.conns, model:GetAttributeChangedSignal("HitAt"):Connect(function()
        r.hitAt = os.clock()
        flash(model)
    end))
    table.insert(r.conns, model.AncestryChanged:Connect(function(_, parent)
        if not parent then unrig(model) end
    end))
end

local function consider(inst)
    if not (inst:IsA("Model") and inst:GetAttribute("IsCreature")) then return end
    -- let the rest of the model arrive before rigging it
    task.delay(0.2, function()
        if inst.Parent and inst:IsDescendantOf(workspace) then rig(inst) end
    end)
end

for _, d in workspace:GetDescendants() do consider(d) end
workspace.DescendantAdded:Connect(consider)

-------------------------------------------------
-- Motion
-------------------------------------------------
local IDENTITY = CFrame.identity
local sin, abs, clamp = math.sin, math.abs, math.clamp

local function setGroup(g, chain, own)
    if not g then return end
    local t = g.pivot:Inverse() * chain * g.pivot * own
    for _, m in g.motors do m.Transform = t end
end

local function still(r)
    for _, g in r.groups do
        for _, m in g.motors do m.Transform = IDENTITY end
    end
    for _, pe in r.fx do pe.Enabled = false end
end

RunService.Stepped:Connect(function(_, dt)
    local now = os.clock()
    local camPos = camera.CFrame.Position
    for model, r in rigs do
        local root = r.root
        local pos = root.Position
        local near = (pos - camPos).Magnitude < ANIM_RANGE
        if not near then
            if r.active then
                r.active = false
                still(r)
            end
            r.lastPos = pos
            continue
        end
        if not r.active then
            r.active = true
            for _, pe in r.fx do pe.Enabled = true end
        end

        -- speed along the ground, smoothed so a stop or start eases in
        local flat = Vector3.new(pos.X - r.lastPos.X, 0, pos.Z - r.lastPos.Z).Magnitude / math.max(dt, 1 / 240)
        r.lastPos = pos
        r.speed += (flat - r.speed) * clamp(dt * 8, 0, 1)
        local walk = clamp(r.speed / 4, 0, 1)
        local lunge = clamp((r.speed - 12) / 20, 0, 1)

        local h = r.height
        local t = now + r.phase
        local step = t * 9

        -- whole body (pivots at the feet)
        local bob = sin(t * 2) * 0.02 * h * (1 - walk) + abs(sin(step)) * 0.07 * h * walk
        local roll = sin(t * 1.1) * 0.02 + sin(step) * 0.10 * walk
        local lean = -(0.10 * walk + 0.30 * lunge)
        local shake = 0
        local age = now - r.hitAt
        if age < 0.45 then
            local f = 1 - age / 0.45
            lean += 0.35 * f -- knocked back
            shake = sin(age * 70) * 0.06 * h * f
        end
        local body = CFrame.new(shake, bob, 0) * CFrame.Angles(lean, 0, roll)

        -- torso breathes, and carries the head and arms with it
        local torsoG = r.groups.Torso
        local breathe = CFrame.Angles(sin(t * 2) * 0.03, 0, sin(t * 1.3) * 0.02)
        local upper = body
        if torsoG then upper = body * torsoG.pivot * breathe * torsoG.pivot:Inverse() end

        setGroup(r.groups.Legs, body, IDENTITY)
        setGroup(torsoG, body, breathe)
        setGroup(r.groups.Head, upper, CFrame.Angles(
            sin(t * 2.3 + 1) * 0.07 + sin(step) * 0.05 * walk,
            sin(t * 0.9) * 0.15,
            sin(t * 1.7) * 0.10
        ))
        local swing = CFrame.Angles(sin(t * 2) * 0.08 + sin(step) * 0.30 * walk - 0.4 * lunge, 0, 0)
        setGroup(r.groups.Arms, upper, swing)
        setGroup(r.groups.Weapon, upper, swing)
    end
end)
