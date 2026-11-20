-- Smoke test for the Journal addon outside the game: stubs just enough of the 3.3.5a API,
-- loads the addon in .toc order and answers its requests with a fake mod-forever-journal server,
-- then walks every page and tab.
-- Usage (any Lua 5.3+): lua tools/addon_smoke_test.lua addon/Journal
-- DRAGON=1 runs it again with a DragonUI stand-in, for the skinned branches.

local dir = arg[1] or "addon/Journal"
unpack = table.unpack
bit = {
	band = function (a, b) return math.floor(a) & math.floor(b) end,
	bor = function (a, b) return math.floor(a) | math.floor(b) end,
}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

local now = 0
function GetTime() return now end

local errors = 0
local function report(where, err)
	errors = errors + 1
	print("ERROR in " .. where .. ": " .. tostring(err))
end

-----------------------------------------
-- frames: tables with scripts; unknown methods are no-ops returning nil

local frameMeta = {}
local allFrames = {}
local function newObject(kind, name, parent)
	local o = { __kind = kind, __name = name, __scripts = {}, __shown = true, __text = "", __width = 100, __height = 20,
		__parent = parent, __enabled = true }
	setmetatable(o, frameMeta)
	if name then _G[name] = o end
	table.insert(allFrames, o)
	return o
end

local methods = {}
function methods:SetScript(event, fn) self.__scripts[event] = fn end
function methods:GetScript(event) return self.__scripts[event] end
function methods:HookScript(event, fn)
	local old = self.__scripts[event]
	self.__scripts[event] = function (...) if old then old(...) end fn(...) end
end
function methods:Show() local was = self.__shown; self.__shown = true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end end
function methods:Hide() local was = self.__shown; self.__shown = false; if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end end
function methods:IsShown() return self.__shown end
function methods:IsVisible()
	local f = self
	while f do
		if not rawget(f, "__shown") then return false end
		f = rawget(f, "__parent")
	end
	return true
end
function methods:SetText(t)
	local old = self.__text
	self.__text = t == nil and "" or tostring(t)
	-- Like the client: an edit box's OnTextChanged runs at once, also for text set from code.
	if self.__kind == "EditBox" and old ~= self.__text and self.__scripts.OnTextChanged then
		self.__scripts.OnTextChanged(self)
	end
end
function methods:SetPoint() self.__points = (rawget(self, "__points") or 0) + 1 end
function methods:ClearAllPoints() self.__points = 0 end
function methods:GetNumPoints() return rawget(self, "__points") or 0 end
function methods:GetText() return self.__text end
function methods:SetChecked(c) self.__checked = c and 1 or nil end
function methods:GetChecked() return rawget(self, "__checked") end
function methods:GetWidth() return self.__width end
function methods:GetHeight() return self.__height end
function methods:SetWidth(w) self.__width = w end
function methods:SetHeight(h) self.__height = h end
function methods:SetSize(w, h) self.__width, self.__height = w, h end
function methods:GetName() return self.__name end
function methods:GetFrameLevel()
	local own = rawget(self, "__level")
	if own then return own end
	local p = rawget(self, "__parent")
	return p and p.GetFrameLevel and p:GetFrameLevel() + 1 or 1
end
function methods:SetFrameLevel(l) self.__level = l end
function methods:GetObjectType() return self.__kind end
function methods:GetRegions() return end
function methods:CreateTexture() return newObject("Texture", nil, self) end
function methods:CreateFontString() return newObject("FontString", nil, self) end
function methods:Enable() self.__enabled = true end
function methods:Disable() self.__enabled = false end
function methods:IsEnabled() return self.__enabled and 1 or nil end
function methods:GetParent() return rawget(self, "__parent") end
function methods:SetParent(p) self.__parent = p end
function methods:GetEffectiveScale() return 1 end
function methods:GetPoint()
	if rawget(self, "__point") then return table.unpack(self.__point) end
	return "TOPLEFT", UIParent, "TOPLEFT", 10, -10
end
function methods:SetPoint(...) self.__point = { ... } end
function methods:GetStringHeight() return 14 * math.max(1, math.ceil(#(self.__text or "") / 60)) end
function methods:GetStringWidth() return 6 * #(self.__text or "") end
function methods:GetVerticalScroll() return self.__vscroll or 0 end
function methods:SetVerticalScroll(v) self.__vscroll = v end
-- A slider runs OnValueChanged on every SetValue, from code or the mouse.
function methods:SetValue(v) self.__value = v; if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, v) end end
function methods:GetValue() return rawget(self, "__value") or 0 end
function methods:SetBackdrop(b) self.__backdrop = b end
-- A texture path "loads" unless it names something the test says is missing.
function methods:SetTexture(path) self.__texture = path; return not (type(path) == "string" and path:find("MISSING")) and 1 or nil end
function methods:GetTexture() return self.__texture end
function methods:GetFontString()
	if not rawget(self, "__fs") then self.__fs = newObject("FontString", nil, self) end
	return self.__fs
end
function methods:SetTextColor(r, g, b) self.__color = { r, g, b } end
function methods:GetTextColor() local c = rawget(self, "__color") or { 1, 1, 1 } return c[1], c[2], c[3] end
function methods:GetCenter() return 500, 400 end
function methods:HasFocus() return rawget(self, "__focus") end
function methods:SetFocus() self.__focus = true end
function methods:ClearFocus() self.__focus = nil end
-- Model frames: a creature shows (GetModel names a file) only once the client has it cached.
local cachedCreatures = { [308] = true, [7385] = true, [639] = true }
local creatureRecordsSent = {}
function methods:SetModelScale(scale) self.__scale = scale end
function methods:SetPosition(depth, x, y) self.__x, self.__y = x, y end
function methods:SetFacing(facing) self.__facing = facing end
function methods:SetCreature(entry) self.__scaleAtLoad = self.__scale; self.__creature = entry end
function methods:ClearModel() self.__creature = nil end
function methods:GetModel()
	local c = rawget(self, "__creature")
	return c and cachedCreatures[c] and ("Creature\\C" .. c .. ".m2") or ""
end
function methods:SetLight(on, omni, x, y, z, ambient) self.__ambient = ambient end
frameMeta.__index = function (t, k)
	if methods[k] then return methods[k] end
	if type(k) == "string" and k:match("^%u") then return function () end end
	return nil
end

function CreateFrame(kind, name, parent, template)
	local f = newObject(kind, name, parent)
	if name and template then
		if template:find("Check") then _G[name .. "Text"] = newObject("FontString", nil, f) end
		if template:find("ScrollFrame") then _G[name .. "ScrollBar"] = newObject("Slider", nil, f) end
	end
	return f
end

function InCombatLockdown() return false end
local played
function PlaySound(name) played = name end
function GetMoney() return 300000 end
local modified = {}
function IsModifiedClick(what) return modified[what] or false end
function IsShiftKeyDown() return modified.SHIFT or false end
local inserted
function ChatEdit_InsertLink(link) inserted = link return true end
function ChatFrame_OpenChat() end
local dressedUp
function DressUpItemLink(link) dressedUp = link end
local lastMenu
function EasyMenu(items) lastMenu = items end
function CloseDropDownMenus() end
function UnitName() return "Tester" end
function GetRealmName() return "Evermore" end
function UnitRace() return "Human", "Human" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitSex() return 2 end
function GetLocale() return "enUS" end
local inInstance = false
function IsInInstance() return inInstance end
function GetItemIcon() return "Interface\\Icons\\X" end
local cursorX, buttonsDown = 0, {}
function GetCursorPosition() return cursorX, 0 end
function IsMouseButtonDown(button) return buttonsDown[button] end
function time() return math.floor(now or 0) end
function GetQuestDifficultyColor() return { r = 1, g = 1, b = 0 } end
function PanelTemplates_TabResize() end
function PanelTemplates_SelectTab(t) t.__selected = true end
function PanelTemplates_DeselectTab(t) t.__selected = false end
function SetPortraitToTexture(tex, path) tex.__portrait = path end
function GameTooltip_ShowCompareItem() end
-- FrameXML's GameTooltip colours (the stock look reads them).
TOOLTIP_DEFAULT_COLOR = { r = 1, g = 1, b = 1 }
TOOLTIP_DEFAULT_BACKGROUND_COLOR = { r = 0.09, g = 0.09, b = 0.19 }
-- As 3.3.5's: the client hands the Dungeon Finder's info out as one table per LFG id, and
-- FrameXML's LFGGetDungeonInfoByID only reads LFGDungeonInfo, which stays nil until the Dungeon
-- Finder list has been opened.
function GetLFDChoiceInfo(into)
	into = into or {}
	local tex = { [6] = "DEADMINES", [18] = "SCARLETMONASTERY", [159] = "NAXXRAMAS" }
	for id = 1, 300 do into[id] = { "x", 1, 1, 1, 1, 1, 1, 0, 1, tex[id] or "MISSING", 0, 5 } end
	return into
end
function LFGGetDungeonInfoByID(id) return LFGDungeonInfo[id] end
local bindings = {}
function GetBindingAction(key) return bindings[key] or "" end
function SetBinding(key, action) bindings[key] = action end
function SaveBindings() end
function GetCurrentBindingSet() return 1 end
function GetBindingKey(action) for k, a in pairs(bindings) do if a == action then return k end end end
function select(n, ...) if n == "#" then return #{ ... } end return table.unpack({ ... }, n) end
function UnitFactionGroup() return "Alliance" end
function FauxScrollFrame_GetOffset(f) return rawget(f, "__offset") or 0 end
function FauxScrollFrame_SetOffset(f, o) f.__offset = o end
function FauxScrollFrame_Update(f, total, shown) f.__total = total end
function FauxScrollFrame_OnVerticalScroll(f, value, h, fn) f.__offset = math.floor(value / h + 0.5) fn() end
-- The character's mounts and pets: (creature, name, spell, icon, active)
local companions = { MOUNT = { { 308, "Black Stallion", 470, "Interface\\Icons\\M", false } },
	CRITTER = { { 7385, "Bombay Cat", 10673, "Interface\\Icons\\P", false } } }
function GetNumCompanions(kind) return #companions[kind] end
function GetCompanionInfo(kind, i) return table.unpack(companions[kind][i]) end
local called
function CallCompanion(kind, i) called = kind .. ":" .. i; companions[kind][i][5] = true end
function DismissCompanion(kind) called = "dismiss:" .. kind end
local picked
function PickupCompanion(kind, i) picked = kind .. ":" .. i end
function PickupItem(id) picked = "item:" .. id end
function IsMounted() return false end
-- Orb of Deception (1973) is a trinket, not worn.
function IsEquippableItem(id) return id == 1973 end
function IsEquippedItem() return false end
function Dismount() end
function GetAchievementInfo(id) return id, "Leeroy!", 10, false, nil, nil, nil, "Defeat 50 whelps.", 0, "Interface\\Icons\\A" end
function GetAddOnInfo(name) if name == "DungeonJournal" then return "DungeonJournal", "Dungeon Journal", "", 1 end end
local disabledAddon
function DisableAddOn(name) disabledAddon = name end
function IsAddOnLoaded() return true end

ITEM_QUALITY_COLORS = {}
for i = 0, 7 do ITEM_QUALITY_COLORS[i] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end
INVTYPE_CHEST, INVTYPE_HEAD, INVTYPE_WEAPON = "Chest", "Head", "One-Hand"
LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", MAGE = "Mage" }
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 } }
UIParent = newObject("Frame", "UIParent")
WorldFrame = newObject("Frame", "WorldFrame")
Minimap = newObject("Frame", "Minimap")
GameTooltip = newObject("GameTooltip", "GameTooltip")
local tipLines = {}
function GameTooltip:SetOwner(owner) tipLines = {} self.__owner = owner end
function GameTooltip:IsOwned(f) return self.__owner == f end
function GameTooltip:AddLine(text) table.insert(tipLines, tostring(text)) end
function GameTooltip:AddDoubleLine(a, b) table.insert(tipLines, tostring(a) .. " | " .. tostring(b)) end
local chatLines = {}
DEFAULT_CHAT_FRAME = { AddMessage = function (_, m) print("  [chat] " .. m); table.insert(chatLines, m) end }
local function chatShown(pattern)
	for _, m in ipairs(chatLines) do if m:find(pattern) then return true end end
	return false
