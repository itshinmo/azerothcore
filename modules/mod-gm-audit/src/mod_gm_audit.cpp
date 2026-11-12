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

#include "AccountMgr.h"
#include "AllCommandScript.h"
#include "Chat.h"
#include "DatabaseEnv.h"
#include "Log.h"
#include "Player.h"
#include "RBAC.h"
#include "Realm.h"
#include "ScriptMgr.h"
#include "World.h"
#include "WorldSession.h"

#include <cctype>
#include <string>
#include <string_view>
#include <vector>

namespace
{
    bool ShouldAudit(WorldSession* session)
    {
        if (!session)
            return true; // console

        if (session->GetSecurity() > SEC_PLAYER)
            return true;

        rbac::RBACData* data = session->GetRBACData();
        if (!data)
        {
            session->LoadPermissions();
            data = session->GetRBACData();
        }

        if (!data || data->GetGrantedPermissions().empty())
            return true; // load failure: audit rather than bypass

        rbac::RBACPermissionContainer const& defaults =
            sAccountMgr->GetRBACDefaultPermissions(session->GetSecurity());

        for (uint32 permission : data->GetGrantedPermissions())
            if (defaults.find(permission) == defaults.end())
                return true;

        return false;
    }

    std::vector<std::string> TokenizeCommand(std::string const& command)
    {
        std::vector<std::string> tokens;
        std::string token;
        for (char c : command)
        {
            if (std::isspace(static_cast<unsigned char>(c)))
            {
                if (!token.empty())
                {
                    tokens.push_back(token);
                    token.clear();
                }
            }
            else
                token += c;
        }

        if (!token.empty())
            tokens.push_back(token);

        return tokens;
    }

    bool IsTokenPrefix(std::string const& token, std::string_view word)
    {
        if (token.empty() || token.size() > word.size())
            return false;

        for (std::size_t i = 0; i < token.size(); ++i)
            if (std::tolower(static_cast<unsigned char>(token[i])) != std::tolower(static_cast<unsigned char>(word[i])))
                return false;

        return true;
    }

    bool HasSensitiveArguments(std::string const& command)
    {
        std::vector<std::string> const tokens = TokenizeCommand(command);
        if (tokens.size() < 2 || !IsTokenPrefix(tokens[0], "account"))
            return false;

        if (IsTokenPrefix(tokens[1], "create")
            || IsTokenPrefix(tokens[1], "password")
            || IsTokenPrefix(tokens[1], "2fa"))
            return true;

        return IsTokenPrefix(tokens[1], "set")
            && tokens.size() >= 3
            && (IsTokenPrefix(tokens[2], "password")
                || IsTokenPrefix(tokens[2], "2fa")
                || IsTokenPrefix(tokens[2], "email"));
    }

    std::string Escape(std::string value)
    {
        LoginDatabase.EscapeString(value);
        return value;
    }
}

class GmAuditScript : public AllCommandScript
{
public:
    GmAuditScript() : AllCommandScript("mod_gm_audit") { }

    bool OnTryExecuteCommand(ChatHandler& handler, std::string_view cmdStr) override
    {
        if (!ShouldAudit(handler.GetSession()))
            return true;

        std::string full{ cmdStr };
        while (!full.empty() && full.front() == '.')
            full.erase(full.begin());

        if (full.empty())
            return true;

        std::size_t const split = full.find(' ');
        std::string const command = split == std::string::npos ? full : full.substr(0, split);
        std::string arguments = split == std::string::npos ? "" : full.substr(split + 1);
        if (HasSensitiveArguments(full))
            arguments = "<redacted>";

        uint32 accountId = 0;
        std::string accountName = "CONSOLE";
        std::string playerName;
        uint64 playerGuid = 0;

        if (WorldSession* session = handler.GetSession())
        {
            accountId = session->GetAccountId();
            if (!AccountMgr::GetName(accountId, accountName))
                accountName.clear();

            if (Player* player = session->GetPlayer())
            {
                playerName = player->GetName();
                playerGuid = player->GetGUID().GetRawValue();
            }
        }

        std::string const sql = Acore::StringFormat(
            "INSERT INTO `gm_audit_log` "
            "(`realm_id`, `account_id`, `account_name`, `player_name`, `player_guid`, `command`, `arguments`) "
            "VALUES ({}, {}, '{}', '{}', {}, '{}', '{}')",
            realm.Id.Realm, accountId, Escape(accountName), Escape(playerName), playerGuid,
            Escape(command), Escape(arguments));

        if (!LoginDatabase.DirectExecute(sql))
        {
            LOG_ERROR("module.gm-audit", "Could not write audit row for account {} command '{}'; command aborted.",
                accountId, command);
            handler.SendSysMessage("Command aborted: audit write failed.");
            return false;
        }

        return true;
    }
};

void Addmod_gm_auditScripts()
{
    new GmAuditScript();
}
