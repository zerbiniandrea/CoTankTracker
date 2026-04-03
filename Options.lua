local addonName, ns = ...
local Components = ns.Components
local LSM = ns.LSM

-----------------------------------------------------------
-- Constants
-----------------------------------------------------------
local PANEL_WIDTH = 460
local PANEL_HEIGHT = 580
local PADDING = 16
local COMPONENT_GAP = 6
local SECTION_GAP = 12
local TAB_HEIGHT = 22

local ANCHOR_OPTIONS = {
    { label = "Top Left", value = "TOPLEFT" },
    { label = "Top Right", value = "TOPRIGHT" },
    { label = "Bottom Left", value = "BOTTOMLEFT" },
    { label = "Bottom Right", value = "BOTTOMRIGHT" },
    { label = "Top", value = "TOP" },
    { label = "Bottom", value = "BOTTOM" },
    { label = "Left", value = "LEFT" },
    { label = "Right", value = "RIGHT" },
    { label = "Center", value = "CENTER" },
}

local DEBUFF_FILTER_OPTIONS = {
    { label = "All", value = "all" },
    { label = "Raid", value = "raid", desc = "Debuffs that appear on raid frames (HARMFUL|RAID)." },
    {
        label = "Important",
        value = "important",
        desc = "Important debuffs as defined by Blizzard (HARMFUL|IMPORTANT).",
    },
    {
        label = "Raid + Important",
        value = "raid_important",
        desc = "Raid debuffs marked as important (HARMFUL|RAID|IMPORTANT).",
    },
}

-----------------------------------------------------------
-- LSM dropdown helpers
-----------------------------------------------------------
local function GetLSMOptions(mediatype)
    local list = LSM:HashTable(mediatype)
    local options = {}
    for name in pairs(list) do
        options[#options + 1] = { label = name, value = name }
    end
    table.sort(options, function(a, b)
        return a.label < b.label
    end)
    return options
end

-----------------------------------------------------------
-- Options panel
-----------------------------------------------------------
local panel
local tabs = {}
local tabContents = {}
local activeTab

local function SetActiveTab(name)
    if activeTab == name then
        return
    end
    activeTab = name
    for tabName, tab in pairs(tabs) do
        tab:SetActive(tabName == name)
    end
    for tabName, content in pairs(tabContents) do
        content:SetShown(tabName == name)
    end
end

local function CreateTab(parent, name, label, x)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(90, TAB_HEIGHT)
    tab:SetPoint("TOPLEFT", x, 0)
    tab.tabName = name

    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 0)
    bg:SetColorTexture(0.2, 0.2, 0.2, 0)
    tab.bg = bg

    local bottomLine = tab:CreateTexture(nil, "BORDER")
    bottomLine:SetHeight(2)
    bottomLine:SetPoint("BOTTOMLEFT", 1, 0)
    bottomLine:SetPoint("BOTTOMRIGHT", -1, 0)
    bottomLine:SetColorTexture(0.6, 0.6, 0.6, 0)
    tab.bottomLine = bottomLine

    local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", 0, 0)
    text:SetText(label)
    tab.text = text

    tab:SetScript("OnEnter", function(self)
        if not self.isActive then
            self.bg:SetColorTexture(0.25, 0.25, 0.25, 0.5)
        end
    end)
    tab:SetScript("OnLeave", function(self)
        if not self.isActive then
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 0)
        end
    end)
    tab:SetScript("OnClick", function()
        SetActiveTab(name)
    end)

    function tab:SetActive(active)
        self.isActive = active
        if active then
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
            self.bottomLine:SetColorTexture(0.8, 0.6, 0, 1)
            self.text:SetFontObject("GameFontHighlightSmall")
        else
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 0)
            self.bottomLine:SetColorTexture(0.6, 0.6, 0.6, 0)
            self.text:SetFontObject("GameFontNormalSmall")
        end
    end

    tabs[name] = tab
    return tab
end

local function CreateScrollContent(parent)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:SetAllPoints()

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(PANEL_WIDTH - PADDING * 2)
    content:SetHeight(800)
    scrollFrame:SetScrollChild(content)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
        local newScroll = math.max(0, math.min(maxScroll, current - delta * 30))
        self:SetVerticalScroll(newScroll)
    end)

    return scrollFrame, content
end

