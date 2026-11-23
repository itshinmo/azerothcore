/*
 * Treasure placer: GM-only in-game preview and coordinate capture for the
 * hand-placed world treasures (ADR-031). Preview chests are temporary summons
 * and never touch the database; `.treasure save` records the current player
 * position and `.treasure export` prints SQL-ready UPDATE lines.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Affero General Public License as published by the
 * Free Software Foundation; either version 3 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
 * for more details.
 */

#include "Chat.h"
#include "CommandScript.h"
#include "GameObject.h"
#include "Map.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "StringConvert.h"

#include <cmath>
#include <optional>
#include <cstdio>
#include <string>
#include <string_view>
#include <unordered_map>

using namespace Acore::ChatCommands;

namespace
{
    constexpr uint32 TREASURE_ITEM_FIRST = 901001;
    constexpr uint32 TREASURE_ITEM_LAST = 901100;
    constexpr uint32 TREASURE_GO_FIRST = 930001;
    constexpr uint32 TREASURE_GUID_FIRST = 5714501;
    constexpr uint32 TREASURE_PREVIEW_SECONDS = 600;
    constexpr uint32 TREASURE_PERMISSION = 950152;

    struct Placement
    {
        uint32 ItemId = 0;
        uint32 Entry = 0;
        uint32 SpawnId = 0;
        uint32 MapId = 0;
        float X = 0.0f;
        float Y = 0.0f;
        float Z = 0.0f;
        float O = 0.0f;
    };

    struct Preview
    {
        ObjectGuid Guid;
        uint32 MapId = 0;
        uint32 ItemId = 0;
    };

    std::unordered_map<uint32, Placement> Placements; // item id -> last saved position
    std::unordered_map<uint32, Preview> Previews;     // player guid counter -> preview chest

    bool IsTreasureItem(uint32 itemId)
    {
        return itemId >= TREASURE_ITEM_FIRST && itemId <= TREASURE_ITEM_LAST;
    }

    uint32 GoEntryForItem(uint32 itemId)
    {
        return TREASURE_GO_FIRST + (itemId - TREASURE_ITEM_FIRST);
    }

    uint32 SpawnIdForItem(uint32 itemId)
    {
        return TREASURE_GUID_FIRST + (itemId - TREASURE_ITEM_FIRST);
    }

    void RemovePreview(Player* player)
    {
        auto itr = Previews.find(player->GetGUID().GetCounter());
        if (itr == Previews.end())
            return;

        if (itr->second.MapId == player->GetMapId())
            if (GameObject* go = player->GetMap()->GetGameObject(itr->second.Guid))
                go->Delete();

        Previews.erase(itr);
    }

    void SendUsage(ChatHandler* handler)
    {
        handler->SendSysMessage("Usage: .treasure list | preview <item> | save <item> | export | clear");
    }

    class TreasurePlacerCommandScript : public CommandScript
    {
    public:
        TreasurePlacerCommandScript() : CommandScript("TreasurePlacerCommandScript") { }

        ChatCommandTable GetCommands() const override
        {
            static ChatCommandTable commandTable =
            {
                { "treasure", HandleTreasureCommand, TREASURE_PERMISSION, Console::No }
            };

            return commandTable;
        }

