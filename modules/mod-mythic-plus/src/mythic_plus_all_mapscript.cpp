/*
 * Credits: silviu20092
 */

#include "GameTime.h"
#include "Log.h"
#include "Map.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "Util.h"
#include "mythic_plus.h"
#include <sstream>

class mythic_plus_all_mapscript : public AllMapScript
{
public:
    mythic_plus_all_mapscript() : AllMapScript("mythic_plus_all_mapscript",
        {
            ALLMAPHOOK_ON_PLAYER_ENTER_ALL,
            ALLMAPHOOK_ON_PLAYER_LEAVE_ALL,
            ALLMAPHOOK_ON_MAP_UPDATE,
            ALLMAPHOOK_ON_DESTROY_INSTANCE
        })
    {
    }

    void OnPlayerEnterAll(Map* map, Player* player) override
    {
        if (!map || !player || !map->IsNonRaidDungeon())
            return;

        std::optional<MythicPlus::MythicPlusDungeonInfo> saved =
            sMythicPlus->GetSavedDungeonInfo(map->GetInstanceId());
        if (!saved || saved->mapId != map->GetId())
            return;

        if (!sMythicPlus->IsEnabled() || !sMythicPlus->CanMapBeMythicPlus(map))
        {
            MythicPlus::BroadcastToPlayer(player,
                "This instance was saved as Mythic+ but the system is disabled or the map is not capable.");
            sMythicPlus->FallbackTeleport(player);
            return;
        }

        if (player->GetLevel() < DEFAULT_MAX_LEVEL)
        {
            MythicPlus::BroadcastToPlayer(player, "You must be level 80 to join a Mythic+ instance.");
            sMythicPlus->FallbackTeleport(player);
            return;
        }

        MythicPlus::MapData* mapData = sMythicPlus->GetMapData(map);
        if (mapData->mythicLevel == nullptr)
            sMythicPlus->RestoreMapData(map, *saved);

        if (mapData->mythicLevel == nullptr)
        {
            MythicPlus::BroadcastToPlayer(player, "This Mythic+ key level no longer exists.");
            sMythicPlus->FallbackTeleport(player);
            return;
        }

        if (!saved->done && !saved->members.empty() && !sMythicPlus->IsRunMember(mapData, player->GetGUID()))
        {
            MythicPlus::BroadcastToPlayer(player, "You are not a member of this Mythic+ run.");
            sMythicPlus->FallbackTeleport(player);
            return;
        }

        std::ostringstream oss;
        oss << "Mythic+ " << mapData->mythicLevel->level << " instance. ";
        if (saved->done)
            oss << "This run is finished.";
        else if (!sMythicPlus->IsMemberEligible(mapData, player->GetGUID()))
            oss << "You left this run; you are not eligible for rewards or a key unlock.";
        else if (!mapData->started)
            oss << "The timer starts on the first damage.";
        else
        {
            oss << "Elapsed " << secsToTimeString(mapData->GetElapsedMs() / 1000) << " of ";
            oss << secsToTimeString(mapData->timeLimit) << ". Deaths: " << mapData->deaths << ".";
        }

        MythicPlus::AnnounceToPlayer(player, oss.str());
    }

    void OnPlayerLeaveAll(Map* map, Player* player) override
    {
        if (!map || !player || !map->IsNonRaidDungeon())
            return;

        MythicPlus::MapData* mapData = sMythicPlus->GetMapData(map, false);
        if (mapData == nullptr || mapData->mythicLevel == nullptr || mapData->done)
            return;

        if (sMythicPlus->IsRunMember(mapData, player->GetGUID()))
            sMythicPlus->MarkMemberLeft(map, player->GetGUID());
    }

    void OnMapUpdate(Map* map, uint32 /*diff*/) override
    {
        if (!map || !map->IsNonRaidDungeon())
            return;

        MythicPlus::MapData* mapData = sMythicPlus->GetMapData(map, false);
        if (mapData == nullptr || mapData->mythicLevel == nullptr || mapData->done)
            return;

        if (!mapData->started)
        {
            if (mapData->prestartDeadlineMs > 0 &&
                MythicPlus::Utils::GameTimeMs() > mapData->prestartDeadlineMs)
                sMythicPlus->AbortRun(map, "prestart timeout");

            return;
        }

        if (mapData->receiveLoot &&
            (mapData->GetElapsedMs() / 1000 + mapData->GetPenaltyTime() > mapData->timeLimit))
        {
            mapData->receiveLoot = false;
            MythicPlus::AnnounceToMap(map,
                MythicPlus::Utils::RedColored("Time is up. This run will not unlock a key or pay a reward."));
        }
    }

    void OnDestroyInstance(MapInstanced* /*mapInstanced*/, Map* map) override
    {
        if (!map)
            return;

        MythicPlus::MapData* mapData = sMythicPlus->GetMapData(map, false);
        if (mapData != nullptr && mapData->mythicLevel != nullptr && !mapData->done)
            LOG_INFO("module.mythic_plus", "Instance {} destroyed with an active run", map->GetInstanceId());

        sMythicPlus->RemoveDungeonInfo(map->GetInstanceId());
    }
};

void AddSC_mythic_plus_all_mapscript()
{
    new mythic_plus_all_mapscript();
}
