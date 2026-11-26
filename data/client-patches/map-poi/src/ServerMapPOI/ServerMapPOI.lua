-- Server Map POI: static world-map layer plus the Outlaw dynamic marker.
--
-- Design rules (decisions/ADR-032):
--   * Draw only while the world map is open; refresh on map update, never per frame.
--   * One reused button per POI; icon textures are set once and cached by kind.
--   * Positions are normalized zone-map coordinates baked from WorldMapArea.dbc
--     (rotated client convention: screen X follows world Y, screen Y follows world X).
--   * Stock client icons, plus Questie's MIT meeting-stone BLP; no other custom art.
--   * Dynamic hooks exist for world bosses, Crow's Cache and Outlaw positions; no server tick work.
--
-- Outlaw wire protocol (client side only; the PvP module is not implemented):
--   CHAT_MSG_ADDON prefix SMPOI, tab-separated, version 2.
--   AUTH:   2 AUTH token
--   OUTLAW: 2 OUTLAW token killer victim continent zone zoneName subzone mapX mapY continentX continentY ttl
--   CLEAR:  2 CLEAR token killer
--   KILL:   2 KILL token killer victim zone subzone
--   The server sends AUTH once per session, then at most one position per outlaw every 5 seconds,
--   to same-zone players with exact map coordinates or same-continent players with coarse
--   continent coordinates. Messages without the current token are ignored.
--   v1 limitation: no PvP module issues AUTH yet, so Outlaw markers stay off. The token stops
--   casual spoofing, not a modified client or addon; the server must still validate every kill.

local ADDON, ns = ...

local Frame = CreateFrame("Frame")
ns.Frame = Frame
_G.ServerMapPOI = Frame

-- Questie-style pins: the stock tracking icons are the same small glyphs Questie draws. Meeting
-- stones use Questie's MIT-licensed mstone.blp (credited in the README); every other texture is
-- stock. Faction tinting is SetVertexColor on the one texture per kind.
local ICONS = {
    flightmaster  = "Interface\\Minimap\\Tracking\\FlightMaster",
    innkeeper     = "Interface\\Minimap\\Tracking\\Innkeeper",
    battlemaster  = "Interface\\Minimap\\Tracking\\Battlemaster",
    meetingstone  = "Interface\\AddOns\\ServerMapPOI\\mstone",
    portal        = "Interface\\Icons\\Spell_Arcane_PortalStormwind",
    transport     = "Interface\\Icons\\Ability_Mount_Wyvern_01",
    warpweaver    = "Interface\\Icons\\INV_Misc_Map_01",
    vendor        = "Interface\\Icons\\INV_Misc_Coin_01",
    boss          = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    cache         = "Interface\\Icons\\INV_Misc_Bag_10",
    outlaw        = "Interface\\Icons\\INV_Misc_Bandana_03",
    callboard     = "Interface\\Icons\\INV_Scroll_03",
}

-- Faction colours: alliance blue, horde red, shared/neutral gold.
local FACTION_COLOURS = {
    alliance = { 0.25, 0.55, 1.00 },
    horde    = { 1.00, 0.25, 0.25 },
    neutral  = { 1.00, 0.82, 0.20 },
}

local function factionColour(poi)
    local c = FACTION_COLOURS[poi.faction or "neutral"] or FACTION_COLOURS.neutral
    return c[1], c[2], c[3]
end

local RED_OVERLAY = "Interface\\Buttons\\WHITE8X8"
local DYNAMIC_LABELS = { boss = "World boss", cache = "Crow's Cache", outlaw = "Outlaw", callboard = "Call board" }

local OUTLAW_PREFIX = "SMPOI"
local OUTLAW_PROTOCOL = 2
local OUTLAW_UPDATE_SECONDS = 5
local OUTLAW_TTL_SECONDS = 15
local OUTLAW_KILL_FORMAT = "[OUTLAW] %s killed %s in %s (%s)."

ns.Outlaw = {
    prefix = OUTLAW_PREFIX,
    protocol = OUTLAW_PROTOCOL,
    authAction = "AUTH",
    tokenRequired = true,
    updateSeconds = OUTLAW_UPDATE_SECONDS,
    ttlSeconds = OUTLAW_TTL_SECONDS,
    killFormat = OUTLAW_KILL_FORMAT,
}

Frame.pins = {}
Frame.dynamic = {}
Frame.outlaws = {}
Frame.outlawPins = {}
Frame.outlawPool = {}
Frame.poiCount = 0

local function Tooltip()
    return WorldMapTooltip or GameTooltip
end

