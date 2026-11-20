-- Collections data: the server's catalog of mounts, pets and toys, where each comes from, and
-- which ones this character has. The catalog is kept across sessions until the server's data
-- stamp changes; sources for the session. Mounts and pets the character knows come from the
-- client (GetCompanionInfo); toys in the bags or bank from the server.

local J = Journal

local Unescape = J.Unescape

J.KINDS = {
	mounts = { letter = "M", companion = "MOUNT", name = "Mounts", noun = "mount" },
	pets = { letter = "P", companion = "CRITTER", name = "Pets", noun = "pet" },
	toys = { letter = "T", name = "Toys", noun = "toy" },
}

-- Catalog row flags (EntryFlags in JournalCollections.cpp).
J.ENTRY = { ALLIANCE = 0x01, HORDE = 0x02, FLYING = 0x04, CLASS = 0x08, UNOBTAINABLE = 0x10, SCALING = 0x20 }

-- Source bits (SourceBits), with the names the filter menu shows.
J.SOURCE = {
	{ bit = 0x001, name = "Vendor" },
	{ bit = 0x002, name = "Drop" },
	{ bit = 0x004, name = "Quest" },
	{ bit = 0x008, name = "Achievement" },
	{ bit = 0x010, name = "Profession" },
	{ bit = 0x020, name = "Trainer" },
	{ bit = 0x040, name = "Container" },
	{ bit = 0x080, name = "Fishing" },
	{ bit = 0x100, name = "World Event" },
	{ bit = 0x400, name = "Coin Shop" },
	{ bit = 0x800, name = "Black Market" },
	{ bit = 0x1000, name = "Guild Vendor" },
	{ bit = 0x200, name = "Other" },
}

-- mod-boss-coins' coin (Tarnished Undermine Real): what the launcher's shop takes.
J.BOSS_COIN = 90410

local band = bit.band

-----------------------------------------
-- the catalog

local catalogs = {}
local inflight = {}

local function buildCatalog(rows)
	local list, byId = {}, {}
	for _, r in ipairs(rows) do
		local e = { id = r[1], creature = r[2], item = r[3], quality = r[4] or 1, flags = r[5] or 0, classMask = r[6] or 0,
			sources = r[7] or 0, reqState = r[8] or 0 }
		table.insert(list, e)
		byId[e.id] = e
	end
	return { list = list, byId = byId }
end

-- Calls done(catalog) with { list = { entry, ... }, byId = { [id] = entry } }, or nil.
function J.LoadCatalog(kind, done)
	if catalogs[kind] then done(catalogs[kind]) return end
	local cache = J.Cache()
	cache.collections = cache.collections or {}
	if cache.collections[kind] then
		catalogs[kind] = buildCatalog(cache.collections[kind])
		done(catalogs[kind])
		return
	end
	if inflight[kind] then table.insert(inflight[kind], done) return end
	inflight[kind] = { done }
	J.Request("C", { J.KINDS[kind].letter }, function (result)
		local waiting = inflight[kind] or {}
		inflight[kind] = nil
		if result then
			-- Kept as the server's rows: a SavedVariable of plain arrays.
			J.Cache().collections = J.Cache().collections or {}
			J.Cache().collections[kind] = result.rows
			catalogs[kind] = buildCatalog(result.rows)
		end
		for _, fn in ipairs(waiting) do fn(catalogs[kind]) end
	end)
end

J.On("CACHE_RESET", function () catalogs = {} end)

-----------------------------------------
-- names and icons: mounts and pets from their spell, toys from their item

function J.EntryName(kind, e)
	if kind == "toys" then
		local name = GetItemInfo(e.id)
		if not name then J.QueryItem(e.id) end
		return name
	end
	return (GetSpellInfo(e.id))
end

function J.EntryIcon(kind, e)
	if kind == "toys" then return J.ItemIcon(e.id) end
	local _, _, icon = GetSpellInfo(e.id)
	return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-----------------------------------------
-- what this character has

local owned = { mounts = {}, pets = {}, toys = {} }
local ownedToysAt = nil
-- Dates what is owned (below, with the Newest / Oldest sort).
local stampOwned

