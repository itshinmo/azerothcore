-- Journal widgets (from RetailProfessions): buttons, inputs, panes, tabs, dropdowns, scroll
-- areas and item buttons. Stock Blizzard frames, dressed in DragonUI's retail art when DragonUI is
-- loaded.

local J = Journal

local nameCounter = 0
local function uniqueName(base)
	nameCounter = nameCounter + 1
	return "Journal" .. base .. nameCounter
end
J.UniqueName = uniqueName

-----------------------------------------
-- DragonUI, if it's there and new enough to carry the helpers we borrow

-- DragonUI's nine-slice helper: DragonUI_NineSlice since DragonUI's 2026 rewrite, NineSliceUtils
-- before it.
local NineSliceUtils = _G.DragonUI_NineSlice or _G.NineSliceUtils

function J.Dragon()
	local D = _G.DragonUI
	if D and D._dir and D.atlasinfo and D.SafeSetAtlas and D.SkinRedButton and NineSliceUtils
			and D.CharacterPanel and D.CharacterPanel.ReskinTab then
		return D, D.CharacterPanel
	end
end

local function solid(host, layer, r, g, b, a, sublevel)
	local tex = host:CreateTexture(nil, layer, nil, sublevel)
	tex:SetTexture(r, g, b, a)
	return tex
end

local function tiled(host, layer, sublevel, file)
	local tex = host:CreateTexture(nil, layer, nil, sublevel)
	tex:SetTexture(file, "REPEAT", "REPEAT")
	tex:SetHorizTile(true)
	tex:SetVertTile(true)
	return tex
end

-----------------------------------------
-- window chrome and panes

-- Without DragonUI every window is a stock Blizzard dialog frame: the dialog-box border and
-- background with the gold header plate for its title.
local DIALOG_BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

-- Dresses a window and gives it a title (frame.title), a close button (frame.closeButton) and a
-- title bar to drag it by. DragonUI's metal frame on rock when DragonUI is loaded, otherwise the
-- stock dialog frame. opts = { portrait = round portrait top-left (frame.portrait, DragonUI only;
-- set it with J.SetPortrait), closeName = global name for the close button, onMoved = fn }.
-- Returns true with DragonUI, and the y offset content starts at.
function J.DressWindow(frame, opts)
	opts = opts or {}
	local D, CP = J.Dragon()
	local close = CreateFrame("Button", opts.closeName, frame, "UIPanelCloseButton")
	frame.closeButton = close

	if D then
		local rock = tiled(frame, "BACKGROUND", -8, D._dir .. "UI\\ui-background-rock")
		rock:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -21)
		rock:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

		local streaks = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
		if D:SafeSetAtlas(streaks, "_UI-Frame-TopTileStreaks") then
			streaks:SetHorizTile(true)
			streaks:SetHeight(43)
			streaks:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -21)
			streaks:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -21)
		else
			streaks:Hide()
		end

		-- On its own frame above the content, so no child panel draws over the metal.
		local chrome = CreateFrame("Frame", nil, frame)
		chrome:SetAllPoints(frame)
		chrome:SetFrameLevel(frame:GetFrameLevel() + 30)
		chrome:EnableMouse(false)
		local layout = opts.portrait and NineSliceUtils.GetLayout("PortraitFrameTemplate")
			or NineSliceUtils.GetLayout("NoPortraitFrameTemplate") or NineSliceUtils.GetLayout("PortraitFrameTemplate")
		NineSliceUtils.ApplyLayout(chrome, layout)
		frame.chrome = chrome
		if opts.portrait then
			-- Where DragonUI's spellbook puts its portrait, under the frame's ring.
			frame.portrait = chrome:CreateTexture(nil, "ARTWORK")
			frame.portrait:SetSize(58, 58)
			frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 6)
		end

		frame.title = chrome:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.title:SetPoint("TOP", frame, "TOP", 0, -5)
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
		if CP.ModernizeCloseButton then
			CP.ModernizeCloseButton(close, chrome, 1, 0)
			close:SetFrameLevel(chrome:GetFrameLevel() + 5)
		end
	else
		frame:SetBackdrop(DIALOG_BACKDROP)
		frame.chrome = frame
		local header = frame:CreateTexture(nil, "ARTWORK")
		header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
		header:SetSize(320, 64)
		header:SetPoint("TOP", frame, "TOP", 0, 12)
		frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.title:SetPoint("TOP", header, "TOP", 0, -14)
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	end

	local dragBar = CreateFrame("Frame", nil, frame)
	dragBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, D and 0 or 12)
	dragBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, 0)
	dragBar:SetHeight(D and 24 or 36)
	dragBar:EnableMouse(true)
	dragBar:RegisterForDrag("LeftButton")
	dragBar:SetScript("OnDragStart", function () frame:StartMoving() end)
	dragBar:SetScript("OnDragStop", function ()
		frame:StopMovingOrSizing()
		if opts.onMoved then opts.onMoved() end
	end)

	return D and true or false, D and -28 or -32
