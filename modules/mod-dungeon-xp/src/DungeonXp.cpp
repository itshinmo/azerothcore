/*
 * Dungeon XP rebalance for AzerothCore (ADR-012 revision 2026-11-20 / RFC-003 Group A).
 *
 * Local module for the modernization fork, retail/Wow-Forever-style split: dungeon mob and
 * boss kills are a farmable repeat path, so their XP is reduced; dungeon quests are one-time
 * per character, so their XP is raised. Dungeons become story events, not XP pinatas, and
 * world questing stays the fastest path.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Affero General Public License as published by the
 * Free Software Foundation; either version 3 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for
 * more details.
 */

#include "Config.h"
#include "DBCStores.h"
#include "Map.h"
#include "Player.h"
#include "PlayerScript.h"
#include "QuestDef.h"
#include "World.h"
#include "WorldScript.h"

#include <algorithm>

namespace
{
    float KillFactor = 0.33f;   // dungeon/raid mob XP multiplier (0.5 = retail-neutral; fork default deeper per owner)
    float QuestFactor = 2.0f;   // dungeon quest XP multiplier, on top of the global Rate.XP.Quest
    bool IncludeRaids = true;   // raid kills get the same reduction

    void LoadConfig()
    {
        // Clamped: a negative multiplier would be undefined behavior in the float->uint32
        // conversions the hooks perform (KillFactor also must not exceed 1 = no-op gate).
        KillFactor = std::clamp(sConfigMgr->GetOption<float>("DungeonXp.KillFactor", 0.33f), 0.0f, 1.0f);
        QuestFactor = std::max(1.0f, sConfigMgr->GetOption<float>("DungeonXp.QuestFactor", 2.0f));
        IncludeRaids = sConfigMgr->GetOption<bool>("DungeonXp.IncludeRaids", true);
    }

    class DungeonXpWorldScript : public WorldScript
    {
    public:
        DungeonXpWorldScript() : WorldScript("DungeonXpWorldScript", {
            WORLDHOOK_ON_AFTER_CONFIG_LOAD
        }) { }

        void OnAfterConfigLoad(bool /*reload*/) override
        {
            LoadConfig();
        }
    };

    // Is this quest a dungeon quest? Dungeon quests carry their dungeon's area id in
    // ZoneOrSort (data-driven, spot-checked: Blackfathom quests -> 719, "Into Utgarde!" ->
    // 206); the area's map being an instance settles it. Quests without such a zone keep
    // the world rate (fail-open; rare, e.g. some turn-in-outside quests).
    bool IsDungeonQuest(Quest const* quest)
    {
        if (!quest)
            return false;

        int32 zoneOrSort = quest->GetZoneOrSort();
        if (zoneOrSort <= 0)
            return false;

        AreaTableEntry const* area = sAreaTableStore.LookupEntry(zoneOrSort);
        if (!area)
            return false;

        MapEntry const* mapEntry = sMapStore.LookupEntry(area->mapid);
        if (!mapEntry)
            return false;

        return mapEntry->IsDungeon() && (IncludeRaids || mapEntry->map_type != MAP_RAID);
    }

    class DungeonXpPlayerScript : public PlayerScript
    {
    public:
        DungeonXpPlayerScript() : PlayerScript("DungeonXpPlayerScript", {
            PLAYERHOOK_ON_GIVE_EXP,
            PLAYERHOOK_ON_QUEST_COMPUTE_EXP
        }) { }

        // Mob side: kill XP inside an instance map is scaled down. BG kills pass through
        // untouched (battlegrounds are not IsDungeon); the hook also fires for BG kill XP.
        void OnPlayerGiveXP(Player* player, uint32& amount, Unit* /*victim*/, uint8 xpSource) override
        {
            if (amount < 1 || KillFactor >= 1.0f || xpSource != PlayerXPSource::XPSOURCE_KILL)
                return;

            if (!IncludeRaids && player->GetMap()->IsRaid())
                return;

            if (!player->GetMap()->IsDungeon())
                return;

            amount = uint32(amount * KillFactor);
        }

        // Quest side: the hook fires wherever the quest XP is computed (the reward sites and
        // the UI preview), each with its own local value, so scaling it keeps UI and reward
        // consistent and applies on top of Rate.XP.Quest.
        void OnPlayerQuestComputeXP(Player* player, Quest const* quest, uint32& xpValue) override
        {
            if (xpValue < 1 || QuestFactor <= 1.0f || !IsDungeonQuest(quest))
                return;

            xpValue = uint32(xpValue * QuestFactor);
        }
    };
}

void AddDungeonXpScripts()
{
    new DungeonXpWorldScript();
    new DungeonXpPlayerScript();
}

void Addmod_dungeon_xpScripts()
{
    AddDungeonXpScripts();
}
