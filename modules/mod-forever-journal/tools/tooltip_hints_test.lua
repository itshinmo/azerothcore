-- lua tools/tooltip_hints_test.lua addon/Journal
local handlers, requests, delayed = {}, {}, {}
local have, completed, criterionDone = false, false, false
local capability = true
local itemId = 900
Journal = {
 HELLO_HINTS = 512, HELLO_COLLECTIONS = 16, serverReady = true,
 KINDS = { mounts = { noun = "mount" }, pets = { noun = "pet" }, toys = { noun = "toy" } },
 On = function(event, fn) handlers[event] = fn end,
 Has = function() return capability end,
 Request = function(cmd, _, done) requests[cmd] = done end,
 Unescape = function(s) return s end,
 Owned = function() return have end,
 EntryLocked = function() return false end,
 Usable = function() return true end,
 Fire = function() end,
 RefreshToys = function() end,
 After = function(_, fn) table.insert(delayed, fn) end,
 LoadCatalog = function(kind, done)
  done({list = {{id = kind == "toys" and 900 or 123, item = 901}}})
 end,
}
GameTooltip = { lines = {}, hooks = {} }
function GameTooltip:HookScript(event, fn) self.hooks[event] = fn end
function GameTooltip:AddLine(text) table.insert(self.lines, text) end
function GameTooltip:GetUnit() return "Squirrel", "mouseover" end
function GameTooltip:GetItem() return "Food", "item:" .. itemId .. ":0:0" end
function GameTooltip:Show() end
function UnitGUID() return "0xF13000058E000001" end -- creature 1422
function GetAchievementInfo(id) return id, "Realm achievement " .. id, 10, completed end
function GetAchievementNumCriteria() return 1 end
function GetAchievementCriteriaInfo() return "Squirrel", 54, criterionDone, 1, 3, nil, nil, 243, nil, 77 end
assert(loadfile((arg[1] or "addon/Journal") .. "/TooltipHints.lua"))()
local function clear()
 GameTooltip.lines = {}
 GameTooltip.hooks.OnTooltipCleared(GameTooltip)
end
local function contains(text)
 return table.concat(GameTooltip.lines, "\n"):find(text, 1, true) ~= nil
end
handlers.READY()
requests.E({rows = {{"U",1422,1206,77,"/love"}, {"U",999,1206,77,"Kill"}, {"I",900,906,77,"Eat / drink"}}})
for _, fn in ipairs(delayed) do fn() end
GameTooltip.hooks.OnTooltipSetUnit(GameTooltip)
assert(contains("/love for Realm achievement 1206 (1/3)"))
assert(not contains("Kill"), "wrong creature's criterion leaked")
clear(); criterionDone = true
GameTooltip.hooks.OnTooltipSetUnit(GameTooltip)
assert(#GameTooltip.lines == 0, "completed criterion still shown")
criterionDone = false; completed = true; clear()
GameTooltip.hooks.OnTooltipSetUnit(GameTooltip)
assert(#GameTooltip.lines == 0, "completed achievement still shown")
completed = false; clear()
GameTooltip.hooks.OnTooltipSetItem(GameTooltip)
assert(contains("Eat / drink for Realm achievement 906"))
assert(contains("Collect toy"))
itemId = 901; clear()
GameTooltip.hooks.OnTooltipSetItem(GameTooltip)
assert(contains("Learn mount") and contains("Learn pet"), "missing companion hints absent")
have = true; clear()
GameTooltip.hooks.OnTooltipSetItem(GameTooltip)
assert(not contains("Learn mount") and not contains("Learn pet"), "known companion hinted")
itemId = 900; clear()
GameTooltip.hooks.OnTooltipSetItem(GameTooltip)
assert(not contains("Collect toy"), "owned toy still requested")
clear(); handlers.READY()
local stale = requests.E
handlers.NO_SERVER()
stale({rows = {{"U",1422,1206,77,"/love"}}})
GameTooltip.hooks.OnTooltipSetUnit(GameTooltip)
assert(#GameTooltip.lines == 0, "realm hints retained after disconnect")
capability = false; requests = {}; handlers.READY()
assert(not next(requests), "queried unsupported server")
print("Tooltip hints OK")
