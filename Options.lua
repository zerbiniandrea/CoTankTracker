local addonName, ns = ...
local Components = ns.Components
local LSM = ns.LSM

-----------------------------------------------------------
-- Constants
-----------------------------------------------------------
local PANEL_WIDTH = 640
local PANEL_HEIGHT = 600
local PADDING = 16
local COMPONENT_GAP = 6
local SECTION_GAP = 12
-- Vertical sidebar layout
local SIDEBAR_WIDTH = 132
local SIDEBAR_GAP = 10
local HEADER_OFFSET = 44 -- vertical space reserved for the title row
local BOTTOM_BAR_HEIGHT = 42 -- vertical space reserved for the lock/test row
-- Width available to page content (right of the sidebar, inside the padding)
local CONTENT_WIDTH = PANEL_WIDTH - (PADDING + SIDEBAR_WIDTH + SIDEBAR_GAP) - PADDING

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

local FRAME_GROWTH_OPTIONS = {
    { label = "Down", value = "DOWN" },
    { label = "Up", value = "UP" },
    { label = "Left", value = "LEFT" },
    { label = "Right", value = "RIGHT" },
}

local DEBUFF_FILTER_OPTIONS = {
    { label = "All", value = "all" },
    { label = "Raid", value = "raid", desc = "Debuffs that appear on raid frames (HARMFUL|RAID)." },
    {
        label = "Important",
        value = "important",
        desc = "Debuffs Blizzard curates as priority auras, the same set the raid frames show.",
    },
    {
        label = "Raid + Important",
        value = "raid_important",
        desc = "Raid debuffs that are also priority auras.",
    },
    {
        label = "Boss + Role",
        value = "boss_role",
        desc = "Boss debuffs and role mechanics, the tank-relevant auras Blizzard flags for a role.",
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
local pageButtons = {} -- id -> sidebar button
local pageContents = {} -- id -> scrollFrame
local activePage

local function ActivatePage(id)
    if activePage == id then
        return
    end
    activePage = id
    for pid, btn in pairs(pageButtons) do
        btn:SetActive(pid == id)
    end
    for pid, content in pairs(pageContents) do
        content:SetShown(pid == id)
    end
end

-- Sidebar group header (dim caps label with a thin underline)
local function CreateSidebarGroupHeader(parent, text)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(SIDEBAR_WIDTH, 20)

    local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", 8, 0)
    fs:SetText("|cffffcc00" .. text:upper() .. "|r")
    fs:SetJustifyH("LEFT")

    local sep = header:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", 4, 1)
    sep:SetPoint("BOTTOMRIGHT", -4, 1)
    sep:SetColorTexture(0.4, 0.32, 0.05, 0.6)

    return header
end

-- Sidebar nav button with a left accent bar on the active page
local function CreateSidebarButton(parent, label)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SIDEBAR_WIDTH, 24)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0)
    btn.bg = bg

    local accent = btn:CreateTexture(nil, "ARTWORK")
    accent:SetSize(2, 18)
    accent:SetPoint("LEFT", 0, 0)
    accent:SetColorTexture(1, 0.82, 0, 1)
    accent:Hide()
    btn.accent = accent

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", 14, 0)
    text:SetJustifyH("LEFT")
    text:SetText(label)
    btn.text = text

    btn:SetScript("OnEnter", function(self)
        if not self.isActive then
            self.bg:SetColorTexture(1, 1, 1, 0.06)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.isActive then
            self.bg:SetColorTexture(1, 1, 1, 0)
        end
    end)

    function btn:SetActive(active)
        self.isActive = active
        if active then
            self.bg:SetColorTexture(1, 0.82, 0, 0.12)
            self.accent:Show()
            self.text:SetTextColor(1, 1, 1)
        else
            self.bg:SetColorTexture(1, 1, 1, 0)
            self.accent:Hide()
            self.text:SetTextColor(0.85, 0.85, 0.85)
        end
    end

    btn:SetActive(false)
    return btn
end

