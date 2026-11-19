local frame = CreateFrame("Frame", "GMHelperFrame", UIParent)
frame:SetWidth(560)
frame:SetHeight(660)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
frame:Hide()
tinsert(UISpecialFrames, "GMHelperFrame")

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -14)
title:SetText("GM Helper")

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
footer:SetTextColor(0.6, 0.6, 0.6)
footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 14)
footer:SetWidth(500)
footer:SetJustifyH("LEFT")
footer:SetText("Commands are checked by the server. RBAC and audit still apply.")

local function Run(command)
    if InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage("GM Helper: unavailable in combat.")
        return false
    end

    -- Keep the command in the chat history so every click leaves a visible record.
    DEFAULT_CHAT_FRAME:AddMessage("GM Helper: " .. command)

    if ChatEdit_SendText and ChatFrame1EditBox then
        ChatFrame1EditBox:SetText(command)
        ChatFrame1EditBox:SetAttribute("chatType", "SAY")
        ChatFrame1EditBox:SetAttribute("channelTarget", nil)
        ChatFrame1EditBox:SetAttribute("tellTarget", nil)
        ChatEdit_SendText(ChatFrame1EditBox)
        -- Some clients leave the command in the edit box after the send; clear
        -- it so the next click does not leave runnable text behind.
        ChatFrame1EditBox:SetText("")
        return true
    end

    ChatFrame_OpenChat(command)
    return false
end

local function RunNpcInfo()
    if not UnitName("target") then
        DEFAULT_CHAT_FRAME:AddMessage("GM Helper: select a target first.")
        return
    end
    if UnitIsPlayer("target") then
        DEFAULT_CHAT_FRAME:AddMessage("GM Helper: select an NPC, not a player.")
        return
    end
    Run(".npc info")
end

local function RunTarget(prefix)
    local name = UnitName("target")
    if not name then
        DEFAULT_CHAT_FRAME:AddMessage("GM Helper: select a target first.")
        return
    end
    Run(prefix .. name)
end

-- --------------------------------------------------------------- tab pages --

local PAGES = {}

local function Page(index)
    if not PAGES[index] then
        local page = CreateFrame("Frame", nil, frame)
        page:SetWidth(520)
        page:SetHeight(570)
        page:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -58)
        page:Hide()
        PAGES[index] = page
    end
    return PAGES[index]
end

local tabNames = { "Commands", "Instances", "Self" }
local ActivateTab -- forward declaration; tab OnClick closures capture this local
for index, name in ipairs(tabNames) do
    -- This client has no GameTabButtonTemplate; a plain button with a font swap
    -- marks the active tab instead.
    local tab = CreateFrame("Button", "GMHelperFrameTab" .. index, frame, "UIPanelButtonTemplate")
    tab:SetID(index)
    tab:SetWidth(96)
    tab:SetHeight(22)
    tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 10 + (index - 1) * 102, -34)
    tab:SetText(name)
    tab:SetNormalFontObject("GameFontNormal")
    tab:SetScript("OnClick", function(self)
        ActivateTab(self:GetID())
    end)
end
-- Manual tab state instead of PanelTemplates_SetTab: that API resolves tabs by
-- _G[<frame name>.."Tab"..i] and touches template-internal textures, which varies
-- between clients. Font swap is enough here.
function ActivateTab(index)
    for i = 1, #tabNames do
        local tab = _G["GMHelperFrameTab" .. i]
        if tab then
            tab:SetNormalFontObject(i == index and "GameFontHighlight" or "GameFontNormal")
        end
        if PAGES[i] then
            if i == index then PAGES[i]:Show() else PAGES[i]:Hide() end
        end
    end
    Page(index):Show()
end
ActivateTab(1)

local function Section(parent, text, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    label:SetText(text)
    return y + 22
end

local function Button(parent, text, command, column, y, width, name)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetHeight(26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", column * ((width and (width + 12) or 192)), -y)
    button:SetText(text)
    -- Auto-size to the label: fixed widths clip text on this client's template.
    local fs = button:GetFontString()
    local textWidth = fs and fs:GetStringWidth() or 0
    button:SetWidth(textWidth > 0 and (textWidth + 44) or (width or 184))
    button:SetScript("OnClick", function()
        if type(command) == "function" then
            command()
        else
            Run(command)
        end
    end)
    return button
end

local function Input(parent, label, prefix, y, width)
    local caption = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    caption:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    caption:SetText(label)

    -- Plain EditBox with an explicit backdrop; InputBoxTemplate's middle texture does not render
    -- reliably here, which left only the left and right end caps visible.
    local box = CreateFrame("EditBox", nil, parent)
    box:SetWidth(width or 190)
    box:SetHeight(22)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 112, -y + 5)
    box:SetAutoFocus(false)
    box:SetMaxLetters(200)
    box:SetFontObject(ChatFontNormal)
    box:SetTextColor(1, 1, 1)
    box:SetJustifyH("LEFT")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    box:SetBackdropColor(0, 0, 0, 0.8)
    box:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            Run(prefix .. text)
            self:SetText("")
        end
        self:ClearFocus()
    end)
    return box
end

