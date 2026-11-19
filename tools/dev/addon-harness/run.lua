-- Offline runner for the GM Helper addon: loads it against the mock WoW API and
-- the client's real FrameXML template/font list, then checks and reports.
--
-- Usage: lua run.lua <path/to/GMHelper.toc> [client-frames.txt]
-- Exits 0 on pass, 1 on failure.

local function die(message)
    io.stderr:write(message .. "\n")
    os.exit(1)
end

local tocPath = arg[1] or die("usage: lua run.lua <GMHelper.toc> [client-frames.txt]")
local framesPath = arg[2] or (arg[0]:match("^(.*)[/\\]") or ".") .. "/client-frames.txt"

local templates, fonts = {}, {}
local framesFile = io.open(framesPath)
if not framesFile then
    die("cannot open frame list " .. framesPath .. " (run extract-client-frames.py first)")
end
for line in framesFile:lines() do
    local kind, name = line:match("^(%S+) (.+)$")
    if kind == "template" then templates[name] = true end
    if kind == "font" then fonts[name] = true end
end

local here = tocPath:match("^(.*)[/\\]") or "."
local files = {}
for line in io.open(tocPath):lines() do
    local file = line:match("^([^#%s].*)$")
    if file and file ~= "" then
        files[#files + 1] = file
    end
end

local MockEnv = dofile((arg[0]:match("^(.*)[/\\]") or ".") .. "/mock-wow.lua")
local log = {}
local env = MockEnv(templates, fonts, log)

local function loadChunk(source, chunkName)
    local chunk, err = load(source, "@" .. chunkName, "t", env)
    if not chunk then
        return false, err
    end
    local ok, runtime = pcall(chunk)
    if not ok then
        return false, runtime
    end
    return true
end

for _, file in ipairs(files) do
    local handle = io.open(here .. "/" .. file)
    if not handle then die("cannot open " .. file) end
    local source = handle:read("*a")
    handle:close()
    local ok, err = loadChunk(source, file)
    if not ok then
        print("FAIL " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
end

local failures = 0

-- 1. the slash command must exist
if not env.SlashCmdList.GMHELPER then
    print("FAIL: slash command /gmhelper is not registered")
    failures = failures + 1
end

-- 2. every fixed-width button must fit its text (the client clips overflow)
local function overflowReport(frame, path)
    if frame.fontString and frame.width and frame.width > 0 then
        local textWidth = frame.fontString:GetStringWidth()
        if textWidth + 20 > frame.width then
            print(string.format("WARN %s: text wider than %dpx button (%s)",
                path, frame.width, tostring(frame.fontString.text)))
        end
    end
    for _, child in ipairs(frame.children) do
        overflowReport(child, path .. ">" .. (child.name or child.kind))
    end
end
for _, root in pairs({ env.UIParent }) do
    overflowReport(root, "UIParent")
end

-- 3. smoke test: tab clicks, one teleport click per column, and every Self-tab
-- command must be sent with the self-only form.
local tab2 = env._G.GMHelperFrameTab2
local tab3 = env._G.GMHelperFrameTab3
if not tab2 or not tab3 then
    print("FAIL: tab buttons missing")
    failures = failures + 1
else
    tab2:Click()
    tab3:Click()
end

local dungeonRow = env._G.GMHelperDungeonRow1
local raidRow = env._G.GMHelperRaidRow1
if not dungeonRow or not raidRow then
    print("FAIL: instance row buttons missing (dungeon/raid columns)")
    failures = failures + 1
else
    local before = #log
    for i = 1, 20 do
        local row = env._G["GMHelperDungeonRow" .. i]
        if row then row:Click() end
        row = env._G["GMHelperRaidRow" .. i]
        if row then row:Click() end
    end
    local sent = false
    for i = before + 1, #log do
        if log[i]:sub(1, 6) == "sent: " then sent = true end
    end
    if not sent then
        print("FAIL: instance row clicks sent no command")
        failures = failures + 1
    end
end

for _, line in ipairs(log) do
    if line:find("tab failed", 1, true) then
        print("FAIL: " .. line)
        failures = failures + 1
    end
end

-- 4. Self tab: click every named button and require each exact self-only form.
local selfButtons = {
    "GMHelperSelfGod", "GMHelperSelfPower", "GMHelperSelfCooldown",
    "GMHelperSelfCasttime", "GMHelperSelfExploreOn", "GMHelperSelfExploreOff",
    "GMHelperSelfCombatStop", "GMHelperSelfLevel", "GMHelperSelfRevive",
    "GMHelperSelfSpeedUp", "GMHelperSelfSpeedReset", "GMHelperSelfGold",
    "GMHelperSelfBags", "GMHelperSelfGear", "GMHelperSelfUnbind",
    "GMHelperSelfListBinds",
}
local selfName = "Mock"
local allowedSelfCommands = {
    ".cheat god", ".cheat power", ".cheat cooldown", ".cheat casttime",
    ".cheat explore 1", ".cheat explore 0", ".combatstop",
    ".character level " .. selfName .. " 80",
    ".revive " .. selfName,
    ".modify speed 2", ".modify speed 1",
    ".modify money 1000g",
    ".additem " .. selfName .. " 51809 4",
    ".instance unbind all " .. selfName,
    ".instance listbinds",
}
-- The gear button sends one additem per generated grant for the mock's class.
local gearData = env._G.GMHelperGearData
if gearData and gearData.MAGE then
    for _, grant in ipairs(gearData.MAGE) do
        allowedSelfCommands[#allowedSelfCommands + 1] = ".additem " .. selfName .. " " .. grant.id
    end
else
    print("FAIL: GMHelperGearData.MAGE missing")
    failures = failures + 1
end
local selfSent = {}
local before = #log
for _, buttonName in ipairs(selfButtons) do
    local button = env._G[buttonName]
    if not button then
        print("FAIL: self button missing: " .. buttonName)
        failures = failures + 1
    else
        button:Click()
    end
end
for i = before + 1, #log do
    if log[i]:sub(1, 6) == "sent: " then
        selfSent[#selfSent + 1] = log[i]:sub(7)
    end
end
for _, command in ipairs(allowedSelfCommands) do
    local found = false
    for _, sent in ipairs(selfSent) do
        if sent == command then found = true end
    end
    if not found then
        print("FAIL: self-only command not exercised: " .. command)
        failures = failures + 1
    end
end
-- No sent command may carry a bare numeric target (the GUID trap).
for _, sent in ipairs(selfSent) do
    if sent:find("^%.additem %d") or sent:find("^%.revive %d")
        or sent:find("^%.character level %d") or sent:find("^%.instance unbind all %d") then
        print("FAIL: numeric (GUID) target sent: " .. sent)
        failures = failures + 1
    end
end

-- 4. summary
local sentCommands = {}
for _, line in ipairs(log) do
    if line:sub(1, 6) == "sent: " then sentCommands[#sentCommands + 1] = line end
end
print(string.format("loaded %d files, %d commands sent", #files, #sentCommands))
for _, line in ipairs(sentCommands) do
    print("  " .. line)
end
for _, line in ipairs(log) do
    if line:sub(1, 10) == "GM Helper " or line:sub(1, 10) == "GM Helper:" then
        print("  chat: " .. line)
    end
end

if failures == 0 then
    print("PASS: addon loads, slash registered, clicks send commands")
else
    print("FAIL: " .. failures .. " checks failed")
    os.exit(1)
end
