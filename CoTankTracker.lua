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
    -- Debuffs. These carry what private auras used to show: boss and role mechanics.
    showDebuffs = true,
    debuffSize = 36,
    debuffNum = 4,
    debuffMaxRows = 1,
    debuffSpacing = 2,
    debuffAnchor = "BOTTOMLEFT",
    debuffAttachTo = "TOPLEFT",
    debuffOffsetX = 0,
    debuffOffsetY = 2,
    debuffShowType = false,
    debuffFilter = "boss_role", -- "all", "raid", "important", "raid_important", "boss_role"
    debuffHidePermanent = false,
    debuffCountdownSize = 11,
    debuffStackSize = 11,
    debuffStackOffsetX = 1,
    debuffStackOffsetY = 1,
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
-- Secret-safe reads
-----------------------------------------------------------
-- Since 12.1 the unit identity, role, and aura APIs return secret values when the
-- unit identity is restricted. A secret value is not nil. Arithmetic, comparison,
-- table-key use, and a boolean test on a secret boolean all throw. Every such read
-- goes through Plain first. An unreadable value reads as nil, and each caller decides
-- what nil means.
local issecret = issecretvalue or function(_)
    return false
end

local function Plain(v)
    if issecret(v) then
        return nil
    end
    return v
end

-- Read one field of an aura struct. Returns nil when the struct or the field is secret.
local function AuraField(data, key)
    if data == nil or issecret(data) then
        return nil
    end
    return Plain(data[key])
end

-- Compare two unit tokens. Returns true, false, or nil when the identities cannot be
-- compared. oUF uses the same gate internally.
local function SameUnit(unitA, unitB)
    if C_Secrets and C_Secrets.CanCompareUnitTokens then
        if not Plain(C_Secrets.CanCompareUnitTokens(unitA, unitB)) then
            return nil
        end
    end
    return Plain(UnitIsUnit(unitA, unitB))
