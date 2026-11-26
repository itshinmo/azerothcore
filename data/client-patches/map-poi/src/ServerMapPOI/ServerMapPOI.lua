-- Server Map POI: static world-map layer plus the Outlaw dynamic marker.
--
-- Design rules (decisions/ADR-032):
--   * Draw only while the world map is open; refresh on map update, never per frame.
--   * One reused button per POI; icon textures are set once and cached by kind.
--   * Positions are normalized zone-map coordinates baked from WorldMapArea.dbc
--     (rotated client convention: screen X follows world Y, screen Y follows world X).
--   * Stock client icons only; no custom BLP.
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

-- Stock client icons only; no custom BLP. Faction tinting is done with SetVertexColor on the one
-- texture per kind, so alliance and horde share a texture and differ by colour.
local ICONS = {
    flightmaster  = "Interface\\Icons\\Ability_Mount_Gryphon_01",
    innkeeper     = "Interface\\Icons\\INV_Misc_Food_15",
    battlemaster  = "Interface\\Icons\\Ability_Warrior_BattleShout",
    meetingstone  = "Interface\\Icons\\INV_Misc_StoneTablet_01",
    portal        = "Interface\\Icons\\Spell_Arcane_PortalStormwind",
    transport     = "Interface\\Icons\\Ability_Mount_Wyvern_01",
    warpweaver    = "Interface\\Icons\\INV_Misc_Map_01",
    vendor        = "Interface\\Icons\\INV_Misc_Coin_01",
    boss          = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    cache         = "Interface\\Icons\\INV_Misc_Bag_10",
    outlaw        = "Interface\\Icons\\INV_Misc_Bandana_03",
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
local DYNAMIC_LABELS = { boss = "World boss", cache = "Crow's Cache", outlaw = "Outlaw" }

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
    pin:SetWidth(24)
    pin:SetHeight(24)
    pin:SetFrameLevel(WorldMapButton:GetFrameLevel() + 2)
    pin:RegisterForClicks("LeftButtonUp")

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(18)
    icon:SetHeight(18)
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

local function SetPinPosition(pin, x, y)
    pin:SetPoint(
        "CENTER",
        WorldMapButton,
        "TOPLEFT",
        x * WorldMapButton:GetWidth(),
        -y * WorldMapButton:GetHeight()
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

local function PositionPin(pin)
    local poi = pin.poi
    local x, y = poi.mapX, poi.mapY
    if not x or not y then
        x, y = ZoneMapPosition(poi.zone, poi.worldX, poi.worldY)
        if not x then
            return nil
        end
        poi.mapX, poi.mapY = x, y
    end
    return SetPinPosition(pin, x, y)
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

function Frame:RefreshOutlaws(zone, area, continent, inInstance)
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
            if data.zone == zone or data.zone == area then
                mode = "zone"
            elseif (zone == 0 or zone == -1) and data.continentX and data.continentY then
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
    local zone = GetCurrentMapZone()
    local area = GetCurrentMapAreaID and GetCurrentMapAreaID() or zone
    local continent = GetCurrentMapContinent and GetCurrentMapContinent() or nil
    local inInstance = IsInInstance and IsInInstance() or false
    local dungeonLevel = GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or 0
    local pins = self:GetPins()
    for index = 1, #pins do
        local pin = pins[index]
        local poi = pin.poi
        local visible = poi.zone == zone or poi.zone == area
        if visible and poi.dungeonOnly and dungeonLevel <= 0 then
            visible = false
        end
        if visible and PositionPin(pin) then
            pin:Show()
        else
            pin:Hide()
        end
    end

    self:RefreshOutlaws(zone, area, continent, inInstance)

    if ns.RedZones and (ns.RedZones[zone] or ns.RedZones[area]) then
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
