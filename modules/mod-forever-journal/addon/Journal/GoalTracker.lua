-- The goal tracker: one mount, pet or toy the character is after, on screen while they play, with
-- where to get it next and how close they are (coins, gold, kills). "Set as goal" on the Mounts,
-- Pets and Toys tabs picks it; it goes away with a cheer once the character has it. Click it to
-- open the journal on it, right-click to flag the place on the map, drag to move it.

local J = Journal
local band = bit.band

-- JournalCharDB.goal = { kind = "mounts", id = <spell or toy item>, kills = <kills seen> }
local function goal() return JournalCharDB and JournalCharDB.goal end

function J.GoalIs(kind, e)
	local g = goal()
	return g ~= nil and e ~= nil and g.kind == kind and g.id == e.id
end

function J.SetGoal(kind, e)
	JournalCharDB.goal = e and { kind = kind, id = e.id, kills = 0 } or nil
	J.Fire("GOAL_CHANGED")
end

-- The source to point a new player at: the first one (the server sorts the easy ones first) their
-- progression has opened, past notes and "...and more" rows; else the first that isn't one.
local SKIP = { N = true, ["+"] = true, R = true }
local function nextStep(list)
	local fallback
	for _, s in ipairs(list) do
		if not SKIP[s.kind] then
			local locked = J.Has(J.HELLO_PROGRESSION) and (s.reqState or 0) > (J.state or 18)
			if not locked then return s end
			fallback = fallback or s
		end
	end
	return fallback or list[1]
end

-----------------------------------------
-- the frame

local frame
local current = {} -- the entry, its sources, the step shown, the live answer

local function savePosition()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	JournalCharDB.goalPos = { point, relPoint, x, y }
end

