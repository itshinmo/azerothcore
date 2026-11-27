-- WorldMapPins: world bosses and custom services on the world map.
--
-- Only content this project adds (Warpweaver, Call Board) plus the seven outdoor world bosses
-- are drawn. Stock NPC categories (flight masters, innkeepers, battlemasters, portals, meeting
-- stones) are deliberately absent; addons such as Questie cover those.
--
-- Positions: acore_world.creature for the bosses, collections_npc_spawns.sql for the
-- Warpweavers, call_boards.sql for the Call Boards. mx/my are zone-map fractions and cx/cy
-- continent fractions. 3.3.5 zone maps rotate the axes:
--   mx = (yMax - worldY) / (yMax - yMin), my = (xMax - worldX) / (xMax - xMin)
-- Silvermoon and the Exodar live on map 530 but display on the Eastern Kingdoms and Kalimdor
-- maps, so their continent fractions first apply the additive offset from
-- WorldMapTransforms.dbc (map 530 -> region 0: -2400, +2400; map 530 -> region 1:
-- +10133.333, +17600) and then project. Skipping the offset put both cities in the ocean.
-- Recompute by hand if a spawn moves; this file is static on purpose.

local ADDON, ns = ...

local Frame = CreateFrame("Frame")
Frame.pins = {}

local ICONS = {
    boss = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    warpweaver = "Interface\\Icons\\INV_NetherPortal",
    callboard = "Interface\\GossipFrame\\AvailableQuestIcon",
}

-- Zone id -> world-map name. Only zones that hold a pin are listed.
ns.Zones = {
    [10] = "Duskwood",
    [16] = "Azshara",
    [17] = "The Barrens",
    [33] = "Stranglethorn Vale",
    [47] = "The Hinterlands",
    [331] = "Ashenvale",
    [357] = "Feralas",
    [440] = "Tanaris",
    [618] = "Winterspring",
    [1497] = "Undercity",
    [1519] = "Stormwind City",
    [1537] = "Ironforge",
    [1637] = "Orgrimmar",
    [1638] = "Thunder Bluff",
    [1657] = "Darnassus",
    [3483] = "Hellfire Peninsula",
    [3487] = "Silvermoon City",
    [3520] = "Shadowmoon Valley",
    [3523] = "Netherstorm",
    [3557] = "The Exodar",
    [3703] = "Shattrath City",
    [4395] = "Dalaran",
}

