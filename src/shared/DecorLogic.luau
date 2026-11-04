--[[
    DecorLogic — plot decorations: the catalog and the placement rules.
    Shared by the server (PlotDecor) and the client (DecorClient) so the
    green/red preview always agrees with what the server accepts.

    Positions are stored in plot-local studs: x = left/right, z = front(-)/back(+).
    The back yard is z 24..55; the money pedestals fill z 55..68. r = rotation in 90° steps (0-3).
]]

local DecorLogic = {}

DecorLogic.Categories = { "Cages", "Displays", "Nature", "Lights", "Furniture", "VIP" }

-- w/d = footprint in studs. cage = income bonus for the creature living in it.
DecorLogic.Items = {
    WoodCage       = { name = "Wooden Pen",      cat = "Cages",     price = 2500,   w = 10, d = 10, cage = 0.10, icon = "🌾", desc = "A home for one creature. +10% cash for it." },
    IronCage       = { name = "Iron Cage",       cat = "Cages",     price = 20000,  w = 10, d = 10, cage = 0.25, icon = "⛓️", desc = "+25% cash for the creature inside." },
    GoldCage       = { name = "Golden Cage",     cat = "Cages",     price = 150000, w = 10, d = 10, cage = 0.50, icon = "👑", desc = "+50% cash for the creature inside." },
    NeonCage       = { name = "Neon Habitat",    cat = "Cages",     price = 750000, w = 10, d = 10, cage = 1.00, icon = "💠", desc = "+100% cash for the creature inside." },
    Pedestal       = { name = "Trophy Pedestal", cat = "Displays",  price = 6000,   w = 4,  d = 4,  icon = "🏆", desc = "Shows off your rarest spare part.", max = 8 },
    OakTree        = { name = "Oak Tree",        cat = "Nature",    price = 600,    w = 10, d = 10, icon = "🌳" },
    PineTree       = { name = "Pine Tree",       cat = "Nature",    price = 500,    w = 6,  d = 6,  icon = "🌲" },
    BirchTree      = { name = "Birch Tree",      cat = "Nature",    price = 400,    w = 4,  d = 4,  icon = "🌿" },
    BigBush        = { name = "Big Bush",        cat = "Nature",    price = 300,    w = 6,  d = 6,  icon = "🌱" },
    FlowerBush     = { name = "Flower Bush",     cat = "Nature",    price = 200,    w = 4,  d = 4,  icon = "🌸" },
    FlowerBed      = { name = "Flower Bed",      cat = "Nature",    price = 250,    w = 4,  d = 4,  icon = "🌼" },
    Hedge          = { name = "Hedge",           cat = "Nature",    price = 350,    w = 6,  d = 2,  icon = "🟩" },
    StreetLamp     = { name = "Street Lamp",     cat = "Lights",    price = 900,    w = 4,  d = 4,  icon = "💡" },
    HangingLantern = { name = "Lantern Post",    cat = "Lights",    price = 700,    w = 6,  d = 2,  icon = "🏮" },
    GlowOrb        = { name = "Glow Orb",        cat = "Lights",    price = 1500,   w = 2,  d = 2,  icon = "🔮" },
    Bench          = { name = "Bench",           cat = "Furniture", price = 600,    w = 6,  d = 2,  icon = "💺" },
    PathTile       = { name = "Stone Tile",      cat = "Furniture", price = 60,     w = 4,  d = 4,  icon = "⬜" },
    Fountain       = { name = "Fountain",        cat = "Furniture", price = 12000,  w = 10, d = 10, icon = "⛲" },
    AlchemyTable   = { name = "Alchemy Table",   cat = "Furniture", price = 3500,   w = 8,  d = 6,  icon = "⚗️" },
    PotionShelf    = { name = "Potion Shelf",    cat = "Furniture", price = 2500,   w = 4,  d = 6,  icon = "🧪" },
    RoyalCage      = { name = "Royal Habitat",   cat = "VIP",       price = 0,      w = 12, d = 12, cage = 1.50, vip = true, icon = "👑", desc = "VIP only. +150% cash for the creature inside." },
    GoldenStatue   = { name = "Golden Mixalot",  cat = "VIP",       price = 0,      w = 6,  d = 6,  vip = true, icon = "🗿", desc = "VIP only. A solid gold statue of the boss." },
    DreamCrystal   = { name = "Dream Crystal",   cat = "VIP",       price = 0,      w = 4,  d = 4,  vip = true, icon = "💎", desc = "VIP only. Glowing pink crystal." },
}

