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
        -- Screen pixels of the frame's own top-left corner, as the client's anchors resolve them.
        screenLeft = 0,
        screenTop = 0,
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
    function frame:GetName() return self.name end
    -- WoW geometry. GetEffectiveScale is the product of the parent chain; GetLeft and GetTop
    -- return the screen position divided by the frame's OWN effective scale, which is why
    -- subtracting two frames' GetLeft() mixes units whenever their scales differ. The client
    -- divides a raw cursor by GetEffectiveScale before comparing it to GetCenter (see
    -- WorldMapButton_OnClick and WorldMapBlobFrame_CalculateHitTranslations), so the mock must
    -- divide too or the unit mix cannot surface.
    function frame:GetEffectiveScale()
        return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1)
    end
    function frame:GetLeft() return self.screenLeft / self:GetEffectiveScale() end
    function frame:GetTop() return self.screenTop / self:GetEffectiveScale() end
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
function WorldMapFrame_UpdateMap() end
function WorldMapFrame_OnShow() end
function WorldMapFrame_OnHide() end
function WorldMapFrame_DisplayQuests() end
function WorldMapFrame_SetQuestMapView() end
function WorldMapFrame_SetFullMapView() end
function WorldMap_ToggleSizeUp() end
function WorldMap_ToggleSizeDown() end
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
load("data/portals.lua")
load("data/transports.lua")
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