end
GameFontHighlightSmall, GameFontNormal, GameFontHighlight = {}, {}, {}
function GameFontNormal:GetFont() return "Fonts\\FRIZQT__.TTF", 12 end
SlashCmdList, UISpecialFrames = {}, {}

-- The scan tooltip: spell descriptions come back as gold lines, like the real one.
local spellText = {
	[5145] = { "Arcane Explosion", "Sends a wave of arcane energy." },
	[6432] = { "Smite Stomp", "Knocks down nearby enemies." },
	[9999] = { "Hidden Trigger" }, -- no description: left out
}
local origCreate = CreateFrame
function CreateFrame(kind, name, parent, template)
	local f = origCreate(kind, name, parent, template)
	if kind == "GameTooltip" and name then
		local lines = {}
		for i = 1, 4 do lines[i] = newObject("FontString", name .. "TextLeft" .. i, f) end
		function f:SetHyperlink(link)
			for i = 1, 4 do lines[i]:SetText(""); lines[i].__color = { 1, 1, 1 } end
			self.__n = 0
			local spell = tonumber(link:match("spell:(%d+)"))
			local s = spell and spellText[spell]
			if s then
				lines[1]:SetText(s[1])
				lines[2]:SetText("Instant")
				self.__n = 2
				if s[2] then
					lines[3]:SetText(s[2])
					lines[3].__color = { 1, 0.82, 0 }
					self.__n = 3
				end
			end
		end
		function f:NumLines() return self.__n or 0 end
	end
	return f
end

