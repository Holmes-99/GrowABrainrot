--[[
    DecorAnimator — moves the big plot decorations, on this client only.

    Decorations with an Anim attribute (set on the template in ReplicatedStorage.DecorTemplates)
    are animated here instead of by a server script, so the server never streams their motion:
      - Octopus: the whole body bobs and slowly spins, each tentacle sways on its own
      - Float:   the body hovers above its plinth and turns a little side to side
      - Bob:     a gentle wobble, like the potion is bubbling
      - Wild:    the same wobble, but much stronger
    Only the "Body" model moves. The Footprint part (the model's PrimaryPart, moved by the server
    when the decoration is placed or moved) is the anchor every pose is built from.
]]

local RunService = game:GetService("RunService")

local camera = workspace.CurrentCamera
local ANIM_RANGE = 160 -- studs from the camera; decorations further away rest in place

local rigs = {}

local function unrig(model)
    local r = rigs[model]
    if not r then return end
    for _, c in r.conns do c:Disconnect() end
    rigs[model] = nil
end

local function rig(model)
    if rigs[model] then return end
    local anchor = model.PrimaryPart or model:FindFirstChild("Footprint")
    local body = model:FindFirstChild("Body")
    if not (anchor and body) then return end
    local r = { anchor = anchor, kind = model:GetAttribute("Anim"), parts = {}, phase = math.random() * math.pi * 2, active = true, conns = {} }
    local base = anchor.CFrame
    for _, p in body:GetDescendants() do
        if p:IsA("BasePart") then
            local n = p.Name:lower()
            table.insert(r.parts, { part = p, offset = base:ToObjectSpace(p.CFrame), tentacle = n:find("tentacle") ~= nil })
        end
    end
    rigs[model] = r
    table.insert(r.conns, model.AncestryChanged:Connect(function(_, parent)
        if not parent then unrig(model) end
    end))
end

local function consider(inst)
    if not (inst:IsA("Model") and inst:GetAttribute("Anim")) then return end
    -- the decoration ghost lives under the camera; only placed ones animate
    if not inst:IsDescendantOf(workspace) or inst:IsDescendantOf(camera) then return end
    task.delay(0.2, function()
        if inst.Parent and inst:IsDescendantOf(workspace) then rig(inst) end
    end)
end

for _, d in workspace:GetDescendants() do consider(d) end
workspace.DescendantAdded:Connect(consider)

-------------------------------------------------
-- Motion
-------------------------------------------------
local sin, cos = math.sin, math.cos
local WOBBLE = { Bob = 0.6, Wild = 1.8 }

local function rest(r)
    local base = r.anchor.CFrame
    for _, e in r.parts do e.part.CFrame = base * e.offset end
end

RunService.Heartbeat:Connect(function()
    local now = os.clock()
    local camPos = camera.CFrame.Position
    for _, r in rigs do
        local base = r.anchor.CFrame
        if (base.Position - camPos).Magnitude > ANIM_RANGE then
            if r.active then
                r.active = false
                rest(r)
            end
            continue
        end
        r.active = true
        local t = now + r.phase

        if r.kind == "Octopus" then
            local s = t * 1.6
            local pose = base * CFrame.new(0, sin(s) * 1.2, 0) * CFrame.Angles(0, sin(s * 0.15) * 0.6, 0)
            for i, e in r.parts do
                if e.tentacle then
                    local ph = i * 0.9
                    e.part.CFrame = pose * e.offset * CFrame.new(0, sin(s * 1.5 + ph) * 0.5, 0)
                        * CFrame.Angles(sin(s * 2 + ph) * 0.18, 0, cos(s * 1.6 + ph) * 0.18)
                else
                    e.part.CFrame = pose * e.offset
                end
            end
        elseif r.kind == "Float" then
            local pose = base * CFrame.new(0, sin(t * 1.2) * 0.8, 0) * CFrame.Angles(sin(t * 0.9) * 0.04, sin(t * 0.5) * 0.25, 0)
            for _, e in r.parts do e.part.CFrame = pose * e.offset end
        else
            local k = WOBBLE[r.kind] or 0.6
            local pose = base * CFrame.new(sin(t * 1.1) * 0.25 * k, (sin(t * 1.5) + 1) * 0.2 * k, 0)
                * CFrame.Angles(sin(t * 0.9) * 0.05 * k, 0, sin(t * 0.9) * 0.025 * k)
            for _, e in r.parts do e.part.CFrame = pose * e.offset end
        end
    end
end)
