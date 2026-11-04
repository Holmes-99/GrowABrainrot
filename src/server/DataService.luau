--[[
    DataService — saves and loads player progress with DataStoreService.

    * One key per player ("u_<UserId>") holding { data = <save table>, lock = { job, t } }.
    * Session lock: a server claims the key when the player joins and releases it on leave,
      so two servers can never overwrite each other (e.g. fast server hops).
    * Every write goes through UpdateAsync with retries.

    In Studio, saving only works when Game Settings > Security >
    "Enable Studio Access to API Services" is on. If it's off the game still runs,
    progress just isn't kept (DataService.enabled == false).
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local DataService = {}

local STORE_NAME = "MixingLab_Save_v1"
local LOCK_TIMEOUT = 150 -- seconds; a lock older than this belongs to a dead server
local JOB = (game.JobId ~= "" and game.JobId) or ("studio")

local store
local ok = pcall(function()
    store = DataStoreService:GetDataStore(STORE_NAME)
end)
DataService.enabled = ok and store ~= nil

local function key(userId: number): string
    return "u_" .. userId
end

local function attempt(fn, tries)
    local lastErr
    for i = 1, tries or 4 do
        local success, result = pcall(fn)
        if success then
            return true, result
        end
        lastErr = result
        warn(("[DataService] attempt %d failed: %s"):format(i, tostring(result)))
        local msg = tostring(result)
        if msg:find("publish") or msg:find("StudioAccess") or msg:find("403") then
            break -- not a hiccup: this place can't use DataStores (unpublished / API access off)
        end
        task.wait(i * 1.5)
    end
    return false, lastErr
end

-- Returns: success (bool), saved data table or nil for a brand-new player.
-- success == false means the store could not be reached: the caller should NOT save over it.
function DataService.load(userId: number)
    if not DataService.enabled then
        return false, nil
    end
    for round = 1, 6 do
        local lockedByOther = false
        local success, result = attempt(function()
            return store:UpdateAsync(key(userId), function(old)
                old = old or {}
                local lock = old.lock
                if lock and lock.job ~= JOB and os.time() - (lock.t or 0) < LOCK_TIMEOUT and round < 6 then
                    lockedByOther = true
                    return nil -- cancel, try again in a moment
                end
                old.lock = { job = JOB, t = os.time() }
                return old
            end)
        end)
        if not success then
            -- API access off in Studio, or DataStores down
            if RunService:IsStudio() then
                -- unpublished place or API access off: run without saving
                DataService.enabled = false
            end
            return false, nil
        end
        if not lockedByOther then
            return true, result and result.data or nil
        end
        task.wait(5) -- the other server is still saving this player; give it time to release
    end
    return false, nil
end

-- release = true when the player is leaving (frees the session lock)
function DataService.save(userId: number, data, release: boolean?): boolean
    if not DataService.enabled or data == nil then
        return false
    end
    local success = attempt(function()
        store:UpdateAsync(key(userId), function(old)
            old = old or {}
            if old.lock and old.lock.job ~= JOB and os.time() - (old.lock.t or 0) < LOCK_TIMEOUT then
                return nil -- another server owns this player now; never overwrite it
            end
            return {
                data = data,
                lock = (not release) and { job = JOB, t = os.time() } or nil,
                savedAt = os.time(),
            }
        end)
    end, release and 5 or 3)
    return success
end

return DataService
