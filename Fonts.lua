local addonName, ns = ...
local LSM = LibStub("LibSharedMedia-3.0")

local abs = math.abs
local floor = math.floor

-- Shared Font objects for every piece of text the addon draws: the unit name, aura stack
-- counts, and aura countdowns.
--
-- Two problems shape this file.
--
-- 1. A font apply can fail silently. The client can report a successful SetFont without
--    applying it, and can revert a verified apply once the async load of the font file
--    finishes. Every apply is therefore checked with a GetFont read-back, and a failed
--    one is retried.
-- 2. Aura text lives on engine-owned buttons. Any write on a button, or on a region
--    parented to it, is denied while auras are secret. A fontstring linked to a Font
--    OBJECT escapes that: the object belongs to the addon, so changing the face or the
--    size later never touches the button. That is why sizes live on the objects and the
--    fontstrings are bound exactly once, inside the creation window.

-- The stock client font, captured at file load, before any addon can reassign the
-- STANDARD_TEXT_FONT global at login. The client preloads this file for its own UI, so a
-- fallback to it always applies.
local CLIENT_FONT = STANDARD_TEXT_FONT
local OUTLINE = "OUTLINE"

-- Resolved from CoTankTrackerDB.font by Resolve().
local fontPath = STANDARD_TEXT_FONT

-- One object per text role. Roles, not sizes: the addon draws few pieces of text, and a
-- size change must mutate an object the addon owns instead of re-pointing a fontstring
-- that the engine may have locked.
local objects = {}
local sizes = {}
local healthy = {}

local DEFAULT_SIZE = 12

local ScheduleReassert -- defined below

---One verified font apply. The return value of SetFont is ignored: a fontstring can
---return true without a real apply, and a Font object returns nothing. Outline flags are
---not compared, because the client reformats the flags string.
local function TrySetFont(target, path, size)
    if not pcall(target.SetFont, target, path, size, OUTLINE) then
        return false
    end
    local ok, appliedPath, appliedSize = pcall(target.GetFont, target)
    return ok and appliedPath == path and appliedSize ~= nil and abs(appliedSize - size) < 0.5
end

---Apply the configured face to one object, with fallbacks. An object must always carry a
---font: SetText on a fontstring linked to a font-less object raises an error.
local function AssertObject(role)
    local obj = objects[role]
    local size = sizes[role]
    if TrySetFont(obj, fontPath, size) then
        healthy[role] = true
        return
    end

    healthy[role] = false
    -- The live global first, because another addon can swap it game-wide, then the font
    -- captured at load.
    if fontPath == STANDARD_TEXT_FONT or not TrySetFont(obj, STANDARD_TEXT_FONT, size) then
        pcall(obj.SetFont, obj, CLIENT_FONT, size, OUTLINE)
    end
    ScheduleReassert()
end

---Re-apply every object the client reverted or never accepted.
local function ReassertObjects()
    for role, obj in pairs(objects) do
        local ok, path, size = pcall(obj.GetFont, obj)
        local intact = ok and path == fontPath and size ~= nil and abs(size - sizes[role]) < 0.5
        if intact then
            healthy[role] = true
        else
            AssertObject(role)
        end
    end
end

-- Retry budget for an object that failed a verified apply, for example a face whose file
-- is not loadable yet. The cap stops the timer for a face that never loads, and Resolve
-- resets it when the face changes.
local reassertScheduled = false
local reassertCount = 0
local MAX_REASSERTS = 10

ScheduleReassert = function()
    if reassertScheduled or reassertCount >= MAX_REASSERTS then
        return
    end
    reassertScheduled = true
    reassertCount = reassertCount + 1
    C_Timer.After(1.5, function()
        reassertScheduled = false
        ReassertObjects()
    end)
end

local function Object(role)
    local obj = objects[role]
    if not obj then
        obj = CreateFont("CoTankTrackerFont_" .. role)
        objects[role] = obj
        sizes[role] = DEFAULT_SIZE
        AssertObject(role)
    end
    return obj
end

ns.Fonts = {}

---Link one fontstring to its role object. Call this inside the creation window of an
---engine-owned button: the write is denied later, while auras are secret.
---@return boolean bound
function ns.Fonts.Bind(fontString, role)
    if not fontString then
        return false
    end
    local obj = Object(role)
    if fontString.GetFontObject and fontString:GetFontObject() == obj then
        return true
    end
    return pcall(fontString.SetFontObject, fontString, obj) and true or false
end

---Resize one role. Every fontstring bound to it follows, including those on buttons the
---engine has locked, because the write lands on the object rather than the button.
function ns.Fonts.SetSize(role, size)
    size = floor((size or DEFAULT_SIZE) + 0.5)
    Object(role)
    if sizes[role] == size then
        return
    end
    sizes[role] = size
    AssertObject(role)
end

---Read the configured face out of the saved variables and apply it everywhere. A
---loadability probe must not gate the result: a probe at login can fail for a face that
---loads a moment later.
function ns.Fonts.Resolve()
    local db = CoTankTrackerDB
    local path = db and db.font and LSM:Fetch("font", db.font)
    path = path or STANDARD_TEXT_FONT

    if path ~= fontPath then
        -- A new face gets a fresh retry budget.
        reassertCount = 0
    end
    fontPath = path
    ReassertObjects()
end

---Report the resolved face and how many role objects actually carry it. A face whose
---file never loads shows up here as an unhealthy count, which is what `/ctt debug` prints.
---@return string path
---@return number healthyRoles
---@return number totalRoles
function ns.Fonts.Status()
    local good, total = 0, 0
    for role in pairs(objects) do
        total = total + 1
        if healthy[role] then
            good = good + 1
        end
    end
    return fontPath, good, total
end

-- LSM can change what Fetch returns after login: a late registration of the configured
-- face, or a global override that makes every Fetch return it.
local function OnMediaChanged(_, mediatype)
    if mediatype == "font" then
        ns.Fonts.Resolve()
    end
end
LSM.RegisterCallback(ns.Fonts, "LibSharedMedia_Registered", OnMediaChanged)
LSM.RegisterCallback(ns.Fonts, "LibSharedMedia_SetGlobal", OnMediaChanged)

-- Zone-change loading screens pass neither flag and stay excluded.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loginFrame:SetScript("OnEvent", function(_, _, isInitialLogin, isReloadingUi)
    if not (isInitialLogin or isReloadingUi) then
        return
    end
    C_Timer.NewTicker(5, ReassertObjects, 6)
end)
