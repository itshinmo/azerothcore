-- Offline smoke test for the WorldMapPins addon.
-- Run: luajit data/client-patches/map-pins/tests/test_addon.lua
--
-- It mocks only the 3.3.5 map API the addon uses. It proves the pin set, tooltip text,
-- hover frame level, exact positions, zone/continent visibility, and the absence of an
-- OnUpdate loop. It is not a substitute for the owner's in-client test.

local root = arg[1] or "data/client-patches/map-pins/src/WorldMapPins"
local continent = 1
local mapZoneIndex = 1
local zoneName = "Stormwind City"
local shown = true
local mapClicks = 0
local hooks = {}
local created = 0

local function Frame()
    local frame = {
        width = 400,
        height = 500,
        level = 90,
        scale = 1,
        strata = "MEDIUM",
        shown = true,
        mouse = false,
        scripts = {},
        points = {},
        textures = {},
    }
    function frame:SetWidth(value) self.width = value end
    function frame:SetHeight(value) self.height = value end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:SetFrameLevel(value) self.level = value end
    function frame:GetFrameLevel() return self.level end
    function frame:SetFrameStrata(value) self.strata = value end
    function frame:GetFrameStrata() return self.strata end
    function frame:GetScale() return self.scale end
    function frame:EnableMouse(value) self.mouse = value ~= false end
    function frame:RegisterForClicks() end
    function frame:SetScript(name, handler) self.scripts[name] = handler end
    function frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function frame:ClearAllPoints() self.points = {} end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:CreateTexture()
        local texture = { shown = true }
        function texture:SetWidth() end
        function texture:SetHeight() end
        function texture:SetPoint() end
        function texture:SetTexture(value) self.texture = value end
        return texture
    end
    created = created + 1
    return frame
end

WORLDMAP_POI_FRAMELEVEL = 100
WorldMapButton = Frame()
WorldMapFrame = Frame()
function WorldMapFrame:IsShown() return shown end
WorldMapPOIFrame = Frame()
WorldMapPOIFrame.allowBlobTooltip = true
WorldMapTooltip = Frame()
function WorldMapTooltip:SetOwner() end
function WorldMapTooltip:SetText(text) self.lines = { text } end
function WorldMapTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function WorldMapTooltip:Show() self.shown = true end
function WorldMapTooltip:Hide() self.shown = false end
GameTooltip = Frame()
function GameTooltip:SetOwner() end
function GameTooltip:SetText(text) self.lines = { text } end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false end
SlashCmdList = {}
function GetMouseFocus() return nil end

function CreateFrame(_, _, parent)
    local frame = Frame()
    frame.parent = parent
    return frame
end

function GetCurrentMapContinent()
    return continent
end

function GetCurrentMapZone()
    return mapZoneIndex
end

function GetMapZones()
    return zoneName
end

