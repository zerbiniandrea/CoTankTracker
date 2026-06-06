local addonName, ns = ...
local oUF = ns.oUF
local LSM = LibStub("LibSharedMedia-3.0")
ns.LSM = LSM

-----------------------------------------------------------
-- Defaults
-----------------------------------------------------------
local DEFAULTS = {
    width = 150,
    height = 20,
    point = "CENTER",
    x = 200,
    y = 0,
    locked = true,
    -- Multi-tank frames
    frameGrowth = "DOWN", -- stack direction for frames 2+ ("UP"/"DOWN"/"LEFT"/"RIGHT")
    frameSpacing = 80, -- gap between stacked frames (px); clears a 36px aura row above + below each bar
    requireTankSpec = false, -- only show frames when the player is a tank
    tankNotice = true, -- print a chat notice when more co-tanks are detected than shown
    optionsPanelScale = 1.0, -- UI scale of the options panel (0.8 - 1.5)
    showName = true,
    nameFontSize = 12,
    texture = "Blizzard Raid Bar",
    font = "Friz Quadrata TT",
    iconBorders = true,
    -- Debuffs
    showDebuffs = false,
    debuffSize = 32,
    debuffNum = 2,
    debuffMaxRows = 2,
    debuffSpacing = 2,
    debuffAnchor = "BOTTOMLEFT",
    debuffAttachTo = "TOPLEFT",
    debuffOffsetX = 0,
    debuffOffsetY = 2,
    debuffShowType = false,
    debuffFilter = "raid_important", -- "all", "raid", "important", "raid_important", "player"
    debuffHidePermanent = false,
    debuffCountdownSize = 11,
    debuffStackSize = 11,
    debuffStackOffsetX = -1,
    debuffStackOffsetY = 1,
    -- Private Auras
    showPrivateAuras = true,
    paSize = 36,
    paMaxIcons = 4,
    paMaxRows = 1,
    paSpacing = 2,
    paShowBorder = false,
    paShowCooldown = true,
    paShowCooldownText = true,
    paCooldownTextScale = 100,
    paAttachElement = "frame", -- "frame" or "debuffs"
    paAnchor = "BOTTOMLEFT",
    paAttachTo = "TOPLEFT",
    paOffsetX = 0,
    paOffsetY = 2,
    -- Defensives
    showDefensives = true,
    defSize = 36,
    defMaxIcons = 4,
    defMaxRows = 1,
    defSpacing = 2,
    defAnchor = "TOPLEFT",
    defAttachTo = "BOTTOMLEFT",
    defOffsetX = 0,
    defOffsetY = -2,
    defCountdownSize = 13,
    defStackSize = 11,
    defStackOffsetX = -1,
    defStackOffsetY = 1,
}
ns.DEFAULTS = DEFAULTS

-----------------------------------------------------------
-- Profiles (pre-configured layouts)
-----------------------------------------------------------
local PROFILES = {
    {
        name = "Private Auras Only",
        settings = {
            showDebuffs = false,
            showDefensives = true,
            showPrivateAuras = true,
            paSize = 36,
            paMaxIcons = 4,
            paMaxRows = 1,
            paAnchor = "BOTTOMLEFT",
            paAttachTo = "TOPLEFT",
            paOffsetX = 0,
            paOffsetY = 2,
        },
    },
    {
        name = "Full",
        settings = {
            showDebuffs = true,
            showDefensives = true,
            showPrivateAuras = true,
            paSize = 32,
            paMaxIcons = 2,
            paMaxRows = 2,
            paAnchor = "BOTTOMRIGHT",
            paAttachTo = "TOPRIGHT",
            paOffsetX = 0,
            paOffsetY = 2,
        },
    },
}
ns.PROFILES = PROFILES

function ns.ApplyProfile(index)
    local profile = PROFILES[index]
    if not profile then
        return
    end
    for k, v in pairs(profile.settings) do
        CoTankTrackerDB[k] = v
    end
    ns.ApplySettings()
end

-- Mock aura textures (common tank-relevant spells)
local MOCK_DEBUFF_ICONS = {
    135813, -- Sunder Armor / generic physical
    136066, -- Curse of Weakness (curse)
    132099, -- Shadow Word: Pain (magic)
    136016, -- Poisoned (poison)
    136127, -- Disease (disease)
    135945, -- Rend / bleed
}
local MOCK_DEFENSIVE_ICONS = {
    135919, -- Shield Wall
    135936, -- Pain Suppression
    136097, -- Ironbark
    132362, -- Ardent Defender
}
-- Debuff type colors matching oUF defaults
local DEBUFF_TYPE_COLORS = {
    { 0.8, 0.2, 0.2 }, -- none
    { 0.6, 0, 1 }, -- curse
    { 0.2, 0.6, 1 }, -- magic
    { 0, 0.6, 0 }, -- poison
    { 0.6, 0.4, 0 }, -- disease
    { 0.8, 0.2, 0.2 }, -- none
}

-----------------------------------------------------------
-- Cached state (event-driven invalidation)
-----------------------------------------------------------
local cachedIsTank = nil -- nil = not yet known
local cachedInRaid = nil -- true only when in a raid group AND inside a raid instance
local cachedGroupSize = nil

local function InvalidateTankCache()
    cachedIsTank = nil
end

local function InvalidateGroupCache()
    cachedInRaid = nil
    cachedGroupSize = nil
end

local function IsCombatLocked()
    return InCombatLockdown()
end

-----------------------------------------------------------
-- Tank detection
-----------------------------------------------------------
local function IsPlayerTankSpec()
    if cachedIsTank ~= nil then
        return cachedIsTank
    end
    if PlayerUtil and PlayerUtil.IsPlayerEffectivelyTank then
        cachedIsTank = PlayerUtil.IsPlayerEffectivelyTank()
    else
        cachedIsTank = UnitGroupRolesAssigned("player") == "TANK"
    end
    return cachedIsTank
end

