/*
 * Credits: silviu20092
 */

#include "Creature.h"
#include "Map.h"
#include "ScriptMgr.h"
#include "mythic_plus.h"

class mythic_plus_all_creaturescript : public AllCreatureScript
{
public:
    mythic_plus_all_creaturescript() : AllCreatureScript("mythic_plus_all_creaturescript") {}

    void OnCreatureAddWorld(Creature* creature) override
    {
        if (!creature)
            return;

        Map* map = creature->GetMap();
        if (!map || !sMythicPlus->IsMapInMythicPlus(map))
            return;

        sMythicPlus->ApplyCreature(map, creature);
    }
};

void AddSC_mythic_plus_all_creaturescript()
{
    new mythic_plus_all_creaturescript();
}
