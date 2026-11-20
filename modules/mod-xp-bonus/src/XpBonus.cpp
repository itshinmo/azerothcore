/*
 * Small-balance XP bonus sources for AzerothCore (ADR-012 revision 2026-11-20 / RFC-003 Group A).
 *
 * Local module for the modernization fork: rare creature kills, gathering nodes and
 * battleground wins award a small base experience that passes through the server's global
 * experience rate (ADR-012), making non-quest leveling paths viable.
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

#include "AllBattlegroundScript.h"
#include "Config.h"
#include "DBCStores.h"
#include "GameObject.h"
#include "KillRewarder.h"
#include "Player.h"
#include "PlayerScript.h"
#include "ScriptMgr.h"
#include "Spell.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "World.h"
#include "WorldScript.h"

#include <ctime>
#include <unordered_map>

namespace
{
    float RareKillPerLevel = 100.0f;    // base XP per rare kill = value x player level
    float GatheringPerLevel = 15.0f;    // base XP per gather node = value x player level
    uint32 GatheringDailyNodeCap = 200; // gathers per character per day; 0 = uncapped
    float BgWinPerLevel = 75.0f;        // base XP per battleground win = value x player level

    // player GUID counter -> { server day, gathers used that day }
    struct GatherCount
    {
        uint32 day = 0;
        uint32 count = 0;
    };
    std::unordered_map<uint32, GatherCount> GatherCountsByPlayer;

    // The ADR-012 global rate (2x) applies to these bases, per the small-balance rule:
    // the awarded XP is Rate.XP.Kill x base.
    uint32 BaseXpForLevel(Player* player, float perLevel)
    {
        return uint32(perLevel * player->GetLevel() * sWorld->getRate(RATE_XP_KILL));
    }

    // Award path mirrors the core's own call sites: the XP goes through the script hook
    // (Ancestral Wisdom multiplies here, per the owner's 2026-11-20 decision that Wisdom
    // stacks with every XP source) before GiveXP applies rested and recruit-a-friend.
    void AwardXp(Player* player, float perLevel, Unit* victim, uint8 xpSource)
    {
        uint32 xp = BaseXpForLevel(player, perLevel);
        if (xp < 1)
            return;

        sScriptMgr->OnPlayerGiveXP(player, xp, victim, xpSource);
        if (xp < 1)
            return;

        player->GiveXP(xp, victim);
    }

    void LoadConfig()
    {
        RareKillPerLevel = sConfigMgr->GetOption<float>("XpBonus.RareKill.PerLevel", 100.0f);
        GatheringPerLevel = sConfigMgr->GetOption<float>("XpBonus.Gathering.PerLevel", 15.0f);
        GatheringDailyNodeCap = sConfigMgr->GetOption<uint32>("XpBonus.Gathering.DailyNodeCap", 200);
        BgWinPerLevel = sConfigMgr->GetOption<float>("XpBonus.BgWin.PerLevel", 75.0f);
    }

    class XpBonusWorldScript : public WorldScript
    {
    public:
        XpBonusWorldScript() : WorldScript("XpBonusWorldScript", {
            WORLDHOOK_ON_AFTER_CONFIG_LOAD
        }) { }

        void OnAfterConfigLoad(bool /*reload*/) override
        {
            LoadConfig();
            GatherCountsByPlayer.clear();
        }
    };

    class XpBonusPlayerScript : public PlayerScript
    {
    public:
        XpBonusPlayerScript() : PlayerScript("XpBonusPlayerScript", {
            PLAYERHOOK_ON_REWARD_KILL_REWARDER,
            PLAYERHOOK_ON_SPELL_CAST
        }) { }

        // Rare and rare-elite creatures award a small bonus on top of their normal kill XP.
        // This hook fires per credited player (killer plus group members at reward distance,
        // pet owners included), so a group kill pays everyone like the normal XP does.
        // World bosses (rank 3) are excluded: endgame kills are not a leveling lever.
        void OnPlayerRewardKillRewarder(Player* player, KillRewarder* rewarder, bool /*isDungeon*/, float& /*rate*/) override
        {
            if (RareKillPerLevel <= 0.0f || !rewarder)
                return;

            Unit* victim = rewarder->GetVictim();
            if (!victim || !victim->IsCreature())
                return;

            uint32 rank = victim->ToCreature()->GetCreatureTemplate()->rank;
            if (rank != CREATURE_ELITE_RARE && rank != CREATURE_ELITE_RAREELITE)
                return;

            // victim passed so the core treats it like any kill (loot recipient and
            // rested-experience checks apply).
            AwardXp(player, RareKillPerLevel, victim, PlayerXPSource::XPSOURCE_KILL);
        }

        // Gathering (herbalism, mining, skinning) awards a small bonus per node/corpse.
        // The award happens at cast time; normally the core's CheckCast has already vetted the
        // cast (prepare's strict check runs before the hook), but directly triggered casts skip
        // CheckCast entirely — the skill gates below mirror the core's CanOpenLock and the
        // skinning block of CheckCast so no path can earn the bonus without the required skill.
        // A node taken by another player mid-cast remains a possible small overcount (bounded
        // by the daily cap).
        void OnPlayerSpellCast(Player* player, Spell* spell, bool /*skipCheck*/) override
        {
            if (GatheringPerLevel <= 0.0f || !spell || !spell->GetSpellInfo())
                return;

            SpellInfo const* spellInfo = spell->GetSpellInfo();

            // Skinning: skinnable, fully looted corpse, skill high enough — the same gates
            // Spell::CheckCast applies to SPELL_EFFECT_SKINNING.
            if (spellInfo->HasEffect(SPELL_EFFECT_SKINNING))
            {
                if (!HasSkillLine(spellInfo, SKILL_SKINNING))
                    return;

                Unit* target = spell->m_targets.GetUnitTarget();
                if (!target || !target->IsCreature())
                    return;

                Creature* creature = target->ToCreature();
                if (!(creature->GetUnitFlags() & UNIT_FLAG_SKINNABLE) ||
                    (!creature->IsCritter() && !creature->loot.isLooted()))
                    return;

                int32 skillValue = player->GetSkillValue(creature->GetCreatureTemplate()->GetRequiredLootSkill());
                int32 targetLevel = creature->GetLevel();
                int32 reqValue = skillValue < 100 ? (targetLevel - 10) * 10 : targetLevel * 5;
                if (reqValue > skillValue)
                    return;

                AwardGatheringXp(player);
                return;
            }

            if (!spellInfo->HasEffect(SPELL_EFFECT_OPEN_LOCK))
                return;

            // Herb and mining nodes: the spell's skill line must be a gathering skill, and
            // the target node's lock must pass the same skill gate Spell::CanOpenLock applies.
            if (!(HasSkillLine(spellInfo, SKILL_HERBALISM) || HasSkillLine(spellInfo, SKILL_MINING)))
                return;

            WorldObject* objTarget = spell->m_targets.GetObjectTarget();
            GameObject* node = objTarget ? objTarget->ToGameObject() : nullptr;
            if (!node)
                return;

            if (uint32 lockId = node->GetGOInfo()->GetLockId())
            {
                LockEntry const* lockInfo = sLockStore.LookupEntry(lockId);
                if (!lockInfo)
                    return;

                int32 lockType = 0;
                for (SpellEffectInfo const& effect : spellInfo->GetEffects())
                    if (effect.IsEffect(SPELL_EFFECT_OPEN_LOCK))
                        lockType = effect.MiscValue;

                bool gateMatched = false;
                for (int j = 0; j < MAX_LOCK_CASE; ++j)
                {
                    if (lockInfo->Type[j] != LOCK_KEY_SKILL || lockType != int32(lockInfo->Index[j]))
                        continue;

                    gateMatched = true;
                    SkillType skillId = SkillByLockType(LockType(lockInfo->Index[j]));
                    if (skillId != SKILL_NONE && player->GetSkillValue(skillId) < int32(lockInfo->Skill[j]))
                        return;
                }

                if (!gateMatched)
                    return;
            }

            AwardGatheringXp(player);
        }

    private:
        static bool HasSkillLine(SpellInfo const* spellInfo, uint32 skillLine)
        {
            SkillLineAbilityMapBounds bounds = sSpellMgr->GetSkillLineAbilityMapBounds(spellInfo->Id);
            for (auto itr = bounds.first; itr != bounds.second; ++itr)
                if (itr->second->SkillLine == skillLine)
                    return true;
            return false;
        }

        // In-memory anti-abuse cap, per character per server day; resets on restart
        // (documented limit in the module README and ADR-012).
        static bool ConsumeGatheringAllowance(Player* player)
        {
            uint32 today = uint32(time(nullptr) / 86400);
            auto [itr, inserted] = GatherCountsByPlayer.try_emplace(player->GetGUID().GetCounter(), today, 0);
            if (itr->second.day != today)
                itr->second = { today, 0 };

            if (itr->second.count >= GatheringDailyNodeCap)
                return false;

            ++itr->second.count;
            return true;
        }

        static void AwardGatheringXp(Player* player)
        {
            if (GatheringDailyNodeCap > 0 && !ConsumeGatheringAllowance(player))
                return;

            // No core XP source enum exists for gathering; Ancestral Wisdom ignores the
            // source, and a future consumer should treat this as world XP.
            AwardXp(player, GatheringPerLevel, nullptr, PlayerXPSource::XPSOURCE_EXPLORE);
        }
    };

    class XpBonusBattlegroundScript : public AllBattlegroundScript
    {
    public:
        XpBonusBattlegroundScript() : AllBattlegroundScript("XpBonusBattlegroundScript", {
            ALLBATTLEGROUNDHOOK_ON_BATTLEGROUND_END_REWARD
        }) { }

        // Winners of a battleground (not an arena match) get a small bonus alongside the
        // core's honor and objective XP; draws and aborted battlegrounds award nothing.
        void OnBattlegroundEndReward(Battleground* bg, Player* player, TeamId winnerTeamId) override
        {
            if (BgWinPerLevel <= 0.0f || !bg || !player || winnerTeamId == TEAM_NEUTRAL)
                return;

            if (!bg->isBattleground())
                return;

            if (player->GetBgTeamId() != winnerTeamId)
                return;

            AwardXp(player, BgWinPerLevel, nullptr, PlayerXPSource::XPSOURCE_BATTLEGROUND);
        }
    };
}

void AddXpBonusScripts()
{
    new XpBonusWorldScript();
    new XpBonusPlayerScript();
    new XpBonusBattlegroundScript();
}

void Addmod_xp_bonusScripts()
{
    AddXpBonusScripts();
}