    private:
        static bool HandleTreasureCommand(ChatHandler* handler, Tail args)
        {
            Player* player = handler->GetPlayer();
            if (!player)
                return false;

            std::string_view action = args;
            std::string_view rest;
            std::size_t const space = args.find(' ');
            if (space != std::string_view::npos)
            {
                action = args.substr(0, space);
                rest = args.substr(space + 1);
            }

            if (action == "list")
            {
                handler->SendSysMessage("World treasures (item -> object, spawn GUID):");
                for (uint32 item = TREASURE_ITEM_FIRST; item <= TREASURE_ITEM_LAST; ++item)
                {
                    if (ItemTemplate const* proto = sObjectMgr->GetItemTemplate(item))
                        handler->PSendSysMessage("{} {} -> {} (spawn {})", item, proto->Name1,
                            GoEntryForItem(item), SpawnIdForItem(item));
                }
                return true;
            }

            if (action == "preview")
            {
                Optional<uint32> parsed = rest.empty() ? Optional<uint32>{} : Acore::StringTo<uint32>(rest);
                if (!parsed || !IsTreasureItem(*parsed))
                {
                    SendUsage(handler);
                    return true;
                }

                GameObjectTemplate const* info = sObjectMgr->GetGameObjectTemplate(GoEntryForItem(*parsed));
                if (!info)
                {
                    handler->PSendSysMessage("No gameobject template for item {}.", *parsed);
                    return true;
                }

                RemovePreview(player);

                float const o = player->GetOrientation();
                float const x = player->GetPositionX() + 1.5f * std::cos(o);
                float const y = player->GetPositionY() + 1.5f * std::sin(o);
                float const z = player->GetPositionZ();

                float const rotation2 = std::sin(o / 2.0f);
                float const rotation3 = std::cos(o / 2.0f);
                GameObject* go = player->SummonGameObject(GoEntryForItem(*parsed), x, y, z, o,
                    0.0f, 0.0f, rotation2, rotation3, TREASURE_PREVIEW_SECONDS);
                if (!go)
                {
                    handler->SendSysMessage("Could not spawn the preview chest.");
                    return true;
                }

                Previews[player->GetGUID().GetCounter()] = Preview{ go->GetGUID(), player->GetMapId(), *parsed };
                handler->PSendSysMessage("Preview {} ({}) at {:.2f} {:.2f} {:.2f} o={:.2f}; 10 min.",
                    *parsed, info->name, x, y, z, o);
                return true;
            }

            if (action == "save")
            {
                Optional<uint32> parsed = rest.empty() ? Optional<uint32>{} : Acore::StringTo<uint32>(rest);
                if (!parsed || !IsTreasureItem(*parsed))
                {
                    SendUsage(handler);
                    return true;
                }

                if (!sObjectMgr->GetGameObjectTemplate(GoEntryForItem(*parsed)))
                {
                    handler->PSendSysMessage("No gameobject template for item {}.", *parsed);
                    return true;
                }

                if (player->GetMap()->IsDungeon() || player->InBattleground() || player->InArena())
                {
                    handler->SendSysMessage("Save placements in the open world, not in an instance or battleground.");
                    return true;
                }

                uint32 const itemId = *parsed;
                Placement& placement = Placements[itemId];
                placement.ItemId = itemId;
                placement.Entry = GoEntryForItem(itemId);
                placement.SpawnId = SpawnIdForItem(itemId);
                placement.MapId = player->GetMapId();
                placement.X = player->GetPositionX();
                placement.Y = player->GetPositionY();
                placement.Z = player->GetPositionZ();
                placement.O = player->GetOrientation();

                auto previewItr = Previews.find(player->GetGUID().GetCounter());
                if (previewItr != Previews.end() && previewItr->second.MapId == placement.MapId
                    && previewItr->second.ItemId == itemId)
                {
                    if (GameObject* go = player->GetMap()->GetGameObject(previewItr->second.Guid))
                    {
                        placement.X = go->GetPositionX();
                        placement.Y = go->GetPositionY();
                        placement.Z = go->GetPositionZ();
                        placement.O = go->GetOrientation();
                    }
                }

                handler->PSendSysMessage(
                    "Saved {}: map {} {:.2f} {:.2f} {:.2f} o={:.4f} (spawn {})",
                    itemId, placement.MapId, placement.X, placement.Y, placement.Z,
                    placement.O, placement.SpawnId);
                return true;
            }

            if (action == "export")
            {
                if (Placements.empty())
                {
                    handler->SendSysMessage("No placements saved in this session.");
                    return true;
                }

                handler->SendSysMessage("-- Treasure placements, generated by .treasure export");
                for (auto const& [itemId, p] : Placements)
                {
                    float const rotation2 = std::sin(p.O / 2.0f);
                    float const rotation3 = std::cos(p.O / 2.0f);
                    handler->PSendSysMessage(
                        "UPDATE `gameobject` SET `map`={}, `position_x`={:.2f}, `position_y`={:.2f}, "
                        "`position_z`={:.2f}, `orientation`={:.4f}, `rotation0`=0, `rotation1`=0, "
                        "`rotation2`={:.6f}, `rotation3`={:.6f} WHERE `guid`={}; -- item {}",
                        p.MapId, p.X, p.Y, p.Z, p.O, rotation2, rotation3, p.SpawnId, itemId);
                }

                handler->SendSysMessage("-- End of placements");
                return true;
            }

            if (action == "clear")
            {
                RemovePreview(player);
                handler->SendSysMessage("Preview chest removed.");
                return true;
            }

            SendUsage(handler);
            return true;
        }
    };
}

void Addmod_treasure_placerScripts()
{
    new TreasurePlacerCommandScript();
}
