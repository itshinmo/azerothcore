-- Hover actions from the realm's achievement criteria and collection catalog.
-- Nothing is matched by English creature names or a stock list of collectibles.
local J = Journal
local actions = { U = {}, I = {} }
local collectionItems = {}
local generation = 0

local function addHint(tip, text)
	if not tip.journalHintHeader then
		tip:AddLine(" ")
		tip:AddLine("Journal", 1, 0.82, 0)
		tip.journalHintHeader = true
	end
	tip:AddLine(text, 0.5, 0.85, 1, true)
end

-- Read progress each time: no stale completion flags in the tooltip index.
local function achievementHints(tip, kind, id)
	for _, row in ipairs(actions[kind][id] or {}) do
		local achievement, criterion, action = row[1], row[2], row[3]
		local _, name, _, complete = GetAchievementInfo(achievement)
		if name and not complete then
			for i = 1, GetAchievementNumCriteria(achievement) do
				local _, _, done, quantity, required, _, _, _, _, criteriaID = GetAchievementCriteriaInfo(achievement, i)
				if criteriaID == criterion and not done then
					local progress = required and required > 1 and (" (" .. (quantity or 0) .. "/" .. required .. ")") or ""
					addHint(tip, action .. " for " .. name .. progress .. " — see achievement for conditions")
					break
				end
			end
		end
	end
end

local function itemHints(tip)
	local _, link = tip:GetItem()
	local id = link and tonumber(link:match("item:(%d+)"))
	if not id then return end
	achievementHints(tip, "I", id)
	for _, ref in ipairs(collectionItems[id] or {}) do
		if not J.Owned(ref.kind, ref.entry) then
			local text = ref.kind == "toys" and "Collect toy" or ("Learn " .. J.KINDS[ref.kind].noun)
			if J.EntryLocked(ref.entry) then text = text .. " (later progression stage)"
			elseif not J.Usable(ref.entry) then text = text .. " (another class or faction)" end
			addHint(tip, text)
		end
	end
	if tip.journalHintHeader then tip:Show() end
end

local function unitHints(tip)
	local _, unit = tip:GetUnit()
	local guid = unit and UnitGUID(unit)
	-- 3.3.5 GUIDs: F130 = creature, F150 = vehicle; entry occupies hex digits 7..12.
	local prefix = guid and guid:sub(3, 6)
	if prefix ~= "F130" and prefix ~= "F150" then return end
	local id = tonumber(guid:sub(7, 12), 16)
	if id then achievementHints(tip, "U", id) end
	if tip.journalHintHeader then tip:Show() end
end

GameTooltip:HookScript("OnTooltipCleared", function (tip) tip.journalHintHeader = nil end)
GameTooltip:HookScript("OnTooltipSetUnit", unitHints)
GameTooltip:HookScript("OnTooltipSetItem", itemHints)

local function load()
	generation = generation + 1
	local current = generation
	actions, collectionItems = { U = {}, I = {} }, {}
	if not J.Has(J.HELLO_HINTS) then return end
	if J.Has(J.HELLO_HINTS) then
		J.Request("E", nil, function (result)
			if not result or generation ~= current then return end
			for _, row in ipairs(result.rows) do
				local list = actions[row[1]]
				if list then
					list[row[2]] = list[row[2]] or {}
					table.insert(list[row[2]], { row[3], row[4], J.Unescape(row[5]) })
				end
			end
		end)
	end
	if J.Has(J.HELLO_COLLECTIONS) then
		J.Fire("COMPANIONS")
		J.RefreshToys()
		-- Spread catalog requests across the transport's token refill window.
		for i, kind in ipairs({ "mounts", "pets", "toys" }) do
			local k = kind
			J.After(i * 2, function ()
				if generation ~= current then return end
				J.LoadCatalog(k, function (catalog)
					if not catalog or generation ~= current then return end
					for _, entry in ipairs(catalog.list) do
						local item = k == "toys" and entry.id or entry.item
						if item and item > 0 then
							collectionItems[item] = collectionItems[item] or {}
							table.insert(collectionItems[item], { kind = k, entry = entry })
						end
					end
				end)
			end)
		end
	end
end
J.On("READY", load)
J.On("NO_SERVER", function () generation = generation + 1; actions, collectionItems = { U = {}, I = {} }, {} end)
-- Refresh on the next hover after an achievement update; progress is deliberately not cached.

J.On("BAGS", function () if J.serverReady and J.Has(J.HELLO_HINTS) then J.RefreshToys() end end)
