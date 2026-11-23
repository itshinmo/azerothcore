-- patch-Z.MPQ canary, appended to Interface\FrameXML\WorldMapFrame.lua.
--
-- The file this block is appended to is copied byte-for-byte from the highest
-- priority archive before patch-Z (Data/enUS/patch-enUS-3.MPQ on the verified
-- English bundle). If patch-Z wins the load order, this message appears at
-- login. If a lower archive wins, the message is absent and the patch did not
-- load. Do not split this file: the whole FrameXML file is replaced.
do
    local canary = CreateFrame("Frame")
    canary:RegisterEvent("PLAYER_LOGIN")
    canary:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        local line = "|cff33ff99[client-patch]|r patch-Z.MPQ canary active: WorldMapFrame.lua loaded from patch-Z."
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(line)
        end
    end)
end
