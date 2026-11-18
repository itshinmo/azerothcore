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
#include "BanMgr.h"
#include "CharacterCache.h"
#include "Config.h"
#include "DatabaseEnv.h"
#include "GmApiAuth.h"
#include "GmApiBody.h"
#include "HMAC.h"
#include "Item.h"
#include "Log.h"
#include "Mail.h"
#include "Map.h"
#include "MapMgr.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "RBAC.h"
#include "Realm.h"
#include "ScriptMgr.h"
#include "StringFormat.h"
#include "Util.h"
#include "World.h"
#include "WorldScript.h"
#include "WorldSession.h"
#include "WorldSessionMgr.h"

#include <boost/asio/ip/tcp.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/beast/core.hpp>
#include <boost/beast/core/tcp_stream.hpp>
#include <boost/beast/http.hpp>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cerrno>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <exception>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>
#include <unordered_map>
#include <vector>

namespace beast = boost::beast;
namespace http = beast::http;
namespace net = boost::asio;
using tcp = net::ip::tcp;

namespace
{
    constexpr uint32 MAX_SESSIONS = 64;

    struct RateWindow
    {
        uint32 count = 0;
        uint32 minute = 0;
    };

    std::string JsonEscape(std::string_view value)
    {
        static char const* hex = "0123456789abcdef";
        std::string out;
        out.reserve(value.size() + 8);
        for (unsigned char c : value)
        {
            switch (c)
            {
                case '"': out += "\\\""; break;
                case '\\': out += "\\\\"; break;
                case '\b': out += "\\b"; break;
                case '\f': out += "\\f"; break;
                case '\n': out += "\\n"; break;
                case '\r': out += "\\r"; break;
                case '\t': out += "\\t"; break;
                default:
                    if (c < 0x20)
                    {
                        out += "\\u00";
                        out += hex[c >> 4];
                        out += hex[c & 0x0f];
                    }
                    else
                        out += char(c);
                    break;
            }
        }
        return out;
    }

    std::string JsonError(std::string_view error)
    {
        return R"({"error":")" + JsonEscape(error) + R"("})";
    }

    bool ConstantTimeEqual(std::string const& left, std::string const& right)
    {
        if (left.size() != right.size())
            return false;

        unsigned char diff = 0;
        for (std::size_t i = 0; i < left.size(); ++i)
            diff |= static_cast<unsigned char>(left[i] ^ right[i]);
        return diff == 0;
    }

    struct Actor
    {
        uint32 accountId = 0;
        std::string name;
        uint8 security = 0;
    };

    /// A write runs on the world thread; the HTTP thread waits for the outcome.
    struct WriteJob
    {
        void Finish(http::status newStatus, std::string newBody)
        {
            std::lock_guard<std::mutex> lock(mutex);
            status = newStatus;
            body = std::move(newBody);
            done = true;
            cv.notify_all();
        }

        bool Wait(std::chrono::seconds timeout)
        {
            std::unique_lock<std::mutex> lock(mutex);
            return cv.wait_for(lock, timeout, [this]() { return done; });
        }

        void Cancel() { cancelled = true; }

        /// Only one terminal audit outcome may be written for a job.
        bool ClaimOutcome()
        {
            bool expected = false;
            return outcomeClaimed.compare_exchange_strong(expected, true);
        }

        std::mutex mutex;
        std::condition_variable cv;
        bool done = false;
        std::atomic<bool> cancelled{ false };
        std::atomic<bool> outcomeClaimed{ false };
        http::status status = http::status::service_unavailable;
        std::string body = R"({"error":"world_unavailable"})";

        Actor auditActor;
        std::string auditCommand;
        std::string auditArguments;
        std::string auditPlayerName;
    };

    struct QueuedJob
    {
        std::shared_ptr<WriteJob> job;
        std::function<void()> action;
    };

    uint32 ParseAccountId(std::string_view actor)
    {
        uint64 value = 0;
        for (char c : actor)
            value = value * 10 + static_cast<uint64>(c - '0');
        return static_cast<uint32>(value);
    }

    bool ResolveActor(uint32 accountId, Actor& actor)
    {
        if (accountId == 0)
            return false;

        actor.accountId = accountId;
        if (!AccountMgr::GetName(accountId, actor.name))
            return false;

        actor.security = static_cast<uint8>(AccountMgr::GetSecurity(accountId, realm.Id.Realm));
        return true;
    }

    std::string Escape(std::string const& value)
    {
        // Local escaping keeps audit writes thread-safe; DatabaseWorkerPool::EscapeString uses a
        // shared synchronous connection without a lock. Single quotes are doubled so the result is
        // also safe when NO_BACKSLASH_ESCAPES is set.
        std::string out;
        out.reserve(value.size() + 8);
        for (char c : value)
        {
            switch (c)
            {
                case '\0': out += "\\0"; break;
                case '\n': out += "\\n"; break;
                case '\r': out += "\\r"; break;
                case 0x1a: out += "\\Z"; break;
                case '\'': out += "''"; break;
                case '\\': out += "\\\\"; break;
                default: out += c; break;
            }
        }
        return out;
    }

    bool WriteAudit(Actor const& actor, std::string const& command, std::string const& arguments,
        std::string const& playerName, uint64 playerGuid, std::string const& result)
    {
        std::string const sql = Acore::StringFormat(
            "INSERT INTO `gm_audit_log` "
            "(`realm_id`, `account_id`, `account_name`, `player_name`, `player_guid`, `command`, "
            "`arguments`, `result`) "
            "VALUES ({}, {}, '{}', '{}', {}, '{}', '{}', '{}')",
            realm.Id.Realm, actor.accountId, Escape(actor.name), Escape(playerName), playerGuid,
            Escape(command), Escape(arguments), Escape(result));

        if (!LoginDatabase.DirectExecute(sql))
        {
            LOG_ERROR("module.gm-api", "Could not write audit row for account {} command '{}'",
                actor.accountId, command);
            return false;
        }

        return true;
    }

    void FinishWrite(Actor const& actor, std::string const& command, std::string const& arguments,
        std::string const& playerName, uint64 playerGuid, std::string const& result,
        http::status status, std::shared_ptr<WriteJob> const& job,
        std::string_view bodyError = {})
    {
        if (!job->ClaimOutcome())
            return;

        if (!WriteAudit(actor, command, arguments, playerName, playerGuid, result))
        {
            job->Finish(http::status::internal_server_error, JsonError("audit_failed"));
            return;
        }

        if (status == http::status::ok)
            job->Finish(status, R"({"status":"ok"})");
        else
            job->Finish(status, JsonError(bodyError.empty() ? result : std::string(bodyError)));
    }

