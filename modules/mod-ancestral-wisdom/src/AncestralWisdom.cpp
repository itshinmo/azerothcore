/*
 * Ancestral Wisdom for AzerothCore (ADR-012 revision 2026-11-20 / RFC-003 Group A).
 *
 * Local module for the modernization fork: characters gain bonus experience for every
 * max-level character on their account (Whitemane-style alt bonus, owner-reduced from
 * +15% to +10% per character; experience only, no reputation).
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
#include "DatabaseEnv.h"
#include "Player.h"
#include "PlayerScript.h"
#include "World.h"
#include "WorldScript.h"

#include <unordered_map>

namespace
{
    float PercentPerChar = 10.0f;
    float MaxBonusPercent = 0.0f; // 0 = uncapped
    // Account id -> cached count of max-level characters. Refreshed at every login and
    // when a cached character reaches the level cap; a character deleted mid-session
    // only matters after its owner logs in again.
    std::unordered_map<uint32, uint16> MaxLevelCharsByAccount;

    void LoadConfig()
    {
        PercentPerChar = sConfigMgr->GetOption<float>("AncestralWisdom.PercentPerChar", 10.0f);
        MaxBonusPercent = sConfigMgr->GetOption<float>("AncestralWisdom.MaxBonusPercent", 0.0f);
    }

    class AncestralWisdomWorldScript : public WorldScript
    {
    public:
        AncestralWisdomWorldScript() : WorldScript("AncestralWisdomWorldScript", {
            WORLDHOOK_ON_AFTER_CONFIG_LOAD
        }) { }

        void OnAfterConfigLoad(bool /*reload*/) override
        {
            LoadConfig();
            MaxLevelCharsByAccount.clear();
        }
    };

    class AncestralWisdomPlayerScript : public PlayerScript
    {
    public:
        AncestralWisdomPlayerScript() : PlayerScript("AncestralWisdomPlayerScript", {
            PLAYERHOOK_ON_LOGIN,
            PLAYERHOOK_ON_LEVEL_CHANGED,
            PLAYERHOOK_ON_GIVE_EXP
        }) { }

        void OnPlayerLogin(Player* player) override
        {
            CacheMaxLevelCount(player);
        }

        void OnPlayerLevelChanged(Player* player, uint8 /*oldLevel*/) override
        {
            if (player->GetLevel() >= sWorld->getIntConfig(CONFIG_MAX_PLAYER_LEVEL))
                CacheMaxLevelCount(player);
        }

        // Multiplies the base experience before the core applies rested or recruit-a-friend
        // bonuses, so Wisdom stacks with them (Whitemane semantics).
        void OnPlayerGiveXP(Player* player, uint32& amount, Unit* /*victim*/, uint8 /*xpSource*/) override
        {
            if (amount < 1 || PercentPerChar <= 0.0f)
                return;

            auto itr = MaxLevelCharsByAccount.find(player->GetSession()->GetAccountId());
            if (itr == MaxLevelCharsByAccount.end() || itr->second == 0)
                return;

            float bonusPercent = PercentPerChar * itr->second;
            if (MaxBonusPercent > 0.0f && bonusPercent > MaxBonusPercent)
                bonusPercent = MaxBonusPercent;

            amount = uint32(amount * (1.0f + bonusPercent / 100.0f));
        }

    private:
        static void CacheMaxLevelCount(Player* player)
        {
            uint32 accountId = player->GetSession()->GetAccountId();
            QueryResult result = CharacterDatabase.Query("SELECT COUNT(*) FROM characters WHERE account = {} AND level >= {}",
                accountId, sWorld->getIntConfig(CONFIG_MAX_PLAYER_LEVEL));
            if (result)
                MaxLevelCharsByAccount[accountId] = result->Fetch()[0].Get<uint16>();
        }
    };
}

void AddAncestralWisdomScripts()
{
    new AncestralWisdomWorldScript();
    new AncestralWisdomPlayerScript();
}

void Addmod_ancestral_wisdomScripts()
{
    AddAncestralWisdomScripts();
}