-- With DRAGON=1, a DragonUI stand-in, so the skinned branches run too.
if os.getenv("DRAGON") == "1" then
	DragonUI_NineSlice = { GetLayout = function () return {} end, ApplyLayout = function () end }
	DragonUI = {
		_dir = "Interface\\AddOns\\DragonUI\\Textures\\", atlasinfo = {}, Fonts = { PRIMARY = "Fonts\\FRIZQT__.TTF" },
		SafeSetAtlas = function () return true end, SkinRedButton = function () end,
		-- ReskinTab sizes the tab to its label, as DragonUI's does; its PanelTemplates_TabResize
		-- hook then calls the tab's _duiRelayout.
		CharacterPanel = { ReskinTab = function (t)
				t.__reskinned = (rawget(t, "__reskinned") or 0) + 1
				t:SetWidth(math.max(62, 6 * #(t.__text or "") + 30))
			end, ModernizeCloseButton = function () end,
			SkinCheckbox = function () end, ReskinScrollBar = function () end,
			SyncScrollThumb = function (scroll) scroll.__thumbSynced = (rawget(scroll, "__thumbSynced") or 0) + 1 end },
		-- Its Mounts and Pets window: the art, and favourites per kind keyed by creature.
		GOLD_ICON_FRAME = { texture = "DUI\\IconFrameGold", open = 0.4922, cx = 0.4727, cy = 0.4336 },
		LayoutGoldIconFrame = function (tex, icon) tex:SetTexture("DUI\\IconFrameGold") end,
		Collections = {
			TEX = { rows = "DUI\\ListButtons", favorite = "DUI\\FavoritesIcon", modelBg = "DUI\\MountJournal-BG",
				faction = "DUI\\MountJournalIcons" },
			ROW_COORDS = { background = { 0, 1, 0, 0.2 }, highlight = { 0, 1, 0.2, 0.4 }, selected = { 0, 1, 0.4, 0.6 } },
			FAV_COORD = { 0, 1, 0, 1 }, MODEL_BG_COORD = { 0, 0.8, 0, 1 },
			FACTION_COORDS = { [0] = { 0.4, 0.8, 0, 0.75 }, [1] = { 0, 0.4, 0, 0.75 } },
			RandomIcon = { MOUNT = "Interface\\Icons\\RandomMount", CRITTER = "Interface\\Icons\\RandomPet" },
			favorites = { MOUNT = {}, CRITTER = {} },
			IsFavorite = function (kind, id) return DragonUI.Collections.favorites[kind][id] == true end,
			ToggleFavorite = function (kind, id)
				local t = DragonUI.Collections.favorites[kind]
				t[id] = (not t[id]) or nil
				return t[id] == true
			end,
			SummonRandomFavorite = function (kind) DragonUI.Collections.randomCalled = kind end,
		},
	}
end

-----------------------------------------
-- the game's items and spells

local items = { [5191] = { "Cruel Barb", 3 }, [5193] = { "Cape of the Brotherhood", 3 }, [2874] = { "Unsent Letter", 1 },
	[1973] = { "Orb of Deception", 3 }, [13379] = { "Piccolo of the Flaming Fire", 3 }, [2411] = { "Black Stallion Bridle", 1 } }
function GetItemInfo(item)
	local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
	local d = id and items[id]
	if not d then return nil end
	return d[1], "|cff0070dd|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[" .. d[1] .. "]|h|r", d[2], 20, 15, "Weapon", "Swords", 1, "", "Interface\\Icons\\X", 100
end
local worn = {}
function GetInventoryItemID(_, slot) return worn[slot] end
-- 7777 and 8888 have no description in the client: the server writes one.
local spellNames = { [5145] = "Arcane Explosion", [6432] = "Smite Stomp", [9999] = "Hidden Trigger", [6603] = "Attack",
	[7777] = "Berserk", [8888] = "Shadow Prison", [7778] = "Hard Enrage", [7779] = "Blank Mechanic",
	[470] = "Black Stallion", [458] = "Brown Horse", [32244] = "Blue Wind Rider", [10673] = "Bombay Cat", [10674] = "Cornish Rex Cat",
	[27241] = "Gurky", [90615] = "Twilight Witch's Sweeper" }
function GetSpellInfo(id) return spellNames[id], nil, "Interface\\Icons\\S" end
function GetSpellLink(id) return "|Hspell:" .. id .. "|h[" .. tostring(spellNames[id]) .. "]|h" end

-----------------------------------------
-- events and the fake server

local outbox = {}
-- mod-pet-loot's auto-summon pick: the Pets tab asks it under its own prefix.
local petLoot = { outbox = {}, sent = {}, pick = 0, online = true }
function SendAddonMessage(prefix, msg, channel)
	assert(channel == "WHISPER", "bad addon message")
	assert(#prefix + 1 + #msg <= 254, "addon message too long")
	if prefix == "PETLOOT" then
		table.insert(petLoot.outbox, msg)
		return
	end
	assert(prefix == "JNL", "bad addon message prefix: " .. tostring(prefix))
	table.insert(outbox, msg)
end

local eventFrames = {}
function methods:RegisterEvent(e) eventFrames[e] = eventFrames[e] or {}; table.insert(eventFrames[e], self) end
function methods:UnregisterEvent() end
local function fire(event, ...)
	for _, f in ipairs(eventFrames[event] or {}) do
		local ok, err = pcall(f.__scripts.OnEvent, f, event, ...)
		if not ok then report(event, err) end
	end
end

local function reply(msg)
	assert(#msg <= 250, "server message too long: " .. #msg)
	fire("CHAT_MSG_ADDON", "JNL", msg, "WHISPER", "Tester")
end

-- Like the server's SendRows: as many rows per message as fit, never splitting one.
local function list(code, req, meta, rows)
	reply(code .. "R:" .. req .. (meta and (":" .. meta) or ""))
	local header = code .. "D:" .. req .. ":"
	local line = ""
	for _, row in ipairs(rows or {}) do
		if line ~= "" and #header + #line + 1 + #row > 240 then
			reply(header .. line)
			line = ""
		end
		line = line == "" and row or (line .. ";" .. row)
	end
	if line ~= "" then reply(header .. line) end
	reply(code .. "E:" .. req)
end

local counts = {}
local sent = {}
local echoOnly = false -- a realm without the module: the whisper to yourself just comes back
local emptyLibrary = false -- the J answer: no books read yet
local function serve(msg)
	if echoOnly then
		fire("CHAT_MSG_ADDON", "JNL", msg, "WHISPER", "Tester")
		return
	end
	local args = {}
	for part in (msg .. ":"):gmatch("([^:]*):") do table.insert(args, part) end
	local cmd, req = args[1], args[2]
	counts[cmd] = (counts[cmd] or 0) + 1
	table.insert(sent, msg)
	print("  -> " .. msg)
	if cmd == "HELLO" then
		assert(args[4] == "1", "HELLO without the addon's features: " .. msg)
		reply("HELLO:" .. req .. ":2:3583:4242:3")
	elseif cmd == "D" then
		list("D", req, "3", {
			"I,6,36,0,0,15,25,19,6,Deadmines,Westfall",
			"V,6,0,0,0,5,15,0,Normal",
			"I,18,189,0,0,27,45,31,18,Scarlet Monastery,Tirisfal Glades",
			"W,18,0,18,27,37,Graveyard", "W,18,1,165,30,40,Library",
			"V,18,0,0,0,5,27,0,Normal",
			"I,159,533,1,2,80,83,80,159,Naxxramas,Dragonblight",
			"V,159,0,0,2,10,80,13,10 Player", "V,159,1,1,2,25,80,13,25 Player", "V,159,101,2,0,40,60,6,40 Player",
		})
	elseif cmd == "B" then
		if args[3] == "6" then
			list("B", req, "6:3", { "3,0,646,0,1,Mr. Smite", "6,0,639,0,1,Edwin VanCleef", "100,255,596,1,1,Miner Johnson" })
		elseif args[3] == "18" then
			list("B", req, "18:3", { "0,0,3983,0,1,Interrogator Vishas", "1,0,4543,0,1,Bloodmage Thalnos", "2,1,3974,0,1,Houndmaster Loksey" })
		else
			list("B", req, args[3] .. ":2", { "0,0,15956,0,7,Anub'Rekhan", "8,0,16063,2,7,The Four Horsemen" })
		end
	elseif cmd == "S" then
		list("S", req, args[3] .. ":3", { "V,0,0,0,1,7200,64", "R,0,L,10,1,-", "R,0,I,2874,0,Unsent Letter",
			"V,1,1,13,0,0,0", "V,101,1,6,0,0,0" })
	elseif cmd == "A" then
		list("A", req, args[3] .. ":" .. args[4] .. ":" .. args[5], {
			"U,639,20,3,3500,0,Edwin VanCleef", "E,639,7777,600", "S,639,5145,97,1500", "S,639,9999,0,0",
			"S,639,7777,16,0,Increases attack speed by 150%25. Lasts 5 min.",
			"S,639,8888,73728,0,Affects enemies within 28 yards.", "N,639,8888,Spread out%2C or else.",
			"S,639,7779,0,0,-", "R,-",
			"U,646,19,1,2000,1,Defias Companion", "E,646,7778,300", "S,646,6432,1024,0",
			"R,Gives a Defias Coin to everyone in the group.",
		})
	elseif cmd == "L" then
		list("L", req, args[3] .. ":" .. args[4] .. ":" .. args[5] .. ":3", {
			"5191,1650,16,1,1,3,2,7,13,24,19,6,Cruel Barb,0",
			"5193,2500,16,1,1,3,4,1,16,24,19,6,Cape of the Brotherhood,0",
			"2874,10000,1,1,1,1,12,0,0,1,0,6,Unsent Letter,0",
			"7230,800,0,1,1,3,4,4,5,24,19,6,Smite's Plate,0",
			-- a token for warriors, priests and druids; a sword only mages may use
			"29767,1500,80,1,1,4,15,0,0,70,0,6,Leggings of the Fallen Defender,1041",
			"50001,500,16,1,1,4,2,7,13,70,0,6,Mage Blade,128",
		})
	elseif cmd == "K" then
		list("K", req, args[3] .. ":3", { "30116,1,Q,4,120,Warbringer Legguards", "30117,16,Q,4,120,Legwraps of the Avatar",
			"30118,1024,V,4,120,Nordrassil Wrath-Kilt" })
	elseif cmd == "Q" then
		list("Q", req, args[3] .. ":3", {
			"Q,166,0,22,14,8,2650,1800,C,234,The Defias Brotherhood,Gryan Stoutmantle,Westfall",
			"R,166,-,5193*1/2874*1",
			"Q,373,4,22,22,0,1200,0,I,2874,The Unsent Letter,Unsent Letter,Drops in the dungeon",
			"R,373,-,-",
			"Q,214,3,20,15,0,0,0,C,235,Red Silk Bandanas,Scout Riell,Westfall",
			"R,214,5191*1,-",
		})
	elseif cmd == "QD" then
		list("T", req, args[3], { "O,Kill Edwin VanCleef and bring his head to $N.", "K,639,1,Edwin VanCleef",
			"I,3637,1,Head of VanCleef", "P,155,1,The Defias Brotherhood" })
	elseif cmd == "H" then
		reply("H:" .. req .. ":159:101")
	elseif cmd == "R" then
		-- The server pushes the creature records; the client caches them as if it had asked.
		local n = 0
		for entry in args[3]:gmatch("%d+") do
			creatureRecordsSent[tonumber(entry)] = (creatureRecordsSent[tonumber(entry)] or 0) + 1
			cachedCreatures[tonumber(entry)] = true
			n = n + 1
		end
		reply("R:" .. req .. ":" .. n)
	elseif cmd == "OPENED" then
		-- the addon's answer to OPEN; nothing comes back
	elseif cmd == "N" then
		if args[3] == "R" then
			list("N", req, "1:1", { "197,225" })
		elseif args[3] == "S" then
			list("N", req, "1:1", { "3,C,4974,Aldwin Laughlin,Guard,Stormwind City,Trade District,-1,-1,-,-1,8,0" })
		elseif args[3] == "P" then
			list("N", req, "1:1", { "7,C,1346,Georgio Bolero,Tailoring Trainer,Stormwind City,-,436,640,-,312,2,4" })
		else
			list("N", req, "2:75", {
				"1,C,914,Ander Germaine,Warrior Trainer,Stormwind City,Old Town,790,710,-,140,1,0",
				"2,C,3169,Tarshaw Jaggedscar,Warrior Trainer,Orgrimmar,-,800,320,Kalimdor,-1,8,0",
			})
		end
	elseif cmd == "M" and args[3] == "N" then
		reply("M:" .. req .. ":ok:Ander Germaine <Warrior Trainer> - Stormwind City%2C Old Town (79%2C 71)%2C 140 yards north-east")
	elseif cmd == "M" then
		reply("M:" .. req .. ":ok:Westfall (42%2C 72)%2C 120 yards away")
	elseif cmd == "F" then
		list("F", req, "3", { "I,6", "B,6,6", "L,6,6,0,5191,1650,3" })
	elseif cmd == "C" then
		local rows = {
			M = { "458,284,5656,1,1,0,1,0", "470,308,2411,1,1,0,1,0", "32244,22720,25475,3,6,0,1,8",
				"99999,1,1,1,0,0,1,0", -- 99999: a spell the client doesn't have
				"90615,1,90615,4,20,0,0,0" }, -- nothing gives it (unobtainable): hidden unless asked for
			P = { "10673,7385,8485,1,0,0,1,0", "10674,7384,8486,1,0,0,3,0" },
			T = { "1973,0,1973,3,0,0,2,0", "13379,0,13379,3,0,0,2,0" },
		}
		list("C", req, args[3] .. ":" .. #rows[args[3]], rows[args[3]])
	elseif cmd == "W" then
		list("W", req, args[3] .. ":" .. args[4] .. ":3", {
			"V,0,384,1000000,0,0,-,0,1,Katie Hunter,Elwynn Forest,-",
			"D,1,30639,150,6,6,0,1,0,Edwin VanCleef,The Deadmines,0,-,639",
			"D,8,15954,100,159,3,0,1,0,Noth the Plaguebringer,Naxxramas,101,40 Player",
			"Q,2,166,22,9,1,1,The Defias Brotherhood,Gryan Stoutmantle,Westfall",
			"A,3,1234", "C,4,9999,202,250,Engineering,0,0,0", "T,5,2,20,0,0,1,12,Lord Grayson,Stormwind City",
			"N,6,Ask a GM%2C nicely.", "S,7,222,180,0", "B,8,5,60000000,0,1,Mister Chu,Booty Bay,Landro Longshot",
			"U,9,20,7,10000000,1,0,1,4,Mirabel Ashford,Stormwind City", "+,10,V,3",
		})
	elseif cmd == "T" then
		-- 34 coins in the wallet, 5 in the bags; up for bid at 6,500g after 2 bids, 5h left.
		reply("T:" .. req .. ":34:5:65000000:2:18000")
	elseif cmd == "G" then
		-- Westfall is where the tester stands; Hellfire Peninsula is past their era (3).
		list("G", req, "5:40", {
			"G,E,12,30,28,28,0,1,10,Elwynn Forest", "G,E,40,45,44,3,0,10,20,Westfall",
			"G,O,3483,80,80,0,8,58,63,Hellfire Peninsula", "G,D,1581,6,6,1,0,17,22,The Deadmines",
			"G,C,100081,12,12,2,0,10,60,Warrior",
		})
	elseif cmd == "Z" then
		list("Z", req, args[3] .. ":3", {
			"Q,166,0,22,14,8,2650,1800,C,234,The Defias Brotherhood,Gryan Stoutmantle,-,0,0",
			"R,166,-,5193*1/2874*1",
			"Q,167,5,22,14,8,2650,1800,C,234,The Defias Brotherhood,Gryan Stoutmantle,-,1,0",
			"R,167,-,-",
			"Q,9999,7,60,58,0,0,0,C,16820,Arrival in Outland,Thrallmar Scout,Hellfire Peninsula,0,8",
			"R,9999,-,-",
		})
	elseif cmd == "X" then
		list("X", req, "1", {
			"C,166,40", "Q,166,0,22,14,8,2650,1800,C,234,The Defias Brotherhood,Gryan Stoutmantle,-,0,0", "R,166,-,-",
		})
	elseif cmd == "Y" then
		-- Elwynn Forest is where the tester stands; Hellfire Peninsula is past their era (3).
		list("Y", req, "3:9:12", {
			"Z,12,E,3,6,0,Elwynn Forest", "Z,14,K,0,2,0,Durotar", "Z,3483,O,0,1,8,Hellfire Peninsula",
		})
	elseif cmd == "U" then
		if args[3] == "12" then
			list("U", req, "12:3:6", {
				"E,12000,0,1,0,Elwynn Forest,-", "E,12001,1,2,0,Goldshire,-", "E,12002,1,0,0,Fargodeep Mine,Explore Fargodeep Mine",
				"E,12010,2,2,0,Marshal Dughan,-", "E,12011,2,0,0,Hogger,Defeat Hogger", "E,12020,3,1,0,The Defias Brotherhood,-",
			})
		else
			list("U", req, args[3] .. ":0:1", { "E,14000,0,0,0,Durotar,Explore Durotar" })
		end
	elseif cmd == "V" then
		if args[3] == "12001" then
			-- The text in three pieces (rows), with an escaped comma and line breaks, and a piece that reads as a number.
			reply("VR:" .. req .. ":12001:12:1:Goldshire")
			reply("VD:" .. req .. ":The town at the crossroads%2C with an inn.%0A%0ALion's Pride;1066; 1066.")
			reply("VE:" .. req)
		else
			list("V", req, args[3] .. ":12:0:Elwynn Forest", { "Green hills%2C old forest." })
		end
	elseif cmd == "J" then
		if emptyLibrary then
			list("J", req, "0", {})
		else
			list("J", req, "2", { "B,1001,1700000000,The Kaldorei and the Well of Eternity,Stormwind City", "B,2002,1700000100,A Letter,-" })
		end
	elseif cmd == "P" then
		-- Two pages; the second's text comes in two pieces, one of them looking like a number.
		reply("PR:" .. req .. ":" .. args[3] .. ":2:The Kaldorei and the Well of Eternity")
		reply("PD:" .. req .. ":1.Long ago%2C the night elves.$B$BHello $N.;2.It fell in;2. 10000.")
		reply("PE:" .. req)
	elseif cmd == "O" then
		-- Orb of Deception in the bags, Piccolo of the Flaming Fire only in the bank.
		list("O", req, "2", { "1973,1", "13379,0" })
	else
		print("  !! unknown command " .. cmd)
	end
end

local function tick(seconds)
	for _ = 1, math.ceil(seconds / 0.05) do
		now = now + 0.05
		for _, f in ipairs(allFrames) do
			if f.__shown and f.__scripts.OnUpdate then
				local ok, err = pcall(f.__scripts.OnUpdate, f, 0.05)
				if not ok then report("OnUpdate", err) end
			end
		end
		while #outbox > 0 do serve(table.remove(outbox, 1)) end
		while #petLoot.outbox > 0 do
			local msg = table.remove(petLoot.outbox, 1)
			table.insert(petLoot.sent, msg)
			if petLoot.online then
				local spell = msg:match("^S:(%d+)$")
				if spell then petLoot.pick = tonumber(spell) end
				fire("CHAT_MSG_ADDON", "PETLOOT", "A:" .. petLoot.pick, "WHISPER", "Tester")
			end
		end
	end
end

local function step(name, fn)
	print("== " .. name)
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then errors = errors + 1; print("ERROR: " .. err) end
	tick(0.5)
end

for line in io.lines(dir .. "/Journal.toc") do
	if line:match("%.lua$") then
		local chunk, err = loadfile(dir .. "/" .. line)
		if not chunk then report("load " .. line, err) else
			local ok, e = pcall(chunk, "Journal", {})
			if not ok then report("run " .. line, e) end
		end
	end
end

local J = Journal
local function find(pred)
	for _, f in ipairs(allFrames) do if pred(f) then return f end end
end
local function findAll(pred)
	local out = {}
	for _, f in ipairs(allFrames) do if pred(f) then table.insert(out, f) end end
	return out
end
local function textShown(pattern)
	return find(function (f) return f.__kind == "FontString" and f.__text:find(pattern) and f:IsVisible() end)
end
local function buttonShown(text)
	return find(function (f) return f.__kind == "Button" and f.__text == text and f:IsVisible() end)
		or find(function (f) return f.__kind == "Button" and rawget(f, "__fs") and f.__fs.__text == text and f:IsVisible() end)
end

step("login, hello, key binding", function ()
	fire("ADDON_LOADED", "Journal")
	fire("PLAYER_LOGIN")
	tick(4)
	assert(J.serverReady, "no HELLO answer")
	assert(J.state == 3, "era state not read")
	assert(J.Has(J.HELLO_PROGRESSION), "progression flag not read")
	assert(bindings["SHIFT-J"] == "JOURNAL_TOGGLE", "Shift-J was not bound")
	assert(disabledAddon == "DungeonJournal", "the old DungeonJournal addon was not turned off")
end)

step("open the journal: classic dungeons", function ()
	J.Toggle()
	tick(1)
	assert(JournalFrame:IsShown(), "window not shown")
	assert(counts.D == 1, "instance list not asked once")
	assert(textShown("^Deadmines$") and textShown("^Scarlet Monastery$"), "classic dungeon tiles missing")
	assert(not textShown("^Naxxramas$"), "a raid shows among the dungeons")
	assert(find(function (f) return f.__kind == "Texture" and f.__portrait == "Interface\\LFGFrame\\LFGIcon-DEADMINES"
		and f:IsVisible() end), "Deadmines tile has no Dungeon Finder icon")
	assert(find(function (f) return f.__kind == "Texture" and f.__texture == "Interface\\LFGFrame\\UI-LFG-BACKGROUND-DEADMINES"
		and f:IsVisible() end), "Deadmines tile has no Dungeon Finder art")
	if DragonUI then
		-- DragonUI's resize hook hands a strip that isn't the character panel's to _duiRelayout,
		-- which has to resize every tab and keep the strip inside the window.
		local tab = JournalFrameTab1
		assert(type(tab._duiRelayout) == "function", "journal tabs have no DragonUI relayout")
		local before1, before2 = JournalFrameTab1.__reskinned, JournalFrameTab2.__reskinned
		tab._duiRelayout()
		assert(JournalFrameTab1.__reskinned > before1 and JournalFrameTab2.__reskinned > before2,
			"relayout didn't resize every tab")
	end
end)

step("raids tab: 40 player Naxxramas under classic, locked by era", function ()
	J.Show({ raids = true })
	tick(0.5)
	assert(textShown("^Naxxramas$"), "Naxxramas missing from classic raids")
	assert(textShown("Progression stage 6"), "era lock not shown")
	J.Show({ tier = 2 })
	tick(0.5)
	assert(textShown("^Naxxramas$"), "Naxxramas missing from Wrath raids")
	assert(textShown("Progression stage 13"), "Wrath era lock not shown")
end)

step("open Deadmines: bosses, rares, overview, lockout and requirements", function ()
	J.OpenInstance(6)
	tick(1)
	assert(J.view.page == "instance" and J.view.tier == 0, "didn't move to the instance under its tier")
	assert(textShown("^Edwin VanCleef$") and textShown("^Mr. Smite$"), "boss rows missing")
	assert(textShown("^Rares$") and textShown("^Miner Johnson$"), "rares section missing")
	assert(textShown("Difficulties"), "instance overview missing")
	assert(textShown("saved, 1/2 defeated"), "lockout not shown: bit 6 is VanCleef")
	assert(textShown("Carry Unsent Letter"), "requirement missing")
	assert(textShown("1 to pick up"), "quest summary missing")
end)

step("entrance on the map", function ()
	local b = buttonShown("Show on map")
	assert(b, "no entrance button")
	b.__scripts.OnClick(b)
	tick(0.5)
	assert(sent[#sent]:match("^M:%d+:E:6$"), "entrance flag not asked: " .. sent[#sent])
end)

step("boss: overview, abilities", function ()
	J.Show({ boss = 6, tab = "overview" })
	tick(1)
	assert(textShown("3,500 health"), "boss health missing")
	assert(textShown("Defeated this lockout"), "kill not shown")
	-- The 3.3.5 client draws a model inside a scroll frame in the wrong place.
	local model = find(function (f) return f.__kind == "PlayerModel" and f:IsVisible() end)
	assert(model, "boss model not shown")
	local p = model:GetParent()
	while p do
		assert(p.__kind ~= "ScrollFrame", "boss model sits inside a scroll frame")
		p = p:GetParent()
	end
	J.Show({ tab = "abilities" })
	tick(0.5)
	assert(textShown("^Arcane Explosion$"), "ability missing")
	assert(textShown("Interruptible") and textShown("Magic"), "ability tags missing")
	assert(not textShown("^Hidden Trigger$"), "a spell without description was listed")
	assert(textShown("^Add: Defias Companion$") and textShown("Knockback"), "add missing")
	assert(textShown("1.5 sec"), "cast time missing")
	assert(textShown("^Berserk$") and textShown("Increases attack speed by 150%%"), "server description not shown")
	assert(textShown("Enrage timer: 10 min"), "enrage timer not on its ability")
	assert(textShown("^Hard Enrage$") and textShown("Cast 5 min into the fight"), "enrage row for an unlisted spell missing")
	assert(textShown("^Shadow Prison$") and textShown("Spread out, or else."), "note missing")
	assert(textShown("Important") and textShown("Tank"), "role flags missing")
	assert(not textShown("^Blank Mechanic$"), "a spell with an empty server text was listed")
	local row = find(function (f) return f.__kind == "Button" and rawget(f, "spell") == 7777 and f:IsVisible() end)
	row.__scripts.OnEnter(row)
	local found = false
	for _, l in ipairs(tipLines) do if l:find("attack speed") then found = true end end
	assert(found, "server description not in the tooltip")
	J.Show({ tab = "overview" })
	tick(0.5)
	assert(textShown("Berserk|r after 10 min"), "enrage timer not on the overview")
	assert(textShown("Also rewards:|r Gives a Defias Coin"), "boss reward missing")
	assert(buttonShown("Abilities (4)"), "ability count should include server-described ones")
end)

step("loot: warrior filter, slots, links", function ()
	J.Show({ tab = "loot" })
	tick(0.5)
	assert(textShown("^Cruel Barb$"), "weapon missing")
	assert(textShown("^Smite's Plate$") == nil, "plate below level 40 shown to a warrior (wants mail)")
	assert(textShown("^Cape of the Brotherhood$"), "cloak missing")
	assert(textShown("^17%%$") and textShown("^100%%$"), "drop chance missing")
	assert(textShown("4 of 6 items"), "filtered count missing")
	assert(textShown("^Leggings of the Fallen Defender$") and textShown("^Token$"), "warrior token missing")
	assert(not textShown("^Mage Blade$"), "a mage-only sword shown to a warrior")
	local token = find(function (f) return f.__kind == "Button" and rawget(f, "data") and f.data.item == 29767 and f:IsVisible() end)
	token.__scripts.OnEnter(token)
	tick(0.5)
	local lines = table.concat(tipLines, "\n")
	assert(counts.K == 1, "token results not asked")
	assert(lines:find("Turns into:") and lines:find("Warbringer Legguards"), "token results missing: " .. lines)
	assert(not lines:find("Legwraps of the Avatar"), "another class's token result shown")
	JournalCharDB.lootClass = false
	J.ctx.inst = J.Instance(6)
	J.RefreshPage()
	tick(0.5)
	assert(textShown("^Smite's Plate$") and textShown("^Mage Blade$"), "All classes didn't show everything")
	local row = find(function (f) return f.__kind == "Button" and rawget(f, "data") and f.data.item == 5191 and f:IsVisible() end)
	modified.CHATLINK = true
	row.__scripts.OnClick(row)
	modified.CHATLINK = nil
	assert(inserted and inserted:find("Cruel Barb"), "Shift-click didn't link")
	row.__scripts.OnEnter(row)
	-- Shift-compare waits until the worn gear is cached: the 3.3.5 client crashes otherwise.
	local compares = 0
	GameTooltip_ShowCompareItem = function () compares = compares + 1 end
	worn[16] = 12345
	modified.SHIFT = true
	tick(0.2)
	assert(compares == 0, "compared against worn gear the client hasn't cached")
	items[12345] = { "Worn Blade", 2 }
	tick(0.2)
	assert(compares == 1, "no compare once the worn gear was cached")
	modified.SHIFT = nil
	worn[16] = nil
	GameTooltip_ShowCompareItem = function () end
	JournalCharDB.lootSlot = "back"
	J.RefreshPage()
	tick(0.5)
	assert(textShown("^Cape of the Brotherhood$") and not textShown("^Cruel Barb$"), "slot filter")
	JournalCharDB.lootSlot = nil
end)

step("every boss's loot", function ()
	local from = #sent
	J.Show({ boss = false, tab = "loot" })
	tick(0.5)
	local asked = false
	for i = from + 1, #sent do if sent[i]:match("^L:%d+:6:all:0$") then asked = true end end
	assert(asked, "every-boss loot not asked")
	assert(textShown("Edwin VanCleef|r"), "boss name missing from every-boss rows")
end)

step("quests: status, rewards, objectives, map flag", function ()
	J.Show({ tab = "quests" })
	tick(0.5)
	assert(textShown("The Defias Brotherhood"), "quest missing")
	assert(textShown("Needs level 22"), "low-level state missing")
	assert(textShown("Starts from Unsent Letter"), "item starter missing")
	assert(textShown("2,650 XP"), "XP missing")
	local row = find(function (f) return f.__kind == "Button" and rawget(f, "quest") and f.quest.id == 166 and f:IsVisible() end)
	row.__scripts.OnClick(row)
	tick(0.5)
	assert(textShown("bring his head to Tester"), "objectives missing or $N not filled")
	assert(textShown("Slay Edwin VanCleef"), "kill objective missing")
	local map = buttonShown("Show giver on map")
	assert(map, "no giver map button")
	map.__scripts.OnClick(map)
	tick(0.5)
	assert(sent[#sent]:match("^M:%d+:Q:166$"), "giver flag not asked")
	JournalCharDB.hideDoneQuests = true
	J.RefreshPage()
	tick(0.5)
	assert(not textShown("Red Silk Bandanas"), "done quest not hidden")
end)

step("search: instances, bosses, loot", function ()
	J.searchBox:SetFocus()
	J.searchBox:SetText("vanc")
	J.searchBox.__scripts.OnTextChanged(J.searchBox)
	tick(1)
	assert(sent[#sent]:match("^F:%d+:vanc$"), "search not sent: " .. sent[#sent])
	local item = find(function (f) return f.__kind == "Button" and rawget(f, "item") == 5191 and f:IsVisible() end)
	assert(item, "loot result missing")
	item.__scripts.OnClick(item)
	tick(0.5)
	assert(J.view.tab == "loot" and J.view.boss == 6, "result didn't open the boss's loot")
end)

step("Naxxramas: 40 player tab under classic", function ()
	J.OpenInstance(159, { variant = 101 })
	tick(0.5)
	assert(J.view.tier == 0 and J.view.variant == 101, "40 player tab not picked")
	assert(textShown("locked: progression stage 6"), "40 player lock missing")
	local menu = buttonShown("40 Player")
	assert(menu, "difficulty menu doesn't show the 40 player tab")
	menu.__scripts.OnClick(menu)
	assert(lastMenu and #lastMenu == 1 and lastMenu[1].text:find("40 Player"), "classic tier offers non-classic tabs")
end)

step("open inside an instance jumps to it", function ()
	JournalFrame:Hide()
	J.Show({ page = "home" })
	inInstance = true
	J.Toggle()
	tick(1)
	assert(J.view.page == "instance" and J.view.instance == 159 and J.view.variant == 101, "didn't open on the current instance")
	inInstance = false
end)

step("cache: no second instance list with the same stamp", function ()
	local before = counts.D
	JournalFrame:Hide()
	fire("PLAYER_LOGIN")
	tick(4)
	J.Toggle()
	tick(1)
	assert(counts.D == before, "instance list asked again with an unchanged stamp")
end)

step("realm without the module: the echo isn't an answer", function ()
	local noServer = false
	J.On("NO_SERVER", function () noServer = true end)
	J.serverReady = false
	echoOnly = true
	J.SayHello()
	tick(7)
	assert(not J.serverReady, "the echoed HELLO passed for the server's answer")
	assert(noServer, "NO_SERVER didn't fire")
	echoOnly = false
	J.SayHello()
	tick(1)
	assert(J.serverReady, "HELLO after the module came back")
end)

step("mounts tab: catalog, collected first, owned count", function ()
	JournalFrame:Hide()
	SlashCmdList.JOURNALMOUNTS()
	tick(1)
	assert(J.view.section == "mounts", "/mounts didn't open the Mounts tab")
	assert(counts.C == 1 and sent[#sent - 0]:match("^[COWT]"), "catalog not asked")
	assert(textShown("Collected: |cffffffff1|r / 3"), "collected count wrong (the unknown spell must not count)")
	assert(textShown("^Black Stallion$") and textShown("^Brown Horse$") and textShown("^Blue Wind Rider$"), "mount rows missing")
	assert(textShown("Progression stage 8"), "era lock on the wind rider missing")
	assert(textShown("Vendor: Katie Hunter"), "sources of the first (collected) mount not shown")
	if DragonUI then
		-- DragonUI's grip follows the slider, not the OnVerticalScroll the list sets after skinning it.
		local bar = find(function (f) return f.__kind == "Slider" and f:IsVisible()
			and (rawget(f, "__parent").__name or ""):find("CollectionScroll") end)
		assert(bar, "no collection scroll bar")
		local before = rawget(bar.__parent, "__thumbSynced") or 0
		bar:SetValue(40)
		assert((rawget(bar.__parent, "__thumbSynced") or 0) > before, "DragonUI scroll grip not moved by scrolling")
	end
end)

step("mount sources: cost, boss link, quest, achievement, trainer, note, more", function ()
	assert(textShown("Boss: Edwin VanCleef"), "boss source missing")
	assert(textShown("40 Player"), "the difficulty a boss drops it on is missing")
	assert(textShown("from a trainer"), "where a crafted one's recipe comes from is missing")
	assert(textShown("Quest: The Defias Brotherhood"), "quest source missing")
	assert(textShown("Achievement: Leeroy!"), "achievement source missing")
	assert(textShown("Trainer: Paladin trainers") or textShown("Trainer: "), "trainer source missing")
	assert(textShown("Ask a GM, nicely."), "note missing")
	assert(textShown("and 3 more vendors"), "more row missing")
	assert(textShown("Coin Shop: 180"), "coin shop source missing")
	assert(textShown("you have 34 %(%+5 in your bags%)"), "coins in hand not filled in from T: " .. tostring(sent[#sent]))
	assert(textShown("Black Market: Mister Chu") and textShown("Up for bid now: 6500"), "Black Market source or its auction missing")
	assert(textShown("Guild Vendor: Mirabel Ashford") and textShown("guild level 20, Exalted with your guild"),
		"guild vendor source missing")
	assert(textShown("%(about 1 in 67 kills%)"), "drop chance not put in plain words")
	assert(counts.T and counts.T >= 1, "live coin shop / auction info not asked")
	local vendor = find(function (f) return f.__kind == "Button" and rawget(f, "source") and f.source.kind == "V" and f:IsVisible() end)
	vendor.__scripts.OnClick(vendor)
	tick(0.5)
	assert(sent[#sent]:match("^M:%d+:S:M:470:0$"), "vendor map flag not asked: " .. sent[#sent])
	assert(textShown("Flagged on your map"), "map flag answer not shown")
	local boss = find(function (f) return f.__kind == "Button" and rawget(f, "source") and f.source.kind == "D" and f:IsVisible() end)
	boss.__scripts.OnClick(boss)
	tick(1)
	assert(J.view.section == "dungeons" and J.view.instance == 6 and J.view.boss == 6 and J.view.tab == "loot"
		and J.view.variant == 0, "boss source didn't open the dungeon journal on its loot and difficulty")
end)

step("mounts: summon, filters, search", function ()
	J.OpenSection("mounts")
	tick(0.5)
	local summon = buttonShown("Summon")
	assert(summon, "no Summon button for a collected mount")
	-- Above the model (a sibling at the pane's level + 1), or the model's drag handler gets the click.
	assert(summon:GetFrameLevel() > summon:GetParent():GetFrameLevel() + 1, "Summon button not above the model")
	summon.__scripts.OnClick(summon)
	assert(called == "MOUNT:1", "CallCompanion not called")
	local model = find(function (f) return f.__kind == "PlayerModel" and f:IsVisible() and f.__creature == 308 end)
	assert(model and model:GetModel() ~= "", "collected mount has no model")
	assert(not (model.lockLayer and model.lockLayer:IsVisible()), "a collected mount shows the padlock")
	-- One you haven't collected: still previewed, dimmed and locked, once the client has the creature.
	local horse = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.id == 458 and f:IsVisible() end)
	horse.__scripts.OnClick(horse)
	tick(0.2)
	assert(model.__creature == 284 and model:IsVisible(), "an uncollected mount isn't previewed")
	assert(model.lockLayer and model.lockLayer:IsVisible(), "no padlock on an uncollected mount")
	assert(model.lockLayer:GetFrameLevel() > model:GetFrameLevel(), "padlock under the model")
	assert(not buttonShown("Summon"), "Summon offered for an uncollected mount")
	picked = nil
	horse.__scripts.OnDragStart(horse)
	assert(picked == nil, "dragging an uncollected mount picked something up")
	-- SetCreature never queries a creature the client lacks: the addon asks the server for it.
	tick(1)
	assert(creatureRecordsSent[284] == 1, "the uncached creature's record wasn't asked for")
	assert(not creatureRecordsSent[308], "asked for a creature the client already had")
	assert(model:GetModel() ~= "" and model.__ambient == 0.3, "the uncollected mount didn't load dimmed")
	local stallion = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.id == 470 and f:IsVisible() end)
	stallion.__scripts.OnClick(stallion)
	tick(0.2)
	assert(model.__creature == 308 and not model.lockLayer:IsVisible() and model.__ambient == 0.7, "back on a collected one: still locked")
	-- The view: remembered per creature, and every load starts from neutral.
	assert(JournalDB.modelViews == ModelViewLib.views, "views aren't saved with the journal")
	assert(model.__scale == 1, "an untouched mount isn't at the default view")
	model.__scripts.OnMouseWheel(model, -1)
	local zoomed = model.__scale
	assert(zoomed < 1, "the wheel didn't zoom out")
	horse.__scripts.OnClick(horse)
	tick(0.2)
	assert(model.__creature == 284 and model.__scaleAtLoad == 1 and model.__scale == 1, "the next mount didn't load from neutral")
	stallion.__scripts.OnClick(stallion)
	tick(0.2)
	assert(model.__creature == 308 and model.__scaleAtLoad == 1 and model.__scale == zoomed, "the view didn't come back")
	model.__scripts.OnMouseDown(model, "MiddleButton")
	assert(model.__scale == 1 and not ModelViewLib.views[308], "a middle click didn't reset it")
	-- Closed window, an event refreshes the page: nothing loads, and the next show does.
	model.__scripts.OnMouseWheel(model, -1)
	model.__scripts.OnHide(model)
	model.__shown = false
	model.__creature = nil
	J.ShowCreature(model, 308)
	assert(model.__creature == nil and not model.shownEntry, "a hidden model loaded")
	model.__shown = true
	J.ShowCreature(model, 308)
	assert(model.__creature == 308 and model.__scaleAtLoad == 1 and model.__scale == zoomed, "showing it again lost the view")
	model.__scripts.OnMouseDown(model, "MiddleButton")
	-- Dragged to an action bar: the companion, as the stock Mounts tab hands it over.
	stallion.__scripts.OnDragStart(stallion)
	assert(picked == "MOUNT:1", "dragging a collected mount didn't pick it up: " .. tostring(picked))
	-- The selected one's big icon in the detail pane drags the same way.
	local iconDrag = find(function (f)
		return f.__kind == "Button" and f:GetParent() == model:GetParent() and f.__scripts.OnDragStart and f:IsVisible()
	end)
	assert(iconDrag, "the detail pane's icon can't be dragged")
	picked = nil
	iconDrag.__scripts.OnDragStart(iconDrag)
	assert(picked == "MOUNT:1", "dragging the detail icon didn't pick the mount up: " .. tostring(picked))
	local f = J.Filters("mounts")
	f.collected = false
	J.Fire("COLLECTION_FILTER", "mounts")
	tick(0.5)
	assert(not textShown("^Black Stallion$") and textShown("^Brown Horse$"), "collected filter")
	f.collected = true
	f.mountType = "flying"
	J.Fire("COLLECTION_FILTER", "mounts")
	tick(0.5)
	assert(textShown("^Blue Wind Rider$") and not textShown("^Brown Horse$"), "flying filter")
	f.mountType = nil
	J.Fire("COLLECTION_FILTER", "mounts")
	tick(0.5)
	-- What nothing gives is left out (and out of the count) until asked for.
	assert(not textShown("^Twilight Witch's Sweeper$") and textShown("Collected: |cffffffff1|r / 3"),
		"an unobtainable mount listed by default")
	f.unobtainable = true
	J.Fire("COLLECTION_FILTER", "mounts")
	tick(0.5)
	assert(textShown("^Twilight Witch's Sweeper$") and textShown("Collected: |cffffffff1|r / 4"), "Show unobtainable")
	f.unobtainable = false
	J.Fire("COLLECTION_FILTER", "mounts")
	tick(0.5)
end)

step("goal tracker: set, where to go, kills, collected", function ()
	J.OpenSection("mounts")
	tick(0.5)
	local horse = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.id == 458 and f:IsVisible() end)
	horse.__scripts.OnClick(horse)
	tick(0.2)
	local set = buttonShown("Set as goal")
	assert(set, "no Set as goal button on an uncollected mount")
	assert(set:GetFrameLevel() > set:GetParent():GetFrameLevel() + 1, "Set as goal under the model")
	set.__scripts.OnClick(set)
	tick(1)
	assert(JournalCharDB.goal and JournalCharDB.goal.id == 458, "goal not saved")
	assert(buttonShown("Stop tracking"), "button doesn't offer to stop tracking")
	assert(JournalGoalTracker and JournalGoalTracker:IsVisible(), "tracker not shown")
	assert(textShown("^Goal: mount$") and textShown("Vendor: Katie Hunter"), "tracker doesn't say where to go")
	assert(textShown("Gold: 30"), "tracker has no gold progress for a vendor")
	-- Kills of a creature that drops it count (a party kill of Edwin VanCleef, 639 = 0x00027F).
	fire("COMBAT_LOG_EVENT_UNFILTERED", 0, "PARTY_KILL", "0x0000000000000001", "Tester", 0x511, "0xF13000027F000042", "Edwin VanCleef", 0xa48)
	fire("COMBAT_LOG_EVENT_UNFILTERED", 0, "PARTY_KILL", "0x0000000000000009", "Stranger", 0x548, "0xF13000027F000043", "Edwin VanCleef", 0xa48)
	assert(JournalCharDB.goal.kills == 1, "kill count wrong: " .. tostring(JournalCharDB.goal.kills))
	-- Clicking the tracker opens the journal on it, whatever the search box holds.
	JournalFrame:Hide()
	JournalGoalTracker.__scripts.OnClick(JournalGoalTracker, "LeftButton")
	tick(0.5)
	assert(JournalFrame:IsShown() and J.view.section == "mounts", "tracker click didn't open the Mounts tab")
	-- Learning it ends the goal.
	table.insert(companions.MOUNT, { 284, "Brown Horse", 458, "Interface\\Icons\\M", false })
	fire("COMPANION_LEARNED")
	tick(1)
	assert(JournalCharDB.goal == nil, "goal not cleared once collected")
	assert(not JournalGoalTracker:IsVisible(), "tracker still up")
	assert(played == "LEVELUPSOUND", "no cheer")
	table.remove(companions.MOUNT)
	fire("COMPANION_LEARNED")
	tick(1)
end)

step("mounts: sort by newest and oldest, open on a new one", function ()
	-- The Black Stallion was there at login (dated 0); the Brown Horse is learned now.
	local at = JournalDB.acquired and JournalDB.acquired.Evermore and JournalDB.acquired.Evermore.mounts
	assert(at and at.at[470] == 0, "a mount had at login isn't dated as before the count")
	tick(5)
	table.insert(companions.MOUNT, { 284, "Brown Horse", 458, "Interface\\Icons\\M", false })
	fire("COMPANION_LEARNED")
	tick(1)
	assert((at.at[458] or 0) > 0, "a mount learned while playing isn't dated")
	local catalog
	J.LoadCatalog("mounts", function (c) catalog = c end)
	local f = J.Filters("mounts")
	local function first() return (J.FilteredEntries("mounts", catalog, ""))[1].id end
	assert(first() == 470, "by name: Black Stallion first")
	f.sort = "newest"
	assert(first() == 458, "newest first: the Brown Horse should lead")
	f.sort = "oldest"
	assert(first() == 470, "oldest first: the Black Stallion should lead")
	local list = J.FilteredEntries("mounts", catalog, "")
	assert(not list[#list].mine, "an uncollected one sorted above a collected one")
	f.sort = nil
	-- The sort is offered in the Filter menu.
	local filter = buttonShown("Filter")
	filter.__scripts.OnClick(filter)
	local offered = {}
	for _, item in ipairs(lastMenu or {}) do offered[item.text] = item end
	assert(offered["Sort by"] and offered["Newest first"] and offered["Oldest first"], "no Sort by in the Filter menu")
	offered["Newest first"].func()
	assert(f.sort == "newest", "picking Newest first didn't set the sort")
	f.sort = nil
	-- LearnedAlert's toast: the journal opens on it, scrolled to it, past a filter that hid it.
	JournalFrame:Hide()
	f.collected = false
	local scroll = find(function (x) return x.__kind == "ScrollFrame" and (x.__name or ""):find("CollectionScroll") end)
	scroll.__offset = 3
	assert(Journal.ShowCollection("MOUNT", 458), "ShowCollection refused")
	tick(0.5)
	assert(JournalFrame:IsShown() and J.view.section == "mounts", "the toast didn't open the Mounts tab")
	assert(f.collected, "the collected filter still hides the new mount")
	assert(JournalCharDB.collectionSelected.mounts == 458, "the new mount isn't selected")
	assert(textShown("^Brown Horse$") and FauxScrollFrame_GetOffset(scroll) == 0, "the list wasn't scrolled to it")
	assert(not Journal.ShowCollection("nothing", 1), "an unknown kind was accepted")
	table.remove(companions.MOUNT)
	fire("COMPANION_LEARNED")
	tick(1)
end)

if DragonUI then
	step("mounts with DragonUI: its row plates, backdrop, favourites, random favourite", function ()
		local CO = DragonUI.Collections
		-- A second mount owned for this step, so favourites have something to jump ahead of.
		companions.MOUNT[2] = { 284, "Brown Horse", 458, "Interface\\Icons\\H", false }
		J.Fire("COMPANIONS")
		J.OpenSection("mounts")
		tick(0.5)
		local function row(id)
			return find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.id == id and f:IsVisible() end)
		end
		local function firstRow()
			return findAll(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f:IsVisible()
				and rawget(f, "star") ~= nil end)[1]
		end
		assert(find(function (f) return f.__kind == "Texture" and f.__texture == CO.TEX.rows and f:IsVisible() end),
			"list rows don't wear DragonUI's plates")
		assert(find(function (f) return f.__kind == "Texture" and f.__texture == CO.TEX.modelBg and f:IsVisible() end),
			"no DragonUI backdrop behind the selected mount")
		assert(not find(function (f) return f.__kind == "Texture" and f.__texture == "Interface\\LFGFrame\\UI-LFG-BACKGROUND-QUESTPAPER"
			and f:IsVisible() end), "the stock model backdrop still shows")
		assert(firstRow().entry.id == 470, "Black Stallion should lead before any favourite")
		local horse = row(458)
		horse.__scripts.OnClick(horse)
		tick(0.2)
		local star = find(function (f) return f.__kind == "Button" and type(rawget(f, "tex")) == "table"
			and f.tex.__texture == CO.TEX.favorite and f:IsVisible() end)
		assert(star, "no favourite star for a collected mount")
		assert(not horse.star:IsVisible(), "row starred before it was a favourite")
		star.__scripts.OnClick(star)
		tick(0.2)
		assert(CO.favorites.MOUNT[284], "the star didn't set DragonUI's favourite (keyed by the companion's creature)")
		assert(firstRow().entry.id == 458 and firstRow().star:IsVisible(), "the favourite isn't first with a star")
		local rider = row(32244)
		rider.__scripts.OnClick(rider)
		tick(0.2)
		assert(not star:IsVisible(), "an uncollected mount offers the favourite star")
		local caption = find(function (f) return f.__kind == "FontString" and f.__text == "Random favorite" and f:IsVisible() end)
		assert(caption, "no Random favorite button")
		local random = caption.__point[2]
		random.__scripts.OnClick(random)
		assert(CO.randomCalled == "MOUNT", "Random favorite didn't call DragonUI's picker")
		J.OpenSection("pets")
		tick(0.5)
		random = find(function (f) return f.__kind == "FontString" and f.__text == "Random favorite" and f:IsVisible() end).__point[2]
		random.__scripts.OnClick(random)
		assert(CO.randomCalled == "CRITTER", "pets' Random favorite didn't summon a pet")
		J.OpenSection("toys")
		tick(0.5)
		assert(not textShown("^Random favorite$"), "toys offer a random favourite")
		-- Back to how the next steps expect it.
		CO.favorites.MOUNT[284] = nil
		companions.MOUNT[2] = nil
		J.Fire("COMPANIONS")
	end)
end

step("pets and toys tabs", function ()
	J.OpenSection("pets")
	tick(1)
	assert(textShown("^Bombay Cat$") and textShown("^Cornish Rex Cat$"), "pet rows missing")
	assert(textShown("Collected: |cffffffff1|r / 2"), "pet count wrong")
	-- Auto-summon: the box shows once mod-pet-loot answers, and ticking it picks the pet.
	local function autoBox()
		return find(function (f) return f.__kind == "CheckButton" and rawget(f, "label") and f.label.__text == "Auto-summon" and f:IsVisible() end)
	end
	local box = autoBox()
	assert(box, "no Auto-summon box for a collected pet")
	assert(not box:GetChecked(), "Auto-summon ticked before anything was picked")
	box:SetChecked(true)
	box.__scripts.OnClick(box)
	tick(0.2)
	assert(petLoot.sent[#petLoot.sent] == "S:10673", "ticking Auto-summon didn't pick the pet: " .. tostring(petLoot.sent[#petLoot.sent]))
	assert(autoBox():GetChecked() and textShown("Auto%-summoned"), "the picked pet isn't shown as auto-summoned")
	box:SetChecked(false)
	box.__scripts.OnClick(box)
	tick(0.2)
	assert(petLoot.sent[#petLoot.sent] == "S:0", "unticking Auto-summon didn't turn it off")
	assert(not autoBox():GetChecked() and not textShown("Auto%-summoned"), "Auto-summon still on after unticking")
	-- A realm without mod-pet-loot (or with auto-summon off) never answers: no box.
	J.autoSummon = nil
	J.Fire("AUTO_SUMMON")
	tick(0.2)
	assert(not autoBox(), "Auto-summon box shown with no answer from the realm")
	fire("CHAT_MSG_ADDON", "PETLOOT", "A:0", "WHISPER", "Tester")
	tick(0.2)
	-- The client renumbered the list since it was read: the summon finds the pet's index afresh.
	table.insert(companions.CRITTER, 1, { 7380, "Cornish Rex Cat", 10674, "Interface\\Icons\\P", false })
	called = nil
	local petSummon = buttonShown("Summon")
	assert(petSummon, "no Summon button for a collected pet")
	petSummon.__scripts.OnClick(petSummon)
	assert(called == "CRITTER:2", "CallCompanion not called with the pet's current index: " .. tostring(called))
	local cat = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.id == 10673 and f:IsVisible() end)
	picked = nil
	cat.__scripts.OnDragStart(cat)
	assert(picked == "CRITTER:2", "dragging a pet didn't pick it up by its current index: " .. tostring(picked))
	table.remove(companions.CRITTER, 1)
	tick(1)
	-- A pet the character has that the catalog leaves out (nothing on the realm gives it) is
	-- listed all the same, unobtainable, with no question to the server about its sources.
	table.insert(companions.CRITTER, { 16069, "Gurky", 27241, "Interface\\Icons\\P", false })
	J.Fire("COMPANIONS")
	tick(1)
	assert(textShown("^Gurky$"), "an owned pet the catalog lacks isn't listed")
	assert(textShown("Collected: |cffffffff2|r / 3"), "pet count wrong with an owned pet the catalog lacks")
	local gurky = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.id == 27241 and f:IsVisible() end)
	local before = counts.W or 0
	gurky.__scripts.OnClick(gurky)
	tick(0.5)
	assert((counts.W or 0) == before, "sources asked for a pet the catalog lacks")
	assert(textShown("Nothing on this realm gives it"), "no 'nothing gives it' for a pet the catalog lacks")
	assert(buttonShown("Summon"), "no Summon button for an owned pet the catalog lacks")
	table.remove(companions.CRITTER)
	J.Fire("COMPANIONS")
	tick(1)
	assert(not textShown("^Gurky$"), "a pet the character no longer has is still listed")
	J.OpenSection("toys")
	tick(1)
	assert(counts.O and counts.O >= 1, "owned toys not asked")
	assert(textShown("^Orb of Deception$") and textShown("^Piccolo of the Flaming Fire$"), "toy rows missing")
	assert(textShown("Collected: |cffffffff2|r / 2"), "toy count wrong (a toy in the bank is collected too)")
	local orb = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.id == 1973 and f:IsVisible() end)
	orb.__scripts.OnClick(orb)
	tick(0.2)
	orb.__scripts.OnDragStart(orb)
	assert(picked == "item:1973", "dragging a toy didn't pick up its item")
	assert(buttonShown("Equip"), "no Equip button for a trinket toy in the bags")
	local use = buttonShown("Equip")
	assert(use:GetParent() == UIParent, "the secure Use button must not sit inside the journal")
	fire("PLAYER_REGEN_DISABLED")
	assert(not buttonShown("Equip"), "Use button not hidden going into combat")
	assert(use:GetNumPoints() == 0, "the hidden Use button still anchored to the journal in combat")
	fire("PLAYER_REGEN_ENABLED")
	assert(buttonShown("Equip"), "Use button not back after combat")
	local piccolo = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.id == 13379 and f:IsVisible() end)
	piccolo.__scripts.OnClick(piccolo)
	tick(0.2)
	assert(not buttonShown("Use") and not buttonShown("Equip"), "a Use button for a toy in the bank")
	assert(textShown("in your bank"), "a toy in the bank isn't said to be there")
end)

step("quests tab: headings, where you are, chains, era, search, filters", function ()
	SlashCmdList.JOURNALQUESTS()
	tick(1)
	assert(J.view.section == "quests", "/quests didn't open the Quests tab")
	assert(counts.G == 1, "headings not asked")
	assert(sent[#sent]:match("^Z:%d+:40$"), "the heading you're in (Westfall) not opened: " .. sent[#sent])
	assert(textShown("^Eastern Kingdoms$") and textShown("^Outland$") and textShown("^Classes$"), "group rows missing")
	assert(textShown("^Westfall"), "zone row missing")
	assert(textShown("Quests done: |cffffffff34|r / 170"), "overall count wrong")
	assert(textShown("%(Part 2"), "chain step missing")
	assert(textShown("Progression stage 8"), "era-locked quest not marked")
	assert(textShown("Needs an earlier quest"), "prerequisite state missing")
	local row = find(function (f) return f.__kind == "Button" and type(rawget(f, "quest")) == "table" and f.quest.id == 167 and f:IsVisible() end)
	row.__scripts.OnClick(row)
	tick(0.5)
	assert(sent[#sent]:match("^QD:%d+:167$"), "quest detail not asked")
	local map = buttonShown("Show giver on map")
	map.__scripts.OnClick(map)
	tick(0.5)
	assert(sent[#sent]:match("^M:%d+:Q:167$"), "giver map flag not asked")
	-- a heading in the tree
	local elwynn = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.heading
		and f.entry.heading.id == 12 and f:IsVisible() end)
	elwynn.__scripts.OnClick(elwynn)
	tick(0.5)
	assert(sent[#sent]:match("^Z:%d+:12$"), "clicking Elwynn didn't ask for its quests")
	assert(JournalCharDB.questTab.heading == 12, "selection not remembered")
	-- collapse a group
	local ek = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.group
		and f.entry.group.key == "E" and f:IsVisible() end)
	ek.__scripts.OnClick(ek)
	assert(not textShown("^Westfall"), "collapsed group still lists its zones")
	ek.__scripts.OnClick(ek)
	-- filters
	JournalCharDB.questTab.onlyAvailable = true
	J.Fire("QUESTS_CHANGED")
	tick(6)
	assert(not textShown("Needs an earlier quest"), "only-available filter")
	JournalCharDB.questTab.onlyAvailable = nil
	-- search
	local box = find(function (f) return f.__kind == "EditBox" and rawget(f, "hint") and f.hint:GetText() == "Search quests" end)
	box:SetText("defias")
	box.__scripts.OnTextChanged(box)
	tick(1)
	assert(sent[#sent]:match("^X:%d+:defias$"), "quest search not asked: " .. sent[#sent])
	assert(textShown("^Search: defias$") and textShown("%(Westfall%)"), "search result without its heading")
	J.OpenSection("dungeons", true)
	tick(0.5)
end)

step("directory tab: class trainer, professions, search, map flag, Town Guide", function ()
	SlashCmdList.JOURNALDIRECTORY()
	tick(1)
	assert(J.view.section == "directory", "/directory didn't open the Directory tab")
	assert(sent[#sent]:match("^N:%d+:C:1$"), "your class trainer not asked first: " .. sent[#sent])
	assert(sent[#sent - 1]:match("^N:%d+:R$"), "your profession skills not asked: " .. sent[#sent - 1])
	assert(textShown("^Warrior trainer$"), "class trainer entry missing")
	assert(textShown("^Ander Germaine"), "nearest trainer not listed")
	assert(textShown("140 yd north%-east"), "distance and direction missing")
	assert(textShown("^Kalimdor$"), "a trainer on another continent without its continent")
	assert(textShown("showing 2 of 75"), "a cut list doesn't say so")
	assert(not textShown("^Pet trainer$"), "hunter-only entry shown to a warrior")
	local row = find(function (f) return f.__kind == "Button" and type(rawget(f, "place")) == "table" and f.place.place == 1 and f:IsVisible() end)
	row.__scripts.OnClick(row)
	tick(0.5)
	assert(sent[#sent]:match("^M:%d+:N:1:914$"), "map flag not asked: " .. sent[#sent])
	assert(chatShown("Flagged on your map"), "map flag answer not printed")
	-- professions are under a group, with your rank
	assert(not textShown("^Tailoring$"), "Profession trainers not collapsed at first")
	local professions = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.group == "professions" and f:IsVisible() end)
	professions.__scripts.OnClick(professions)
	local tailoring = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.skill == 197 and f:IsVisible() end)
	assert(tailoring, "profession entries not shown")
	assert(textShown("Expert"), "your own profession rank missing")
	tailoring.__scripts.OnClick(tailoring)
	tick(0.5)
	assert(sent[#sent]:match("^N:%d+:P:197$"), "profession not asked: " .. sent[#sent])
	assert(textShown("up to Artisan"), "trainer rank missing")
	assert(JournalCharDB.directory.selected == "p197", "selection not remembered")
	-- the More group starts collapsed
	assert(not textShown("^Barber$"), "More group not collapsed")
	professions.__scripts.OnClick(professions)
	assert(textShown("^Tailoring$"), "the picked profession hidden by its collapsed group")
	local more = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.group == "more" and f:IsVisible() end)
	more.__scripts.OnClick(more)
	assert(textShown("^Barber$"), "More group didn't open")
	-- search
	local box = find(function (f) return f.__kind == "EditBox" and rawget(f, "hint") and f.hint:GetText() == "Search name, title or zone" end)
	box:SetText("aldwin")
	tick(1)
	assert(sent[#sent]:match("^N:%d+:S:aldwin$"), "search not asked: " .. sent[#sent])
	assert(textShown("^Search: aldwin$") and textShown("^Aldwin Laughlin"), "search result missing")
	-- picking a category while searching clears the box and asks once
	local before = counts.N
	local bank = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.category == 7 and f:IsVisible() end)
	bank.__scripts.OnClick(bank)
	tick(1)
	assert(box:GetText() == "", "picking a category didn't clear the search")
	assert(counts.N == before + 1, "a category picked while searching was asked " .. (counts.N - before) .. " times")
	assert(sent[#sent]:match("^N:%d+:C:7$"), "bank not asked: " .. sent[#sent])
	-- a long search with a non-ASCII letter on the cut is cut before that letter
	box:SetText(string.rep("a", 63) .. "\195\164")
	tick(1)
	assert(sent[#sent]:match("^N:%d+:S:" .. string.rep("a", 63) .. "$"), "search cut inside a character: " .. sent[#sent])
	box:SetText("")
	tick(1)
	-- the Town Guide spell: the server says OPEN, which toggles the tab
	reply("OPEN:7:directory")
	tick(0.2)
	assert(sent[#sent] == "OPENED:7", "OPEN not answered: " .. sent[#sent])
	assert(not JournalFrame:IsShown(), "OPEN didn't close the tab that was shown")
	reply("OPEN:8:directory")
	tick(0.5)
	assert(JournalFrame:IsShown() and J.view.section == "directory", "OPEN didn't open the tab")
	-- .find <words>
	J.OpenSection("dungeons", true)
	tick(0.5)
	before = counts.N
	reply("OPEN:9:directory:aldwin laughlin")
	tick(1)
	assert(J.view.section == "directory", ".find didn't open the tab")
	assert(sent[#sent]:match("^N:%d+:S:aldwin laughlin$"), ".find words not searched: " .. sent[#sent])
	assert(box:GetText() == "aldwin laughlin", ".find words not in the search box")
	-- the skills and the search; not the remembered category first
	assert(counts.N == before + 2, ".find opening the tab asked " .. (counts.N - before) .. " times")
	box:SetText("")
	J.OpenSection("dungeons", true)
	tick(0.5)
end)

step("lore tab: zones, entries, reading, discovery banner", function ()
	SlashCmdList.JOURNALLORE()
	tick(1)
	assert(J.view.section == "lore", "/lore didn't open the Lore tab")
	assert(textShown("^Lore found:"), "lore count missing")
	assert(textShown("^Elwynn Forest$") and textShown("^Goldshire$"), "zone or its entries missing")
	assert(textShown("^Places$") and textShown("^People$"), "kind headings missing")
	assert(sent[#sent]:match("^V:%d+:12000$"), "zone overview not opened first: " .. sent[#sent])
	assert(textShown("^Green hills, old forest%.$"), "overview text not shown")
	-- an undiscovered entry says how it's found and never asks for its text
	local before = counts.V or 0
	local fargodeep = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.entry
		and f.entry.entry.id == 12002 and f:IsVisible() end)
	fargodeep.__scripts.OnClick(fargodeep)
	tick(0.5)
	assert((counts.V or 0) == before, "undiscovered entry's text asked for")
	assert(textShown("Explore Fargodeep Mine to learn more"), "hint not shown")
	-- a new entry: marked New until read
	assert(textShown("New"), "a found entry isn't marked New")
	local goldshire = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.entry
		and f.entry.entry.id == 12001 and f:IsVisible() end)
	goldshire.__scripts.OnClick(goldshire)
	tick(0.5)
	assert(textShown("^The town at the crossroads, with an inn%.\n\nLion's Pride1066 1066%.$"), "pieces not joined and unescaped, or read as numbers")
	assert(JournalCharDB.loreRead[12001], "reading it didn't mark it read")
	-- a discovery while playing: the banner, which opens the entry
	J.OpenSection("dungeons", true)
	tick(0.5)
	reply("LN:0:12010:12:2:Marshal Dughan")
	tick(0.2)
	assert(JournalLoreBanner:IsShown() and textShown("^Marshal Dughan$"), "discovery banner not shown")
	-- with DragonUI, its level-up card (no backdrop, the icon ringed) instead of the dialog box
	if DragonUI then
		assert(not rawget(JournalLoreBanner, "__backdrop") and JournalLoreBanner.iconBack, "banner not in DragonUI's look")
	else
		assert(rawget(JournalLoreBanner, "__backdrop"), "banner lost the stock dialog box")
	end
	JournalLoreBanner.__scripts.OnClick(JournalLoreBanner, "LeftButton")
	tick(1)
	assert(J.view.section == "lore", "the banner didn't open the Lore tab")
	assert(sent[#sent]:match("^V:%d+:12010$"), "the banner's entry not opened: " .. sent[#sent])
	-- banners queue, and go away by themselves
	reply("LN:0:12011:12:2:Hogger")
	reply("LN:0:14000:14:0:Durotar")
	tick(0.2)
	assert(textShown("^Hogger$"), "first queued banner not shown")
	tick(6)
	assert(textShown("^Durotar$"), "second queued banner not shown")
	tick(6)
	assert(not JournalLoreBanner:IsShown(), "banner didn't go away")
	SlashCmdList.JOURNALLORE("banner")
	reply("LN:0:12002:12:1:Fargodeep Mine")
	tick(0.2)
	assert(not JournalLoreBanner:IsShown(), "/lore banner didn't turn it off")
	SlashCmdList.JOURNALLORE("banner")
	-- the Library: the books you've read, pages joined, read again
	SlashCmdList.JOURNALLORE("library")
	tick(1)
	assert(J.view.section == "lore", "/lore library didn't open the Lore tab")
	assert(textShown("Library$"), "Library row missing")
	assert(sent[#sent]:match("^P:%d+:2002$") or sent[#sent]:match("^P:%d+:1001$"), "no book opened: " .. sent[#sent])
	local kaldorei = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.book
		and f.entry.book.id == 1001 and f:IsVisible() end)
	assert(kaldorei, "book missing from the shelf")
	kaldorei.__scripts.OnClick(kaldorei)
	tick(0.5)
	assert(textShown("^|cffffd200Page 1|r\n\nLong ago, the night elves%.\n\nHello Tester%.\n\n|cffffd200Page 2|r\n\nIt fell in 10000%.$"),
		"pages not joined in order, placeholders not filled in, or read as numbers")
	assert(textShown("^Read in Stormwind City$"), "where it was read missing")
	assert(JournalCharDB.loreRead.b1001, "reading a book didn't mark it read")
	-- an empty Library, then back to a zone: the zone's entry shows again
	local elwynn = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.zone
		and f.entry.zone.id == 12 and f:IsVisible() end)
	elwynn.__scripts.OnClick(elwynn)
	tick(0.5)
	local function loreText() return textShown("^The town at the crossroads") or textShown("^Green hills, old forest%.$") end
	assert(loreText(), "Elwynn's entry not reopened")
	emptyLibrary = true
	tick(6) -- past the shelf's few seconds of grace
	local libraryRow = find(function (f) return f.__kind == "Button" and type(rawget(f, "entry")) == "table" and f.entry.zone
		and f.entry.zone.library and f:IsVisible() end)
	libraryRow.__scripts.OnClick(libraryRow)
	tick(1.5)
	assert(textShown("^Your library is empty"), "empty Library message missing")
	emptyLibrary = false
	elwynn.__scripts.OnClick(elwynn)
	tick(0.5)
	assert(loreText() and not textShown("^Your library is empty"), "the reader stayed blank after the empty Library")
	-- a book read while playing: its banner opens it
	J.OpenSection("dungeons", true)
	tick(0.5)
	reply("BN:0:2002:A Letter")
	tick(0.2)
	assert(textShown("^Added to your library$") and textShown("^A Letter$"), "book banner not shown")
	JournalLoreBanner.__scripts.OnClick(JournalLoreBanner, "LeftButton")
	tick(1)
	-- (its pages were read before and kept: no second request)
	assert(J.view.section == "lore" and JournalCharDB.loreTab.book == 2002, "the banner's book not opened")
	J.OpenSection("dungeons", true)
	tick(0.5)
end)

step("another addon's tab", function ()
	local built, shownCount = 0, 0
	Journal.RegisterTab({ key = "beasts", name = "Beasts", order = 60,
		build = function (panel) built = built + 1; panel.label = panel:CreateFontString(); panel.label:SetText("Field Guide here") end,
		onShow = function () shownCount = shownCount + 1 end })
	assert(Journal.OpenTab("beasts"), "OpenTab failed")
	tick(0.5)
	assert(built == 1 and shownCount == 1, "build/onShow not called once")
	J.OpenSection("beasts", true)
	assert(shownCount == 2, "clicking the shown tab again didn't run its onShow")
	assert(textShown("Field Guide here"), "registered panel not shown")
	assert(JournalFrame.title:GetText() == "Beasts", "window title not the tab's")
	J.OpenSection("dungeons", true)
	tick(0.5)
	assert(not textShown("Field Guide here"), "registered panel still shown")
	assert(J.view.page == "home", "Dungeons tab didn't go home")
end)

step("DragonUI's Pets & Mounts button opens the journal", function ()
	assert(type(ToggleCollectionsJournal) == "function", "ToggleCollectionsJournal not defined")
	JournalFrame:Hide()
	ToggleCollectionsJournal()
	tick(1)
	assert(JournalFrame:IsShown() and (J.view.section == "mounts" or J.view.section == "pets"),
		"the button didn't open Mounts or Pets: " .. tostring(J.view.section))
	ToggleCollectionsJournal()
	assert(not JournalFrame:IsShown(), "a second click didn't close the journal")
	ToggleCollectionsJournal(2)
	tick(1)
	assert(JournalFrame:IsShown() and J.view.section == "pets", "tab 2 didn't open Pets")
	J.OpenSection("dungeons")
	ToggleCollectionsJournal()
	tick(1)
	assert(J.view.section == "pets", "from Dungeons the button didn't go back to Pets")
	JournalFrame:Hide()
end)

step("slash commands", function ()
	SlashCmdList.JOURNAL("help")
	SlashCmdList.JOURNAL("minimap")
	assert(JournalDB.minimap.hide, "minimap toggle")
	SlashCmdList.JOURNAL("minimap")
	SlashCmdList.JOURNAL("reset")
	SlashCmdList.JOURNAL("smite")
	tick(1)
end)

print(errors == 0 and "OK" or (errors .. " error(s)"))
os.exit(errors == 0 and 0 or 1)