    void ExecutePlayerAction(Actor const& actor, std::string const& command, std::string const& action,
        std::string const& playerName, std::shared_ptr<WriteJob> const& job)
    {
        Player* player = ObjectAccessor::FindPlayerByName(playerName);
        if (!player || !player->GetSession())
        {
            FinishWrite(actor, command, playerName, playerName, 0, "target_not_found",
                http::status::not_found, job);
            return;
        }

        WorldSession* session = player->GetSession();
        uint64 const guid = player->GetGUID().GetRawValue();
        std::string const name = player->GetName();

        if (session->GetAccountId() == actor.accountId)
        {
            FinishWrite(actor, command, playerName, name, guid, "cannot_target_self",
                http::status::conflict, job);
            return;
        }

        if (AccountMgr::GetSecurity(session->GetAccountId(), realm.Id.Realm) >= actor.security)
        {
            FinishWrite(actor, command, playerName, name, guid, "forbidden_target_security",
                http::status::forbidden, job, "forbidden");
            return;
        }

        if (action == "kick")
        {
            session->KickPlayer("GM API");
        }
        else
        {
            if (player->IsInFlight() || player->IsInCombat())
            {
                FinishWrite(actor, command, playerName, name, guid, "player_busy",
                    http::status::conflict, job);
                return;
            }

            if (!player->TeleportTo(player->m_homebindMapId, player->m_homebindX, player->m_homebindY,
                    player->m_homebindZ, player->GetOrientation()))
            {
                FinishWrite(actor, command, playerName, name, guid, "teleport_failed",
                    http::status::internal_server_error, job);
                return;
            }
        }

        FinishWrite(actor, command, playerName, name, guid, "success", http::status::ok, job);
    }

    struct WriteSpec
    {
        std::string command;
        std::string arguments;
        std::string playerName;
        std::vector<uint32> permissions;
    };

    bool CheckTargetAccount(Actor const& actor, uint32 accountId, std::string const& targetName,
        std::string const& command, std::string const& arguments,
        std::shared_ptr<WriteJob> const& job)
    {
        if (accountId == actor.accountId)
        {
            FinishWrite(actor, command, arguments, targetName, 0, "cannot_target_self",
                http::status::conflict, job);
            return false;
        }

        if (AccountMgr::GetSecurity(accountId, realm.Id.Realm) >= actor.security)
        {
            FinishWrite(actor, command, arguments, targetName, 0, "forbidden_target_security",
                http::status::forbidden, job, "forbidden");
            return false;
        }

        return true;
    }

    bool CheckTargetAccount(Actor const& actor, WorldSession* session, std::string const& targetName,
        std::string const& command, std::string const& arguments,
        std::shared_ptr<WriteJob> const& job)
    {
        return session && CheckTargetAccount(actor, session->GetAccountId(), targetName, command,
            arguments, job);
    }

    void ExecuteAddItem(Actor const& actor, std::string const& command, std::string const& arguments,
        std::string const& playerName, std::string const& body, std::shared_ptr<WriteJob> const& job)
    {
        GmApiBody::ItemGrantRequest request;
        std::string error;
        if (!GmApiBody::ParseItemGrant(body, request, error))
        {
            FinishWrite(actor, command, arguments, playerName, 0, error,
                http::status::bad_request, job);
            return;
        }

        ItemTemplate const* itemTemplate = sObjectMgr->GetItemTemplate(request.itemId);
        if (!itemTemplate || (itemTemplate->MaxCount > 0
                && request.count > static_cast<uint32>(itemTemplate->MaxCount)))
        {
            FinishWrite(actor, command, arguments, playerName, 0, "invalid_item",
                http::status::bad_request, job);
            return;
        }

        Player* player = ObjectAccessor::FindPlayerByName(playerName);
        if (!player || !player->GetSession())
        {
            FinishWrite(actor, command, arguments, playerName, 0, "target_not_found",
                http::status::not_found, job);
            return;
        }

        uint64 const guid = player->GetGUID().GetRawValue();
        std::string const name = player->GetName();
        if (!CheckTargetAccount(actor, player->GetSession(), name, command, arguments, job))
            return;

        ItemPosCountVec dest;
        uint32 noSpace = 0;
        InventoryResult const storeResult = player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest,
            request.itemId, request.count, &noSpace);
        if (storeResult != EQUIP_ERR_OK || noSpace > 0)
        {
            FinishWrite(actor, command, arguments, name, guid, "inventory_full",
                http::status::conflict, job);
            return;
        }

        Item* item = player->StoreNewItem(dest, request.itemId, true, 0);
        if (!item)
        {
            FinishWrite(actor, command, arguments, name, guid, "inventory_full",
                http::status::conflict, job);
            return;
        }

        player->SendNewItem(item, request.count, true, false);

