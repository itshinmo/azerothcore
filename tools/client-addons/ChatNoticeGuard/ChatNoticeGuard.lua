-- The Ascension client emits channel-notice tokens whose CHAT_<token>_NOTICE global is missing
-- from its GlobalStrings. ChatFrame_MessageEventHandler then calls format(nil, ...) and throws
-- "bad argument #1 to 'format' (string expected, got nil)"; seen on the LookingForGroup channel.
-- This wrapper supplies a safe string before the client formats it, and names the missing key once
-- so the real wording can be set here.

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
