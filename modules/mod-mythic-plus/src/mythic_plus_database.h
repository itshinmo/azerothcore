/*
 * Credits: silviu20092
 *
 * Module-owned database pool for mod-mythic-plus. This pool targets the characters
 * database so the module can use prepared statements without changing the core
 * CharacterDatabase enum. The connection and statement setup mirror mod-pvp-rulesets.
 */

#ifndef _MYTHIC_PLUS_DATABASE_H_
#define _MYTHIC_PLUS_DATABASE_H_

#include "Define.h"
#include <unordered_map>

namespace MythicPlusDatabase
{
    [[nodiscard]] bool IsReady();
    void Open();
    void Close();

    void ClearRunRows();
    void SaveRun(uint32 instanceId, uint32 mapId, uint32 timeLimit, uint64 startTimeMs,
        uint32 keyLevel, uint32 penaltyOnDeath, uint32 deaths);
    void DeleteRun(uint32 instanceId);

    bool LoadProgress(std::unordered_map<uint64, uint8>& progress);
    void SaveProgress(uint32 guid, uint8 era, uint8 highestKey);
}

#endif
