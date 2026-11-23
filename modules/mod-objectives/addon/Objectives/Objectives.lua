-- Objectives: standalone Adventure Board and Chronicle window.
-- Protocol: the server whispers addon messages under the OBJ prefix. This addon only requests
-- state and rerolls; all progress, prices and purchases are server-side.

local ADDON_PREFIX = "OBJ"
local FRAME_WIDTH = 460
local FRAME_HEIGHT = 400
local ROW_HEIGHT = 22
local MAX_ROWS = 10

Objectives = Objectives or {}
local O = Objectives

O.PREFIX = ADDON_PREFIX
O.board = { focusName = "Any zone", marks = 0, coins = 0, commendations = 0, rows = {} }
O.chronicle = { marks = 0, coins = 0, commendations = 0, rows = {} }
O.requestId = 0
O.currentTab = "board"

local frame
local rows = {}

local function send(message)
    SendAddonMessage(O.PREFIX, message, "WHISPER", UnitName("player"))
end

function O.Request(command, argument)
    O.requestId = O.requestId + 1
    local request = tostring(O.requestId)
    if argument and argument ~= "" then
        send(command .. ":" .. request .. ":" .. argument)
    else
        send(command .. ":" .. request)
    end
    return request
end

local function splitRows(text)
    local out = {}
    for row in (text .. ";"):gmatch("([^;]*);") do
        if row ~= "" then
            table.insert(out, row)
        end
    end
    return out
end

local function splitFields(text)
    local out = {}
    for field in (text .. ","):gmatch("([^,]*),") do
        table.insert(out, field)
    end
    return out
end

local function splitColon(text)
    local out = {}
    for field in (text .. ":"):gmatch("([^:]*):") do
        table.insert(out, field)
    end
    return out
end

local function number(value)
    return tonumber(value) or 0
end

local function hideRows()
    for i = 1, MAX_ROWS do
        rows[i].text:Hide()
        rows[i].reroll:Hide()
    end
    O.emptyText:Hide()
end

local function renderBoard()
    hideRows()
    local board = O.board
    O.focusButton:SetText("Focus: " .. (board.focusName or "Any zone"))
    O.balanceText:SetText(string.format("Marks %d   Coins %d   Commendations %d",
        number(board.marks), number(board.coins), number(board.commendations)))

    for i, row in ipairs(board.rows) do
        if i <= MAX_ROWS then
            local widget = rows[i]
            local suffix = row.completed == 1 and "  [done]" or ""
            if row.taskId == 0 then
                widget.text:SetText("Empty slot")
            else
                widget.text:SetText(string.format("%s  %d/%d%s", row.name, row.progress, row.required, suffix))
            end
            widget.text:Show()
            if row.scope == 1 and row.completed == 0 and row.taskId ~= 0 then
                local slot = row.slot
                widget.reroll:SetScript("OnClick", function()
                    O.Request("R", tostring(slot))
                end)
                widget.reroll:Show()
            end
        end
    end

    if #board.rows == 0 then
        O.emptyText:SetText("No objectives for this character yet.")
        O.emptyText:Show()
    end
end

local function renderChronicle()
    hideRows()
    local chronicle = O.chronicle
    O.balanceText:SetText(string.format("Marks %d   Coins %d   Commendations %d",
        number(chronicle.marks), number(chronicle.coins), number(chronicle.commendations)))

    for i, row in ipairs(chronicle.rows) do
        if i <= MAX_ROWS then
            local widget = rows[i]
            local suffix = row.completed == 1 and "  [done]" or ""
            if row.taskId == 0 then
                widget.text:SetText("Empty slot")
            else
                widget.text:SetText(string.format("%s  %d/%d%s", row.name, row.progress, row.required, suffix))
            end
            widget.text:Show()
        end
    end

    if #chronicle.rows == 0 then
        O.emptyText:SetText("The chronicle has no objectives yet.")
        O.emptyText:Show()
    end
end

function O.ShowTab(tab)
    O.currentTab = tab
    if tab == "chronicle" then
        O.boardTab:SetText("Board")
        O.chronicleTab:SetText("|cffffd100Chronicle|r")
        O.focusButton:Hide()
        renderChronicle()
        O.Request("C")
    else
        O.boardTab:SetText("|cffffd100Board|r")
        O.chronicleTab:SetText("Chronicle")
        O.focusButton:Show()
        renderBoard()
        O.Request("B")
    end
end

local function printResult(prefix, fields)
    local ok = fields[2] or "?"
    local rest = fields[3] or ""
    if ok == "ok" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Objectives:|r " .. prefix .. " " .. rest)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Objectives:|r " .. prefix .. " refused: " .. rest)
    end
end

