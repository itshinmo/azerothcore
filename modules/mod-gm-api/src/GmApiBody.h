#ifndef MOD_GM_API_BODY_H
#define MOD_GM_API_BODY_H

#include "Define.h"

#include <boost/property_tree/json_parser.hpp>
#include <boost/property_tree/ptree.hpp>

#include <cstddef>
#include <exception>
#include <sstream>
#include <string>
#include <vector>

namespace GmApiBody
{
    namespace ptree = boost::property_tree;

    constexpr uint32 MAX_ITEM_COUNT = 1000;
    constexpr uint32 MAX_MAIL_ATTACHMENTS = 12;
    constexpr uint32 MAX_MAIL_MONEY = 2147483646u;
    constexpr uint32 MAX_BAN_SECONDS = 315360000;
    constexpr uint32 MAX_SERVER_DELAY = 3600;

    struct ItemRequest
    {
        uint32 itemId = 0;
        uint32 count = 0;
    };

    struct ItemGrantRequest
    {
        uint32 itemId = 0;
        uint32 count = 0;
    };

    struct MailRequest
    {
        std::string recipient;
        std::string subject;
        std::string text;
        uint32 money = 0;
        std::vector<ItemRequest> items;
    };

    struct BanRequest
    {
        uint32 durationSeconds = 0;
        std::string reason;
    };

    struct PermissionRequest
    {
        std::string action;
        uint32 permissionId = 0;
        int32 realmId = -1;
    };

    struct ServerControlRequest
    {
        std::string action;
        uint32 delaySeconds = 0;
        std::string reason;
    };

    inline std::size_t Utf8Length(std::string const& value)
    {
        std::size_t length = 0;
        for (unsigned char c : value)
            if ((c & 0xC0) != 0x80)
                ++length;
        return length;
    }

    inline bool ParseObject(std::string const& body, ptree::ptree& tree)
    {
        if (body.empty())
            return false;

        try
        {
            std::istringstream stream(body);
            ptree::read_json(stream, tree);
            return true;
        }
        catch (std::exception const&)
        {
            return false;
        }
    }

    inline bool ParseUInt32(std::string const& value, uint32& out)
    {
        if (value.empty() || value.size() > 10)
            return false;

        uint64 result = 0;
        for (char c : value)
        {
            if (c < '0' || c > '9')
                return false;

            result = result * 10 + static_cast<uint64>(c - '0');
            if (result > 0xFFFFFFFFull)
                return false;
        }

        out = static_cast<uint32>(result);
        return true;
    }

    inline bool ParseInt32(std::string const& value, int32& out)
    {
        bool const negative = !value.empty() && value.front() == '-';
        std::string const digits = negative ? value.substr(1) : value;

        uint32 magnitude = 0;
        if (!ParseUInt32(digits, magnitude))
            return false;

        if (negative)
        {
            if (magnitude > 2147483648u)
                return false;
            out = static_cast<int32>(-static_cast<int64>(magnitude));
        }
        else
        {
            if (magnitude > 2147483647u)
                return false;
            out = static_cast<int32>(magnitude);
        }

        return true;
    }

    inline bool ReadString(ptree::ptree const& tree, char const* key, std::string& out, bool required)
    {
        try
        {
            auto value = tree.get_optional<std::string>(key);
            if (!value)
                return !required;

            out = *value;
            return true;
        }
        catch (std::exception const&)
        {
            return false;
        }
    }

    inline bool ReadUInt32(ptree::ptree const& tree, char const* key, uint32& out, bool required)
    {
        try
        {
            auto value = tree.get_optional<std::string>(key);
            if (!value)
                return !required;

            return ParseUInt32(*value, out);
        }
        catch (std::exception const&)
        {
            return false;
        }
    }

    inline bool ReadInt32(ptree::ptree const& tree, char const* key, int32& out, bool required)
    {
        try
        {
            auto value = tree.get_optional<std::string>(key);
            if (!value)
                return !required;

            return ParseInt32(*value, out);
        }
        catch (std::exception const&)
        {
            return false;
        }
    }

