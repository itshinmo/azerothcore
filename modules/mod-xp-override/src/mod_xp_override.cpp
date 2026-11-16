/*
 * This file is part of the AzerothCore Project. See AUTHORS file for Copyright information
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
 * for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#include "AccountScript.h"
#include "Chat.h"
#include "CommandScript.h"
#include "Common.h"
#include "DatabaseEnv.h"
#include "GameTime.h"
#include "Log.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "World.h"
#include "WorldSession.h"
#include "XpOverride.h"

#include <chrono>
#include <unordered_map>
#include <unordered_set>

namespace
{
    // Login, command, XP, and account hooks all run on the world thread.
    std::unordered_set<uint32> overriddenAccounts;
    std::unordered_map<uint32, Milliseconds> toggleReadyAt;

    constexpr Milliseconds TOGGLE_COOLDOWN{ 5000 };

    void LoadOverride(uint32 accountId)
    {
        if (LoginDatabase.Query("SELECT `account_id` FROM `account_xp_override` WHERE `account_id` = {}", accountId))
            overriddenAccounts.insert(accountId);
        else
            overriddenAccounts.erase(accountId);
    }

    float RateFor(XpOverride::XpRate rate)
    {
        using XpOverride::XpRate;

        switch (rate)
        {
            case XpRate::Kill:              return sWorld->getRate(RATE_XP_KILL);
            case XpRate::BgKillAV:          return sWorld->getRate(RATE_XP_BG_KILL_AV);
            case XpRate::BgKillWSG:         return sWorld->getRate(RATE_XP_BG_KILL_WSG);
            case XpRate::BgKillAB:          return sWorld->getRate(RATE_XP_BG_KILL_AB);
            case XpRate::BgKillEOTS:        return sWorld->getRate(RATE_XP_BG_KILL_EOTS);
            case XpRate::BgKillSOTA:        return sWorld->getRate(RATE_XP_BG_KILL_SOTA);
            case XpRate::BgKillIC:          return sWorld->getRate(RATE_XP_BG_KILL_IC);
            case XpRate::Quest:             return sWorld->getRate(RATE_XP_QUEST);
            case XpRate::QuestDf:           return sWorld->getRate(RATE_XP_QUEST_DF);
            case XpRate::Explore:           return sWorld->getRate(RATE_XP_EXPLORE);
            case XpRate::BattlegroundBonus: return sWorld->getRate(RATE_XP_BATTLEGROUND_BONUS);
            case XpRate::None:              return 0.0f;
        }

        return 0.0f;
    }
}

class XpOverrideCommandScript : public CommandScript
{
public:
    XpOverrideCommandScript() : CommandScript("mod_xp_override_command") { }

    Acore::ChatCommands::ChatCommandTable GetCommands() const override
    {
        static Acore::ChatCommands::ChatCommandTable commandTable =
        {
            { "xp", HandleXpCommand, SEC_PLAYER, Acore::ChatCommands::Console::No }
        };
        return commandTable;
    }

    static bool HandleXpCommand(ChatHandler* handler)
    {
        Player* player = handler->GetPlayer();
        if (!player)
        {
            handler->SendErrorMessage("This command can only be used in game.");
            return false;
        }

        uint32 const accountId = player->GetSession()->GetAccountId();
        Milliseconds const now = GameTime::GetGameTimeMS();
        auto const ready = toggleReadyAt.find(accountId);
        if (ready != toggleReadyAt.end() && now < ready->second)
        {
            auto const wait = std::chrono::ceil<std::chrono::seconds>(ready->second - now).count();
            if (wait == 1)
                handler->SendErrorMessage("Wait 1 second before toggling the experience override again.");
            else
                handler->SendErrorMessage(
                    "Wait {} seconds before toggling the experience override again.", wait);
            return false;
        }
        toggleReadyAt[accountId] = now + TOGGLE_COOLDOWN;

        if (overriddenAccounts.contains(accountId))
        {
            if (!LoginDatabase.DirectExecute(
                    "DELETE FROM `account_xp_override` WHERE `account_id` = {}", accountId))
            {
                handler->SendErrorMessage("Could not save the experience override. Try again later.");
                return false;
            }

            overriddenAccounts.erase(accountId);
            handler->SendSysMessage("Experience override removed. This account now uses the realm default.");
            return true;
        }

        if (!LoginDatabase.DirectExecute(
                "INSERT INTO `account_xp_override` (`account_id`) VALUES ({}) "
                "ON DUPLICATE KEY UPDATE `account_id` = `account_id`", accountId))
        {
            handler->SendErrorMessage("Could not save the experience override. Try again later.");
            return false;
        }

        overriddenAccounts.insert(accountId);
        handler->SendSysMessage("Experience override enabled: 1x. Use .xp again to return to the realm default.");
        return true;
    }
};

class XpOverridePlayerScript : public PlayerScript
{
public:
    XpOverridePlayerScript() : PlayerScript("mod_xp_override_player") { }

    void OnPlayerLogin(Player* player) override
    {
        LoadOverride(player->GetSession()->GetAccountId());
    }

    void OnPlayerGiveXP(Player* player, uint32& amount, Unit* /*victim*/, uint8 xpSource) override
    {
        uint32 const accountId = player->GetSession()->GetAccountId();
        if (amount == 0 || !overriddenAccounts.contains(accountId))
            return;

        XpOverride::XpRate const rate = XpOverride::SelectRate(
            xpSource, player->InBattleground(), player->GetMapId());
        amount = XpOverride::ComputeOverriddenXp(amount, RateFor(rate));
    }
};

class XpOverrideAccountScript : public AccountScript
{
public:
    XpOverrideAccountScript() : AccountScript("mod_xp_override_account") { }

    void OnBeforeAccountDelete(uint32 accountId) override
    {
        // Account deletion already blocks on database work; keep the cleanup with it.
        if (!LoginDatabase.DirectExecute(
                "DELETE FROM `account_xp_override` WHERE `account_id` = {}", accountId))
            LOG_ERROR("module.xp-override",
                "Could not delete the experience override for account {}.", accountId);

        overriddenAccounts.erase(accountId);
        toggleReadyAt.erase(accountId);
    }
};

void Addmod_xp_overrideScripts()
{
    new XpOverrideCommandScript();
    new XpOverridePlayerScript();
    new XpOverrideAccountScript();
}