-- Returns an ordered list of unit tokens for every non-player TANK in the raid.
-- Reuses the provided table (caller-owned) to avoid per-update allocations.
local function FindOtherTanks(out)
    out = out or {}
    for i = #out, 1, -1 do
        out[i] = nil
    end

    if cachedInRaid == nil then
        local _, instanceType = IsInInstance()
        cachedInRaid = IsInRaid() and instanceType == "raid"
        cachedGroupSize = GetNumGroupMembers()
    end

    if not cachedInRaid then
        return out
    end

    for i = 1, cachedGroupSize do
        local unit = "raid" .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            if UnitGroupRolesAssigned(unit) == "TANK" then
                out[#out + 1] = unit
            end
        end
    end

    return out
end

-----------------------------------------------------------
-- Growth direction derived from attach point
-----------------------------------------------------------
-- Icons grow inward toward the center of the frame.
-- Attach on the LEFT side  → grow RIGHT; RIGHT side → grow LEFT.
-- Attach on TOP            → grow DOWN;  BOTTOM     → grow UP.
local function GrowthFromAttach(attachPoint)
    local growthX = "RIGHT"
    local growthY = "DOWN"

    if attachPoint:find("RIGHT") then
        growthX = "LEFT"
    end
    if attachPoint:find("TOP") then
        growthY = "UP"
    elseif attachPoint:find("BOTTOM") then
        growthY = "DOWN"
    end

    -- initialAnchor = the corner icons start from (opposite of growth)
    local yPart = (growthY == "DOWN") and "TOP" or "BOTTOM"
    local xPart = (growthX == "LEFT") and "RIGHT" or "LEFT"
    local initialAnchor = yPart .. xPart

    return initialAnchor, growthX, growthY
end

-----------------------------------------------------------
-- Aura button styling
-----------------------------------------------------------
local function PostCreateAuraButton(element, button)
    local db = CoTankTrackerDB
    -- element.ctType is tagged at creation in StyleCoTank ("def" / "debuff"); identity
    -- comparison against ns.coTankFrame.* would be wrong for stacked frames 2+.
    local isDef = (element.ctType == "def")
    local isDebuff = (element.ctType == "debuff")
    local stackSize, stackOffX, stackOffY
    if isDef then
        stackSize = db.defStackSize
        stackOffX = db.defStackOffsetX
        stackOffY = db.defStackOffsetY
    elseif isDebuff then
        stackSize = db.debuffStackSize
        stackOffX = db.debuffStackOffsetX
        stackOffY = db.debuffStackOffsetY
    else
        stackSize = db.debuffStackSize
        stackOffX = db.debuffStackOffsetX
        stackOffY = db.debuffStackOffsetY
    end

    -- Restyle stack count
    if button.Count then
        button.Count:SetFont(STANDARD_TEXT_FONT, stackSize, "OUTLINE")
        button.Count:ClearAllPoints()
        button.Count:SetPoint("BOTTOMRIGHT", stackOffX, stackOffY)
    end

    -- Inner black border
    local iconBorder = CreateFrame("Frame", nil, button, "BackdropTemplate")
    iconBorder:SetPoint("TOPLEFT", -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    iconBorder:SetBackdrop({ edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1 })
    iconBorder:SetBackdropBorderColor(0, 0, 0, 1)
    iconBorder:SetFrameLevel(button:GetFrameLevel() + 2)
    iconBorder:SetShown(db.iconBorders)
    button.IconBorder_ = iconBorder
end

-----------------------------------------------------------
-- oUF style — always create all elements, show/hide via ApplySettings
-----------------------------------------------------------
local function StyleCoTank(frame)
    local db = CoTankTrackerDB
    frame:SetSize(db.width, db.height)

    -- Health bar
    local health = CreateFrame("StatusBar", nil, frame)
    health:SetAllPoints()
    health:SetStatusBarTexture(LSM:Fetch("statusbar", db.texture) or [[Interface\Buttons\WHITE8X8]])
    health.colorClass = true
    health.colorReaction = true
    health.colorDisconnected = true
    frame.Health = health

    -- Dark background behind health
    local bg = health:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- 1px border
    local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({ edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1 })
    border:SetBackdropBorderColor(0, 0, 0, 1)
    border:SetFrameLevel(frame:GetFrameLevel() + 2)

    -- Name text
    local name = health:CreateFontString(nil, "OVERLAY")
    name:SetPoint("CENTER")
    name:SetFont(LSM:Fetch("font", db.font) or STANDARD_TEXT_FONT, db.nameFontSize, "OUTLINE")
    frame:Tag(name, "[name]")
    frame.nameText = name

    -- Defensives (oUF Buffs element: BIG_DEFENSIVE + EXTERNAL_DEFENSIVE)
    local defTotal = db.defMaxIcons * db.defMaxRows
    local defensives = CreateFrame("Frame", nil, frame)
    defensives:SetSize(db.defMaxIcons * (db.defSize + db.defSpacing), db.defMaxRows * (db.defSize + db.defSpacing))
    defensives:SetPoint(db.defAnchor, frame, db.defAttachTo, db.defOffsetX, db.defOffsetY)
    defensives.size = db.defSize
    defensives.num = defTotal
    defensives.spacing = db.defSpacing
    defensives.initialAnchor, defensives.growthX, defensives.growthY = GrowthFromAttach(db.defAttachTo)
    defensives.filter = "HELPFUL"
    defensives.FilterAura = function(element, unit, data)
        local id = data.auraInstanceID
        if not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, id, "HELPFUL|BIG_DEFENSIVE") then
            return true
        end
        if not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, id, "HELPFUL|EXTERNAL_DEFENSIVE") then
            return true
        end
        return false
    end
    defensives.PostCreateButton = PostCreateAuraButton
    defensives.ctType = "def"
    frame.Buffs = defensives

    -- Debuffs (always created, visibility controlled by ApplySettings)
    local debuffs = CreateFrame("Frame", nil, frame)
    debuffs:SetSize(
        db.debuffNum * (db.debuffSize + db.debuffSpacing),
        db.debuffMaxRows * (db.debuffSize + db.debuffSpacing)
    )
    debuffs:SetPoint(db.debuffAnchor, frame, db.debuffAttachTo, db.debuffOffsetX, db.debuffOffsetY)
    debuffs.size = db.debuffSize
    debuffs.num = db.debuffNum * db.debuffMaxRows
    debuffs.spacing = db.debuffSpacing
    debuffs.initialAnchor, debuffs.growthX, debuffs.growthY = GrowthFromAttach(db.debuffAttachTo)
    debuffs.showDebuffType = db.debuffShowType
    ns.ApplyDebuffFilter(debuffs, db)
    debuffs.PostCreateButton = PostCreateAuraButton
    debuffs.ctType = "debuff"
    frame.Debuffs = debuffs
end

-----------------------------------------------------------
-- Filter logic
-----------------------------------------------------------

-- Debuff filter: Blizzard native C_UnitAuras filter strings
function ns.ApplyDebuffFilter(debuffs, db)
    local filter = db.debuffFilter
    if filter == "raid" then
        debuffs.filter = "HARMFUL|RAID"
    elseif filter == "important" then
        debuffs.filter = "HARMFUL|IMPORTANT"
    elseif filter == "raid_important" then
        debuffs.filter = "HARMFUL|RAID|IMPORTANT"
    else
        debuffs.filter = "HARMFUL"
    end

    local hidePermanent = db.debuffHidePermanent

    if hidePermanent then
        debuffs.FilterAura = function(element, unit, data)
            -- data.duration is a secret/tainted value; use the DurationObject API instead
            local duration = C_UnitAuras.GetAuraDuration(unit, data.auraInstanceID)
            if not duration then
                return false
            end
            return true
        end
    else
        debuffs.FilterAura = nil
    end
