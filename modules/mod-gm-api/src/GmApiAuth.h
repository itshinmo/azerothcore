#ifndef MOD_GM_API_AUTH_H
#define MOD_GM_API_AUTH_H

#include "Define.h"

#include <cstddef>

#include "HMAC.h"
#include "Util.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <limits>
#include <string>
#include <string_view>
#include <vector>

namespace GmApiAuth
{
    inline std::string ToLower(std::string value)
    {
        for (char& c : value)
            c = char(std::tolower(static_cast<unsigned char>(c)));
        return value;
    }

    inline std::string Canonical(std::string_view timestamp, std::string_view nonce,
        std::string_view method, std::string_view target, std::string_view actor = {})
    {
        std::string canonical = std::string(timestamp) + "\n" + std::string(nonce) + "\n"
            + std::string(method) + "\n" + std::string(target);
        if (!actor.empty())
            canonical += "\n" + std::string(actor);
        return canonical;
    }

    inline std::string Signature(std::string_view secret, std::string_view canonical)
    {
        std::vector<uint8> const key(secret.begin(), secret.end());
        return ToLower(ByteArrayToHexStr(Acore::Crypto::HMAC_SHA256::GetDigestOf(
            key, reinterpret_cast<uint8 const*>(canonical.data()), canonical.size())));
    }

    inline bool TimestampInWindow(uint64 now, uint64 requestTime, uint64 skew)
    {
        return requestTime <= now + skew && now <= requestTime + skew;
    }

    inline bool ValidNonce(std::string_view nonce)
    {
        return nonce.size() >= 8 && nonce.size() <= 128;
    }

    /// Actor is a numeric game account id. It is signed as the last canonical line.
    inline bool ValidActor(std::string_view actor)
    {
        if (actor.empty() || actor.size() > 10)
            return false;

        uint64 value = 0;
        for (char c : actor)
        {
            if (!std::isdigit(static_cast<unsigned char>(c)))
                return false;
            value = value * 10 + static_cast<uint64>(c - '0');
        }

        return value > 0 && value <= 0xFFFFFFFFull;
    }

    /// Path without the query string; route matching uses the exact path.
    inline std::string_view TargetPath(std::string_view target)
    {
        std::size_t const queryPos = target.find('?');
        return queryPos == std::string_view::npos ? target : target.substr(0, queryPos);
    }

    inline bool ValidPlayerName(std::string_view name)
    {
        if (name.empty() || name.size() > 24)
            return false;

        for (char c : name)
            if (!std::isalnum(static_cast<unsigned char>(c)))
                return false;

        return true;
    }

    /// Account names are stored upper case; letters, digits, '_', '-' and '.' are allowed.
    inline bool ValidAccountName(std::string_view name)
    {
        if (name.empty() || name.size() > 17)
            return false;

        for (char c : name)
        {
            unsigned char const value = static_cast<unsigned char>(c);
            if (!std::isalnum(value) && c != '_' && c != '-' && c != '.')
                return false;
        }

        return true;
    }

    /// Matches /api/v1/players/<name>/<verb> and returns the verb and name.
    inline bool ParsePlayerVerb(std::string_view target, std::string_view verb, std::string& player)
    {
        constexpr std::string_view prefix = "/api/v1/players/";
        if (!target.starts_with(prefix))
            return false;

        std::string_view rest = target.substr(prefix.size());
        std::size_t const slash = rest.rfind('/');
        if (slash == std::string_view::npos || slash == 0)
            return false;

        std::string_view const name = rest.substr(0, slash);
        if (rest.substr(slash + 1) != verb || !ValidPlayerName(name))
            return false;

        player = std::string(name);
        return true;
    }

    /// Splits /api/v1/players/<name>/<kick|unstuck> into the action and target name.
    inline bool ParsePlayerTarget(std::string_view target, std::string& action, std::string& player)
    {
        if (ParsePlayerVerb(target, "kick", player))
        {
            action = "kick";
            return true;
        }

        if (ParsePlayerVerb(target, "unstuck", player))
        {
            action = "unstuck";
            return true;
        }

        return false;
    }

    /// Matches /api/v1/players/<name>/items.
    inline bool ParsePlayerItemsTarget(std::string_view target, std::string& player)
    {
        return ParsePlayerVerb(target, "items", player);
    }

    /// Matches /api/v1/accounts/<name>/<ban|permissions>.
    inline bool ParseAccountActionTarget(std::string_view target, std::string& action,
        std::string& account)
    {
        constexpr std::string_view prefix = "/api/v1/accounts/";
        if (!target.starts_with(prefix))
            return false;

        std::string_view rest = target.substr(prefix.size());
        std::size_t const slash = rest.rfind('/');
        if (slash == std::string_view::npos || slash == 0)
            return false;

        std::string_view const name = rest.substr(0, slash);
        std::string_view const verb = rest.substr(slash + 1);
        if (verb != "ban" && verb != "permissions")
            return false;
        if (!ValidAccountName(name))
            return false;

        action = std::string(verb);
        account = std::string(name);
        return true;
    }

