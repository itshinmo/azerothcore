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
#include "Config.h"
#include "DatabaseEnv.h"
#include "GmApiAuth.h"
#include "HMAC.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "RBAC.h"
#include "Realm.h"
#include "ScriptMgr.h"
#include "StringFormat.h"
#include "Util.h"
#include "World.h"
#include "WorldScript.h"
#include "WorldSession.h"

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

        std::mutex mutex;
        std::condition_variable cv;
        bool done = false;
        std::atomic<bool> cancelled{ false };
        http::status status = http::status::service_unavailable;
        std::string body = R"({"error":"world_unavailable"})";
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
        // shared synchronous connection without a lock. Backslash escaping assumes the default
        // sql_mode (NO_BACKSLASH_ESCAPES is not set).
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
                case '\'': out += "\\'"; break;
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
            "(`realm_id`, `account_id`, `account_name`, `player_name`, `player_guid`, `command`, `arguments`, `result`) "
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

    void ExecutePlayerAction(Actor const& actor, std::string const& action, std::string const& playerName,
        std::shared_ptr<WriteJob> const& job)
    {
        std::string const command = "api." + action;

        Player* player = ObjectAccessor::FindPlayerByName(playerName);
        if (!player || !player->GetSession())
        {
            WriteAudit(actor, command, playerName, "", 0, "target_not_found");
            job->Finish(http::status::not_found, R"({"error":"target_not_found"})");
            return;
        }

        WorldSession* session = player->GetSession();
        uint64 const guid = player->GetGUID().GetRawValue();
        std::string const name = player->GetName();

        if (session->GetAccountId() == actor.accountId)
        {
            WriteAudit(actor, command, playerName, name, guid, "cannot_target_self");
            job->Finish(http::status::conflict, R"({"error":"cannot_target_self"})");
            return;
        }

        if (AccountMgr::GetSecurity(session->GetAccountId(), realm.Id.Realm) >= actor.security)
        {
            WriteAudit(actor, command, playerName, name, guid, "forbidden_target_security");
            job->Finish(http::status::forbidden, R"({"error":"forbidden"})");
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
                WriteAudit(actor, command, playerName, name, guid, "player_busy");
                job->Finish(http::status::conflict, R"({"error":"player_busy"})");
                return;
            }

            if (!player->TeleportTo(player->m_homebindMapId, player->m_homebindX, player->m_homebindY,
                    player->m_homebindZ, player->GetOrientation()))
            {
                WriteAudit(actor, command, playerName, name, guid, "teleport_failed");
                job->Finish(http::status::internal_server_error, R"({"error":"teleport_failed"})");
                return;
            }
        }

        if (!WriteAudit(actor, command, playerName, name, guid, "success"))
        {
            job->Finish(http::status::internal_server_error, R"({"error":"audit_failed"})");
            return;
        }

        job->Finish(http::status::ok, R"({"status":"ok"})");
    }

}

