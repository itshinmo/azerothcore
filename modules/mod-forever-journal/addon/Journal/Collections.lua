-- The Mounts, Pets and Toys tabs, laid out like retail's Collections: a list on the left (search,
-- filters, collected count) and on the right the selected one's model, a Summon or Use button
-- and where it comes from. Data from CollectionData.lua.

local J = Journal
local setShown = J.SetShown
local band = bit.band

local LIST_WIDTH = 300
local ROW_HEIGHT = 40
local ROWS = 11
-- With DragonUI: its Mounts window's 46px row plate (the height the art is cut at), so fewer rows.
local DUI_ROW_HEIGHT = 46
local DUI_ROWS = 10
local DUI_ROW_ICON = 38
local DUI_INFO_ICON = 40

local SOURCE_ICONS = {
	V = "Interface\\GossipFrame\\VendorGossipIcon",
	D = "Interface\\Icons\\INV_Misc_Bag_07",
	G = "Interface\\Icons\\INV_Box_02",
	P = "Interface\\Icons\\INV_Misc_Bag_11",
	F = "Interface\\Icons\\Trade_Fishing",
	R = "Interface\\Icons\\INV_Misc_Map02",
	Q = "Interface\\GossipFrame\\AvailableQuestIcon",
	A = "Interface\\AchievementFrame\\UI-Achievement-TinyShield",
	T = "Interface\\GossipFrame\\TrainerGossipIcon",
	N = "Interface\\GossipFrame\\GossipGossipIcon",
	S = "Interface\\Icons\\INV_Misc_Coin_16",
	B = "Interface\\Icons\\INV_Misc_Coin_02",
	U = "Interface\\GossipFrame\\TabardGossipIcon",
}
local BOSS_ICON = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local MORE_NAMES = { V = "vendors", D = "creatures", G = "chests", P = "pockets", F = "fishing spots", I = "containers",
	Q = "quests", A = "achievements", C = "recipes", T = "trainers", S = "shop offers", B = "Black Market listings",
	U = "guild rewards" }
-- Guild reputation ranks (mod-guild-levels uses the standing ranks, 7 = Exalted).
local RANK_NAMES = { [0] = "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

-- The pet that comes out on its own, kept by the realm's pet loot module (mod-pet-loot) under its
-- own prefix: "G" asks, "S:<spell>" picks (0 = off); it answers "A:<spell>" or "OFF". J.autoSummon
-- stays nil until it answers, so a realm without it never shows the box.
local AUTO_PREFIX = "PETLOOT"

local function sendAutoSummon(msg)
	SendAddonMessage(AUTO_PREFIX, msg, "WHISPER", UnitName("player"))
end

local autoEvents = CreateFrame("Frame")
autoEvents:RegisterEvent("CHAT_MSG_ADDON")
autoEvents:SetScript("OnEvent", function (_, _, prefix, message, _, sender)
	if prefix ~= AUTO_PREFIX or sender ~= UnitName("player") then return end
	local spell = message:match("^A:(%d+)$")
	if spell then
		J.autoSummon = tonumber(spell)
	elseif message == "OFF" then
		J.autoSummon = nil
	else
		return
	end
	J.Fire("AUTO_SUMMON")
end)
J.On("LOGIN", function () J.After(3, function () sendAutoSummon("G") end) end)

local function lockText(state)
	return "|cffff5555Progression stage " .. state .. "|r"
end

-- "12 [icon] 2 [icon]" for an extended cost's "id*count/id*count".
local function itemCosts(text)
	if not text or text == "-" or text == "" then return nil end
	local parts = {}
	for idText, count in tostring(text):gmatch("(%d+)%*(%d+)") do
		local id = tonumber(idText)
		local icon = J.ItemIcon(id)
		if not GetItemInfo(id) then J.QueryItem(id) end
		table.insert(parts, count .. " |T" .. icon .. ":14:14:0:0|t")
	end
	return #parts > 0 and table.concat(parts, " ") or nil
end

local function costText(s)
	local parts = {}
	if s.copper and s.copper > 0 then table.insert(parts, J.Money(s.copper)) end
	if s.honor and s.honor > 0 then
		local faction = UnitFactionGroup and UnitFactionGroup("player") or "Alliance"
		table.insert(parts, J.Number(s.honor) .. " |TInterface\\PVPFrame\\PVP-Currency-" .. faction .. ":14:14:0:0|t")
	end
	if s.arena and s.arena > 0 then
		table.insert(parts, J.Number(s.arena) .. " |TInterface\\PVPFrame\\PVP-ArenaPoints-Icon:14:14:0:0|t")
	end
	local items = itemCosts(s.items)
	if items then table.insert(parts, items) end
	return #parts > 0 and table.concat(parts, "  ") or nil
end

local function className(id)
	local token = J.CLASS_TOKENS[id or 0]
	return token and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token] or token
end

