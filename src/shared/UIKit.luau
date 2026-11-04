--[[
    UIKit — shared look + helpers for the client UIs (DecorClient, ShopClient),
    matching LabClient's style. Also tells you what kind of screen we're on.
]]
local UserInputService = game:GetService("UserInputService")

local UIKit = {}

UIKit.HEAD = Font.fromEnum(Enum.Font.FredokaOne)
UIKit.BODY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
UIKit.BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
UIKit.GOLD = Color3.fromRGB(255, 205, 90)
UIKit.PANEL = Color3.fromRGB(22, 17, 32)
UIKit.PANEL2 = Color3.fromRGB(36, 28, 52)
UIKit.PANEL3 = Color3.fromRGB(52, 42, 72)
UIKit.WHITE = Color3.fromRGB(245, 240, 255)
UIKit.MUTED = Color3.fromRGB(170, 160, 190)
UIKit.DARKTEXT = Color3.fromRGB(30, 20, 10)
UIKit.GREEN = Color3.fromRGB(90, 230, 130)
UIKit.RED = Color3.fromRGB(255, 95, 95)
UIKit.ROBUX = Color3.fromRGB(0, 176, 111)

function UIKit.fmt(n)
    n = math.floor(n or 0)
    local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if s:sub(1, 1) == "," then s = s:sub(2) end
    return (n < 0 and "-" or "") .. s
end

function UIKit.new(class, props, children)
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
local new = UIKit.new

function UIKit.corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 12) }) end
function UIKit.stroke(color, t, th)
    return new("UIStroke", { Color = color or UIKit.GOLD, Transparency = t or 0.4, Thickness = th or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
function UIKit.pad(p) return new("UIPadding", { PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p), PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p) }) end

function UIKit.label(props, children)
    props.BackgroundTransparency = props.BackgroundTransparency or 1
    props.TextColor3 = props.TextColor3 or UIKit.WHITE
    props.FontFace = props.FontFace or UIKit.BODY
    props.TextWrapped = true
    return new("TextLabel", props, children)
end

function UIKit.button(props, onClick)
    props.BackgroundColor3 = props.BackgroundColor3 or UIKit.GOLD
    props.TextColor3 = props.TextColor3 or UIKit.DARKTEXT
    props.FontFace = props.FontFace or UIKit.HEAD
    props.AutoButtonColor = true
    local b = new("TextButton", props, { UIKit.corner(10) })
    if onClick then b.Activated:Connect(onClick) end
    return b
end

function UIKit.clear(frame)
    for _, c in frame:GetChildren() do
        if c:IsA("GuiObject") then c:Destroy() end
    end
end

-- "phone" (small touch screen), "tablet" or "desktop"
function UIKit.device()
    local vp = workspace.CurrentCamera.ViewportSize
    local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    if touch and math.min(vp.X, vp.Y) < 500 then return "phone" end
    if touch then return "tablet" end
    return "desktop"
end

-- UI scale for the current screen (1 on a 1100x700+ desktop)
function UIKit.scale()
    local vp = workspace.CurrentCamera.ViewportSize
    local s = math.min(vp.X / 1100, vp.Y / 700)
    if UIKit.device() == "phone" then s = math.max(s * 1.15, 0.75) end
    return math.clamp(s, 0.55, 1.15)
end

-- keep a list of UIScale objects in sync with the screen size
local scalers = {}
function UIKit.autoScale(guiObject)
    local sc = new("UIScale", { Scale = UIKit.scale(), Parent = guiObject })
    table.insert(scalers, sc)
    return sc
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
    local s = UIKit.scale()
    for _, sc in scalers do sc.Scale = s end
end)

return UIKit