local function CreateScrollContent(parent)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:SetAllPoints()

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(CONTENT_WIDTH)
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

    local fontDd = Components.Dropdown(content, {
        label = "Font",
        width = 160,
        options = GetLSMOptions("font"),
        get = function()
            return CoTankTrackerDB.font
        end,
        enabled = function()
            return CoTankTrackerDB.showName
        end,
        onChange = function(val)
            CoTankTrackerDB.font = val
            ns.ApplySettings()
        end,
    })
    fontDd:SetPoint("TOPLEFT", 0, y)
    y = y - 26 - COMPONENT_GAP

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

    -- Position
    local _, newYPos = ns.CreateSectionHeader(content, "Position", 0, y)
    y = newYPos

    local resetPosBtn = ns.CreateButton(content, "Reset Position", function()
        if ns.IsCombatLocked() then
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
    y = y - 22 - COMPONENT_GAP

    local xPosSlider = Components.Slider(content, {
        label = "X",
        labelWidth = 20,
        min = -2000,
        max = 2000,
        step = 1,
        get = function()
            return CoTankTrackerDB.x
        end,
        onChange = function(val)
            if ns.IsCombatLocked() then
                return
            end
            CoTankTrackerDB.x = val
            ns.coTankFrame:ClearAllPoints()
            local db = CoTankTrackerDB
            ns.coTankFrame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
        end,
    })
    xPosSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local yPosSlider = Components.Slider(content, {
        label = "Y",
        labelWidth = 20,
        min = -2000,
        max = 2000,
        step = 1,
        get = function()
            return CoTankTrackerDB.y
        end,
        onChange = function(val)
            if ns.IsCombatLocked() then
                return
            end
            CoTankTrackerDB.y = val
            ns.coTankFrame:ClearAllPoints()
            local db = CoTankTrackerDB
            ns.coTankFrame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
        end,
    })
    yPosSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

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
-- Tab: Multiple Tanks
-----------------------------------------------------------
local function BuildMultipleTanksTab(parent)
    local scrollFrame, content = CreateScrollContent(parent)
    local y = 0

    local help = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, y)
    help:SetWidth(CONTENT_WIDTH)
    help:SetJustifyH("LEFT")
    help:SetText(
        "Co-tanks are auto-detected. Choose which to show with |cffffcc00/ctt show 1,2|r "
            .. "(see |cffffcc00/ctt tanks|r). Extra frames stack from the main one."
    )
    y = y - 32 - COMPONENT_GAP

    -- Layout
    local _, newYLayout = ns.CreateSectionHeader(content, "Layout", 0, y)
    y = newYLayout

    local frameGrowthDd = Components.Dropdown(content, {
        label = "Stack Direction",
        labelWidth = 90,
        width = 120,
        options = FRAME_GROWTH_OPTIONS,
        get = function()
            return CoTankTrackerDB.frameGrowth
        end,
        tooltip = {
            title = "Stack Direction",
            desc = "Direction additional co-tank frames grow from the main (anchor) frame.",
        },
        onChange = function(val)
            CoTankTrackerDB.frameGrowth = val
            ns.ApplySettings()
        end,
    })
    frameGrowthDd:SetPoint("TOPLEFT", 0, y)
    y = y - 26 - COMPONENT_GAP

    local frameSpacingSlider = Components.Slider(content, {
        label = "Frame Spacing",
        labelWidth = 90,
        min = 0,
        max = 200,
        step = 5,
        suffix = "px",
        get = function()
            return CoTankTrackerDB.frameSpacing
        end,
        onChange = function(val)
            CoTankTrackerDB.frameSpacing = val
            ns.ApplySettings()
        end,
    })
    frameSpacingSlider:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - SECTION_GAP

    -- Detection
    local _, newYDetect = ns.CreateSectionHeader(content, "Detection", 0, y)
    y = newYDetect

    local requireTankCb = Components.Checkbox(content, {
        label = "Only show when I'm a tank",
        get = function()
            return CoTankTrackerDB.requireTankSpec
        end,
        tooltip = {
            title = "Only When Tank",
            desc = "When enabled, frames only appear if you are a tank. Disable to track co-tanks as a healer or DPS.",
        },
        onChange = function(checked)
            CoTankTrackerDB.requireTankSpec = checked
            ns.UpdateUnit()
        end,
    })
    requireTankCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20 - COMPONENT_GAP

    local tankNoticeCb = Components.Checkbox(content, {
        label = "Notify when more co-tanks detected",
        get = function()
            return CoTankTrackerDB.tankNotice
        end,
        tooltip = {
            title = "Detection Notice",
            desc = "Print a chat hint when more co-tanks are detected than are currently shown.",
        },
        onChange = function(checked)
            CoTankTrackerDB.tankNotice = checked
        end,
    })
    tankNoticeCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20

    content:SetHeight(math.abs(y) + 20)
    return scrollFrame