-- The title, the line under it and the icon of a source row. live: J.LoadLive's answer, once it
-- is in, for the coin shop and Black Market rows.
local function describe(s, live)
	local title, detail, icon = "", nil, SOURCE_ICONS[s.kind]
	local PER = { D = "kills", G = "chests", P = "pockets", F = "catches", I = "" }
	local chance = s.chance and s.chance > 0 and J.ChanceText(s.chance, PER[s.kind]) or nil
	if s.kind == "V" then
		title = "Vendor: " .. s.name
		local bits = {}
		if s.where ~= "" then table.insert(bits, s.where) end
		local cost = costText(s)
		if cost then table.insert(bits, cost) end
		if s.event ~= "" then table.insert(bits, "|cff66ccffDuring " .. s.event .. "|r") end
		detail = table.concat(bits, " - ")
	elseif s.kind == "D" then
		title = (s.instance and s.instance > 0 and s.boss and s.boss > 0 and "Boss: " or "Drop: ") .. s.name
			.. (s.rare and " |cffc0c0c0(Rare)|r" or "")
		if s.instance and s.instance > 0 then icon = BOSS_ICON end
		detail = (s.where ~= "" and (s.where .. " - ") or "") .. (s.tabs and s.tabs ~= "" and ("|cffffd200" .. s.tabs .. "|r - ") or "")
			.. (chance or "")
	elseif s.kind == "G" then
		title = "Chest: " .. s.name
		detail = (s.where ~= "" and (s.where .. " - ") or "") .. (s.tabs and s.tabs ~= "" and ("|cffffd200" .. s.tabs .. "|r - ") or "")
			.. (chance or "")
	elseif s.kind == "P" then
		title = "Pickpocket: " .. s.name
		detail = (s.where ~= "" and (s.where .. " - ") or "") .. (chance or "")
	elseif s.kind == "F" then
		title = "Fishing: " .. s.name
		detail = chance
	elseif s.kind == "I" then
		local name = GetItemInfo(s.item)
		if not name then J.QueryItem(s.item) end
		title = "Contained in: " .. (name or ("item " .. s.item))
		detail = chance
		icon = J.ItemIcon(s.item)
	elseif s.kind == "R" then
		title = "World drop"
		detail = "Drops from many creatures around the world"
	elseif s.kind == "Q" then
		title = "Quest: " .. s.name
		local bits = {}
		if s.giver ~= "" then table.insert(bits, "from " .. s.giver) end
		if s.where ~= "" then table.insert(bits, s.where) end
		if s.level and s.level > 0 then table.insert(bits, "level " .. s.level) end
		if s.faction == 1 then table.insert(bits, "|cff4080ffAlliance|r") elseif s.faction == 2 then table.insert(bits, "|cffff4040Horde|r") end
		detail = table.concat(bits, ", ")
	elseif s.kind == "A" then
		local ok, _, name, points, _, _, _, _, description, _, achIcon = pcall(GetAchievementInfo, s.achievement)
		title = "Achievement: " .. (ok and name or ("#" .. s.achievement))
		detail = ok and description or nil
		if ok and points and points > 0 then detail = (detail and (detail .. " ") or "") .. "(" .. points .. " points)" end
		if ok and achIcon then icon = achIcon end
	elseif s.kind == "C" then
		local recipe, _, spellIcon = GetSpellInfo(s.spell)
		title = "Profession: " .. s.name .. (s.rank and s.rank > 0 and (" (" .. s.rank .. ")") or "")
		local bits = { recipe }
		if s.recipe then
			local name = GetItemInfo(s.recipe)
			if not name then J.QueryItem(s.recipe) end
			table.insert(bits, "from " .. (name or "a recipe"))
		elseif recipe then
			table.insert(bits, "from a trainer")
		end
		if s.reqSpell then
			local spec = GetSpellInfo(s.reqSpell)
			if spec then table.insert(bits, "|cffff8020needs " .. spec .. "|r") end
		end
		detail = table.concat(bits, " - ")
		icon = spellIcon or "Interface\\Icons\\Trade_Engineering"
	elseif s.kind == "T" then
		local cls = className(s.class)
		title = "Trainer: " .. (cls and (cls .. " trainers") or s.name)
		local bits = {}
		if s.level and s.level > 0 then table.insert(bits, "level " .. s.level) end
		if s.copper and s.copper > 0 then table.insert(bits, J.Money(s.copper)) end
		if s.name ~= "" then table.insert(bits, s.name .. (s.where ~= "" and (", " .. s.where) or "")) end
		if s.trainers and s.trainers > 1 then table.insert(bits, "and " .. (s.trainers - 1) .. " more") end
		detail = table.concat(bits, " - ")
	elseif s.kind == "S" then
		title = "Coin Shop: " .. J.Number(s.coins) .. " |T" .. J.ItemIcon(J.BOSS_COIN) .. ":14:14:0:0|t coins"
		icon = J.ItemIcon(J.BOSS_COIN)
		local bits = { "In the launcher's Shop tab" }
		if live and live.coins then
			-- The shop spends the wallet only: coins in the bags go in at Pix Xizzix first.
			local text = "you have " .. J.Number(live.coins) .. (live.bags and live.bags > 0 and (" (+" .. J.Number(live.bags) .. " in your bags)") or "")
			table.insert(bits, (live.coins >= s.coins and "|cff66ff66" or "|cffffd200") .. text .. "|r")
			if live.coins < s.coins and live.coins + (live.bags or 0) >= s.coins then
				table.insert(bits, "put your bag coins in your wallet with Pix Xizzix in Booty Bay")
			end
		else
			table.insert(bits, "coins come from dungeon and raid bosses")
		end
		detail = table.concat(bits, " - ")
	elseif s.kind == "B" then
		title = "Black Market: " .. s.name
		local bits = {}
		if s.where ~= "" then table.insert(bits, s.where) end
		if live and live.bid then
			table.insert(bits, "|cff66ff66Up for bid now: " .. J.Money(live.bid) .. (live.bids > 0 and "" or " to start")
				.. ", " .. J.Duration(live.left) .. " left|r")
		else
			table.insert(bits, "bids from " .. J.Money(s.copper) .. " on the days it's up for auction")
		end
		detail = table.concat(bits, " - ")
	elseif s.kind == "U" then
		title = "Guild Vendor: " .. s.name .. (s.vendors and s.vendors > 1 and " |cffc0c0c0(every capital)|r" or "")
		local bits = {}
		if s.where ~= "" then table.insert(bits, s.where) end
		table.insert(bits, "guild level " .. s.guildLevel .. ", " .. (RANK_NAMES[s.rank] or ("rank " .. s.rank)) .. " with your guild")
		if s.copper and s.copper > 0 then table.insert(bits, J.Money(s.copper)) end
		if s.faction == 1 then table.insert(bits, "|cff4080ffAlliance|r") elseif s.faction == 2 then table.insert(bits, "|cffff4040Horde|r") end
		detail = table.concat(bits, " - ")
	elseif s.kind == "N" then
		title = s.text
	elseif s.kind == "+" then
		title = "|cff9d9d9d...and " .. s.more .. " more " .. (MORE_NAMES[s.of] or "sources") .. "|r"
		icon = nil
	end
	if (s.reqState or 0) > 0 and J.Has(J.HELLO_PROGRESSION) and s.reqState > (J.state or 18) then
		-- The shop opens an offer once any character of the account gets there.
		detail = (detail and detail ~= "" and (detail .. " - ") or "") .. lockText(s.reqState)
			.. (s.kind == "S" and "|cffff5555 on any of your characters|r" or "")
	end
	return title, detail, icon
end

J.DescribeSource = describe

-- DragonUI's Mounts and Pets window, when it's there: its art for the rows and the selected one,
-- and its favourites, so a star set here shows there and the other way round.
local function dragonCollections()
	if not J.Dragon() then return nil end
	local CO = _G.DragonUI and _G.DragonUI.Collections
	if CO and CO.TEX and CO.ROW_COORDS and CO.FAV_COORD and CO.MODEL_BG_COORD and CO.IsFavorite and CO.ToggleFavorite then
		return CO
	end
end

-----------------------------------------
-- one tab

