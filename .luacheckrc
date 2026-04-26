---@diagnostic disable: lowercase-global
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "libs/" }

ignore = {
    "21./_",
    "211/addonName", -- Standard WoW addon destructure
    "212/self",
    "212/element", -- oUF callback signatures
    "212/unit", -- oUF callback signatures
    "212/position", -- oUF callback signatures
}

globals = {
    "_",
    "CoTankTrackerDB",
    "SLASH_COTANKTRACKER1",
    "SLASH_COTANKTRACKER2",
    "SlashCmdList",
}

read_globals = {
    -- WoW API
    "C_Timer",
    "C_UnitAuras",
    "ChatFrame1",
    "CreateFrame",
    "GetCursorPosition",
    "LibStub",
    "GetTime",
    "GetNumGroupMembers",
    "InCombatLockdown",
    "IsInInstance",
    "IsInRaid",
    "IsMouseButtonDown",
    "UnitExists",
    "UnitGroupRolesAssigned",
    "UnitIsUnit",

    "tinsert",

    -- WoW UI globals
    "DEBUFF_TYPE_COLORS",
    "GameTooltip",
    "STANDARD_TEXT_FONT",
    "UIParent",
    "UISpecialFrames",

    -- oUF
    "oUF",

    -- WoW utilities
    "GrowthFromAttach",
    "PlayerUtil",
    "RegisterUnitWatch",
    "UnregisterUnitWatch",
}