    /// Matches /api/v1/accounts/<name-or-id> for the account read.
    inline bool ParseAccountReadTarget(std::string_view target, std::string& account)
    {
        constexpr std::string_view prefix = "/api/v1/accounts/";
        if (!target.starts_with(prefix))
            return false;

        std::string_view const name = target.substr(prefix.size());
        if (name.find('/') != std::string_view::npos || !ValidAccountName(name))
            return false;

        account = std::string(name);
        return true;
    }

    /// Matches /api/v1/characters/<name>.
    inline bool ParseCharacterTarget(std::string_view target, std::string& name)
    {
        constexpr std::string_view prefix = "/api/v1/characters/";
        if (!target.starts_with(prefix))
            return false;

        std::string_view const character = target.substr(prefix.size());
        if (character.find('/') != std::string_view::npos || !ValidPlayerName(character))
            return false;

        name = std::string(character);
        return true;
    }

    /// Parses ?limit=N; missing or invalid values use defaultLimit, larger values clamp to maxLimit.
    inline uint32 ParseLimit(std::string_view target, uint32 defaultLimit = 50, uint32 maxLimit = 200)
    {
        uint32 limit = defaultLimit;
        std::size_t const queryPos = target.find('?');
        if (queryPos == std::string_view::npos)
            return limit;

        std::string_view query = target.substr(queryPos + 1);
        while (!query.empty())
        {
            std::size_t const amp = query.find('&');
            std::string_view const pair = query.substr(0, amp);
            std::size_t const eq = pair.find('=');
            if (eq != std::string_view::npos && pair.substr(0, eq) == "limit")
            {
                std::string const value{ pair.substr(eq + 1) };
                char* end = nullptr;
                unsigned long const parsed = std::strtoul(value.c_str(), &end, 10);
                if (end && *end == '\0' && parsed > 0)
                    limit = parsed > maxLimit ? maxLimit : static_cast<uint32>(parsed);
                break;
            }

            if (amp == std::string_view::npos)
                break;
            query.remove_prefix(amp + 1);
        }

        return limit;
    }

    /// Exact-match filters and the newest-first cursor for the audit read. `beforeId` is the id of
    /// the last row already shown (0 = newest page); the next page asks for ids below it.
    struct AuditQuery
    {
        uint32 limit = 50;
        uint64 beforeId = 0;
        std::string account;
        std::string command;
        std::string result;
    };

    /// Filter values are column values, not free text; reject anything that cannot be one so a
    /// malformed query answers 400 instead of silently matching nothing.
    inline bool ValidAuditFilter(std::string const& value)
    {
        if (value.empty() || value.size() > 64)
            return false;

        return std::all_of(value.begin(), value.end(), [](unsigned char c)
        {
            return std::isalnum(c) != 0 || c == '_' || c == '-' || c == '.' || c == ':';
        });
    }

    inline bool ParseUInt64(std::string_view value, uint64& out)
    {
        if (value.empty() || value.size() > 20)
            return false;

        uint64 result = 0;
        for (char c : value)
        {
            if (c < '0' || c > '9')
                return false;

            uint64 const digit = static_cast<uint64>(c - '0');
            if (result > (std::numeric_limits<uint64>::max() - digit) / 10)
                return false;

            result = result * 10 + digit;
        }

        out = result;
        return true;
    }

    /// Parses the audit read query: ?limit=&before_id=&account=&command=&result=. Unknown keys are
    /// ignored; a malformed known key returns false with `error` = "invalid_parameter".
    inline bool ParseAuditQuery(std::string_view target, AuditQuery& out, std::string& error)
    {
        out = AuditQuery{};
        error.clear();

        std::size_t const queryPos = target.find('?');
        if (queryPos == std::string_view::npos)
            return true;

        std::string_view query = target.substr(queryPos + 1);
        while (!query.empty())
        {
            std::size_t const amp = query.find('&');
            std::string_view const pair = query.substr(0, amp);
            std::size_t const eq = pair.find('=');
            if (eq != std::string_view::npos)
            {
                std::string_view const key = pair.substr(0, eq);
                std::string const value{ pair.substr(eq + 1) };

                if (key == "limit")
                {
                    // Digits only: strtoul would accept "-1" and "+5" and clamp
                    // them to a valid limit, hiding a malformed query. A value
                    // that is not a number is a bad request; 0 means "default".
                    uint64 parsed = 0;
                    if (!ParseUInt64(value, parsed))
                    {
                        error = "invalid_parameter";
                        return false;
                    }

                    if (parsed > 0)
                        out.limit = parsed > 200 ? 200 : static_cast<uint32>(parsed);
                }
                else if (key == "before_id")
                {
                    if (!ParseUInt64(value, out.beforeId))
                    {
                        error = "invalid_parameter";
                        return false;
                    }
                }
                else if (key == "account" || key == "command" || key == "result")
                {
                    if (!ValidAuditFilter(value))
                    {
                        error = "invalid_parameter";
                        return false;
                    }

                    if (key == "account")
                        out.account = value;
                    else if (key == "command")
                        out.command = value;
                    else
                        out.result = value;
                }
            }

            if (amp == std::string_view::npos)
                break;
            query.remove_prefix(amp + 1);
        }

        return true;
    }
}

#endif
