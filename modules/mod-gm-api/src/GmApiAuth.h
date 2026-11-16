#ifndef MOD_GM_API_AUTH_H
#define MOD_GM_API_AUTH_H

#include "Define.h"

#include <cstddef>

#include "HMAC.h"
#include "Util.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
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
}

#endif