ns.Pins = {
    { kind = "boss", zone = 16, place = "Azshara", label = "Azuregos",
      note = "Classic world boss", x = 2622.2, y = -5977.9,
      mx = 0.5326, my = 0.8043, cont = 1, cx = 0.6262, cy = 0.4149 },
    { kind = "boss", zone = 47, place = "The Hinterlands", label = "Lethon",
      note = "Classic world boss", x = 753.6, y = -4012.0,
      mx = 0.6330, my = 0.2778, cont = 2, cx = 0.5445, cy = 0.3839 },
    { kind = "boss", zone = 10, place = "Duskwood", label = "Taerar",
      note = "Classic world boss", x = -10428.8, y = -392.2,
      mx = 0.4539, my = 0.3956, cont = 2, cx = 0.4557, cy = 0.7958 },
    { kind = "boss", zone = 357, place = "Feralas", label = "Emeriss",
      note = "Classic world boss", x = -2872.7, y = 1884.2,
      mx = 0.5119, my = 0.1092, cont = 1, cx = 0.4126, cy = 0.6388 },
    { kind = "boss", zone = 331, place = "Ashenvale", label = "Ysondre",
      note = "Classic world boss", x = 3301.1, y = -3732.6,
      mx = 0.9421, my = 0.3569, cont = 1, cx = 0.5652, cy = 0.3872 },
    { kind = "boss", zone = 3483, place = "Hellfire Peninsula", label = "Doom Lord Kazzak",
      note = "The Burning Crusade world boss", x = 943.5, y = 2269.8,
      mx = 0.6331, my = 0.1562, cont = 3, cx = 0.6142, cy = 0.4190 },
    { kind = "boss", zone = 3520, place = "Shadowmoon Valley", label = "Doomwalker",
      note = "The Burning Crusade world boss", x = -3563.3, y = 233.9,
      mx = 0.7257, my = 0.4406, cont = 3, cx = 0.7308, cy = 0.8061 },
    { kind = "warpweaver", zone = 1519, place = "Stormwind City", label = "Warpweaver",
      note = "Transmogrifier", x = -8829.3, y = 598.9,
      mx = 0.6469, my = 0.7195, cont = 2, cx = 0.4313, cy = 0.7369 },
    { kind = "warpweaver", zone = 1537, place = "Ironforge", label = "Warpweaver",
      note = "Transmogrifier", x = -4959.6, y = -1021.3,
      mx = 0.3892, my = 0.7399, cont = 2, cx = 0.4711, cy = 0.5943 },
    { kind = "warpweaver", zone = 1657, place = "Darnassus", label = "Warpweaver",
      note = "Transmogrifier", x = 9926.8, y = 2319.0,
      mx = 0.5852, my = 0.4414, cont = 1, cx = 0.4008, cy = 0.1171 },
    { kind = "warpweaver", zone = 3557, place = "The Exodar", label = "Warpweaver",
      note = "Transmogrifier", x = -3931.7, y = -11625.6,
      mx = 0.5292, my = 0.4570, cont = 1, cx = 0.3014, cy = 0.2690 },
    { kind = "warpweaver", zone = 1637, place = "Orgrimmar", label = "Warpweaver",
      note = "Transmogrifier", x = 1894.1, y = -4324.3,
      mx = 0.4589, my = 0.4060, cont = 1, cx = 0.5813, cy = 0.4445 },
    { kind = "warpweaver", zone = 1497, place = "Undercity", label = "Warpweaver",
      note = "Transmogrifier", x = 1581.6, y = 190.5,
      mx = 0.7116, my = 0.4630, cont = 2, cx = 0.4414, cy = 0.3534 },
    { kind = "warpweaver", zone = 1638, place = "Thunder Bluff", label = "Warpweaver",
      note = "Transmogrifier", x = -1244.6, y = -60.6,
      mx = 0.5531, my = 0.5671, cont = 1, cx = 0.4654, cy = 0.5725 },
    { kind = "warpweaver", zone = 3487, place = "Silvermoon City", label = "Warpweaver",
      note = "Transmogrifier", x = 9870.2, y = -7442.9,
      mx = 0.8602, my = 0.3514, cont = 2, cx = 0.5698, cy = 0.1365 },
    { kind = "warpweaver", zone = 3703, place = "Shattrath City", label = "Warpweaver",
      note = "Transmogrifier", x = -2006.6, y = 5371.1,
      mx = 0.5850, my = 0.6117, cont = 3, cx = 0.4366, cy = 0.6723 },
    { kind = "warpweaver", zone = 4395, place = "Dalaran", label = "Warpweaver",
      note = "Transmogrifier", x = 5842.8, y = 721.8,
      mx = 0.3984, my = 0.4046, cont = 4, cx = 0.4786, cy = 0.4014 },
    { kind = "callboard", zone = 1519, place = "Stormwind City", label = "Call Board",
      note = "Custom quest board", x = -8863.883407, y = 669.521069,
      mx = 0.6063, my = 0.7494, cont = 2, cx = 0.4296, cy = 0.7381 },
    { kind = "callboard", zone = 1537, place = "Ironforge", label = "Call Board",
      note = "Custom quest board", x = -4839.80944, y = -862.526259,
      mx = 0.1884, my = 0.5128, cont = 2, cx = 0.4672, cy = 0.5899 },
    { kind = "callboard", zone = 1657, place = "Darnassus", label = "Call Board",
      note = "Custom quest board", x = 10125.787802, y = 2230.085151,
      mx = 0.6692, my = 0.1595, cont = 1, cx = 0.4032, cy = 0.1090 },
    { kind = "callboard", zone = 3557, place = "The Exodar", label = "Call Board",
      note = "Custom quest board", x = -3751.869951, y = -11696.12314,
      mx = 0.5959, my = 0.2018, cont = 1, cx = 0.3033, cy = 0.2616 },
    { kind = "callboard", zone = 1637, place = "Orgrimmar", label = "Call Board",
      note = "Custom quest board", x = 1629.452468, y = -4435.918796,
      mx = 0.5385, my = 0.6889, cont = 1, cx = 0.5843, cy = 0.4553 },
    { kind = "callboard", zone = 1497, place = "Undercity", label = "Call Board",
      note = "Custom quest board", x = 1629.701764, y = 223.504511,
      mx = 0.6772, my = 0.3878, cont = 2, cx = 0.4405, cy = 0.3516 },
    { kind = "callboard", zone = 1638, place = "Thunder Bluff", label = "Call Board",
      note = "Custom quest board", x = -1294.820848, y = 40.128255,
      mx = 0.4566, my = 0.6393, cont = 1, cx = 0.4627, cy = 0.5745 },
    { kind = "callboard", zone = 3487, place = "Silvermoon City", label = "Call Board",
      note = "Custom quest board", x = 9569.86665, y = -7226.669362,
      mx = 0.6818, my = 0.7237, cont = 2, cx = 0.5645, cy = 0.1476 },
    { kind = "callboard", zone = 3703, place = "Shattrath City", label = "Call Board",
      note = "Custom quest board", x = -2180.831174, y = 5404.332052,
      mx = 0.5596, my = 0.8117, cont = 3, cx = 0.4347, cy = 0.6873 },
    { kind = "callboard", zone = 4395, place = "Dalaran", label = "Call Board",
      note = "Custom quest board", x = 5850.769034, y = 637.283083,
      mx = 0.5003, my = 0.3902, cont = 4, cx = 0.4833, cy = 0.4008 },
    { kind = "callboard", zone = 33, place = "Booty Bay", label = "Call Board",
      note = "Custom quest board", x = -14460.26525, y = 490.256881,
      mx = 0.2712, my = 0.7737, cont = 2, cx = 0.4340, cy = 0.9443 },
    { kind = "callboard", zone = 440, place = "Gadgetzan", label = "Call Board",
      note = "Custom quest board", x = -7162.411254, y = -3837.072506,
      mx = 0.5244, my = 0.2799, cont = 1, cx = 0.5680, cy = 0.8137 },
    { kind = "callboard", zone = 618, place = "Everlook", label = "Call Board",
      note = "Custom quest board", x = 6699.864284, y = -4670.207065,
      mx = 0.6132, my = 0.3874, cont = 1, cx = 0.5907, cy = 0.2486 },
    { kind = "callboard", zone = 3523, place = "Area 52", label = "Call Board",
      note = "Custom quest board", x = 3064.123887, y = 3696.471751,
      mx = 0.3205, my = 0.6436, cont = 3, cx = 0.5325, cy = 0.2368 },
    { kind = "callboard", zone = 17, place = "Ratchet", label = "Call Board",
      note = "Custom quest board", x = -1044.339607, y = -3664.874299,
      mx = 0.6205, my = 0.3932, cont = 1, cx = 0.5634, cy = 0.5643 },
}

