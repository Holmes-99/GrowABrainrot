--[[
    LabAPI — the bridge between GameManager and the add-on server scripts
    (Monetization, PlotDecor). GameManager fills in the functions below once it has
    started; add-ons call LabAPI.waitReady() before using them.

    Fields set by GameManager:
      playerData, notify, broadcast, sendState, newId, getPlot, plotFrame, fmt,
      spawnCreatureModel, removeCreatureModel, refreshMarket, rollRarity, randomPart,
      rarityRank, partName, totalIncome, setPodVisual, revealPart, openUI, near
    Add-ons register remote actions in LabAPI.requests[action] = function(player, arg) end
]]

local LabAPI = {
    ready = false,
    requests = {},
    stateHooks = {},                               -- functions(data, stateTable) adding fields to StateUpdate
}

-- tiny signal: unlike a BindableEvent it passes the real data table, not a copy.
-- Handlers run in order on the caller's thread, so keep them quick (spawn anything that yields).
local function signal()
    local handlers = {}
    return {
        Connect = function(_, fn) table.insert(handlers, fn) end,
        Fire = function(_, ...)
            for _, fn in handlers do
                local ok, err = pcall(fn, ...)
                if not ok then warn("[LabAPI] handler error: " .. tostring(err)) end
            end
        end,
    }
end
LabAPI.playerLoaded = signal()  -- (player, data) after the save is loaded
LabAPI.playerLeaving = signal() -- (player, data) right before it's saved
LabAPI.creaturesChanged = signal() -- (player, data) a creature was built, taken apart, sold or reset

function LabAPI.waitReady()
    while not LabAPI.ready do
        task.wait()
    end
end

return LabAPI