local function CreatePin(poi)
    local pin = CreateFrame("Button", nil, WorldMapButton)
    pin:SetWidth(20)
    pin:SetHeight(20)
    pin:SetFrameLevel(WorldMapButton:GetFrameLevel() + 2)
    pin:RegisterForClicks("LeftButtonUp")

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(12)
    icon:SetHeight(12)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture(ICONS[poi.kind] or ICONS.vendor)
    icon:SetVertexColor(factionColour(poi))
    pin.icon = icon
    pin.poi = poi

    pin:SetScript("OnEnter", function(self)
        local tip = Tooltip()
        if not tip then
            return
        end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:SetText(self.poi.label or DYNAMIC_LABELS[self.poi.kind] or "Point of interest", 1, 1, 1)
        if self.poi.note then
            tip:AddLine(self.poi.note, 0.8, 0.8, 0.8)
        end
        tip:Show()
    end)
    pin:SetScript("OnLeave", function()
        local tip = Tooltip()
        if tip then
            tip:Hide()
        end
    end)
    pin:SetScript("OnClick", function(self)
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff33ff99ServerMapPOI|r " .. (self.poi.label or "point of interest")
            )
        end
    end)
    return pin
end

-- Several markers can share one world position: every battleground emissary in a city stands in
-- the same spot, and 131 pins sit on only 22 distinct coordinates (worst case six on one point).
-- Drawing them all at the exact centre leaves only the topmost hoverable. Fan them out on a small
-- deterministic ring instead: the same pin always keeps the same offset, so nothing jitters
-- between refreshes.
local STACK_RADIUS = 14
local STACK_GOLDEN = 2.399963229728653  -- golden angle in radians

local function stackOffset(index)
    if index <= 1 then
        return 0, 0
    end
    -- Slot 1 is the centre; the next six share the first ring, then the next six a wider one.
    -- A zero radius here would pile every slot onto the centre, which is the bug this replaces.
    local radius = STACK_RADIUS * math.ceil((index - 1) / 6)
    local angle = STACK_GOLDEN * (index - 1)
    return math.cos(angle) * radius, math.sin(angle) * radius
end

local function SetPinPosition(pin, x, y, slot)
    local offset_x, offset_y = stackOffset(slot or 1)
    pin:SetPoint(
        "CENTER",
        WorldMapButton,
        "TOPLEFT",
        x * WorldMapButton:GetWidth() + offset_x,
        -y * WorldMapButton:GetHeight() + offset_y
    )
    return true
end

local function ZoneMapPosition(zone, worldX, worldY)
    local bounds = ns.ZoneBounds[zone]
    if not bounds or not worldX or not worldY then
        return nil
    end
    -- 3.3.5 zone maps are rotated: map X is world Y, map Y is world X.
    return (bounds.yMax - worldY) / (bounds.yMax - bounds.yMin),
        (bounds.xMax - worldX) / (bounds.xMax - bounds.xMin)
end

local function PositionPin(pin, slot)
    local poi = pin.poi
    local x, y = poi.mapX, poi.mapY
    if not x or not y then
        x, y = ZoneMapPosition(poi.zone, poi.worldX, poi.worldY)
        if not x then
            return nil
        end
        poi.mapX, poi.mapY = x, y
    end
    return SetPinPosition(pin, x, y, slot)
end