local function buildTab(kind, panel)
	local info = J.KINDS[kind]
	local state = { selected = nil, entries = {}, catalog = nil }
	local CO = dragonCollections()
	-- Favourites are DragonUI's, per companion kind; toys have none.
	local favKind = CO and info.companion
	local rowHeight, rowCount = ROW_HEIGHT, ROWS
	if CO then rowHeight, rowCount = DUI_ROW_HEIGHT, DUI_ROWS end

	-- Keyed by the creature the client lists the companion with, as DragonUI's window does; only
	-- one you own can be a favourite.
	local function favoriteId(e)
		local c = favKind and J.Companion(kind, e)
		return c and c.creature
	end
	local function isFavorite(e)
		local id = favoriteId(e)
		return id ~= nil and CO.IsFavorite(favKind, id)
	end

	local status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	status:SetPoint("CENTER", panel, "CENTER", 0, 20)
	status:SetWidth(520)
	local statusSub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	statusSub:SetPoint("TOP", status, "BOTTOM", 0, -10)
	statusSub:SetWidth(520)

	local body = CreateFrame("Frame", nil, panel)
	body:SetAllPoints(panel)

	-- left: search, filters, count, list

	local left = CreateFrame("Frame", nil, body)
	left:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
	left:SetWidth(LIST_WIDTH)

	local search = J.CreateEditBox(left, LIST_WIDTH - 104)
	search:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -4)
	search.hint = search:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	search.hint:SetPoint("LEFT", search, "LEFT", 2, 0)
	search.hint:SetText("Search " .. info.name:lower())
	search.hint:SetTextColor(0.6, 0.6, 0.6)

	local filter = J.CreateDropdown(left, 90, function ()
		local f = J.Filters(kind)
		local function toggle(key) return function () f[key] = not f[key]; J.Fire("COLLECTION_FILTER", kind) end end
		local items = {
			{ text = "Collected", checked = f.collected, keepShownOnClick = true, func = toggle("collected") },
			{ text = "Not collected", checked = f.missing, keepShownOnClick = true, func = toggle("missing") },
			{ text = "Only usable by me", checked = f.usable, keepShownOnClick = true, func = toggle("usable") },
		}
		if J.Has(J.HELLO_PROGRESSION) then
			table.insert(items, { text = "Hide locked by progression", checked = f.hideLocked, keepShownOnClick = true,
				func = toggle("hideLocked") })
		end
		table.insert(items, { text = "Show unobtainable", checked = f.unobtainable, keepShownOnClick = true,
			tooltipTitle = "Show unobtainable", tooltipText = "Also list the ones nothing on this realm gives yet.",
			func = toggle("unobtainable") })
		if kind == "mounts" then
			table.insert(items, { text = "Mount type", isTitle = true, notCheckable = true })
			for _, t in ipairs({ { nil, "All" }, { "flying", "Flying" }, { "ground", "Ground" } }) do
				table.insert(items, { text = t[2], checked = f.mountType == t[1], func = function ()
					f.mountType = t[1]
					J.Fire("COLLECTION_FILTER", kind)
				end })
			end
		end
		table.insert(items, { text = "Sort by", isTitle = true, notCheckable = true })
		for _, s in ipairs({ { nil, "Name" }, { "newest", "Newest first" }, { "oldest", "Oldest first" } }) do
			table.insert(items, { text = s[2], checked = f.sort == s[1],
				tooltipTitle = s[1] and s[2] or nil,
				tooltipText = s[1] and ("By when you first had it. The journal starts counting the first time it sees "
					.. "your collection: what you had before then is the oldest, in name order.") or nil,
				func = function ()
					f.sort = s[1]
					J.Fire("COLLECTION_FILTER", kind)
				end })
		end
		table.insert(items, { text = "Sources (none ticked: all)", isTitle = true, notCheckable = true })
		for _, src in ipairs(J.SOURCE) do
			table.insert(items, { text = src.name, checked = f.sources[src.bit] and true or false, keepShownOnClick = true,
				func = function ()
					f.sources[src.bit] = not f.sources[src.bit] or nil
					J.Fire("COLLECTION_FILTER", kind)
				end })
		end
		return items
	end)
	filter:SetPoint("LEFT", search, "RIGHT", 6, 0)
	filter:SetText("Filter")

	local count = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	count:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -30)
	count:SetPoint("RIGHT", left, "RIGHT", -8, 0)
	count:SetJustifyH("LEFT")

	-- DragonUI's Random Favorite, from its window's top band: the same picker, and dragged it is
	-- the same macro.
	if favKind and CO.SummonRandomFavorite then
		local random = CreateFrame("Button", nil, left)
		random:SetSize(20, 20)
		random:SetPoint("TOPRIGHT", left, "TOPRIGHT", -6, -25)
		local icon = random:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints(random)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:SetTexture(CO.RandomIcon and CO.RandomIcon[favKind] or "Interface\\Icons\\INV_Misc_Dice_01")
		random:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
		random:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		local caption = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		caption:SetPoint("RIGHT", random, "LEFT", -5, 0)
		caption:SetText("Random favorite")
		count:SetPoint("RIGHT", caption, "LEFT", -6, 0)
		random:SetScript("OnClick", function ()
			CO.SummonRandomFavorite(favKind)
			J.Debounce("collection-companions", 0.5, function () J.Fire("COMPANIONS") end)
		end)
		if CO.EnsureRandomMacro then
			random:RegisterForDrag("LeftButton")
			random:SetScript("OnDragStart", function ()
				local index = CO.EnsureRandomMacro(favKind)
				if index then PickupMacro(index) end
			end)
		end
		J.SetTooltip(random, function (tip)
			tip:SetText(kind == "mounts" and "Summon Random Favorite Mount" or "Summon Random Favorite Pet", 1, 1, 1)
			tip:AddLine(kind == "mounts" and "Summons and dismisses a favorite mount that is usable in the current area."
				or "Summons and dismisses a favorite pet.", 1, 0.82, 0, true)
			tip:AddLine("With no favorites it picks from your whole collection.", 1, 0.82, 0, true)
			if CO.EnsureRandomMacro then tip:AddLine("Drag to place it on an action bar.", 0.6, 0.8, 1, true) end
		end, "ANCHOR_LEFT")
	end

	local listInset = J.CreateInset(left)
	listInset:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -46)
	listInset:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", 0, 0)

	local scrollName = J.UniqueName("CollectionScroll")
	local scroll = CreateFrame("ScrollFrame", scrollName, listInset, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", listInset, "TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", listInset, "BOTTOMRIGHT", -26, 4)
	J.SkinScrollBar(scroll, scrollName)

	local empty = listInset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER", listInset, "CENTER")
	empty:SetWidth(LIST_WIDTH - 30)

	-- Dragged onto an action bar like the stock companion buttons: one you own, by the index
	-- the client lists it at right now; a toy as its item.
	local function pickup(e)
		if not (e and e.mine) then return end
		if kind == "toys" then
			PickupItem(e.id)
		else
			local c = J.CompanionNow(kind, e)
			if c then PickupCompanion(info.companion, c.index) end
		end
	end

	local rows = {}
	local render

	-- One the catalog leaves out but the character has sits in its extras (CollectionData.lua).
	local function entryById(id)
		local c = state.catalog
		return c and (c.byId[id] or (c.extras and c.extras[id])) or nil
	end

	local function select(e)
		state.selected = e
		JournalCharDB.collectionSelected = JournalCharDB.collectionSelected or {}
		JournalCharDB.collectionSelected[kind] = e and e.id or nil
		render()
	end

	for i = 1, rowCount do
		local b = CreateFrame("Button", nil, listInset)
		b:SetHeight(rowHeight)
		b:SetPoint("TOPLEFT", listInset, "TOPLEFT", 6, -6 - (i - 1) * rowHeight)
		b:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
		if CO then
			-- DragonUI's row: plate, gold selected plate over the icon, its hover, a favourite star on
			-- the icon's corner and a faint faction crest.
			local function plate(layer, coords, sublevel)
				local t = b:CreateTexture(nil, layer, nil, sublevel)
				t:SetTexture(CO.TEX.rows)
				t:SetTexCoord(unpack(coords))
				t:SetAllPoints(b)
				return t
			end
			plate("BACKGROUND", CO.ROW_COORDS.background)
			b.selectedBg = plate("ARTWORK", CO.ROW_COORDS.selected, 1)
			plate("HIGHLIGHT", CO.ROW_COORDS.highlight)
			b.icon = b:CreateTexture(nil, "BORDER")
			b.icon:SetSize(DUI_ROW_ICON, DUI_ROW_ICON)
			b.icon:SetPoint("LEFT", b, "LEFT", 8, 0)
			b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			b.star = b:CreateTexture(nil, "OVERLAY")
			b.star:SetSize(20, 20)
			b.star:SetPoint("TOPLEFT", b.icon, "TOPLEFT", -7, 7)
			b.star:SetTexture(CO.TEX.favorite)
			b.star:SetTexCoord(unpack(CO.FAV_COORD))
			b.star:Hide()
			if CO.TEX.faction and CO.FACTION_COORDS then
				b.faction = b:CreateTexture(nil, "ARTWORK")
				b.faction:SetSize(32, 36)
				b.faction:SetPoint("RIGHT", b, "RIGHT", -6, 0)
				b.faction:SetTexture(CO.TEX.faction)
				b.faction:SetAlpha(0.55)
				b.faction:Hide()
			end
		else
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetSize(32, 32)
			b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
		end
		b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", CO and 10 or 8, CO and -4 or -2)
		b.name:SetPoint("RIGHT", b, "RIGHT", -22, 0)
		b.name:SetJustifyH("LEFT")
		b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -2)
		b.sub:SetPoint("RIGHT", b, "RIGHT", -22, 0)
		b.sub:SetJustifyH("LEFT")
		b.lock = b:CreateTexture(nil, "OVERLAY")
		b.lock:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
		b.lock:SetSize(16, 16)
		-- Over the crest's middle with DragonUI.
		b.lock:SetPoint("RIGHT", b, "RIGHT", CO and -14 or -2, 0)
		if not CO then
			b.selectedBg = b:CreateTexture(nil, "BACKGROUND")
			b.selectedBg:SetAllPoints(b)
			b.selectedBg:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
			b.selectedBg:SetBlendMode("ADD")
			b.selectedBg:SetVertexColor(1, 0.82, 0, 0.5)
			local hl = b:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints(b)
			hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
			hl:SetBlendMode("ADD")
		end
		b:SetScript("OnClick", function (self)
			local e = self.entry
			if not e then return end
			if IsModifiedClick("CHATLINK") then
				local link = kind == "toys" and J.ItemLink(e.id, J.EntryName(kind, e), e.quality)
					or (GetSpellLink and GetSpellLink(e.id))
				if link and not ChatEdit_InsertLink(link) then ChatFrame_OpenChat(link) end
				return
			end
			select(e)
		end)
		b:RegisterForDrag("LeftButton")
		b:SetScript("OnDragStart", function (self) pickup(self.entry) end)
		b:SetScript("OnEnter", function (self)
			local e = self.entry
			if not e then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(kind == "toys" and ("item:" .. e.id) or ("spell:" .. e.id))
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function () GameTooltip:Hide() end)
		rows[i] = b
	end

	local function summary(e)
		local parts = {}
		for _, src in ipairs(J.SOURCE) do
			if band(e.sources, src.bit) ~= 0 then table.insert(parts, src.name) end
		end
		if band(e.flags, J.ENTRY.UNOBTAINABLE) ~= 0 then return "|cff9d9d9dUnobtainable|r" end
		return table.concat(parts, ", ")
	end

	local function renderList()
		local offset = FauxScrollFrame_GetOffset(scroll)
		for i = 1, rowCount do
			local b = rows[i]
			local e = state.entries[offset + i]
			b.entry = e
			if e then
				b.icon:SetTexture(J.EntryIcon(kind, e))
				b.icon:SetDesaturated(not e.mine)
				if CO then b.icon:SetAlpha(e.mine and 1 or 0.35) end
				b.name:SetText(J.EntryName(kind, e) or ("item " .. e.id))
				if e.mine then
					local r, g, bl = J.QualityColor(e.quality)
					b.name:SetTextColor(r, g, bl)
				else
					b.name:SetTextColor(0.6, 0.6, 0.6)
				end
				local locked = J.EntryLocked(e)
				b.sub:SetText(locked and lockText(e.reqState) or summary(e))
				setShown(b.lock, locked)
				setShown(b.selectedBg, state.selected == e)
				if b.star then setShown(b.star, isFavorite(e)) end
				if b.faction then
					-- DragonUI's crest sheet: 0 is the Horde's, 1 the Alliance's.
					local side = band(e.flags, J.ENTRY.HORDE) ~= 0 and 0 or band(e.flags, J.ENTRY.ALLIANCE) ~= 0 and 1 or nil
					local coords = side and CO.FACTION_COORDS[side]
					if coords then b.faction:SetTexCoord(unpack(coords)) end
					setShown(b.faction, coords ~= nil)
				end
				b:Show()
			else
				b:Hide()
			end
		end
		FauxScrollFrame_Update(scroll, #state.entries, rowCount, rowHeight)
	end

	scroll:SetScript("OnVerticalScroll", function (self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, rowHeight, renderList)
	end)

	-- right: the selected one

	local right = J.CreateInset(body)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
	right:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)

	local bigIcon = right:CreateTexture(nil, "ARTWORK")
	bigIcon:SetSize(40, 40)
	local title = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetJustifyH("LEFT")
	local star
	if CO then
		-- DragonUI's pane: the red and gold backdrop behind all of it, the icon in its gold ornament
		-- (where DragonUI pins it: 6px in, the icon hung off the ornament's opening) and the star.
		local backdrop = right:CreateTexture(nil, "BACKGROUND", nil, -4)
		backdrop:SetPoint("TOPLEFT", right, "TOPLEFT", 4, -4)
		backdrop:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -4, 4)
		backdrop:SetTexture(CO.TEX.modelBg)
		backdrop:SetTexCoord(unpack(CO.MODEL_BG_COORD))
		bigIcon:SetPoint("TOPLEFT", right, "TOPLEFT", 24, -21)
		bigIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local layout = _G.DragonUI.LayoutGoldIconFrame
		if layout and _G.DragonUI.GOLD_ICON_FRAME then
			layout(right:CreateTexture(nil, "OVERLAY"), bigIcon, DUI_INFO_ICON)
		end
		title:SetPoint("LEFT", bigIcon, "RIGHT", 14, 8)
		if favKind then
			star = CreateFrame("Button", nil, right)
			star:SetSize(24, 24)
			star:SetPoint("TOPRIGHT", right, "TOPRIGHT", -14, -14)
			star.tex = star:CreateTexture(nil, "ARTWORK")
			star.tex:SetAllPoints(star)
			star.tex:SetTexture(CO.TEX.favorite)
			star.tex:SetTexCoord(unpack(CO.FAV_COORD))
			local glow = star:CreateTexture(nil, "HIGHLIGHT")
			glow:SetAllPoints(star)
			glow:SetTexture(CO.TEX.favorite)
			glow:SetTexCoord(unpack(CO.FAV_COORD))
			glow:SetBlendMode("ADD")
			glow:SetAlpha(0.4)
			J.SetTooltip(star, function (tip)
				tip:SetText("Favorite", 1, 0.82, 0)
				tip:AddLine("Keeps it at the top of the list, here and in DragonUI's window.", 1, 1, 1, true)
			end, "ANCHOR_LEFT")
			title:SetPoint("RIGHT", star, "LEFT", -8, 0)
			star:SetScript("OnClick", function ()
				local id = state.selected and favoriteId(state.selected)
				if not id then return end
				CO.ToggleFavorite(favKind, id)
				PlaySound("igMainMenuOptionCheckBoxOn")
				render()
			end)
		else
			title:SetPoint("RIGHT", right, "RIGHT", -12, 0)
		end
	else
		bigIcon:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -12)
		title:SetPoint("TOPLEFT", bigIcon, "TOPRIGHT", 10, -2)
		title:SetPoint("RIGHT", right, "RIGHT", -12, 0)
	end
	-- The big icon drags onto an action bar too, as the list's rows do.
	local iconDrag = CreateFrame("Button", nil, right)
	iconDrag:SetAllPoints(bigIcon)
	iconDrag:RegisterForDrag("LeftButton")
	iconDrag:SetScript("OnDragStart", function () pickup(state.selected) end)
	J.SetTooltip(iconDrag, function (tip)
		local e = state.selected
		if not e then return end
		tip:SetHyperlink(kind == "toys" and ("item:" .. e.id) or ("spell:" .. e.id))
		if e.mine then tip:AddLine("Drag to place it on an action bar.", 0.6, 0.8, 1, true) end
	end, "ANCHOR_RIGHT")
	local subtitle = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	subtitle:SetPoint("RIGHT", right, "RIGHT", -12, 0)
	subtitle:SetJustifyH("LEFT")

	local SOURCES_HEIGHT = 190

	local model = CreateFrame("PlayerModel", nil, right)
	-- Below the gold ornament's flourishes with DragonUI.
	model:SetPoint("TOPLEFT", right, "TOPLEFT", 8, CO and -86 or -60)
	model:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -8, SOURCES_HEIGHT + 8)
	model:SetScript("OnHide", function (self) self.shownEntry = nil end)
	ModelViewLib.Wire(model, 0.5)
	-- DragonUI's backdrop already runs behind the whole pane.
	if not CO then
		local modelBg = right:CreateTexture(nil, "BACKGROUND", nil, 1)
		modelBg:SetPoint("TOPLEFT", model, "TOPLEFT")
		modelBg:SetPoint("BOTTOMRIGHT", model, "BOTTOMRIGHT")
		modelBg:SetTexture("Interface\\LFGFrame\\UI-LFG-BACKGROUND-QUESTPAPER")
		modelBg:SetTexCoord(0, 0.6, 0, 0.55)
		modelBg:SetVertexColor(0.35, 0.32, 0.3)
	end
	-- Stops short of the Summon button and its Auto-summon check.
	ModelViewLib.AddHint(model, 250)

	-- Toys have no model: their icon and what using them does.
	local toyIcon = right:CreateTexture(nil, "ARTWORK")
	toyIcon:SetSize(96, 96)
	toyIcon:SetPoint("CENTER", model, "CENTER", 0, 30)
	local toyText = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	toyText:SetPoint("TOP", toyIcon, "BOTTOM", 0, -14)
	toyText:SetWidth(380)

	-- Summon (mounts, pets) or Use (toys, a secure button so the item can be used).
	local action = J.CreateButton(right, "Summon", 110, 24)
	action:SetPoint("BOTTOMRIGHT", model, "BOTTOMRIGHT", -6, 6)
	-- The model takes the mouse (drag to turn) and in the client it ends up above this button,
	-- a sibling made after it: clicks on Summon turned the model instead. So the button sits a
	-- level above the model, re-pinned on every render in case the window is re-levelled.
	local auto
	local function raiseAction()
		action:SetFrameLevel(model:GetFrameLevel() + 1)
		if auto then auto:SetFrameLevel(model:GetFrameLevel() + 1) end
	end
	raiseAction()
	action:SetScript("OnClick", function ()
		local e = state.selected
		local c = e and J.CompanionNow(kind, e)
		if not c then return end
		if kind == "mounts" and IsMounted and IsMounted() then
			Dismount()
		elseif c.active then
			DismissCompanion(info.companion)
		else
			CallCompanion(info.companion, c.index)
		end
		J.Debounce("collection-companions", 0.5, function () J.Fire("COMPANIONS") end)
	end)

	-- One not collected yet: make it the character's goal, and the tracker (GoalTracker.lua) shows
	-- where to go for it while they play. Where Summon is for one they have.
	local goalButton = J.CreateButton(right, "Set as goal", 110, 24)
	goalButton:SetPoint("BOTTOMRIGHT", model, "BOTTOMRIGHT", -6, 6)
	goalButton:SetScript("OnClick", function ()
		local e = state.selected
		if not e then return end
		J.SetGoal(kind, not J.GoalIs(kind, e) and e or nil)
	end)
	J.SetTooltip(goalButton, function (tip)
		local e = state.selected
		if e and J.GoalIs(kind, e) then
			tip:SetText("Stop tracking", 1, 1, 1)
			tip:AddLine("Takes it off your screen.", 1, 0.82, 0, true)
		else
			tip:SetText("Set as goal", 1, 1, 1)
			tip:AddLine("Shows it on your screen while you play: where to get it next, and how close you are. "
				.. "Click the tracker to come back here.", 1, 0.82, 0, true)
		end
	end, "ANCHOR_TOP")
	local function syncGoal()
		local e = state.selected
		goalButton:SetFrameLevel(model:GetFrameLevel() + 1)
		local can = e and not e.mine and band(e.flags, J.ENTRY.UNOBTAINABLE) == 0 and J.Usable(e)
		setShown(goalButton, can)
		if can then goalButton:SetText(J.GoalIs(kind, e) and "Stop tracking" or "Set as goal") end
	end

	-- Pets: pick the one that comes out on its own, left of Summon.
	if kind == "pets" then
		auto = J.CreateCheck(right, "Auto-summon")
		auto:SetPoint("RIGHT", action, "LEFT", -(auto.label:GetStringWidth() + 12), 0)
		auto:SetScript("OnClick", function (self)
			local e = state.selected
			if not e then return end
			sendAutoSummon("S:" .. (self:GetChecked() and e.id or 0))
		end)
		J.SetTooltip(auto, function (tip)
			tip:SetText("Auto-summon", 1, 1, 1)
			tip:AddLine("Comes out on its own whenever you have no pet: after logging in, zoning, dying or a flight. "
				.. "Dismiss it and it stays away until you summon a pet again.", 1, 0.82, 0, true)
		end, "ANCHOR_TOP")
		raiseAction()
	end

	-- A secure button makes every frame it sits in protected, and the journal would then be
	-- blocked from closing or switching tabs in combat. So it sits on UIParent, over the
	-- model, and is only moved, shown or hidden out of combat; in combat it isn't there.
	local use
	local function syncUse()
		if not use or InCombatLockdown() then return end
		local e = state.selected
		if e and e.mine and J.ToyInBags(e) and panel:IsVisible() and right:IsVisible() then
			use:SetAttribute("item", "item:" .. e.id)
			-- A trinket (Orb of Deception) is put on first: using it from the bags equips it.
			local equip = IsEquippableItem and IsEquippableItem(e.id) and not (IsEquippedItem and IsEquippedItem(e.id))
			use:SetText(equip and "Equip" or "Use")
			use:ClearAllPoints()
			use:SetPoint("BOTTOMRIGHT", model, "BOTTOMRIGHT", -6, 6)
			use:Show()
		else
			use:Hide()
			use:ClearAllPoints()
		end
	end
	if kind == "toys" then
		use = CreateFrame("Button", J.UniqueName("ToyUse"), UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
		use:SetSize(110, 24)
		use:SetText("Use")
		use:SetFrameStrata("DIALOG")
		use:SetAttribute("type", "item")
		do local D = J.Dragon() if D then D.SkinRedButton(use) end end
		use:Hide()
		local combat = CreateFrame("Frame")
		combat:RegisterEvent("PLAYER_REGEN_DISABLED")
		combat:RegisterEvent("PLAYER_REGEN_ENABLED")
		combat:SetScript("OnEvent", function (self, event)
			-- REGEN_DISABLED comes just before the lockdown starts: the last chance to hide it,
			-- and to let go of the model, so the journal never has a protected frame anchored
			-- to it while in combat.
			if event == "PLAYER_REGEN_DISABLED" then
				use:Hide()
				use:ClearAllPoints()
			else
				syncUse()
			end
		end)
		panel:HookScript("OnHide", syncUse)
		J.frame:HookScript("OnHide", syncUse)
	end

	local sourcesTitle = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	sourcesTitle:SetPoint("TOPLEFT", model, "BOTTOMLEFT", 4, -8)
	sourcesTitle:SetText("Where to get it")
	local mapNote = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	mapNote:SetPoint("LEFT", sourcesTitle, "RIGHT", 12, 0)
	mapNote:SetPoint("RIGHT", right, "RIGHT", -12, 0)
	mapNote:SetJustifyH("LEFT")

	local sourceScroll = J.CreateScrollArea(right)
	sourceScroll:SetPoint("TOPLEFT", sourcesTitle, "BOTTOMLEFT", -4, -6)
	sourceScroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -28, 8)
	sourceScroll:SetScript("OnMouseWheel", function (self, delta)
		local max = math.max(0, self.content:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
	end)

	local function makeSourceRow()
		local b = CreateFrame("Button", nil, sourceScroll.content)
		b:SetHeight(34)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(22, 22)
		b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -4)
		b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 30, -3)
		b.title:SetPoint("RIGHT", b, "RIGHT", -4, 0)
		b.title:SetJustifyH("LEFT")
		b.detail = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.detail:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -2)
		b.detail:SetPoint("RIGHT", b, "RIGHT", -4, 0)
		b.detail:SetJustifyH("LEFT")
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(b)
		hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		hl:SetBlendMode("ADD")
		hl:SetVertexColor(1, 1, 1, 0.4)
		b:SetScript("OnClick", function (self)
			local s, e = self.source, state.selected
			if not s or not e then return end
			if s.kind == "I" then
				if J.HandleItemClick(s.item) then return end
			elseif (s.kind == "D" or s.kind == "G") and s.instance and s.instance > 0 then
				J.OpenInstance(s.instance, { boss = s.boss and s.boss > 0 and s.boss or nil, tab = "loot", variant = s.variant })
				return
			elseif s.kind == "A" then
				if not AchievementFrame and AchievementFrame_LoadUI then AchievementFrame_LoadUI() end
				if AchievementFrame and AchievementFrame_SelectAchievement then
					ShowUIPanel(AchievementFrame)
					AchievementFrame_SelectAchievement(s.achievement)
				end
				return
			end
			if s.placed then
				J.ShowSourceOnMap(kind, e, s, function (where)
					if state.selected ~= e then return end
					mapNote:SetText(where and ("|cff66ff66Flagged on your map:|r " .. where) or "|cff9d9d9dNot on any map the journal knows|r")
				end)
			end
		end)
		b:SetScript("OnEnter", function (self)
			local s = self.source
			if not s then return end
			if s.kind == "I" then
				J.ShowItemTooltip(self, s.item)
			elseif s.kind == "C" then
				if s.recipe then
					J.ShowItemTooltip(self, s.recipe)
				else
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetHyperlink("spell:" .. s.spell)
					GameTooltip:Show()
				end
			elseif s.kind == "S" then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText("Coin Shop", 1, 1, 1)
				GameTooltip:AddLine("Open the Shop tab in the realm's launcher and buy it there with Tarnished Undermine "
					.. "Reals. Bosses of high-level dungeons and raids give them, and you get a couple each day "
					.. "for logging in.", 1, 0.82, 0, true)
				GameTooltip:Show()
			elseif s.placed or (s.instance and s.instance > 0) then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(self.title:GetText() or "")
				GameTooltip:AddLine(s.instance and s.instance > 0 and "Click to open it in the dungeon journal."
					or "Click to flag it on your map.", 0.8, 0.8, 0.8)
				GameTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", function () GameTooltip:Hide() end)
		return b
	end
	local sourceRows = J.CreatePool(makeSourceRow)
	local sourcesEmpty = sourceScroll.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	sourcesEmpty:SetPoint("TOPLEFT", sourceScroll.content, "TOPLEFT", 4, -4)

	local function renderSources(e)
		sourceRows:Reset()
		mapNote:SetText("")
		sourcesEmpty:SetText("Loading...")
		sourcesEmpty:Show()
		J.LoadSources(kind, e, function (list)
			if state.selected ~= e then return end
			sourceRows:Reset()
			if not list or #list == 0 then
				sourcesEmpty:SetText(list and "Nothing on this realm gives it" or "Couldn't ask the server")
				sourcesEmpty:Show()
				sourceScroll:SetContentHeight(20)
				return
			end
			sourcesEmpty:Hide()
			local function layout(live)
				sourceRows:Reset()
				local y = 0
				for _, s in ipairs(list) do
					local b = sourceRows:Get()
					b.source = s
					local t, detail, icon = describe(s, live)
					b.title:SetText(t)
					b.detail:SetText(detail or "")
					b.icon:SetTexture(icon)
					setShown(b.icon, icon ~= nil)
					local h = (detail and detail ~= "") and 34 or 22
					b:SetHeight(h)
					b:ClearAllPoints()
					b:SetPoint("TOPLEFT", sourceScroll.content, "TOPLEFT", 0, -y)
					b:SetPoint("RIGHT", sourceScroll.content, "RIGHT", 0, 0)
					y = y + h + 2
				end
				sourceScroll:SetContentHeight(y)
			end
			layout(nil)
			-- The coin shop and Black Market rows fill in what you have and what's up for bid.
			for _, s in ipairs(list) do
				if s.kind == "S" or s.kind == "B" then
					J.LoadLive(kind, e, function (live)
						if live and state.selected == e and state.sourcesFor == e then layout(live) end
					end)
					break
				end
			end
		end)
	end

	local function renderDetail()
		local e = state.selected
		setShown(right, e ~= nil)
		if not e then syncUse() return end
		local name = J.EntryName(kind, e) or ("item " .. e.id)
		bigIcon:SetTexture(J.EntryIcon(kind, e))
		title:SetText(name)
		local r, g, b = J.QualityColor(e.quality)
		title:SetTextColor(r, g, b)
		local bits = {}
		if kind == "mounts" then
			local flying, scaling = band(e.flags, J.ENTRY.FLYING) ~= 0, band(e.flags, J.ENTRY.SCALING) ~= 0
			table.insert(bits, scaling and "Ground and flying mount" or flying and "Flying mount" or "Mount")
		end
		if band(e.flags, J.ENTRY.ALLIANCE) ~= 0 then table.insert(bits, "|cff4080ffAlliance only|r") end
		if band(e.flags, J.ENTRY.HORDE) ~= 0 then table.insert(bits, "|cffff4040Horde only|r") end
		if band(e.flags, J.ENTRY.CLASS) ~= 0 and e.classMask ~= 0 then
			local names = {}
			for id = 1, 11 do
				if band(e.classMask, 2 ^ (id - 1)) ~= 0 and className(id) then table.insert(names, className(id)) end
			end
			if #names > 0 then table.insert(bits, table.concat(names, ", ") .. " only") end
		end
		if e.mine and kind == "toys" and not J.ToyInBags(e) then
			table.insert(bits, "|cff66ff66Collected|r (in your bank)")
		else
			table.insert(bits, e.mine and "|cff66ff66Collected|r" or "|cff9d9d9dNot collected|r")
		end
		if kind == "pets" and J.autoSummon == e.id then table.insert(bits, "|cff66ccffAuto-summoned|r") end
		if J.EntryLocked(e) then table.insert(bits, lockText(e.reqState)) end
		subtitle:SetText(table.concat(bits, " - "))

		if kind == "toys" then
			model:Hide()
			toyIcon:SetTexture(J.ItemIcon(e.id))
			toyIcon:Show()
			local text = J.ItemUseText and J.ItemUseText(e.id) or nil
			toyText:SetText(text or "")
			toyText:Show()
			action:Hide()
			syncUse()
		else
			toyIcon:Hide()
			toyText:Hide()
			model:Show()
			-- One you haven't collected still shows, dimmed and with a padlock.
			J.ShowCreature(model, e.creature, not e.mine)
			local c = J.Companion(kind, e)
			raiseAction()
			setShown(action, c ~= nil)
			if auto then
				setShown(auto, c ~= nil and J.autoSummon ~= nil)
				auto:SetChecked(J.autoSummon == e.id)
			end
			if star then
				setShown(star, c ~= nil and c.creature ~= nil)
				local fav = isFavorite(e)
				star.tex:SetDesaturated(not fav)
				star.tex:SetAlpha(fav and 1 or 0.75)
			end
			if c then
				local mounted = kind == "mounts" and IsMounted and IsMounted()
				action:SetText((c.active or mounted) and (kind == "mounts" and "Dismount" or "Dismiss") or "Summon")
			end
		end
		syncGoal()
		if state.sourcesFor ~= e then
			state.sourcesFor = e
			renderSources(e)
		end
	end

	render = function ()
		local problem, sub = J.ServerStatus()
		if not problem and not J.Has(J.HELLO_COLLECTIONS) then
			problem, sub = "This realm doesn't list " .. info.name:lower() .. " yet",
				"The realm's journal module has its collections turned off (Journal.Collections.Enable)."
		end
		if problem then
			body:Hide()
			status:SetText(problem)
			statusSub:SetText(sub or "")
			status:Show()
			statusSub:Show()
			return
		end
		status:Hide()
		statusSub:Hide()
		if not state.catalog then
			body:Hide()
			status:SetText("Loading " .. info.name:lower() .. "...")
			status:Show()
			return
		end
		body:Show()
		local have, total
		state.entries, have, total = J.FilteredEntries(kind, state.catalog, search:GetText())
		if favKind and not J.Filters(kind).sort then
			-- Favourites first, the rest in the order they came: DragonUI's window sorts the same way.
			-- Not when sorting by Newest / Oldest, which is asked for to see that order.
			local favs, rest = {}, {}
			for _, e in ipairs(state.entries) do table.insert(isFavorite(e) and favs or rest, e) end
			for _, e in ipairs(rest) do table.insert(favs, e) end
			state.entries = favs
		end
		count:SetText(string.format("Collected: |cffffffff%d|r / %d", have, total))
		if not state.selected and JournalCharDB.collectionSelected then
			state.selected = entryById(JournalCharDB.collectionSelected[kind] or -1)
		end
		-- A selection the filters now hide gives way to the first one shown.
		local listed
		for i, e in ipairs(state.entries) do if e == state.selected then listed = i break end end
		if not listed then state.selected = state.entries[1] end
		local revealAt = state.reveal and listed
		state.reveal = nil
		if #state.entries == 0 then
			empty:SetText(total == 0 and ("No " .. info.name:lower() .. " on this realm") or "Nothing matches the filters")
			empty:Show()
		else
			empty:Hide()
		end
		renderList()
		-- Opened on one entry: scroll the list to it when it's out of view. Through the scroll bar,
		-- after renderList has set its range, so the bar and the rows agree.
		if revealAt then
			local offset = FauxScrollFrame_GetOffset(scroll)
			if revealAt <= offset or revealAt > offset + rowCount then
				offset = math.max(0, math.min(revealAt - 1, #state.entries - rowCount))
				FauxScrollFrame_SetOffset(scroll, offset)
				local bar = _G[scrollName .. "ScrollBar"]
				if bar then bar:SetValue(offset * rowHeight) end
				renderList()
			end
		end
		renderDetail()
	end

	local function load()
		if J.ServerStatus() or not J.Has(J.HELLO_COLLECTIONS) then render() return end
		J.Fire("COMPANIONS")
		if kind == "toys" then J.RefreshToys() end
		if kind == "pets" and J.autoSummon == nil then sendAutoSummon("G") end
		if state.catalog then render() return end
		render()
		J.LoadCatalog(kind, function (catalog)
			if not catalog then
				status:SetText("The " .. info.name:lower() .. " couldn't be loaded")
				statusSub:SetText("Try again in a moment with /journal refresh.")
				status:Show()
				statusSub:Show()
				return
			end
			state.catalog = catalog
			render()
		end)
	end

	local lastText = ""
	search:SetScript("OnTextChanged", function (self)
		local text = self:GetText() or ""
		setShown(self.hint, text == "" and not self:HasFocus())
		if text == lastText then return end
		lastText = text
		J.Debounce("collection-search-" .. kind, 0.2, function ()
			FauxScrollFrame_SetOffset(scroll, 0)
			local bar = _G[scrollName .. "ScrollBar"]
			if bar then bar:SetValue(0) end
			render()
		end)
	end)
	search:SetScript("OnEditFocusGained", function (self) self.hint:Hide() end)
	search:SetScript("OnEditFocusLost", function (self) setShown(self.hint, (self:GetText() or "") == "") end)

	local function shown() return panel:IsVisible() end
	J.On("COLLECTION_FILTER", function (k) if k == kind and shown() then FauxScrollFrame_SetOffset(scroll, 0) render() end end)
	J.On("COLLECTION_OWNED", function (k) if k == kind and shown() then render() end end)
	J.On("ITEM_INFO", function () if shown() then render() end end)
	J.On("SECTION_SERVER", function () if shown() then load() end end)
	J.On("CACHE_RESET", function ()
		state.catalog, state.selected, state.sourcesFor = nil, nil, nil
		if shown() then load() end
	end)
	J.On("LOCKOUTS_CHANGED", function () if shown() then render() end end)
	if kind == "pets" then J.On("AUTO_SUMMON", function () if shown() then render() end end) end
	J.On("GOAL_CHANGED", function () if shown() then syncGoal() end end)
	-- The goal tracker and LearnedAlert's New Mount toast open the tab on one entry: show it,
	-- whatever the search box held, scrolled into view.
	J.On("COLLECTION_SELECT", function (k, id)
		if k ~= kind then return end
		JournalCharDB.collectionSelected = JournalCharDB.collectionSelected or {}
		JournalCharDB.collectionSelected[kind] = id
		state.selected = entryById(id)
		state.reveal = true
		-- Cleared without the search's debounce, which would scroll the list back to the top.
		lastText = ""
		if (search:GetText() or "") ~= "" then search:SetText("") end
		-- Filters that would hide it let it through: a goal is one not collected yet (and usable by
		-- this character), a new mount one that is (which may be the other faction's, shared by the
		-- account). Owned read from the client's list now: the toast can beat the COMPANIONS refresh.
		local f = J.Filters(kind)
		local mine
		if kind == "toys" then mine = J.Owned(kind, { id = id }) else mine = J.CompanionNow(kind, { id = id }) ~= nil end
		if mine then
			f.collected, f.usable = true, false
		else
			f.missing = true
		end
		f.hideLocked, f.mountType = false, nil
		wipe(f.sources)
		if shown() then render() end
	end)

	return load
end

-- What an item does when used: the green "Use:" lines of its tooltip.
local scanTip = CreateFrame("GameTooltip", "JournalToyScanTooltip", nil, "GameTooltipTemplate")
function J.ItemUseText(item)
	scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanTip:ClearLines()
	scanTip:SetHyperlink("item:" .. item)
	local parts = {}
	for i = 2, scanTip:NumLines() do
		local line = _G["JournalToyScanTooltipTextLeft" .. i]
		local text = line and line:GetText()
		if text and text ~= "" then
			local r, g, b = line:GetTextColor()
			if g and g > 0.9 and r < 0.2 and b < 0.2 then table.insert(parts, text) end
		end
	end
	return #parts > 0 and table.concat(parts, "\n") or nil
end

-- For other addons (LearnedAlert's New Mount and New Pet toasts): opens the tab on one entry, by
-- spell (mounts, pets) or item (toys). kind: "mounts", "pets", "toys", or the client's "MOUNT" /
-- "CRITTER". False when the realm has no collections to show, so the caller can open its own.
local KIND_ALIASES = { MOUNT = "mounts", CRITTER = "pets" }
function Journal.ShowCollection(kind, id)
	kind = KIND_ALIASES[kind] or kind
	if not J.KINDS[kind] or J.ServerStatus() or not J.Has(J.HELLO_COLLECTIONS) then return false end
	if not Journal.OpenTab(kind) then return false end
	if id then J.Fire("COLLECTION_SELECT", kind, id) end
	return true
end

for _, def in ipairs({
	{ key = "mounts", order = 30, icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
	{ key = "pets", order = 40, icon = "Interface\\Icons\\INV_Box_PetCarrier_01" },
	{ key = "toys", order = 50, icon = "Interface\\Icons\\INV_Misc_Toy_10" },
}) do
	local load
	J.AddSection({
		key = def.key, name = J.KINDS[def.key].name, order = def.order, icon = def.icon,
		build = function (panel) load = buildTab(def.key, panel) end,
		onShow = function () if load then load() end end,
	})
end
