/*
 * mod-objectives: public module API.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Affero General Public License as published by the
 * Free Software Foundation; either version 3 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public
 * License for more details.
 */

#ifndef MOD_OBJECTIVES_H
#define MOD_OBJECTIVES_H

#include "Define.h"

#include <string>

class Battleground;
class Creature;
class Player;
class Quest;

namespace Objectives
{
    // Configuration, definitions and all mutable state live in Objectives.cpp.
    void LoadConfig(bool reload);
    void Startup();
    void OnUpdate(uint32 diff);
    void OnShutdown();

    void OnLogin(Player* player);
    void OnLogout(Player* player);
    void OnCreatureKill(Player* player, Creature* killed);
    void OnQuestComplete(Player* player, Quest const* quest);
    void OnBattlegroundWin(Player* player, uint32 battlegroundTypeId);

    // Returns false when the message is an objective request and must not reach chat.
    bool OnAddonChat(Player* player, uint32 language, std::string& message, Player* receiver);

    bool OnVendorGossipHello(Player* player, Creature* creature);
    bool OnVendorGossipSelect(Player* player, Creature* creature, uint32 action);
}

#endif