end

-- A round picture of an icon, as portraits and retail's recipe icons are drawn.
function J.SetPortrait(texture, path)
	if not texture then return end
	if path and SetPortraitToTexture then
		texture:SetTexCoord(0, 1, 0, 1)
		SetPortraitToTexture(texture, path)
	else
		texture:SetTexture(path)
	end
end

-- The stock options box (OptionsBoxTemplate: the tooltip border in 0.4 grey, insets 5), filled
-- with the tooltip background in dark grey so a list reads on the dialog.
local OPTIONS_BOX_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

-- A recessed pane: retail's InsetFrameTemplate with DragonUI, the stock options box without.
function J.CreateInset(parent)
	local pane = CreateFrame("Frame", nil, parent)
	local D = J.Dragon()
	if D then
		local bg = tiled(pane, "BACKGROUND", -5, D._dir .. "UI\\ui-background-marble")
		bg:SetAllPoints(pane)
		NineSliceUtils.ApplyLayout(pane, NineSliceUtils.GetLayout("InsetFrameTemplate"))
	else
		pane:SetBackdrop(OPTIONS_BOX_BACKDROP)
		pane:SetBackdropColor(0.1, 0.1, 0.1, 1)
		pane:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	end
	return pane
end

-- The stock category bar (the Currency tab's headers) behind a header row, for the look without
-- DragonUI.
function J.CreateHeaderBand(host)
	local file = "Interface\\TokenFrame\\UI-TokenFrame-CategoryButton"
	local right = host:CreateTexture(nil, "BACKGROUND")
	right:SetTexture(file)
	right:SetTexCoord(0, 0.14453125, 0.296875, 0.578125)
	-- At the art's own 18px height, centred on the row, so the bevel isn't stretched.
	right:SetSize(37, 18)
	right:SetPoint("RIGHT", host, "RIGHT")
	local left = host:CreateTexture(nil, "BACKGROUND")
	left:SetTexture(file)
	left:SetTexCoord(0, 1, 0, 0.28125)
	left:SetHeight(18)
	left:SetPoint("LEFT", host, "LEFT")
	left:SetPoint("RIGHT", right, "LEFT")
	return left, right
end

-- A FauxScrollFrame's bar: DragonUI's thin one, or the stock one.
function J.SkinScrollBar(scroll, scrollName)
	local bar = _G[scrollName .. "ScrollBar"]
	if not bar then return end
	local _, CP = J.Dragon()
	if CP and CP.ReskinScrollBar then
		pcall(CP.ReskinScrollBar, scroll, scroll, -7, 18, -7, true)
		-- DragonUI moves its grip from a hook on the scroll frame's OnVerticalScroll, which our lists
		-- replace with SetScript afterwards; the slider's own value change still reaches it.
		if CP.SyncScrollThumb then
			bar:HookScript("OnValueChanged", function () CP.SyncScrollThumb(scroll) end)
		end
	end
	-- Otherwise the stock scroll bar stays as it is.
end

-----------------------------------------
-- controls

function J.SetEnabled(control, enabled)
	if enabled then control:Enable() else control:Disable() end
end

function J.CreateButton(parent, text, width, height)
	local btn = CreateFrame("Button", uniqueName("Button"), parent, "UIPanelButtonTemplate")
	btn:SetSize(width or 100, height or 22)
	btn:SetText(text or "")
	local D = J.Dragon()
	if D then D.SkinRedButton(btn) end
	return btn
end

local function skinInput(eb)
	local D = J.Dragon()
	if not D then return end
	local regions = { eb:GetRegions() }
	for i = 1, #regions do
		local r = regions[i]
		if r:GetObjectType() == "Texture" then
			local path = r:GetTexture()
			if type(path) == "string" and path:lower():find("common%-input%-border") then
				r:SetTexture(0, 0, 0, 0.55)
			end
		end
	end
end

function J.CreateEditBox(parent, width, numeric)
	local eb = CreateFrame("EditBox", uniqueName("EditBox"), parent, "InputBoxTemplate")
	eb:SetSize(width or 120, 20)
	-- InputBoxTemplate's boxes take the keyboard as soon as they exist; ours only when clicked.
	eb:SetAutoFocus(false)
	eb:ClearFocus()
	if numeric then eb:SetNumeric(true) end
	eb:SetScript("OnEscapePressed", function (self) self:ClearFocus() end)
	eb:SetScript("OnEnterPressed", function (self) self:ClearFocus() end)
	skinInput(eb)
	return eb
end

function J.CreateCheck(parent, label)
	local name = uniqueName("Check")
	local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	local text = _G[name .. "Text"]
	text:SetText(label or "")
	text:SetFontObject(GameFontHighlightSmall)
	cb.label = text
	local _, CP = J.Dragon()
	if CP and CP.SkinCheckbox then CP.SkinCheckbox(cb) end
	return cb
end

-- A square item button with a quality border.
function J.CreateItemButton(parent, size)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(size or 37, size or 37)
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetAllPoints(btn)
	btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	btn.border = btn:CreateTexture(nil, "OVERLAY")
	btn.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	btn.border:SetBlendMode("ADD")
	btn.border:SetPoint("CENTER", btn, "CENTER")
	btn.border:SetSize((size or 37) * 1.8, (size or 37) * 1.8)
	btn.border:Hide()
	btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
	local hl = btn:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(btn)
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")

	btn.SetItem = function (self, texture, quality, count)
		self.icon:SetTexture(texture)
		if quality and quality >= 2 then
			local r, g, b = J.QualityColor(quality)
			self.border:SetVertexColor(r, g, b)
			self.border:Show()
		else
			self.border:Hide()
		end
		self.count:SetText(count and count > 1 and count or "")
	end
	return btn
end

-----------------------------------------
-- journal widgets

-- A tab along the top of a pane. The stock top tab (TabButtonTemplate) without DragonUI, a red
-- DragonUI button with a gold edge for the selected one with it.
function J.CreateTab(parent, text, onClick)
	local D = J.Dragon()
	local tab
	if D then
		tab = J.CreateButton(parent, text, 80, 22)
		tab:SetWidth(math.max(70, tab:GetFontString():GetStringWidth() + 24))
		tab.edge = CreateFrame("Frame", nil, tab)
		tab.edge:SetPoint("TOPLEFT", tab, "TOPLEFT", -3, 3)
		tab.edge:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 3, -3)
		tab.edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
		tab.edge:SetBackdropBorderColor(1, 0.82, 0, 1)
		tab.edge:Hide()
		function tab:SetSelected(selected)
			if selected then self.edge:Show() else self.edge:Hide() end
		end
	else
		tab = CreateFrame("Button", uniqueName("Tab"), parent, "TabButtonTemplate")
		tab:SetText(text)
		PanelTemplates_TabResize(tab, 4)
		function tab:SetSelected(selected)
			if selected then PanelTemplates_SelectTab(self) else PanelTemplates_DeselectTab(self) end
		end
	end
	tab:SetScript("OnClick", function (self)
		PlaySound("igCharacterInfoTab")
		onClick(self)
	end)
	return tab
