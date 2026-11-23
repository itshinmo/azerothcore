/*
 * mod-objectives: script hooks, addon transport and the reward vendor gossip.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Affero General Public License as published by the
 * Free Software Foundation; either version 3 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public
 * License for more details.
 */

#include "Objectives.h"

#include "AllBattlegroundScript.h"
#include "Battleground.h"
#include "Creature.h"
#include "CreatureScript.h"
#include "KillRewarder.h"
#include "Player.h"
#include "PlayerScript.h"
#include "QuestDef.h"
#include "ScriptedGossip.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "Unit.h"
#include "WorldScript.h"

namespace
{
    class ObjectivesWorldScript : public WorldScript
    {
    public:
        ObjectivesWorldScript() : WorldScript("ObjectivesWorldScript", {
            WORLDHOOK_ON_AFTER_CONFIG_LOAD,
            WORLDHOOK_ON_STARTUP,
            WORLDHOOK_ON_UPDATE,
            WORLDHOOK_ON_SHUTDOWN
        }) { }

        void OnAfterConfigLoad(bool reload) override
        {
            Objectives::LoadConfig(reload);
        }

        void OnStartup() override
        {
            Objectives::Startup();
        }

        void OnUpdate(uint32 diff) override
        {
            Objectives::OnUpdate(diff);
        }

        void OnShutdown() override
        {
            Objectives::OnShutdown();
        }
    };

    class ObjectivesPlayerScript : public PlayerScript
    {
    public:
        ObjectivesPlayerScript() : PlayerScript("ObjectivesPlayerScript", {
            PLAYERHOOK_ON_LOGIN,
            PLAYERHOOK_ON_LOGOUT,
            PLAYERHOOK_ON_REWARD_KILL_REWARDER,
            PLAYERHOOK_ON_PLAYER_COMPLETE_QUEST,
            PLAYERHOOK_CAN_PLAYER_USE_PRIVATE_CHAT
        }) { }

        void OnPlayerLogin(Player* player) override
        {
            Objectives::OnLogin(player);
        }

        void OnPlayerLogout(Player* player) override
        {
            Objectives::OnLogout(player);
        }

        // The core calls this once per credited player, including group members at reward distance
        // and pet owners, so the module does not implement its own group scan.
        void OnPlayerRewardKillRewarder(Player* player, KillRewarder* rewarder, bool /*isDungeon*/,
            float& /*rate*/) override
        {
            if (!rewarder)
                return;

            Unit* victim = rewarder->GetVictim();
            if (!victim || !victim->IsCreature())
                return;

            Objectives::OnCreatureKill(player, victim->ToCreature());
        }

        void OnPlayerCompleteQuest(Player* player, Quest const* quest) override
        {
            Objectives::OnQuestComplete(player, quest);
        }

        bool OnPlayerCanUseChat(Player* player, uint32 /*type*/, uint32 language, std::string& message,
            Player* receiver) override
        {
            return Objectives::OnAddonChat(player, language, message, receiver);
        }
    };

    class ObjectivesBattlegroundScript : public AllBattlegroundScript
    {
    public:
        ObjectivesBattlegroundScript() : AllBattlegroundScript("ObjectivesBattlegroundScript", {
            ALLBATTLEGROUNDHOOK_ON_BATTLEGROUND_END_REWARD
        }) { }

        void OnBattlegroundEndReward(Battleground* battleground, Player* player,
            TeamId winnerTeamId) override
        {
            if (!battleground || !player || winnerTeamId == TEAM_NEUTRAL)
                return;
            if (!battleground->isBattleground() || player->GetBgTeamId() != winnerTeamId)
                return;

            Objectives::OnBattlegroundWin(player, uint32(battleground->GetBgTypeID(false)));
        }
    };

    class ObjectivesVendorScript : public CreatureScript
    {
    public:
        ObjectivesVendorScript() : CreatureScript("npc_objectives_vendor") { }

        bool OnGossipHello(Player* player, Creature* creature) override
        {
            return Objectives::OnVendorGossipHello(player, creature);
        }

        bool OnGossipSelect(Player* player, Creature* creature, uint32 sender, uint32 action) override
        {
            if (sender != GOSSIP_SENDER_MAIN)
                return false;
            return Objectives::OnVendorGossipSelect(player, creature, action);
        }
    };
}

void Addmod_objectivesScripts()
{
    new ObjectivesWorldScript();
    new ObjectivesPlayerScript();
    new ObjectivesBattlegroundScript();
    new ObjectivesVendorScript();
}
