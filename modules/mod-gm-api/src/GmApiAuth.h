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
        std::string_view method, std::string_view target)
    {
        return std::string(timestamp) + "\n" + std::string(nonce) + "\n"
            + std::string(method) + "\n" + std::string(target);
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

    inline uint32 ParseLimit(std::string_view target)
    {
        uint32 limit = 50;
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
                    limit = parsed > 200 ? 200 : static_cast<uint32>(parsed);
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
