/*
 * Credits: silviu20092
 */

#include "Chat.h"
#include "CommandScript.h"
#include "Map.h"
#include "Player.h"
#include "StringConvert.h"
#include "Util.h"
#include "mythic_affix.h"
#include "mythic_plus.h"
#include "mythic_plus_database.h"

using namespace Acore::ChatCommands;

class mythic_plus_commandscript : public CommandScript
{
public:
    mythic_plus_commandscript() : CommandScript("mythic_plus_commandscript") {}

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable mythicCommandTable =
        {
            { "info", HandleMythicInfoCommand, 950160, Console::No },
            { "status", HandleMythicStatusCommand, 950163, Console::Yes },
            { "reload", HandleMythicReloadCommand, 950163, Console::Yes }
        };

        static ChatCommandTable commandTable =
        {
            { "mythic", mythicCommandTable }
        };

        return commandTable;
    }

private:
    static bool HandleMythicInfoCommand(ChatHandler* handler)
    {
        Player* player = handler->GetPlayer();
        if (!player)
        {
            handler->SendSysMessage("This command requires a player.");
            return true;
        }

        Map* map = player->GetMap();
        MythicPlus::MapData* mapData = sMythicPlus->GetMapData(map, false);
        if (mapData == nullptr || mapData->mythicLevel == nullptr)
        {
            handler->SendSysMessage("You are not in a Mythic+ dungeon.");
            return true;
        }

        handler->PSendSysMessage("Mythic+ level: {}", mapData->mythicLevel->level);
        handler->PSendSysMessage("Timer limit: {}", secsToTimeString(mapData->timeLimit));
        handler->PSendSysMessage("Deaths: {} (penalty {})", mapData->deaths,
            secsToTimeString(mapData->GetPenaltyTime()));

        if (mapData->started && !mapData->done)
            handler->PSendSysMessage("Elapsed: {}", secsToTimeString(mapData->GetElapsedMs() / 1000));

        uint32 guid = MythicPlus::Utils::PlayerGUID(player);
        handler->PSendSysMessage("Highest key (era {}): {}, next: {}",
            uint32(mapData->era), uint32(sMythicPlus->GetHighestKey(guid, mapData->era)),
            uint32(sMythicPlus->GetNextKey(guid, mapData->era)));

        handler->PSendSysMessage("Eligible: {}", sMythicPlus->IsMemberEligible(mapData, player->GetGUID())
            ? "yes" : "no (left instance or not a member)");

        for (auto const& affix : mapData->mythicLevel->affixes)
            handler->PSendSysMessage("Affix: {}", affix->ToString());

        return true;
    }

    static bool HandleMythicStatusCommand(ChatHandler* handler)
    {
        handler->PSendSysMessage("Mythic+ enabled: {}, database ready: {}",
            sMythicPlus->IsEnabled(), MythicPlusDatabase::IsReady() ? "yes" : "no");
        handler->PSendSysMessage("Dungeons: {}, bosses: {}, scales: {}, key levels: {}",
            sMythicPlus->GetCapableDungeonCount(), sMythicPlus->GetBossCount(),
            sMythicPlus->GetCreatureScaleCount(), sMythicPlus->GetMythicLevelCount());
        handler->PSendSysMessage("Active runs: {}", sMythicPlus->HasActiveRuns() ? "yes" : "no");
        handler->PSendSysMessage("Penalty on death: {}s", sMythicPlus->GetPenaltyOnDeath());

        return true;
    }

    static bool HandleMythicReloadCommand(ChatHandler* handler)
    {
        if (sMythicPlus->HasActiveRuns())
        {
            handler->SendSysMessage("Cannot reload Mythic+ while a run is active.");
            return true;
        }

        sMythicPlus->ProcessConfig(true);
        if (!sMythicPlus->ReloadTables())
        {
            handler->SendSysMessage("Mythic+ reload failed; previous tables were kept.");
            return true;
        }

        handler->SendGlobalGMSysMessage("Mythic+ configuration, key levels, scales and affixes reloaded.");
        return true;
    }
};

void AddSC_mythic_plus_commandscript()
{
    new mythic_plus_commandscript();
}
