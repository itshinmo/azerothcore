local Transmog = _G.Transmog

-- Ctrl+right-click collect (ADR-021 revision 2026-11-21, Ascension's mechanic): Ctrl+right-click
-- a bag item to add its appearance to the account collection; the server soulbinds the item on
-- collect, so a collected piece can no longer be traded or sold. The request rides the
-- server-verified addon channel; the server ignores anything not collectible and answers with a
-- chat line either way.
--
-- Hooked on ContainerFrameItemButton_OnModifiedClick: with Ctrl held the client's bag button
-- OnClick takes the modified branch (IsModifiedClick) and never calls the plain OnClick handler,
-- which is why an OnClick hook alone never fired. The plain handler and UseContainerItem are
-- hooked too as fallbacks; a per-slot throttle keeps a double fire to one request.

local lastRequest, lastRequestAt = nil, 0

local function requestCollect(bag, slot)
	if type(bag) ~= "number" or bag < 0 or bag > 4 then return end
	if type(slot) ~= "number" or slot < 1 or slot > GetContainerNumSlots(bag) then return end
	local itemID = GetContainerItemID(bag, slot)
	if not itemID then return end
	-- No client-side class filter: the server verifies armor/weapon and answers either way, so a
	-- click always produces a reason. 3.3.5 GetItemInfo has no numeric class return; filtering
	-- here on the localized string also dropped items the client had not cached yet.

	-- The client numbers the backpack slots 1..N and equipped bags 1..N; the server numbers the
	-- backpack 23..38 (INVENTORY_SLOT_ITEM_START) and, inside an equipped bag, 0..N-1. The
	-- equipped bag itself is 19..22 (INVENTORY_SLOT_BAG_START). Keyring/bank are not collectible
	-- this way (the login scan covers everything bound there).
	local serverBag, serverSlot = bag, slot
	if bag == 0 then
		serverSlot = slot + 22
	elseif bag >= 1 and bag <= 4 then
		serverBag = bag + 18
		serverSlot = slot - 1
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[Transmog]|r Could not tell which bag that item is in.")
		return
	end

	local key = bag .. ":" .. slot
	local now = GetTime()
	if lastRequest == key and now - lastRequestAt < 2 then return end
	lastRequest, lastRequestAt = key, now

	Transmog:aSend("CollectItem:" .. serverBag .. ":" .. serverSlot)
end

-- A global handler can be called from a button that is not a container frame (whose GetID may be
-- 0, the backpack's number). Require a ContainerFrame and the backpack/equipped-bag range before
-- trusting the id.
local function bagClicked(button, mouseButton)
	if mouseButton ~= "RightButton" or not IsControlKeyDown() then return end
	local parent = button:GetParent()
	local name = parent and parent:GetName()
	local bag = parent and parent:GetID()
	if type(name) ~= "string" or not name:find("^ContainerFrame%d+$") or type(bag) ~= "number" then return end
	if bag < 0 or bag > 4 then return end
	requestCollect(bag, button:GetID())
end

if ContainerFrameItemButton_OnClick then
	hooksecurefunc("ContainerFrameItemButton_OnClick", bagClicked)
end

-- The path a Ctrl+right-click actually takes: the button's OnClick sees IsModifiedClick() true
-- and calls this handler instead of ContainerFrameItemButton_OnClick.
if ContainerFrameItemButton_OnModifiedClick then
	hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", bagClicked)
end

if UseContainerItem then
	hooksecurefunc("UseContainerItem", function (bag, slot)
		if not IsControlKeyDown() then return end
		requestCollect(bag, slot)
	end)
end