-- ------------------------------------------------------- tab 1: commands ----

local function BuildCommands()
    local page = Page(1)
    local y = 4
    y = Section(page, "Server and GM", y)
    Button(page, ".server info", ".server info", 0, y)
    Button(page, ".instance listbinds", ".instance listbinds", 1, y)
    y = y + 34
    local gmEnabled = false
    local gmButton
    gmButton = Button(page, "GM mode: off", function()
        local nextState = not gmEnabled
        if Run(nextState and ".gm on" or ".gm off") then
            gmEnabled = nextState
            gmButton:SetText(gmEnabled and "GM mode: on" or "GM mode: off")
        end
    end, 0, y)
    Button(page, ".unstuck", ".unstuck", 1, y)
    y = y + 34
    Button(page, "Visible to players", ".gm visible on", 0, y)
    Button(page, "Hidden from players", ".gm visible off", 1, y)

    y = y + 52
    y = Section(page, "Target", y)
    Button(page, ".pinfo target", function() RunTarget(".pinfo ") end, 0, y)
    Button(page, ".npc info", RunNpcInfo, 1, y)

    y = y + 52
    y = Section(page, "Lookup", y)
    Input(page, "Item", ".lookup item ", y)
    y = y + 32
    Input(page, "Creature", ".lookup creature ", y)
    y = y + 32
    Input(page, "Quest", ".lookup quest ", y)
    y = y + 32
    Input(page, "Spell", ".lookup spell ", y)
    y = y + 32
    Input(page, "Player account", ".lookup player account ", y)

    y = y + 50
    y = Section(page, "Teleport", y)
    Input(page, "Location", ".teleport ", y)
end

-- ------------------------------------------------------- tab 2: instances ---