end

-----------------------------------------------------------
-- Public API (for Options.lua)
-----------------------------------------------------------
-- Pool of co-tank frames. ns.coTankFrame is kept as an alias for frame 1 (the stack
-- anchor) so Options.lua position controls, dragging, and mock containers keep working.
local MAX_FRAMES = 5
ns.coTankFrame = nil
ns.coTankFrames = nil
ns.MAX_FRAMES = MAX_FRAMES
ns.IsCombatLocked = IsCombatLocked
ns.IsPlayerTankSpec = IsPlayerTankSpec
ns.FindOtherTanks = FindOtherTanks

-----------------------------------------------------------
-- Private Aura anchors
-----------------------------------------------------------
-- Private aura anchors are managed per oUF frame so that several co-tanks can each
-- display their own Blizzard private auras simultaneously. Each frame keeps its own
-- pool (frame.paAnchors) and tracks the unit it is currently anchoring (frame.paUnit).
local function GetPARelativeFrame(frame)
    local db = CoTankTrackerDB
    if db.paAttachElement == "debuffs" and frame and frame.Debuffs then
        return frame.Debuffs
    end
    return frame
end

local PA_GROWTH = {
    RIGHT = { point = "LEFT", relPoint = "RIGHT", xMul = 1, yMul = 0 },
    LEFT = { point = "RIGHT", relPoint = "LEFT", xMul = -1, yMul = 0 },
    UP = { point = "BOTTOM", relPoint = "TOP", xMul = 0, yMul = 1 },
    DOWN = { point = "TOP", relPoint = "BOTTOM", xMul = 0, yMul = -1 },
}

local function ClearPrivateAuraAnchors(frame)
    if not frame then
        return
    end
    local anchors = frame.paAnchors
    if anchors then
        for i = 1, #anchors do
            local anchor = anchors[i]
            if anchor.paId then
                C_UnitAuras.RemovePrivateAuraAnchor(anchor.paId)
                anchor.paId = nil
            end
            anchor:ClearAllPoints()
            anchor:Hide()
        end
    end
    frame.paUnit = nil
end

local function UpdatePrivateAuraAnchors(frame, unitToken)
    if not frame then
        return
    end
    local anchors = frame.paAnchors
    if not anchors then
        anchors = {}
        frame.paAnchors = anchors
    end

    -- Remove existing anchors
    for i = 1, #anchors do
        local anchor = anchors[i]
        if anchor.paId then
            C_UnitAuras.RemovePrivateAuraAnchor(anchor.paId)
            anchor.paId = nil
        end
        anchor:ClearAllPoints()
        anchor:Hide()
    end

    local db = CoTankTrackerDB
    if not db.showPrivateAuras or not unitToken then
        frame.paUnit = nil
        return
    end

    frame.paUnit = unitToken
    local scale = math.max((db.paCooldownTextScale or 100) / 100, 0.01)
    local size = db.paSize * (1 / scale)
    local spacing = db.paSpacing * (1 / scale)
    local perRow = db.paMaxIcons
    local maxRows = db.paMaxRows
    local totalIcons = perRow * maxRows
    local _, growthX, growthY = GrowthFromAttach(db.paAttachTo)
    local hGrowth = PA_GROWTH[growthX] or PA_GROWTH.RIGHT
    local vGrowth = PA_GROWTH[growthY] or PA_GROWTH.UP
    local showBorder = db.paShowBorder
    local borderScale = showBorder and (size / 32 * 2) or -10000
    local namePrefix = "CoTankTrackerPA" .. (frame.paIndex or 1) .. "_"

    for i = 1, totalIcons do
        local anchor = anchors[i]
        if not anchor then
            anchor = CreateFrame("Frame", namePrefix .. i, UIParent)
            anchor:SetFrameStrata("MEDIUM")
            anchor:SetFixedFrameStrata(true)
            anchor:SetFrameLevel(1000)
            anchor:SetFixedFrameLevel(true)
            anchors[i] = anchor
        end

        anchor:SetSize(size, size)
        anchor:SetScale(scale)
        local col = (i - 1) % perRow
        if i == 1 then
            anchor:SetPoint(
                db.paAnchor,
                GetPARelativeFrame(frame),
                db.paAttachTo,
                db.paOffsetX / scale,
                db.paOffsetY / scale
            )
        elseif col == 0 then
            -- First icon of a new row: anchor relative to the first icon of the previous row
            local rowStart = anchors[i - perRow]
            anchor:SetPoint(vGrowth.point, rowStart, vGrowth.relPoint, spacing * vGrowth.xMul, spacing * vGrowth.yMul)
        else
            local prev = anchors[i - 1]
            anchor:SetPoint(hGrowth.point, prev, hGrowth.relPoint, spacing * hGrowth.xMul, spacing * hGrowth.yMul)
        end
        anchor:Show()

        anchor.paId = C_UnitAuras.AddPrivateAuraAnchor({
            unitToken = unitToken,
            auraIndex = i,
            parent = anchor,
            isContainer = false,
            showCountdownFrame = db.paShowCooldown,
            showCountdownNumbers = db.paShowCooldownText,
            iconInfo = {
                iconAnchor = {
                    point = "CENTER",
                    relativeTo = anchor,
                    relativePoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                },
                iconWidth = size,
                iconHeight = size,
                borderScale = borderScale,
            },
        })
    end

    -- Hide excess anchors
    for i = totalIcons + 1, #anchors do
        anchors[i]:Hide()
    end
end
ns.UpdatePrivateAuraAnchors = UpdatePrivateAuraAnchors
ns.ClearPrivateAuraAnchors = ClearPrivateAuraAnchors

-----------------------------------------------------------
-- Frame state management
-----------------------------------------------------------
local pendingUpdate = false
local testMode = false
local lastNoticedTankCount = nil
local detectedTanks = {} -- reused scratch table for UpdateUnit