        FinishWrite(actor, command, arguments, name, guid, "success", http::status::ok, job);
    }

    void ExecuteMail(Actor const& actor, std::string const& command, std::string const& arguments,
        std::string const& playerName, std::string const& body, std::shared_ptr<WriteJob> const& job)
    {
        GmApiBody::MailRequest request;
        std::string error;
        if (!GmApiBody::ParseMail(body, request, error))
        {
            FinishWrite(actor, command, arguments, playerName, 0, error,
                http::status::bad_request, job);
            return;
        }

        std::string recipient = request.recipient;
        if (!normalizePlayerName(recipient))
        {
            FinishWrite(actor, command, arguments, playerName, 0, "bad_request",
                http::status::bad_request, job);
            return;
        }

        CharacterCacheEntry const* cache = sCharacterCache->GetCharacterCacheByName(recipient);
        if (!cache)
        {
            FinishWrite(actor, command, arguments, playerName, 0, "target_not_found",
                http::status::not_found, job);
            return;
        }

        if (cache->MailCount >= 100)
        {
            FinishWrite(actor, command, arguments, cache->Name, cache->Guid.GetRawValue(),
                "mailbox_full", http::status::conflict, job);
            return;
        }

        if (!CheckTargetAccount(actor, cache->AccountId, cache->Name, command, arguments, job))
            return;

        struct Stack
        {
            uint32 itemId;
            uint32 count;
        };

        std::vector<Stack> stacks;
        for (GmApiBody::ItemRequest const& requested : request.items)
        {
            ItemTemplate const* itemTemplate = sObjectMgr->GetItemTemplate(requested.itemId);
            if (!itemTemplate || (itemTemplate->MaxCount > 0
                    && requested.count > static_cast<uint32>(itemTemplate->MaxCount)))
            {
                FinishWrite(actor, command, arguments, cache->Name, cache->Guid.GetRawValue(),
                    "invalid_item", http::status::bad_request, job);
                return;
            }

            uint32 maxStack = itemTemplate->GetMaxStackSize();
            if (maxStack == 0)
                maxStack = 1;

            uint32 remaining = requested.count;
            while (remaining > maxStack)
            {
                stacks.push_back({ requested.itemId, maxStack });
                remaining -= maxStack;
            }
            stacks.push_back({ requested.itemId, remaining });

            if (stacks.size() > MAX_MAIL_ITEMS)
            {
                FinishWrite(actor, command, arguments, cache->Name, cache->Guid.GetRawValue(),
                    "too_many_items", http::status::bad_request, job);
                return;
            }
        }

        Player* online = ObjectAccessor::FindPlayer(cache->Guid);
        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        MailDraft draft(request.subject, request.text);
        if (request.money > 0)
            draft.AddMoney(request.money);

        std::vector<Item*> created;
        for (Stack const& stack : stacks)
        {
            Item* item = Item::CreateItem(stack.itemId, stack.count);
            if (!item)
            {
                for (Item* existing : created)
                    delete existing;
                FinishWrite(actor, command, arguments, cache->Name, cache->Guid.GetRawValue(),
                    "mail_failed", http::status::internal_server_error, job);
                return;
            }

            item->SaveToDB(trans);
            created.push_back(item);
            draft.AddItem(item);
        }

        draft.SendMailTo(trans, MailReceiver(online, cache->Guid.GetCounter()),
            MailSender(MAIL_NORMAL, cache->Guid.GetCounter(), MAIL_STATIONERY_GM));
        CharacterDatabase.CommitTransaction(trans);

        FinishWrite(actor, command, arguments, cache->Name, cache->Guid.GetRawValue(),
            "success", http::status::ok, job);
    }

    void ExecuteBan(Actor const& actor, std::string const& command, std::string const& arguments,
        std::string const& playerName, std::string const& account, std::string const& body,
        std::shared_ptr<WriteJob> const& job)
    {
        GmApiBody::BanRequest request;
        std::string error;
        if (!GmApiBody::ParseBan(body, request, error))
        {
            FinishWrite(actor, command, arguments, playerName, 0, error,
                http::status::bad_request, job);
            return;
        }

        std::string accountName = account;
        Utf8ToUpperOnlyLatin(accountName);
        uint32 const accountId = AccountMgr::GetId(accountName);
        if (!accountId)
        {
            FinishWrite(actor, command, arguments, playerName, 0, "target_not_found",
                http::status::not_found, job);
            return;
        }

        if (accountId == actor.accountId)
        {
            FinishWrite(actor, command, arguments, accountName, 0, "cannot_target_self",
                http::status::conflict, job);
            return;
        }

        if (AccountMgr::GetSecurity(accountId, realm.Id.Realm) >= actor.security)
        {
            FinishWrite(actor, command, arguments, accountName, 0, "forbidden_target_security",
                http::status::forbidden, job, "forbidden");
            return;
        }

        std::string const duration = secsToTimeString(request.durationSeconds, true);
        BanReturn const result = sBan->BanAccount(accountName, duration, request.reason, actor.name);
        switch (result)
        {
            case BAN_SUCCESS:
                FinishWrite(actor, command, arguments, accountName, 0, "success",
                    http::status::ok, job);
                return;
            case BAN_NOTFOUND:
                FinishWrite(actor, command, arguments, accountName, 0, "target_not_found",
                    http::status::not_found, job);
                return;
            case BAN_LONGER_EXISTS:
                FinishWrite(actor, command, arguments, accountName, 0, "longer_ban_exists",
                    http::status::conflict, job);
                return;
            case BAN_SYNTAX_ERROR:
            default:
                FinishWrite(actor, command, arguments, accountName, 0, "bad_request",
                    http::status::bad_request, job);
                return;
        }
    }

    void ExecutePermission(Actor const& actor, std::string const& command,
        std::string const& arguments, std::string const& playerName, std::string const& account,
        std::string const& body, std::shared_ptr<WriteJob> const& job)
    {
        GmApiBody::PermissionRequest request;
        std::string error;
        if (!GmApiBody::ParsePermission(body, request, error))
        {
            FinishWrite(actor, command, arguments, playerName, 0, error,
                http::status::bad_request, job);
            return;
        }

        if (request.realmId != -1 && request.realmId != static_cast<int32>(realm.Id.Realm))
        {
            FinishWrite(actor, command, arguments, playerName, 0, "bad_request",
                http::status::bad_request, job);
            return;
        }

        std::string accountName = account;
        Utf8ToUpperOnlyLatin(accountName);
        uint32 const accountId = AccountMgr::GetId(accountName);
        if (!accountId)
        {
            FinishWrite(actor, command, arguments, playerName, 0, "target_not_found",
                http::status::not_found, job);
            return;
        }

        if (accountId == actor.accountId)
        {
            FinishWrite(actor, command, arguments, accountName, 0, "cannot_target_self",
                http::status::conflict, job);
            return;
        }

        uint32 const security = AccountMgr::GetSecurity(accountId, realm.Id.Realm);
        if (security >= actor.security)
        {
            FinishWrite(actor, command, arguments, accountName, 0, "forbidden_target_security",
                http::status::forbidden, job, "forbidden");
            return;
        }

        if (!sAccountMgr->GetRBACPermission(request.permissionId))
        {
            FinishWrite(actor, command, arguments, accountName, 0, "unknown_permission",
                http::status::not_found, job);
            return;
        }

        rbac::RBACData data(accountId, accountName, realm.Id.Realm, static_cast<uint8>(security));
        data.LoadFromDB();

        rbac::RBACCommandResult result;
        if (request.action == "grant")
            result = data.GrantPermission(request.permissionId, request.realmId);
        else if (request.action == "deny")
            result = data.DenyPermission(request.permissionId, request.realmId);
        else
            result = data.RevokePermission(request.permissionId, request.realmId);

        std::string resultName;
        switch (result)
        {
            case rbac::RBAC_OK:
                if (WorldSession* session = sWorldSessionMgr->FindSession(accountId))
                    if (session->GetRBACData())
                        session->InvalidateRBACData();

                FinishWrite(actor, command, arguments, accountName, 0, "success",
                    http::status::ok, job);
                return;
            case rbac::RBAC_CANT_ADD_ALREADY_ADDED:
                resultName = request.action == "grant" ? "already_granted" : "already_denied";
                break;
            case rbac::RBAC_IN_GRANTED_LIST:
                resultName = "in_granted_list";
                break;
            case rbac::RBAC_IN_DENIED_LIST:
                resultName = "in_denied_list";
                break;
            case rbac::RBAC_CANT_REVOKE_NOT_IN_LIST:
                resultName = "not_in_list";
                break;
            case rbac::RBAC_ID_DOES_NOT_EXISTS:
                FinishWrite(actor, command, arguments, accountName, 0, "unknown_permission",
                    http::status::not_found, job);
                return;
            default:
                resultName = "bad_request";
                break;
        }

        FinishWrite(actor, command, arguments, accountName, 0, resultName,
            http::status::conflict, job);
    }

    void ExecuteServerControl(Actor const& actor, std::string const& command,
        std::string const& arguments, std::string const& body, bool allowServerControl,
        std::shared_ptr<WriteJob> const& job)
    {
        GmApiBody::ServerControlRequest request;
        std::string error;
        if (!GmApiBody::ParseServerControl(body, request, error))
        {
            FinishWrite(actor, command, arguments, "", 0, error, http::status::bad_request, job);
            return;
        }

        if (!allowServerControl)
        {
            FinishWrite(actor, command, arguments, "", 0, "server_control_disabled",
                http::status::forbidden, job);
            return;
        }

        if (request.action == "shutdown")
            sWorld->ShutdownServ(request.delaySeconds, 0, SHUTDOWN_EXIT_CODE, request.reason);
        else if (request.action == "restart")
            sWorld->ShutdownServ(request.delaySeconds, SHUTDOWN_MASK_RESTART, RESTART_EXIT_CODE,
                request.reason);
        else
            sWorld->ShutdownCancel();

        FinishWrite(actor, command, arguments, "", 0, "success", http::status::ok, job);
    }

    void ReadAccount(std::string const& account, std::shared_ptr<WriteJob> const& job)
    {
        uint32 accountId = 0;
        if (GmApiAuth::ValidActor(account))
        {
            accountId = ParseAccountId(account);
        }
        else
        {
            std::string name = account;
            Utf8ToUpperOnlyLatin(name);
            accountId = AccountMgr::GetId(name);
        }

        std::string name;
        if (!accountId || !AccountMgr::GetName(accountId, name))
        {
            job->Finish(http::status::not_found, JsonError("target_not_found"));
            return;
        }

        uint32 const security = AccountMgr::GetSecurity(accountId, realm.Id.Realm);
        bool const online = sWorldSessionMgr->FindSession(accountId) != nullptr;

        job->Finish(http::status::ok, Acore::StringFormat(
            R"({{"id":{},"username":"{}","security":{},"online":{}}})",
            accountId, JsonEscape(name), security, online ? "true" : "false"));
    }

    void ReadCharacter(std::string const& character, std::shared_ptr<WriteJob> const& job)
    {
        std::string name = character;
        if (!normalizePlayerName(name))
        {
            job->Finish(http::status::not_found, JsonError("target_not_found"));
            return;
        }

        CharacterCacheEntry const* cache = sCharacterCache->GetCharacterCacheByName(name);
        if (!cache)
        {
            job->Finish(http::status::not_found, JsonError("target_not_found"));
            return;
        }

        std::string accountName;
        AccountMgr::GetName(cache->AccountId, accountName);
        bool const online = ObjectAccessor::FindPlayer(cache->Guid) != nullptr;

        job->Finish(http::status::ok, Acore::StringFormat(
            R"({{"guid":{},"name":"{}","account_id":{},"account_name":"{}","level":{},"race":{},)"
            R"("class":{},"online":{}}})",
            cache->Guid.GetRawValue(), JsonEscape(cache->Name), cache->AccountId,
            JsonEscape(accountName), uint32(cache->Level), uint32(cache->Race), uint32(cache->Class),
            online ? "true" : "false"));
    }

    void ReadOnlinePlayers(uint32 limit, std::shared_ptr<WriteJob> const& job)
    {
        struct Entry
        {
            uint64 guid;
            std::string name;
            uint32 accountId;
            uint32 level;
            uint32 race;
            uint32 playerClass;
            uint32 map;
            uint32 zone;
        };

        std::vector<Entry> entries;
        for (auto const& [accountId, session] : sWorldSessionMgr->GetAllSessions())
        {
            if (!session)
                continue;

            Player* player = session->GetPlayer();
            if (!player || !player->IsInWorld())
                continue;

            entries.push_back({ player->GetGUID().GetRawValue(), player->GetName(), accountId,
                uint32(player->GetLevel()), uint32(player->getRace()), uint32(player->getClass()),
                player->GetMapId(), player->GetZoneId() });
        }

        std::sort(entries.begin(), entries.end(),
            [](Entry const& left, Entry const& right) { return left.guid < right.guid; });
        if (entries.size() > limit)
            entries.resize(limit);

        std::string body = "[";
        bool first = true;
        for (Entry const& entry : entries)
        {
            if (!first)
                body += ",";
            first = false;

            body += Acore::StringFormat(
                R"({{"guid":{},"name":"{}","account_id":{},"level":{},"race":{},"class":{},)"
                R"("map":{},"zone":{}}})",
                entry.guid, JsonEscape(entry.name), entry.accountId, entry.level, entry.race,
                entry.playerClass, entry.map, entry.zone);
        }
        body += "]";
        job->Finish(http::status::ok, std::move(body));
    }

    void ReadInstances(uint32 limit, std::shared_ptr<WriteJob> const& job)
    {
        std::vector<Map*> maps;
        sMapMgr->DoForAllMaps([&maps](Map* map)
        {
            if (map && map->GetInstanceId() != 0)
                maps.push_back(map);
        });

        std::sort(maps.begin(), maps.end(), [](Map const* left, Map const* right)
        {
            return left->GetInstanceId() < right->GetInstanceId();
        });
        if (maps.size() > limit)
            maps.resize(limit);

        std::string body = "[";
        bool first = true;
        for (Map const* map : maps)
        {
            if (!first)
                body += ",";
            first = false;

            uint32 players = 0;
            for (auto const& ref : map->GetPlayers())
                if (ref.GetSource())
                    ++players;

            body += Acore::StringFormat(
                R"({{"instance_id":{},"map_id":{},"difficulty":{},"players":{}}})",
                map->GetInstanceId(), map->GetId(), uint32(map->GetDifficulty()), players);
        }
        body += "]";
        job->Finish(http::status::ok, std::move(body));
    }

}