class GmApiServer
{
public:
    GmApiServer(std::string bindAddress, uint16 port, std::string secret, int32 maxSkew,
        int32 nonceTtl, int32 rateLimit, bool allowWrites,
        std::function<bool(std::shared_ptr<WriteJob>, std::function<void()>)> postToWorld)
        : _bindAddress(std::move(bindAddress)), _port(port), _secret(std::move(secret)),
          _maxSkew(maxSkew), _nonceTtl(nonceTtl), _rateLimit(rateLimit), _allowWrites(allowWrites),
          _postToWorld(std::move(postToWorld)) { }

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
        std::string const& remoteIp)
    {
        std::string actor;
        http::status const authStatus = Authorize(request, remoteIp, actor);
        if (authStatus != http::status::ok)
        {
            std::string error = "unauthorized";
            if (authStatus == http::status::conflict)
                error = "replayed_nonce";
            else if (authStatus == http::status::too_many_requests)
                error = "rate_limited";

            return MakeResponse(request, authStatus, R"({"error":")" + error + R"("})");
        }

        std::string_view const target = request.target();
        bool const isGet = request.method() == http::verb::get;

        if (target == "/api/v1/status")
        {
            if (!isGet)
                return MethodNotAllowed(request, "GET");
            return MakeResponse(request, http::status::ok, R"({"status":"ok"})");
        }

        if (target == "/api/v1/audit" || target.starts_with("/api/v1/audit?"))
        {
            if (!isGet)
                return MethodNotAllowed(request, "GET");
            return MakeResponse(request, http::status::ok, AuditJson(GmApiAuth::ParseLimit(target)));
        }

        std::string action;
        std::string playerName;
        if (GmApiAuth::ParsePlayerTarget(target, action, playerName))
        {
            if (request.method() != http::verb::post)
                return MethodNotAllowed(request, "POST");
            return HandleWrite(request, actor, action, playerName);
        }

        return MakeResponse(request, http::status::not_found, R"({"error":"not_found"})");
    }

    static http::response<http::string_body> MethodNotAllowed(
        http::request<http::string_body> const& request, std::string_view allow)
    {
        return MakeResponse(request, http::status::method_not_allowed,
            R"({"error":"method_not_allowed"})", allow);
    }

    http::response<http::string_body> HandleWrite(http::request<http::string_body> const& request,
        std::string const& actorHeader, std::string const& action, std::string const& playerName)
    {
        if (!_allowWrites)
            return MakeResponse(request, http::status::forbidden, R"({"error":"writes_disabled"})");

        if (actorHeader.empty())
            return MakeResponse(request, http::status::unauthorized, R"({"error":"actor_required"})");

        Actor actor;
        if (!ResolveActor(ParseAccountId(actorHeader), actor))
            return MakeResponse(request, http::status::unauthorized, R"({"error":"unauthorized"})");

        std::string const command = "api." + action;

        if (actor.security <= SEC_PLAYER)
        {
            WriteAudit(actor, command, playerName, "", 0, "denied");
            return MakeResponse(request, http::status::forbidden, R"({"error":"forbidden"})");
        }

        uint32 const permission = action == "kick"
            ? rbac::RBAC_PERM_COMMAND_KICK
            : rbac::RBAC_PERM_COMMAND_UNSTUCK;
        if (!AccountMgr::HasPermission(actor.accountId, permission, realm.Id.Realm))
        {
            WriteAudit(actor, command, playerName, "", 0, "denied");
            return MakeResponse(request, http::status::forbidden, R"({"error":"forbidden"})");
        }

        if (!WriteAudit(actor, command, playerName, "", 0, "pending"))
            return MakeResponse(request, http::status::internal_server_error,
                R"({"error":"audit_failed"})");

        auto job = std::make_shared<WriteJob>();
        if (!_postToWorld(job, [actor, action, playerName, job]()
            {
                ExecutePlayerAction(actor, action, playerName, job);
            }))
        {
            WriteAudit(actor, command, playerName, "", 0, "world_unavailable");
            return MakeResponse(request, http::status::service_unavailable,
                R"({"error":"world_unavailable"})");
        }

        if (!job->Wait(std::chrono::seconds(5)))
        {
            job->Cancel();
            WriteAudit(actor, command, playerName, "", 0, "world_timeout");
            return MakeResponse(request, http::status::service_unavailable,
                R"({"error":"world_unavailable"})");
        }

        return MakeResponse(request, job->status, job->body);
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
            : _stream(std::move(socket)), _server(server), _timer(_stream.get_executor()) { }

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
                        http::response<http::string_body> response =
                            self->_server.Process(self->_request, self->RemoteIp());
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

    std::string AuditJson(uint32 limit)
    {
        QueryResult result = LoginDatabase.Query(
            "SELECT `id`, `realm_id`, `account_name`, `player_name`, `command`, `arguments`, "
            "`result`, UNIX_TIMESTAMP(`created_at`) FROM `gm_audit_log` ORDER BY `id` DESC LIMIT {}",
            limit);

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
            LOG_INFO("module.gm-api", "GM API write endpoints enabled (kick, unstuck).");

        _server = std::make_unique<GmApiServer>(
            sConfigMgr->GetOption<std::string>("GmApi.BindAddress", "127.0.0.1"),
            static_cast<uint16>(port), secret, maxSkew, nonceTtl, rateLimit, allowWrites,
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

        for (auto& job : jobs)
            job.job->Finish(http::status::service_unavailable, R"({"error":"world_unavailable"})");

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