-- GMHelperInstancesData (generated) holds one row per instance:
--   name, map, expansion (0/1/2), kind ("dungeon"/"raid"), minLevel, maxLevel,
--   and x/y/z/o entrance coordinates from areatrigger_teleport.
local function BuildInstances()
    local page = Page(2)
    local EXPANSIONS = { [0] = "Classic", [1] = "The Burning Crusade", [2] = "Wrath of the Lich King" }

    local function columnRows(kind)
        local rows = {}
        for expansion = 0, 2 do
            local list = {}
            if GMHelperInstancesData then
                for _, entry in ipairs(GMHelperInstancesData) do
                    if entry.expansion == expansion and entry.kind == kind then
                        tinsert(list, entry)
                    end
                end
            end
            if #list > 0 then
                table.sort(list, function(a, b) return a.name < b.name end)
                tinsert(rows, { separator = EXPANSIONS[expansion] .. " (" .. #list .. ")" })
                for _, entry in ipairs(list) do
                    tinsert(rows, { entry = entry })
                end
            end
        end
        return rows
    end

    local COL_W = 250
    local ROW_H = 26
    local VISIBLE_ROWS = 20
    local SCROLL_W = COL_W - 16
    local function buildColumn(title, dataRows, x, prefix)
        local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", page, "TOPLEFT", x, -2)
        label:SetText(title)

        local scroll = CreateFrame("ScrollFrame", prefix .. "Scroll", page, "FauxScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", page, "TOPLEFT", x, -22)
        scroll:SetWidth(SCROLL_W)
        scroll:SetHeight(VISIBLE_ROWS * ROW_H)

        local sepPool = {}
        local itemPool = {}
        for i = 1, VISIBLE_ROWS do
            local sep = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            sep:SetWidth(COL_W)
            sep:SetJustifyH("LEFT")
            sep:SetTextColor(1, 0.82, 0.3)
            sepPool[i] = sep

            local item = CreateFrame("Button", prefix .. i, page, "UIPanelButtonTemplate")
            item:SetWidth(SCROLL_W - 8)
            item:SetHeight(ROW_H)
            item:SetNormalFontObject("GameFontHighlightSmall")
            item:SetScript("OnEnter", function(self)
                local entry = self.entry
                if not entry then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(entry.name)
                GameTooltip:AddLine(string.format("map %d, lvl %d-%d", entry.map, entry.minLevel, entry.maxLevel),
                    0.7, 0.7, 0.7)
                if entry.x then
                    GameTooltip:AddLine("Click to teleport to the entrance", 0.9, 0.9, 0.9)
                else
                    GameTooltip:AddLine("No entrance coordinates", 1, 0.4, 0.4)
                end
                GameTooltip:Show()
            end)
            item:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
            item:SetScript("OnClick", function(self)
                local entry = self.entry
                if not entry then return end
                if not entry.x then
                    DEFAULT_CHAT_FRAME:AddMessage("GM Helper: no entrance coordinates for " .. entry.name)
                    return
                end
                Run(string.format(".go xyz %.4f %.4f %.4f %d %.4f", entry.x, entry.y, entry.z, entry.map, entry.o))
            end)
            itemPool[i] = item
        end

        local function Render()
            local offset = FauxScrollFrame_GetOffset(scroll)
            for i = 1, VISIBLE_ROWS do
                local row = dataRows[offset + i]
                local sep = sepPool[i]
                local item = itemPool[i]
                -- Page-anchored rows start below the column title (title is at
                -- y -2, the list area begins at y -22).
                local y = -26 - (i - 1) * ROW_H
                if row then
                    if row.separator then
                        item:Hide()
                        sep:Show()
                        sep:SetText(row.separator)
                        sep:SetPoint("TOPLEFT", page, "TOPLEFT", x + 4, y)
                    else
                        sep:Hide()
                        item:Show()
                        item.entry = row.entry
                        item:SetText(row.entry.name)
                        item:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
                    end
                else
                    sep:Hide()
                    item:Hide()
                end
            end
            FauxScrollFrame_Update(scroll, #dataRows, VISIBLE_ROWS, ROW_H)
        end

        scroll:SetScript("OnVerticalScroll", function(self, value)
            FauxScrollFrame_OnVerticalScroll(self, value, ROW_H, Render)
        end)
        Render()
    end

    buildColumn("Dungeons", columnRows("dungeon"), 0, "GMHelperDungeonRow")
    buildColumn("Raids", columnRows("raid"), 262, "GMHelperRaidRow")
end

-- --------------------------------------------------------------- tab 3: self

-- Cheat commands are server-side toggles; the addon sends them and does not track
-- server state, so there is no on/off label to desync. Every command here acts on
-- the GM's own character only: named commands pass our own name, and the core
-- handlers for money, speed, and explore are pinned to the session player.
local function BuildSelf()
    local page = Page(3)
    local y = 4
    y = Section(page, "Cheat toggles (self-only, click to flip)", y)
    y = y + 6
    Button(page, "God mode (.cheat god)", ".cheat god", 0, y, 252, "GMHelperSelfGod")
    Button(page, "Infinite power (.cheat power)", ".cheat power", 1, y, 252, "GMHelperSelfPower")
    y = y + 34
    Button(page, "No cooldowns (.cheat cooldown)", ".cheat cooldown", 0, y, 252, "GMHelperSelfCooldown")
    Button(page, "Instant cast (.cheat casttime)", ".cheat casttime", 1, y, 252, "GMHelperSelfCasttime")
    y = y + 34
    Button(page, "Reveal map (.cheat explore 1)", ".cheat explore 1", 0, y, 252, "GMHelperSelfExploreOn")
    Button(page, "Hide map (.cheat explore 0)", ".cheat explore 0", 1, y, 252, "GMHelperSelfExploreOff")
    y = y + 34
    Button(page, "Leave combat (.combatstop)", ".combatstop", 0, y, 252, "GMHelperSelfCombatStop")

    y = y + 56
    y = Section(page, "Character", y)
    -- A bare number here would parse as a player GUID, so pass our own name.
    Button(page, "Level 80 (self)", function()
        Run(".character level " .. UnitName("player") .. " 80")
    end, 0, y, 252, "GMHelperSelfLevel")
    Button(page, "Revive (self)", function()
        Run(".revive " .. UnitName("player"))
    end, 1, y, 252, "GMHelperSelfRevive")
    y = y + 34
    Button(page, "Speed 2x (.modify speed 2)", ".modify speed 2", 0, y, 252, "GMHelperSelfSpeedUp")
    Button(page, "Speed reset (.modify speed 1)", ".modify speed 1", 1, y, 252, "GMHelperSelfSpeedReset")

    y = y + 56
    y = Section(page, "Give to self", y)
    Button(page, "1k gold (.modify money 1000g)", ".modify money 1000g", 0, y, 252, "GMHelperSelfGold")
    Button(page, "4 big bags (24-slot x4)", function()
        Run(".additem " .. UnitName("player") .. " 51809 4")
    end, 1, y, 252, "GMHelperSelfBags")

    y = y + 56
    y = Section(page, "Instance lockouts", y)
    Button(page, "Clear my lockouts (.instance unbind all)", function()
        Run(".instance unbind all " .. UnitName("player"))
    end, 0, y, 252, "GMHelperSelfUnbind")
    y = y + 34
    Button(page, "List my binds", ".instance listbinds", 0, y, 252, "GMHelperSelfListBinds")

    y = y + 50
    local note = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetTextColor(0.6, 0.6, 0.6)
    note:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
    note:SetWidth(500)
    note:SetJustifyH("LEFT")
    note:SetText("Every command acts on your own character, even with someone targeted.\n" ..
        "Toggles have no state label: the addon cannot read the server state. Click once to flip,\n" ..
        "again to flip back. Item grants stay manual beyond these two buttons.")
end

-- Build every tab behind pcall: a failure prints to chat and can never stop the
-- slash command from registering.
local function BuildTab(name, builder)
    local ok, err = pcall(builder)
    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage("GM Helper: " .. name .. " tab failed: " .. tostring(err))
    end
end
BuildTab("Commands", BuildCommands)
BuildTab("Instances", BuildInstances)
BuildTab("Self", BuildSelf)

SLASH_GMHELPER1 = "/gmhelper"
SLASH_GMHELPER2 = "/gmh"
SlashCmdList["GMHELPER"] = function()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

DEFAULT_CHAT_FRAME:AddMessage("GM Helper 0.3.2 loaded: /gmh")