end

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
        cachedIsTank = Plain(PlayerUtil.IsPlayerEffectivelyTank()) or false
    else
        cachedIsTank = Plain(UnitGroupRolesAssigned("player")) == "TANK"
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
        -- Identity reads fail closed: a unit that cannot be compared against the player
        -- is skipped, so the player's own frame can never appear as a co-tank. Connection
        -- reads fail open, so an unreadable connection state never drops a tank.
        local isSelf = SameUnit(unit, "player")
        local connected = Plain(UnitIsConnected(unit)) ~= false
        if UnitExists(unit) and isSelf == false and connected then
            if Plain(UnitGroupRolesAssigned(unit)) == "TANK" then
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
-- Aura containers
-----------------------------------------------------------
-- Blizzard owns aura data since 12.1. The engine parses, filters, sorts, and renders
-- every icon through an AuraContainer, which oUF 14 exposes as frame:CreateAuras().
-- The addon only declares groups by filter string and styles the buttons it gets back.
--
-- Two rules drive the code below:
--   1. A button and every region parented to it can only be created inside the
--      creation window (the engine's initializeFrame callback).
--   2. Writes on a button, or on a region parented to it, are denied while auras are
--      secret. Every such write goes through ButtonWrite, which queues a retry for the
--      next time the restriction lifts.
--
-- All addon state for a container or a button lives in a weak-keyed side table, never
-- as a field on the engine object.
local auraButtons = setmetatable({}, { __mode = "k" }) -- [button] = { overlayHost, iconBorder, ... }
local auraState = setmetatable({}, { __mode = "k" }) -- [element] = { kind, keys, styled }
local restyleQueued = false

-- Growth direction values for the engine flow layout (AnchorUtil.FlowDirection).
local FLOW_DIR = { LEFT = -1, RIGHT = 1, UP = 1, DOWN = -1 }

local DEBUFF_BORDER_TEXTURE = [[Interface\Buttons\UI-Debuff-Overlays]]

-- Icon crop. Blizzard icon art carries a baked border, so every icon is inset by the
-- same fraction. The mock preview uses this too, so the preview cannot drift from the
-- real buttons.
local ICON_CROP = 0.07

-- Countdown text formatter, built once.
--
-- Blizzard's stock aura formatter is a SecondsFormatter, which always names its unit
-- ("42 sec" at best) with no option to drop it. A NumericRuleFormatter takes raw format
-- strings instead, so the text reads as a bare number under a minute and m:ss above it.
-- Seconds round up, so an aura with 0.4 seconds left reads "1" and never "0".
local durationFormatter

local function DurationFormatter()
    if durationFormatter == nil then
        local ok, formatter = pcall(function()
            local f = C_StringUtil.CreateNumericRuleFormatter()
            f:SetBreakpoints({
                {
                    threshold = 0,
                    format = "%d",
                    step = 1,
                    rounding = Enum.NumericRuleFormatRounding.Up,
                },
                {
                    threshold = 60,
                    format = "%d:%02d",
                    components = {
                        { div = 60, step = 1, rounding = Enum.NumericRuleFormatRounding.Down },
                        { mod = 60, step = 1, rounding = Enum.NumericRuleFormatRounding.Down },
                    },
                },
            })
            return f
        end)
        durationFormatter = ok and formatter or false
    end
    return durationFormatter or nil
end

-- Wrap width for the engine flow layout. The 0.4 slack absorbs rounding so the last
-- icon of a row never wraps on its own.
local function RowLimit(perRow, size, spacing)
    if perRow and perRow >= 2 then
        return perRow * size + (perRow - 1) * spacing + 0.4
    end
    return size + 0.4
end

-- Protected write on an engine-owned button. A denial means auras are secret right
-- now, so the write is retried on PLAYER_REGEN_ENABLED or ENCOUNTER_END.
local function ButtonWrite(fn, ...)
    if fn == nil then
        return false
    end
    local ok = pcall(fn, ...)
    if not ok then
        restyleQueued = true
    end
    return ok
end

-- Engine sort rules. BigDefensive orders by another player's cast first, then by the
-- longest remaining time. UnitFrameDebuff matches the Blizzard unit frame debuff order.
-- A missing member leaves the oUF default (ExpirationOnly).
local function SortMethod(name)
    return AuraContainerSortMethod and AuraContainerSortMethod[name]
end

local function DispelTextureStyle()
    local styles = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    -- PreserveAsset keeps our own border art and lets the engine tint it. Any other
    -- style stamps Blizzard atlas art over it.
    return styles and styles.PreserveAsset
end

-- Register or clear the dispel-type border. The engine drives the tint and the shown
-- state once the texture is registered, so the addon never reads a dispel type.
local function ApplyDispelBorder(kind, element, button, state)
    local border = state.dispelBorder
    if not border then
        return
    end
    local want = (kind == "debuff") and CoTankTrackerDB.debuffShowType and true or false
    if state.dispelOn == want then
        return
    end

    if want then
        local style = DispelTextureStyle()
        if style == nil then
            return
        end
        local colors = element.__owner and element.__owner.colors
        local ok = ButtonWrite(button.AddDispelTypeTexture, button, border, {
            style = style,
            showWhenHarmful = true,
            showWhenHelpful = false,
            customDispelColorMap = colors and colors.dispel,
        })
        if ok then
            state.dispelOn = true
        end
    elseif ButtonWrite(button.ClearDispelTypeTextures, button) then
        border:Hide()
        state.dispelOn = false
    end
end

-- Font roles per aura kind. Counts and countdowns are sized independently, so each gets
-- its own shared object.
local function AuraFontRoles(kind)
    if kind == "def" then
        return "defCount", "defDuration"
    end
    return "debuffCount", "debuffDuration"
end

local function AuraStyleValues(kind)
    local db = CoTankTrackerDB
    if kind == "def" then
        return db.defSize, db.defCountdownSize, db.defStackSize, db.defStackOffsetX, db.defStackOffsetY
    end
    return db.debuffSize, db.debuffCountdownSize, db.debuffStackSize, db.debuffStackOffsetX, db.debuffStackOffsetY
end

-- Apply every configurable visual to one button. Runs once in the creation window and
-- again after each settings change. Each write is stamped on success only, so an
-- unchanged value costs nothing and a denied write is attempted again on the retry.
local function StyleAuraButton(element, button)
    local state = auraButtons[button]
    local shared = auraState[element]
    if not (state and shared) then
        return
    end
    local db = CoTankTrackerDB
    local size, cdSize, stackSize, stackX, stackY = AuraStyleValues(shared.kind)

    if state.size ~= size and ButtonWrite(button.SetSize, button, size, size) then
        state.size = size
    end

    -- Text faces and sizes ride shared Font objects, so a settings change reaches these
    -- fontstrings even while auras are secret. Only the binding and the anchor are writes
    -- on the button, and the binding happens once.
    local countRole, timeRole = AuraFontRoles(shared.kind)
    ns.Fonts.SetSize(countRole, stackSize)
    ns.Fonts.SetSize(timeRole, cdSize)

    local count = button.Count
    if count then
        if not state.countBound then
            state.countBound = ns.Fonts.Bind(count, countRole)
            if not state.countBound then
                restyleQueued = true
            end
        end
        local countStamp = stackX .. ":" .. stackY
        if state.countStamp ~= countStamp then
            ButtonWrite(count.ClearAllPoints, count)
            if ButtonWrite(count.SetPoint, count, "BOTTOMRIGHT", stackX, stackY) then
                state.countStamp = countStamp
            end
        end
    end

    local time = button.Time
    if time then
        if not state.timeBound then
            state.timeBound = ns.Fonts.Bind(time, timeRole)
            if not state.timeBound then
                restyleQueued = true
            end
        end
        if not state.timeAnchored then
            ButtonWrite(time.ClearAllPoints, time)
            state.timeAnchored = ButtonWrite(time.SetPoint, time, "CENTER")
        end
    end

    -- Upgrade the countdown text from the stock "42 sec" to bare seconds and m:ss.
    -- oUF already bound the stock formatter, so a rejection here changes nothing. The
    -- call stays protected for a second reason: an uncaught error inside
    -- SetDurationText aborts the whole engine frame batch that created this button.
    local formatter = DurationFormatter()
    if time and formatter and not state.durationBound then
        if ButtonWrite(button.SetDurationText, button, time, { textFormatter = formatter }) then
            state.durationBound = true
        end
    end

    -- Crop the baked border off the icon art. The engine only calls SetTexture on each
    -- aura update, so texture coordinates set here survive every icon swap.
    local icon = button.Icon
    if icon and state.crop ~= ICON_CROP then
        if ButtonWrite(icon.SetTexCoord, icon, ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP) then
            state.crop = ICON_CROP
        end
    end

    local wantBorder = db.iconBorders and true or false
    if state.iconBorder and state.borderShown ~= wantBorder then
        if ButtonWrite(state.iconBorder.SetShown, state.iconBorder, wantBorder) then
            state.borderShown = wantBorder
        end
    end

    ApplyDispelBorder(shared.kind, element, button, state)
end

local function RestyleAuraButtons(element)
    local shared = element and auraState[element]
    if not shared then
        return
    end
    for button in pairs(shared.styled) do
        StyleAuraButton(element, button)
    end
end

-- Creation window. Everything the addon owns on a button must be built here.
local function PostCreateAuraButton(element, button)
    local shared = auraState[element]
    if not shared then
        return
    end

    local state = {}
    auraButtons[button] = state
    shared.styled[button] = true

    -- Host frame for our own art, one level above the cooldown swipe. The mouse stays
    -- with the button so tooltips keep working.
    local host = CreateFrame("Frame", nil, button)
    host:SetAllPoints()
    host:EnableMouse(false)
    if button.Cooldown then
        host:SetFrameLevel(button.Cooldown:GetFrameLevel() + 1)
    end
    state.overlayHost = host

    -- The addon draws its own duration text, so the Blizzard cooldown numbers stay off
    -- and no icon can show the time twice.
    if button.Cooldown then
        ButtonWrite(button.Cooldown.SetHideCountdownNumbers, button.Cooldown, true)
    end

    local iconBorder = CreateFrame("Frame", nil, host, "BackdropTemplate")
    iconBorder:SetPoint("TOPLEFT", -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    iconBorder:SetBackdrop({ edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1 })
    iconBorder:SetBackdropBorderColor(0, 0, 0, 1)
    iconBorder:SetFrameLevel(host:GetFrameLevel() + 1)
    state.iconBorder = iconBorder

    -- Dispel border art is always created, because it can never be created later. The
    -- engine only tints and shows it while it is registered.
    local border = host:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetTexture(DEBUFF_BORDER_TEXTURE)
    border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    border:Hide()
    state.dispelBorder = border
    state.dispelOn = false

    StyleAuraButton(element, button)
end

-- Group definitions. A group's filter string and candidate filters are fixed at
-- declaration, and groups are add-only on a container. Each configuration therefore
-- becomes its own variant, declared the first time the user selects it. A retired
-- variant stays declared and parks at zero icons.
--
-- WORKAROUND (12.1): C_UnitAuras.GetUnitAuraInstanceIDs applies the polarity of a
-- filter string but ignores the classification tokens. Measured on a co-tank whose
-- auras were readable: HELPFUL returned 3 ids, and HELPFUL|BIG_DEFENSIVE returned the
-- same 3, while IsAuraFilteredOutByInstanceID reported every one of them as neither a
-- big nor an external defensive. The aura container fetches through that list query and
-- reports hasMatchedFilterString = true, so the group never re-checks its own filter
-- string and displays every helpful aura. The UNIT_AURA path re-checks correctly, so
-- the row self-corrects as auras change, which is why the fault looks intermittent.
--
-- Candidate filters are evaluated on BOTH paths, so a duration bound narrows the group
-- where the filter string cannot. Every big and external defensive in the game runs
-- well under a minute, while the noise this removes is permanent or very long: flasks,
-- food, paladin auras, shapeshift forms. A max duration also excludes permanent auras
-- outright (the engine treats duration == 0 as failing the bound). Short non-defensive
-- buffs still leak, and they leak once per group. Remove this once the list query
-- honours the tokens.
local DEFENSIVE_MAX_DURATION = 60
local DEFENSIVE_CANDIDATES = { maxDuration = DEFENSIVE_MAX_DURATION }

local DEF_GROUPS = {
    { variant = "bigdef", filter = "HELPFUL|BIG_DEFENSIVE", candidateFilters = DEFENSIVE_CANDIDATES },
    -- Negated so an aura that carries both flags renders exactly once. A build that
    -- rejects the negated token falls back to the plain filter.
    {
        variant = "extdef",
        filter = "HELPFUL|EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE",
        fallback = "HELPFUL|EXTERNAL_DEFENSIVE",
        candidateFilters = DEFENSIVE_CANDIDATES,
    },
}

-- IMPORTANT is not a usable token here. Blizzard flags HELPFUL auras with it, so
-- HARMFUL|IMPORTANT is an empty set. The friendly-unit equivalents are engine candidate
-- filters, evaluated in AuraContainerUtil.DoesAuraPassCandidateFilters:
--   isPriorityAura     - the curated priority-debuff list the raid frames use
--   isBossOrRoleAura   - boss auras plus role auras (isTankRoleAura and its siblings),
--                        which is where 12.1 delivers tank mechanics as readable auras
local DEBUFF_FILTERS = {
    all = "HARMFUL",
    raid = "HARMFUL|RAID",
    important = "HARMFUL",
    raid_important = "HARMFUL|RAID",
    boss_role = "HARMFUL",
}
local DEBUFF_CANDIDATES = {
    important = { isPriorityAura = true },
    raid_important = { isPriorityAura = true },
    boss_role = { isBossOrRoleAura = true },
}

-- Group setters are engine methods on the container. They are guarded so that a build
-- without one degrades instead of breaking the whole settings pass.
local function SetGroupCount(element, key, count)
    if element.SetAuraGroupMaxFrameCount then
        element:SetAuraGroupMaxFrameCount(key, count)
    end
end

local function SetGroupLayout(element, key, layout)
    if element.SetAuraGroupLayout then
        element:SetAuraGroupLayout(key, layout)
    end
end

-- The groups an element must display right now. Every other declared variant parks.
local function WantedGroups(kind, db, out)
    for i = #out, 1, -1 do
        out[i] = nil
    end

    if kind == "def" then
        if db.showDefensives then
            out[1] = DEF_GROUPS[1]
            out[2] = DEF_GROUPS[2]
        end
        return out
    end

    if not db.showDebuffs then
        return out
    end

    local preset = db.debuffFilter or "all"
    local candidates
    local preset_candidates = DEBUFF_CANDIDATES[preset]
    if preset_candidates then
        candidates = {}
        for key, value in pairs(preset_candidates) do
            candidates[key] = value
        end
    end
    if db.debuffHidePermanent then
        candidates = candidates or {}
        -- The engine drops an aura when duration > maxDuration or duration == 0, so a
        -- limit of math.huge excludes permanent auras only.
        candidates.maxDuration = math.huge
    end

    out[1] = {
        variant = preset .. (db.debuffHidePermanent and "|timed" or ""),
        filter = DEBUFF_FILTERS[preset] or DEBUFF_FILTERS.all,
        candidateFilters = candidates,
    }
    return out
end

-- Declare a group once. Returns its record, plus true when this call declared it.
-- A record is { key = <engine group key>, filter = <filter string>, count = <last applied> }.
local function EnsureGroup(element, spec, count, layout)
    local keys = auraState[element].keys
    local record = keys[spec.variant]
    if record then
        return record, false
    end

    -- Every declaration allocates a button batch, so a group that shows nothing is
    -- never declared in the first place.
    if count <= 0 then
        return nil, false
    end

    local options = {
        maxFrameCount = count,
        candidateFilters = spec.candidateFilters,
        layout = layout,
    }
    local filter = spec.filter
    local ok, key = pcall(element.AddGroup, element, filter, options)
    if not ok and spec.fallback then
        filter = spec.fallback
        ok, key = pcall(element.AddGroup, element, filter, options)
    end
    if not ok then
        return nil, false
    end

    record = { key = key, filter = filter }
    keys[spec.variant] = record
    return record, true
end

local function AuraElementFor(frame, kind)
    if kind == "def" then
        return frame.Buffs
    end
    return frame.Debuffs
end

-- Every geometry value for one aura element, read from the shared settings.
local function AuraGeometry(kind)
    local db = CoTankTrackerDB
    if kind == "def" then
        return db.defSize,
            db.defMaxIcons,
            db.defMaxRows,
            db.defSpacing,
            db.defAnchor,
            db.defAttachTo,
            db.defOffsetX,
            db.defOffsetY,
            db.showDefensives
    end
    return db.debuffSize,
        db.debuffNum,
        db.debuffMaxRows,
        db.debuffSpacing,
        db.debuffAnchor,
        db.debuffAttachTo,
        db.debuffOffsetX,
        db.debuffOffsetY,
        db.showDebuffs
end

local function CreateAuraElement(frame, kind)
    local size, perRow, _, spacing, anchor, attachTo, offsetX, offsetY = AuraGeometry(kind)
    local initialAnchor, growthX, growthY = GrowthFromAttach(attachTo)

    local element = frame:CreateAuras({
        initialAnchor = initialAnchor,
        growthX = growthX,
        growthY = growthY,
        layoutLimit = RowLimit(perRow, size, spacing),
    })
    auraState[element] = {
        kind = kind,
        keys = {},
        styled = setmetatable({}, { __mode = "k" }),
    }
    element.size = size
    element.elementSpacing = spacing
    element.lineSpacing = spacing
    element.showCount = true
    element.showDuration = true
    element.tooltipAnchor = "ANCHOR_BOTTOMRIGHT"
    element.sortMethod = SortMethod(kind == "def" and "BigDefensive" or "UnitFrameDebuff")
    element.PostCreateButton = PostCreateAuraButton
    element:SetPoint(anchor, frame, attachTo, offsetX, offsetY)
    return element
end

local wantedScratch = {}

-- Apply all settings to one aura element: anchor, flow layout, group set, icon
-- counts, and button visuals. Safe to call in combat: every container call belongs to
-- a frame the addon owns, and every button call is protected.
local function ApplyAuraElement(frame, kind)
    local element = AuraElementFor(frame, kind)
    if not (element and auraState[element]) then
        return
    end
    local db = CoTankTrackerDB
    local size, perRow, rows, spacing, anchor, attachTo, offsetX, offsetY, shown = AuraGeometry(kind)
    local total = shown and (perRow * rows) or 0
    local initialAnchor, growthX, growthY = GrowthFromAttach(attachTo)

    element.size = size
    element.elementSpacing = spacing
    element.lineSpacing = spacing

    element:ClearAllPoints()
    element:SetPoint(anchor, frame, attachTo, offsetX, offsetY)
    element:SetFlowLayoutAnchorPoint(initialAnchor)
    element:SetFlowLayoutGrowthDirection(FLOW_DIR[growthX] or 1, FLOW_DIR[growthY] or 1)
    element:SetFlowLayoutMaximumLineSize(RowLimit(perRow, size, spacing))

    local wanted = WantedGroups(kind, db, wantedScratch)
    local active = {}
    local fresh = false
    for i = 1, #wanted do
        local spec = wanted[i]
        local layout = {
            elementWidth = size,
            elementHeight = size,
            elementSpacing = spacing,
            lineSpacing = spacing,
            layoutIndex = i,
        }
        local record, declared = EnsureGroup(element, spec, total, layout)
        if record then
            active[spec.variant] = true
            fresh = fresh or declared
            record.count = total
            SetGroupCount(element, record.key, total)
            SetGroupLayout(element, record.key, layout)
        end
    end

    for variant, record in pairs(auraState[element].keys) do
        if not active[variant] then
            record.count = 0
            SetGroupCount(element, record.key, 0)
        end
    end

    -- A group declared on a live container needs one refresh to pick up the auras that
    -- are already on the unit.
    if fresh then
        element:ForceUpdate()
    end

    RestyleAuraButtons(element)
end
ns.ApplyAuraElement = ApplyAuraElement

-- Read-only view of the container state, for the /ctt debug dump.
function ns.AuraElementState(element)
    return element and auraState[element]
end

-- Re-apply button visuals that the engine denied while auras were secret.
function ns.RetryAuraStyles()
    if not restyleQueued or not ns.coTankFrames then
        return
    end
    restyleQueued = false
    for _, frame in ipairs(ns.coTankFrames) do
        RestyleAuraButtons(frame.Buffs)
        RestyleAuraButtons(frame.Debuffs)
    end
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
    ns.Fonts.SetSize("name", db.nameFontSize)
    ns.Fonts.Bind(name, "name")
    frame:Tag(name, "[name]")
    frame.nameText = name

    -- Aura containers. Group declaration and icon counts are driven by ApplySettings.
    frame.Buffs = CreateAuraElement(frame, "def")
    frame.Debuffs = CreateAuraElement(frame, "debuff")
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

    -- Name. The face comes from the shared object, so only the size and the shown state
    -- are set here.
    if frame.nameText then
        ns.Fonts.SetSize("name", db.nameFontSize)
        ns.Fonts.Bind(frame.nameText, "name")
        frame.nameText:SetShown(db.showName)
    end

    -- Aura containers (defensives and debuffs)
    ApplyAuraElement(frame, "def")
    ApplyAuraElement(frame, "debuff")

    -- Force oUF to re-query and re-layout all elements
    if frame:IsShown() then
        frame:UpdateAllElements("ForceUpdate")
    end
end

function ns.ApplySettings()
    if not ns.coTankFrames then
        return
    end

    -- Picks up a font change, and re-asserts any object the client reverted.
    ns.Fonts.Resolve()

    for _, frame in ipairs(ns.coTankFrames) do
        ApplyFrameSettings(frame)
    end

    -- Re-anchor the stack (frame growth / spacing may have changed)
    ApplyStackAnchors()

    -- Update mocks if visible
    if ns.mockVisible then
        ns.UpdateMockAuras()
    end
end

-----------------------------------------------------------
-- Mock auras for preview
-----------------------------------------------------------
local mockDebuffButtons = {}
local mockDefButtons = {}
local mockDebuffContainer, mockDefContainer

local function CreateMockButton(parent, size, icon, debuffColor)
    local btn = CreateFrame("Frame", nil, parent)
    btn:SetSize(size, size)

    local tex = btn:CreateTexture(nil, "BORDER")
    tex:SetAllPoints()
    tex:SetTexture(icon)
    tex:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
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

    -- The preview binds the same Font objects as the real buttons, so the two can never
    -- show different text. The caller binds the roles for its own aura kind.
    local count = btn:CreateFontString(nil, "OVERLAY")
    count:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.Count = count

    local duration = btn:CreateFontString(nil, "OVERLAY")
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

    ns.Fonts.SetSize("debuffCount", db.debuffStackSize)
    ns.Fonts.SetSize("debuffDuration", db.debuffCountdownSize)
    ns.Fonts.SetSize("defCount", db.defStackSize)
    ns.Fonts.SetSize("defDuration", db.defCountdownSize)

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
        ns.Fonts.Bind(btn.Count, "debuffCount")
        btn.Count:ClearAllPoints()
        btn.Count:SetPoint("BOTTOMRIGHT", db.debuffStackOffsetX, db.debuffStackOffsetY)
        btn.Count:SetText(MOCK_DEBUFF_STACKS[((i - 1) % #MOCK_DEBUFF_STACKS) + 1])
        local dur = MOCK_DEBUFF_DURATIONS[((i - 1) % #MOCK_DEBUFF_DURATIONS) + 1]
        ns.Fonts.Bind(btn.Duration, "debuffDuration")
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
        ns.Fonts.Bind(btn.Count, "defCount")
        btn.Count:SetText(MOCK_DEF_STACKS[((i - 1) % #MOCK_DEF_STACKS) + 1])
        local dur = MOCK_DEF_DURATIONS[((i - 1) % #MOCK_DEF_DURATIONS) + 1]
        ns.Fonts.Bind(btn.Duration, "defDuration")
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
    ns.UpdateMockAuras()
end

function ns.HideMockAuras()
    ns.mockVisible = false
    if mockDebuffContainer then
        mockDebuffContainer:Hide()
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

-- Chat treats "|" as an escape introducer, so "HARMFUL|RAID" prints as "HARMFULAID"
-- unless every pipe is doubled.
local function Esc(text)
    return (tostring(text):gsub("|", "||"))
end

-- Every filter string the addon can hand to the engine. The dump validates each one,
-- so a token that a build no longer accepts shows up immediately.
local DEBUG_FILTERS = {
    "HELPFUL|BIG_DEFENSIVE",
    "HELPFUL|EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE",
    "HELPFUL|EXTERNAL_DEFENSIVE",
    "HARMFUL",
    "HARMFUL|RAID",
}

local function DumpAuraElement(label, element)
    local state = ns.AuraElementState(element)
    if not state then
        print("    " .. label .. ": missing")
        return
    end
    local unit = element.GetUnit and Plain(element:GetUnit())
    print(string.format("    %s: shown=%s containerUnit=%s", label, tostring(Plain(element:IsShown())), tostring(unit)))
    local any = false
    for variant, record in pairs(state.keys) do
        any = true
        print(
            string.format(
                "      group %s: key=%s icons=%s filter=%s",
                variant,
                tostring(record.key),
                tostring(record.count),
                Esc(record.filter)
            )
        )
    end
    if not any then
        print("      no groups declared")
    end
end

-- How many auras pass each filter, asked through the exact API the aura container uses
-- for its own groups. Equal counts for HELPFUL and HELPFUL|BIG_DEFENSIVE mean the
-- classification token is not restricting, which is the whole question.
local PROBE_FILTERS = {
    "HELPFUL",
    "HELPFUL|BIG_DEFENSIVE",
    "HELPFUL|EXTERNAL_DEFENSIVE",
    "HELPFUL|EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE",
    "HARMFUL",
}

local function CountAuras(unit, filter)
    if not C_UnitAuras.GetUnitAuraInstanceIDs then
        return nil, "api missing"
    end
    local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, filter)
    if not ok then
        return nil, "denied"
    end
    if ids == nil then
        return nil, "no data"
    end
    if issecret(ids) then
        return nil, "secret list"
    end
    -- The length operator throws on a secret container, so it is protected too.
    local okLen, count = pcall(function()
        return #ids
    end)
    if not okLen then
        return nil, "secret list"
    end
    return count
end

local function PrintCountProbe(unit)
    -- The player is measured too: aura data is always readable there, so a mismatch on
    -- the player proves the list query ignores the token regardless of secrecy.
    local units = { "player" }
    if unit then
        units[2] = unit
    else
        print("  count probe: no co-tank shown")
    end

    for _, probeUnit in ipairs(units) do
        print("  count probe for " .. probeUnit .. ":")
        for _, filter in ipairs(PROBE_FILTERS) do
            local count, reason = CountAuras(probeUnit, filter)
            print(string.format("    %s -> %s", Esc(filter), tostring(count or reason)))
        end
    end
end

-- Ask the engine how it classifies each helpful aura on a unit. This is the check that
-- tells us whether a buff belongs in the defensives row. Enumeration throws in a
-- restricted context, so run it out of combat. Every read is secret-safe.
local function PrintAuraProbe(unit)
    if not unit then
        print("  aura probe: no co-tank shown")
        return
    end
    print("  aura probe for " .. unit .. " (HELPFUL, out of combat only):")

    local shown = 0
    for i = 1, 40 do
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok then
            print("    enumeration denied at index " .. i .. " (auras are secret right now)")
            return
        end
        if data == nil then
            break
        end

        local id = AuraField(data, "auraInstanceID")
        local name = AuraField(data, "name")
        if id == nil then
            print(string.format("    %d: secret entry", i))
        else
            local bigOk, big = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, id, "HELPFUL|BIG_DEFENSIVE")
            local extOk, ext = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, id, "HELPFUL|EXTERNAL_DEFENSIVE")
            local function Verdict(callOk, filteredOut)
                if not callOk then
                    return "denied"
                end
                local plain = Plain(filteredOut)
                if plain == nil then
                    return "secret"
                end
                return tostring(plain == false)
            end
            print(
                string.format(
                    "    %s: big=%s external=%s",
                    tostring(name or id),
                    Verdict(bigOk, big),
                    Verdict(extOk, ext)
                )
            )
        end
        shown = shown + 1
    end

    if shown == 0 then
        print("    no helpful auras returned")
    end
end

-- Dump what the addon configured. Aura data is never read, only the values the addon
-- itself handed to the engine plus the unit each container is pointed at.
local function PrintDebug()
    PrintMsg("debug:")
    local restricted = C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()
    print(string.format("  oUF=%s secretRestrictions=%s", tostring(oUF.version), tostring(restricted)))

    local fontPath, healthyRoles, totalRoles = ns.Fonts.Status()
    print(string.format("  font=%s applied=%d/%d", tostring(fontPath), healthyRoles, totalRoles))

    for _, filter in ipairs(DEBUG_FILTERS) do
        if AuraUtil and AuraUtil.IsValidFilterString then
            local ok, reason = AuraUtil.IsValidFilterString(filter)
            print(string.format("  filter %s -> valid=%s %s", Esc(filter), tostring(ok), Esc(reason or "")))
        end
    end

    for i, frame in ipairs(ns.coTankFrames or {}) do
        print(
            string.format(
                "  frame %d: shown=%s attrUnit=%s oufUnit=%s",
                i,
                tostring(Plain(frame:IsShown())),
                tostring(frame:GetAttribute("unit")),
                tostring(frame.__unit)
            )
        )
        DumpAuraElement("defensives", frame.Buffs)
        DumpAuraElement("debuffs", frame.Debuffs)
    end

    local frames = ns.coTankFrames
    local probeUnit = frames and frames[1] and frames[1]:IsShown() and frames[1]:GetAttribute("unit")
    PrintCountProbe(probeUnit)
    PrintAuraProbe(probeUnit)
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
        local name = Plain(UnitName(unit)) or unit
        local class = Plain(select(2, UnitClass(unit)))
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
    elseif cmd == "debug" then
        PrintDebug()
    elseif cmd == "help" then
        PrintMsg("commands:")
        print("  |cffffcc00/ctt|r \226\128\148 open options")
        print("  |cffffcc00/ctt tanks|r \226\128\148 list detected co-tanks")
        print("  |cffffcc00/ctt show 1,2|r \226\128\148 show co-tanks 1 and 2 (or |cffffcc00all|r)")
        print("  |cffffcc00/ctt debug|r \226\128\148 dump frame, container and filter state")
    else
        PrintMsg("unknown command \226\128\148 type |cffffcc00/ctt help|r.")
    end
end

-----------------------------------------------------------
-- Defaults & migrations
-----------------------------------------------------------
local DB_VERSION = 3

local function DeepCopyDefaults(src, dst)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Private aura keys removed in DB_VERSION 3.
local PRIVATE_AURA_KEYS = {
    "showPrivateAuras",
    "paSize",
    "paMaxIcons",
    "paMaxRows",
    "paSpacing",
    "paShowBorder",
    "paShowCooldown",
    "paShowCooldownText",
    "paCooldownTextScale",
    "paAttachElement",
    "paAnchor",
    "paAttachTo",
    "paOffsetX",
    "paOffsetY",
}

local migrations = {
    [2] = function()
        -- showInParty was removed: addon now only activates inside raid instances.
        CoTankTrackerDB.showInParty = nil
    end,
    [3] = function()
        local db = CoTankTrackerDB
        -- Private aura support was removed. 12.1 renders private auras through aura
        -- containers, so the debuff row shows those mechanics now and the separate
        -- anchor display had nothing left to add.
        --
        -- Idempotent: the keys are cleared at the end, so a second run sees nil and
        -- does nothing.
        local hadPrivateAuras = db.showPrivateAuras
        if hadPrivateAuras == nil then
            return
        end

        if hadPrivateAuras then
            -- The debuff row takes over the display: same mechanics, same place, same
            -- geometry. A row that was anchored TO the debuffs keeps its own position,
            -- because adopting that anchor would offset the debuffs from themselves.
            db.showDebuffs = true
            db.debuffFilter = "boss_role"
            db.debuffHidePermanent = false
            db.debuffSize = db.paSize or db.debuffSize
            db.debuffNum = db.paMaxIcons or db.debuffNum
            db.debuffMaxRows = db.paMaxRows or db.debuffMaxRows
            db.debuffSpacing = db.paSpacing or db.debuffSpacing
            if db.paAttachElement ~= "debuffs" then
                db.debuffAnchor = db.paAnchor or db.debuffAnchor
                db.debuffAttachTo = db.paAttachTo or db.debuffAttachTo
                db.debuffOffsetX = db.paOffsetX or db.debuffOffsetX
                db.debuffOffsetY = db.paOffsetY or db.debuffOffsetY
            end
        end

        for i = 1, #PRIVATE_AURA_KEYS do
            db[PRIVATE_AURA_KEYS[i]] = nil
        end
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
    ns.ApplySettings()
    UpdateUnit()
end

-----------------------------------------------------------
-- Events
-----------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("UNIT_CONNECTION")
events:RegisterEvent("PLAYER_ROLES_ASSIGNED")
events:RegisterEvent("ROLE_CHANGED_INFORM")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("ENCOUNTER_END")

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        OnLogin()
        return
    end

    if not ns.coTankFrame then
        return
    end

    -- Both events mark the end of a context where auras are secret, so any button
    -- write the engine denied is retried here.
    if event == "PLAYER_REGEN_ENABLED" then
        ns.RetryAuraStyles()
        if pendingUpdate then
            pendingUpdate = false
            UpdateUnit()
        end
        return
    end

    if event == "ENCOUNTER_END" then
        ns.RetryAuraStyles()
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

    -- A tank going offline/online doesn't change the roster size, so it won't
    -- arrive as GROUP_ROSTER_UPDATE. Re-run detection so disconnected tanks drop
    -- out (FindOtherTanks skips them) and reconnected ones reappear.
    if event == "UNIT_CONNECTION" then
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