end

-----------------------------------------------------------
-- Tab: Frame
-----------------------------------------------------------
local function BuildFrameTab(parent)
    local scrollFrame, content = CreateScrollContent(parent)
    local y = 0

    -- Size
    local _, newYSize = ns.CreateSectionHeader(content, "Size", 0, y)
    y = newYSize

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

    -- Health Bar
    local _, newYBar = ns.CreateSectionHeader(content, "Health Bar", 0, y)
    y = newYBar

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
    y = y - 26 - SECTION_GAP

    -- Icons
    local _, newYIcons = ns.CreateSectionHeader(content, "Icons", 0, y)
    y = newYIcons

    local iconBordersCb = Components.Checkbox(content, {
        label = "Icon borders",
        get = function()
            return CoTankTrackerDB.iconBorders
        end,
        tooltip = {
            title = "Icon Borders",
            desc = "Show a thin black border around defensive and debuff icons.",
        },
        onChange = function(checked)
            CoTankTrackerDB.iconBorders = checked
            ns.ApplySettings()
        end,
    })
    iconBordersCb:SetPoint("TOPLEFT", 0, y)
    y = y - 20

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

    -- Icons
    local _, newYIcons = ns.CreateSectionHeader(content, "Icons", 0, y)
    y = newYIcons

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
    y = y - 20 - COMPONENT_GAP

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

    -- Icons
    local _, newYIcons = ns.CreateSectionHeader(content, "Icons", 0, y)
    y = newYIcons

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
    y = y - 20

    content:SetHeight(math.abs(y) + 20)
    return scrollFrame
end

-----------------------------------------------------------
-- Build panel
-----------------------------------------------------------
-- Sidebar nav layout: ordered groups of pages. Each page maps an id to a Build fn.
local PAGE_BUILDERS = {
    general = BuildGeneralTab,
    frame = BuildFrameTab,
    tanks = BuildMultipleTanksTab,
    defensives = BuildDefensivesTab,
    debuffs = BuildDebuffsTab,
}

local PAGE_GROUPS = {
    {
        title = "Layout",
        pages = {
            { id = "general", title = "General" },
            { id = "frame", title = "Frame" },
            { id = "tanks", title = "Multiple Tanks" },
        },
    },
    {
        title = "Auras",
        pages = {
            { id = "defensives", title = "Defensives" },
            { id = "debuffs", title = "Debuffs" },
        },
    },
}

