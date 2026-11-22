-- The Ascension client emits channel-notice tokens whose CHAT_<token>_NOTICE global is missing
-- from its effective GlobalStrings; the player saw CHAT_NOT_IN_LFG_NOTICE. ChatFrame then calls
-- format(nil, ...) and throws "bad argument #1 to 'format' (string expected, got nil)", seen on the
-- LookingForGroup channel. The known keys are defined here with their stock wording (no format
-- specifier, so a call with or without arguments is safe); any other missing key gets a safe
-- placeholder and is named once so it can be added here.

local NOTICES = {
	-- The stock enUS string exists in locale-enUS.MPQ's GlobalStrings.lua but not in the effective
	-- Ascension patch layer, which is why the client formatted nil on this channel.
	CHAT_NOT_IN_LFG_NOTICE = "You must be queued in looking for group before joining this channel.",
}

for key, text in pairs(NOTICES) do
	if not _G[key] then _G[key] = text end
end

local PREFIX = "|cffff4444ChatNoticeGuard:|r "
local reported = {}

local function guard(event, token)
	if event ~= "CHAT_MSG_CHANNEL_NOTICE" and event ~= "CHAT_MSG_CHANNEL_NOTICE_USER" then return end
	if type(token) ~= "string" then return end
	local key = "CHAT_" .. token .. "_NOTICE"
	if _G[key] or _G[key .. "_BN"] then return end
	_G[key] = "[channel notice]"
	if not reported[key] then
		reported[key] = true
		print(PREFIX .. "missing " .. key .. "; using a placeholder.")
	end
end

if ChatFrame_MessageEventHandler then
	local original = ChatFrame_MessageEventHandler
	ChatFrame_MessageEventHandler = function (self, event, ...)
		guard(event, ...)
		return original(self, event, ...)
	end
end