    inline bool ParseItemGrant(std::string const& body, ItemGrantRequest& request, std::string& error)
    {
        error = "bad_request";
        request = ItemGrantRequest{};

        ptree::ptree tree;
        if (!ParseObject(body, tree))
            return false;

        if (!ReadUInt32(tree, "itemId", request.itemId, true))
            return false;
        if (!ReadUInt32(tree, "count", request.count, true))
            return false;
        if (request.itemId == 0)
        {
            error = "invalid_item";
            return false;
        }
        if (request.count == 0 || request.count > MAX_ITEM_COUNT)
            return false;

        error.clear();
        return true;
    }

    inline bool ParseMail(std::string const& body, MailRequest& request, std::string& error)
    {
        error = "bad_request";
        request = MailRequest{};

        ptree::ptree tree;
        if (!ParseObject(body, tree))
            return false;

        if (!ReadString(tree, "recipient", request.recipient, true))
            return false;
        if (request.recipient.empty() || Utf8Length(request.recipient) > 24)
            return false;

        if (!ReadString(tree, "subject", request.subject, false))
            return false;
        if (!ReadString(tree, "text", request.text, false))
            return false;
        if (Utf8Length(request.subject) > 64 || Utf8Length(request.text) > 5000)
            return false;

        if (!ReadUInt32(tree, "money", request.money, false))
            return false;
        if (request.money > MAX_MAIL_MONEY)
            return false;

        try
        {
            auto items = tree.get_child_optional("items");
            if (items)
            {
                if (!items->data().empty())
                    return false;

                for (auto const& entry : *items)
                {
                    if (!entry.second.data().empty())
                        return false;

                    ItemRequest item;
                    if (!ReadUInt32(entry.second, "itemId", item.itemId, true))
                        return false;
                    if (!ReadUInt32(entry.second, "count", item.count, true))
                        return false;
                    if (item.itemId == 0)
                    {
                        error = "invalid_item";
                        return false;
                    }
                    if (item.count == 0 || item.count > MAX_ITEM_COUNT)
                        return false;

                    request.items.push_back(item);
                }
            }
        }
        catch (std::exception const&)
        {
            return false;
        }

        if (request.items.size() > MAX_MAIL_ATTACHMENTS)
        {
            error = "too_many_items";
            return false;
        }

        error.clear();
        return true;
    }

    inline bool ParseBan(std::string const& body, BanRequest& request, std::string& error)
    {
        error = "bad_request";
        request = BanRequest{};

        ptree::ptree tree;
        if (!ParseObject(body, tree))
            return false;

        if (!ReadUInt32(tree, "durationSeconds", request.durationSeconds, true))
            return false;
        if (request.durationSeconds > MAX_BAN_SECONDS)
            return false;

        if (!ReadString(tree, "reason", request.reason, false))
            return false;
        if (Utf8Length(request.reason) > 255)
            return false;

        error.clear();
        return true;
    }

    inline bool ParsePermission(std::string const& body, PermissionRequest& request, std::string& error)
    {
        error = "bad_request";
        request = PermissionRequest{};

        ptree::ptree tree;
        if (!ParseObject(body, tree))
            return false;

        if (!ReadString(tree, "action", request.action, true))
            return false;
        if (request.action != "grant" && request.action != "deny" && request.action != "revoke")
            return false;

        if (!ReadUInt32(tree, "permissionId", request.permissionId, true))
            return false;
        if (request.permissionId == 0)
            return false;

        if (!ReadInt32(tree, "realmId", request.realmId, false))
            return false;
        if (request.realmId < -1 || request.realmId == 0)
            return false;

        error.clear();
        return true;
    }

    inline bool ParseServerControl(std::string const& body, ServerControlRequest& request,
        std::string& error)
    {
        error = "bad_request";
        request = ServerControlRequest{};

        ptree::ptree tree;
        if (!ParseObject(body, tree))
            return false;

        if (!ReadString(tree, "action", request.action, true))
            return false;
        if (request.action != "shutdown" && request.action != "restart"
            && request.action != "cancel")
            return false;

        bool const needsDelay = request.action != "cancel";
        if (!ReadUInt32(tree, "delaySeconds", request.delaySeconds, needsDelay))
            return false;
        if (needsDelay && (request.delaySeconds < 1 || request.delaySeconds > MAX_SERVER_DELAY))
            return false;
        if (!needsDelay && request.delaySeconds > MAX_SERVER_DELAY)
            return false;

        if (!ReadString(tree, "reason", request.reason, false))
            return false;
        if (Utf8Length(request.reason) > 255)
            return false;

        error.clear();
        return true;
    }
}

#endif
