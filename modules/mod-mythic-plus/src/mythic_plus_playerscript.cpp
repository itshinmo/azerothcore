/*
 * Credits: silviu20092
 */

#include "Map.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "Util.h"
#include "mythic_plus.h"
#include <sstream>

class mythic_plus_playerscript : public PlayerScript
{
public:
    mythic_plus_playerscript() : PlayerScript("mythic_plus_playerscript",
        {
            PLAYERHOOK_ON_PLAYER_JUST_DIED
        })
    {
    }

    void OnPlayerJustDied(Player* player) override
    {
        if (!player)
            return;

        Map* map = player->GetMap();
        MythicPlus::MapData* mapData = sMythicPlus->GetMapData(map, false);
        if (mapData == nullptr || mapData->mythicLevel == nullptr || !mapData->started || mapData->done)
            return;

        if (!sMythicPlus->IsMemberEligible(mapData, player->GetGUID()))
            return;

        mapData->deaths++;

        std::ostringstream oss;
        oss << player->GetName() << " died. Penalty: ";
        oss << secsToTimeString(mapData->penaltyOnDeath) << ". Total penalty: ";
        oss << secsToTimeString(mapData->GetPenaltyTime()) << ".";
        MythicPlus::BroadcastToMap(map, MythicPlus::Utils::RedColored(oss.str()));
    }
};

void AddSC_mythic_plus_playerscript()
{
    new mythic_plus_playerscript();
}
