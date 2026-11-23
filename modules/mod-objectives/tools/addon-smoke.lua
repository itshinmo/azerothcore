-- Offline smoke test for the Objectives addon. Loads the .toc against a small WoW API mock,
-- opens the window, feeds a synthetic board and chronicle answer, and clicks Reroll.
-- Usage: lua modules/mod-objectives/tools/addon-smoke.lua

local tocPath = "modules/mod-objectives/addon/Objectives/Objectives.toc"
local addonDir = tocPath:match("^(.*)/[^/]+$")

local frames = {}
local fontStrings = {}
local sent = {}
local chat = {}
local eventFrames = {}

local function newFrame(kind, name, parent)
    local frame = {
        kind = kind,
        name = name,
        parent = parent,
        shown = false,
        scripts = {},
        children = {},
        fontStrings = {},
        events = {},
        text = "",
    }
    function frame:SetWidth() end
    function frame:SetHeight() end
    function frame:SetPoint() end
    function frame:SetFrameStrata() end
    function frame:SetMovable() end
    function frame:EnableMouse() end
    function frame:RegisterForDrag() end
    function frame:StartMoving() end
    function frame:StopMovingOrSizing() end
    function frame:SetBackdrop() end
    function frame:SetScript(key, handler) self.scripts[key] = handler end
    function frame:GetScript(key) return self.scripts[key] end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:Show()
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetText(text) self.text = tostring(text) end
    function frame:GetText() return self.text end
    function frame:SetJustifyH() end
    function frame:Click()
        if self.scripts.OnClick then self.scripts.OnClick(self) end
    end
    function frame:CreateFontString(_, _, font)
        local fs = newFrame("FontString", nil, self)
        fs.font = font
        table.insert(self.fontStrings, fs)
        table.insert(fontStrings, fs)
        return fs
    end
    if parent then table.insert(parent.children, frame) end
    if name then _G[name] = frame end
    table.insert(frames, frame)
    if kind == "Frame" then table.insert(eventFrames, frame) end
    return frame
end

_G.UIParent = newFrame("Frame", "UIParent", nil)
_G.SlashCmdList = {}
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, message) table.insert(chat, tostring(message)) end,
}
_G.UnitName = function(unit) return unit == "player" and "Tester" or nil end
_G.SendAddonMessage = function(prefix, message) table.insert(sent, prefix .. ":" .. message) end
_G.RegisterAddonMessagePrefix = function() end
_G.CreateFrame = function(kind, name, parent, template)
    local allowed = {
        ["UIPanelButtonTemplate"] = true,
        ["UIPanelCloseButton"] = true,
    }
    if template and not allowed[template] then
        error("unexpected template: " .. tostring(template))
    end
    return newFrame(kind, name, parent)
end

for line in io.open(tocPath):lines() do
    local file = line:match("^([^#%s].*)$")
    if file then
        local path = addonDir .. "/" .. file
        local chunk, err = loadfile(path)
        if not chunk then
            error(err)
        end
        chunk()
    end
end

local function fail(message)
    io.stderr:write("FAIL: " .. message .. "\n")
    os.exit(1)
end

local function expect(condition, message)
    if not condition then fail(message) end
end

local frame = _G.ObjectivesFrame
expect(frame ~= nil, "ObjectivesFrame was not created")
expect(_G.SlashCmdList.OBJECTIVES ~= nil, "/objectives slash command is missing")

_G.SlashCmdList.OBJECTIVES()
expect(frame:IsShown(), "/objectives did not show the frame")
expect(#sent == 1 and sent[1]:match("^OBJ:B:%d+$"), "opening the window did not request the board")

local function feed(message)
    for _, candidate in ipairs(eventFrames) do
        if candidate.events.CHAT_MSG_ADDON and candidate.scripts.OnEvent then
            candidate.scripts.OnEvent(candidate, "CHAT_MSG_ADDON", "OBJ", message, "WHISPER", "Tester")
            return
        end
    end
    fail("no addon-message event frame")
end

feed("BR:1:40:Westfall:120:30:5:5000:5")
feed("BD:0,1,950300,1,10,3,0,20,2,0,40,Defias Pillagers")
feed("BD:1,1,950303,3,1,1,1,15,5,0,0,Edwin VanCleef")
feed("BE")

local rendered = false
for _, fs in ipairs(fontStrings) do
    if fs.text and fs.text:find("Defias Pillagers", 1, true) and fs.text:find("3/10", 1, true) then
        rendered = true
    end
end
expect(rendered, "board row did not render progress 3/10")

local reroll
for _, candidate in ipairs(frame.children) do
    if candidate.text == "Reroll" and candidate.shown then
        reroll = candidate
        break
    end
end
expect(reroll ~= nil, "reroll button for an incomplete daily row is missing")
local before = #sent
reroll:Click()
expect(#sent == before + 1, "reroll click sent no request")
expect(sent[#sent]:match("^OBJ:R:%d+:0$"), "reroll request was not R:<req>:0")

local chronicleTab
for _, candidate in ipairs(frame.children) do
    if candidate.text and candidate.text:find("Chronicle", 1, true) then
        chronicleTab = candidate
        break
    end
end
expect(chronicleTab ~= nil, "chronicle tab button is missing")
before = #sent
chronicleTab:Click()
expect(#sent == before + 1 and sent[#sent]:match("^OBJ:C:%d+$"), "chronicle tab did not request C")

feed("CR:2:120:30:5")
feed("CD:0,950309,2,10,4,0,50,10,0,0,Chronicle Quests")
feed("CD:1,0,0,0,0,0,0,0,0,0,Empty slot")
feed("CE")

local chronicleRendered = false
local emptyRendered = false
for _, fs in ipairs(fontStrings) do
    if fs.text and fs.text:find("Chronicle Quests", 1, true) and fs.text:find("4/10", 1, true) then
        chronicleRendered = true
    end
    if fs.text and fs.text:find("Empty slot", 1, true) then
        emptyRendered = true
    end
end
expect(chronicleRendered, "chronicle row did not render")
expect(emptyRendered, "empty chronicle slot did not render")
print("PASS: addon loaded, board rendered, reroll requested, chronicle rendered")
os.exit(0)
