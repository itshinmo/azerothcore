/*
 * Dungeon XP rebalance for AzerothCore (ADR-012 revisions 2026-11-20 / 2026-11-26 / RFC-003 Group A).
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
#include "Creature.h"
#include "DBCStores.h"
#include "DungeonXpMath.h"
#include "Map.h"
#include "Player.h"
#include "PlayerScript.h"
#include "QuestDef.h"
#include "World.h"
#include "WorldScript.h"

namespace
{
    // Trash is the repeatable income, so it takes the deeper cut; bosses keep the
    // 2026-11-20 depth because they are the goal of a run, not its farm.
    float TrashKillFactor = 0.10f; // dungeon/raid trash mob XP multiplier
    float BossKillFactor = 0.33f;  // dungeon/raid boss XP multiplier
    float QuestFactor = 3.0f;      // dungeon quest XP multiplier, on top of the global Rate.XP.Quest
    bool IncludeRaids = true;      // raids get the same split

    void LoadConfig()
    {
        // Clamped: a negative multiplier would be undefined behavior in the float->uint32
        // conversions the hooks perform (a kill factor also must not exceed 1 = no-op gate).
        TrashKillFactor = DungeonXp::Math::ClampKillFactor(
            sConfigMgr->GetOption<float>("DungeonXp.TrashKillFactor", 0.10f));
        BossKillFactor = DungeonXp::Math::ClampKillFactor(
            sConfigMgr->GetOption<float>("DungeonXp.BossKillFactor", 0.33f));
        QuestFactor = DungeonXp::Math::ClampQuestFactor(
            sConfigMgr->GetOption<float>("DungeonXp.QuestFactor", 3.0f));
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

        return mapEntry->IsDungeon() && (IncludeRaids || !mapEntry->IsRaid());
    }

    // Boss classification shared with mod-objectives: a dungeon encounter creature, plus a
    // world boss that happens to stand inside an instance. mod-objectives asks
    // `killed->GetMap()->IsDungeon() && (killed->IsDungeonBoss() || killed->isWorldBoss())`
    // for its objective credit; the two modules must agree or a kill pays one rate and
    // counts as another.
    bool IsBossKill(Unit* victim)
    {
        if (!victim || !victim->IsCreature())
            return false;

        Creature* killed = victim->ToCreature();
        return killed->GetMap()->IsDungeon() && (killed->IsDungeonBoss() || killed->isWorldBoss());
    }

    class DungeonXpPlayerScript : public PlayerScript
    {
    public:
        DungeonXpPlayerScript() : PlayerScript("DungeonXpPlayerScript", {
            PLAYERHOOK_ON_GIVE_EXP,
            PLAYERHOOK_ON_QUEST_COMPUTE_EXP
        }) { }

        // Mob side: kill XP inside an instance map is scaled by the trash or boss factor.
        // BG kills pass through untouched (battlegrounds are not IsDungeon); the hook also
        // fires for BG kill XP. A null victim is treated as trash.
        void OnPlayerGiveXP(Player* player, uint32& amount, Unit* victim, uint8 xpSource) override
        {
            if (amount < 1 || xpSource != PlayerXPSource::XPSOURCE_KILL)
                return;

            float const factor = DungeonXp::Math::SelectKillFactor(player->GetMap()->IsDungeon(),
                player->GetMap()->IsRaid(), IncludeRaids, IsBossKill(victim), TrashKillFactor,
                BossKillFactor);

            if (factor >= 1.0f)
                return;

            amount = uint32(amount * factor);
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
