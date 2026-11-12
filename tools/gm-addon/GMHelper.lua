local frame = CreateFrame("Frame", "GMHelperFrame", UIParent)
frame:SetWidth(420)
frame:SetHeight(580)
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
footer:SetWidth(380)
footer:SetJustifyH("LEFT")
footer:SetText("Commands are checked by the server. RBAC and audit still apply.")

local function Run(command)
    if InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage("GM Helper: unavailable in combat.")
        return false
    end

    if ChatEdit_SendText and ChatFrame1EditBox then
        ChatFrame1EditBox:SetText(command)
        ChatFrame1EditBox:SetAttribute("chatType", "SAY")
        ChatFrame1EditBox:SetAttribute("channelTarget", nil)
        ChatFrame1EditBox:SetAttribute("tellTarget", nil)
        ChatEdit_SendText(ChatFrame1EditBox)
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

local function Section(text, y)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -y)
    label:SetText(text)
    return y + 22
end

local function Button(text, command, column, y)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetWidth(184)
    button:SetHeight(24)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 18 + column * 192, -y)
    button:SetText(text)
    button:SetScript("OnClick", function()
        if type(command) == "function" then
            command()
        else
            Run(command)
        end
    end)
    return button
end

local function Input(label, prefix, y)
    local caption = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    caption:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -y)
    caption:SetText(label)

    local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    box:SetWidth(190)
    box:SetMaxLetters(200)
    box:SetHeight(20)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 130, -y + 6)
    box:SetAutoFocus(false)
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

local y = 48
y = Section("Server and GM", y)
Button(".server info", ".server info", 0, y)
Button(".instance listbinds", ".instance listbinds", 1, y)
y = y + 28
local gmEnabled = false
local gmButton
gmButton = Button("GM mode: off", function()
    local nextState = not gmEnabled
    if Run(nextState and ".gm on" or ".gm off") then
        gmEnabled = nextState
        gmButton:SetText(gmEnabled and "GM mode: on" or "GM mode: off")
    end
end, 0, y)
Button(".unstuck", ".unstuck", 1, y)
y = y + 40
Button("Visible to players", ".gm visible on", 0, y)
Button("Hidden from players", ".gm visible off", 1, y)

y = y + 42
y = Section("Target", y)
Button(".pinfo target", function() RunTarget(".pinfo ") end, 0, y)
Button(".npc info", RunNpcInfo, 1, y)

y = y + 42
y = Section("Lookup", y)
Input("Item", ".lookup item ", y)
y = y + 28
Input("Creature", ".lookup creature ", y)
y = y + 28
Input("Quest", ".lookup quest ", y)
y = y + 28
Input("Spell", ".lookup spell ", y)
y = y + 28
Input("Player account", ".lookup player account ", y)

y = y + 40
y = Section("Teleport", y)
Input("Location", ".teleport ", y)

SLASH_GMHELPER1 = "/gmhelper"
SLASH_GMHELPER2 = "/gmh"
SlashCmdList["GMHELPER"] = function()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
