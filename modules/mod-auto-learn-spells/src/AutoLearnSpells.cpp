/*
 * This file is part of the AzerothCore Project. See AUTHORS file for Copyright information.
 *
 * Local module for the modernization fork (RFC-003 Group A / ADR-021): teaches class
 * trainer spells automatically when their level requirement is met, Cataclysm-style,
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

#include "ObjectMgr.h"
#include "Player.h"
#include "PlayerScript.h"
#include "Trainer.h"

namespace
{
// The learned set is exactly what the player could buy from their class trainers:
// the Trainer class applies the same availability filter the trainer UI uses
// (level, skill, ability and rank-chain requirements), driven by the server's
// trainer data, so there is no hand-maintained spell list to drift out of sync.
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
    }

    void OnPlayerLevelChanged(Player* player, uint8 oldLevel) override
    {
        // Only real level-ups; a level decrease re-checks nothing.
        if (player->GetLevel() > oldLevel)
            LearnClassTrainerSpells(player);
    }

private:
    static void LearnClassTrainerSpells(Player* player)
    {
        for (Trainer::Trainer const* trainer : sObjectMgr->GetClassTrainers(player->getClass()))
            for (Trainer::Spell const& spell : trainer->GetSpells())
            {
                // LEARN_SPELL wrapper entries (class mounts, druid flight forms) are cast by the
                // trainer, not learned directly; learnSpell would refuse them and leak a
                // PlayerSpell record, so they stay normal trainer visits.
                if (spell.IsCastable())
                    continue;

                if (trainer->CanTeachSpell(player, &spell))
                    player->learnSpell(spell.SpellId);
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