class GmApiServer
{
public:
    GmApiServer(std::string bindAddress, uint16 port, std::string secret, int32 maxSkew,
        int32 nonceTtl, int32 rateLimit, bool allowWrites, bool allowServerControl,
        std::function<bool(std::shared_ptr<WriteJob>, std::function<void()>)> postToWorld)
        : _bindAddress(std::move(bindAddress)), _port(port), _secret(std::move(secret)),
          _maxSkew(maxSkew), _nonceTtl(nonceTtl), _rateLimit(rateLimit), _allowWrites(allowWrites),
          _allowServerControl(allowServerControl), _postToWorld(std::move(postToWorld)) { }

    ~GmApiServer() { Stop(); }

    void Start()
    {
        boost::system::error_code ec;
        _acceptor = std::make_unique<tcp::acceptor>(_io);
        tcp::endpoint endpoint(net::ip::make_address(_bindAddress, ec), _port);
        if (ec)
        {
            LOG_ERROR("module.gm-api", "Invalid GmApi.BindAddress '{}': {}", _bindAddress, ec.message());
            return;
        }

        _acceptor->open(endpoint.protocol(), ec);
        if (ec)
        {
            LOG_ERROR("module.gm-api", "Could not open GmApi listener: {}", ec.message());
            return;
        }

        _acceptor->set_option(net::socket_base::reuse_address(true), ec);
        _acceptor->bind(endpoint, ec);
        if (ec)
        {
            LOG_ERROR("module.gm-api", "Could not bind GmApi to {}:{}: {}", _bindAddress, _port, ec.message());
            _acceptor.reset();
            return;
        }

        _acceptor->listen(net::socket_base::max_listen_connections, ec);
        if (ec)
        {
            LOG_ERROR("module.gm-api", "Could not listen on GmApi port {}: {}", _port, ec.message());
            _acceptor.reset();
            return;
        }

        _running = true;
        DoAccept();
        _thread = std::thread([this]() { _io.run(); });
        LOG_INFO("module.gm-api", "GM API listening on {}:{}", _bindAddress, _port);
    }

    void Stop()
    {
        if (!_running.exchange(false))
            return;

        _io.stop();
        if (_acceptor)
        {
            boost::system::error_code ec;
            _acceptor->close(ec);
        }

        if (_thread.joinable())
            _thread.join();
        _acceptor.reset();
        LOG_INFO("module.gm-api", "GM API stopped");
    }

private:
    void DoAccept()
    {
        auto socket = std::make_shared<tcp::socket>(_io);
        _acceptor->async_accept(*socket, [this, socket](boost::system::error_code ec)
        {
            if (!ec)
            {
                if (_activeSessions >= MAX_SESSIONS)
                {
                    LOG_WARN("module.gm-api", "GM API session limit reached; rejecting connection.");
                    boost::system::error_code ignored;
                    socket->close(ignored);
                }
                else
                {
                    ++_activeSessions;
                    std::make_shared<Session>(std::move(*socket), *this)->Start();
                }
            }
            else if (ec != net::error::operation_aborted && _running)
            {
                LOG_ERROR("module.gm-api", "Accept failed: {}", ec.message());
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }

            if (_running)
                DoAccept();
        });
    }