local ZONE_BY_NAME = {}
local function Normalize(name)
    name = string.lower(name or "")
    name = name:gsub("^the%s+", "")
    name = name:gsub("%s+city$", "")
    return name
end
for zone, name in pairs(ns.Zones) do
    ZONE_BY_NAME[Normalize(name)] = zone
end

-- The map tooltip, not GameTooltip. WorldMapTooltip is a GameTooltip at TOOLTIP strata
-- parented to WorldMapFrame; the client uses it for every other map hover (units, quest
-- POIs, the buttons), so it is the one that renders above the map texture.
local function Tooltip()
    return WorldMapTooltip or GameTooltip
end

-- Pins are children of WorldMapFrame at its frame level + 7, with the frame's strata
-- copied. That is exactly what Questie does in this client (HandyNotes uses +6) and it is
-- the only map-pin arrangement proven to receive hover and click. The previous build was a
-- child of WorldMapButton at WORLDMAP_POI_FRAMELEVEL + 50: it drew, but no mouse event
-- ever reached it.
local function PlaceLevel(button)
    if WorldMapFrame then
        button:SetFrameStrata(WorldMapFrame:GetFrameStrata())
        button:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 7)
    end
end

local function CreatePin(pin)
    local button = CreateFrame("Button", nil, WorldMapFrame)
    button:SetWidth(24)
    button:SetHeight(24)
    PlaceLevel(button)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(14)
    icon:SetHeight(14)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICONS[pin.kind])
    button.icon = icon
    button.pin = pin

    button:SetScript("OnEnter", function(self)
        local tip = Tooltip()
        if not tip then
            return
        end
        -- Stop WorldMapBlobFrame_OnUpdate from swapping the tooltip back to the quest blob
        -- under the cursor while the pin is hovered.
        if WorldMapPOIFrame then
            WorldMapPOIFrame.allowBlobTooltip = false
        end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        -- The city is the title, not a lower line: a capital's Warpweaver and Call Board sit 1 to
        -- 7 pixels apart on the continent map, so only the top pin of a pair can be hovered and
        -- its title has to say which city it is.
        if self.pin.kind == "boss" then
            tip:SetText(self.pin.label)
            tip:AddLine(self.pin.note .. " - " .. self.pin.place, 0.8, 0.8, 0.8)
        else
            tip:SetText(self.pin.place)
            tip:AddLine(self.pin.label .. " - " .. self.pin.note, 0.8, 0.8, 0.8)
        end
        tip:Show()
    end)
    button:SetScript("OnLeave", function()
        local tip = Tooltip()
        if tip then
            tip:Hide()
        end
        if WorldMapPOIFrame then
            WorldMapPOIFrame.allowBlobTooltip = true
        end
    end)
    button:SetScript("OnClick", function(self, mouseButton)
        local tip = Tooltip()
        if tip then
            tip:Hide()
        end
        -- Keep the stock map click (ping) working through the pin.
        if WorldMapButton_OnClick then
            WorldMapButton_OnClick(WorldMapButton, mouseButton)
        end
    end)
    return button