function O.HandleMessage(message)
    local command, payload = message:match("^(%u+):(.*)$")
    if not command then
        command = message:match("^(%u+)$")
        payload = ""
    end
    if not command then
        return
    end

    if command == "BR" then
        local fields = splitColon(payload)
        O.board = {
            focusZone = number(fields[2]),
            focusName = fields[3] or "Any zone",
            marks = number(fields[4]),
            coins = number(fields[5]),
            commendations = number(fields[6]),
            rows = {},
        }
    elseif command == "BD" then
        local fields = splitFields(payload)
        table.insert(O.board.rows, {
            slot = number(fields[1]),
            scope = number(fields[2]),
            taskId = number(fields[3]),
            taskType = number(fields[4]),
            required = number(fields[5]),
            progress = number(fields[6]),
            completed = number(fields[7]),
            rewardMarks = number(fields[8]),
            rewardCoins = number(fields[9]),
            rewardCommendations = number(fields[10]),
            zoneId = number(fields[11]),
            name = fields[12] or "Objective",
        })
    elseif command == "BE" then
        if O.currentTab == "board" then
            renderBoard()
        end
    elseif command == "CR" then
        local fields = splitColon(payload)
        O.chronicle = {
            marks = number(fields[2]),
            coins = number(fields[3]),
            commendations = number(fields[4]),
            rows = {},
        }
    elseif command == "CD" then
        local fields = splitFields(payload)
        table.insert(O.chronicle.rows, {
            slot = number(fields[1]),
            taskId = number(fields[2]),
            taskType = number(fields[3]),
            required = number(fields[4]),
            progress = number(fields[5]),
            completed = number(fields[6]),
            rewardMarks = number(fields[7]),
            rewardCoins = number(fields[8]),
            rewardCommendations = number(fields[9]),
            zoneId = number(fields[10]),
            name = fields[11] or "Objective",
        })
    elseif command == "CE" then
        if O.currentTab == "chronicle" then
            renderChronicle()
        end
    elseif command == "RR" then
        printResult("Reroll", splitColon(payload))
    elseif command == "FR" then
        printResult("Focus", splitColon(payload))
    elseif command == "ERR" then
        local fields = splitColon(payload)
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Objectives:|r " .. (fields[2] or "unavailable"))
    end
end

local function createRow(index)
    local widget = {}
    widget.text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    widget.text:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -120 - (index - 1) * ROW_HEIGHT)
    widget.text:SetWidth(330)
    widget.text:SetJustifyH("LEFT")
    widget.text:Hide()

    widget.reroll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    widget.reroll:SetWidth(70)
    widget.reroll:SetHeight(18)
    widget.reroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -22, -118 - (index - 1) * ROW_HEIGHT)
    widget.reroll:SetText("Reroll")
    widget.reroll:Hide()

    return widget
end

local function createFrame()
    frame = CreateFrame("Frame", "ObjectivesFrame", UIParent)
    frame:SetWidth(FRAME_WIDTH)
    frame:SetHeight(FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -16)
    title:SetText("Objectives")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

    O.boardTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    O.boardTab:SetWidth(120)
    O.boardTab:SetHeight(22)
    O.boardTab:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -44)
    O.boardTab:SetScript("OnClick", function() O.ShowTab("board") end)

    O.chronicleTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    O.chronicleTab:SetWidth(120)
    O.chronicleTab:SetHeight(22)
    O.chronicleTab:SetPoint("TOPLEFT", frame, "TOPLEFT", 150, -44)
    O.chronicleTab:SetScript("OnClick", function() O.ShowTab("chronicle") end)

    O.focusButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    O.focusButton:SetWidth(210)
    O.focusButton:SetHeight(22)
    O.focusButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -70)
    O.focusButton:SetText("Focus: Any zone")
    O.focusButton:SetScript("OnClick", function() O.Request("F") end)

    O.balanceText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    O.balanceText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -100)
    O.balanceText:SetJustifyH("RIGHT")

    O.emptyText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    O.emptyText:SetPoint("TOP", frame, "TOP", 0, -200)
    O.emptyText:SetText("Loading...")
    O.emptyText:Show()

    for i = 1, MAX_ROWS do
        rows[i] = createRow(i)
    end

    frame:SetScript("OnShow", function()
        O.ShowTab(O.currentTab)
    end)
end

createFrame()
tinsert(UISpecialFrames, "ObjectivesFrame")

SLASH_OBJECTIVES1 = "/objectives"
SlashCmdList["OBJECTIVES"] = function()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:SetScript("OnEvent", function(_, event, prefix, message, _, sender)
    if event == "CHAT_MSG_ADDON" and prefix == O.PREFIX and sender == UnitName("player") then
        O.HandleMessage(message)
    end
end)

if RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(O.PREFIX)
end