    http::response<http::string_body> Process(http::request<http::string_body> const& request,
        std::string const& remoteIp, std::string& actorOut)
    {
        std::string actor;
        actorOut.clear();
        http::status const authStatus = Authorize(request, remoteIp, actor);
        if (authStatus != http::status::ok)
        {
            std::string error = "unauthorized";
            if (authStatus == http::status::conflict)
                error = "replayed_nonce";
            else if (authStatus == http::status::too_many_requests)
                error = "rate_limited";

            return MakeResponse(request, authStatus, JsonError(error));
        }
        actorOut = actor;

        std::string_view const target = request.target();
        std::string_view const path = GmApiAuth::TargetPath(target);
        bool const hasQuery = path.size() != target.size();
        bool const isGet = request.method() == http::verb::get;

        if (path == "/api/v1/status")
        {
            if (!isGet)
                return MethodNotAllowed(request, "GET");
            if (hasQuery)
                return MakeResponse(request, http::status::not_found, JsonError("not_found"));
            return MakeResponse(request, http::status::ok, R"({"status":"ok"})");
        }

        if (path == "/api/v1/audit")
        {
            if (!isGet)
                return MethodNotAllowed(request, "GET");

            GmApiAuth::AuditQuery query;
            std::string error;
            if (!GmApiAuth::ParseAuditQuery(target, query, error))
                return MakeResponse(request, http::status::bad_request, JsonError(error));

            return MakeResponse(request, http::status::ok, AuditJson(query));
        }

        if (path == "/api/v1/players/online")
        {
            if (!isGet)
                return MethodNotAllowed(request, "GET");
            return HandleOnlinePlayers(request);
        }

        if (path == "/api/v1/instances")
        {
            if (!isGet)
                return MethodNotAllowed(request, "GET");
            return HandleInstances(request);
        }

        std::string account;
        if (GmApiAuth::ParseAccountReadTarget(path, account))
        {
            if (!isGet)
                return MethodNotAllowed(request, "GET");
            if (hasQuery)
                return MakeResponse(request, http::status::not_found, JsonError("not_found"));
            return HandleAccountRead(request, account);
        }

        std::string character;
        if (GmApiAuth::ParseCharacterTarget(path, character))
        {
            if (!isGet)
                return MethodNotAllowed(request, "GET");
            if (hasQuery)
                return MakeResponse(request, http::status::not_found, JsonError("not_found"));
            return HandleCharacterRead(request, character);
        }

        if (path == "/api/v1/mail")
        {
            if (request.method() != http::verb::post)
                return MethodNotAllowed(request, "POST");
            if (hasQuery)
                return MakeResponse(request, http::status::not_found, JsonError("not_found"));
            return HandleMail(request, actor);
        }

        if (path == "/api/v1/server/control")
        {
            if (request.method() != http::verb::post)
                return MethodNotAllowed(request, "POST");
            if (hasQuery)
                return MakeResponse(request, http::status::not_found, JsonError("not_found"));
            return HandleServerControl(request, actor);
        }

        std::string playerName;
        if (GmApiAuth::ParsePlayerItemsTarget(path, playerName))
        {
            if (request.method() != http::verb::post)
                return MethodNotAllowed(request, "POST");
            if (hasQuery)
                return MakeResponse(request, http::status::not_found, JsonError("not_found"));
            return HandleAddItem(request, actor, playerName);
        }

        std::string action;
        if (GmApiAuth::ParsePlayerTarget(path, action, playerName))
        {
            if (request.method() != http::verb::post)
                return MethodNotAllowed(request, "POST");
            if (hasQuery)
                return MakeResponse(request, http::status::not_found, JsonError("not_found"));
            return HandlePlayerAction(request, actor, action, playerName);
        }

        if (GmApiAuth::ParseAccountActionTarget(path, action, account))
        {
            if (request.method() != http::verb::post)
                return MethodNotAllowed(request, "POST");
            if (hasQuery)
                return MakeResponse(request, http::status::not_found, JsonError("not_found"));
            return HandleAccountAction(request, actor, action, account);
        }

        return MakeResponse(request, http::status::not_found, R"({"error":"not_found"})");
    }

    static http::response<http::string_body> MethodNotAllowed(
        http::request<http::string_body> const& request, std::string_view allow)
    {
        return MakeResponse(request, http::status::method_not_allowed,
            R"({"error":"method_not_allowed"})", allow);
    }

    using WriteAction = std::function<void(Actor const&, std::string const&, std::string const&,
        std::shared_ptr<WriteJob> const&)>;

    http::response<http::string_body> RunWrite(http::request<http::string_body> const& request,
        std::string const& actorHeader, WriteSpec const& spec, WriteAction action)
    {
        if (!_allowWrites)
            return MakeResponse(request, http::status::forbidden, R"({"error":"writes_disabled"})");

        if (actorHeader.empty())
            return MakeResponse(request, http::status::unauthorized, R"({"error":"actor_required"})");

        Actor actor;
        if (!ResolveActor(ParseAccountId(actorHeader), actor))
            return MakeResponse(request, http::status::unauthorized, R"({"error":"unauthorized"})");

        if (actor.security <= SEC_PLAYER)
        {
            WriteAudit(actor, spec.command, spec.arguments, spec.playerName, 0, "denied");
            return MakeResponse(request, http::status::forbidden, R"({"error":"forbidden"})");
        }

        if (spec.permissions.empty())
            return MakeResponse(request, http::status::internal_server_error,
                R"({"error":"internal_error"})");

        for (uint32 permission : spec.permissions)
        {
            if (AccountMgr::HasPermission(actor.accountId, permission, realm.Id.Realm))
                continue;

            WriteAudit(actor, spec.command, spec.arguments, spec.playerName, 0, "denied");
            return MakeResponse(request, http::status::forbidden, R"({"error":"forbidden"})");
        }

        if (!WriteAudit(actor, spec.command, spec.arguments, spec.playerName, 0, "pending"))
            return MakeResponse(request, http::status::internal_server_error,
                R"({"error":"audit_failed"})");

        auto job = std::make_shared<WriteJob>();
        job->auditActor = actor;
        job->auditCommand = spec.command;
        job->auditArguments = spec.arguments;
        job->auditPlayerName = spec.playerName;
        if (!_postToWorld(job, [actor, spec, action, job]()
            {
                action(actor, spec.command, spec.arguments, job);
            }))
        {
            if (job->ClaimOutcome())
                WriteAudit(actor, spec.command, spec.arguments, spec.playerName, 0, "world_unavailable");
            return MakeResponse(request, http::status::service_unavailable,
                R"({"error":"world_unavailable"})");
        }

        if (!job->Wait(std::chrono::seconds(5)))
        {
            if (job->ClaimOutcome())
                WriteAudit(actor, spec.command, spec.arguments, spec.playerName, 0, "world_timeout");
            job->Cancel();
            return MakeResponse(request, http::status::service_unavailable,
                R"({"error":"world_unavailable"})");
        }

        return MakeResponse(request, job->status, job->body);
    }

