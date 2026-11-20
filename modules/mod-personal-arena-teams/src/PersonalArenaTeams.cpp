/*
 * Personal arena teams for AzerothCore (ADR-024, RFC-003 Group D).
 *
 * Local module for the modernization fork: rated arena premades queue without buying a charter —
 * when a group leader queues rated and has no team of that bracket, a personal team named after
 * the leader is created and the group joins it. Solo rated 3v3 is served by mod-arena-3v3-solo-queue.
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
#include "ArenaTeam.h"
#include "ArenaTeamMgr.h"
#include "Group.h"
#include "Player.h"
#include "PlayerScript.h"
#include "ScriptMgr.h"
#include "WorldScript.h"

namespace
{
    bool Enabled = true;

    void LoadConfig()
    {
        Enabled = sConfigMgr->GetOption<bool>("PersonalArenaTeams.Enable", true);
    }

    class PersonalArenaTeamsWorldScript : public WorldScript
    {
    public:
        PersonalArenaTeamsWorldScript() : WorldScript("PersonalArenaTeamsWorldScript", {
            WORLDHOOK_ON_AFTER_CONFIG_LOAD
        }) { }

        void OnAfterConfigLoad(bool /*reload*/) override
        {
            LoadConfig();
        }
    };

    class PersonalArenaTeamsPlayerScript : public PlayerScript
    {
    public:
        PersonalArenaTeamsPlayerScript() : PlayerScript("PersonalArenaTeamsPlayerScript", {
            PLAYERHOOK_CAN_JOIN_IN_ARENA_QUEUE
        }) { }

        // Runs before the queue handler's team checks: creating the team here lets the
        // handler's own rated-group flow (BattleGroundHandler reads GetArenaTeamId) proceed
        // normally. Solo rated 3v3 is not this module's job (solo-queue module owns it, via a
        // separate fake bracket slot).
        bool OnPlayerCanJoinInArenaQueue(Player* player, ObjectGuid /*battlemasterGuid*/, uint8 arenaslot,
            BattlegroundTypeId /*bgTypeId*/, uint8 joinAsGroup, uint8 isRated, GroupJoinBattlegroundResult& err) override
        {
            if (!Enabled || !isRated || !joinAsGroup || !player || arenaslot > 2)
                return true;

            Group* group = player->GetGroup();
            if (!group || group->GetLeaderGUID() != player->GetGUID())
                return true;

            uint8 teamType = arenaslot == 0 ? 2 : arenaslot == 1 ? 3 : 5;

            // Leader's personal team of this bracket, or the team they already belong to.
            ArenaTeam* team = sArenaTeamMgr->GetArenaTeamByCaptain(player->GetGUID(), teamType);
            if (!team)
            {
                // In a team of this bracket they are not the captain of: leave it alone.
                if (player->GetArenaTeamId(arenaslot))
                    return true;

                team = CreatePersonalTeam(player, teamType, player->GetName());
                if (!team)
                    team = CreatePersonalTeam(player, teamType, player->GetName() + " Arena");

                if (!team)
                    return true;
            }

            // Ensure-members pass on EVERY queue attempt: Group::CanJoinBattlegroundQueue
            // requires every member's team id to match the leader's, so a premade whose
            // members drifted out (double-queue conflicts, roster changes, a refused first
            // attempt that never reached creation) must be re-synced before the join.
            group->DoForAllMembers([team, arenaslot](Player* member)
            {
                // AddMember refuses double joins itself; the explicit check keeps a member
                // already in another team of this bracket out of the personal team.
                if (member->GetGUID() != team->GetCaptain() && !member->GetArenaTeamId(arenaslot))
                    team->AddMember(member->GetGUID());
            });

            return true;
        }

    private:
        // Returns the created team (kept by the arena team manager), or null.
        static ArenaTeam* CreatePersonalTeam(Player* player, uint8 teamType, std::string const& name)
        {
            // ArenaTeam::Create checks the name is free and adds the captain as member.
            ArenaTeam* team = new ArenaTeam();
            if (!team->Create(player->GetGUID(), teamType, name, 4194303, 44, 4231054, 22, 4679533))
            {
                delete team;
                return nullptr;
            }

            sArenaTeamMgr->AddArenaTeam(team);
            return team;
        }
    };
}

void AddPersonalArenaTeamsScripts()
{
    new PersonalArenaTeamsWorldScript();
    new PersonalArenaTeamsPlayerScript();
}

void Addmod_personal_arena_teamsScripts()
{
    AddPersonalArenaTeamsScripts();
}
