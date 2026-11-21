/*
 * This file is part of the AzerothCore Project. See AUTHORS file for Copyright information.
 *
 * Local module for the modernization fork (RFC-003 Group A / ADR-021, revised 2026-11-21): teaches
 * class trainer spells automatically when their level requirement is met, Cataclysm-style,
 * instead of requiring a trainer visit.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Affero General Public License as published by the
 * Free Software Foundation; either version 3 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for
 * more details.
 */

#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "PlayerScript.h"
#include "Trainer.h"

#include <algorithm>
#include <utility>
#include <vector>

namespace
{
// The learned set is exactly what the player could buy from their class trainers: driven by
// the server's trainer data through the core Trainer availability filter (Trainer::CanTeachSpell,
// the same logic the trainer UI uses), so there is no hand-maintained spell list to drift out
// of sync. Two lessons from the first rollout (ADR-021 revision):
//  - spells are processed from the lowest level requirement up, because rank spells are only
//    learnable once their previous rank is known — a GM-boosted or legacy character is missing
//    every lower rank of a chain, not just the newest one;
//  - LEARN_SPELL wrapper entries (class mounts, druid flight form) are taught by the trainer as
//    a cast, not by learnSpell (which refuses them and would leak a PlayerSpell record), so the
//    trainer's own teach action is mirrored — every class ends up complete.
class AutoLearnClassSpellsPlayerScript : public PlayerScript
{
public:
    AutoLearnClassSpellsPlayerScript() : PlayerScript("AutoLearnClassSpellsPlayerScript", {
        PLAYERHOOK_ON_LOGIN,
        PLAYERHOOK_ON_LEVEL_CHANGED
    }) { }

    // Every login gives a cheap catch-up pass (CanTeachSpell skips known spells): it closes the
    // gap for pre-existing characters, who have no level-up left to trigger the learn and never
    // fire the first-login hook (that flag is consumed at the character's first-ever login).
    void OnPlayerLogin(Player* player) override
    {
        LearnClassTrainerSpells(player);

        if (player->getClass() == CLASS_SHAMAN)
            EnsureShamanTotems(player);
    }

    void OnPlayerLevelChanged(Player* player, uint8 oldLevel) override
    {
        // Only real level-ups; a level decrease re-checks nothing. A GM level jump is a single
        // event with oldLevel far below the new level, and the level-ordered pass fills the
        // whole rank chain in one go.
        if (player->GetLevel() > oldLevel)
            LearnClassTrainerSpells(player);
    }

private:
    // Shamans' totem spells carry a TotemCategory requirement in Spell.dbc (earth=2, air=3,
    // fire=4, water=5), and the core's cast check looks for an item of that category anywhere
    // in the bags. The four vanilla totems (5175-5178) satisfy them; retail grants them via
    // the level 4/10/20/30 class quests, this fork grants any missing ones every login
    // (idempotent; a deleted totem comes back, exactly like the spell catch-up). Only shamans
    // have such requirements — checked across all class trainer data.
    static void EnsureShamanTotems(Player* player)
    {
        static constexpr uint32 ShamanTotemItems[] = { 5175, 5176, 5177, 5178 };
        for (uint32 item : ShamanTotemItems)
            if (!player->HasItemCount(item, 1, true))
                player->AddItem(item, 1);
    }

    static void LearnClassTrainerSpells(Player* player)
    {        std::vector<std::pair<Trainer::Trainer const*, Trainer::Spell const*>> spells;
        for (Trainer::Trainer const* trainer : sObjectMgr->GetClassTrainers(player->getClass()))
            for (Trainer::Spell const& spell : trainer->GetSpells())
                spells.emplace_back(trainer, &spell);

        std::sort(spells.begin(), spells.end(), [](auto const& a, auto const& b)
        {
            return a.second->ReqLevel < b.second->ReqLevel;
        });

        uint32 learned = 0;
        std::string blocked;
        // Iterate to a fixpoint: a spell can only be learned once its requirements are known,
        // and those requirements are learned inside the same pass — so one pass is not enough
        // regardless of order (ties and cascades). Each round learns more; stop when a round
        // adds nothing. Wrappers cast in round N unlock their chains for round N+1 too.
        for (int round = 0; round < 5; ++round)
        {
            uint32 learnedThisRound = 0;
            for (auto const& [trainer, spell] : spells)
            {
                if (player->HasSpell(spell->SpellId))
                    continue;

                if (!trainer->CanTeachSpell(player, spell))
                {
                    // TEMPORARY DIAGNOSTIC (ADR-021 investigation): log every non-learnable spell.
                    if (round == 4 && blocked.size() < 600)
                    {
                        blocked += " " + std::to_string(spell->SpellId) + "(lvl" + std::to_string(spell->ReqLevel)
                            + (spell->IsCastable() ? ",wrap)" : ")");
                    }
                    continue;
                }

                if (spell->IsCastable())
                    player->CastSpell(player, spell->SpellId, true);
                else
                    player->learnSpell(spell->SpellId);
                ++learned;
                ++learnedThisRound;
            }

            if (!learnedThisRound)
                break;
        }
    }
};
}

void AddAutoLearnSpellsScripts()
{
    new AutoLearnClassSpellsPlayerScript();
}

void Addmod_auto_learn_spellsScripts()
{
    AddAutoLearnSpellsScripts();
}