    http::response<http::string_body> RunRead(http::request<http::string_body> const& request,
        std::function<void(std::shared_ptr<WriteJob> const&)> action)
    {
        auto job = std::make_shared<WriteJob>();
        if (!_postToWorld(job, [action, job]()
            {
                action(job);
            }))
        {
            return MakeResponse(request, http::status::service_unavailable,
                R"({"error":"world_unavailable"})");
        }

        if (!job->Wait(std::chrono::seconds(5)))
        {
            job->Cancel();
            return MakeResponse(request, http::status::service_unavailable,
                R"({"error":"world_unavailable"})");
        }

        return MakeResponse(request, job->status, job->body);
    }

    http::response<http::string_body> HandlePlayerAction(
        http::request<http::string_body> const& request, std::string const& actorHeader,
        std::string const& action, std::string const& playerName)
    {
        WriteSpec const spec{
            "api." + action,
            playerName,
            playerName,
            { action == "kick" ? rbac::RBAC_PERM_COMMAND_KICK : rbac::RBAC_PERM_COMMAND_UNSTUCK }
        };

        return RunWrite(request, actorHeader, spec,
            [action, playerName](Actor const& actor, std::string const& command,
                std::string const& /*arguments*/, std::shared_ptr<WriteJob> const& job)
            {
                ExecutePlayerAction(actor, command, action, playerName, job);
            });
    }

    http::response<http::string_body> HandleAddItem(
        http::request<http::string_body> const& request, std::string const& actorHeader,
        std::string const& playerName)
    {
        std::string const body = request.body();
        GmApiBody::ItemGrantRequest parsed;
        std::string error;
        if (!GmApiBody::ParseItemGrant(body, parsed, error))
            return MakeResponse(request, http::status::bad_request, JsonError(error));

        std::string arguments = Acore::StringFormat("player={} item={} count={}", playerName,
            parsed.itemId, parsed.count);

        WriteSpec const spec{
            "api.additem", arguments, playerName, { rbac::RBAC_PERM_COMMAND_ADDITEM }
        };

        return RunWrite(request, actorHeader, spec,
            [body, playerName](Actor const& actor, std::string const& command,
                std::string const& arguments, std::shared_ptr<WriteJob> const& job)
            {
                ExecuteAddItem(actor, command, arguments, playerName, body, job);
            });
    }

    http::response<http::string_body> HandleMail(
        http::request<http::string_body> const& request, std::string const& actorHeader)
    {
        std::string const body = request.body();
        GmApiBody::MailRequest parsed;
        std::string error;
        if (!GmApiBody::ParseMail(body, parsed, error))
            return MakeResponse(request, http::status::bad_request, JsonError(error));

        std::vector<uint32> permissions{ rbac::RBAC_PERM_COMMAND_SEND_MAIL };
        if (!parsed.items.empty())
            permissions.push_back(rbac::RBAC_PERM_COMMAND_SEND_ITEMS);
        if (parsed.money > 0)
            permissions.push_back(rbac::RBAC_PERM_COMMAND_SEND_MONEY);

        std::string const arguments = Acore::StringFormat("to={} items={} money={}",
            parsed.recipient, parsed.items.size(), parsed.money);

        WriteSpec const spec{ "api.mail", arguments, parsed.recipient, permissions };

        return RunWrite(request, actorHeader, spec,
            [body, playerName = spec.playerName](Actor const& actor, std::string const& command,
                std::string const& arguments, std::shared_ptr<WriteJob> const& job)
            {
                ExecuteMail(actor, command, arguments, playerName, body, job);
            });
    }

    http::response<http::string_body> HandleAccountAction(
        http::request<http::string_body> const& request, std::string const& actorHeader,
        std::string const& action, std::string const& account)
    {
        if (action == "ban")
            return HandleBan(request, actorHeader, account);
        return HandlePermissions(request, actorHeader, account);
    }

    http::response<http::string_body> HandleBan(
        http::request<http::string_body> const& request, std::string const& actorHeader,
        std::string const& account)
    {
        std::string const body = request.body();
        GmApiBody::BanRequest parsed;
        std::string error;
        if (!GmApiBody::ParseBan(body, parsed, error))
            return MakeResponse(request, http::status::bad_request, JsonError(error));

        std::string const arguments = Acore::StringFormat("account={} duration={}", account,
            parsed.durationSeconds);

        WriteSpec const spec{
            "api.ban", arguments, account, { rbac::RBAC_PERM_COMMAND_BAN_ACCOUNT }
        };

        return RunWrite(request, actorHeader, spec,
            [body, account](Actor const& actor, std::string const& command,
                std::string const& arguments, std::shared_ptr<WriteJob> const& job)
            {
                ExecuteBan(actor, command, arguments, account, account, body, job);
            });
    }

    http::response<http::string_body> HandlePermissions(
        http::request<http::string_body> const& request, std::string const& actorHeader,
        std::string const& account)
    {
        std::string const body = request.body();
        GmApiBody::PermissionRequest parsed;
        std::string error;
        if (!GmApiBody::ParsePermission(body, parsed, error))
            return MakeResponse(request, http::status::bad_request, JsonError(error));

        uint32 const permission = parsed.action == "grant"
            ? rbac::RBAC_PERM_COMMAND_RBAC_ACC_PERM_GRANT
            : parsed.action == "deny"
                ? rbac::RBAC_PERM_COMMAND_RBAC_ACC_PERM_DENY
                : rbac::RBAC_PERM_COMMAND_RBAC_ACC_PERM_REVOKE;

        std::string const arguments = Acore::StringFormat(
            "account={} action={} permission={} realm={}", account, parsed.action,
            parsed.permissionId, parsed.realmId);

        WriteSpec const spec{ "api.rbac", arguments, account, { permission } };

        return RunWrite(request, actorHeader, spec,
            [body, account](Actor const& actor, std::string const& command,
                std::string const& arguments, std::shared_ptr<WriteJob> const& job)
            {
                ExecutePermission(actor, command, arguments, account, account, body, job);
            });
    }

    http::response<http::string_body> HandleServerControl(
        http::request<http::string_body> const& request, std::string const& actorHeader)
    {
        std::string const body = request.body();
        GmApiBody::ServerControlRequest parsed;
        std::string error;
        if (!GmApiBody::ParseServerControl(body, parsed, error))
            return MakeResponse(request, http::status::bad_request, JsonError(error));

        uint32 const permission = parsed.action == "shutdown"
            ? rbac::RBAC_PERM_COMMAND_SERVER_SHUTDOWN
            : parsed.action == "restart"
                ? rbac::RBAC_PERM_COMMAND_SERVER_RESTART
                : rbac::RBAC_PERM_COMMAND_SERVER_SHUTDOWN_CANCEL;

        std::string const arguments = Acore::StringFormat("action={} delay={}", parsed.action,
            parsed.delaySeconds);

        WriteSpec const spec{ "api.server", arguments, "", { permission } };

        bool const allowServerControl = _allowServerControl;
        return RunWrite(request, actorHeader, spec,
            [body, allowServerControl](Actor const& actor, std::string const& command,
                std::string const& arguments, std::shared_ptr<WriteJob> const& job)
            {
                ExecuteServerControl(actor, command, arguments, body, allowServerControl, job);
            });
    }