-- Mounts and pets: spell -> companion index (and creature), read from the client.
local function readCompanions()
	for kind, info in pairs(J.KINDS) do
		if info.companion and GetNumCompanions then
			local have = {}
			for i = 1, GetNumCompanions(info.companion) do
				local creature, _, spell, _, active = GetCompanionInfo(info.companion, i)
				if spell then have[spell] = { index = i, active = active and true or false, creature = creature } end
			end
			owned[kind] = have
		end
	end
end

function J.Owned(kind, e)
	return owned[kind][e.id] ~= nil
end

function J.Companion(kind, e)
	return owned[kind][e.id]
end

-- The companion as the client lists it right now: its index and whether it's out. The client
-- renumbers the list without warning (a creature name arriving re-sorts it), so a summon
-- takes this, not the index read earlier, and the stored one is refreshed on the way.
function J.CompanionNow(kind, e)
	local info = J.KINDS[kind]
	if not (info and info.companion and GetNumCompanions) then return J.Companion(kind, e) end
	for i = 1, GetNumCompanions(info.companion) do
		local creature, _, spell, _, active = GetCompanionInfo(info.companion, i)
		if spell == e.id then
			local c = { index = i, active = active and true or false, creature = creature }
			owned[kind][e.id] = c
			return c
		end
	end
	owned[kind][e.id] = nil
	return nil
end

-- A toy in the bags (or worn) can be used; one only in the bank is collected but can't.
function J.ToyInBags(e)
	local t = owned.toys[e.id]
	return t ~= nil and t ~= false and t ~= 0
end

-- Asks the server which toys are in the bags or bank, at most every few seconds.
function J.RefreshToys(done)
	if not J.Has(J.HELLO_COLLECTIONS) then if done then done() end return end
	if ownedToysAt and GetTime() - ownedToysAt < 3 then if done then done() end return end
	ownedToysAt = GetTime()
	J.Request("O", nil, function (result)
		if result then
			local have = {}
			-- "<item>,<in bags>"; a server without the second field only counted the bags and bank.
			for _, r in ipairs(result.rows) do have[r[1]] = r[2] == nil and 1 or r[2] end
			owned.toys = have
			stampOwned("toys")
			J.Fire("COLLECTION_OWNED", "toys")
		end
		if done then done() end
	end)
end

-----------------------------------------
-- when each one was first had, for the Newest / Oldest sort

-- Neither the client nor the server keeps a date (accountwide_mounts is account and spell, a toy is
-- an item in the bags), so the journal notes the first time it sees each one: os time, or 0 for
-- one that was there before it kept count. Mounts and pets are the account's (the realm shares
-- them), so per realm in JournalDB; toys sit in one character's bags, so per character.
local function stamps(kind)
	local root
	if kind == "toys" then
		JournalCharDB.acquired = JournalCharDB.acquired or {}
		root = JournalCharDB.acquired
	else
		JournalDB.acquired = JournalDB.acquired or {}
		local realm = GetRealmName() or "?"
		JournalDB.acquired[realm] = JournalDB.acquired[realm] or {}
		root = JournalDB.acquired[realm]
	end
	local s = root[kind]
	if not s then
		s = { at = {}, characters = {} }
		root[kind] = s
	end
	return s
end

-- The first-acquired time of one this character has, or nil when the journal hasn't noted it yet.
function J.AcquiredAt(kind, e)
	return stamps(kind).at[e.id]
end

-- Until a few seconds after login the companion list can still be filling in, and a pass over a
-- short list would date the rest as new.
local stampsReady = false

-- Notes a time for each one owned that has none. A character's first pass dates what it has as 0,
-- as LearnedAlert's first scan does: so an alt with two mounts, the first to log in, can't leave
-- the main's fifty to be dated today. Anything the character turns up later is new, even one it
-- was gifted while logged out.
stampOwned = function (kind, ids)
	local s = stamps(kind)
	local me = UnitName("player") or "?"
	local first = not s.characters[me]
	local now = time()
	for id in pairs(ids or owned[kind]) do
		if s.at[id] == nil then s.at[id] = first and 0 or now end
	end
	s.characters[me] = true
end

-- A toy that lands in the bags is dated on the spot, without asking the server: the bags against
-- the toy catalog (kept across sessions). Only once the server's list has given this character its
-- first pass, or every toy it carries today would be dated now.
local function stampToysInBags()
	local s = stamps("toys")
	if not s.characters[UnitName("player") or "?"] or not GetContainerItemID then return end
	J.LoadCatalog("toys", function (catalog)
		if not catalog then return end
		local found
		for bag = 0, NUM_BAG_SLOTS do
			for slot = 1, GetContainerNumSlots(bag) do
				local item = GetContainerItemID(bag, slot)
				if item and catalog.byId[item] and s.at[item] == nil then
					found = found or {}
					found[item] = true
				end
			end
		end
		if found then stampOwned("toys", found) end
	end)
