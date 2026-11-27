-- Offline test for the Icon Browser addon.
-- Run: luajit tools/icon-browser/tests/test_addon.lua
--
-- Mocks only the 3.3.5 widget surface the addon uses. It proves the addon loads
-- the generated icon list, /icons opens the frame, search/paging/source filter
-- work, and a click copies the exact texture path. It is not a substitute for
-- the in-client test.

local root = arg[1] or "tools/icon-browser"

-- ------------------------------------------------------------------- mocks --

local WIDGET = {}
WIDGET.__index = WIDGET

local function Widget(kind)
    local widget = setmetatable({ kind = kind, shown = true, texts = {}, scripts = {} }, WIDGET)
    return widget
end

function WIDGET:SetWidth(value) self.width = value end
function WIDGET:SetHeight(value) self.height = value end
function WIDGET:GetWidth() return self.width or 0 end
function WIDGET:GetHeight() return self.height or 0 end
function WIDGET:SetPoint(...) self.point = { ... } end
function WIDGET:ClearAllPoints() self.point = nil end
function WIDGET:SetFrameStrata(value) self.strata = value end
function WIDGET:SetClampedToScreen() end
function WIDGET:SetMovable() end
function WIDGET:EnableMouse() end
function WIDGET:RegisterForDrag() end
function WIDGET:RegisterForClicks() end
function WIDGET:StartMoving() end
function WIDGET:StopMovingOrSizing() end
function WIDGET:SetBackdrop() end
function WIDGET:SetBackdropColor() end
function WIDGET:SetBackdropBorderColor() end
function WIDGET:SetScript(name, handler) self.scripts[name] = handler end
function WIDGET:Show() self.shown = true end
function WIDGET:Hide() self.shown = false end
function WIDGET:IsShown() return self.shown end
function WIDGET:SetID(value) self.id = value end
function WIDGET:GetID() return self.id end
function WIDGET:SetNormalFontObject() end
function WIDGET:SetFontObject() end
function WIDGET:SetTextColor() end
function WIDGET:SetJustifyH(value) self.justify = value end
function WIDGET:SetTextInsets() end
function WIDGET:SetMaxLetters(value) self.maxLetters = value end
function WIDGET:SetAutoFocus() end
function WIDGET:SetFocus() self.focused = true end
function WIDGET:ClearFocus() self.focused = false end
function WIDGET:HighlightText() self.highlighted = true end
function WIDGET:SetText(value)
    self.text = value
    self.texts[#self.texts + 1] = value
    if self.scripts.OnTextChanged then
        self.scripts.OnTextChanged(self)
    end
end
function WIDGET:GetText() return self.text end
function WIDGET:CreateFontString()
    local font = Widget("FontString")
    return font
end
function WIDGET:CreateTexture()
    local texture = Widget("Texture")
    function texture:SetTexture(value) self.texture = value end
    function texture:SetTexCoord() end
    function texture:SetBlendMode(value) self.blend = value end
    return texture
end

local frames = {}
function CreateFrame(kind, name, parent, template)
    local frame = Widget(kind)
    frame.name, frame.parent, frame.template = name, parent, template
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end

UISpecialFrames = {}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = {
    messages = {},
    AddMessage = function(self, text) self.messages[#self.messages + 1] = text end,
}
tinsert = table.insert

GameTooltip = Widget("GameTooltip")
GameTooltip.lines = {}
function GameTooltip:SetOwner() end
function GameTooltip:SetText(text) self.lines = { text } end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false end

-- ------------------------------------------------------------- load addon ---

dofile(root .. "/IconBrowserIcons.lua")
local icons = IconBrowserIcons
assert(type(icons) == "table", "IconBrowserIcons.lua must define the data table")
local dataCount = #icons
assert(dataCount > 30000, "expected the full icon list, got " .. dataCount)

local stock, reforged = 0, 0
for _, entry in ipairs(icons) do
    if entry:sub(-1) == "#" then
        reforged = reforged + 1
    else
        stock = stock + 1
    end
end
assert(stock + reforged == dataCount, "every entry is either stock or Reforged")

local ns = {}
assert(loadfile(root .. "/IconBrowser.lua"))("IconBrowser", ns)

-- Loading is deferred to the first /icons so login pays nothing.
assert(#ns.Icons == 0, "icon data must not be ingested at load")
assert(IconBrowserIcons == icons, "raw data stays available until first use")
assert(ns.LoadIcons() == dataCount, "addon must load every generated icon")
assert(#ns.Icons == stock + reforged)
assert(IconBrowserIcons == nil, "raw data table is released after ingestion")
assert(ns.LoadIcons() == dataCount and #ns.Icons == dataCount, "loading twice must not duplicate")

local first = ns.Icons[1]
assert(first.name and first.name:sub(-1) ~= "#", "addon strips the Reforged marker")
assert(first.tag == "stock" or first.tag == "reforged", "tag must be stock or reforged")
for _, icon in ipairs(ns.Icons) do
    assert(icon.name:sub(-1) ~= "#", "marker survived on " .. icon.name)
    assert(icon.lower == icon.name:lower(), "lower-cased key mismatch on " .. icon.name)
end

local frame = ns.frame
assert(frame and frame.kind == "Frame", "addon frame missing")
assert(frame.shown == false, "frame starts hidden")
assert(UISpecialFrames[1] == "IconBrowserFrame", "Escape must close the frame")

local pageSize = 48
assert(#ns.Buttons == pageSize, "expected a 8x6 grid, got " .. #ns.Buttons)

-- --------------------------------------------------------------- /icons -----

SlashCmdList["ICONBROWSER"]()
assert(frame:IsShown(), "/icons must open the frame")
assert(ns.State.matches and #ns.State.matches == dataCount, "opening shows every icon")
assert(string.find(ns.pageLabel.text, "^Page 1 / "), "page indicator, got " .. tostring(ns.pageLabel.text))
assert(ns.countLabel.text == dataCount .. " matches", "match count, got " .. tostring(ns.countLabel.text))

SlashCmdList["ICONBROWSER"]()
assert(not frame:IsShown(), "second /icons click closes the frame")
SlashCmdList["ICONBROWSER"]()
assert(frame:IsShown(), "/icons reopens")

-- --------------------------------------------------------------- search -----

ns.searchBox:SetText("anchor")
assert(ns.State.matches[1] ~= nil, "search must find INV_Misc_Anchor")
local foundAnchor = false
for _, entry in ipairs(ns.State.matches) do
    assert(entry.lower:find("anchor", 1, true), "search result missing the needle: " .. entry.name)
    if entry.name == "INV_Misc_Anchor" then foundAnchor = true end
end
assert(foundAnchor, "INV_Misc_Anchor must be in the results")
assert(#ns.State.matches < dataCount, "search must narrow the list")
assert(ns.State.page == 1, "a new search resets to page 1")

ns.searchBox:SetText("ANCHOR")
local upperCount = #ns.State.matches
ns.searchBox:SetText("anchor")
assert(#ns.State.matches == upperCount, "search is case-insensitive")

ns.searchBox:SetText("")
assert(#ns.State.matches == dataCount, "empty search restores every icon")

-- Search is substring, not prefix.
ns.searchBox:SetText("misc_anchor")
local substring = ns.Filter("misc_anchor", "all")
assert(#substring > 0, "substring search must work")
for _, entry in ipairs(substring) do
    assert(entry.lower:find("misc_anchor", 1, true), "substring result mismatch")
end

-- --------------------------------------------------------------- paging -----

ns.searchBox:SetText("")
assert(ns.State.page == 1)
assert(ns.Buttons[1].entry.name == ns.Icons[1].name, "page 1 starts at the first icon")
assert(ns.Buttons[pageSize].entry.name == ns.Icons[pageSize].name, "page 1 fills the grid")

local firstPageName = ns.Buttons[1].entry.name
ns.nextButton.scripts.OnClick(ns.nextButton)
assert(ns.State.page == 2, "Next moves to page 2")
assert(ns.Buttons[1].entry.name == ns.Icons[pageSize + 1].name, "page 2 starts at icon 49")
assert(ns.Buttons[1].entry.name ~= firstPageName, "page 2 must show different icons")
assert(string.find(ns.pageLabel.text, "^Page 2 / "), "page indicator updates")

ns.prevButton.scripts.OnClick(ns.prevButton)
assert(ns.State.page == 1, "Prev returns to page 1")

ns.SetPage(-5)
assert(ns.State.page == 1, "page clamps at 1")
ns.SetPage(999999)
local maxPage = math.ceil(dataCount / pageSize)
assert(ns.State.page == maxPage, "page clamps at the last page")
local lastStart = (maxPage - 1) * pageSize
assert(ns.Buttons[1].entry.name == ns.Icons[lastStart + 1].name, "last page starts correctly")
for index = dataCount - lastStart + 1, pageSize do
    assert(not ns.Buttons[index]:IsShown(), "unused slots on the last page stay hidden")
end
ns.SetPage(1)

-- --------------------------------------------------------- source filter ----

ns.SetSource("stock")
assert(ns.State.source == "stock")
assert(#ns.State.matches == stock, "stock filter count, got " .. #ns.State.matches)
for _, entry in ipairs(ns.State.matches) do
    assert(entry.tag == "stock", "stock filter leaked a Reforged icon: " .. entry.name)
end
assert(ns.sourceButton.text == "Stock only", "source button label")
assert(ns.countLabel.text == stock .. " matches", "stock count label")

ns.SetSource("reforged")
assert(#ns.State.matches == reforged, "reforged filter count, got " .. #ns.State.matches)
for _, entry in ipairs(ns.State.matches) do
    assert(entry.tag == "reforged", "reforged filter leaked a stock icon: " .. entry.name)
end

ns.SetSource("all")
assert(#ns.State.matches == dataCount, "all filter restores every icon")

-- Escape inside a focused box closes the frame, same as anywhere else.
ns.searchBox.scripts.OnEscapePressed(ns.searchBox)
assert(not frame:IsShown(), "Escape must close the frame")
SlashCmdList["ICONBROWSER"]()
assert(frame:IsShown(), "/icons reopens after Escape")

-- Filter cycles all -> stock -> reforged -> all on click.
ns.sourceButton.scripts.OnClick(ns.sourceButton)
assert(ns.State.source == "stock", "first click selects stock")
ns.sourceButton.scripts.OnClick(ns.sourceButton)
assert(ns.State.source == "reforged", "second click selects reforged")
ns.sourceButton.scripts.OnClick(ns.sourceButton)
assert(ns.State.source == "all", "third click returns to all")

-- Search and source filter combine.
ns.SetSource("stock")
ns.SetSearch("anchor")
for _, entry in ipairs(ns.State.matches) do
    assert(entry.tag == "stock" and entry.lower:find("anchor", 1, true), "combined filter mismatch")
end
ns.SetSource("all")
ns.SetSearch("")

-- ------------------------------------------------------------ copy path -----

local target = ns.Buttons[1]
target.scripts.OnClick(target)
assert(ns.copyBox.text == "Interface\\Icons\\" .. target.entry.name,
    "copied path mismatch: " .. tostring(ns.copyBox.text))
assert(ns.copyBox.highlighted and ns.copyBox.focused, "path must be selected for Ctrl+C")
assert(ns.copyBox:GetText() == "Interface\\Icons\\" .. target.entry.name, "path stays in the box")

-- Both source tags are present in the shipped data, and the path builder is exact.
local stockIcon, reforgedIcon
for _, entry in ipairs(ns.Icons) do
    if entry.tag == "stock" and not stockIcon then stockIcon = entry end
    if entry.tag == "reforged" and not reforgedIcon then reforgedIcon = entry end
end
assert(stockIcon and reforgedIcon, "data must contain both stock and Reforged icons")
assert(ns.Path(stockIcon.name) == "Interface\\Icons\\" .. stockIcon.name, "path builder")
assert(ns.Path("INV_Misc_Anchor") == "Interface\\Icons\\INV_Misc_Anchor", "path builder")
assert(ns.TagLabel("reforged") == "Reforged (patch-I)", "reforged tooltip label")
assert(ns.TagLabel("stock") == "Stock 3.3.5a", "stock tooltip label")

-- ------------------------------------------------------------- tooltip ------

GameTooltip.Hide(GameTooltip)
target.scripts.OnEnter(target)
assert(GameTooltip.lines[1] == target.entry.name, "tooltip title is the icon name")
assert(GameTooltip.lines[2] == ns.TagLabel(target.entry.tag), "tooltip shows the source tag")
assert(GameTooltip.lines[3] == "Click to copy the path", "tooltip copy hint")
assert(GameTooltip:IsShown(), "tooltip shows on hover")
target.scripts.OnLeave(target)
assert(not GameTooltip:IsShown(), "tooltip hides on leave")

-- An empty slot has no entry and must not error on hover or click.
ns.SetSearch("INV_Misc_Anchor")
assert(#ns.State.matches > 0 and #ns.State.matches < pageSize, "narrow search must leave empty slots")
local filled = #ns.State.matches
local empty = ns.Buttons[filled + 1]
assert(empty and not empty.entry, "slot after the last match must be empty")
empty.scripts.OnEnter(empty)
assert(not GameTooltip:IsShown(), "empty slot must not open a tooltip")
empty.scripts.OnClick(empty)

-- No matches at all: every slot hides, the page clamps to 1, the labels still read correctly.
ns.SetSearch("zzzz-no-such-icon")
assert(#ns.State.matches == 0, "nonsense search must match nothing")
assert(ns.State.page == 1, "zero matches must clamp to page 1")
for index, button in ipairs(ns.Buttons) do
    assert(button.entry == nil and not button:IsShown(), "slot " .. index .. " must be empty and hidden")
end
assert(ns.countLabel.text == "0 matches", "zero-match count, got " .. tostring(ns.countLabel.text))
assert(ns.pageLabel.text == "Page 1 / 1", "zero-match page label, got " .. tostring(ns.pageLabel.text))
ns.nextButton.scripts.OnClick(ns.nextButton)
assert(ns.State.page == 1, "Next past the end must clamp")
ns.prevButton.scripts.OnClick(ns.prevButton)
assert(ns.State.page == 1, "Prev past the start must clamp")

-- A source with no matches in the current search must not error or leave a stale slot.
ns.SetSearch("INV_Misc_Anchor")
ns.SetSource("reforged")
local anchorReforged = 0
for _, entry in ipairs(ns.State.matches) do
    if entry.name == "INV_Misc_Anchor" then anchorReforged = anchorReforged + 1 end
    assert(entry.tag == "reforged", "source filter leaked a stock icon")
end
ns.SetSearch("")
ns.SetSource("all")
assert(#ns.State.matches == dataCount, "returning to All restores the full list")

print(string.format("ok: %d icons (%d stock, %d reforged), %d frames, paging, filters, copy path",
    #ns.Icons, stock, reforged, #frames))
