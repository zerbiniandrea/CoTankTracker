local _, ns = ...

-- ============================================================================
-- UI COMPONENT FACTORY (adapted from BuffReminders)
-- ============================================================================

local floor, max, min = math.floor, math.max, math.min
local rad = math.rad
local tinsert = table.insert

ns.Components = {}
ns.RefreshableComponents = {}

local Components = ns.Components
local RefreshableComponents = ns.RefreshableComponents

-- ============================================================================
-- TOOLTIP UTILITIES
-- ============================================================================

local function ShowTooltip(owner, title, desc, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if desc then
        GameTooltip:AddLine(desc, 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

ns.ShowTooltip = ShowTooltip
ns.HideTooltip = HideTooltip

-- ============================================================================
-- REFRESH ALL
-- ============================================================================

function Components.RefreshAll()
    for _, comp in ipairs(RefreshableComponents) do
        if comp.Refresh then
            comp:Refresh()
        end
    end
end

-- ============================================================================
-- COLORS
-- ============================================================================

local ButtonColors = {
    bg = { 0.15, 0.15, 0.15, 1 },
    bgHover = { 0.22, 0.22, 0.22, 1 },
    bgPressed = { 0.12, 0.12, 0.12, 1 },
    border = { 0.3, 0.3, 0.3, 1 },
    borderHover = { 0.5, 0.5, 0.5, 1 },
    borderPressed = { 1, 0.82, 0, 1 },
    borderDisabled = { 0.25, 0.25, 0.25, 1 },
    text = { 1, 1, 1, 1 },
    textDisabled = { 0.5, 0.5, 0.5, 1 },
}

local SliderColors = {
    track = { 0.2, 0.2, 0.2, 1 },
    trackFill = { 0.6, 0.5, 0.1, 1 },
    trackDisabled = { 0.15, 0.15, 0.15, 1 },
    thumb = { 0.4, 0.4, 0.4, 1 },
    thumbHover = { 1, 0.82, 0, 1 },
    thumbDisabled = { 0.25, 0.25, 0.25, 1 },
    text = { 1, 1, 1, 1 },
    textDisabled = { 0.5, 0.5, 0.5, 1 },
}

local CheckboxColors = {
    bg = { 0.12, 0.12, 0.12, 1 },
    bgHover = { 0.16, 0.16, 0.16, 1 },
    bgChecked = { 0.15, 0.13, 0.08, 1 },
    border = { 0.3, 0.3, 0.3, 1 },
    borderHover = { 0.45, 0.45, 0.45, 1 },
    borderChecked = { 0.6, 0.5, 0.2, 1 },
    borderDisabled = { 0.2, 0.2, 0.2, 1 },
    checkmark = { 0.9, 0.75, 0.2, 1 },
    checkmarkDisabled = { 0.5, 0.42, 0.1, 1 },
    text = { 1, 1, 1, 1 },
    textDisabled = { 0.5, 0.5, 0.5, 1 },
}

local DropdownColors = {
    bg = { 0.15, 0.15, 0.15, 1 },
    bgHover = { 0.2, 0.2, 0.2, 1 },
    bgDisabled = { 0.1, 0.1, 0.1, 1 },
    border = { 0.3, 0.3, 0.3, 1 },
    borderHover = { 0.5, 0.5, 0.5, 1 },
    borderDisabled = { 0.2, 0.2, 0.2, 1 },
    arrow = { 0.7, 0.7, 0.7, 1 },
    arrowHover = { 1, 0.82, 0, 1 },
    arrowDisabled = { 0.4, 0.4, 0.4, 1 },
    text = { 1, 1, 1, 1 },
    textDisabled = { 0.5, 0.5, 0.5, 1 },
    menuBg = { 0.12, 0.12, 0.12, 0.98 },
    menuBorder = { 0.3, 0.3, 0.3, 1 },
    itemBgHover = { 0.25, 0.22, 0.1, 1 },
    itemText = { 1, 1, 1, 1 },
    itemTextHover = { 1, 0.82, 0, 1 },
    checkmark = { 0.9, 0.75, 0.2, 1 },
}

local TextInputColors = {
    bg = { 0.08, 0.08, 0.08, 0.9 },
    bgFocused = { 0.1, 0.1, 0.1, 0.95 },
    border = { 0.3, 0.3, 0.3, 1 },
    borderFocused = { 1, 0.82, 0, 1 },
}

-- ============================================================================
-- STYLE EDIT BOX
-- ============================================================================

local function StyleEditBox(editBox)
    local colors = TextInputColors
    local parent = editBox:GetParent()

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    container:SetBackdropColor(unpack(colors.bg))
    container:SetBackdropBorderColor(unpack(colors.border))

    editBox:SetParent(container)
    editBox:ClearAllPoints()
    editBox:SetPoint("TOPLEFT", 4, -2)
    editBox:SetPoint("BOTTOMRIGHT", -4, 2)
    editBox:SetTextColor(1, 1, 1, 1)

    editBox:HookScript("OnEditFocusGained", function()
        container:SetBackdropColor(unpack(colors.bgFocused))
        container:SetBackdropBorderColor(unpack(colors.borderFocused))
    end)

    editBox:HookScript("OnEditFocusLost", function()
        container:SetBackdropColor(unpack(colors.bg))
        container:SetBackdropBorderColor(unpack(colors.border))
    end)

    editBox:HookScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    return container
end

-- ============================================================================
-- BUTTON
-- ============================================================================

function ns.CreateButton(parent, text, onClick, tooltip, colorOverrides)
    local colors = {}
    for k, v in pairs(ButtonColors) do
        colors[k] = (colorOverrides and colorOverrides[k]) or v
    end

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btnText:SetPoint("CENTER", 0, 0)
    btnText:SetText(text)
    btn.text = btnText

    local textWidth = btnText:GetStringWidth()
    btn:SetSize(max(textWidth + 16, 60), 22)

    local isEnabled = true
    local isPressed = false
    local isHovered = false

    local function UpdateVisual()
        if not isEnabled then
            btn:SetBackdropColor(unpack(colors.bg))
            btn:SetBackdropBorderColor(unpack(colors.borderDisabled))
            btnText:SetTextColor(unpack(colors.textDisabled))
        elseif isPressed then
            btn:SetBackdropColor(unpack(colors.bgPressed))
            btn:SetBackdropBorderColor(unpack(colors.borderPressed))
            btnText:SetTextColor(unpack(colors.text))
        elseif isHovered then
            btn:SetBackdropColor(unpack(colors.bgHover))
            btn:SetBackdropBorderColor(unpack(colors.borderHover))
            btnText:SetTextColor(unpack(colors.text))
        else
            btn:SetBackdropColor(unpack(colors.bg))
            btn:SetBackdropBorderColor(unpack(colors.border))
            btnText:SetTextColor(unpack(colors.text))
        end
    end

    UpdateVisual()

    btn:SetScript("OnEnter", function()
        isHovered = true
        UpdateVisual()
        if tooltip then
            ShowTooltip(btn, tooltip.title, tooltip.desc, "ANCHOR_TOP")
        end
    end)
    btn:SetScript("OnLeave", function()
        isHovered = false
        isPressed = false
        UpdateVisual()
        if tooltip then
            HideTooltip()
        end
    end)
    btn:SetScript("OnMouseDown", function()
        if isEnabled then
            isPressed = true
            UpdateVisual()
        end
    end)
    btn:SetScript("OnMouseUp", function()
        isPressed = false
        UpdateVisual()
    end)
    btn:SetScript("OnClick", function()
        if isEnabled and onClick then
            onClick(btn)
        end
    end)

    function btn:SetText(newText)
        btnText:SetText(newText)
        local w = btnText:GetStringWidth()
        self:SetSize(max(w + 16, 60), 22)
    end

    function btn:SetEnabled(enabled)
        isEnabled = enabled
        if enabled then
            self:Enable()
        else
            self:Disable()
        end
        UpdateVisual()
    end

    return btn
end

-- ============================================================================
-- SECTION HEADER
-- ============================================================================

function ns.CreateSectionHeader(parent, text, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", x, y)
    header:SetText("|cffffcc00" .. text .. "|r")
    return header, y - 18
end

-- ============================================================================
-- PANEL
-- ============================================================================

function ns.CreatePanel(name, width, height, options)
    options = options or {}
    local bgColor = options.bgColor or { 0.1, 0.1, 0.1, 0.95 }
    local borderColor = options.borderColor or { 0.3, 0.3, 0.3, 1 }

    local panel = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetPoint("CENTER")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(unpack(bgColor))
    panel:SetBackdropBorderColor(unpack(borderColor))
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata(options.strata or "DIALOG")
    if options.escClose and name then
        tinsert(UISpecialFrames, name)
    end
    return panel
end

-- ============================================================================
-- SLIDER
-- ============================================================================

---@class SliderConfig
---@field label? string
---@field min number
---@field max number
---@field step? number
---@field value? number
---@field get? fun(): number
---@field enabled? fun(): boolean
---@field suffix? string
---@field onChange fun(val: number)
---@field labelWidth? number
---@field sliderWidth? number

---@param parent any
---@param config SliderConfig
function Components.Slider(parent, config)
    local colors = SliderColors
    local labelWidth = config.labelWidth or (config.label and 70 or 0)
    local sliderWidth = config.sliderWidth or 100
    local step = config.step or 1
    local suffix = config.suffix or ""
    local TRACK_HEIGHT = 4
    local THUMB_WIDTH = 8
    local THUMB_HEIGHT = 14

    local function displayText(val)
        return floor(val) .. suffix
    end

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(labelWidth + sliderWidth + 60, 20)

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(labelWidth)
    label:SetJustifyH("LEFT")
    if config.label then
        label:SetText(config.label)
    end
    holder.label = label

    local sliderFrame = CreateFrame("Frame", nil, holder)
    sliderFrame:SetPoint("LEFT", label, "RIGHT", 5, 0)
    sliderFrame:SetSize(sliderWidth, 16)
    holder.slider = sliderFrame

    local trackBg = sliderFrame:CreateTexture(nil, "BACKGROUND")
    trackBg:SetHeight(TRACK_HEIGHT)
    trackBg:SetPoint("LEFT", 0, 0)
    trackBg:SetPoint("RIGHT", 0, 0)
    trackBg:SetColorTexture(unpack(colors.track))

    local trackFill = sliderFrame:CreateTexture(nil, "ARTWORK")
    trackFill:SetHeight(TRACK_HEIGHT)
    trackFill:SetPoint("LEFT", trackBg, "LEFT", 0, 0)
    trackFill:SetColorTexture(unpack(colors.trackFill))

    local thumb = CreateFrame("Button", nil, sliderFrame)
    thumb:SetSize(THUMB_WIDTH, THUMB_HEIGHT)
    thumb:SetPoint("CENTER", trackBg, "LEFT", 0, 0)

    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(unpack(colors.thumb))

    local currentValue = config.get and config.get() or config.value or config.min
    local isEnabled = true
    local isDragging = false
    local isThumbHovered = false

    local valueBtn = CreateFrame("Button", nil, holder)
    valueBtn:SetPoint("LEFT", sliderFrame, "RIGHT", 6, 0)
    valueBtn:SetSize(40, 16)

    local valueText = valueBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetAllPoints()
    valueText:SetJustifyH("LEFT")
    valueText:SetText(displayText(currentValue))
    holder.valueText = valueText

    local function ValueToPosition(val)
        local range = config.max - config.min
        if range == 0 then
            return 0
        end
        local pct = (val - config.min) / range
        return pct * (sliderWidth - THUMB_WIDTH)
    end

    local function PositionToValue(pos)
        local pct = pos / (sliderWidth - THUMB_WIDTH)
        pct = max(0, min(1, pct))
        local val = config.min + pct * (config.max - config.min)
        val = floor(val / step + 0.5) * step
        return max(config.min, min(config.max, val))
    end

    local function UpdateThumbPosition()
        local pos = ValueToPosition(currentValue)
        thumb:SetPoint("CENTER", trackBg, "LEFT", pos + THUMB_WIDTH / 2, 0)
        trackFill:SetWidth(max(1, pos + THUMB_WIDTH / 2))
    end

    local function UpdateVisual()
        if not isEnabled then
            thumbTex:SetColorTexture(unpack(colors.thumbDisabled))
            trackBg:SetColorTexture(unpack(colors.trackDisabled))
            trackFill:SetColorTexture(0.3, 0.25, 0.05, 1)
        elseif isThumbHovered or isDragging then
            thumbTex:SetColorTexture(unpack(colors.thumbHover))
            trackBg:SetColorTexture(unpack(colors.track))
            trackFill:SetColorTexture(unpack(colors.trackFill))
        else
            thumbTex:SetColorTexture(unpack(colors.thumb))
            trackBg:SetColorTexture(unpack(colors.track))
            trackFill:SetColorTexture(unpack(colors.trackFill))
        end
        UpdateThumbPosition()
    end

    thumb:SetScript("OnEnter", function()
        isThumbHovered = true
        UpdateVisual()
    end)
    thumb:SetScript("OnLeave", function()
        isThumbHovered = false
        UpdateVisual()
    end)
    thumb:SetScript("OnMouseDown", function()
        if isEnabled then
            isDragging = true
            UpdateVisual()
        end
    end)
    thumb:SetScript("OnMouseUp", function()
        isDragging = false
        UpdateVisual()
    end)

    sliderFrame:SetScript("OnUpdate", function()
        if isDragging and isEnabled then
            local mouseX = GetCursorPosition()
            local scale = sliderFrame:GetEffectiveScale()
            local frameLeft = sliderFrame:GetLeft() * scale
            local localX = (mouseX - frameLeft) / scale - THUMB_WIDTH / 2
            local newVal = PositionToValue(localX)
            if newVal ~= currentValue then
                currentValue = newVal
                valueText:SetText(displayText(currentValue))
                UpdateThumbPosition()
                config.onChange(floor(currentValue))
            end
        end
    end)

    sliderFrame:EnableMouse(true)
    sliderFrame:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and isEnabled then
            local mouseX = GetCursorPosition()
            local scale = sliderFrame:GetEffectiveScale()
            local frameLeft = sliderFrame:GetLeft() * scale
            local localX = (mouseX - frameLeft) / scale - THUMB_WIDTH / 2
            local newVal = PositionToValue(localX)
            currentValue = newVal
            valueText:SetText(displayText(currentValue))
            UpdateVisual()
            config.onChange(floor(currentValue))
            isDragging = true
        end
    end)
    sliderFrame:SetScript("OnMouseUp", function()
        isDragging = false
        UpdateVisual()
    end)

    -- Edit box for click-to-type
    local editBox = CreateFrame("EditBox", nil, holder)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetAutoFocus(false)
    local editContainer = StyleEditBox(editBox)
    editContainer:SetSize(35, 16)
    editContainer:SetPoint("LEFT", sliderFrame, "RIGHT", 6, 0)
    editContainer:Hide()

    editBox:SetScript("OnEnterPressed", function(self)
        local num = tonumber(self:GetText())
        if num then
            num = max(config.min, min(config.max, num))
            currentValue = num
            valueText:SetText(displayText(currentValue))
            UpdateVisual()
            config.onChange(floor(currentValue))
        end
        editContainer:Hide()
        valueBtn:Show()
    end)
    editBox:SetScript("OnEscapePressed", function()
        editContainer:Hide()
        valueBtn:Show()
    end)
    editBox:SetScript("OnEditFocusLost", function()
        editContainer:Hide()
        valueBtn:Show()
    end)

    valueBtn:SetScript("OnClick", function()
        valueBtn:Hide()
        editBox:SetText(tostring(floor(currentValue)))
        editContainer:Show()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    -- Mouse wheel
    holder:EnableMouseWheel(true)
    holder:SetScript("OnMouseWheel", function(_, delta)
        if isEnabled then
            local newVal = currentValue + (delta * step)
            newVal = max(config.min, min(config.max, newVal))
            currentValue = newVal
            valueText:SetText(displayText(currentValue))
            UpdateVisual()
            config.onChange(floor(currentValue))
        end
    end)

    UpdateVisual()

    function holder:SetValue(val)
        currentValue = val
        valueText:SetText(displayText(currentValue))
        UpdateVisual()
    end

    function holder:GetValue()
        return currentValue
    end

    function holder:SetEnabled(enabled)
        isEnabled = enabled
        local color = enabled and 1 or 0.5
        label:SetTextColor(color, color, color)
        valueText:SetTextColor(color, color, color)
        UpdateVisual()
    end

    function holder:Refresh()
        if config.get then
            currentValue = config.get()
            valueText:SetText(displayText(currentValue))
            UpdateVisual()
        end
        if config.enabled then
            holder:SetEnabled(config.enabled())
        end
    end

    if config.get or config.enabled then
        tinsert(RefreshableComponents, holder)
    end

    return holder
end

-- ============================================================================
-- CHECKBOX
-- ============================================================================

function Components.Checkbox(parent, config)
    local colors = CheckboxColors
    local CHECKBOX_SIZE = 16
    local initialChecked = config.get and config.get() or config.checked or false

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(200, 20)

    local cb = CreateFrame("Button", nil, holder, "BackdropTemplate")
    cb:SetSize(CHECKBOX_SIZE, CHECKBOX_SIZE)
    cb:SetPoint("LEFT", 0, 0)
    cb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    cb:SetBackdropColor(unpack(colors.bg))
    cb:SetBackdropBorderColor(unpack(colors.border))
    holder.checkbox = cb

    local checkmark = cb:CreateTexture(nil, "ARTWORK")
    checkmark:SetPoint("CENTER", 0, 0)
    checkmark:SetSize(CHECKBOX_SIZE + 4, CHECKBOX_SIZE + 4)
    checkmark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    checkmark:SetVertexColor(unpack(colors.checkmark))
    checkmark:Hide()

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    label:SetText(config.label)
    holder.label = label

    local isChecked = initialChecked
    local isEnabled = true
    local isHovered = false

    local function UpdateVisual()
        checkmark:SetShown(isChecked)
        if not isEnabled then
            cb:SetBackdropBorderColor(unpack(colors.borderDisabled))
            cb:SetBackdropColor(0.08, 0.08, 0.08, 1)
            checkmark:SetVertexColor(unpack(colors.checkmarkDisabled))
        elseif isChecked and isHovered then
            cb:SetBackdropBorderColor(unpack(colors.borderHover))
            cb:SetBackdropColor(unpack(colors.bgHover))
            checkmark:SetVertexColor(unpack(colors.checkmark))
        elseif isChecked then
            cb:SetBackdropBorderColor(unpack(colors.borderChecked))
            cb:SetBackdropColor(unpack(colors.bgChecked))
            checkmark:SetVertexColor(unpack(colors.checkmark))
        elseif isHovered then
            cb:SetBackdropBorderColor(unpack(colors.borderHover))
            cb:SetBackdropColor(unpack(colors.bgHover))
        else
            cb:SetBackdropBorderColor(unpack(colors.border))
            cb:SetBackdropColor(unpack(colors.bg))
        end
    end

    cb:SetScript("OnEnter", function()
        isHovered = true
        UpdateVisual()
    end)
    cb:SetScript("OnLeave", function()
        isHovered = false
        UpdateVisual()
    end)
    cb:SetScript("OnClick", function()
        if isEnabled then
            isChecked = not isChecked
            UpdateVisual()
            if config.onChange then
                config.onChange(isChecked)
            end
        end
    end)

    if config.tooltip then
        holder:EnableMouse(true)
        local function showTip()
            ShowTooltip(holder, config.tooltip.title, config.tooltip.desc, "ANCHOR_TOP")
        end
        holder:HookScript("OnEnter", showTip)
        holder:HookScript("OnLeave", HideTooltip)
        cb:HookScript("OnEnter", showTip)
        cb:HookScript("OnLeave", HideTooltip)
    end

    UpdateVisual()

    function holder:SetChecked(checked)
        isChecked = checked
        UpdateVisual()
    end

    function holder:GetChecked()
        return isChecked
    end

    function holder:SetEnabled(enabled)
        isEnabled = enabled
        if enabled then
            label:SetTextColor(unpack(colors.text))
        else
            label:SetTextColor(unpack(colors.textDisabled))
        end
        UpdateVisual()
    end

    function holder:Refresh()
        if config.get then
            isChecked = config.get()
            UpdateVisual()
        end
        if config.enabled then
            holder:SetEnabled(config.enabled())
        end
    end

    if config.get or config.enabled then
        tinsert(RefreshableComponents, holder)
    end

    return holder
end

-- ============================================================================
-- DROPDOWN (core)
-- ============================================================================

local function CreateDropdownCore(parent, width, options, initialValue, onChange)
    local colors = DropdownColors
    local BUTTON_HEIGHT = 22
    local ITEM_HEIGHT = 22
    local MENU_PADDING_V = 4
    local MAX_VISIBLE_ITEMS = 12

    local currentValue = initialValue
    local currentLabel = ""
    local placeholder = options.placeholder
    for _, opt in ipairs(options) do
        if opt.value == currentValue then
            currentLabel = opt.label
            break
        end
    end

    local isEnabled = true
    local isOpen = false
    local isHovered = false

    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, BUTTON_HEIGHT)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    local buttonText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    buttonText:SetPoint("LEFT", 8, 0)
    buttonText:SetPoint("RIGHT", -20, 0)
    buttonText:SetJustifyH("LEFT")
    if currentLabel ~= "" then
        buttonText:SetText(currentLabel)
    elseif placeholder then
        buttonText:SetText("|cff999999" .. placeholder .. "|r")
    end

    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetRotation(rad(-90))

    local needsScroll = #options > MAX_VISIBLE_ITEMS
    local visibleCount = needsScroll and MAX_VISIBLE_ITEMS or #options
    local totalContentHeight = #options * ITEM_HEIGHT + MENU_PADDING_V * 2
    local menuHeight = visibleCount * ITEM_HEIGHT + MENU_PADDING_V * 2

    local menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    menu:SetSize(width, menuHeight)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(unpack(colors.menuBg))
    menu:SetBackdropBorderColor(unpack(colors.menuBorder))
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:EnableMouse(true)
    menu:Hide()

    -- Scroll frame (only when needed)
    local itemParent = menu
    local scrollFrame
    if needsScroll then
        scrollFrame = CreateFrame("ScrollFrame", nil, menu)
        scrollFrame:SetPoint("TOPLEFT", 1, -1)
        scrollFrame:SetPoint("BOTTOMRIGHT", -1, 1)

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetSize(width - 2, totalContentHeight)
        scrollFrame:SetScrollChild(scrollChild)
        itemParent = scrollChild

        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local maxScroll = max(0, totalContentHeight - menuHeight + 2)
            local newScroll = max(0, min(maxScroll, current - delta * ITEM_HEIGHT * 3))
            self:SetVerticalScroll(newScroll)
        end)
    end

    local function UpdateButtonVisual()
        if not isEnabled then
            button:SetBackdropColor(unpack(colors.bgDisabled))
            button:SetBackdropBorderColor(unpack(colors.borderDisabled))
            buttonText:SetTextColor(unpack(colors.textDisabled))
            arrow:SetVertexColor(unpack(colors.arrowDisabled))
        elseif isHovered or isOpen then
            button:SetBackdropColor(unpack(colors.bgHover))
            button:SetBackdropBorderColor(unpack(colors.borderHover))
            buttonText:SetTextColor(unpack(colors.text))
            arrow:SetVertexColor(unpack(colors.arrowHover))
        else
            button:SetBackdropColor(unpack(colors.bg))
            button:SetBackdropBorderColor(unpack(colors.border))
            buttonText:SetTextColor(unpack(colors.text))
            arrow:SetVertexColor(unpack(colors.arrow))
        end
    end

    local wasMouseDown = false

    local function CloseMenu()
        isOpen = false
        menu:Hide()
        wasMouseDown = false
        UpdateButtonVisual()
    end

    local function ScrollToSelected()
        if not scrollFrame then
            return
        end
        for i, opt in ipairs(options) do
            if opt.value == currentValue then
                local itemTop = MENU_PADDING_V + (i - 1) * ITEM_HEIGHT
                local maxScroll = max(0, totalContentHeight - menuHeight + 2)
                local scroll = max(0, min(maxScroll, itemTop - ITEM_HEIGHT))
                scrollFrame:SetVerticalScroll(scroll)
                break
            end
        end
    end

    local function OpenMenu()
        isOpen = true
        menu:ClearAllPoints()
        -- Flip upward if not enough space below
        local scale = button:GetEffectiveScale()
        local buttonBottom = button:GetBottom() * scale
        local menuH = menuHeight * scale
        if buttonBottom - menuH < 0 then
            menu:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 0)
        else
            menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, 0)
        end
        menu:Show()
        ScrollToSelected()
        wasMouseDown = IsMouseButtonDown("LeftButton")
        UpdateButtonVisual()
    end

    menu:SetScript("OnUpdate", function()
        local isMouseDown = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        if isMouseDown and not wasMouseDown then
            if not menu:IsMouseOver() and not button:IsMouseOver() then
                CloseMenu()
            end
        end
        wasMouseDown = isMouseDown
    end)

    local items = {}
    for i, opt in ipairs(options) do
        local item = CreateFrame("Button", nil, itemParent)
        item:SetSize(width - 2, ITEM_HEIGHT)
        item:SetPoint("TOPLEFT", 0, -MENU_PADDING_V - (i - 1) * ITEM_HEIGHT)

        local itemBg = item:CreateTexture(nil, "BACKGROUND")
        itemBg:SetAllPoints()
        itemBg:SetColorTexture(0, 0, 0, 0)

        local check = item:CreateTexture(nil, "ARTWORK")
        check:SetSize(14, 14)
        check:SetPoint("LEFT", 6, 0)
        check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        check:SetVertexColor(unpack(colors.checkmark))
        check:SetShown(opt.value == currentValue)

        local itemLabel = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        itemLabel:SetPoint("LEFT", 24, 0)
        itemLabel:SetPoint("RIGHT", -8, 0)
        itemLabel:SetJustifyH("LEFT")
        itemLabel:SetText(opt.label)
        itemLabel:SetTextColor(unpack(colors.itemText))

        item:SetScript("OnEnter", function()
            itemBg:SetColorTexture(unpack(colors.itemBgHover))
            itemLabel:SetTextColor(unpack(colors.itemTextHover))
        end)
        item:SetScript("OnLeave", function()
            itemBg:SetColorTexture(0, 0, 0, 0)
            itemLabel:SetTextColor(unpack(colors.itemText))
        end)
        item:SetScript("OnClick", function()
            currentValue = opt.value
            currentLabel = opt.label
            buttonText:SetText(currentLabel)
            for _, it in ipairs(items) do
                it.check:SetShown(it.value == currentValue)
            end
            CloseMenu()
            onChange(currentValue, currentLabel)
        end)

        item.value = opt.value
        item.check = check
        items[i] = item
    end

    button:SetScript("OnEnter", function()
        isHovered = true
        UpdateButtonVisual()
    end)
    button:SetScript("OnLeave", function()
        isHovered = false
        UpdateButtonVisual()
    end)
    button:SetScript("OnClick", function()
        if isEnabled then
            if isOpen then
                CloseMenu()
            else
                OpenMenu()
            end
        end
    end)

    UpdateButtonVisual()

    local dropdown = { button = button, menu = menu }

    function dropdown:SetValue(value)
        currentValue = value
        for _, opt in ipairs(options) do
            if opt.value == value then
                currentLabel = opt.label
                break
            end
        end
        buttonText:SetText(currentLabel)
        for _, item in ipairs(items) do
            item.check:SetShown(item.value == currentValue)
        end
    end

    function dropdown:GetValue()
        return currentValue
    end

    function dropdown:SetEnabled(enabled)
        isEnabled = enabled
        button:EnableMouse(enabled)
        if not enabled and isOpen then
            CloseMenu()
        end
        UpdateButtonVisual()
    end

    return dropdown
end

-- ============================================================================
-- DROPDOWN (component wrapper)
-- ============================================================================

function Components.Dropdown(parent, config)
    local width = config.width or 100
    local labelWidth = config.labelWidth or 70

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(labelWidth + width + 10, 26)

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(labelWidth)
    label:SetJustifyH("LEFT")
    label:SetText(config.label)
    holder.label = label

    local initialValue = config.get and config.get() or config.selected

    local dropdown = CreateDropdownCore(holder, width, config.options, initialValue, function(value)
        config.onChange(value)
    end)
    dropdown.button:SetPoint("LEFT", label, "RIGHT", 5, 0)
    holder.dropdown = dropdown

    function holder:SetValue(value)
        dropdown:SetValue(value)
    end

    function holder:GetValue()
        return dropdown:GetValue()
    end

    function holder:SetEnabled(enabled)
        dropdown:SetEnabled(enabled)
        local color = enabled and 1 or 0.5
        label:SetTextColor(color, color, color)
    end

    function holder:Refresh()
        if config.get then
            dropdown:SetValue(config.get())
        end
        if config.enabled then
            holder:SetEnabled(config.enabled())
        end
    end

    if config.get or config.enabled then
        tinsert(RefreshableComponents, holder)
    end

    return holder
end