end

J.On("LOGIN", function ()
	J.After(5, function ()
		stampsReady = true
		readCompanions()
		stampOwned("mounts")
		stampOwned("pets")
	end)
end)

J.On("COMPANIONS", function ()
	readCompanions()
	if stampsReady then
		stampOwned("mounts")
		stampOwned("pets")
	end
	J.Fire("COLLECTION_OWNED", "mounts")
	J.Fire("COLLECTION_OWNED", "pets")
end)

J.On("BAGS", function ()
	ownedToysAt = nil
	if J.frame:IsShown() and J.view.section == "toys" then J.RefreshToys() end
	if J.Has(J.HELLO_COLLECTIONS) then stampToysInBags() end
end)

-----------------------------------------
-- filters, kept per character and kind

-- unobtainable: also list what nothing on the realm gives yet (whatever the character has always shows).
-- sort: nil (by name), "newest" or "oldest" (by when first had).
local DEFAULT_FILTERS = { collected = true, missing = true, usable = false, hideLocked = false, unobtainable = false, sources = {} }

function J.Filters(kind)
	JournalCharDB.collectionFilters = JournalCharDB.collectionFilters or {}
	local f = JournalCharDB.collectionFilters[kind]
	if not f then
		f = {}
		for k, v in pairs(DEFAULT_FILTERS) do f[k] = type(v) == "table" and {} or v end
		JournalCharDB.collectionFilters[kind] = f
	end
	f.sources = f.sources or {}
	return f
end

local _, playerClass = UnitClass("player")
local CLASS_BITS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8,
	WARLOCK = 9, DRUID = 11 }
local CLASS_TOKENS = {}
for token, id in pairs(CLASS_BITS) do CLASS_TOKENS[id] = token end
J.CLASS_TOKENS = CLASS_TOKENS

local function playerFaction()
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	return faction
end

-- Whether this character could use it: its faction and class.
function J.Usable(e)
	local faction = playerFaction()
	if band(e.flags, J.ENTRY.ALLIANCE) ~= 0 and faction == "Horde" then return false end
	if band(e.flags, J.ENTRY.HORDE) ~= 0 and faction == "Alliance" then return false end
	if band(e.flags, J.ENTRY.CLASS) ~= 0 and e.classMask ~= 0 then
		local _, token = UnitClass("player")
		local id = CLASS_BITS[token or playerClass or ""]
		if not id or band(e.classMask, 2 ^ (id - 1)) == 0 then return false end
	end
	return true
end

function J.EntryLocked(e)
	return J.Has(J.HELLO_PROGRESSION) and (e.reqState or 0) > (J.state or 18)
end

-- Mounts and pets the character has that the catalog leaves out (nothing on the realm gives
-- them: a promotion like Gurky, with Journal.Collections.ShowUnobtainable off) are listed all the
-- same, marked unobtainable: whatever the character owns shows.
local function withOwned(kind, catalog)
	local have = owned[kind]
	if not have or not next(have) then return catalog.list end
	catalog.extras = catalog.extras or {}
	local list
	for spell, c in pairs(have) do
		if not catalog.byId[spell] then
			local e = catalog.extras[spell]
			if not e then
				e = { id = spell, creature = c.creature or 0, item = 0, quality = 1, flags = J.ENTRY.UNOBTAINABLE,
					classMask = 0, sources = 0, reqState = 0, extra = true }
				catalog.extras[spell] = e
			end
			if not list then
				list = {}
				for i, x in ipairs(catalog.list) do list[i] = x end
			end
			table.insert(list, e)
		end
	end
	return list or catalog.list
end