-- Resolve db.selectedTanks into an ordered list of 1-based detected-tank indices.
-- "all" -> every detected index; a table -> its in-range, de-duplicated values.
-- Guarantees at least index 1 whenever tanks exist (a selection can never hide every
-- frame), matching the addon's original always-show-one behavior.
local function ResolveSelection(sel, count, out)
    out = out or {}
    for i = #out, 1, -1 do
        out[i] = nil
    end
    if sel == "all" then
        for i = 1, count do
            out[i] = i
        end
    elseif type(sel) == "table" then
        for _, idx in ipairs(sel) do
            if idx >= 1 and idx <= count then
                local dup = false
                for j = 1, #out do
                    if out[j] == idx then
                        dup = true
                        break
                    end
                end
                if not dup then
                    out[#out + 1] = idx
                end
            end
        end
    end
    -- Never resolve to an empty set while tanks are present.
    if #out == 0 and count > 0 then
        out[1] = 1
    end
    return out
end
ns.ResolveSelection = ResolveSelection

local function HideFramesFrom(startIdx)
    local frames = ns.coTankFrames
    if not frames then
        return
    end
    for i = startIdx, #frames do
        local f = frames[i]
        f:SetAttribute("unit", nil)
        f:Hide()
        ClearPrivateAuraAnchors(f)
    end
end

-- Print a one-line hint when more co-tanks exist than are currently shown.
local selScratch = {}
local function MaybeNoticeMoreTanks(detected, shown)
    if not CoTankTrackerDB.tankNotice then
        return
    end
    if detected > shown and detected ~= lastNoticedTankCount then
        print(
            string.format(
                "|cffffcc00CoTankTracker|r: %d co-tanks detected \226\128\148 |cffffcc00/ctt tanks|r to list, "
                    .. "|cffffcc00/ctt show 1,2|r to pick.",
                detected
            )
        )
        lastNoticedTankCount = detected
    elseif detected <= shown then
        -- Reset so the notice re-fires if the roster grows again later.
        lastNoticedTankCount = nil
    end
end

local function UpdateUnit()
    if IsCombatLocked() then
        return
    end
    if not ns.coTankFrames then
        return
    end

    if testMode then
        return
    end

    local tanks = FindOtherTanks(detectedTanks)
    local roleOk = (not CoTankTrackerDB.requireTankSpec) or IsPlayerTankSpec()
    local frames = ns.coTankFrames
    local shown = 0

    if roleOk and #tanks > 0 then
        local indices = ResolveSelection(CoTankTrackerDB.selectedTanks, #tanks, selScratch)
        for _, detIdx in ipairs(indices) do
            local unit = tanks[detIdx]
            if unit and shown < #frames then
                shown = shown + 1
                local f = frames[shown]
                f:SetAttribute("unit", unit)
                f:Show()
                UpdatePrivateAuraAnchors(f, unit)
            end
        end
    end

    HideFramesFrom(shown + 1)

    -- Only nudge when frames are actually displayable (role gate passed and tanks exist);
    -- otherwise reset so the notice re-fires once the situation changes.
    if roleOk and #tanks > 0 then
        MaybeNoticeMoreTanks(#tanks, shown)
    else
        lastNoticedTankCount = nil
    end
end
ns.UpdateUnit = UpdateUnit

local function QueueUpdate()
    if IsCombatLocked() then
        pendingUpdate = true
        return
    end
    UpdateUnit()
end

-- Trailing-edge debounce: roster events can burst (raid formation, mass invites)
-- and ZONE_CHANGED_NEW_AREA's instance API may return stale data on the first tick.
local deferredTimer = nil
local function ScheduleDeferredUpdate(delay)
    if deferredTimer then
        deferredTimer:Cancel()
    end
    deferredTimer = C_Timer.NewTimer(delay, function()
        deferredTimer = nil
        QueueUpdate()
    end)
end

function ns.EnterTestMode()
    if IsCombatLocked() or not ns.coTankFrames then
        return
    end
    testMode = true
    local frames = ns.coTankFrames
    -- Preview at least 2 frames (or however many are selected) so the stack layout is
    -- visible while options are open. Mock aura overlays render on frame 1 only.
    local indices = ResolveSelection(CoTankTrackerDB.selectedTanks, #frames, selScratch)
    local previewCount = math.max(2, #indices)
    previewCount = math.min(previewCount, #frames)
    for i = 1, previewCount do
        local f = frames[i]
        f:SetAttribute("unit", "player")
        f:Show()
    end
    HideFramesFrom(previewCount + 1)
    -- Private auras preview only on the anchor frame (mock overlays live there too).
    UpdatePrivateAuraAnchors(frames[1], "player")
    for i = 2, previewCount do
        ClearPrivateAuraAnchors(frames[i])
    end
end

function ns.ExitTestMode()
    testMode = false
    -- Frames can't be reassigned in combat; defer the live re-evaluation to
    -- PLAYER_REGEN_ENABLED so we don't strand the preview frames on "player".
    if IsCombatLocked() then
        pendingUpdate = true
        return
    end
    UpdateUnit()
end

function ns.IsTestMode()
    return testMode
end

-----------------------------------------------------------
-- Stack positioning (frames 2+ anchor to the frame above them)
-----------------------------------------------------------
local STACK_GROWTH = {
    DOWN = { point = "TOP", relPoint = "BOTTOM", x = 0, y = -1 },
    UP = { point = "BOTTOM", relPoint = "TOP", x = 0, y = 1 },
    LEFT = { point = "RIGHT", relPoint = "LEFT", x = -1, y = 0 },
    RIGHT = { point = "LEFT", relPoint = "RIGHT", x = 1, y = 0 },
}

-- Anchor each pool frame (2+) relative to the previous one. Frame 1 keeps its own
-- saved position on UIParent. Since assignment always fills frames 1..N contiguously,
-- hidden trailing frames never leave gaps in the stack.
local function ApplyStackAnchors()
    local frames = ns.coTankFrames
    if not frames or IsCombatLocked() then
        return
    end
    local db = CoTankTrackerDB
    local g = STACK_GROWTH[db.frameGrowth] or STACK_GROWTH.DOWN
    local spacing = db.frameSpacing or 0
    for i = 2, #frames do
        local f = frames[i]
        f:ClearAllPoints()
        f:SetPoint(g.point, frames[i - 1], g.relPoint, spacing * g.x, spacing * g.y)
    end
end
ns.ApplyStackAnchors = ApplyStackAnchors

-----------------------------------------------------------
-- Apply settings to live frame (no reload needed)
-----------------------------------------------------------
-- Apply all appearance settings to a single frame. Settings are shared across the pool,
-- so this is called for every frame in ns.coTankFrames.
local function ApplyFrameSettings(frame)
    local db = CoTankTrackerDB

    -- Frame size
    if not IsCombatLocked() then
        frame:SetSize(db.width, db.height)
    end

    -- Health bar texture
    if frame.Health then
        frame.Health:SetStatusBarTexture(LSM:Fetch("statusbar", db.texture) or [[Interface\Buttons\WHITE8X8]])
    end

    -- Name
    local fontPath = LSM:Fetch("font", db.font) or STANDARD_TEXT_FONT
    if frame.nameText then
        frame.nameText:SetFont(fontPath, db.nameFontSize, "OUTLINE")
        frame.nameText:SetShown(db.showName)
    end

    -- Defensives (Buffs element)
    local buffs = frame.Buffs
    if buffs then
        local defTotal = db.defMaxIcons * db.defMaxRows
        buffs.size = db.defSize
        buffs.num = db.showDefensives and defTotal or 0
        buffs.spacing = db.defSpacing
        buffs.initialAnchor, buffs.growthX, buffs.growthY = GrowthFromAttach(db.defAttachTo)
        buffs.needFullUpdate = true
        buffs.anchoredButtons = 0
        buffs:SetSize(db.defMaxIcons * (db.defSize + db.defSpacing), db.defMaxRows * (db.defSize + db.defSpacing))
        buffs:ClearAllPoints()
        buffs:SetPoint(db.defAnchor, frame, db.defAttachTo, db.defOffsetX, db.defOffsetY)
        for i = 1, buffs.createdButtons or 0 do
            local btn = buffs[i]
            if btn then
                btn:SetSize(db.defSize, db.defSize)
                if btn.Count then
                    btn.Count:SetFont(STANDARD_TEXT_FONT, db.defStackSize, "OUTLINE")
                    btn.Count:ClearAllPoints()
                    btn.Count:SetPoint("BOTTOMRIGHT", db.defStackOffsetX, db.defStackOffsetY)
                end
                if btn.Duration then
                    btn.Duration:SetFont(STANDARD_TEXT_FONT, db.defCountdownSize, "OUTLINE")
                end
                if btn.IconBorder_ then
                    btn.IconBorder_:SetShown(db.iconBorders)
                end
            end
        end
    end

    -- Debuffs
    local debuffs = frame.Debuffs
    if debuffs then
        debuffs.size = db.debuffSize
        local debuffTotal = db.debuffNum * db.debuffMaxRows
        debuffs.num = db.showDebuffs and debuffTotal or 0
        debuffs.spacing = db.debuffSpacing
        debuffs.initialAnchor, debuffs.growthX, debuffs.growthY = GrowthFromAttach(db.debuffAttachTo)
        debuffs.showDebuffType = db.debuffShowType
        ns.ApplyDebuffFilter(debuffs, db)
        debuffs.needFullUpdate = true
        debuffs.anchoredButtons = 0
        debuffs:SetSize(
            db.debuffNum * (db.debuffSize + db.debuffSpacing),
            db.debuffMaxRows * (db.debuffSize + db.debuffSpacing)
        )
        debuffs:ClearAllPoints()
        debuffs:SetPoint(db.debuffAnchor, frame, db.debuffAttachTo, db.debuffOffsetX, db.debuffOffsetY)
        for i = 1, debuffs.createdButtons or 0 do
            local btn = debuffs[i]
            if btn then
                btn:SetSize(db.debuffSize, db.debuffSize)
                if btn.Count then
                    btn.Count:SetFont(STANDARD_TEXT_FONT, db.debuffStackSize, "OUTLINE")
                    btn.Count:ClearAllPoints()
                    btn.Count:SetPoint("BOTTOMRIGHT", db.debuffStackOffsetX, db.debuffStackOffsetY)
                end
                if btn.Duration then
                    btn.Duration:SetFont(STANDARD_TEXT_FONT, db.debuffCountdownSize, "OUTLINE")
                end
                if btn.IconBorder_ then
                    btn.IconBorder_:SetShown(db.iconBorders)
                end
            end
        end
    end

    -- Force oUF to re-query and re-layout all elements
    if frame:IsShown() then
        frame:UpdateAllElements("ForceUpdate")
    end
end

function ns.ApplySettings()
    if not ns.coTankFrames then
        return
    end

    for _, frame in ipairs(ns.coTankFrames) do
        ApplyFrameSettings(frame)
    end

    -- Re-anchor the stack (frame growth / spacing may have changed)
    ApplyStackAnchors()

    -- Refresh private aura anchors for every frame currently tracking a unit
    for _, frame in ipairs(ns.coTankFrames) do
        if frame.paUnit then
            UpdatePrivateAuraAnchors(frame, frame.paUnit)
        end
    end

    -- Update mocks if visible
    if ns.mockVisible then
        ns.UpdateMockAuras()
    end
end

-----------------------------------------------------------
-- Mock auras for preview
-----------------------------------------------------------
local mockDebuffButtons = {}
local mockPAButtons = {}
local mockDefButtons = {}
local mockDebuffContainer, mockPAContainer, mockDefContainer

-- Private aura mock icons (common boss mechanic spells)
local MOCK_PA_ICONS = {
    237274, -- Incendiary Brand (tank debuff)
    135945, -- Rend / bleed
    136124, -- Shadow Bolt (magic)
    132365, -- Holy Shield
}
-- Dispel-type border colors for mock PA icons
local PA_BORDER_COLORS = {
    { 0.2, 0.6, 1 }, -- magic
    { 0.8, 0.2, 0.2 }, -- none / physical
    { 0.6, 0, 1 }, -- curse
    { 1, 0.82, 0 }, -- holy
}

local function CreateMockButton(parent, size, icon, debuffColor)
    local btn = CreateFrame("Frame", nil, parent)
    btn:SetSize(size, size)

    local tex = btn:CreateTexture(nil, "BORDER")
    tex:SetAllPoints()
    tex:SetTexture(icon)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.Icon = tex

    -- Cooldown swipe overlay (static partial fill)
    local cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:SetDrawEdge(true)
    cooldown:SetDrawSwipe(true)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetSwipeColor(0, 0, 0, 0.6)
    cooldown:Hide()
    btn.Cooldown = cooldown

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetTexture([[Interface\Buttons\UI-Debuff-Overlays]])
    border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    if debuffColor then
        border:SetVertexColor(debuffColor[1], debuffColor[2], debuffColor[3])
        border:Show()
    else
        border:Hide()
    end
    btn.Border = border

    -- Inner black border
    local iconBorder = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    iconBorder:SetPoint("TOPLEFT", -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    iconBorder:SetBackdrop({ edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1 })
    iconBorder:SetBackdropBorderColor(0, 0, 0, 1)
    iconBorder:SetFrameLevel(btn:GetFrameLevel() + 2)
    btn.IconBorder_ = iconBorder

    local count = btn:CreateFontString(nil, "OVERLAY")
    count:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.Count = count

    local duration = btn:CreateFontString(nil, "OVERLAY")
    duration:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    duration:SetPoint("CENTER", btn, "CENTER", 0, 0)
    duration:SetTextColor(1, 1, 1)
    btn.Duration = duration

    return btn
end

local function LayoutMockButtons(buttons, container, size, spacing, maxCols, initialAnchor)
    local sizeX = size + spacing
    local sizeY = size + spacing
    local growthX = initialAnchor:find("RIGHT") and -1 or 1
    local growthY = initialAnchor:find("BOTTOM") and 1 or -1

    for i, btn in ipairs(buttons) do
        if not btn:IsShown() then
            break
        end
        local col = (i - 1) % maxCols
        local row = math.floor((i - 1) / maxCols)
        btn:ClearAllPoints()
        btn:SetSize(size, size)
        btn:SetPoint(initialAnchor, container, initialAnchor, col * sizeX * growthX, row * sizeY * growthY)
    end
end

function ns.UpdateMockAuras()
    if not ns.coTankFrame then
        return
    end
    local db = CoTankTrackerDB
    local frame = ns.coTankFrame

    -- Ensure containers exist
    if not mockDebuffContainer then
        mockDebuffContainer = CreateFrame("Frame", nil, frame)
    end

    -- Debuffs
    local debuffPerRow = db.debuffNum
    local debuffRows = db.debuffMaxRows
    local debuffNum = db.showDebuffs and (debuffPerRow * debuffRows) or 0
    local cols = debuffPerRow

    mockDebuffContainer:SetSize(
        cols * (db.debuffSize + db.debuffSpacing),
        debuffRows * (db.debuffSize + db.debuffSpacing)
    )
    mockDebuffContainer:ClearAllPoints()
    mockDebuffContainer:SetPoint(db.debuffAnchor, frame, db.debuffAttachTo, db.debuffOffsetX, db.debuffOffsetY)

    local MOCK_DEBUFF_DURATIONS = { "12", "3.1", "45", "" }
    local MOCK_DEBUFF_STACKS = { "3", "", "2", "" }
    for i = 1, debuffNum do
        local color = db.debuffShowType and DEBUFF_TYPE_COLORS[((i - 1) % #DEBUFF_TYPE_COLORS) + 1] or nil
        if not mockDebuffButtons[i] then
            local iconIdx = ((i - 1) % #MOCK_DEBUFF_ICONS) + 1
            mockDebuffButtons[i] =
                CreateMockButton(mockDebuffContainer, db.debuffSize, MOCK_DEBUFF_ICONS[iconIdx], color)
        end
        local btn = mockDebuffButtons[i]
        btn.Icon:SetTexture(MOCK_DEBUFF_ICONS[((i - 1) % #MOCK_DEBUFF_ICONS) + 1])
        if color then
            btn.Border:SetVertexColor(color[1], color[2], color[3])
            btn.Border:Show()
        else
            btn.Border:Hide()
        end
        btn.Count:SetFont(STANDARD_TEXT_FONT, db.debuffStackSize, "OUTLINE")
        btn.Count:ClearAllPoints()
        btn.Count:SetPoint("BOTTOMRIGHT", db.debuffStackOffsetX, db.debuffStackOffsetY)
        btn.Count:SetText(MOCK_DEBUFF_STACKS[((i - 1) % #MOCK_DEBUFF_STACKS) + 1])
        local dur = MOCK_DEBUFF_DURATIONS[((i - 1) % #MOCK_DEBUFF_DURATIONS) + 1]
        btn.Duration:SetFont(STANDARD_TEXT_FONT, db.debuffCountdownSize, "OUTLINE")
        btn.Duration:SetText(dur)
        if dur ~= "" and btn.Cooldown then
            btn.Cooldown:SetCooldown(GetTime() - 5, 15)
            btn.Cooldown:Show()
        elseif btn.Cooldown then
            btn.Cooldown:Hide()
        end
        if btn.IconBorder_ then
            btn.IconBorder_:SetShown(db.iconBorders)
        end
        btn:Show()
    end
    for i = debuffNum + 1, #mockDebuffButtons do
        mockDebuffButtons[i]:Hide()
    end
    local debuffInitAnchor = GrowthFromAttach(db.debuffAttachTo)
    LayoutMockButtons(mockDebuffButtons, mockDebuffContainer, db.debuffSize, db.debuffSpacing, cols, debuffInitAnchor)
    mockDebuffContainer:SetShown(debuffNum > 0)

    -- Private Auras
    local paPerRow = db.paMaxIcons
    local paRows = db.paMaxRows
    local paNum = db.showPrivateAuras and (paPerRow * paRows) or 0

    if not mockPAContainer then
        mockPAContainer = CreateFrame("Frame", nil, frame)
        mockPAContainer:SetFrameStrata("MEDIUM")
        mockPAContainer:SetFrameLevel(1000)
    end

    local paScale = math.max((db.paCooldownTextScale or 100) / 100, 0.01)
    local paSize = db.paSize
    local paSpacing = db.paSpacing
    local paTotalWidth = paPerRow * (paSize + paSpacing)
    local paTotalHeight = paRows * (paSize + paSpacing)
    mockPAContainer:SetSize(math.max(1, paTotalWidth), math.max(1, paTotalHeight))
    mockPAContainer:ClearAllPoints()
    local paRelative = (db.paAttachElement == "debuffs" and mockDebuffContainer) and mockDebuffContainer or frame
    mockPAContainer:SetPoint(db.paAnchor, paRelative, db.paAttachTo, db.paOffsetX, db.paOffsetY)

    local _, paGrowthX, paGrowthY = GrowthFromAttach(db.paAttachTo)
    local hGrowth = PA_GROWTH[paGrowthX] or PA_GROWTH.RIGHT
    local vGrowth = PA_GROWTH[paGrowthY] or PA_GROWTH.UP

    local MOCK_PA_DURATIONS = { 12, 14, 0, 6, 0 }
    for i = 1, paNum do
        local color = db.paShowBorder and PA_BORDER_COLORS[((i - 1) % #PA_BORDER_COLORS) + 1] or nil
        if not mockPAButtons[i] then
            local iconIdx = ((i - 1) % #MOCK_PA_ICONS) + 1
            mockPAButtons[i] = CreateMockButton(mockPAContainer, paSize, MOCK_PA_ICONS[iconIdx], color)
        end
        local btn = mockPAButtons[i]
        btn.Icon:SetTexture(MOCK_PA_ICONS[((i - 1) % #MOCK_PA_ICONS) + 1])
        local scaledPASize = paSize * (1 / paScale)
        btn:SetSize(scaledPASize, scaledPASize)
        btn:SetScale(paScale)
        if color then
            btn.Border:SetVertexColor(color[1], color[2], color[3])
            btn.Border:Show()
        else
            btn.Border:Hide()
        end
        -- Private auras are rendered by Blizzard — use CooldownFrameTemplate's
        -- built-in countdown numbers to match the real appearance
        btn.Duration:SetText("")
        btn.Count:SetText("")
        local dur = MOCK_PA_DURATIONS[((i - 1) % #MOCK_PA_DURATIONS) + 1]
        if db.paShowCooldown and dur > 0 and btn.Cooldown then
            btn.Cooldown:SetHideCountdownNumbers(not db.paShowCooldownText)
            btn.Cooldown:SetCooldown(GetTime() - 4, dur)
            btn.Cooldown:Show()
        elseif btn.Cooldown then
            btn.Cooldown:Hide()
        end
        btn:ClearAllPoints()
        local scaledPASpacing = paSpacing * (1 / paScale)
        local paCol = (i - 1) % paPerRow
        if i == 1 then
            btn:SetPoint(db.paAnchor, mockPAContainer, db.paAnchor, 0, 0)
        elseif paCol == 0 then
            local rowStart = mockPAButtons[i - paPerRow]
            btn:SetPoint(
                vGrowth.point,
                rowStart,
                vGrowth.relPoint,
                scaledPASpacing * vGrowth.xMul,
                scaledPASpacing * vGrowth.yMul
            )
        else
            local prev = mockPAButtons[i - 1]
            btn:SetPoint(
                hGrowth.point,
                prev,
                hGrowth.relPoint,
                scaledPASpacing * hGrowth.xMul,
                scaledPASpacing * hGrowth.yMul
            )
        end
        if btn.IconBorder_ then
            btn.IconBorder_:SetShown(db.iconBorders)
        end
        btn:Show()
    end
    for i = paNum + 1, #mockPAButtons do
        mockPAButtons[i]:Hide()
    end
    mockPAContainer:SetShown(paNum > 0)

    -- Defensives
    local defPerRow = db.defMaxIcons
    local defRows = db.defMaxRows
    local defNum = db.showDefensives and (defPerRow * defRows) or 0

    if not mockDefContainer then
        mockDefContainer = CreateFrame("Frame", nil, frame)
    end

    local defSize = db.defSize
    local defSpacing = db.defSpacing
    mockDefContainer:SetSize(
        math.max(1, defPerRow * (defSize + defSpacing)),
        math.max(1, defRows * (defSize + defSpacing))
    )
    mockDefContainer:ClearAllPoints()
    mockDefContainer:SetPoint(db.defAnchor, frame, db.defAttachTo, db.defOffsetX, db.defOffsetY)

    local MOCK_DEF_DURATIONS = { "8.2", "12", "", "5.0" }
    local MOCK_DEF_STACKS = { "", "", "", "" }
    for i = 1, defNum do
        if not mockDefButtons[i] then
            local iconIdx = ((i - 1) % #MOCK_DEFENSIVE_ICONS) + 1
            mockDefButtons[i] = CreateMockButton(mockDefContainer, defSize, MOCK_DEFENSIVE_ICONS[iconIdx])
        end
        local btn = mockDefButtons[i]
        btn.Icon:SetTexture(MOCK_DEFENSIVE_ICONS[((i - 1) % #MOCK_DEFENSIVE_ICONS) + 1])
        btn:SetSize(defSize, defSize)
        btn.Border:Hide()
        btn.Count:SetFont(STANDARD_TEXT_FONT, db.defStackSize, "OUTLINE")
        btn.Count:SetText(MOCK_DEF_STACKS[((i - 1) % #MOCK_DEF_STACKS) + 1])
        local dur = MOCK_DEF_DURATIONS[((i - 1) % #MOCK_DEF_DURATIONS) + 1]
        btn.Duration:SetFont(STANDARD_TEXT_FONT, db.defCountdownSize, "OUTLINE")
        btn.Duration:SetText(dur)
        if dur ~= "" and btn.Cooldown then
            btn.Cooldown:SetCooldown(GetTime() - 3, 10)
            btn.Cooldown:Show()
        elseif btn.Cooldown then
            btn.Cooldown:Hide()
        end
        if btn.IconBorder_ then
            btn.IconBorder_:SetShown(db.iconBorders)
        end
        btn:Show()
    end
    for i = defNum + 1, #mockDefButtons do
        mockDefButtons[i]:Hide()
    end

    -- Layout mock defensives in grid
    local defCols = defPerRow
    local defInitAnchor = GrowthFromAttach(db.defAttachTo)
    LayoutMockButtons(mockDefButtons, mockDefContainer, defSize, defSpacing, defCols, defInitAnchor)
    mockDefContainer:SetShown(defNum > 0)
end

function ns.ShowMockAuras()
    ns.mockVisible = true
    -- Hide real oUF auras on every pool frame so preview frames 2+ stay plain bars
    -- and frame 1 shows only the mock overlays.
    for _, frame in ipairs(ns.coTankFrames or {}) do
        if frame.Buffs then
            frame.Buffs:Hide()
        end
        if frame.Debuffs then
            frame.Debuffs:Hide()
        end
    end
    -- Private aura anchors stay visible (they use Blizzard rendering)
    ns.UpdateMockAuras()
end

function ns.HideMockAuras()
    ns.mockVisible = false
    if mockDebuffContainer then
        mockDebuffContainer:Hide()
    end
    if mockPAContainer then
        mockPAContainer:Hide()
    end
    if mockDefContainer then
        mockDefContainer:Hide()
    end
    -- Restore real oUF auras on every pool frame
    for _, frame in ipairs(ns.coTankFrames or {}) do
        if frame.Buffs then
            frame.Buffs:Show()
        end
        if frame.Debuffs then
            frame.Debuffs:Show()
        end
        if frame:IsShown() then
            frame:UpdateAllElements("ForceUpdate")
        end
    end
end

-----------------------------------------------------------
-- Reset to defaults
-----------------------------------------------------------
function ns.ResetToDefaults()
    for k, v in pairs(DEFAULTS) do
        CoTankTrackerDB[k] = v
    end
    CoTankTrackerDB.selectedTanks = { 1 }
    ns.ApplySettings()
    if ns.coTankFrame and not IsCombatLocked() then
        ns.coTankFrame:ClearAllPoints()
        ns.coTankFrame:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.point, DEFAULTS.x, DEFAULTS.y)
        ns.ApplyStackAnchors()
    end
    ns.UpdateUnit()
end

-----------------------------------------------------------
-- Dragging
-----------------------------------------------------------
local function MakeDraggable(frame)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    frame:SetScript("OnMouseDown", function(self, button)
        local db = CoTankTrackerDB
        if button == "LeftButton" and not db.locked and not InCombatLockdown() then
            self:StartMoving()
        end
    end)

    frame:SetScript("OnMouseUp", function(self)
        local db = CoTankTrackerDB
        if db.locked or InCombatLockdown() then
            return
        end
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        db.point = point
        db.x = x
        db.y = y
        if ns.Components then
            ns.Components.RefreshAll()
        end
    end)
end

-----------------------------------------------------------
-- Slash commands
-----------------------------------------------------------
SLASH_COTANKTRACKER1 = "/cotanktracker"
SLASH_COTANKTRACKER2 = "/ctt"

local function PrintMsg(msg)
    print("|cffffcc00CoTankTracker|r: " .. msg)
end

-- Parse the argument of `/ctt show`: "all" -> "all", or a CSV of 1-based indices.
-- At least one tank is always shown, so an empty/invalid arg falls back to {1}.
local function ParseShowArg(arg)
    arg = arg:gsub("%s+", "")
    if arg == "all" then
        return "all"
    end
    local list, seen = {}, {}
    for num in arg:gmatch("%d+") do
        local n = tonumber(num)
        if n and n >= 1 and not seen[n] then
            seen[n] = true
            list[#list + 1] = n
        end
    end
    if #list == 0 then
        list[1] = 1
    end
    return list
end

local slashTanks = {}
local function PrintTankList()
    local tanks = FindOtherTanks(slashTanks)
    if #tanks == 0 then
        PrintMsg("no other tanks detected (you must be in a raid instance).")
        return
    end
    local indices = ResolveSelection(CoTankTrackerDB.selectedTanks, #tanks)
    local shownSet = {}
    for _, idx in ipairs(indices) do
        shownSet[idx] = true
    end
    PrintMsg(#tanks .. " co-tank(s) detected:")
    for i, unit in ipairs(tanks) do
        local name = UnitName(unit) or unit
        local _, class = UnitClass(unit)
        local color = class and RAID_CLASS_COLORS[class]
        if color then
            name = "|c" .. color.colorStr .. name .. "|r"
        end
        local marker = shownSet[i] and " |cff00ff00(shown)|r" or ""
        print(string.format("  %d. %s%s", i, name, marker))
    end
    print("  |cffffcc00/ctt show 1,2|r to choose \226\128\148 or |cffffcc00/ctt show all|r.")
end

SlashCmdList["COTANKTRACKER"] = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "config" or cmd == "options" then
        if ns.ToggleOptions then
            ns.ToggleOptions()
        end
    elseif cmd == "tanks" or cmd == "list" then
        PrintTankList()
    elseif cmd == "show" then
        CoTankTrackerDB.selectedTanks = ParseShowArg(rest:lower())
        ns.UpdateUnit()
        if ns.Components then
            ns.Components.RefreshAll()
        end
        PrintTankList()
    elseif cmd == "help" then
        PrintMsg("commands:")
        print("  |cffffcc00/ctt|r \226\128\148 open options")
        print("  |cffffcc00/ctt tanks|r \226\128\148 list detected co-tanks")
        print("  |cffffcc00/ctt show 1,2|r \226\128\148 show co-tanks 1 and 2 (or |cffffcc00all|r)")
    else
        PrintMsg("unknown command \226\128\148 type |cffffcc00/ctt help|r.")
    end
end

-----------------------------------------------------------
-- Defaults & migrations
-----------------------------------------------------------
local DB_VERSION = 2

local function DeepCopyDefaults(src, dst)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        end
    end
end

local migrations = {
    [2] = function()
        -- showInParty was removed: addon now only activates inside raid instances.
        CoTankTrackerDB.showInParty = nil
    end,
}

-----------------------------------------------------------
-- Init
-----------------------------------------------------------
local function OnLogin()
    if not CoTankTrackerDB then
        CoTankTrackerDB = {}
    end

    -- Run migrations
    local currentVersion = CoTankTrackerDB.dbVersion or 0
    for version = currentVersion + 1, DB_VERSION do
        if migrations[version] then
            migrations[version]()
        end
    end
    CoTankTrackerDB.dbVersion = DB_VERSION

    -- Fill in any missing defaults
    DeepCopyDefaults(DEFAULTS, CoTankTrackerDB)
    -- selectedTanks is a table/"all" value, so it can't live in DEFAULTS (DeepCopyDefaults
    -- would alias the shared default table). Initialize it explicitly.
    if type(CoTankTrackerDB.selectedTanks) ~= "table" and CoTankTrackerDB.selectedTanks ~= "all" then
        CoTankTrackerDB.selectedTanks = { 1 }
    end
    local db = CoTankTrackerDB

    oUF:RegisterStyle("CoTankTracker", StyleCoTank)
    oUF:SetActiveStyle("CoTankTracker")
    oUF.DisableBlizzard = function() end

    -- Spawn a fixed pool of co-tank frames. Frame 1 is the stack anchor; ns.coTankFrame
    -- aliases it so existing position/drag/mock code keeps working unchanged.
    ns.coTankFrames = {}
    for i = 1, MAX_FRAMES do
        local name = (i == 1) and "CoTankTrackerFrame" or ("CoTankTrackerFrame" .. i)
        local frame = oUF:Spawn("player", name)
        frame.paIndex = i
        UnregisterUnitWatch(frame)
        frame:Hide()
        ns.coTankFrames[i] = frame
    end
    ns.coTankFrame = ns.coTankFrames[1]

    ns.coTankFrame:ClearAllPoints()
    ns.coTankFrame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    ApplyStackAnchors()

    -- Only the anchor frame is draggable; it carries the rest of the stack with it.
    MakeDraggable(ns.coTankFrame)
    if db.showPrivateAuras and db.paShowBorder then
        C_UnitAuras.TriggerPrivateAuraShowDispelType(true)
    end
    ns.ApplySettings()
    UpdateUnit()
end

-----------------------------------------------------------
-- Events
-----------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ROLES_ASSIGNED")
events:RegisterEvent("ROLE_CHANGED_INFORM")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        OnLogin()
        return
    end

    if not ns.coTankFrame then
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if pendingUpdate then
            pendingUpdate = false
            UpdateUnit()
        end
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        InvalidateGroupCache()
        ScheduleDeferredUpdate(0.1)
        return
    end

    -- ZONE_CHANGED_NEW_AREA: IsInInstance() can return stale data on the first
    -- tick after the event fires, so defer slightly longer than the roster debounce.
    if event == "ZONE_CHANGED_NEW_AREA" then
        InvalidateGroupCache()
        ScheduleDeferredUpdate(0.2)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        InvalidateTankCache()
        InvalidateGroupCache()
    end

    if event == "PLAYER_ROLES_ASSIGNED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        InvalidateTankCache()
        InvalidateGroupCache()
    end

    if event == "ROLE_CHANGED_INFORM" then
        InvalidateTankCache()
    end

    QueueUpdate()
end)