    http::response<http::string_body> HandleAccountRead(
        http::request<http::string_body> const& request, std::string const& account)
    {
        return RunRead(request, [account](std::shared_ptr<WriteJob> const& job)
        {
            ReadAccount(account, job);
        });
    }

    http::response<http::string_body> HandleCharacterRead(
        http::request<http::string_body> const& request, std::string const& character)
    {
        return RunRead(request, [character](std::shared_ptr<WriteJob> const& job)
        {
            ReadCharacter(character, job);
        });
    }

    http::response<http::string_body> HandleOnlinePlayers(
        http::request<http::string_body> const& request)
    {
        uint32 const limit = GmApiAuth::ParseLimit(request.target(), 100, 500);
        return RunRead(request, [limit](std::shared_ptr<WriteJob> const& job)
        {
            ReadOnlinePlayers(limit, job);
        });
    }

    http::response<http::string_body> HandleInstances(
        http::request<http::string_body> const& request)
    {
        uint32 const limit = GmApiAuth::ParseLimit(request.target(), 100, 100);
        return RunRead(request, [limit](std::shared_ptr<WriteJob> const& job)
        {
            ReadInstances(limit, job);
        });
    }

    static http::response<http::string_body> MakeResponse(
        http::request<http::string_body> const& request, http::status status,
        std::string body, std::string_view allow = {})
    {
        http::response<http::string_body> response{ status, request.version() };
        response.set(http::field::content_type, "application/json");
        response.set(http::field::server, "mod-gm-api");
        if (!allow.empty())
            response.set(http::field::allow, allow);
        response.keep_alive(false);
        response.body() = std::move(body);
        response.prepare_payload();
        return response;
    }

    void SessionClosed() { --_activeSessions; }

    class Session : public std::enable_shared_from_this<Session>
    {
    public:
        Session(tcp::socket&& socket, GmApiServer& server)
            : _stream(std::move(socket)), _timer(_stream.get_executor()), _server(server) { }

        ~Session() { _server.SessionClosed(); }

        void Start()
        {
            _timer.expires_after(std::chrono::seconds(5));
            _timer.async_wait([self = shared_from_this()](boost::system::error_code ec)
            {
                if (!ec)
                {
                    boost::system::error_code ignored;
                    self->_stream.socket().shutdown(tcp::socket::shutdown_both, ignored);
                }
            });

            http::async_read(_stream, _buffer, _request,
                [self = shared_from_this()](boost::system::error_code ec, std::size_t)
                {
                    self->_timer.cancel();
                    if (!ec)
                    {
                        auto const started = std::chrono::steady_clock::now();
                        std::string actor;
                        http::response<http::string_body> response;
                        try
                        {
                            response = self->_server.Process(self->_request, self->RemoteIp(), actor);
                        }
                        catch (std::exception const& ex)
                        {
                            LOG_ERROR("module.gm-api", "GM API request failed: {}", ex.what());
                            response = GmApiServer::MakeResponse(self->_request,
                                http::status::internal_server_error, JsonError("internal_error"));
                        }
                        catch (...)
                        {
                            LOG_ERROR("module.gm-api", "GM API request failed with an unknown error");
                            response = GmApiServer::MakeResponse(self->_request,
                                http::status::internal_server_error, JsonError("internal_error"));
                        }

                        auto const elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                            std::chrono::steady_clock::now() - started).count();
                        LOG_INFO("module.gm-api", "{} {} status={} duration_ms={} actor={} ip={}",
                            self->_request.method_string(), self->_request.target(),
                            response.result_int(), elapsedMs, actor.empty() ? std::string("-") : actor,
                            self->RemoteIp());

                        boost::system::error_code ignored;
                        http::write(self->_stream, response, ignored);
                    }

                    boost::system::error_code ignored;
                    self->_stream.socket().shutdown(tcp::socket::shutdown_both, ignored);
                });
        }

    private:
        std::string RemoteIp() const
        {
            boost::system::error_code ec;
            auto const endpoint = _stream.socket().remote_endpoint(ec);
            return ec ? "unknown" : endpoint.address().to_string();
        }

        beast::tcp_stream _stream;
        beast::flat_buffer _buffer;
        http::request<http::string_body> _request;
        net::steady_timer _timer;
        GmApiServer& _server;
    };

    http::status Authorize(http::request<http::string_body> const& request, std::string const& remoteIp,
        std::string& actor)
    {
        if (!RateAllowed(remoteIp))
            return http::status::too_many_requests;

        auto const timestampHeader = request["X-GM-Timestamp"];
        auto const nonceHeader = request["X-GM-Nonce"];
        auto const signatureHeader = request["X-GM-Signature"];
        if (timestampHeader.empty() || nonceHeader.empty() || signatureHeader.empty())
            return http::status::unauthorized;

        auto const actorHeader = request["X-GM-Actor"];
        if (!actorHeader.empty())
        {
            actor = std::string(actorHeader);
            if (!GmApiAuth::ValidActor(actor))
                return http::status::unauthorized;
        }

        std::string const timestamp{ timestampHeader };
        if (timestamp.empty() || timestamp.front() == '-')
            return http::status::unauthorized;

        char* end = nullptr;
        errno = 0;
        unsigned long long const requestTime = std::strtoull(timestamp.c_str(), &end, 10);
        if (errno != 0 || !end || *end != '\0')
            return http::status::unauthorized;

        uint64 const now = static_cast<uint64>(std::chrono::duration_cast<std::chrono::seconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());
        if (!GmApiAuth::TimestampInWindow(now, requestTime, static_cast<uint64>(_maxSkew)))
            return http::status::unauthorized;

        std::string const nonce{ nonceHeader };
        if (!GmApiAuth::ValidNonce(nonce))
            return http::status::unauthorized;

        std::string const canonical = GmApiAuth::Canonical(
            timestamp, nonce, request.method_string(), request.target(), actor);
        std::string const expected = GmApiAuth::Signature(_secret, canonical);

        if (!ConstantTimeEqual(GmApiAuth::ToLower(std::string(signatureHeader)), expected))
            return http::status::unauthorized;

        {
            std::lock_guard<std::mutex> lock(_mutex);
            auto const nowSteady = std::chrono::steady_clock::now();
            for (auto it = _nonces.begin(); it != _nonces.end();)
            {
                if (nowSteady - it->second > std::chrono::seconds(_nonceTtl))
                    it = _nonces.erase(it);
                else
                    ++it;
            }

            if (!_nonces.emplace(nonce, nowSteady).second)
                return http::status::conflict;
        }

        return http::status::ok;
    }

    bool RateAllowed(std::string const& remoteIp)
    {
        std::lock_guard<std::mutex> lock(_mutex);
        auto const now = std::chrono::steady_clock::now();
        auto const minute = std::chrono::duration_cast<std::chrono::minutes>(
            now.time_since_epoch()).count();

        RateWindow& window = _rates[remoteIp];
        if (window.minute != minute)
        {
            window.minute = static_cast<uint32>(minute);
            window.count = 0;
        }

        return ++window.count <= static_cast<uint32>(_rateLimit);
    }

    std::string AuditJson(GmApiAuth::AuditQuery const& query)
    {
        std::vector<std::string> conditions;
        if (query.beforeId != 0)
            conditions.push_back("`id` < " + std::to_string(query.beforeId));
        if (!query.account.empty())
            conditions.push_back("`account_name` = '" + Escape(query.account) + "'");
        if (!query.command.empty())
            conditions.push_back("`command` = '" + Escape(query.command) + "'");
        if (!query.result.empty())
            conditions.push_back("`result` = '" + Escape(query.result) + "'");

        std::string sql =
            "SELECT `id`, `realm_id`, `account_name`, `player_name`, `command`, `arguments`, "
            "`result`, UNIX_TIMESTAMP(`created_at`) FROM `gm_audit_log`";
        if (!conditions.empty())
        {
            sql += " WHERE ";
            for (std::size_t i = 0; i < conditions.size(); ++i)
            {
                if (i != 0)
                    sql += " AND ";
                sql += conditions[i];
            }
        }
        sql += " ORDER BY `id` DESC LIMIT " + std::to_string(query.limit);

        QueryResult result = LoginDatabase.Query(sql);

        std::string body = "[";
        bool first = true;
        if (result)
        {
            do
            {
                Field* fields = result->Fetch();
                if (!first)
                    body += ",";
                first = false;

                body += R"({"id":)" + std::to_string(fields[0].Get<uint64>());
                body += R"(,"realm_id":)" + std::to_string(fields[1].Get<int32>());
                body += R"(,"account_name":")" + JsonEscape(fields[2].Get<std::string>()) + "\"";
                body += R"(,"player_name":")" + JsonEscape(fields[3].Get<std::string>()) + "\"";
                body += R"(,"command":")" + JsonEscape(fields[4].Get<std::string>()) + "\"";
                if (!fields[5].IsNull())
                    body += R"(,"arguments":")" + JsonEscape(fields[5].Get<std::string>()) + "\"";
                if (!fields[6].IsNull())
                    body += R"(,"result":")" + JsonEscape(fields[6].Get<std::string>()) + "\"";
                body += R"(,"created_at":)" + std::to_string(fields[7].Get<uint64>()) + "}";
            } while (result->NextRow());
        }
        body += "]";
        return body;
    }

    std::string _bindAddress;
    uint16 _port;
    std::string _secret;
    int32 _maxSkew;
    int32 _nonceTtl;
    int32 _rateLimit;
    bool _allowWrites;
    bool _allowServerControl;
    std::function<bool(std::shared_ptr<WriteJob>, std::function<void()>)> _postToWorld;

    std::atomic<uint32> _activeSessions{ 0 };

    net::io_context _io;
    std::unique_ptr<tcp::acceptor> _acceptor;
    std::thread _thread;
    std::atomic<bool> _running{ false };

    std::mutex _mutex;
    std::unordered_map<std::string, std::chrono::steady_clock::time_point> _nonces;
    std::unordered_map<std::string, RateWindow> _rates;
};