StaticPopupDialogs["COTANKTRACKER_KOFI_URL"] = {
    text = "Thank you for supporting CoTankTracker!\nCopy the URL below (Ctrl+C):",
    button1 = "Close",
    hasEditBox = true,
    editBoxWidth = 250,
    OnShow = function(self)
        self.EditBox:SetText("https://ko-fi.com/zerbyy")
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

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

    -- Ko-fi support link (right of the title)
    local kofiLink = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    kofiLink:SetPoint("LEFT", title, "RIGHT", 10, 0)
    kofiLink:SetText("|cffff5e5bSupport on Ko-fi|r")

    local kofiHit = CreateFrame("Button", nil, panel)
    kofiHit:SetAllPoints(kofiLink)
    kofiHit:SetScript("OnClick", function()
        StaticPopup_Show("COTANKTRACKER_KOFI_URL")
    end)
    kofiHit:SetScript("OnEnter", function()
        kofiLink:SetText("|cffff8a88Support on Ko-fi|r")
        ns.ShowTooltip(
            kofiHit,
            "Support on Ko-fi",
            "Enjoying CoTankTracker?\nConsider supporting development on Ko-fi!",
            "ANCHOR_BOTTOM"
        )
    end)
    kofiHit:SetScript("OnLeave", function()
        kofiLink:SetText("|cffff5e5bSupport on Ko-fi|r")
        ns.HideTooltip()
    end)

    -- Close button
    local closeBtn = ns.CreateButton(panel, "x", function()
        panel:Hide()
    end)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)

    -- Scale stepper ( < 100% > ) left of the close button
    local BASE_SCALE = 1.0
    local MIN_PCT, MAX_PCT = 80, 150

    local function GetScalePct()
        return math.floor((CoTankTrackerDB.optionsPanelScale or BASE_SCALE) / BASE_SCALE * 100 + 0.5)
    end

    local scaleHolder = CreateFrame("Frame", nil, panel)
    scaleHolder:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    scaleHolder:SetSize(64, 16)

    local scaleDown = scaleHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleDown:SetPoint("LEFT", 0, 0)
    scaleDown:SetText("<")

    local scaleValue = scaleHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValue:SetPoint("LEFT", scaleDown, "RIGHT", 4, 0)

    local scaleUp = scaleHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleUp:SetPoint("LEFT", scaleValue, "RIGHT", 4, 0)
    scaleUp:SetText(">")

    local function UpdateScaleText()
        local pct = GetScalePct()
        scaleValue:SetText(pct .. "%")
        local d = pct > MIN_PCT and 1 or 0.4
        local u = pct < MAX_PCT and 1 or 0.4
        scaleDown:SetTextColor(d, d, d)
        scaleUp:SetTextColor(u, u, u)
    end

    local function UpdateScale(delta)
        local newPct = math.max(MIN_PCT, math.min(MAX_PCT, GetScalePct() + delta))
        local newScale = newPct / 100 * BASE_SCALE
        CoTankTrackerDB.optionsPanelScale = newScale
        panel:SetScale(newScale)
        UpdateScaleText()
    end

    local downBtn = CreateFrame("Button", nil, scaleHolder)
    downBtn:SetAllPoints(scaleDown)
    downBtn:SetScript("OnClick", function()
        UpdateScale(-10)
    end)
    downBtn:SetScript("OnEnter", function()
        if GetScalePct() > MIN_PCT then
            scaleDown:SetTextColor(1, 0.82, 0)
        end
    end)
    downBtn:SetScript("OnLeave", UpdateScaleText)

    local upBtn = CreateFrame("Button", nil, scaleHolder)
    upBtn:SetAllPoints(scaleUp)
    upBtn:SetScript("OnClick", function()
        UpdateScale(10)
    end)
    upBtn:SetScript("OnEnter", function()
        if GetScalePct() < MAX_PCT then
            scaleUp:SetTextColor(1, 0.82, 0)
        end
    end)
    upBtn:SetScript("OnLeave", UpdateScaleText)

    if CoTankTrackerDB.optionsPanelScale then
        panel:SetScale(CoTankTrackerDB.optionsPanelScale)
    end
    UpdateScaleText()

    -- Divider primitives: the sidebar, content area, and bottom bar all anchor to
    -- these, so the layout follows the dividers with no per-element offset juggling.
    local headerSep = panel:CreateTexture(nil, "ARTWORK")
    headerSep:SetHeight(1)
    headerSep:SetPoint("TOPLEFT", PADDING, -HEADER_OFFSET)
    headerSep:SetPoint("TOPRIGHT", -PADDING, -HEADER_OFFSET)
    headerSep:SetColorTexture(0.27, 0.27, 0.32, 1)

    local bottomSep = panel:CreateTexture(nil, "ARTWORK")
    bottomSep:SetHeight(1)
    bottomSep:SetPoint("BOTTOMLEFT", PADDING, BOTTOM_BAR_HEIGHT)
    bottomSep:SetPoint("BOTTOMRIGHT", -PADDING, BOTTOM_BAR_HEIGHT)
    bottomSep:SetColorTexture(0.27, 0.27, 0.32, 1)

    -- Sidebar (left column between the dividers)
    local sidebar = CreateFrame("Frame", nil, panel)
    sidebar:SetPoint("TOPLEFT", headerSep, "BOTTOMLEFT", 0, -6)
    sidebar:SetPoint("BOTTOMLEFT", bottomSep, "TOPLEFT", 0, 6)
    sidebar:SetWidth(SIDEBAR_WIDTH)

    local sidebarBorder = sidebar:CreateTexture(nil, "BORDER")
    sidebarBorder:SetWidth(1)
    sidebarBorder:SetPoint("TOPRIGHT", SIDEBAR_GAP / 2, 0)
    sidebarBorder:SetPoint("BOTTOMRIGHT", SIDEBAR_GAP / 2, 0)
    sidebarBorder:SetColorTexture(0.27, 0.27, 0.32, 1)

    -- Content area (right of the sidebar, between the dividers)
    local contentArea = CreateFrame("Frame", nil, panel)
    contentArea:SetPoint("TOPLEFT", headerSep, "BOTTOMLEFT", SIDEBAR_WIDTH + SIDEBAR_GAP, -6)
    contentArea:SetPoint("BOTTOMRIGHT", bottomSep, "TOPRIGHT", 0, 6)

    -- Build pages + sidebar nav from the group registry
    local sidebarY = 0
    local firstId
    for _, group in ipairs(PAGE_GROUPS) do
        local header = CreateSidebarGroupHeader(sidebar, group.title)
        header:SetPoint("TOPLEFT", 0, sidebarY)
        sidebarY = sidebarY - 22
        for _, page in ipairs(group.pages) do
            local id = page.id
            pageContents[id] = PAGE_BUILDERS[id](contentArea)
            pageContents[id]:Hide()

            local btn = CreateSidebarButton(sidebar, page.title)
            btn:SetPoint("TOPLEFT", 0, sidebarY)
            btn:SetScript("OnClick", function()
                ActivatePage(id)
            end)
            pageButtons[id] = btn
            sidebarY = sidebarY - 24
            firstId = firstId or id
        end
        sidebarY = sidebarY - 8 -- group gap
    end

    -- Bottom bar: Lock / Unlock
    local lockBtn = ns.CreateButton(panel, "Unlock", function()
        CoTankTrackerDB.locked = not CoTankTrackerDB.locked
        Components.RefreshAll()
    end, { title = "Lock / Unlock", desc = "When unlocked, drag the frame to reposition the stack." }, {
        border = { 0.7, 0.58, 0, 1 },
        borderHover = { 1, 0.82, 0, 1 },
        text = { 1, 0.82, 0, 1 },
    })
    lockBtn:SetSize(90, 22)
    lockBtn:SetPoint("BOTTOMLEFT", PADDING, (BOTTOM_BAR_HEIGHT - 22) / 2)

    function lockBtn:Refresh()
        self:SetText(CoTankTrackerDB.locked and "Unlock" or "Lock")
    end
    lockBtn:Refresh()
    table.insert(ns.RefreshableComponents, lockBtn)

    local lockHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lockHint:SetPoint("LEFT", lockBtn, "RIGHT", 10, 0)
    lockHint:SetText("Unlock to drag the frame; the stack moves with it.")

    -- Default page
    ActivatePage(firstId)

    -- Auto test mode + mock auras when panel opens
    local wasTestMode = false
    panel:SetScript("OnShow", function()
        Components.RefreshAll()
        wasTestMode = ns.IsTestMode()
        if not wasTestMode and not ns.IsCombatLocked() then
            ns.EnterTestMode()
        end
        ns.ShowMockAuras()
    end)
    panel:SetScript("OnHide", function()
        ns.HideMockAuras()
        if not wasTestMode and not ns.IsCombatLocked() then
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