-- Static data.
assert(#ns.Pins == 73, "expected 73 pins, got " .. #ns.Pins)
local counts = { boss = 0, warpweaver = 0, callboard = 0, portal = 0, ship = 0, zeppelin = 0 }
for _, pin in ipairs(ns.Pins) do
    counts[pin.kind] = (counts[pin.kind] or 0) + 1
    assert(pin.mx >= 0 and pin.mx <= 1 and pin.my >= 0 and pin.my <= 1,
        "zone position outside the map: " .. tostring(pin.label))
    assert(pin.cx >= 0 and pin.cx <= 1 and pin.cy >= 0 and pin.cy <= 1,
        "continent position outside the map: " .. tostring(pin.label))
end
assert(counts.boss == 7, "expected 7 world bosses")
assert(counts.warpweaver == 10, "expected 10 Warpweavers")
assert(counts.callboard == 15, "expected 15 Call Boards")
assert(counts.portal == 12, "expected 12 portal rooms")
assert(counts.ship == 16, "expected 16 ship stations")
assert(counts.zeppelin == 13, "expected 13 zeppelin stations")
for _, pin in ipairs(ns.Pins) do
    assert(pin.kind == "boss" or pin.kind == "warpweaver" or pin.kind == "callboard"
        or pin.kind == "portal" or pin.kind == "ship" or pin.kind == "zeppelin",
        "unexpected pin kind: " .. pin.kind)
end

-- Portal pins: one per room, explicit title and subtitle, one destination per line.
local function find(predicate, what)
    for _, pin in ipairs(ns.Pins) do
        if predicate(pin) then
            return pin
        end
    end
    error("pin not found: " .. what)
end
local shattrat = find(function(pin)
    return pin.kind == "portal" and pin.title == "Shattrath City"
        and pin.subtitle == "Terrace of Light"
end, "Shattrath Terrace of Light")
assert(#shattrat.lines == 8, "Shattrath must list 8 capital destinations")
assert(shattrat.lines[1] == "To Stormwind", shattrat.lines[1])
assert(shattrat.icon == "Interface\\Icons\\Spell_Arcane_PortalShattrath", shattrat.icon)

local enclave = find(function(pin)
    return pin.kind == "portal" and pin.subtitle == "Silver Enclave"
end, "Silver Enclave")
assert(enclave.title == "Dalaran", enclave.title)
assert(enclave.icon == "Interface\\Icons\\Spell_Arcane_PortalStormWind", enclave.icon)
assert(#enclave.lines == 5, "Silver Enclave must list 5 destinations")

local sunreaver = find(function(pin)
    return pin.kind == "portal" and pin.subtitle == "Sunreaver's Sanctuary"
end, "Sunreaver's Sanctuary")
assert(sunreaver.title == "Dalaran", sunreaver.title)
assert(sunreaver.icon == "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar", sunreaver.icon)
assert(#sunreaver.lines == 5, "Sunreaver's Sanctuary must list 5 destinations")

-- A portal pin without its own icon must fall back to the kind icon instead of erroring.
assert(ns.ICONS.portal == "Interface\\Icons\\Spell_Arcane_PortalShattrath", ns.ICONS.portal)

local blasted = find(function(pin)
    return pin.kind == "portal" and pin.title == "Stormwind City"
end, "Stormwind Blasted Lands portal")
-- Icon names must match the client's own spelling, because tools/icon-browser/IconBrowserIcons.lua
-- is the list we choose from and it is case-sensitive there.
assert(blasted.icon == "Interface\\Icons\\Spell_Arcane_PortalStormWind", blasted.icon)
-- The room's name is the destination, so the pin carries no extra destination line.
assert(blasted.subtitle == "Portal - Blasted Lands", blasted.subtitle)
assert(blasted.lines == nil, "Blasted Lands must not repeat its name, got "
    .. tostring(blasted.lines and blasted.lines[1]))

-- Transport pins: one per station node, no merging, station as title, destination as one line.
local harbor = find(function(pin)
    return pin.kind == "ship" and pin.title == "Stormwind Harbor"
        and pin.lines[1] == "To Auberdine"
end, "Stormwind Harbor to Auberdine")
assert(harbor.icon == nil, "ship pins use the kind icon")
assert(ns.ICONS.ship == "Interface\\Icons\\INV_ShipMount", ns.ICONS.ship)

local westguard = find(function(pin) return pin.title == "Westguard Keep" end, "Westguard Keep")
assert(#westguard.lines == 1 and westguard.lines[1] == "To Shattered Straits",
    "the shared-coordinate route must be one pin naming the other end")

-- A portal pin must draw its own room icon, not the kind fallback, and its tooltip must show the
-- city, the room and the destinations. Stormwind's fallback and room icons differ, so this bites.
continent, mapZoneIndex, zoneName = 2, 1, "Stormwind City"
ns.Refresh()
local blastedFrame = nil
for _, frame in ipairs(visible()) do
    if frame.pin.kind == "portal" then blastedFrame = frame end
end
assert(blastedFrame, "Stormwind must show its Blasted Lands portal pin")
assert(blastedFrame.icon.texture == blastedFrame.pin.icon,
    "portal pin must draw its room icon, got " .. tostring(blastedFrame.icon.texture))
blastedFrame.scripts.OnEnter(blastedFrame)
assert(WorldMapTooltip.lines[1] == "Stormwind City",
    "portal tooltip title, got " .. tostring(WorldMapTooltip.lines[1]))
-- The room is already named after the destination, so the tooltip must not repeat it as "To
-- Blasted Lands" on the next line. One mention of the destination per tooltip.
assert(WorldMapTooltip.lines[2] == "Portal - Blasted Lands",
    "portal tooltip room, got " .. tostring(WorldMapTooltip.lines[2]))
assert(WorldMapTooltip.lines[3] == nil,
    "the Blasted Lands room must not repeat its destination, got "
        .. tostring(WorldMapTooltip.lines[3]))
blastedFrame.scripts.OnLeave(blastedFrame)

-- Shattrath shows two portal pins and lists every capital.
continent, mapZoneIndex, zoneName = 3, 1, "Shattrath City"
ns.Refresh()
local portals = 0
for _, frame in ipairs(visible()) do
    if frame.pin.kind == "portal" then portals = portals + 1 end
end
assert(portals == 2, "Shattrath must show both portal pins, got " .. portals)

-- A transport pin tooltip is the station and the destination, and it uses the neutral kind icon.
continent, mapZoneIndex, zoneName = 2, 1, "Wetlands"
ns.Refresh()
local harborFrame = nil
for _, frame in ipairs(visible()) do
    if frame.pin.kind == "ship" and frame.pin.title == "Menethil Harbor"
        and frame.pin.lines[1] == "To Theramore" then
        harborFrame = frame
    end
end
assert(harborFrame, "Menethil Harbor to Theramore pin missing")
assert(harborFrame.icon.texture == "Interface\\Icons\\INV_ShipMount",
    "ship pin must use the neutral ship icon, got " .. tostring(harborFrame.icon.texture))
harborFrame.scripts.OnEnter(harborFrame)
assert(WorldMapTooltip.lines[1] == "Menethil Harbor",
    "transport tooltip title, got " .. tostring(WorldMapTooltip.lines[1]))
assert(WorldMapTooltip.lines[2] == "To Theramore",
    "transport tooltip destination, got " .. tostring(WorldMapTooltip.lines[2]))
harborFrame.scripts.OnLeave(harborFrame)
assert(ns.ICONS.zeppelin == "Interface\\Icons\\INV_ZeppelinMount", ns.ICONS.zeppelin)

-- The owner chose one pin per station node and no distance merging, so every transport node must
-- be its own coordinate. A reintroduced merge removes a pin and passes a uniqueness check that
-- keys on title, so this asserts distinct coordinates directly.
local coords = {}
for _, pin in ipairs(ns.Pins) do
    if pin.kind == "ship" or pin.kind == "zeppelin" then
        local key = string.format("%.1f|%.1f", pin.x, pin.y)
        assert(not coords[key], "two transport pins share a coordinate: " .. key)
        coords[key] = true
    end
end

-- Hooks must be installed.
for _, name in ipairs({ "WorldMapFrame_Update", "WorldMapFrame_OnShow", "WorldMapFrame_OnHide" }) do
    assert(hooks[name] and #hooks[name] == 1, "missing hook: " .. name)
end

-- Stormwind zone map: Warpweaver, Call Board, one Blasted Lands portal and the two harbor
-- station pins. The Warpweaver pin carries the position and hover assertions.
continent, mapZoneIndex, zoneName = 1, 1, "Stormwind City"
ns.Refresh()
local stormwind = visible()
assert(#stormwind == 5, "Stormwind must show 5 pins, got " .. #stormwind)
local service = 0
for _, frame in ipairs(stormwind) do
    if frame.pin.kind == "warpweaver" or frame.pin.kind == "callboard" then
        service = service + 1
    end
end
assert(service == 2, "Stormwind must show both service pins, got " .. service)
local warp = nil
for _, frame in ipairs(stormwind) do
    if frame.pin.label == "Warpweaver" then warp = frame end
    -- Questie's arrangement: WorldMapFrame level + 7, and the frame's own strata. A child of
    -- WorldMapButton at POI_FRAMELEVEL + 50 drew but never received a mouse event.
    -- 8 is one above Questie's 7, so a player's map addon cannot win the mouse on load order.
    assert(frame.level == WorldMapFrame:GetFrameLevel() + 8,
        "pin must sit one level above Questie's pins, got " .. frame.level)
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
-- The expectation is derived from raw screen pixels and the addon's documented anchor contract
-- (CENTER of the pin at the map's fraction, anchored to WorldMapFrame TOPLEFT). It deliberately
-- does NOT reuse MapRect's arithmetic: a mirror of the implementation asserts only that the code
-- equals itself and would pass with the unit mix that caused the drift.
local function expectedPoint(pin, fx, fy)
    local frameScale = WorldMapFrame:GetEffectiveScale()
    local buttonScale = WorldMapButton:GetEffectiveScale()
    local mapLeft = WorldMapButton.screenLeft
    local mapTop = WorldMapButton.screenTop
    local screenX = mapLeft + (fx or pin.mx) * WorldMapButton:GetWidth() * buttonScale
    local screenY = mapTop - (fy or pin.my) * WorldMapButton:GetHeight() * buttonScale
    return (screenX - WorldMapFrame.screenLeft) / frameScale,
        (screenY - WorldMapFrame.screenTop) / frameScale
end
local function assertAtWarp(label, pin, fx, fy)
    local point = warp.points[#warp.points]
    local input = pin or warp.pin
    local ex, ey = expectedPoint(input, fx, fy)
    assert(point[1] == "CENTER" and point[2] == WorldMapFrame and point[3] == "TOPLEFT",
        label .. ": pin must be anchored to WorldMapFrame TOPLEFT")
    assert(math.abs(point[4] - ex) < 0.01, label .. ": pin X is off, got " .. point[4] .. " want " .. ex)
    assert(math.abs(point[5] - ey) < 0.01, label .. ": pin Y is off, got " .. point[5] .. " want " .. ey)
end

-- Real nesting, from the shipped WorldMapFrame.xml: WorldMapDetailFrame and WorldMapButton are
-- SIBLINGS under WorldMapFrame. The button is only anchored to the detail frame, and the client
-- scales each of them independently (0.691 quest, 0.573 windowed, 1.0 full map), so the button's
-- effective scale is 0.691 in the quest view, not 0.4775.
WorldMapDetailFrame = Frame()
WorldMapDetailFrame.parent = WorldMapFrame
WorldMapDetailFrame.screenLeft = 120
WorldMapDetailFrame.screenTop = 700
WorldMapButton.parent = WorldMapFrame

assertAtWarp("full map")

-- Quest view: both frames scaled 0.691, but independently. Only the button carries the map.
WorldMapDetailFrame.scale = 0.691
WorldMapButton.scale = 0.691
-- The button's screen rect moves because it is scaled about its own anchor, so model that too.
WorldMapButton.screenLeft = 145
WorldMapButton.screenTop = 640
ns.Refresh()
assertAtWarp("quest view, 0.691 each")

-- The old bug: subtracting the button's GetLeft (already divided by the button's 0.691) from the
-- frame's GetLeft (divided by 1.0) mixes unit spaces. Assert the naive formula really is far off,
-- so this test cannot silently stop exercising the fix.
local naiveDx = (WorldMapButton:GetLeft() - WorldMapFrame:GetLeft()) / WorldMapFrame:GetEffectiveScale()
local correctDx = expectedPoint(warp.pin)
assert(math.abs(naiveDx - correctDx) > 20,
    "the quest-view fixture must be far enough from the naive formula for the test to bite, got "
        .. naiveDx .. " vs " .. correctDx)

-- Windowed view, a size no test above uses, then an addon that scales only one frame.
WorldMapButton.scale = 0.573
ns.Refresh()
assertAtWarp("windowed view, 0.573")
WorldMapButton.scale = 0.5
ns.Refresh()
assertAtWarp("button scaled 0.5 alone")
WorldMapButton.scale = 1.0
ns.Refresh()
assertAtWarp("full map again")
WorldMapDetailFrame.scale = 1.0
ns.Refresh()

-- The objectives checkbox re-scales the map through WorldMapFrame_DisplayQuests, which never
-- calls WorldMapFrame_Update. Hooking only Update left the pins at the previous view's offsets,
-- which was the defect the owner reported, so every path that moves the map must refresh.
local function assertRefreshes(name)
    assert(hooks[name] and #hooks[name] > 0, name .. " must trigger a pin refresh")
end
for _, name in ipairs({
    "WorldMapFrame_Update", "WorldMapFrame_UpdateMap", "WorldMapFrame_OnShow",
    "WorldMapFrame_DisplayQuests", "WorldMapFrame_SetQuestMapView",
    "WorldMapFrame_SetFullMapView", "WorldMap_ToggleSizeUp", "WorldMap_ToggleSizeDown",
    "WorldMapFrame_OnHide",
}) do
    assertRefreshes(name)
end
for _, name in ipairs({
    "WorldMapFrame_DisplayQuests", "WorldMapFrame_SetQuestMapView", "WorldMap_ToggleSizeUp",
}) do
    hooks[name][1]()
    assert(#visible() > 0, name .. " must reposition the pins, not only re-level them")
end

-- PlaceLevel runs on every refresh, not only at creation: the client re-levels its own map
-- frames on show, so a pin that is only leveled once can fall behind.
local before = warp.level
WorldMapFrame.level = 120
ns.Refresh()
assert(warp.level == 128, "refresh must re-level the pin, got " .. warp.level)
WorldMapFrame.level = before - 8
ns.Refresh()
assert(warp.level == before, "refresh must follow the frame level back, got " .. warp.level)

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

-- A third-party addon can make a handler raise. The layer must survive it, and report it once.
local setText = WorldMapTooltip.SetText
WorldMapTooltip.SetText = function() error("third-party tooltip broke") end
local errors = {}
local realPrintError = print
print = function(text) errors[#errors + 1] = text end
warp.scripts.OnEnter(warp)
warp.scripts.OnEnter(warp)
print = realPrintError
WorldMapTooltip.SetText = setText
assert(ns.GuardErrors and ns.GuardErrors.enter == 2,
    "a failing handler must be counted, got " .. tostring(ns.GuardErrors and ns.GuardErrors.enter))
assert(#errors == 1 and errors[1]:find("enter handler failed"),
    "a failing handler must be reported once, got " .. #errors .. " lines")
assert(WorldMapTooltip.shown ~= true, "a failed handler must not leave a broken tooltip up")
-- The same pin still works once the other addon stops erroring.
WorldMapPOIFrame.allowBlobTooltip = true
warp.scripts.OnEnter(warp)
assert(WorldMapTooltip.shown == true, "the pin must still work after a failed handler")
warp.scripts.OnLeave(warp)

-- A boss zone shows only that boss.
continent, mapZoneIndex, zoneName = 1, 1, "Duskwood"
ns.Refresh()
local duskwood = visible()
assert(#duskwood == 1, "Duskwood must show 1 pin, got " .. #duskwood)

assert(duskwood[1].pin.label == "Taerar", "wrong Duskwood pin")
duskwood[1].scripts.OnEnter(duskwood[1])
assert(WorldMapTooltip.lines[1] == "Taerar", "boss tooltip title is the boss name")
assert(WorldMapTooltip.lines[2] == "Classic world boss - Duskwood", "boss tooltip names kind and zone")

-- A city's pins must also draw on the zone map that contains it. Thunder Bluff stores zone 1638
-- (the city) and Mulgore is 215, so matching the id alone left the Mulgore map empty.
local function zonePins(name)
    continent, mapZoneIndex, zoneName = 1, 1, name
    ns.Refresh()
    return visible()
end
local function titles(list)
    local out = {}
    for _, frame in ipairs(list) do
        out[frame.pin.title or frame.pin.label .. "|" .. frame.pin.place] = true
    end
    return out
end
local function firstOf(list, key)
    for _, frame in ipairs(list) do
        if (frame.pin.title or frame.pin.label .. "|" .. frame.pin.place) == key then
            return frame
        end
    end
end
local tbCity = titles(zonePins("Thunder Bluff"))
assert(tbCity["Thunder Bluff"], "the Thunder Bluff city map must draw its own pins")
local tbMulgore = zonePins("Mulgore")
assert(titles(tbMulgore)["Thunder Bluff"],
    "the Mulgore map must draw the Thunder Bluff pins; a city's pins draw on their region map")
-- The region map is about five times the width of the city micro-map, so drawing the city's
-- mx/my there parks every pin in the sea. The pin carries px/py for exactly this case.
local tbOnRegion = firstOf(tbMulgore, "Thunder Bluff")
assert(tbOnRegion and tbOnRegion.pin.px, "the Thunder Bluff pins must carry region fractions")
local tbPoint = tbOnRegion.points[#tbOnRegion.points]
local tbEx, tbEy = expectedPoint(tbOnRegion.pin, tbOnRegion.pin.px, tbOnRegion.pin.py)
assert(math.abs(tbPoint[4] - tbEx) < 0.01 and math.abs(tbPoint[5] - tbEy) < 0.01,
    "the Thunder Bluff pin must land on its region fraction on the Mulgore map")
local cityEx, cityEy = expectedPoint(tbOnRegion.pin, tbOnRegion.pin.mx, tbOnRegion.pin.my)
assert(math.abs(tbPoint[4] - cityEx) > 20 or math.abs(tbPoint[5] - cityEy) > 20,
    "the region position must differ from the city position, or the fixture proves nothing")
local elwynn = titles(zonePins("Elwynn Forest"))
assert(elwynn["Stormwind City"], "the Elwynn Forest map must draw the Stormwind pins")
-- A zone with no pin of its own and no city inside it stays empty.
assert(#zonePins("Westfall") == 0, "Westfall has no pin and no city, so it must stay empty")
-- The parent rule must not leak pins to unrelated zones.
local strangle = titles(zonePins("Stranglethorn Vale"))
assert(not strangle["Stormwind City"], "Stormwind pins must not appear in Stranglethorn")

-- A zone without pins shows none.
continent, mapZoneIndex, zoneName = 1, 1, "Westfall"
ns.Refresh()
assert(#visible() == 0, "Westfall must show no pins")

-- Continent maps show only pins of that continent, at their continent position.
-- Client order is 1 Kalimdor, 2 Eastern Kingdoms, 3 Outland, 4 Northrend.
continent, mapZoneIndex, zoneName = 2, 0, ""
ns.Refresh()
assert(#visible() == 25, "Eastern Kingdoms must show 25 pins, got " .. #visible())
local first = visible()[1]
local cpoint = first.points[#first.points]
local cex, cey = expectedPoint({ mx = first.pin.cx, my = first.pin.cy })
assert(cpoint[2] == WorldMapFrame, "continent pin must be anchored to WorldMapFrame")
assert(math.abs(cpoint[4] - cex) < 0.01, "continent pin X must be exact, got " .. cpoint[4])
assert(math.abs(cpoint[5] - cey) < 0.01, "continent pin Y must be exact, got " .. cpoint[5])

continent, mapZoneIndex = 1, 0
ns.Refresh()
assert(#visible() == 32, "Kalimdor must show 32 pins, got " .. #visible())
continent, mapZoneIndex = 3, 0
ns.Refresh()
assert(#visible() == 7, "Outland must show 7 pins, got " .. #visible())
continent, mapZoneIndex = 4, 0
ns.Refresh()
assert(#visible() == 9, "Northrend must show 9 pins, got " .. #visible())

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
-- The diagnostic must name the geometry the owner needs to report a misplaced pin: the map
-- rect, the effective scale, and the frame under the mouse. A one-line "73 pins" cannot tell a
-- scale bug from a data bug.
assert(printed[1] and printed[1]:find("^WorldMapPins: 73 pins"), printed[1] or "no output")
assert(printed[2] and printed[2]:find("^  pin level 8 above frame, map rect ") and printed[2]:find(","),
    printed[2] or "no map rect line")
assert(printed[3] and printed[3]:find("^  mouse over "), printed[3] or "no mouse line")

-- The zone list resolver handles the "The"/"City" spelling differences.
zoneName = "Stormwind City"
assert(ns.DisplayedZone(1, 1) == 1519, "Stormwind City must resolve")
zoneName = "The Exodar"
assert(ns.DisplayedZone(2, 1) == 3557, "The Exodar must resolve")
zoneName = "Silvermoon City"
assert(ns.DisplayedZone(1, 1) == 3487, "Silvermoon City must resolve")

print(string.format("ok: %d pins, %d frames, tooltips, exact positions, no OnUpdate", #ns.Pins, created))