-----------------------------------------------------------
-- Tab: General
-----------------------------------------------------------
local function BuildGeneralTab(parent)
    local scrollFrame, content = CreateScrollContent(parent)
    local y = 0

    -- Frame
    local _, newY = ns.CreateSectionHeader(content, "Frame", 0, y)
    y = newY

    local widthSlider = Components.Slider(content, {
        label = "Width",
        min = 60,
        max = 400,
        step = 5,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.width
        end,
        onChange = function(val)
            CoTankTrackerDB.width = val
            ns.ApplySettings()
        end,
    })
    widthSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local heightSlider = Components.Slider(content, {
        label = "Height",
        min = 8,
        max = 60,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.height
        end,
        onChange = function(val)
            CoTankTrackerDB.height = val
            ns.ApplySettings()
        end,
    })
    heightSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Name
    local _, newYName = ns.CreateSectionHeader(content, "Name", 0, y)
    y = newYName

    local showNameCb = Components.Checkbox(content, {
        label = "Show name",
        get = function()
            return CoTankTrackerDB.showName
        end,
        onChange = function(checked)
            CoTankTrackerDB.showName = checked
            ns.ApplySettings()
            Components.RefreshAll()
        end,
    })
    showNameCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local fontSizeSlider = Components.Slider(content, {
        label = "Font Size",
        labelWidth = 70,
        min = 6,
        max = 24,
        step = 1,
        suffix = "pt",
        get = function()
            return CoTankTrackerDB.nameFontSize
        end,
        enabled = function()
            return CoTankTrackerDB.showName
        end,
        onChange = function(val)
            CoTankTrackerDB.nameFontSize = val
            ns.ApplySettings()
        end,
    })
    fontSizeSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Appearance
    local _, newYAppearance = ns.CreateSectionHeader(content, "Appearance", 0, y)
    y = newYAppearance

    local textureDd = Components.Dropdown(content, {
        label = "Texture",
        width = 160,
        options = GetLSMOptions("statusbar"),
        get = function()
            return CoTankTrackerDB.texture
        end,
        onChange = function(val)
            CoTankTrackerDB.texture = val
            ns.ApplySettings()
        end,
    })
    textureDd:SetPoint("TOPLEFT", 0, y)
    y = y - 26 - COMPONENT_GAP

    local fontDd = Components.Dropdown(content, {
        label = "Font",
        width = 160,
        options = GetLSMOptions("font"),
        get = function()
            return CoTankTrackerDB.font
        end,
        onChange = function(val)
            CoTankTrackerDB.font = val
            ns.ApplySettings()
        end,
    })
    fontDd:SetPoint("TOPLEFT", 0, y)
    y = y - 26 - COMPONENT_GAP

    local iconBordersCb = Components.Checkbox(content, {
        label = "Icon borders",
        get = function()
            return CoTankTrackerDB.iconBorders
        end,
        tooltip = {
            title = "Icon Borders",
            desc = "Show a thin black border around buff, debuff, and private aura icons.",
        },
        onChange = function(checked)
            CoTankTrackerDB.iconBorders = checked
            ns.ApplySettings()
        end,
    })
    iconBordersCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Behavior
    local _, newYBehavior = ns.CreateSectionHeader(content, "Behavior", 0, y)
    y = newYBehavior

    local showInPartyCb = Components.Checkbox(content, {
        label = "Show in party (not just raid)",
        get = function()
            return CoTankTrackerDB.showInParty
        end,
        tooltip = { title = "Party Mode", desc = "Also detect the other tank in 5-man parties." },
        onChange = function(checked)
            CoTankTrackerDB.showInParty = checked
            ns.UpdateUnit()
        end,
    })
    showInPartyCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local lockedCb = Components.Checkbox(content, {
        label = "Lock frame",
        get = function()
            return CoTankTrackerDB.locked
        end,
        tooltip = { title = "Lock", desc = "When unlocked, drag the frame to reposition it." },
        onChange = function(checked)
            CoTankTrackerDB.locked = checked
        end,
    })
    lockedCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Position
    local _, newYPos = ns.CreateSectionHeader(content, "Position", 0, y)
    y = newYPos

    local resetPosBtn = ns.CreateButton(content, "Reset Position", function()
        if InCombatLockdown() then
            return
        end
        local db = CoTankTrackerDB
        db.point = "CENTER"
        db.x = 200
        db.y = 0
        ns.coTankFrame:ClearAllPoints()
        ns.coTankFrame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    end)
    resetPosBtn:SetPoint("TOPLEFT", 0, y)
    y = y - 22 - SECTION_GAP

    -- Profiles
    local _, newYProfiles = ns.CreateSectionHeader(content, "Profiles", 0, y)
    y = newYProfiles

    local profileOptions = { placeholder = "Select a profile" }
    for i, profile in ipairs(ns.PROFILES) do
        profileOptions[#profileOptions + 1] = { label = profile.name, value = i }
    end
    local profileDropdown = Components.Dropdown(content, {
        label = "Profile",
        labelWidth = 50,
        width = 150,
        options = profileOptions,
        onChange = function(value)
            ns.ApplyProfile(value)
            Components.RefreshAll()
            if ns.mockVisible then
                ns.UpdateMockAuras()
            end
        end,
    })
    profileDropdown:SetPoint("TOPLEFT", 0, y)
    y = y - 26 - SECTION_GAP

    -- Danger Zone
    local _, newYDanger = ns.CreateSectionHeader(content, "Danger Zone", 0, y)
    y = newYDanger

    local resetAllBtn = ns.CreateButton(content, "Reset All to Defaults", function()
        ns.ResetToDefaults()
        Components.RefreshAll()
        if ns.mockVisible then
            ns.UpdateMockAuras()
        end
    end)
    resetAllBtn:SetPoint("TOPLEFT", 0, y)
    y = y - 22

    content:SetHeight(math.abs(y) + 20)
    return scrollFrame
end

-----------------------------------------------------------
-- Tab: Debuffs
-----------------------------------------------------------
local function BuildDebuffsTab(parent)
    local scrollFrame, content = CreateScrollContent(parent)
    local y = 0
    local enabled = function()
        return CoTankTrackerDB.showDebuffs
    end

    local showDebuffsCb = Components.Checkbox(content, {
        label = "Show debuffs",
        get = function()
            return CoTankTrackerDB.showDebuffs
        end,
        onChange = function(checked)
            CoTankTrackerDB.showDebuffs = checked
            ns.ApplySettings()
            Components.RefreshAll()
        end,
    })
    showDebuffsCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Layout
    local _, newYLayout = ns.CreateSectionHeader(content, "Layout", 0, y)
    y = newYLayout

    local debuffSizeSlider = Components.Slider(content, {
        label = "Size",
        min = 10,
        max = 64,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.debuffSize
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.debuffSize = val
            ns.ApplySettings()
        end,
    })
    debuffSizeSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local debuffNumSlider = Components.Slider(content, {
        label = "Per Row",
        min = 1,
        max = 16,
        step = 1,
        get = function()
            return CoTankTrackerDB.debuffNum
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.debuffNum = val
            ns.ApplySettings()
        end,
    })
    debuffNumSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local debuffMaxRowsSlider = Components.Slider(content, {
        label = "Max Rows",
        labelWidth = 70,
        min = 1,
        max = 4,
        step = 1,
        get = function()
            return CoTankTrackerDB.debuffMaxRows
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.debuffMaxRows = val
            ns.ApplySettings()
        end,
    })
    debuffMaxRowsSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local debuffSpacingSlider = Components.Slider(content, {
        label = "Spacing",
        min = 0,
        max = 8,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.debuffSpacing
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.debuffSpacing = val
            ns.ApplySettings()
        end,
    })
    debuffSpacingSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Text
    local _, newYText = ns.CreateSectionHeader(content, "Text", 0, y)
    y = newYText

    local debuffCdSizeSlider = Components.Slider(content, {
        label = "Countdown",
        labelWidth = 80,
        min = 6,
        max = 24,
        step = 1,
        suffix = "pt",
        get = function()
            return CoTankTrackerDB.debuffCountdownSize
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.debuffCountdownSize = val
            ns.ApplySettings()
        end,
    })
    debuffCdSizeSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local debuffStackSizeSlider = Components.Slider(content, {
        label = "Stacks",
        min = 6,
        max = 24,
        step = 1,
        suffix = "pt",
        get = function()
            return CoTankTrackerDB.debuffStackSize
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.debuffStackSize = val
            ns.ApplySettings()
        end,
    })
    debuffStackSizeSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Display
    local _, newYDisplay = ns.CreateSectionHeader(content, "Display", 0, y)
    y = newYDisplay

    local debuffTypeCb = Components.Checkbox(content, {
        label = "Color border by debuff type",
        get = function()
            return CoTankTrackerDB.debuffShowType
        end,
        enabled = enabled,
        tooltip = {
            title = "Debuff Type",
            desc = "Colors the debuff border by dispel type (Magic, Curse, Poison, Disease).",
        },
        onChange = function(checked)
            CoTankTrackerDB.debuffShowType = checked
            ns.ApplySettings()
        end,
    })
    debuffTypeCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Filtering
    local _, newYFilter = ns.CreateSectionHeader(content, "Filtering", 0, y)
    y = newYFilter

    local debuffFilterDd = Components.Dropdown(content, {
        label = "Show",
        width = 140,
        options = DEBUFF_FILTER_OPTIONS,
        get = function()
            return CoTankTrackerDB.debuffFilter
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.debuffFilter = val
            ns.ApplySettings()
        end,
    })
    debuffFilterDd:SetPoint("TOPLEFT", 0, y)
    y = y - 26 - COMPONENT_GAP

    local debuffHidePermanentCb = Components.Checkbox(content, {
        label = "Hide permanent auras",
        get = function()
            return CoTankTrackerDB.debuffHidePermanent
        end,
        enabled = enabled,
        tooltip = { title = "Hide Permanent", desc = "Hides debuffs with no duration (e.g. permanent boss mechanics)." },
        onChange = function(checked)
            CoTankTrackerDB.debuffHidePermanent = checked
            ns.ApplySettings()
        end,
    })
    debuffHidePermanentCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Positioning
    local _, newYPos = ns.CreateSectionHeader(content, "Positioning", 0, y)
    y = newYPos

    local debuffAnchorDd = Components.Dropdown(content, {
        label = "Anchor",
        width = 120,
        options = ANCHOR_OPTIONS,
        get = function()
            return CoTankTrackerDB.debuffAnchor
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.debuffAnchor = val
            ns.ApplySettings()
        end,
    })
    debuffAnchorDd:SetPoint("TOPLEFT", 0, y)
    y = y - 26 - COMPONENT_GAP

    local debuffAttachDd = Components.Dropdown(content, {
        label = "Attach To",
        width = 120,
        options = ANCHOR_OPTIONS,
        get = function()
            return CoTankTrackerDB.debuffAttachTo
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.debuffAttachTo = val
            ns.ApplySettings()
        end,
    })
    debuffAttachDd:SetPoint("TOPLEFT", 0, y)
    y = y - 26 - COMPONENT_GAP

    local debuffOffXSlider = Components.Slider(content, {
        label = "Offset X",
        min = -50,
        max = 50,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.debuffOffsetX
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.debuffOffsetX = val
            ns.ApplySettings()
        end,
    })
    debuffOffXSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local debuffOffYSlider = Components.Slider(content, {
        label = "Offset Y",
        min = -50,
        max = 50,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.debuffOffsetY
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.debuffOffsetY = val
            ns.ApplySettings()
        end,
    })
    debuffOffYSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local debuffStackOffXSlider = Components.Slider(content, {
        label = "Stack X",
        min = -20,
        max = 20,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.debuffStackOffsetX
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.debuffStackOffsetX = val
            ns.ApplySettings()
        end,
    })
    debuffStackOffXSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local debuffStackOffYSlider = Components.Slider(content, {
        label = "Stack Y",
        min = -20,
        max = 20,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.debuffStackOffsetY
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.debuffStackOffsetY = val
            ns.ApplySettings()
        end,
    })
    debuffStackOffYSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20

    content:SetHeight(math.abs(y) + 20)
    return scrollFrame
end

-----------------------------------------------------------
-- Tab: Private Auras
-----------------------------------------------------------
local function BuildPrivateAurasTab(parent)
    local scrollFrame, content = CreateScrollContent(parent)
    local y = 0
    local enabled = function()
        return CoTankTrackerDB.showPrivateAuras
    end

    local showPACb = Components.Checkbox(content, {
        label = "Show private auras",
        get = function()
            return CoTankTrackerDB.showPrivateAuras
        end,
        tooltip = {
            title = "Private Auras",
            desc = "Display Blizzard private auras on your co-tank using the native C_UnitAuras anchor API. These are boss mechanic auras that are normally only visible to the affected player.",
        },
        onChange = function(checked)
            CoTankTrackerDB.showPrivateAuras = checked
            if checked and CoTankTrackerDB.paShowBorder then
                C_UnitAuras.TriggerPrivateAuraShowDispelType(true)
            end
            ns.ApplySettings()
            Components.RefreshAll()
        end,
    })
    showPACb:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Layout
    local _, newYLayout = ns.CreateSectionHeader(content, "Layout", 0, y)
    y = newYLayout

    local paSizeSlider = Components.Slider(content, {
        label = "Size",
        min = 16,
        max = 64,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.paSize
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.paSize = val
            ns.ApplySettings()
        end,
    })
    paSizeSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local paMaxSlider = Components.Slider(content, {
        label = "Per Row",
        labelWidth = 70,
        min = 1,
        max = 5,
        step = 1,
        get = function()
            return CoTankTrackerDB.paMaxIcons
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.paMaxIcons = val
            ns.ApplySettings()
        end,
    })
    paMaxSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local paMaxRowsSlider = Components.Slider(content, {
        label = "Max Rows",
        labelWidth = 70,
        min = 1,
        max = 4,
        step = 1,
        get = function()
            return CoTankTrackerDB.paMaxRows
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.paMaxRows = val
            ns.ApplySettings()
        end,
    })
    paMaxRowsSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local paSpacingSlider = Components.Slider(content, {
        label = "Spacing",
        min = 0,
        max = 16,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.paSpacing
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.paSpacing = val
            ns.ApplySettings()
        end,
    })
    paSpacingSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Display
    local _, newYDisplay = ns.CreateSectionHeader(content, "Display", 0, y)
    y = newYDisplay

    local paBorderCb = Components.Checkbox(content, {
        label = "Show dispel type border",
        get = function()
            return CoTankTrackerDB.paShowBorder
        end,
        enabled = enabled,
        tooltip = { title = "Border", desc = "Show the dispel type border around private aura icons." },
        onChange = function(checked)
            CoTankTrackerDB.paShowBorder = checked
            if checked then
                C_UnitAuras.TriggerPrivateAuraShowDispelType(true)
            end
            ns.ApplySettings()
        end,
    })
    paBorderCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local paCooldownCb = Components.Checkbox(content, {
        label = "Show cooldown swipe",
        get = function()
            return CoTankTrackerDB.paShowCooldown
        end,
        enabled = enabled,
        onChange = function(checked)
            CoTankTrackerDB.paShowCooldown = checked
            ns.ApplySettings()
            Components.RefreshAll()
        end,
    })
    paCooldownCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local paCooldownTextCb = Components.Checkbox(content, {
        label = "Show cooldown text",
        get = function()
            return CoTankTrackerDB.paShowCooldownText
        end,
        enabled = function()
            return CoTankTrackerDB.showPrivateAuras and CoTankTrackerDB.paShowCooldown
        end,
        onChange = function(checked)
            CoTankTrackerDB.paShowCooldownText = checked
            ns.ApplySettings()
        end,
    })
    paCooldownTextCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Positioning
    local _, newYPos = ns.CreateSectionHeader(content, "Positioning", 0, y)
    y = newYPos

    local paAttachElementDd = Components.Dropdown(content, {
        label = "Relative To",
        width = 120,
        options = {
            { value = "frame", label = "Frame" },
            { value = "debuffs", label = "Debuffs" },
        },
        get = function()
            return CoTankTrackerDB.paAttachElement
        end,
        enabled = enabled,
        tooltip = {
            title = "Relative To",
            desc = "Choose whether private auras anchor relative to the main frame or the debuffs element.",
        },
        onChange = function(val)
            CoTankTrackerDB.paAttachElement = val
            ns.ApplySettings()
        end,
    })
    paAttachElementDd:SetPoint("TOPLEFT", 0, y)
    y = y - 26 - COMPONENT_GAP

    local paAnchorDd = Components.Dropdown(content, {
        label = "Anchor",
        width = 120,
        options = ANCHOR_OPTIONS,
        get = function()
            return CoTankTrackerDB.paAnchor
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.paAnchor = val
            ns.ApplySettings()
        end,
    })
    paAnchorDd:SetPoint("TOPLEFT", 0, y)
    y = y - 26 - COMPONENT_GAP

    local paAttachDd = Components.Dropdown(content, {
        label = "Attach To",
        width = 120,
        options = ANCHOR_OPTIONS,
        get = function()
            return CoTankTrackerDB.paAttachTo
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.paAttachTo = val
            ns.ApplySettings()
        end,
    })
    paAttachDd:SetPoint("TOPLEFT", 0, y)
    y = y - 26 - COMPONENT_GAP

    local paOffXSlider = Components.Slider(content, {
        label = "Offset X",
        min = -100,
        max = 100,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.paOffsetX
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.paOffsetX = val
            ns.ApplySettings()
        end,
    })
    paOffXSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local paOffYSlider = Components.Slider(content, {
        label = "Offset Y",
        min = -100,
        max = 100,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.paOffsetY
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.paOffsetY = val
            ns.ApplySettings()
        end,
    })
    paOffYSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20

    content:SetHeight(math.abs(y) + 20)
    return scrollFrame
end

-----------------------------------------------------------
-- Tab: Defensives
-----------------------------------------------------------
local function BuildDefensivesTab(parent)
    local scrollFrame, content = CreateScrollContent(parent)
    local y = 0
    local enabled = function()
        return CoTankTrackerDB.showDefensives
    end

    local showDefCb = Components.Checkbox(content, {
        label = "Show defensives",
        get = function()
            return CoTankTrackerDB.showDefensives
        end,
        tooltip = {
            title = "Defensives",
            desc = "Show major defensive cooldowns (BIG_DEFENSIVE) and external defensives (EXTERNAL_DEFENSIVE) on your co-tank.",
        },
        onChange = function(checked)
            CoTankTrackerDB.showDefensives = checked
            ns.ApplySettings()
            Components.RefreshAll()
        end,
    })
    showDefCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Layout
    local _, newYLayout = ns.CreateSectionHeader(content, "Layout", 0, y)
    y = newYLayout

    local defSizeSlider = Components.Slider(content, {
        label = "Size",
        min = 16,
        max = 64,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.defSize
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.defSize = val
            ns.ApplySettings()
        end,
    })
    defSizeSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local defPerRowSlider = Components.Slider(content, {
        label = "Per Row",
        min = 1,
        max = 5,
        step = 1,
        get = function()
            return CoTankTrackerDB.defMaxIcons
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.defMaxIcons = val
            ns.ApplySettings()
        end,
    })
    defPerRowSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local defMaxRowsSlider = Components.Slider(content, {
        label = "Max Rows",
        labelWidth = 70,
        min = 1,
        max = 4,
        step = 1,
        get = function()
            return CoTankTrackerDB.defMaxRows
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.defMaxRows = val
            ns.ApplySettings()
        end,
    })
    defMaxRowsSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local defSpacingSlider = Components.Slider(content, {
        label = "Spacing",
        min = 0,
        max = 16,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.defSpacing
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.defSpacing = val
            ns.ApplySettings()
        end,
    })
    defSpacingSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Text
    local _, newYText = ns.CreateSectionHeader(content, "Text", 0, y)
    y = newYText

    local defCdSizeSlider = Components.Slider(content, {
        label = "Countdown",
        min = 6,
        max = 24,
        step = 1,
        suffix = "pt",
        get = function()
            return CoTankTrackerDB.defCountdownSize
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.defCountdownSize = val
            ns.ApplySettings()
        end,
    })
    defCdSizeSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local defStackSizeSlider = Components.Slider(content, {
        label = "Stacks",
        min = 6,
        max = 24,
        step = 1,
        suffix = "pt",
        get = function()
            return CoTankTrackerDB.defStackSize
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.defStackSize = val
            ns.ApplySettings()
        end,
    })
    defStackSizeSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Positioning
    local _, newYPos = ns.CreateSectionHeader(content, "Positioning", 0, y)
    y = newYPos

    local defAnchorDd = Components.Dropdown(content, {
        label = "Anchor",
        width = 120,
        options = ANCHOR_OPTIONS,
        get = function()
            return CoTankTrackerDB.defAnchor
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.defAnchor = val
            ns.ApplySettings()
        end,
    })
    defAnchorDd:SetPoint("TOPLEFT", 0, y)
    y = y - 26 - COMPONENT_GAP

    local defAttachDd = Components.Dropdown(content, {
        label = "Attach To",
        width = 120,
        options = ANCHOR_OPTIONS,
        get = function()
            return CoTankTrackerDB.defAttachTo
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.defAttachTo = val
            ns.ApplySettings()
        end,
    })
    defAttachDd:SetPoint("TOPLEFT", 0, y)
    y = y - 26 - COMPONENT_GAP

    local defOffXSlider = Components.Slider(content, {
        label = "Offset X",
        min = -100,
        max = 100,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.defOffsetX
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.defOffsetX = val
            ns.ApplySettings()
        end,
    })
    defOffXSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local defOffYSlider = Components.Slider(content, {
        label = "Offset Y",
        min = -100,
        max = 100,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.defOffsetY
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.defOffsetY = val
            ns.ApplySettings()
        end,
    })
    defOffYSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local defStackOffXSlider = Components.Slider(content, {
        label = "Stack X",
        min = -20,
        max = 20,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.defStackOffsetX
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.defStackOffsetX = val
            ns.ApplySettings()
        end,
    })
    defStackOffXSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local defStackOffYSlider = Components.Slider(content, {
        label = "Stack Y",
        min = -20,
        max = 20,
        step = 1,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.defStackOffsetY
        end,
        enabled = enabled,
        onChange = function(val)
            CoTankTrackerDB.defStackOffsetY = val
            ns.ApplySettings()
        end,
    })
    defStackOffYSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20

    content:SetHeight(math.abs(y) + 20)
    return scrollFrame
end

-----------------------------------------------------------
-- Build panel
-----------------------------------------------------------
local function CreateOptionsPanel()
    if panel then
        return panel
    end

    panel = ns.CreatePanel("CoTankTrackerOptions", PANEL_WIDTH, PANEL_HEIGHT, { escClose = true })
    panel:Hide()

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)
    title:SetText("|cffffcc00CoTank|r|cffffffffTracker|r")

    -- Close button
    local closeBtn = ns.CreateButton(panel, "x", function()
        panel:Hide()
    end)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)

    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetPoint("TOPLEFT", PADDING, -44)
    tabBar:SetPoint("TOPRIGHT", -PADDING, -44)
    tabBar:SetHeight(TAB_HEIGHT)

    CreateTab(tabBar, "general", "General", 0)
    CreateTab(tabBar, "debuffs", "Debuffs", 92)
    CreateTab(tabBar, "privateauras", "Priv. Auras", 184)
    CreateTab(tabBar, "defensives", "Defensives", 276)

    -- Separator under tabs
    local sep = panel:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", PADDING, -44 - TAB_HEIGHT)
    sep:SetPoint("TOPRIGHT", -PADDING, -44 - TAB_HEIGHT)
    sep:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- Content area
    local contentArea = CreateFrame("Frame", nil, panel)
    contentArea:SetPoint("TOPLEFT", PADDING, -44 - TAB_HEIGHT - 4)
    contentArea:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

    -- Build tab contents
    tabContents["general"] = BuildGeneralTab(contentArea)
    tabContents["debuffs"] = BuildDebuffsTab(contentArea)
    tabContents["privateauras"] = BuildPrivateAurasTab(contentArea)
    tabContents["defensives"] = BuildDefensivesTab(contentArea)

    -- Default tab
    SetActiveTab("general")

    -- Auto test mode + mock auras when panel opens
    local wasTestMode = false
    panel:SetScript("OnShow", function()
        Components.RefreshAll()
        wasTestMode = ns.IsTestMode()
        if not wasTestMode and not InCombatLockdown() then
            ns.EnterTestMode()
        end
        ns.ShowMockAuras()
    end)
    panel:SetScript("OnHide", function()
        ns.HideMockAuras()
        if not wasTestMode and not InCombatLockdown() then
            ns.ExitTestMode()
        end
    end)

    return panel
end

-----------------------------------------------------------
-- Toggle
-----------------------------------------------------------
function ns.ToggleOptions()
    local p = CreateOptionsPanel()
    if p:IsShown() then
        p:Hide()
    else
        p:Show()
    end
end
