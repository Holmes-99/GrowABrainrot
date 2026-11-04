--[[
    DecorLogic — plot decorations: the catalog and the placement rules.
    Shared by the server (PlotDecor) and the client (DecorClient) so the
    green/red preview always agrees with what the server accepts.

    Positions are stored in plot-local studs: x = left/right, z = front(-)/back(+).
    The back yard is z 24..55; the money pedestals fill z 55..68. r = rotation in 90° steps (0-3).
]]

local DecorLogic = {}

DecorLogic.Categories = { "Epic", "Cages", "Displays", "Nature", "Lights", "Furniture", "VIP" }

-- w/d = footprint in studs. cage = income bonus for the creature living in it.
-- retired = no longer sold, but kept so decorations players already own still load and sell back.
DecorLogic.Items = {
    ArcoAngelotto  = { name = "Arco Angelotto",   cat = "Epic",      price = 800000, w = 20, d = 12, icon = "😇", desc = "A giant arch of angel wings with a spinning golden halo.", max = 2 },
    CastelloSognarello = { name = "Castello Sognarello", cat = "Epic", price = 500000, w = 20, d = 20, icon = "🏰", desc = "A candy castle floating on a pink cloud.", max = 2 },
    PortaleVortellino = { name = "Portale Vortellino", cat = "Epic",  price = 350000, w = 18, d = 18, icon = "🌀", desc = "A swirling void portal on a glowing plinth.", max = 2 },
    StatuaMuscolina = { name = "Statua Muscolina", cat = "Epic",     price = 300000, w = 18, d = 16, icon = "💪", desc = "A giant marble statue flexing for the whole server.", max = 2 },
    TronoGhiacciato = { name = "Trono Ghiacciato", cat = "Epic",     price = 250000, w = 18, d = 18, icon = "🧊", desc = "A floating cluster of giant ice crystals." },
    TrofeoBling    = { name = "Trofeo Bling Bling", cat = "Epic",    price = 150000, w = 18, d = 18, icon = "🏆", desc = "A spinning diamond trophy with a big pink heart." },
    TotemGremlino  = { name = "Totem Gremlino",   cat = "Epic",      price = 60000,  w = 8,  d = 8,  icon = "👹", desc = "A tall totem of three grinning gremlins." },
    PolpoSpettrale = { name = "Polpo Spettrale",  cat = "Epic",      price = 600000, w = 20, d = 20, icon = "🐙", desc = "A giant spooky octopus that floats and waves its tentacles.", max = 2 },
    TestaInfernale = { name = "Testa Infernale",  cat = "Epic",      price = 400000, w = 16, d = 16, icon = "😈", desc = "A huge demon head with burning eyes, hovering over a lava plinth.", max = 2 },
    ChaoticStill   = { name = "Alambicco Caotico", cat = "Epic",     price = 200000, w = 12, d = 6,  icon = "🌋", desc = "A giant fiery still that shakes like it's about to blow." },
    GiantVialRack  = { name = "Provettone Reale", cat = "Epic",      price = 90000,  w = 10, d = 10, icon = "👑", desc = "A giant rack of royal sparkling vials." },
    GiantFlask     = { name = "Fiascone Viola",   cat = "Epic",      price = 40000,  w = 8,  d = 8,  icon = "🧪", desc = "A giant glowing potion flask." },
    GiantBeaker    = { name = "Becher Gigante",   cat = "Epic",      price = 15000,  w = 10, d = 10, icon = "⚗️", desc = "A giant bubbling beaker." },
    WoodCage       = { name = "Wooden Pen",      cat = "Cages",     price = 2500,   w = 10, d = 10, cage = 0.10, icon = "🌾", desc = "A home for one creature. +10% cash for it." },
    IronCage       = { name = "Iron Cage",       cat = "Cages",     price = 20000,  w = 10, d = 10, cage = 0.25, icon = "⛓️", desc = "+25% cash for the creature inside." },
    GoldCage       = { name = "Golden Cage",     cat = "Cages",     price = 150000, w = 10, d = 10, cage = 0.50, icon = "👑", desc = "+50% cash for the creature inside." },
    NeonCage       = { name = "Neon Habitat",    cat = "Cages",     price = 750000, w = 10, d = 10, cage = 1.00, icon = "💠", desc = "+100% cash for the creature inside." },
    Pedestal       = { name = "Trophy Pedestal", cat = "Displays",  price = 6000,   w = 4,  d = 4,  icon = "🏆", desc = "Shows off your rarest spare part.", max = 8 },
    OakTree        = { name = "Oak Tree",        cat = "Nature",    price = 600,    w = 10, d = 10, icon = "🌳" },
    PineTree       = { name = "Pine Tree",       cat = "Nature",    price = 500,    w = 6,  d = 6,  icon = "🌲" },
    BirchTree      = { name = "Birch Tree",      cat = "Nature",    price = 400,    w = 4,  d = 4,  icon = "🌿", retired = true },
    BigBush        = { name = "Big Bush",        cat = "Nature",    price = 300,    w = 6,  d = 6,  icon = "🌱", retired = true },
    FlowerBush     = { name = "Flower Bush",     cat = "Nature",    price = 200,    w = 4,  d = 4,  icon = "🌸", retired = true },
    FlowerBed      = { name = "Flower Bed",      cat = "Nature",    price = 250,    w = 4,  d = 4,  icon = "🌼", retired = true },
    Hedge          = { name = "Hedge",           cat = "Nature",    price = 350,    w = 6,  d = 2,  icon = "🟩", retired = true },
    StreetLamp     = { name = "Street Lamp",     cat = "Lights",    price = 900,    w = 4,  d = 4,  icon = "💡" },
    HangingLantern = { name = "Lantern Post",    cat = "Lights",    price = 700,    w = 6,  d = 2,  icon = "🏮" },
    GlowOrb        = { name = "Glow Orb",        cat = "Lights",    price = 1500,   w = 2,  d = 2,  icon = "🔮" },
    Bench          = { name = "Bench",           cat = "Furniture", price = 600,    w = 6,  d = 2,  icon = "💺", retired = true },
    PathTile       = { name = "Stone Tile",      cat = "Furniture", price = 60,     w = 4,  d = 4,  icon = "⬜", retired = true },
    Fountain       = { name = "Fountain",        cat = "Furniture", price = 12000,  w = 10, d = 10, icon = "⛲" },
    AlchemyTable   = { name = "Alchemy Table",   cat = "Furniture", price = 3500,   w = 8,  d = 6,  icon = "⚗️" },
    PotionShelf    = { name = "Potion Shelf",    cat = "Furniture", price = 2500,   w = 4,  d = 6,  icon = "🧪" },
    RoyalCage      = { name = "Royal Habitat",   cat = "VIP",       price = 0,      w = 12, d = 12, cage = 1.50, vip = true, icon = "👑", desc = "VIP only. +150% cash for the creature inside." },
    GoldenStatue   = { name = "Golden Mixalot",  cat = "VIP",       price = 0,      w = 6,  d = 6,  vip = true, icon = "🗿", desc = "VIP only. A solid gold statue of the boss." },
    DreamCrystal   = { name = "Dream Crystal",   cat = "VIP",       price = 0,      w = 4,  d = 4,  vip = true, icon = "💎", desc = "VIP only. Glowing pink crystal." },
}

DecorLogic.Order = {
    "ArcoAngelotto", "PolpoSpettrale", "CastelloSognarello", "TestaInfernale", "PortaleVortellino", "StatuaMuscolina",
    "TronoGhiacciato", "ChaoticStill", "TrofeoBling", "GiantVialRack", "TotemGremlino", "GiantFlask", "GiantBeaker",
    "WoodCage", "IronCage", "GoldCage", "NeonCage", "Pedestal",
    "OakTree", "PineTree",
    "StreetLamp", "HangingLantern", "GlowOrb",
    "Fountain", "AlchemyTable", "PotionShelf",
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