end

-- A button that opens a menu (EasyMenu) under itself: "Classic", "10 Player", "All Classes".
-- items() returns the EasyMenu entries when it opens.
local menuFrame = CreateFrame("Frame", "JournalMenu", UIParent, "UIDropDownMenuTemplate")

function J.CreateDropdown(parent, width, items)
	local btn = J.CreateButton(parent, "", width or 120, 22)
	local arrow = btn:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetSize(10, 12)
	arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
	local fs = btn:GetFontString()
	if fs then
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", btn, "LEFT", 8, 0)
		fs:SetPoint("RIGHT", arrow, "LEFT", -2, 0)
	end
	btn:SetScript("OnClick", function (self)
		if DropDownList1 and DropDownList1:IsShown() and menuFrame.owner == self then
			CloseDropDownMenus()
			return
		end
		menuFrame.owner = self
		EasyMenu(items(), menuFrame, self, 0, 0, "MENU")
	end)
	return btn
end

-- A scrolling area for content of any height: content is the child to put things on; call
-- area:SetContentHeight(h) after laying it out.
function J.CreateScrollArea(parent)
	local name = uniqueName("Scroll")
	local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(10, 10)
	scroll:SetScrollChild(content)
	scroll.content = content
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnSizeChanged", function (self, w)
		content:SetWidth(math.max(10, (w or self:GetWidth()) - 4))
	end)
	local _, CP = J.Dragon()
	if CP and CP.ReskinScrollBar then pcall(CP.ReskinScrollBar, scroll, scroll, -7, 18, -7, true) end

	function scroll:SetContentHeight(h)
		content:SetHeight(math.max(1, h))
		self:UpdateScrollChildRect()
		local maxScroll = math.max(0, h - self:GetHeight())
		if self:GetVerticalScroll() > maxScroll then self:SetVerticalScroll(maxScroll) end
		local bar = _G[name .. "ScrollBar"]
		if bar then
			if maxScroll > 0 then bar:Show() else bar:Hide() end
		end
	end

	function scroll:ScrollToTop()
		self:SetVerticalScroll(0)
	end
	return scroll
