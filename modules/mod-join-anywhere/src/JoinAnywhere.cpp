/*
 * Queue-from-anywhere for AzerothCore (ADR-024, RFC-003 Group D).
 *
 * Local module for the modernization fork: a player chat command that joins a battleground
 * queue without walking to a battlemaster — the Netherwing-style ".join ab" shape, renamed
 * to ".queue" because /join is the client's reserved channel command.
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

#include "BattlegroundMgr.h"
#include "Chat.h"
#include "CommandScript.h"
#include "DBCStores.h"
#include "DisableMgr.h"
#include "LFG.h"
#include "LFGMgr.h"
#include "Player.h"
#include "RBAC.h"
#include "ScriptMgr.h"

#include <algorithm>
#include <string>
#include <string_view>
#include <unordered_map>

using namespace Acore::ChatCommands;

namespace
{
    // Battleground name tokens accepted by the command.
    std::unordered_map<std::string_view, BattlegroundTypeId> const BgNames = {
        { "wsg", BattlegroundTypeId::BATTLEGROUND_WS },
        { "ab", BattlegroundTypeId::BATTLEGROUND_AB },
        { "av", BattlegroundTypeId::BATTLEGROUND_AV },
        { "eots", BattlegroundTypeId::BATTLEGROUND_EY },
        { "sota", BattlegroundTypeId::BATTLEGROUND_SA },
        { "ic", BattlegroundTypeId::BATTLEGROUND_IC },
        { "random", BattlegroundTypeId::BATTLEGROUND_RB },
    };

    class QueueAnywhereCommandScript : public CommandScript
    {
    public:
        QueueAnywhereCommandScript() : CommandScript("QueueAnywhereCommandScript") { }

        ChatCommandTable GetCommands() const override
        {
            // 950150 = "Command: queue bg (project)", created and granted to role 199 (Player
            // Commands) by data/sql/custom/db_auth/queue_anywhere_command.sql; the literal
            // avoids a core enum edit (house rule: modules do not edit core files).
            static ChatCommandTable queueAnywhereCommandTable =
            {
                { "bg", HandleQueueCommand, 950150, Console::No }
            };

            static ChatCommandTable commandTable =
            {
                { "queue", queueAnywhereCommandTable }
            };

            return commandTable;
        }

    private:
        // ".queue bg <wsg|ab|av|eots|sota|ic|random>" joins solo, from anywhere. The
        // eligibility ladder mirrors the core battlemaster join path
        // (WorldSession::HandleBattlemasterJoinOpcode); a drift there is a bug here.
        static bool HandleQueueCommand(ChatHandler* handler, std::string_view args)
        {
            Player* player = handler->GetPlayer();
            if (!player)
                return false;

            if (player->InBattleground())
            {
                handler->SendSysMessage("You are already in a battleground.");
                return true;
            }

            std::string token(args);
            std::transform(token.begin(), token.end(), token.begin(), ::tolower);
            token.erase(token.find_last_not_of(" \t") + 1);

            auto itr = BgNames.find(token);
            if (itr == BgNames.end())
            {
                handler->SendSysMessage("Usage: .queue bg <wsg|ab|av|eots|sota|ic|random>");
                return true;
            }

            BattlegroundTypeId bgTypeId = itr->second;
            BattlegroundQueueTypeId bgQueueTypeId = BattlegroundMgr::BGQueueTypeId(bgTypeId, 0);
            BattlegroundQueueTypeId bgQueueTypeIdRandom = BattlegroundMgr::BGQueueTypeId(BATTLEGROUND_RB, 0);

            Battleground* bg = sBattlegroundMgr->GetBattlegroundTemplate(bgTypeId);
            if (!bg)
                return true;

            PvPDifficultyEntry const* bracket = GetBattlegroundBracketByLevel(bg->GetMapId(), player->GetLevel());
            if (!bracket)
                return true;

            if (!player->HasFreeBattlegroundQueueId())
            {
                handler->SendSysMessage("You have too many active queues.");
                return true;
            }

            GroupJoinBattlegroundResult err = GroupJoinBattlegroundResult(bg->GetBgTypeID());

            if (!sScriptMgr->OnPlayerCanJoinInBattlegroundQueue(player, player->GetGUID(), bgTypeId, false, err) && err <= 0)
            {
                SendQueueResult(player, err);
                return true;
            }

            BattlegroundQueue& bgQueue = sBattlegroundMgr->GetBattlegroundQueue(bgQueueTypeId);

            lfg::LfgState lfgState = sLFGMgr->GetState(player->GetGUID());
            if (sDisableMgr->IsDisabledFor(DISABLE_TYPE_BATTLEGROUND, bgTypeId, nullptr))
                err = ERR_BATTLEGROUND_NOT_IN_BATTLEGROUND;
            else if (player->InBattleground())
                err = ERR_BATTLEGROUND_NOT_IN_BATTLEGROUND;
            else if (player->HasPlayerFlag(PLAYER_FLAGS_NO_PLAY_TIME))
                err = ERR_GROUP_JOIN_BATTLEGROUND_FAIL;
            else if (lfgState > lfg::LFG_STATE_NONE && (lfgState != lfg::LFG_STATE_QUEUED || !sWorld->getBoolConfig(CONFIG_ALLOW_JOIN_BG_AND_LFG)))
                err = ERR_LFG_CANT_USE_BATTLEGROUND;
            else if (!player->CanJoinToBattleground(bg))
                err = ERR_GROUP_JOIN_BATTLEGROUND_DESERTERS;
            else if (player->InBattlegroundQueueForBattlegroundQueueType(bgQueueTypeIdRandom))
                err = ERR_IN_RANDOM_BG;
            else if (player->InBattlegroundQueueForBattlegroundQueueType(bgQueueTypeId))
                err = ERR_BATTLEGROUND_NONE;
            else if (player->InBattlegroundQueue() && bgTypeId == BATTLEGROUND_RB)
                err = ERR_IN_NON_RANDOM_BG;
            else if (player->InBattlegroundQueueForBattlegroundQueueType(BATTLEGROUND_QUEUE_2v2) ||
                     player->InBattlegroundQueueForBattlegroundQueueType(BATTLEGROUND_QUEUE_3v3) ||
                     player->InBattlegroundQueueForBattlegroundQueueType(BATTLEGROUND_QUEUE_5v5))
                err = ERR_BATTLEGROUND_QUEUED_FOR_RATED;
            else if (player->IsClass(CLASS_DEATH_KNIGHT, CLASS_CONTEXT_TELEPORT) && player->GetMapId() == MAP_EBON_HOLD &&
                     !player->IsGameMaster() && !player->HasSpell(50977))
                err = ERR_BATTLEGROUND_NONE;
            else if (!player->GetBGAccessByLevel(bgTypeId))
                err = ERR_BATTLEGROUND_NONE;

            if (err <= 0)
            {
                SendQueueResult(player, err);
                return true;
            }

            GroupQueueInfo* ginfo = bgQueue.AddGroup(player, nullptr, bgTypeId, bracket, 0, false, false, 0, 0);
            if (!ginfo)
            {
                handler->SendSysMessage("You cannot join that queue right now.");
                return true;
            }

            uint32 avgWaitTime = bgQueue.GetAverageQueueWaitTime(ginfo);
            uint32 queueSlot = player->AddBattlegroundQueueId(bgQueueTypeId);

            WorldPacket data;
            sBattlegroundMgr->BuildBattlegroundStatusPacket(&data, bg, queueSlot, STATUS_WAIT_QUEUE, avgWaitTime, 0, 0, TEAM_NEUTRAL);
            player->GetSession()->SendPacket(&data);

            sBattlegroundMgr->ScheduleQueueUpdate(0, 0, bgQueueTypeId, bgTypeId, bracket->GetBracketId());

            sScriptMgr->OnPlayerJoinBG(player);
            return true;
        }

        static void SendQueueResult(Player* player, GroupJoinBattlegroundResult err)
        {
            WorldPacket data;
            sBattlegroundMgr->BuildGroupJoinedBattlegroundPacket(&data, err);
            player->GetSession()->SendPacket(&data);
        }
    };
}

void AddJoinAnywhereScripts()
{
    new QueueAnywhereCommandScript();
}

void Addmod_join_anywhereScripts()
{
    AddJoinAnywhereScripts();
}