end

local function HideAll()
    for _, button in ipairs(Frame.pins) do
        button:Hide()
    end
    local tip = Tooltip()
    if tip then
        tip:Hide()
    end
    -- Closing the map or switching zone while hovered skips OnLeave, so restore the quest
    -- blob tooltip here or it stays switched off.
    if WorldMapPOIFrame then
        WorldMapPOIFrame.allowBlobTooltip = true
    end
end

local function DisplayedZone(continent, index)
    if not continent or continent < 1 or continent > 4 or not index or index == 0
        or not GetMapZones then
        return nil
    end
    local name = select(index, GetMapZones(continent))
    if not name then
        return nil
    end
    return ZONE_BY_NAME[Normalize(name)]
end

local function Refresh()
    if not WorldMapButton or not WorldMapFrame then
        return
    end
    if not WorldMapFrame:IsShown() then
        HideAll()
        return
    end
    local continent = GetCurrentMapContinent and GetCurrentMapContinent()
    local index = GetCurrentMapZone and GetCurrentMapZone()
    local zone = DisplayedZone(continent, index)
    local onContinent = index == 0 and continent ~= nil and continent >= 1 and continent <= 4
    -- The pins are children of WorldMapFrame, which is not scaled. WorldMapButton is scaled
    -- to the current map size, so the offsets must use its displayed size, not its raw size.
    local scale = WorldMapButton:GetScale() or 1
    local width = WorldMapButton:GetWidth() * scale
    local height = WorldMapButton:GetHeight() * scale

    for i, pin in ipairs(ns.Pins) do
        local button = Frame.pins[i]
        if not button then
            button = CreatePin(pin)
            Frame.pins[i] = button
        end
        local x, y
        if zone and pin.zone == zone then
            x, y = pin.mx, pin.my
        elseif onContinent and pin.cont == continent then
            x, y = pin.cx, pin.cy
        end
        if x then
            PlaceLevel(button)
            button:ClearAllPoints()
            button:SetPoint("CENTER", WorldMapButton, "TOPLEFT", x * width, -y * height)
            button:Show()
        else
            button:Hide()
        end
    end
end

local function Hook(name, handler)
    if type(_G[name]) == "function" then
        hooksecurefunc(name, handler)
    end
end

Hook("WorldMapFrame_Update", Refresh)
Hook("WorldMapFrame_OnShow", Refresh)
Hook("WorldMapFrame_OnHide", HideAll)

-- `/wmp` prints the frame under the cursor and the pin count. When a hover does not open the
-- tooltip this says whether a pin, the client quest POI layer, or something else owns the
-- mouse, without a debugger.
local function Diagnose()
    local out = "WorldMapPins: " .. #ns.Pins .. " pins"
    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        print(out .. ", map closed")
        return
    end
    local frame = GetMouseFocus and GetMouseFocus()
    local name = frame and (frame:GetName() or frame.pin and "pin: " .. frame.pin.label)
    print(out .. ", map open, zone index " .. tostring(GetCurrentMapZone and GetCurrentMapZone())
        .. ", mouse over " .. tostring(name or "nothing"))
end

SLASH_WORLDMAPPINS1 = "/wmp"
SLASH_WORLDMAPPINS2 = "/worldmappins"
SlashCmdList["WORLDMAPPINS"] = Diagnose

if Frame.RegisterEvent then
    Frame:RegisterEvent("PLAYER_LOGIN")
    Frame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff33ff99WorldMapPins|r loaded from patch-Z.MPQ (" .. #ns.Pins .. " pins)."
            )
        end
    end)
end

ns.Refresh = Refresh
ns.DisplayedZone = DisplayedZone
ns.ICONS = ICONS