end

-- A pool of frames made on demand: pool:Get() hands out the next one, pool:Reset() hides them all.
function J.CreatePool(make)
	local pool = { items = {}, used = 0 }
	function pool:Get()
		self.used = self.used + 1
		local item = self.items[self.used]
		if not item then
			item = make()
			self.items[self.used] = item
		end
		item:Show()
		return item
	end
	function pool:Reset()
		for i = 1, #self.items do self.items[i]:Hide() end
		self.used = 0
	end
	return pool
end

-- Creature previews. A 3.3.5 model frame shows a creature only once the client has it cached,
-- and SetCreature never asks the server for one it lacks, so one it hasn't met (a mount or pet
-- you don't own, a boss you never saw) stayed blank. The server sends the creature's record on
-- request (R), and the creature is set again until the frame reports a model file (GetModel).
-- A locked one keeps its colours under a dim light, with a padlock in the corner.
local MODEL_LIGHT = { 1, 0, 0, -0.707, -0.707, 0.7, 1.0, 1.0, 1.0, 0.8, 1.0, 1.0, 0.8 }
local MODEL_DIM = { 1, 0, 0, -0.707, -0.707, 0.3, 1.0, 1.0, 1.0, 0.3, 1.0, 1.0, 0.8 }
local MODEL_RETRY = 0.4
local MODEL_TRIES = 30 -- 12 seconds

local function modelLoaded(model)
	local file = model.GetModel and model:GetModel()
	return type(file) == "string" and file ~= ""
end

-- Creatures whose record was asked for this session: the client keeps it from then on.
local recordAsked = {}

local function askRecord(entry)
	if recordAsked[entry] or not J.Has(J.HELLO_MODELS) then return end
	recordAsked[entry] = true
	J.Request("R", { tostring(entry) })
end

local function frameCreature(model)
	ModelViewLib.Frame(model, model.shownEntry)
	if model.SetLight then model:SetLight(unpack(model.locked and MODEL_DIM or MODEL_LIGHT)) end
end