function hooksecurefunc(name, handler)
    hooks[name] = hooks[name] or {}
    hooks[name][#hooks[name] + 1] = handler
end

function WorldMapFrame_Update() end
function WorldMapFrame_OnShow() end
function WorldMapFrame_OnHide() end
function WorldMapButton_OnClick()
    mapClicks = mapClicks + 1
end

local ns = {}
local function load(name)
    assert(loadfile(root .. "/" .. name))("WorldMapPins", ns)
end
load("data/zones.lua")
load("data/bosses.lua")
load("data/services.lua")
load("WorldMapPins.lua")

-- The addon keeps its frames private; collect them from CreateFrame instead.
local frames = {}
local originalCreateFrame = CreateFrame
function CreateFrame(...)
    local frame = originalCreateFrame(...)
    frames[#frames + 1] = frame
    return frame
end

ns.Refresh()

local function visible()
    local out = {}
    for _, frame in ipairs(frames) do
        if frame.pin and frame:IsShown() then
            out[#out + 1] = frame
        end
    end
    return out
end

local function labels(list)
    local out = {}
    for _, frame in ipairs(list) do
        out[#out + 1] = frame.pin.label
    end
    table.sort(out)
    return out
end

-- Static data.
assert(#ns.Pins == 32, "expected 32 pins, got " .. #ns.Pins)
local counts = { boss = 0, warpweaver = 0, callboard = 0 }
for _, pin in ipairs(ns.Pins) do
    counts[pin.kind] = (counts[pin.kind] or 0) + 1
    assert(pin.mx >= 0 and pin.mx <= 1 and pin.my >= 0 and pin.my <= 1,
        "zone position outside the map: " .. pin.label)
    assert(pin.cx >= 0 and pin.cx <= 1 and pin.cy >= 0 and pin.cy <= 1,
        "continent position outside the map: " .. pin.label)
end
assert(counts.boss == 7, "expected 7 world bosses")
assert(counts.warpweaver == 10, "expected 10 Warpweavers")
assert(counts.callboard == 15, "expected 15 Call Boards")
for _, pin in ipairs(ns.Pins) do
    assert(pin.kind == "boss" or pin.kind == "warpweaver" or pin.kind == "callboard",
        "unexpected pin kind: " .. pin.kind)
end

-- Hooks must be installed.
for _, name in ipairs({ "WorldMapFrame_Update", "WorldMapFrame_OnShow", "WorldMapFrame_OnHide" }) do
    assert(hooks[name] and #hooks[name] == 1, "missing hook: " .. name)
end

-- Stormwind zone map: Warpweaver + Call Board, exact positions, hoverable.
continent, mapZoneIndex, zoneName = 1, 1, "Stormwind City"
ns.Refresh()
local stormwind = visible()
assert(#stormwind == 2, "Stormwind must show 2 pins, got " .. #stormwind)
local names = labels(stormwind)
assert(names[1] == "Call Board" and names[2] == "Warpweaver", "wrong Stormwind pins")
local warp = nil
for _, frame in ipairs(stormwind) do
    if frame.pin.label == "Warpweaver" then warp = frame end
    -- Questie's arrangement: WorldMapFrame level + 7, and the frame's own strata. A child of
    -- WorldMapButton at POI_FRAMELEVEL + 50 drew but never received a mouse event.
    assert(frame.level == WorldMapFrame:GetFrameLevel() + 7,
        "pin must sit above the map frame, got " .. frame.level)
    assert(frame.strata == WorldMapFrame:GetFrameStrata(), "pin must copy the map strata")
    -- The parent is what broke hover: a child of WorldMapButton drew but got no mouse event.
    assert(frame.parent == WorldMapFrame, "pin must be a child of WorldMapFrame")
    assert(frame.mouse, "pin must enable the mouse or hover never fires")
    assert(frame:GetWidth() == 24 and frame:GetHeight() == 24, "pin hit box must be 24x24")
    assert(frame.scripts.OnUpdate == nil, "no OnUpdate loop allowed")
end
assert(warp, "Warpweaver pin missing")
assert(warp.icon.texture == "Interface\\Icons\\INV_NetherPortal",
    "Warpweaver must use the void portal icon")
local point = warp.points[#warp.points]
assert(math.abs(point[4] - warp.pin.mx * WorldMapButton:GetWidth()) < 0.01, "pin X must be exact")
assert(math.abs(point[5] + warp.pin.my * WorldMapButton:GetHeight()) < 0.01, "pin Y must be exact")

-- The map scales WorldMapButton; the pin is anchored in the unscaled WorldMapFrame, so the
-- offset must follow the displayed size. A missed scale puts every pin in the wrong place.
WorldMapButton.scale = 0.691
ns.Refresh()
point = warp.points[#warp.points]
assert(math.abs(point[4] - warp.pin.mx * WorldMapButton:GetWidth() * 0.691) < 0.01,
    "pin X must follow the map scale")
assert(math.abs(point[5] + warp.pin.my * WorldMapButton:GetHeight() * 0.691) < 0.01,
    "pin Y must follow the map scale")
WorldMapButton.scale = 1
ns.Refresh()

-- PlaceLevel runs on every refresh, not only at creation: the client re-levels its own map
-- frames on show, so a pin that is only leveled once can fall behind.
local before = warp.level
WorldMapFrame.level = 120
ns.Refresh()
assert(warp.level == 127, "refresh must re-level the pin, got " .. warp.level)
WorldMapFrame.level = before - 7
ns.Refresh()
assert(warp.level == before, "refresh must follow the frame level back")

-- Hiding the map while hovered must restore the quest blob tooltip.
WorldMapPOIFrame.allowBlobTooltip = false
hooks.WorldMapFrame_OnHide[1]()
assert(WorldMapPOIFrame.allowBlobTooltip == true, "OnHide must restore the blob tooltip")

-- Hover must state what the pin is, on the map tooltip, and must silence the blob tooltip.
WorldMapPOIFrame.allowBlobTooltip = true
warp.scripts.OnEnter(warp)
assert(WorldMapTooltip.lines[1] == "Stormwind City", "tooltip title is the city")
assert(WorldMapTooltip.lines[2] == "Warpweaver - Transmogrifier",
    "tooltip names the service, because a stacked pair leaves only the top pin hoverable")
assert(WorldMapTooltip.shown == true, "hover must show the map tooltip")
assert(GameTooltip.lines == nil, "hover must not use GameTooltip")
assert(WorldMapPOIFrame.allowBlobTooltip == false,
    "hover must stop the quest blob tooltip from replacing the pin tooltip")
warp.scripts.OnLeave(warp)
assert(WorldMapTooltip.shown == false, "tooltip must hide on leave")
assert(WorldMapPOIFrame.allowBlobTooltip == true, "leave must restore the blob tooltip")

-- Clicking a pin must not swallow the stock map click.
warp.scripts.OnClick(warp, "LeftButtonUp")
assert(mapClicks == 1, "pin click must forward to WorldMapButton_OnClick")

-- A boss zone shows only that boss.
continent, mapZoneIndex, zoneName = 1, 1, "Duskwood"
ns.Refresh()
local duskwood = visible()
assert(#duskwood == 1, "Duskwood must show 1 pin, got " .. #duskwood)

assert(duskwood[1].pin.label == "Taerar", "wrong Duskwood pin")
duskwood[1].scripts.OnEnter(duskwood[1])
assert(WorldMapTooltip.lines[1] == "Taerar", "boss tooltip title is the boss name")
assert(WorldMapTooltip.lines[2] == "Classic world boss - Duskwood", "boss tooltip names kind and zone")

-- A zone without pins shows none.
continent, mapZoneIndex, zoneName = 1, 1, "Westfall"
ns.Refresh()
assert(#visible() == 0, "Westfall must show no pins")

-- Continent maps show only pins of that continent, at their continent position.
-- Client order is 1 Kalimdor, 2 Eastern Kingdoms, 3 Outland, 4 Northrend.
continent, mapZoneIndex, zoneName = 2, 0, ""
ns.Refresh()
assert(#visible() == 11, "Eastern Kingdoms must show 11 pins, got " .. #visible())
local first = visible()[1]
local cpoint = first.points[#first.points]
assert(math.abs(cpoint[4] - first.pin.cx * WorldMapButton:GetWidth()) < 0.01,
    "continent pin X must be exact")
assert(math.abs(cpoint[5] + first.pin.cy * WorldMapButton:GetHeight()) < 0.01,
    "continent pin Y must be exact")

continent, mapZoneIndex = 1, 0
ns.Refresh()
assert(#visible() == 14, "Kalimdor must show 14 pins, got " .. #visible())
continent, mapZoneIndex = 3, 0
ns.Refresh()
assert(#visible() == 5, "Outland must show 5 pins, got " .. #visible())
continent, mapZoneIndex = 4, 0
ns.Refresh()
assert(#visible() == 2, "Northrend must show 2 pins, got " .. #visible())

-- Hiding the map hides every pin.
hooks.WorldMapFrame_OnHide[1]()
assert(#visible() == 0, "OnHide must hide all pins")

-- The continent offsets for Silvermoon and The Exodar come from WorldMapTransforms.dbc. The
-- client adds them before projecting on the Eastern Kingdoms and Kalimdor maps. The old raw
-- values put both cities in the ocean; these are the values the client's own landmark uses.
local function pin(zone, label)
    for _, candidate in ipairs(ns.Pins) do
        if candidate.zone == zone and candidate.label == label then
            return candidate
        end
    end
    error("pin not found: " .. label .. " in " .. zone)
end
local function close(a, b)
    return math.abs(a - b) < 0.0002
end
local smw = pin(3487, "Warpweaver")
assert(smw.cont == 2 and close(smw.cx, 0.5698) and close(smw.cy, 0.1365),
    "Silvermoon Warpweaver continent position must use the WorldMapTransforms offset")
local smc = pin(3487, "Call Board")
assert(smc.cont == 2 and close(smc.cx, 0.5645) and close(smc.cy, 0.1476),
    "Silvermoon Call Board continent position must use the WorldMapTransforms offset")
local exw = pin(3557, "Warpweaver")
assert(exw.cont == 1 and close(exw.cx, 0.3014) and close(exw.cy, 0.2690),
    "Exodar Warpweaver continent position must use the WorldMapTransforms offset")
local exc = pin(3557, "Call Board")
assert(exc.cont == 1 and close(exc.cx, 0.3033) and close(exc.cy, 0.2616),
    "Exodar Call Board continent position must use the WorldMapTransforms offset")
-- Zone positions never take the offset; they were always right.
assert(close(smw.mx, 0.8602) and close(smw.my, 0.3514), "Silvermoon zone position changed")
assert(close(exw.mx, 0.5292) and close(exw.my, 0.4570), "Exodar zone position changed")

-- The diagnostic slash command must exist and run without error.
assert(type(SlashCmdList["WORLDMAPPINS"]) == "function", "missing /wmp diagnostic")
local printed = {}
local realPrint = print
print = function(text) printed[#printed + 1] = text end
SlashCmdList["WORLDMAPPINS"]()
print = realPrint
assert(#printed == 1 and printed[1]:find("^WorldMapPins: 32 pins"), printed[1] or "no output")

-- The zone list resolver handles the "The"/"City" spelling differences.
zoneName = "Stormwind City"
assert(ns.DisplayedZone(1, 1) == 1519, "Stormwind City must resolve")
zoneName = "The Exodar"
assert(ns.DisplayedZone(2, 1) == 3557, "The Exodar must resolve")
zoneName = "Silvermoon City"
assert(ns.DisplayedZone(1, 1) == 3487, "Silvermoon City must resolve")

print(string.format("ok: %d pins, %d frames, tooltips, exact positions, no OnUpdate", #ns.Pins, created))