class GmApiWorldScript : public WorldScript
{
public:
    GmApiWorldScript() : WorldScript("mod_gm_api") { }

    void OnStartup() override
    {
        if (!sConfigMgr->GetOption<bool>("GmApi.Enable", false))
            return;

        std::string secret = Acore::String::Trim(
            sConfigMgr->GetOption<std::string>("GmApi.Secret", ""));
        if (secret.size() < 32)
        {
            LOG_ERROR("module.gm-api", "GmApi.Secret must be at least 32 characters; GM API not started.");
            return;
        }

        int32 const port = sConfigMgr->GetOption<int32>("GmApi.Port", 8090);
        if (port <= 0 || port > 65535)
        {
            LOG_ERROR("module.gm-api", "GmApi.Port {} is invalid.", port);
            return;
        }

        int32 const maxSkew = sConfigMgr->GetOption<int32>("GmApi.MaxClockSkew", 60);
        if (maxSkew < 1 || maxSkew > 300)
        {
            LOG_ERROR("module.gm-api", "GmApi.MaxClockSkew must be between 1 and 300.");
            return;
        }

        int32 const nonceTtl = sConfigMgr->GetOption<int32>("GmApi.NonceTtl", 120);
        if (nonceTtl < 2 * maxSkew || nonceTtl > 3600)
        {
            LOG_ERROR("module.gm-api", "GmApi.NonceTtl must be at least 2 * MaxClockSkew and at most 3600.");
            return;
        }

        int32 const rateLimit = sConfigMgr->GetOption<int32>("GmApi.RateLimit", 120);
        if (rateLimit < 1 || rateLimit > 10000)
        {
            LOG_ERROR("module.gm-api", "GmApi.RateLimit must be between 1 and 10000.");
            return;
        }

        bool const allowWrites = sConfigMgr->GetOption<bool>("GmApi.AllowWrites", false);
        if (allowWrites)
            LOG_INFO("module.gm-api",
                "GM API write endpoints enabled (kick, unstuck, additem, mail, ban, rbac, server).");

        bool const allowServerControl = sConfigMgr->GetOption<bool>("GmApi.AllowServerControl", false);
        if (allowServerControl)
            LOG_WARN("module.gm-api", "GM API server control is enabled (shutdown, restart, cancel).");

        _server = std::make_unique<GmApiServer>(
            sConfigMgr->GetOption<std::string>("GmApi.BindAddress", "127.0.0.1"),
            static_cast<uint16>(port), secret, maxSkew, nonceTtl, rateLimit, allowWrites,
            allowServerControl,
            [this](std::shared_ptr<WriteJob> job, std::function<void()> action)
            {
                return Post(std::move(job), std::move(action));
            });
        _server->Start();
    }

    void OnUpdate(uint32 /*diff*/) override
    {
        std::deque<QueuedJob> jobs;
        {
            std::lock_guard<std::mutex> lock(_queueMutex);
            jobs.swap(_jobs);
        }

        for (auto& job : jobs)
            if (!job.job->cancelled)
                job.action();
    }

    void OnShutdown() override
    {
        std::deque<QueuedJob> jobs;
        {
            std::lock_guard<std::mutex> lock(_queueMutex);
            _shuttingDown = true;
            jobs.swap(_jobs);
        }

        for (auto& queued : jobs)
        {
            auto const& job = queued.job;
            if (job->auditActor.accountId != 0 && job->ClaimOutcome())
                WriteAudit(job->auditActor, job->auditCommand, job->auditArguments,
                    job->auditPlayerName, 0, "world_unavailable");
            job->Finish(http::status::service_unavailable, R"({"error":"world_unavailable"})");
        }

        _server.reset();
    }

private:
    bool Post(std::shared_ptr<WriteJob> job, std::function<void()> action)
    {
        {
            std::lock_guard<std::mutex> lock(_queueMutex);
            if (!_shuttingDown)
            {
                _jobs.push_back({ std::move(job), std::move(action) });
                return true;
            }
        }

        job->Finish(http::status::service_unavailable, R"({"error":"world_unavailable"})");
        return false;
    }

    std::unique_ptr<GmApiServer> _server;
    std::mutex _queueMutex;
    std::deque<QueuedJob> _jobs;
    bool _shuttingDown = false;
};

void Addmod_gm_apiScripts()
{
    new GmApiWorldScript();
}