local function build()
	frame = CreateFrame("Button", "JournalGoalTracker", UIParent)
	frame:SetSize(250, 78)
	frame:SetFrameStrata("LOW")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local pos = JournalCharDB.goalPos
	if pos then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
	end
	frame:SetScript("OnDragStart", function (self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function (self) self:StopMovingOrSizing() savePosition() end)

	-- Plain text over a faint shade, like the quest tracker: no window in the way.
	local shade = frame:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints(frame)
	shade:SetTexture(0, 0, 0, 0.35)

	frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -4)
	frame.header:SetText("Goal")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function () J.SetGoal(nil) end)

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(30, 30)
	frame.icon:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -3)

	-- Fixed widths, not two anchors: the client measures wrapped text only on a set width.
	local function line(template, anchor, gap)
		local fs = frame:CreateFontString(nil, "OVERLAY", template)
		fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
		fs:SetWidth(202)
		fs:SetJustifyH("LEFT")
		return fs
	end
	frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.name:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 6, 0)
	frame.name:SetWidth(190)
	frame.name:SetJustifyH("LEFT")
	frame.step = line("GameFontNormalSmall", frame.name, 2)
	frame.detail = line("GameFontHighlightSmall", frame.step, 2)
	frame.progress = line("GameFontHighlightSmall", frame.detail, 2)

	frame:SetScript("OnClick", function (self, button)
		local g, s = goal(), current.step
		if not g then return end
		if button == "RightButton" then
			if s and s.placed and current.e then
				J.ShowSourceOnMap(g.kind, current.e, s, function (where)
					J.Print(where and ("flagged on your map: " .. where) or "it isn't on any map the journal knows.")
				end)
			end
			return
		end
		Journal.OpenTab(g.kind)
		J.Fire("COLLECTION_SELECT", g.kind, g.id)
	end)
	frame:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(self.name:GetText() or "Goal")
		GameTooltip:AddLine("Click to see every way to get it in the journal.", 0.8, 0.8, 0.8)
		if current.step and current.step.placed then
			GameTooltip:AddLine("Right-click to flag the place on your map.", 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine("Drag to move.", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function () GameTooltip:Hide() end)
	frame:Hide()
end

-- The progress line: what the player has against what the step asks for.
local function progressText(s, live, g)
	if not s then return nil end
	if s.kind == "S" and live and live.coins then
		-- The shop spends the wallet only; coins in the bags are counted apart.
		local color = live.coins >= s.coins and "|cff66ff66" or "|cffffd200"
		return color .. "Coins: " .. J.Number(live.coins) .. " / " .. J.Number(s.coins) .. "|r"
			.. ((live.bags or 0) > 0 and (" (+" .. J.Number(live.bags) .. " in your bags)") or "")
	elseif s.kind == "B" and live then
		if live.bid then
			return "|cff66ff66Up for bid now: " .. J.Money(live.bid) .. ", " .. J.Duration(live.left) .. " left|r"
		end
		return "|cff9d9d9dNot up for bid right now|r"
	elseif (s.kind == "V" or s.kind == "U" or s.kind == "T") and s.copper and s.copper > 0 then
		local money = GetMoney()
		local color = money >= s.copper and "|cff66ff66" or "|cffffd200"
		return color .. "Gold: " .. J.Money(math.min(money, s.copper)) .. " / " .. J.Money(s.copper) .. "|r"
	elseif s.kind == "D" and (g.kills or 0) > 0 then
		return "Kills so far: " .. J.Number(g.kills)
	end
	return nil
end

local function paint()
	local g, e, s = goal(), current.e, current.step
	if not (g and e) then frame:Hide() return end
	frame.header:SetText("Goal: " .. (J.KINDS[g.kind] and J.KINDS[g.kind].noun or "collectible"))
	frame.icon:SetTexture(J.EntryIcon(g.kind, e))
	frame.name:SetText(J.EntryName(g.kind, e) or "?")
	local r, gr, b = J.QualityColor(e.quality)
	frame.name:SetTextColor(r, gr, b)
	if s and J.DescribeSource then
		local title, detail = J.DescribeSource(s, current.live)
		frame.step:SetText(title)
		frame.detail:SetText(detail or "")
	elseif current.failed then
		frame.step:SetText("Couldn't ask the server")
		frame.detail:SetText("Trying again in a moment.")
	elseif current.list then
		frame.step:SetText("Nothing on this realm gives it")
		frame.detail:SetText("")
	else
		frame.step:SetText("Loading...")
		frame.detail:SetText("")
	end
	local progress = progressText(s, current.live, g)
	frame.progress:SetText(progress or "")
	-- Long places wrap: the frame grows to fit its lines.
	local h = 4 + frame.header:GetStringHeight() + 3
	local text = frame.name:GetStringHeight() + 2 + frame.step:GetStringHeight()
	if (frame.detail:GetText() or "") ~= "" then text = text + 2 + frame.detail:GetStringHeight() end
	if progress then text = text + 2 + frame.progress:GetStringHeight() end
	frame:SetHeight(h + math.max(30, text) + 6)
	frame:Show()
end

-----------------------------------------
-- keeping it current

-- Creatures whose kills count toward the goal: every creature that drops it, by the entry it is
-- spawned as (a heroic boss's loot is on its heroic template; its kills show the normal one).
local killFor = {}
local combat = CreateFrame("Frame")

local function watchKills(list)
	killFor = {}
	for _, s in ipairs(list or {}) do
		if s.kind == "D" and s.creature then
			killFor[s.creature] = true
			if s.base then killFor[s.base] = true end
		end
	end
	if next(killFor) then
		combat:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	else
		combat:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
end

-- 3.3.5 creature GUID: "0xF130" then the entry in 6 hex digits, then the spawn's counter.
local AFFILIATION_OURS = 0x7 -- COMBATLOG_OBJECT_AFFILIATION_MINE | PARTY | RAID
combat:SetScript("OnEvent", function (self, event, _, subEvent, _, _, sourceFlags, destGUID)
	if subEvent ~= "PARTY_KILL" or type(destGUID) ~= "string" then return end
	if band(sourceFlags or 0, AFFILIATION_OURS) == 0 then return end
	local high = destGUID:sub(3, 6):upper()
	if high ~= "F130" and high ~= "F150" then return end
	local entry = tonumber(destGUID:sub(7, 12), 16)
	local g = goal()
	if g and entry and killFor[entry] then
		g.kills = (g.kills or 0) + 1
		if frame then paint() end
	end
end)

local function refreshLive()
	local g, e = goal(), current.e
	if not (g and e and current.list) then return end
	for _, s in ipairs(current.list) do
		if s.kind == "S" or s.kind == "B" then
			J.LoadLive(g.kind, e, function (live)
				if current.e ~= e then return end
				current.live = live
				paint()
			end)
			return
		end
	end
end

-- Coins and auctions change while you play: a look every minute while there's a goal.
local liveTicking = false
local function tickLive()
	if not goal() then liveTicking = false return end
	refreshLive()
	J.After(60, tickLive)
end

local function celebrate(g, e)
	local name = J.EntryName(g.kind, e) or "it"
	J.Print("|cff66ff66Goal reached!|r You collected " .. name .. ".")
	if PlaySound then PlaySound("LEVELUPSOUND") end
	J.SetGoal(nil)
end

local function load()
	if not frame then build() end
	local g = goal()
	if g and g.kind == "toys" and J.Has(J.HELLO_COLLECTIONS) then J.RefreshToys() end
	current = {}
	watchKills(nil)
	if not g or not J.KINDS[g.kind] or not J.Has(J.HELLO_COLLECTIONS) then frame:Hide() return end
	J.LoadCatalog(g.kind, function (catalog)
		if goal() ~= g then return end
		local e = catalog and catalog.byId[g.id]
		if not e then frame:Hide() return end
		if J.Owned(g.kind, e) then celebrate(g, e) return end
		current.e = e
		paint()
		J.LoadSources(g.kind, e, function (list)
			if goal() ~= g or current.e ~= e then return end
			if not list then
				current.failed = true
				paint()
				J.After(30, function () if goal() == g and current.e == e and current.failed then load() end end)
				return
			end
			current.list = list
			current.step = nextStep(current.list)
			watchKills(current.list)
			paint()
			refreshLive()
			if not liveTicking then
				liveTicking = true
				J.After(60, tickLive)
			end
		end)
	end)
end

-- READY and CACHE_RESET come together after a HELLO: one load for both.
local function reload() J.Debounce("goal-load", 0.2, load) end
J.On("READY", reload)
J.On("GOAL_CHANGED", reload)
J.On("CACHE_RESET", reload)
J.On("NO_SERVER", function () if frame then frame:Hide() end end)
J.On("COLLECTION_OWNED", function (kind)
	local g, e = goal(), current.e
	if g and e and g.kind == kind and J.Owned(kind, e) then celebrate(g, e) end
end)
J.On("ITEM_INFO", function () if frame and frame:IsShown() then paint() end end)
J.On("BAGS", function ()
	local g = goal()
	if g and g.kind == "toys" and current.e then J.RefreshToys() end
	if current.live then refreshLive() end
end)

local money = CreateFrame("Frame")
money:RegisterEvent("PLAYER_MONEY")
money:SetScript("OnEvent", function () if frame and frame:IsShown() then paint() end end)