-- The catalog's entries the filters and the search text let through, collected ones first,
-- then by name (or by when they were first had, as the filter menu's Sort by asks). Entries the
-- client can't name (spells it doesn't have) are left out.
function J.FilteredEntries(kind, catalog, text)
	local f = J.Filters(kind)
	local anySource = next(f.sources) ~= nil
	local out, total, have = {}, 0, 0
	text = text and text ~= "" and text:lower() or nil
	for _, e in ipairs(withOwned(kind, catalog)) do
		local name = J.EntryName(kind, e)
		local mine = J.Owned(kind, e)
		-- Nothing gives it and the character hasn't got it: left out of the list and the count
		-- unless asked for, so a new player sees what they can go and get.
		local hidden = not mine and not f.unobtainable and band(e.flags, J.ENTRY.UNOBTAINABLE) ~= 0
		if (name or kind == "toys") and not hidden then
			total = total + 1
			if mine then have = have + 1 end
			local ok = (mine and f.collected) or (not mine and f.missing)
			if ok and f.usable and not J.Usable(e) then ok = false end
			if ok and f.hideLocked and J.EntryLocked(e) then ok = false end
			if ok and kind == "mounts" and f.mountType then
				-- A mount that runs on the ground and flies where you can fly is both.
				local flying = band(e.flags, J.ENTRY.FLYING) ~= 0
				local scaling = band(e.flags, J.ENTRY.SCALING) ~= 0
				if not scaling and (f.mountType == "flying") ~= flying then ok = false end
			end
			if ok and anySource then
				local hit = false
				for b in pairs(f.sources) do if band(e.sources, b) ~= 0 then hit = true break end end
				ok = hit
			end
			if ok and text and not (name or ""):lower():find(text, 1, true) then ok = false end
			if ok then
				e.sortName = (name or ("item " .. e.id)):lower()
				e.mine = mine
				table.insert(out, e)
			end
		end
	end
	-- Newest / Oldest: the collected ones by when they were first had, the rest by name after them.
	-- One owned but not dated yet (the first seconds after login) counts as newest; the ones from
	-- before the journal kept count (0) are the oldest, by name among themselves.
	local at = (f.sort == "newest" or f.sort == "oldest") and stamps(kind).at
	local newest = f.sort == "newest"
	table.sort(out, function (a, b)
		if a.mine ~= b.mine then return a.mine end
		if at and a.mine then
			local ta, tb = at[a.id] or math.huge, at[b.id] or math.huge
			if ta ~= tb then
				if newest then return ta > tb end
				return ta < tb
			end
		end
		if a.sortName ~= b.sortName then return a.sortName < b.sortName end
		return a.id < b.id
	end)
	return out, have, total
end

-----------------------------------------
-- where one comes from

local sources = {}

local function buildSources(rows)
	local list = {}
	for _, r in ipairs(rows) do
		local kind = r[1]
		local s = { kind = kind, index = r[2] }
		if kind == "V" then
			s.npc, s.copper, s.honor, s.arena, s.items, s.reqState, s.placed = r[3], r[4], r[5], r[6], r[7], r[8], r[9] == 1
			s.name, s.where, s.event = Unescape(tostring(r[10])), Unescape(tostring(r[11] or "-")), Unescape(tostring(r[12] or "-"))
		elseif kind == "D" then
			s.creature, s.chance, s.instance, s.boss, s.reqState, s.placed, s.rare = r[3], r[4], r[5], r[6], r[7], r[8] == 1, r[9] == 1
			s.name, s.where = Unescape(tostring(r[10])), Unescape(tostring(r[11] or "-"))
			s.variant, s.tabs = r[12] ~= 255 and r[12] or nil, Unescape(tostring(r[13] or "-"))
			s.base = r[14]
		elseif kind == "G" then
			s.object, s.chance, s.instance, s.boss, s.reqState, s.placed = r[3], r[4], r[5], r[6], r[7], r[8] == 1
			s.name, s.where = Unescape(tostring(r[9])), Unescape(tostring(r[10] or "-"))
			s.variant, s.tabs = r[11] ~= 255 and r[11] or nil, Unescape(tostring(r[12] or "-"))
		elseif kind == "P" then
			s.creature, s.chance, s.reqState, s.placed = r[3], r[4], r[5], r[6] == 1
			s.name, s.where, s.base = Unescape(tostring(r[7])), Unescape(tostring(r[8] or "-")), r[9]
		elseif kind == "F" then
			s.area, s.chance, s.reqState, s.name = r[3], r[4], r[5], Unescape(tostring(r[6]))
		elseif kind == "I" then
			s.item, s.chance = r[3], r[4]
		elseif kind == "Q" then
			s.quest, s.level, s.reqState, s.placed, s.faction = r[3], r[4], r[5], r[6] == 1, r[7]
			s.name, s.giver, s.where = Unescape(tostring(r[8])), Unescape(tostring(r[9] or "-")), Unescape(tostring(r[10] or "-"))
		elseif kind == "A" then
			s.achievement = r[3]
		elseif kind == "C" then
			s.spell, s.skill, s.rank, s.name = r[3], r[4], r[5], Unescape(tostring(r[6]))
			s.recipe, s.reqSpell, s.reqState = r[7] ~= 0 and r[7] or nil, r[8] ~= 0 and r[8] or nil, r[9]
		elseif kind == "T" then
			s.class, s.level, s.copper, s.reqState, s.placed, s.trainers = r[3], r[4], r[5], r[6], r[7] == 1, r[8]
			s.name, s.where = Unescape(tostring(r[9])), Unescape(tostring(r[10] or "-"))
		elseif kind == "S" then
			s.offer, s.coins, s.reqState = r[3], r[4], r[5]
		elseif kind == "B" then
			s.template, s.copper, s.reqState, s.placed = r[3], r[4], r[5], r[6] == 1
			s.name, s.where, s.seller = Unescape(tostring(r[7])), Unescape(tostring(r[8] or "-")), Unescape(tostring(r[9] or "-"))
		elseif kind == "U" then
			s.guildLevel, s.rank, s.copper, s.faction, s.reqState, s.placed, s.vendors = r[3], r[4], r[5], r[6], r[7], r[8] == 1, r[9]
			s.name, s.where = Unescape(tostring(r[10])), Unescape(tostring(r[11] or "-"))
		elseif kind == "N" then
			s.text = Unescape(tostring(r[3]))
		elseif kind == "+" then
			s.of, s.more = r[3], r[4]
		end
		s.reqState = s.reqState or 0
		table.insert(list, s)
	end
	return list