local modelLoader = CreateFrame("Frame")
modelLoader:Hide()
modelLoader.pending = {}
modelLoader.wait = 0
modelLoader:SetScript("OnUpdate", function (self, elapsed)
	self.wait = self.wait - elapsed
	if self.wait > 0 then return end
	self.wait = MODEL_RETRY
	for model in pairs(self.pending) do
		if not model:IsVisible() or not model.shownEntry then
			self.pending[model] = nil
		elseif modelLoaded(model) then
			frameCreature(model)
			self.pending[model] = nil
		else
			model.tries = model.tries + 1
			if model.tries > MODEL_TRIES then
				self.pending[model] = nil
			else
				model:SetCreature(model.shownEntry)
			end
		end
	end
	if not next(self.pending) then self:Hide() end
end)

-- The padlock sits on a layer a level above the model (a sibling: the model draws over its own
-- regions' children), re-pinned on every call in case the window is re-levelled.
local function modelLock(model)
	local layer = model.lockLayer
	if not layer then
		layer = CreateFrame("Frame", nil, model:GetParent())
		layer:SetAllPoints(model)
		layer:EnableMouse(false)
		layer.icon = layer:CreateTexture(nil, "OVERLAY")
		layer.icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
		layer.icon:SetTexCoord(0, 0.71875, 0, 0.875)
		layer.icon:SetSize(23, 28)
		layer.icon:SetPoint("TOPRIGHT", layer, "TOPRIGHT", -10, -10)
		model:HookScript("OnHide", function () layer:Hide() end)
		model.lockLayer = layer
	end
	layer:SetFrameLevel(model:GetFrameLevel() + 1)
	return layer
end

-- Shows a creature in a model frame; locked dims it and adds the padlock. Entry nil or 0 clears it.
function J.ShowCreature(model, entry, locked)
	-- Events refresh a page whose window is closed. The frame's OnShow comes back for it.
	if not model:IsVisible() then
		model.shownEntry = nil
		modelLoader.pending[model] = nil
		return
	end
	locked = locked and true or false
	if locked or model.lockLayer then J.SetShown(modelLock(model), locked and entry and entry ~= 0) end
	if not entry or entry == 0 then
		ModelViewLib.BeforeLoad(model)
		model:ClearModel()
		model.shownEntry = nil
		modelLoader.pending[model] = nil
		return
	end
	local relight = model.locked ~= locked
	model.locked = locked
	if model.shownEntry ~= entry then
		model.shownEntry = entry
		model.tries = 0
		ModelViewLib.BeforeLoad(model)
		model:ClearModel()
		model:SetCreature(entry)
	elseif not relight then
		return
	end
	if modelLoaded(model) then
		frameCreature(model)
	else
		askRecord(entry)
		modelLoader.pending[model] = true
		modelLoader:Show()
	end
end

-- Puts a tooltip on a frame: text is a string or fn(tooltip).
function J.SetTooltip(frame, text, anchor)
	frame:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
		if type(text) == "function" then text(GameTooltip, self) else GameTooltip:SetText(text, 1, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function () GameTooltip:Hide() end)
end

-- Whether Shift-compare is safe for this item. The 3.3.5 client crashes (#132 at 0x00620727)
-- when it compares against worn gear whose item record isn't in its cache yet, which is
-- common right after the cache is wiped. Anything missing is queried; the next hover compares.
function J.CanCompare(entry)
	local ready = GetItemInfo(entry) ~= nil
	if not ready then J.QueryItem(entry) end
	for slot = 1, 19 do
		local worn = GetInventoryItemID("player", slot)
		if worn and not GetItemInfo(worn) then
			J.QueryItem(worn)
			ready = false
		end
	end
	return ready
end

-- An item's tooltip, with the gear you wear beside it while Shift is held.
function J.ShowItemTooltip(owner, entry)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink("item:" .. entry)
	if IsShiftKeyDown() and GameTooltip_ShowCompareItem and J.CanCompare(entry) then GameTooltip_ShowCompareItem(GameTooltip) end
	GameTooltip:Show()
end

-- Clicks on an item: Shift links it in chat, Ctrl tries it on.
function J.HandleItemClick(entry, name, quality)
	local link = J.ItemLink(entry, name, quality)
	if IsModifiedClick("CHATLINK") then
		if not ChatEdit_InsertLink(link) then ChatFrame_OpenChat(link) end
		return true
	elseif IsModifiedClick("DRESSUP") then
		DressUpItemLink(link)
		return true
	end
	return false
end
