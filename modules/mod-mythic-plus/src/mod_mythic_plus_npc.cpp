/*
 * Credits: silviu20092
 */

#include "Creature.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "ScriptedGossip.h"
#include "StringConvert.h"
#include "Util.h"
#include "mythic_plus.h"
#include <sstream>

class mod_mythic_plus_npc : public CreatureScript
{
private:
    static void ShowMainMenu(Player* player, Creature* creature)
    {
        ClearGossipMenuFor(player);

        if (sMythicPlus->CanMapBeMythicPlus(player->GetMap()))
            AddGossipItemFor(player, GOSSIP_ICON_BATTLE, "Start a Mythic+ run", GOSSIP_SENDER_MAIN, 1);
        else
            AddGossipItemFor(player, GOSSIP_ICON_CHAT, "How to start a Mythic+ run", GOSSIP_SENDER_MAIN, 4);

        AddGossipItemFor(player, GOSSIP_ICON_CHAT, "Mythic+ status", GOSSIP_SENDER_MAIN, 2);
        AddGossipItemFor(player, GOSSIP_ICON_CHAT, "Nevermind", GOSSIP_SENDER_MAIN, 3);

        SendGossipMenuFor(player, DEFAULT_GOSSIP_MESSAGE, creature->GetGUID());
    }

    static void ShowKeyMenu(Player* player, Creature* creature)
    {
        ClearGossipMenuFor(player);

        uint8 nextKey = sMythicPlus->GetNextKey(MythicPlus::Utils::PlayerGUID(player),
            MythicPlus::MYTHIC_PLUS_ERA_CLASSIC);
        for (uint32 key = 1; key <= MythicPlus::MAX_KEY_LEVEL; ++key)
        {
            std::shared_ptr<MythicLevel const> level = sMythicPlus->GetMythicLevel(key);
            if (level == nullptr)
                continue;

            std::ostringstream oss;
            oss << "Key " << key << " (" << secsToTimeString(level->timeLimit) << ")";
            if (key > nextKey)
                oss << " [locked until key " << uint32(nextKey) << "]";

            AddGossipItemFor(player, GOSSIP_ICON_BATTLE, oss.str(), GOSSIP_SENDER_MAIN + 1, key);
        }

        AddGossipItemFor(player, GOSSIP_ICON_CHAT, "Back", GOSSIP_SENDER_MAIN + 1, 0);
        SendGossipMenuFor(player, DEFAULT_GOSSIP_MESSAGE, creature->GetGUID());
    }

    static void ShowStatus(Player* player)
    {
        uint32 guid = MythicPlus::Utils::PlayerGUID(player);
        uint8 highest = sMythicPlus->GetHighestKey(guid, MythicPlus::MYTHIC_PLUS_ERA_CLASSIC);
        uint8 next = sMythicPlus->GetNextKey(guid, MythicPlus::MYTHIC_PLUS_ERA_CLASSIC);
        std::ostringstream oss;
        oss << "Highest completed key: " << uint32(highest) << ". Next key: " << uint32(next) << ".";
        MythicPlus::BroadcastToPlayer(player, oss.str());
        MythicPlus::BroadcastToPlayer(player,
            "Ragefire Chasm, normal difficulty. The timer starts on the first damage. "
            "The final boss is Taragaman the Hungerer.");
    }

public:
    mod_mythic_plus_npc() : CreatureScript("mod_mythic_plus_npc") {}

    bool OnGossipHello(Player* player, Creature* creature) override
    {
        if (!sMythicPlus->IsEnabled())
        {
            MythicPlus::BroadcastToPlayer(player, "Mythic+ is disabled.");
            return true;
        }

        ShowMainMenu(player, creature);
        return true;
    }

    bool OnGossipSelect(Player* player, Creature* creature, uint32 sender, uint32 action) override
    {
        if (sender == GOSSIP_SENDER_MAIN)
        {
            switch (action)
            {
                case 1:
                    ShowKeyMenu(player, creature);
                    return true;
                case 2:
                    ShowStatus(player);
                    ShowMainMenu(player, creature);
                    return true;
                case 3:
                    CloseGossipMenuFor(player);
                    return true;
                case 4:
                    MythicPlus::BroadcastToPlayer(player,
                        "Travel to Ragefire Chasm. Start the run inside the instance at the "
                        "Mythic Plus NPC beside the entrance.");
                    ShowMainMenu(player, creature);
                    return true;
                default:
                    break;
            }
        }
        else if (sender == GOSSIP_SENDER_MAIN + 1)
        {
            if (action == 0)
            {
                ShowMainMenu(player, creature);
                return true;
            }

            sMythicPlus->StartRun(player, action);
            CloseGossipMenuFor(player);
            return true;
        }

        return true;
    }
};

void AddSC_mod_mythic_plus_npc()
{
    new mod_mythic_plus_npc();
}