end

-- Calls done(sources) with the entry's sources, in the server's order.
function J.LoadSources(kind, e, done)
	-- One the catalog left out has nothing for the server to tell.
	if e.extra then done({}) return end
	local key = kind .. ":" .. e.id
	if sources[key] then done(sources[key]) return end
	J.Request("W", { J.KINDS[kind].letter, tostring(e.id) }, function (result)
		if result then sources[key] = buildSources(result.rows) end
		done(sources[key])
	end)
end

-- What changes by the minute for an entry sold in the coin shop or at the Black Market: done(live)
-- with { coins = wallet (nil without a shop), bags = coins in the bags, bid = copper, bids,
-- left = seconds } (bid nil when it isn't up for bid), or done(nil). Never cached.
function J.LoadLive(kind, e, done)
	if not J.Has(J.HELLO_LIVE) or e.extra then done(nil) return end
	J.Request("T", { J.KINDS[kind].letter, tostring(e.id) }, function (result)
		if not result then done(nil) return end
		local coins, bid = tonumber(result[1]) or -1, tonumber(result[3]) or 0
		done({
			coins = coins >= 0 and coins or nil,
			bags = tonumber(result[2]) or 0,
			bid = bid > 0 and bid or nil,
			bids = tonumber(result[4]) or 0,
			left = tonumber(result[5]) or 0,
		})
	end)
end

-- A red flag on the map for a source; done(where text) when the server answers.
function J.ShowSourceOnMap(kind, e, s, done)
	J.Request("M", { "S", J.KINDS[kind].letter, tostring(e.id), tostring(s.index) }, function (result, err)
		local where = result and result[2] and Unescape(result[2])
		if done then done(where, err) end
	end)
end

J.On("CACHE_RESET", function () sources = {} end)

-----------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("COMPANION_LEARNED")
events:RegisterEvent("COMPANION_UPDATE")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
events:SetScript("OnEvent", function (self, event)
	if event == "BAG_UPDATE" or event == "PLAYERBANKSLOTS_CHANGED" then
		J.Debounce("collection-bags", 1.0, function () J.Fire("BAGS") end)
	elseif event == "COMPANION_UPDATE" and not (J.frame and J.frame:IsShown()) then
		-- Fires constantly in cities (anyone's pet or mount); the tabs read the companions
		-- again when they're opened, so there's nothing to do while the journal is closed.
		return
	else
		J.Debounce("collection-companions", 0.3, function () J.Fire("COMPANIONS") end)
	end
end)
