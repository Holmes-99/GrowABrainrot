--[[
    CreatureBuilder — builds a creature Model out of its parts.

    parts = { Head = { family, rarity, shiny }, Torso = {...}, Arms = {...}, Legs = {...}, Weapon = {...} }
    Any slot may be missing. opts.only = "Head" renders just that one part (used for part icons).

    The model has an anchored, invisible "Root" at ground level (PrimaryPart).
    Every other part is welded to it, so moving Root moves the creature.
    Front of the creature faces Root's -Z (LookVector).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local PartMeshes = ReplicatedStorage:FindFirstChild("PartMeshes")

local CreatureBuilder = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(22, 18, 28)
local GOLD = Color3.fromRGB(255, 205, 60)
local SKIN = Color3.fromRGB(238, 203, 172)
local NAVY = Color3.fromRGB(28, 30, 46)
local PORCELAIN = Color3.fromRGB(240, 242, 246)
local VOID = Color3.fromRGB(38, 26, 58)
local SILVER = Color3.fromRGB(200, 205, 215)

local function famColor(family)
    local ing = Config.Ingredients[family]
    return ing and Config.Color(ing.color) or Color3.fromRGB(200, 200, 200)
end
local function rank(rarity) return Config.RarityRank[rarity] or 1 end
local function rarityColor(rarity)
    local rgb = Config.RarityColors[rarity]
    return rgb and Config.Color(rgb) or WHITE
end

function CreatureBuilder.BuildFromParts(parts, opts)
    opts = opts or {}
    local only = opts.only

    -- overall size from the average part rarity
    local total, n = 0, 0
    for _, p in parts do
        total += Config.PartSize[p.rarity] or 1
        n += 1
    end
    local u = (n > 0 and total / n or 1) * (opts.scale or 1)

    local model = Instance.new("Model")
    model.Name = opts.name or "Creature"
    local root = Instance.new("Part")
    root.Name = "Root"
    root.Size = Vector3.new(1, 1, 1)
    root.Transparency = 1
    root.Anchored = true
    root.CanCollide = false
    root.CanQuery = false
    root.CanTouch = false
    root.CFrame = CFrame.new()
    root.Parent = model
    model.PrimaryPart = root

    local current -- slot being built (for opts.only filtering)
    -- slot / family / rarity tags let the client animate and decorate each body part
    local function tag(p, slot)
        local info = slot and parts[slot]
        if not info then return end
        p:SetAttribute("Slot", slot)
        p:SetAttribute("Family", info.family)
        p:SetAttribute("Rarity", info.rarity)
    end
    local function add(props)
        if only and current ~= only then return nil end
        local p = Instance.new("Part")
        p.Anchored = false
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.Massless = true
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth
        p.Material = Enum.Material.SmoothPlastic
        for k, v in props do p[k] = v end
        p.Parent = model
        local w = Instance.new("WeldConstraint")
        w.Part0 = root
        w.Part1 = p
        w.Parent = p
        tag(p, current)
        return p
    end
    local function S(v) return v * u end
    local function V(x, y, z) return Vector3.new(x * u, y * u, z * u) end
    local function at(x, y, z) return CFrame.new(x * u, y * u, z * u) end
    local function ball(name, size, cf, color, extra)
        local props = { Name = name, Shape = Enum.PartType.Ball, Size = size, CFrame = cf, Color = color }
        for k, v in extra or {} do props[k] = v end
        return add(props)
    end
    local function block(name, size, cf, color, extra)
        local props = { Name = name, Size = size, CFrame = cf, Color = color }
        for k, v in extra or {} do props[k] = v end
        return add(props)
    end
    local function cyl(name, len, dia, cf, color, extra) -- axis along cf's Y
        local props = { Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, dia, dia), CFrame = cf * CFrame.Angles(0, 0, math.rad(90)), Color = color }
        for k, v in extra or {} do props[k] = v end
        return add(props)
    end
    local function wedge(name, size, cf, color, extra)
        local p = block(name, size, cf, color, extra)
        if p then
            local m = Instance.new("SpecialMesh")
            m.MeshType = Enum.MeshType.Wedge
            m.Parent = p
        end
        return p
    end
    local function neon(extra)
        local e = { Material = Enum.Material.Neon }
        for k, v in extra or {} do e[k] = v end
        return e
    end

    -- rarity dressing: bands from Rare, sparkles from Epic, light from Legendary, aura at Mythic
    local function sparkle(part, colorSeq, rate, size)
        if not part then return end
        local a = Instance.new("Attachment")
        a.Parent = part
        local pe = Instance.new("ParticleEmitter")
        pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        pe.Color = colorSeq
        pe.Size = NumberSequence.new(size or S(0.35), 0)
        pe.Lifetime = NumberRange.new(0.7, 1.4)
        pe.Rate = rate
        pe.Speed = NumberRange.new(0.4, 1.2)
        pe.SpreadAngle = Vector2.new(180, 180)
        pe.LightEmission = 1
        pe.Parent = a
    end
    local function dress(part, info, bandCF, bandDia)
        if not part then return end
        local r = rank(info.rarity)
        local rc = rarityColor(info.rarity)
        if r >= 3 and bandCF and not part:IsA("MeshPart") then -- 3D mesh parts skip the band
            cyl("RarityBand", S(0.12), bandDia, bandCF, rc, neon())
        end
        if r >= 4 then sparkle(part, ColorSequence.new(rc), r >= 6 and 10 or 4) end
        if r >= 5 then
            local l = Instance.new("PointLight")
            l.Color = rc
            l.Range = S(6)
            l.Brightness = r >= 6 and 1.6 or 1
            l.Parent = part
        end
        if info.shiny then
            sparkle(part, ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
                ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
                ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 255, 160)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 140, 255)),
            }), 8)
        end
    end

    -- 3D mesh parts: ReplicatedStorage.PartMeshes.<Family>.<Slot> (a MeshPart or Model).
    -- When one exists it replaces the shape-built part: scaled to fit the slot's box and centred in it.
    local lastMesh, lastH
    local function meshSlot(slot, info, box, cf, align)
        local folder = PartMeshes and PartMeshes:FindFirstChild(info.family)
        -- Legendary and Mythic parts get the family's special mesh ("<Slot>_Legendary") when it has one
        local tpl = folder and ((rank(info.rarity) >= 5 and folder:FindFirstChild(slot .. "_Legendary")) or folder:FindFirstChild(slot))
        if not tpl then return false end
        if only and current ~= only then return true end
        local m = tpl:Clone()
        local size = m:IsA("Model") and select(2, m:GetBoundingBox()) or m.Size
        local k = math.min(box.X / size.X, box.Y / size.Y, box.Z / size.Z)
        local h = size.Y * k
        lastH = h / u
        -- slide the fitted mesh to the bottom (or top) of its box instead of floating in the middle;
        -- a template's Sink attribute pushes it further down (a fraction of its height) when its outline has empty space at the bottom
        cf = cf * CFrame.new(0, (align == "top" and 1 or -1) * (box.Y - h) / 2 - (tpl:GetAttribute("Sink") or 0) * h, 0)
        if m:IsA("Model") then
            m:ScaleTo(m:GetScale() * k)
            m:PivotTo(cf * m:GetBoundingBox():ToObjectSpace(m:GetPivot()))
        else
            m.Size = size * k
            m.CFrame = cf
        end
        local main
        for _, p in (m:IsA("Model") and m:GetDescendants() or { m, unpack(m:GetDescendants()) }) do
            if p:IsA("BasePart") then
                p.Anchored = false
                p.CanCollide = false
                p.CanQuery = false
                p.CanTouch = false
                p.Massless = true
                local w = Instance.new("WeldConstraint")
                w.Part0 = root
                w.Part1 = p
                w.Parent = p
                tag(p, slot)
                if not main or p.Size.Magnitude > main.Size.Magnitude then main = p end
            elseif p:IsA("Script") or p:IsA("LocalScript") then
                p:Destroy()
            end
        end
        -- lift the parts straight into the creature (other scripts look for model.Torso / model.Head)
        for _, p in (m:IsA("Model") and m:GetDescendants() or { m }) do
            if p:IsA("BasePart") then
                p.Name = p == main and slot or (slot .. "Detail")
                p.Parent = model
            end
        end
        if m:IsA("Model") then m:Destroy() end
        lastMesh = main
        if slot == "Legs" then dress(main, info) end -- the other slots dress their part after the family branches
        return true
    end

    -------------------------------------------------
    -- LEGS (decide hip height)
    -------------------------------------------------
    local L = parts.Legs
    current = "Legs"
    local hipY = 1.0
    if L then
        local fc = famColor(L.family)
        if meshSlot("Legs", L, V(1.8, 1.6, 1.8), at(0, 0.8, 0)) then
            hipY = math.max(lastH, 0.9) - 0.05 -- body sits on the legs' real height
        elseif L.family == "Sigma" then
            hipY = 1.75
            for _, sd in { -1, 1 } do
                local leg = cyl("Leg", S(1.55), S(0.48), at(sd * 0.38, 0.95, 0), Color3.fromRGB(48, 48, 58))
                block("Shoe", V(0.55, 0.28, 0.85), at(sd * 0.38, 0.14, -0.15), BLACK, { Reflectance = 0.15 })
                if sd == 1 then dress(leg, L, at(sd * 0.38, 0.45, 0), S(0.55)) end
            end
        elseif L.family == "Ohio" then
            hipY = 1.35
            for i = 1, 4 do
                local a = math.rad(45 + i * 90)
                local t = cyl("Tendril", S(1.5), S(0.36), at(math.cos(a) * 0.45, 0.65, math.sin(a) * 0.45) * CFrame.Angles(math.sin(a) * 0.5, 0, -math.cos(a) * 0.5), VOID)
                ball("TendrilTip", V(0.34, 0.34, 0.34), at(math.cos(a) * 0.85, 0.1, math.sin(a) * 0.85), fc, neon())
                if i == 1 then dress(t, L, nil) end
            end
        elseif L.family == "Skibidi" then
            hipY = 1.55
            local bowl = cyl("Bowl", S(1.1), S(1.9), at(0, 0.55, 0), PORCELAIN, { Material = Enum.Material.Marble })
            cyl("Rim", S(0.22), S(2.1), at(0, 1.2, 0), PORCELAIN, { Material = Enum.Material.Marble })
            cyl("Water", S(0.05), S(1.6), at(0, 1.32, 0), Color3.fromRGB(120, 200, 255), { Material = Enum.Material.Glass, Transparency = 0.3 })
            block("Lid", V(1.9, 0.12, 0.5), at(0, 1.55, 0.95) * CFrame.Angles(math.rad(70), 0, 0), PORCELAIN)
            dress(bowl, L, at(0, 0.3, 0), S(2.0))
        elseif L.family == "Rizz" then
            hipY = 1.95
            for _, sd in { -1, 1 } do
                local leg = cyl("Leg", S(1.5), S(0.5), at(sd * 0.4, 1.15, 0), Color3.fromRGB(55, 75, 135), { Material = Enum.Material.Fabric })
                block("Sneaker", V(0.7, 0.45, 1.05), at(sd * 0.4, 0.22, -0.15), WHITE)
                block("Swoosh", V(0.72, 0.12, 0.6), at(sd * 0.4, 0.3, -0.1), fc, neon())
                if sd == 1 then dress(leg, L, at(sd * 0.4, 0.7, 0), S(0.58)) end
            end
        elseif L.family == "Mewing" then
            hipY = 1.6
            for _, sd in { -1, 1 } do
                local leg = cyl("Leg", S(1.2), S(0.7), at(sd * 0.45, 0.95, 0), SKIN)
                block("Shorts", V(0.85, 0.5, 0.85), at(sd * 0.45, 1.4, 0), fc)
                block("Sock", V(0.62, 0.2, 0.62), at(sd * 0.45, 0.42, 0), WHITE)
                block("Shoe", V(0.7, 0.32, 0.95), at(sd * 0.45, 0.16, -0.12), Color3.fromRGB(40, 40, 45))
                if sd == 1 then dress(leg, L, at(sd * 0.45, 0.8, 0), S(0.78)) end
            end
        elseif L.family == "Aura" then
            hipY = 1.5
            local cloud = ball("Cloud", V(2.0, 0.8, 1.6), at(0, 0.75, 0), WHITE)
            ball("Puff", V(1.0, 0.8, 1.0), at(-0.7, 0.9, 0.2), WHITE)
            ball("Puff", V(1.0, 0.8, 1.0), at(0.7, 0.9, 0.2), WHITE)
            ball("Puff", V(0.9, 0.7, 0.9), at(0, 1.0, 0.5), WHITE)
            ball("CloudGlow", V(1.6, 0.25, 1.3), at(0, 0.35, 0), fc, neon({ Transparency = 0.3 }))
            dress(cloud, L, nil)
        elseif L.family == "Delulu" then
            hipY = 1.9
            for _, sd in { -1, 1 } do
                local spring
                for i = 0, 3 do
                    local coil = cyl("Coil", S(0.12), S(0.6), at(sd * 0.42, 0.55 + i * 0.3, 0), i % 2 == 0 and fc or WHITE, { Material = Enum.Material.Metal })
                    if i == 0 then spring = coil end
                end
                block("Boot", V(0.75, 0.45, 1.0), at(sd * 0.42, 0.22, -0.1), fc:Lerp(WHITE, 0.3))
                ball("Pompom", V(0.3, 0.3, 0.3), at(sd * 0.42, 0.5, -0.55), WHITE)
                if sd == 1 then dress(spring, L, at(sd * 0.42, 0.45, 0), S(0.7)) end
            end
        else -- Fanum
            hipY = 1.2
            for _, sd in { -1, 1 } do
                local leg = cyl("Leg", S(0.95), S(0.8), at(sd * 0.5, 0.75, 0), fc:Lerp(BLACK, 0.25))
                ball("Paw", V(0.95, 0.5, 1.1), at(sd * 0.5, 0.25, -0.1), fc:Lerp(BLACK, 0.35))
                for c = -1, 1 do
                    wedge("Claw", V(0.12, 0.22, 0.3), at(sd * 0.5 + c * 0.25, 0.15, -0.7) * CFrame.Angles(math.rad(-90), 0, 0), WHITE)
                end
                if sd == 1 then dress(leg, L, at(sd * 0.5, 0.95, 0), S(0.85)) end
            end
        end
    else
        if not only then
            current = nil
        end
    end

    -------------------------------------------------
    -- TORSO
    -------------------------------------------------
    local T = parts.Torso
    current = "Torso"
    local tw, th, td = 1.6, 1.7, 1.1 -- torso width / height / depth (in u)
    if T then
        local fc = famColor(T.family)
        local cy = hipY + 0.85
        local main
        if meshSlot("Torso", T, V(1.9, 1.9, 1.4), at(0, hipY + 0.95, 0)) then
            tw, th, td = 1.9, lastH, 1.4
            cy = hipY + th / 2
            main = lastMesh
        elseif T.family == "Sigma" then
            tw, th, td = 1.7, 1.8, 1.0
            cy = hipY + th / 2
            main = block("Torso", V(tw, th, td), at(0, cy, 0), NAVY)
            block("Shirt", V(0.55, th * 0.95, 0.05), at(0, cy, -td / 2 - 0.01), WHITE)
            wedge("Tie", V(0.25, 1.1, 0.06), at(0, cy - 0.15, -td / 2 - 0.05) * CFrame.Angles(0, 0, math.rad(180)), fc)
            block("Lapel", V(0.18, 0.9, 0.06), at(-0.38, cy + 0.35, -td / 2 - 0.03) * CFrame.Angles(0, 0, math.rad(-20)), NAVY:Lerp(BLACK, 0.4))
            block("Lapel", V(0.18, 0.9, 0.06), at(0.38, cy + 0.35, -td / 2 - 0.03) * CFrame.Angles(0, 0, math.rad(20)), NAVY:Lerp(BLACK, 0.4))
        elseif T.family == "Ohio" then
            tw, th, td = 1.9, 1.9, 1.6
            cy = hipY + th / 2
            main = ball("Torso", V(tw, th, td), at(0, cy, 0), VOID, { Material = Enum.Material.Glass, Transparency = 0.25 })
            ball("Core", V(0.8, 0.8, 0.8), at(0, cy, 0), fc, neon())
            for i = 1, 3 do
                cyl("Ring", S(0.06), S(1.2 + i * 0.15), at(0, cy, 0) * CFrame.Angles(math.rad(i * 60), math.rad(i * 30), 0), fc, neon({ Transparency = 0.4 }))
            end
        elseif T.family == "Skibidi" then
            tw, th, td = 1.7, 1.75, 1.2
            cy = hipY + th / 2
            main = block("Torso", V(tw, th, td), at(0, cy, 0), PORCELAIN, { Material = Enum.Material.Marble })
            block("TankLid", V(tw + 0.15, 0.2, td + 0.15), at(0, cy + th / 2, 0), PORCELAIN, { Material = Enum.Material.Marble })
            cyl("Flush", S(0.2), S(0.35), at(-0.55, cy + 0.45, -td / 2 - 0.05) * CFrame.Angles(math.rad(90), 0, 0), SILVER, { Material = Enum.Material.Metal })
            block("Logo", V(0.6, 0.6, 0.05), at(0.2, cy - 0.1, -td / 2 - 0.02), fc)
        elseif T.family == "Rizz" then
            tw, th, td = 1.85, 1.8, 1.3
            cy = hipY + th / 2
            main = ball("Torso", V(tw, th, td), at(0, cy, 0), Color3.fromRGB(45, 40, 55), { Material = Enum.Material.Fabric })
            block("Pocket", V(1.0, 0.45, 0.1), at(0, cy - 0.4, -td / 2 + 0.05), Color3.fromRGB(60, 55, 70), { Material = Enum.Material.Fabric })
            cyl("Chain", S(0.12), S(1.15), at(0, cy + 0.3, -td / 2 + 0.15) * CFrame.Angles(math.rad(70), 0, 0), GOLD, { Material = Enum.Material.Metal, Reflectance = 0.3 })
            ball("Pendant", V(0.35, 0.35, 0.15), at(0, cy - 0.05, -td / 2 - 0.02), fc, neon())
        elseif T.family == "Mewing" then
            tw, th, td = 2.1, 1.8, 1.1
            cy = hipY + th / 2
            main = block("Torso", V(tw, th, td), at(0, cy, 0), SKIN)
            block("Tank", V(tw * 0.8, th * 0.75, td + 0.04), at(0, cy - 0.2, 0), fc)
            for _, sd in { -1, 1 } do
                block("Pec", V(0.75, 0.4, 0.1), at(sd * 0.42, cy + 0.4, -td / 2 - 0.04), SKIN:Lerp(BLACK, 0.08))
                ball("Shoulder", V(0.75, 0.75, 0.75), at(sd * tw / 2, cy + th / 2 - 0.3, 0), SKIN)
            end
            block("Belt", V(tw + 0.05, 0.25, td + 0.06), at(0, hipY + 0.15, 0), Color3.fromRGB(40, 40, 45))
        elseif T.family == "Aura" then
            tw, th, td = 1.7, 1.9, 1.2
            cy = hipY + th / 2
            main = ball("Torso", V(tw, th, td), at(0, cy, 0), Color3.fromRGB(248, 248, 255))
            block("Sash", V(0.3, th, 0.06), at(0, cy, -td / 2 + 0.05) * CFrame.Angles(0, 0, math.rad(25)), GOLD, { Material = Enum.Material.Metal })
            for _, sd in { -1, 1 } do
                local wingCF = at(sd * 0.75, cy + 0.4, td / 2 + 0.35) * CFrame.Angles(0, 0, math.rad(sd * -30))
                wedge("Wing", V(0.15, 1.8, 1.2), wingCF, WHITE)
                wedge("WingGlow", V(0.17, 1.3, 0.8), wingCF * CFrame.new(0, S(-0.1), S(0.1)), fc, neon({ Transparency = 0.4 }))
            end
        elseif T.family == "Delulu" then
            tw, th, td = 1.9, 1.8, 1.5
            cy = hipY + th / 2
            main = ball("Torso", V(tw, th, td), at(0, cy, 0), fc)
            for i = 1, 6 do
                local a = math.rad(i * 60)
                ball("Fluff", V(0.8, 0.8, 0.8), at(math.cos(a) * tw * 0.42, cy + math.sin(a) * th * 0.35, 0), i % 2 == 0 and WHITE or fc:Lerp(WHITE, 0.4))
            end
            ball("Heart", V(0.4, 0.4, 0.15), at(0, cy, -td / 2 - 0.02), Color3.fromRGB(255, 60, 140), neon())
        else -- Fanum
            tw, th, td = 2.2, 2.0, 1.9
            cy = hipY + th / 2 - 0.1
            main = ball("Torso", V(tw, th, td), at(0, cy, 0), fc:Lerp(Color3.fromRGB(255, 150, 60), 0.5))
            ball("Belly", V(1.4, 1.3, 0.6), at(0, cy - 0.15, -td / 2 + 0.2), Color3.fromRGB(255, 225, 170))
            block("Crumb", V(0.15, 0.15, 0.1), at(0.3, cy + 0.1, -td / 2 - 0.05), Color3.fromRGB(150, 90, 40))
        end
        dress(main, T, at(0, cy - th * 0.35, 0), S(math.max(tw, td) * 0.95))
        if rank(T.rarity) >= 6 then sparkle(main, ColorSequence.new(rarityColor(T.rarity), GOLD), 14, S(0.6)) end
    end
    local torsoTop = hipY + th
    local shoulderX = tw / 2 + 0.22
    local shoulderY = torsoTop - 0.4

    -------------------------------------------------
    -- HEAD
    -------------------------------------------------
    local H = parts.Head
    current = "Head"
    local headTop = torsoTop + 0.2
    if H then
        local fc = famColor(H.family)
        local hs = 1.45
        local hy = torsoTop + hs / 2 - 0.05
        local fz = -hs / 2 -- face plane
        local head
        local function eyes(eyeColor, pupil, y, spread, size)
            for _, sd in { -1, 1 } do
                ball("Eye", V(size, size, size * 0.6), at(sd * spread, y, fz + 0.05), eyeColor)
                if pupil then
                    ball("Pupil", V(size * 0.5, size * 0.5, size * 0.3), at(sd * spread, y - 0.02, fz - 0.06), pupil)
                end
            end
        end
        if meshSlot("Head", H, V(1.8, 2.2, 1.7), at(0, torsoTop + 1.05, 0)) then -- (box bottom sits just inside the torso top)
            head = lastMesh
            headTop = torsoTop - 0.05 + lastH
        elseif H.family == "Sigma" then
            head = block("Head", V(1.4, 1.4, 1.3), at(0, hy, 0), SKIN)
            block("Hair", V(1.5, 0.35, 1.4), at(0, hy + 0.78, 0.05), BLACK, { Reflectance = 0.1 })
            block("Quiff", V(1.0, 0.25, 0.5), at(0.15, hy + 0.95, -0.4) * CFrame.Angles(math.rad(15), 0, 0), BLACK)
            block("Shades", V(1.3, 0.3, 0.08), at(0, hy + 0.15, -0.68), BLACK, { Reflectance = 0.2 })
            block("Lens", V(0.3, 0.06, 0.02), at(-0.3, hy + 0.22, -0.73), fc, neon())
            block("Smirk", V(0.4, 0.07, 0.05), at(0.1, hy - 0.35, -0.66) * CFrame.Angles(0, 0, math.rad(8)), BLACK)
            headTop = hy + 1.05
        elseif H.family == "Ohio" then
            head = ball("Head", V(1.5, 1.55, 1.45), at(0, hy, 0), VOID)
            eyes(Color3.fromRGB(255, 255, 255), BLACK, hy, 0.3, 0.32)
            ball("ThirdEye", V(0.38, 0.38, 0.2), at(0, hy + 0.42, fz + 0.08), Color3.fromRGB(255, 40, 70), neon())
            for _, sd in { -1, 1 } do
                cyl("Horn", S(0.7), S(0.18), at(sd * 0.45, hy + 0.85, 0) * CFrame.Angles(0, 0, math.rad(sd * -25)), fc, neon())
            end
            block("Mouth", V(0.5, 0.06, 0.05), at(0, hy - 0.35, fz + 0.12), fc, neon())
            headTop = hy + 1.25
        elseif H.family == "Skibidi" then
            head = ball("Head", V(1.5, 1.55, 1.45), at(0, hy, 0), SKIN)
            eyes(WHITE, BLACK, hy + 0.2, 0.3, 0.34)
            for _, sd in { -1, 1 } do
                block("Brow", V(0.35, 0.08, 0.06), at(sd * 0.3, hy + 0.48, fz + 0.02) * CFrame.Angles(0, 0, math.rad(sd * 15)), Color3.fromRGB(70, 45, 30))
            end
            block("Grin", V(0.9, 0.28, 0.08), at(0, hy - 0.3, fz + 0.1), BLACK)
            block("Teeth", V(0.8, 0.1, 0.06), at(0, hy - 0.2, fz + 0.06), WHITE)
            ball("Hair", V(1.2, 0.35, 1.1), at(0, hy + 0.7, 0.05), Color3.fromRGB(70, 45, 30))
            headTop = hy + 0.9
        elseif H.family == "Rizz" then
            head = ball("Head", V(1.45, 1.45, 1.4), at(0, hy, 0), fc:Lerp(SKIN, 0.55))
            for _, sd in { -1, 1 } do
                ball("HeartEyeL", V(0.22, 0.22, 0.1), at(sd * 0.3 - 0.07, hy + 0.17, fz + 0.02), Color3.fromRGB(255, 70, 140), neon())
                ball("HeartEyeR", V(0.22, 0.22, 0.1), at(sd * 0.3 + 0.07, hy + 0.17, fz + 0.02), Color3.fromRGB(255, 70, 140), neon())
                wedge("HeartTip", V(0.3, 0.2, 0.08), at(sd * 0.3, hy + 0.04, fz + 0.03) * CFrame.Angles(math.rad(180), 0, 0), Color3.fromRGB(255, 70, 140), neon())
            end
            block("Smile", V(0.45, 0.08, 0.05), at(0, hy - 0.3, fz + 0.08), BLACK)
            local cy2 = hy + 0.75
            cyl("CrownBand", S(0.25), S(0.9), at(0, cy2, 0), GOLD, { Material = Enum.Material.Metal, Reflectance = 0.35 })
            for i = 1, 5 do
                local a = math.rad(i * 72)
                wedge("CrownPoint", V(0.14, 0.3, 0.2), at(math.cos(a) * 0.38, cy2 + 0.25, math.sin(a) * 0.38) * CFrame.Angles(0, -a, 0), GOLD, { Material = Enum.Material.Metal, Reflectance = 0.35 })
            end
            ball("CrownGem", V(0.18, 0.18, 0.1), at(0, cy2, -0.45), fc, neon())
            headTop = cy2 + 0.45
        elseif H.family == "Mewing" then
            head = block("Head", V(1.3, 1.3, 1.25), at(0, hy + 0.1, 0), SKIN)
            block("Jaw", V(1.55, 0.6, 1.3), at(0, hy - 0.5, -0.02), SKIN:Lerp(BLACK, 0.04))
            block("Chin", V(0.7, 0.3, 0.3), at(0, hy - 0.7, -0.6), SKIN)
            for _, sd in { -1, 1 } do
                block("Eye", V(0.32, 0.08, 0.05), at(sd * 0.3, hy + 0.2, -0.65), BLACK)
                block("Brow", V(0.4, 0.1, 0.06), at(sd * 0.3, hy + 0.34, -0.65) * CFrame.Angles(0, 0, math.rad(sd * -10)), BLACK)
            end
            block("Mouth", V(0.35, 0.06, 0.04), at(0, hy - 0.4, -0.68), BLACK)
            block("Buzz", V(1.34, 0.18, 1.29), at(0, hy + 0.78, 0), Color3.fromRGB(60, 40, 25))
            block("Headband", V(1.36, 0.2, 1.31), at(0, hy + 0.55, 0), fc)
            headTop = hy + 0.9
        elseif H.family == "Aura" then
            head = ball("Head", V(1.45, 1.45, 1.4), at(0, hy, 0), Color3.fromRGB(250, 244, 235))
            for _, sd in { -1, 1 } do
                block("ClosedEye", V(0.3, 0.06, 0.05), at(sd * 0.3, hy + 0.1, fz + 0.06) * CFrame.Angles(0, 0, math.rad(sd * -8)), Color3.fromRGB(90, 80, 110))
                ball("Blush", V(0.25, 0.15, 0.08), at(sd * 0.42, hy - 0.1, fz + 0.12), Color3.fromRGB(255, 180, 200))
            end
            block("Smile", V(0.3, 0.06, 0.05), at(0, hy - 0.28, fz + 0.08), Color3.fromRGB(90, 80, 110))
            ball("Hair", V(1.5, 0.6, 1.45), at(0, hy + 0.55, 0.12), Color3.fromRGB(255, 240, 190))
            cyl("Halo", S(0.1), S(1.3), at(0, hy + 1.1, 0), GOLD, neon())
            headTop = hy + 1.25
        elseif H.family == "Delulu" then
            head = ball("Head", V(1.6, 1.55, 1.5), at(0, hy, 0), fc:Lerp(WHITE, 0.35))
            for _, sd in { -1, 1 } do
                ball("BigEye", V(0.5, 0.55, 0.2), at(sd * 0.32, hy + 0.1, fz + 0.06), BLACK)
                ball("Sparkle", V(0.16, 0.16, 0.08), at(sd * 0.32 + 0.08, hy + 0.22, fz - 0.03), WHITE, neon())
                wedge("Ear", V(0.15, 0.55, 0.45), at(sd * 0.5, hy + 0.85, 0) * CFrame.Angles(0, math.rad(90), math.rad(sd * -15)), fc)
            end
            ball("Mouth", V(0.2, 0.12, 0.06), at(0, hy - 0.32, fz + 0.1), Color3.fromRGB(200, 40, 90))
            ball("Bubble", V(2.0, 2.0, 2.0), at(0, hy + 0.1, 0), Color3.fromRGB(200, 230, 255), { Material = Enum.Material.Glass, Transparency = 0.8 })
            headTop = hy + 1.2
        else -- Fanum
            head = ball("Head", V(1.6, 1.4, 1.5), at(0, hy + 0.1, 0), fc:Lerp(Color3.fromRGB(255, 150, 60), 0.5))
            eyes(WHITE, BLACK, hy + 0.4, 0.32, 0.34)
            block("Jaw", V(1.4, 0.45, 1.2), at(0, hy - 0.45, -0.1), fc:Lerp(BLACK, 0.3))
            for i = -2, 2 do
                wedge("Tooth", V(0.16, 0.22, 0.1), at(i * 0.24, hy - 0.12, fz - 0.05) * CFrame.Angles(math.rad(180), 0, 0), WHITE)
            end
            cyl("Antenna", S(0.6), S(0.08), at(0, hy + 1.05, 0), BLACK)
            ball("AntennaTip", V(0.25, 0.25, 0.25), at(0, hy + 1.38, 0), fc, neon())
            headTop = hy + 1.5
        end
        dress(head, H, at(0, torsoTop + 0.02, 0), S(0.95)) -- rarity collar at the neck
    end

    -------------------------------------------------
    -- ARMS
    -------------------------------------------------
    local A = parts.Arms
    current = "Arms"
    local armLen = 1.3
    local handR = Vector3.new(shoulderX + 0.15, shoulderY - armLen, -0.15)
    if A then
        local fc = famColor(A.family)
        for _, sd in { -1, 1 } do
            local sx = sd * shoulderX
            local mid = at(sx + sd * 0.08, shoulderY - armLen / 2, 0) * CFrame.Angles(0, 0, math.rad(sd * 10))
            local handPos = at(sx + sd * 0.18, shoulderY - armLen, -0.1)
            local arm
            if meshSlot("Arms", A, V(0.75, armLen + 0.2, 0.75), at(sx - sd * 0.05, shoulderY + 0.25 - (armLen + 0.2) / 2, 0), "top") then
                arm = lastMesh
            elseif A.family == "Sigma" then
                arm = cyl("Arm", S(armLen), S(0.42), mid, NAVY)
                cyl("Cuff", S(0.15), S(0.46), handPos * CFrame.new(0, S(0.22), 0), WHITE)
                ball("Hand", V(0.42, 0.42, 0.42), handPos, SKIN)
            elseif A.family == "Ohio" then
                arm = cyl("Arm", S(armLen), S(0.3), mid, VOID)
                ball("Hand", V(0.38, 0.38, 0.38), handPos, VOID)
                for c = -1, 1 do
                    wedge("Claw", V(0.08, 0.35, 0.12), handPos * CFrame.new(S(c * 0.1), S(-0.3), S(-0.05)) * CFrame.Angles(math.rad(180), 0, 0), fc, neon())
                end
            elseif A.family == "Skibidi" then
                arm = cyl("Arm", S(armLen), S(0.36), mid, PORCELAIN)
                cyl("PlungerStick", S(0.5), S(0.12), handPos * CFrame.new(0, S(-0.1), 0), Color3.fromRGB(160, 110, 60))
                cyl("PlungerCup", S(0.3), S(0.6), handPos * CFrame.new(0, S(-0.4), 0), Color3.fromRGB(200, 40, 50))
            elseif A.family == "Rizz" then
                arm = cyl("Arm", S(armLen), S(0.4), mid, Color3.fromRGB(45, 40, 55), { Material = Enum.Material.Fabric })
                cyl("Bracelet", S(0.14), S(0.5), handPos * CFrame.new(0, S(0.25), 0), GOLD, { Material = Enum.Material.Metal, Reflectance = 0.35 })
                ball("Hand", V(0.42, 0.42, 0.42), handPos, SKIN)
                ball("Ring", V(0.14, 0.14, 0.14), handPos * CFrame.new(0, 0, S(-0.2)), fc, neon())
            elseif A.family == "Mewing" then
                arm = cyl("Arm", S(armLen), S(0.55), mid, SKIN)
                ball("Bicep", V(0.62, 0.62, 0.62), at(sx + sd * 0.14, shoulderY - 0.45, -0.05), SKIN)
                cyl("Wristband", S(0.2), S(0.6), handPos * CFrame.new(0, S(0.25), 0), fc)
                ball("Fist", V(0.55, 0.55, 0.55), handPos, SKIN)
            elseif A.family == "Aura" then
                arm = cyl("Arm", S(armLen), S(0.34), mid, Color3.fromRGB(248, 248, 255))
                ball("Hand", V(0.4, 0.4, 0.4), handPos, fc, neon({ Transparency = 0.2 }))
                cyl("Bangle", S(0.1), S(0.42), handPos * CFrame.new(0, S(0.22), 0), GOLD, { Material = Enum.Material.Metal })
            elseif A.family == "Delulu" then
                local upper = at(sx + sd * 0.25, shoulderY - 0.35, 0) * CFrame.Angles(0, 0, math.rad(sd * 40))
                arm = cyl("Arm", S(0.8), S(0.22), upper, fc)
                cyl("Forearm", S(0.9), S(0.22), at(sx + sd * 0.3, shoulderY - armLen + 0.4, -0.05) * CFrame.Angles(0, 0, math.rad(sd * -30)), fc:Lerp(WHITE, 0.3))
                ball("Mitten", V(0.5, 0.5, 0.5), handPos, WHITE)
            else -- Fanum
                arm = cyl("Arm", S(armLen), S(0.6), mid, fc:Lerp(Color3.fromRGB(255, 150, 60), 0.5))
                ball("Mitt", V(0.75, 0.7, 0.75), handPos, fc:Lerp(BLACK, 0.3))
            end
            if sd == 1 then dress(arm, A, handPos * CFrame.new(0, S(0.4), 0), S(0.55)) end
        end
        handR = Vector3.new(shoulderX + 0.18, shoulderY - armLen, -0.1)
    end

    -------------------------------------------------
    -- WEAPON (in the right hand, or floating beside the body)
    -------------------------------------------------
    local W = parts.Weapon
    current = "Weapon"
    if W then
        local fc = famColor(W.family)
        local hx, hyy, hz = handR.X, handR.Y, handR.Z
        if not A then hx, hyy, hz = shoulderX + 0.6, shoulderY - 0.6, -0.2 end
        local g = at(hx, hyy, hz)
        local main
        if W.family == "Sigma" then
            main = block("Briefcase", V(1.0, 0.75, 0.3), g * CFrame.new(0, S(-0.5), 0), Color3.fromRGB(70, 45, 30), { Material = Enum.Material.Leather })
            block("Clasp", V(0.3, 0.12, 0.33), g * CFrame.new(0, S(-0.25), 0), GOLD, { Material = Enum.Material.Metal })
            block("Handle", V(0.4, 0.12, 0.12), g * CFrame.new(0, S(-0.08), 0), BLACK)
            block("Cash", V(0.3, 0.05, 0.32), g * CFrame.new(S(0.3), S(-0.85), 0), Color3.fromRGB(90, 200, 90))
        elseif W.family == "Ohio" then
            local up = g * CFrame.Angles(math.rad(-70), 0, 0)
            block("Hilt", V(0.6, 0.12, 0.12), up, BLACK)
            block("Grip", V(0.14, 0.4, 0.14), up * CFrame.new(0, S(-0.25), 0), VOID)
            main = block("Blade", V(0.12, 2.3, 0.32), up * CFrame.new(0, S(1.2), 0), fc, neon({ Transparency = 0.1 }))
        elseif W.family == "Skibidi" then
            local fwd = g * CFrame.Angles(math.rad(-90), 0, 0)
            main = cyl("Barrel", S(1.7), S(0.55), fwd * CFrame.new(0, S(0.6), 0), PORCELAIN, { Material = Enum.Material.Marble })
            cyl("Muzzle", S(0.25), S(0.75), fwd * CFrame.new(0, S(1.45), 0), Color3.fromRGB(200, 40, 50))
            cyl("Water", S(0.05), S(0.45), fwd * CFrame.new(0, S(1.6), 0), Color3.fromRGB(120, 200, 255), neon())
        elseif W.family == "Rizz" then
            main = cyl("Staff", S(2.4), S(0.14), g * CFrame.new(0, S(0.5), 0), GOLD, { Material = Enum.Material.Metal, Reflectance = 0.3 })
            local top = g * CFrame.new(0, S(1.85), 0)
            ball("HeartL", V(0.42, 0.42, 0.25), top * CFrame.new(S(-0.15), 0, 0), Color3.fromRGB(255, 70, 140), neon())
            ball("HeartR", V(0.42, 0.42, 0.25), top * CFrame.new(S(0.15), 0, 0), Color3.fromRGB(255, 70, 140), neon())
            wedge("HeartTip", V(0.62, 0.42, 0.24), top * CFrame.new(0, S(-0.25), 0) * CFrame.Angles(math.rad(180), 0, 0), Color3.fromRGB(255, 70, 140), neon())
        elseif W.family == "Mewing" then
            local axis = g * CFrame.Angles(math.rad(90), 0, 0)
            main = cyl("Bar", S(1.8), S(0.14), axis, SILVER, { Material = Enum.Material.Metal })
            for _, e in { -1, 1 } do
                cyl("Plate", S(0.25), S(0.9), axis * CFrame.new(0, S(e * 0.7), 0), Color3.fromRGB(35, 35, 40))
                cyl("PlateRim", S(0.27), S(0.4), axis * CFrame.new(0, S(e * 0.7), 0), fc, neon())
            end
        elseif W.family == "Aura" then
            main = cyl("Staff", S(2.5), S(0.14), g * CFrame.new(0, S(0.5), 0), WHITE, { Material = Enum.Material.Marble })
            local top = g * CFrame.new(0, S(1.9), 0)
            ball("Orb", V(0.55, 0.55, 0.55), top, fc, neon())
            cyl("OrbHalo", S(0.06), S(0.9), top, GOLD, neon())
        elseif W.family == "Delulu" then
            main = cyl("Stick", S(2.0), S(0.14), g * CFrame.new(0, S(0.4), 0), WHITE)
            local face = g * CFrame.new(0, S(1.7), 0) * CFrame.Angles(math.rad(90), 0, 0)
            cyl("Candy", S(0.25), S(1.1), face, fc)
            cyl("Swirl", S(0.27), S(0.7), face, WHITE)
            cyl("CandyCore", S(0.29), S(0.3), face, fc, neon())
        else -- Fanum
            main = cyl("Shaft", S(2.6), S(0.13), g * CFrame.new(0, S(0.6), 0), SILVER, { Material = Enum.Material.Metal })
            local top = g * CFrame.new(0, S(1.9), 0)
            block("ForkBar", V(0.7, 0.1, 0.1), top, SILVER, { Material = Enum.Material.Metal })
            for i = -1, 1 do
                wedge("Prong", V(0.1, 0.5, 0.1), top * CFrame.new(S(i * 0.3), S(0.3), 0), SILVER, { Material = Enum.Material.Metal })
            end
            ball("Gem", V(0.2, 0.2, 0.2), top * CFrame.new(0, S(-0.1), S(-0.08)), fc, neon())
        end
        dress(main, W, nil)
    end

    -- pure sets get an aura
    if not only then
        local fams = {}
        local count = 0
        for _, p in parts do
            fams[p.family] = (fams[p.family] or 0) + 1
            count += 1
        end
        for fam, k in fams do
            if k >= 5 then
                current = "Torso"
                local body = model:FindFirstChild("Torso")
                if body then sparkle(body, ColorSequence.new(famColor(fam), GOLD), 16, S(0.7)) end
            end
        end
        current = nil
    end

    model:SetAttribute("IsCreature", true)
    model:SetAttribute("Height", S(math.max(headTop, torsoTop + 0.3)))
    return model
end

return CreatureBuilder
