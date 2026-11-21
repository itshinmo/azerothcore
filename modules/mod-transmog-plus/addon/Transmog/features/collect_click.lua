local Transmog = _G.Transmog

-- Ctrl+right-click collect (ADR-021 revision 2026-11-21, Ascension's mechanic): Ctrl+right-click
-- a bag item to add its appearance to the account collection; the server soulbinds the item on
-- collect, so a collected piece can no longer be traded or sold. The request rides the
-- server-verified addon channel; the server ignores anything not collectible and answers with a
-- chat line either way.
--
-- Hooked on ContainerFrameItemButton_OnClick (the global every bag item button's OnClick calls)
-- so it fires for all bag clicks regardless of when the client creates the buttons — per-button
-- hooks attached at login never fired on 3.3.5 (buttons are created lazily). UseContainerItem is
-- hooked too as a belt-and-braces path; a per-slot throttle keeps the double fire to one request.

local lastRequest, lastRequestAt = nil, 0

local function requestCollect(bag, slot)
	if not bag or not slot then return end
	local itemID = GetContainerItemID(bag, slot)
	if not itemID then return end
	-- 3.3.5 GetItemInfo has no numeric class return; the class arrives as a localized string
	-- (same strings ui/costs.lua maps). Uncached item: skipped, the next click gets it.
	local _, _, _, _, _, itemClassStr = GetItemInfo(itemID)
	if not itemClassStr then return end
	if itemClassStr ~= "Armor" and itemClassStr ~= "Armadura"
		and itemClassStr ~= "Weapon" and itemClassStr ~= "Arma" then return end

	-- The client numbers the backpack slots 1..N and equipped bags 1..4; the server numbers the
	-- backpack 23..38 (INVENTORY_SLOT_ITEM_START) and the equipped bags 19..22 (absolute
	-- inventory positions). Keyring/bank are not collectible this way (the login scan covers
	-- everything bound there).
	local serverBag, serverSlot = bag, slot
	if bag == 0 then
		serverSlot = slot + 22
	elseif bag >= 1 and bag <= 4 then
		serverBag = bag + 18
	else
		return
	end

	local key = bag .. ":" .. slot
	local now = GetTime()
	if lastRequest == key and now - lastRequestAt < 2 then return end
	lastRequest, lastRequestAt = key, now

	Transmog:aSend("CollectItem:" .. serverBag .. ":" .. serverSlot)
end

if ContainerFrameItemButton_OnClick then
	hooksecurefunc("ContainerFrameItemButton_OnClick", function (self, mouseButton)
		if mouseButton ~= "RightButton" or not IsControlKeyDown() then return end
		local bag = self:GetParent() and self:GetParent():GetID()
		requestCollect(bag, self:GetID())
	end)
end

if UseContainerItem then
	hooksecurefunc("UseContainerItem", function (bag, slot)
		if not IsControlKeyDown() then return end
		requestCollect(bag, slot)
	end)
end
