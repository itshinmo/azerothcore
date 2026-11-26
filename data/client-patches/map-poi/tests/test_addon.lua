-- Offline smoke test for the baked ServerMapPOI addon.
-- Run: luajit data/client-patches/map-poi/tests/test_addon.lua
--
-- It mocks only the 3.3.5 map API the addon uses. It proves load, pins per zone,
-- hide/show, dynamic hooks, the red overlay, tooltips, and the absence of an
-- OnUpdate loop. It is not a substitute for the owner's in-client test.

local root = arg[1] or "data/client-patches/map-poi/src/ServerMapPOI"
local zone = 1519
local area = 1519
local continent = 1
local inInstance = false
local shown = true
local now = 1000
local messages = {}
local hooks = {}
local registeredPrefix
local created = 0

local function Frame()
    local frame = {
        width = 384,
        height = 512,
        level = 90,
        shown = true,
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
    function frame:RegisterForClicks() end
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript(name, handler) self.scripts[name] = handler end
    function frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:CreateTexture()
        local texture = { shown = true }
        function texture:SetWidth() end
        function texture:SetHeight() end
        function texture:SetPoint() end
        function texture:SetTexture() end
        function texture:SetVertexColor() end
        function texture:SetAllPoints() end
        function texture:Show() self.shown = true end
        function texture:Hide() self.shown = false end
        function texture:IsShown() return self.shown end
        return texture
    end
    created = created + 1
    return frame
end

WorldMapButton = Frame()
WorldMapFrame = Frame()
WorldMapFrame.shown = shown
function WorldMapFrame:IsShown() return shown end
WorldMapTooltip = Frame()
function WorldMapTooltip:SetOwner() end
function WorldMapTooltip:SetText(text) self.text = text end
function WorldMapTooltip:AddLine() end
function WorldMapTooltip:Show() self.shown = true end
function WorldMapTooltip:Hide() self.shown = false end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) messages[#messages + 1] = text end }

function CreateFrame()
    return Frame()
end

function GetCurrentMapZone()
    return zone
end

function GetCurrentMapAreaID()
    return area
end

function GetCurrentMapContinent()
    return continent
end

function IsInInstance()
    return inInstance
end

function GetCurrentMapDungeonLevel()
    return 1
end

function GetTime()
    return now
end

function RegisterAddonMessagePrefix(prefix)
    registeredPrefix = prefix
    return true
end

function hooksecurefunc(name, handler)
    hooks[name] = hooks[name] or {}
    hooks[name][#hooks[name] + 1] = handler
end

function WorldMapFrame_Update() end
function WorldMapFrame_OnShow() end
function WorldMapFrame_OnHide() end

local fixture = assert(loadfile(root .. "/../../tests/fixtures/outlaw.lua"))()

local ns = {}
assert(loadfile(root .. "/Data.lua"))("ServerMapPOI", ns)
assert(loadfile(root .. "/ServerMapPOI.lua"))("ServerMapPOI", ns)
local addon = _G.ServerMapPOI
assert(addon, "ServerMapPOI global missing")
assert(registeredPrefix == ns.Outlaw.prefix, "SMPOI prefix must be registered for CHAT_MSG_ADDON")
assert(addon.scripts.OnUpdate == nil, "addon must not register OnUpdate")

-- Fire the login event.
addon.scripts.OnEvent(addon, "PLAYER_LOGIN")
assert(#addon.pins == #ns.POIs, "every static POI must get one reused pin")
assert(#messages >= 1, "login must print the addon load line")

local function visibleCount(zoneId)
    zone = zoneId
    area = zoneId
    hooks.WorldMapFrame_Update[1]()
    local total = 0
    for _, pin in ipairs(addon.pins) do
        if pin:IsShown() then
            total = total + 1
        end
    end
    return total
end

-- Counts are derived from the generated data, so the test states the invariant rather than a
-- hard-coded number that breaks on every harvest: every POI in a zone is shown, and nothing from
-- another zone is.
local function expectedIn(zoneId)
    local total = 0
    for _, poi in ipairs(ns.POIs) do
        if poi.zone == zoneId then
            total = total + 1
        end
    end
    return total
end

for _, zoneId in ipairs({ 1519, 1637, 4395, 3483, 3703, 571 }) do
    assert(visibleCount(zoneId) == expectedIn(zoneId),
        "zone " .. zoneId .. " must show exactly its own markers")
end
assert(expectedIn(1519) > 10, "Stormwind must carry flight masters, innkeepers and battlemasters")
assert(expectedIn(3483) > 3, "Hellfire must carry its flight masters and Kazzak skull")
assert(visibleCount(99999) == 0, "an unknown zone must show no markers")

-- Every drawn kind has an icon and a faction colour; an unknown kind would silently fall back.
local seenKinds = {}
for _, poi in ipairs(ns.POIs) do
    seenKinds[poi.kind] = true
end
assert(seenKinds.flightmaster, "the layer must draw flight masters")
assert(seenKinds.innkeeper, "the layer must draw innkeepers")
assert(seenKinds.meetingstone, "the layer must draw meeting stones")
assert(seenKinds.portal, "the layer must draw portals")
assert(seenKinds.battlemaster, "the layer must draw battlemasters")
assert(#ns.TransportRoutes > 0, "transport routes must be baked")

-- Tooltip and click handlers.
zone = 1519
hooks.WorldMapFrame_Update[1]()
-- Pick any shown pin in Stormwind rather than assuming index 1: the marker order follows the
-- harvested data, not the old hand-written list.
local shown = nil
for _, pin in ipairs(addon.pins) do
    if pin:IsShown() then shown = pin break end
end
assert(shown, "Stormwind must have at least one shown pin")
shown.scripts.OnEnter(shown)
assert(WorldMapTooltip.text and #WorldMapTooltip.text > 0, "tooltip label must render")
local label = shown.poi.label
shown.scripts.OnClick(shown)
assert(messages[#messages]:find(label, 1, true), "click chat echo must name the marker")

-- Red overlay.
zone = 4197
area = 4197
hooks.WorldMapFrame_Update[1]()
assert(addon.overlay:IsShown(), "red overlay on Wintergrasp")
zone = 0
area = 4384
hooks.WorldMapFrame_Update[1]()
assert(addon.overlay:IsShown(), "red overlay via GetCurrentMapAreaID fallback")
zone = 1519
area = 1519
hooks.WorldMapFrame_Update[1]()
assert(not addon.overlay:IsShown(), "no overlay outside selected zones")

-- Dynamic hooks.
addon:SetWorldBoss(1519, -8829.3, 598.9, "Test boss")
addon:SetCrowsCache(1519, -8800, 600, "Test cache")
zone = 1519
hooks.WorldMapFrame_Update[1]()
assert(addon.dynamicPins.boss:IsShown(), "dynamic boss pin")
assert(addon.dynamicPins.cache:IsShown(), "dynamic cache pin")
addon:ClearDynamicPOI("boss")
assert(not addon.dynamicPins.boss:IsShown(), "cleared boss pin hidden")

-- Outlaw protocol: one dynamic marker, exact in zone, coarse on the continent map.
zone = 1519
area = 1519
continent = 1
inInstance = false
assert(not addon:HandleAddonMessage("SMPOI", fixture.addon, "ZONE", "Server"), "outlaw rejected before AUTH")
assert(not addon:SetOutlaw("Direct", { zone = 1519, mapX = 0.5, mapY = 0.5, ttl = 15 }), "direct API requires a token")
assert(addon:HandleAddonMessage("SMPOI", fixture.auth, "ZONE", "Server"), "AUTH accepted")
assert(addon.outlawToken == fixture.token, "session token stored")
assert(addon:HandleAddonMessage("SMPOI", fixture.addon, "ZONE", "Server"), "outlaw message accepted after AUTH")
local killer = fixture.position.killer
assert(not addon:HandleAddonMessage("SMPOI", fixture.spoof, "ZONE", "Server"), "spoofed token rejected")
assert(addon.outlaws["Mallory"] == nil, "spoofed outlaw ignored")
local outlawPin = addon.outlawPins[killer]
assert(outlawPin and outlawPin:IsShown(), "outlaw exact marker")
local point = outlawPin.points[#outlawPin.points]
assert(math.abs(point[4] - fixture.position.mapX * WorldMapButton:GetWidth()) < 0.01, "outlaw exact X")
assert(math.abs(point[5] + fixture.position.mapY * WorldMapButton:GetHeight()) < 0.01, "outlaw exact Y")

zone = 0
area = 0
continent = 1
hooks.WorldMapFrame_Update[1]()
assert(outlawPin:IsShown(), "outlaw coarse marker on the continent map")
point = outlawPin.points[#outlawPin.points]
assert(math.abs(point[4] - fixture.position.continentX * WorldMapButton:GetWidth()) < 0.01, "outlaw coarse X")
assert(math.abs(point[5] + fixture.position.continentY * WorldMapButton:GetHeight()) < 0.01, "outlaw coarse Y")

zone = 1519
area = 1519
continent = 2
hooks.WorldMapFrame_Update[1]()
assert(not outlawPin:IsShown(), "outlaw hidden on another continent")

continent = 1
inInstance = true
hooks.WorldMapFrame_Update[1]()
assert(not outlawPin:IsShown(), "outlaw hidden in an instance or battleground")

inInstance = false
hooks.WorldMapFrame_Update[1]()
assert(outlawPin:IsShown(), "outlaw visible again after the instance")

local line = addon:FormatOutlawKill(
    fixture.position.killer,
    fixture.position.victim,
    fixture.position.zoneName,
    fixture.position.subzone
)
assert(line == fixture.chat, "kill chat formatting")
local parsedKiller, parsedVictim, parsedZone, parsedSubzone = addon:ParseOutlawKill(fixture.chat)
assert(parsedKiller == fixture.position.killer, "kill parse killer")
assert(parsedVictim == fixture.position.victim, "kill parse victim")
assert(parsedZone == fixture.position.zoneName, "kill parse zone")
assert(parsedSubzone == fixture.position.subzone, "kill parse subzone")
assert(addon:HandleAddonMessage("SMPOI", fixture.kill, "ZONE", "Server"), "kill message accepted")
assert(messages[#messages]:find(fixture.chat, 1, true), "kill chat line")
assert(addon:HandleAddonMessage("SMPOI", fixture.clear, "ZONE", "Server"), "clear message accepted")
assert(addon.outlaws[killer] == nil, "clear removes the outlaw")
assert(not outlawPin:IsShown(), "clear hides the outlaw pin")
assert(#addon.outlawPool >= 1, "cleared outlaw pin returned to the pool")

-- Stale marker: the pin is released, not leaked.
assert(addon:HandleAddonMessage("SMPOI", fixture.addon, "ZONE", "Server"), "outlaw re-added")
local reused = addon.outlawPins[killer]
assert(reused, "outlaw pin reacquired")
now = now + fixture.position.ttl + 1
hooks.WorldMapFrame_Update[1]()
assert(addon.outlaws[killer] == nil, "stale outlaw removed")
assert(not reused:IsShown(), "stale outlaw pin hidden")
assert(#addon.outlawPool >= 1, "stale pin returned to the pool")

-- Close the map; all work stops.
shown = false
hooks.WorldMapFrame_OnHide[1]()
for _, pin in ipairs(addon.pins) do
    assert(not pin:IsShown(), "pins hidden when the map closes")
end
assert(not addon.overlay:IsShown(), "overlay hidden when the map closes")

print("ok: " .. #ns.POIs .. " static POIs, " .. created .. " frames created, no OnUpdate")