DecorLogic.Order = {
    "WoodCage", "IronCage", "GoldCage", "NeonCage", "Pedestal",
    "OakTree", "PineTree", "BirchTree", "BigBush", "FlowerBush", "FlowerBed", "Hedge",
    "StreetLamp", "HangingLantern", "GlowOrb",
    "Bench", "PathTile", "Fountain", "AlchemyTable", "PotionShelf",
    "RoyalCage", "GoldenStatue", "DreamCrystal",
}

DecorLogic.MaxItems = 80
DecorLogic.SellBack = 0.5

-- where decorations may go (plot-local rectangles: x1, x2, z1, z2)
DecorLogic.Areas = {
    { -29.4, 29.4, 24.6, 54.6 },   -- back yard, in front of the money pedestals
    { -29.4, -16.6, -21.5, 7.8 },  -- left strip beside the lab (incubator 4 sits at z 8..18)
    { 16.6, 29.4, -21.5, 7.8 },    -- right strip (incubator 5)
    { -29.4, -16.6, 18.2, 24.6 },
    { 16.6, 29.4, 18.2, 24.6 },
    { -29.4, -4, -21.5, -12.6 },   -- front lawn (left of the path)
    { 4, 29.4, -21.5, -12.6 },     -- front lawn (right of the path)
}

-- the plot's frame: origin = middle of the lab on the ground, -Z faces the main path
function DecorLogic.plotFrame(plot)
    local g = plot:FindFirstChild("PlotGround")
    local c = Vector3.new(g.Position.X, g.Position.Y + g.Size.Y / 2, g.Position.Z)
    return CFrame.lookAt(c, c + Vector3.new(-math.sign(c.X), 0, 0))
end

function DecorLogic.footprint(itemId, r)
    local it = DecorLogic.Items[itemId]
    if r % 2 == 1 then return it.d, it.w end
    return it.w, it.d
end

-- snap a plot-local point so even sizes sit on whole studs
function DecorLogic.snap(itemId, r, x, z)
    local w, d = DecorLogic.footprint(itemId, r)
    local function s(v, size) local off = (size % 2) / 2 return math.floor(v - off + 0.5) + off end
    return s(x, w), s(z, d)
end

local function inArea(x, z)
    for _, a in DecorLogic.Areas do
        if x >= a[1] - 1e-3 and x <= a[2] + 1e-3 and z >= a[3] - 1e-3 and z <= a[4] + 1e-3 then return true end
    end
    return false
end

-- decor = the player's list of { id, item, x, z, r }. ignoreId = item being moved.
-- returns ok, reason
function DecorLogic.canPlace(decor, itemId, x, z, r, ignoreId)
    local it = DecorLogic.Items[itemId]
    if not it then return false, "Unknown item." end
    if typeof(x) ~= "number" or typeof(z) ~= "number" or x ~= x or z ~= z then return false, "Bad spot." end
    local w, d = DecorLogic.footprint(itemId, r)
    local x1, x2, z1, z2 = x - w / 2, x + w / 2, z - d / 2, z + d / 2
    -- every corner and edge midpoint must be on decoratable ground
    for _, px in { x1, x, x2 } do
        for _, pz in { z1, z, z2 } do
            if not inArea(px, pz) then return false, "Can't build there." end
        end
    end
    for _, e in decor do
        if e.id ~= ignoreId and DecorLogic.Items[e.item] then
            local ew, ed = DecorLogic.footprint(e.item, e.r)
            if x1 < e.x + ew / 2 - 0.01 and x2 > e.x - ew / 2 + 0.01 and z1 < e.z + ed / 2 - 0.01 and z2 > e.z - ed / 2 + 0.01 then
                return false, "Something's already there."
            end
        end
    end
    return true
end

function DecorLogic.worldCFrame(plot, x, z, r)
    return DecorLogic.plotFrame(plot) * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(90 * r), 0)
end

return DecorLogic