function Frame:GetPins()
    local pins = {}
    for index = 1, #ns.POIs do
        local poi = ns.POIs[index]
        self.pins[index] = self.pins[index] or CreatePin(poi)
        self.pins[index].poi = poi
        pins[#pins + 1] = self.pins[index]
    end
    for kind, poi in pairs(self.dynamic) do
        local pin = self.dynamicPins and self.dynamicPins[kind]
        if not pin then
            pin = CreatePin(poi)
            self.dynamicPins = self.dynamicPins or {}
            self.dynamicPins[kind] = pin
        end
        pin.poi = poi
        pin.icon:SetTexture(ICONS[poi.kind] or ICONS.vendor)
        pin.icon:SetVertexColor(factionColour(poi))
        pins[#pins + 1] = pin
    end
    return pins
end

function Frame:HideAll()
    for index = 1, #self.pins do
        self.pins[index]:Hide()
    end
    if self.dynamicPins then
        for _, pin in pairs(self.dynamicPins) do
            pin:Hide()
        end
    end
    for _, pin in pairs(self.outlawPins) do
        pin:Hide()
    end
    if self.overlay then
        self.overlay:Hide()
    end
end

function Frame:AcquireOutlawPin(data)
    local pin = self.outlawPool[#self.outlawPool]
    if pin then
        table.remove(self.outlawPool)
    else
        pin = CreatePin(data)
    end
    pin.poi = data
    return pin
end

function Frame:ReleaseOutlawPin(id)
    local pin = self.outlawPins[id]
    if not pin then
        return
    end
    pin:Hide()
    pin.poi = nil
    self.outlawPins[id] = nil
    self.outlawPool[#self.outlawPool + 1] = pin
end

function Frame:RefreshOutlaws(area, continent, inInstance, mapZone)
    local now = GetTime()
    for id, data in pairs(self.outlaws) do
        local pin = self.outlawPins[id]
        if not pin then
            pin = self:AcquireOutlawPin(data)
            self.outlawPins[id] = pin
        end
        pin.poi = data

        local ttl = data.ttl or OUTLAW_TTL_SECONDS
        local stale = data.updated and (now - data.updated) > ttl
        local mode = nil
        if not stale
            and not inInstance
            and data.continent
            and continent
            and data.continent == continent
        then
            if mapZone and mapZone > 0 and data.zone == area then
                mode = "zone"
            elseif (not mapZone or mapZone <= 0) and data.continentX and data.continentY then
                mode = "continent"
            end
        end

        local x, y
        if mode == "zone" then
            x, y = data.mapX, data.mapY
            if not x or not y then
                x, y = ZoneMapPosition(data.zone, data.worldX, data.worldY)
                data.mapX, data.mapY = x, y
            end
        elseif mode == "continent" then
            x, y = data.continentX, data.continentY
        end

        if x and y then
            SetPinPosition(pin, x, y)
            pin:Show()
        else
            pin:Hide()
        end
        if stale then
            self.outlaws[id] = nil
            self:ReleaseOutlawPin(id)
        end
    end
end

function Frame:Refresh()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        self:HideAll()
        return
    end
    -- GetCurrentMapZone returns the zone index, not an area id. It is 0 on a continent map, so a
    -- zone-relative pin must never draw there: that is the "markers in the ocean" bug.
    local mapZone = GetCurrentMapZone and GetCurrentMapZone() or 0
    local area = GetCurrentMapAreaID and GetCurrentMapAreaID() or 0
    local continent = GetCurrentMapContinent and GetCurrentMapContinent() or nil
    local inInstance = IsInInstance and IsInInstance() or false
    local dungeonLevel = GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or 0
    local onZoneMap = mapZone and mapZone > 0 and area and area > 0
    local pins = self:GetPins()

    -- Visibility first, then stack slots. Only pins that actually share a coordinate are spread:
    -- every emissary in a city stands on one spot, and a blanket offset would scatter the rest of
    -- the map for no reason.
    local shown = {}
    for index = 1, #pins do
        local pin = pins[index]
        local poi = pin.poi
        local visible = onZoneMap and poi.zone == area
        if visible and poi.dungeonOnly and dungeonLevel <= 0 then
            visible = false
        end
        if visible then
            shown[#shown + 1] = pin
        else
            pin:Hide()
        end
    end

    local slots = {}
    for index = 1, #shown do
        local poi = shown[index].poi
        local key = string.format("%d:%d", math.floor((poi.mapX or 0) * 4096),
            math.floor((poi.mapY or 0) * 4096))
        slots[key] = (slots[key] or 0) + 1
        shown[index].stackSlot = slots[key]
    end

    for index = 1, #shown do
        local pin = shown[index]
        if PositionPin(pin, pin.stackSlot) then
            pin:Show()
        else
            pin:Hide()
        end
    end

    self:RefreshOutlaws(area, continent, inInstance, mapZone)

    if onZoneMap and ns.RedZones and ns.RedZones[area] then
        if not self.overlay then
            self.overlay = WorldMapButton:CreateTexture(nil, "OVERLAY")
            self.overlay:SetTexture(RED_OVERLAY)
            self.overlay:SetVertexColor(0.75, 0.05, 0.05, 0.22)
            self.overlay:SetAllPoints(WorldMapButton)
        end
        self.overlay:Show()
    elseif self.overlay then
        self.overlay:Hide()
    end
end

function Frame:SetDynamicPOI(kind, poi)
    if not poi then
        self.dynamic[kind] = nil
        if self.dynamicPins and self.dynamicPins[kind] then
            self.dynamicPins[kind]:Hide()
        end
        return
    end
    poi.kind = kind
    poi.label = poi.label or DYNAMIC_LABELS[kind]
    self.dynamic[kind] = poi
    self:Refresh()
end

function Frame:ClearDynamicPOI(kind)
    self:SetDynamicPOI(kind, nil)
end

-- Future server-driven or baked updates: call with zone, world coordinates and a label.
function Frame:SetWorldBoss(zone, worldX, worldY, label)
    self:SetDynamicPOI("boss", {
        zone = zone,
        worldX = worldX,
        worldY = worldY,
        label = label or DYNAMIC_LABELS.boss,
    })
end

function Frame:SetCrowsCache(zone, worldX, worldY, label)
    self:SetDynamicPOI("cache", {
        zone = zone,
        worldX = worldX,
        worldY = worldY,
        label = label or DYNAMIC_LABELS.cache,
    })
end

-- Map coordinates are accepted for zones without WorldMapArea bounds (Dalaran micro-map).
function Frame:SetDynamicMapPOI(kind, zone, mapX, mapY, label)
    self:SetDynamicPOI(kind, {
        zone = zone,
        mapX = mapX,
        mapY = mapY,
        label = label or DYNAMIC_LABELS[kind],
    })
end

function Frame:SetOutlaw(id, data)
    if not id or id == "" or not data then
        return false
    end
    if not self.outlawToken or data.token ~= self.outlawToken then
        return false
    end
    local zoneName = data.zoneName
        or (ns.ZoneBounds[data.zone] and ns.ZoneBounds[data.zone].name)
        or ("zone " .. tostring(data.zone))
    data.kind = "outlaw"
    data.killer = id
    data.zoneName = zoneName
    data.label = data.label or ("Outlaw: " .. id)
    data.note = data.note
        or string.format(
            "Killed %s in %s (%s)",
            data.victim or "?",
            zoneName,
            data.subzone or "?"
        )
    data.updated = GetTime()
    data.ttl = data.ttl or OUTLAW_TTL_SECONDS
    self.outlaws[id] = data
    self:Refresh()
    return true
end

function Frame:ClearOutlaw(id)
    if not id or not self.outlaws[id] then
        return false
    end
    self.outlaws[id] = nil
    self:ReleaseOutlawPin(id)
    return true
end

function Frame:ClearOutlaws()
    for id in pairs(self.outlaws) do
        self:ClearOutlaw(id)
    end
end

function Frame:GetOutlaw(id)
    return self.outlaws[id]
end

function Frame:FormatOutlawKill(killer, victim, zone, subzone)
    return string.format(
        OUTLAW_KILL_FORMAT,
        killer or "?",
        victim or "?",
        zone or "?",
        subzone or "?"
    )
end

function Frame:ParseOutlawKill(text)
    if type(text) ~= "string" then
        return nil
    end
    local killer, victim, zoneName, subzone = text:match(
        "^%[OUTLAW%] (%S+) killed (%S+) in (.+) %((.-)%)%.$"
    )
    return killer, victim, zoneName, subzone
end

function Frame:AnnounceOutlawKill(killer, victim, zone, subzone)
    local line = self:FormatOutlawKill(killer, victim, zone, subzone)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff3333" .. line .. "|r")
    end
    return line
end

function Frame:HandleAddonMessage(prefix, message, channel, sender)
    if prefix ~= OUTLAW_PREFIX or type(message) ~= "string" then
        return false
    end
    local fields = {}
    for field in (message .. "\t"):gmatch("(.-)\t") do
        fields[#fields + 1] = field
    end
    if fields[1] ~= tostring(OUTLAW_PROTOCOL) then
        return false
    end
    local action = fields[2]
    local token = fields[3]
    if action == "AUTH" then
        if not token or #token < 8 or #token > 128 then
            return false
        end
        if self.outlawToken and self.outlawToken ~= token then
            self:ClearOutlaws()
        end
        self.outlawToken = token
        return true
    end
    if not self.outlawToken or token ~= self.outlawToken then
        return false
    end
    if action == "OUTLAW" then
        local data = {
            token = token,
            killer = fields[4],
            victim = fields[5],
            continent = tonumber(fields[6]),
            zone = tonumber(fields[7]),
            zoneName = fields[8],
            subzone = fields[9],
            mapX = tonumber(fields[10]),
            mapY = tonumber(fields[11]),
            continentX = tonumber(fields[12]),
            continentY = tonumber(fields[13]),
            ttl = tonumber(fields[14]),
        }
        if not data.killer or data.killer == "" or not data.zone then
            return false
        end
        return self:SetOutlaw(data.killer, data)
    elseif action == "CLEAR" then
        return self:ClearOutlaw(fields[4])
    elseif action == "KILL" then
        self:AnnounceOutlawKill(fields[4], fields[5], fields[6], fields[7])
        return true
    end
    return false
end

local function Hook(name, handler)
    if type(_G[name]) == "function" then
        hooksecurefunc(name, handler)
    end
end

Hook("WorldMapFrame_Update", function()
    Frame:Refresh()
end)
Hook("WorldMapFrame_OnShow", function()
    Frame:Refresh()
end)
Hook("WorldMapFrame_OnHide", function()
    Frame:HideAll()
end)

if RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(OUTLAW_PREFIX)
end

Frame:RegisterEvent("PLAYER_LOGIN")
Frame:RegisterEvent("CHAT_MSG_ADDON")
Frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff33ff99ServerMapPOI|r loaded from patch-Z.MPQ ("
                    .. tostring(#ns.POIs)
                    .. " static markers, Outlaw protocol v2 token required)."
            )
        end
        self:Refresh()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        self:HandleAddonMessage(prefix, message, channel, sender)
    end
end)
