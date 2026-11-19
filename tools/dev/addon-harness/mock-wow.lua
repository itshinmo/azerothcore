-- Mock of the WoW 3.3.5 UI API, sized for loading GM Helper outside the client.
--
-- What it does:
--   * validates every template and font name against the client's FrameXML
--     (the same failure the client raises: Couldn't find inherited node)
--   * records frame geometry and scripts so the runner can check layout and
--     click buttons
--   * approximates FontString width for text-overflow checks
--
-- It does not render pixels and does not cover the full API. Extend it when the
-- addon uses something new; keep every function used by GM Helper working.

local function MockEnv(templates, fonts, log)
    local env = {}
    env.log = log

    local frames = {}

    local function estimateWidth(text)
        -- Rough per-character width; enough to catch text wider than its button.
        return #tostring(text) * 7
    end

    local function makeFontString(owner)
        local fs = {
            text = "",
            owner = owner,
        }
        function fs:SetText(text) fs.text = tostring(text) end
        function fs:GetText() return fs.text end
        function fs:GetStringWidth() return estimateWidth(fs.text) end
        function fs:SetTextColor() end
        function fs:SetPoint(...) fs.point = { ... } end
        function fs:SetWidth(w) fs.width = w end
        function fs:SetTextInsets() end
        function fs:SetJustifyH() end
        function fs:Show() fs.shown = true end
        function fs:Hide() fs.shown = false end
        function fs:IsShown() return fs.shown end
        return fs
    end

    local function checkFont(_, name)
        if name and not fonts[name] then
            error('Couldn\'t find font object "' .. tostring(name) .. '"', 3)
        end
    end

    local frameMethods = {}
    local frameMetatable = { __index = frameMethods }

    function frameMethods:SetWidth(w) self.width = w end
    function frameMethods:SetHeight(h) self.height = h end
    function frameMethods:GetWidth() return self.width end
    function frameMethods:GetHeight() return self.height end
    function frameMethods:SetPoint(point, relativeTo, relativePoint, x, y)
        self.points[#self.points + 1] = {
            point = point, relativeTo = relativeTo, relativePoint = relativePoint,
            x = x, y = y,
        }
    end
    function frameMethods:Show() self.shown = true end
    function frameMethods:Hide() self.shown = false end
    function frameMethods:IsShown() return self.shown end
    function frameMethods:SetScript(key, handler) self.scripts[key] = handler end
    function frameMethods:GetScript(key) return self.scripts[key] end
    function frameMethods:CreateFontString(_, _, fontObject)
        checkFont(self, fontObject)
        local fs = makeFontString(self)
        if fontObject then fs.fontObject = fontObject end
        self.fontStrings[#self.fontStrings + 1] = fs
        return fs
    end
    function frameMethods:GetFontString() return self.fontString end
    function frameMethods:SetText(text)
        -- Client truth: a template-less Button has no FontString, so SetText
        -- renders nothing until one is attached (SetFontString / CreateFontString).
        if not self.fontString and not self.template then
            self.plainText = tostring(text)
            return
        end
        if not self.fontString then
            self.fontString = makeFontString(self)
        end
        self.fontString:SetText(text)
    end
    function frameMethods:GetText()
        if self.fontString then return self.fontString.text end
        return self.plainText
    end
    function frameMethods:SetFontString(fs) self.fontString = fs end
    function frameMethods:SetNormalFontObject(name) checkFont(self, name) self.normalFont = name end
    function frameMethods:SetHighlightFontObject(name) checkFont(self, name) end
    function frameMethods:SetPushedFontObject(name) checkFont(self, name) end
    function frameMethods:SetDisabledFontObject(name) checkFont(self, name) end
    function frameMethods:SetFontObject(name) checkFont(self, name) end
    function frameMethods:SetID(id) self.id = id end
    function frameMethods:GetID() return self.id end
    function frameMethods:SetFrameStrata() end
    function frameMethods:SetFrameLevel() end
    function frameMethods:GetFrameLevel() return 0 end
    function frameMethods:SetClampedToScreen() end
    function frameMethods:SetMovable() end
    function frameMethods:EnableMouse() end
    function frameMethods:RegisterForDrag() end
    function frameMethods:StartMoving() end
    function frameMethods:StopMovingOrSizing() end
    function frameMethods:SetBackdrop() end
    function frameMethods:SetBackdropColor() end
    function frameMethods:SetBackdropBorderColor() end
    function frameMethods:SetTextInsets() end
    function frameMethods:SetTextColor() end
    function frameMethods:SetAutoFocus() end
    function frameMethods:SetMaxLetters() end
    function frameMethods:SetJustifyH() end
    function frameMethods:ClearFocus() end
    function frameMethods:SetAttribute() end
    function frameMethods:Click()
        if self.scripts.OnClick then self.scripts.OnClick(self) end
    end

    local function createFrame(kind, name, parent, template)
        if template ~= nil and not templates[template] then
            error('CreateFrame(): Couldn\'t find inherited node "' .. tostring(template) .. '"', 3)
        end
        local frame = {
            kind = kind, name = name, template = template, parent = parent,
            width = 0, height = 0, shown = false,
            points = {}, scripts = {}, fontStrings = {}, children = {},
        }
        if parent then
            parent.children[#parent.children + 1] = frame
        end
        if name then
            env._G[name] = frame
            frames[name] = frame
        end
        setmetatable(frame, frameMetatable)
        return frame
    end

    env._G = {}
    -- The addon runs with this env as its global table, so seed the Lua standard
    -- library first; everything else is the WoW API surface.
    for name in pairs(_G) do
        env[name] = _G[name]
    end
    env._G = env
    env.frames = frames
    env.CreateFrame = createFrame
    env.UIParent = createFrame("Frame", "UIParent", nil, nil)
    env.UISpecialFrames = {}
    env.tinsert = table.insert
    env.SlashCmdList = {}
    env.InCombatLockdown = function() return false end
    env.UnitName = function(unit)
        if unit == "player" then return "Mock" end
        return nil
    end
    env.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, message) log[#log + 1] = tostring(message) end,
    }
    env.ChatFrame1EditBox = setmetatable({}, frameMetatable)
    env.ChatEdit_SendText = function(editBox)
        log[#log + 1] = "sent: " .. tostring(editBox:GetText())
    end
    env.ChatFrame_OpenChat = function(command)
        log[#log + 1] = "sent: " .. tostring(command)
    end
    env.GameTooltip = createFrame("GameTooltip", "GameTooltip", env.UIParent, nil)
    env.FauxScrollFrame_GetOffset = function() return 0 end
    env.FauxScrollFrame_Update = function() end
    env.FauxScrollFrame_OnVerticalScroll = function() end
    return env
end

return MockEnv
