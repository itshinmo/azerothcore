/*
 * Credits: silviu20092
 */

#include "Creature.h"
#include "Map.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SpellInfo.h"
#include "mythic_plus.h"

class mythic_plus_unitscript : public UnitScript
{
private:
    static void ApplyDamageMultiplier(Unit* attacker, uint32& damage)
    {
        Creature* creature = attacker ? attacker->ToCreature() : nullptr;
        if (creature == nullptr)
            return;

        Map* map = creature->GetMap();
        if (!map || !map->IsNonRaidDungeon() || !sMythicPlus->IsMapInMythicPlus(map))
            return;

        MythicPlus::CreatureData* creatureData = sMythicPlus->GetCreatureData(creature, false);
        if (creatureData == nullptr || !creatureData->processed)
            return;

        damage = uint32(float(damage) * creatureData->extraDamageMultiplier);
    }

public:
    mythic_plus_unitscript() : UnitScript("mythic_plus_unitscript", true,
        {
            UNITHOOK_ON_DAMAGE,
            UNITHOOK_ON_UNIT_DEATH,
            UNITHOOK_MODIFY_MELEE_DAMAGE,
            UNITHOOK_MODIFY_SPELL_DAMAGE_TAKEN,
            UNITHOOK_MODIFY_PERIODIC_DAMAGE_AURAS_TICK
        })
    {
    }

    void OnDamage(Unit* attacker, Unit* victim, uint32& /*damage*/) override
    {
        if (!attacker || !victim || attacker->GetMap() != victim->GetMap())
            return;

        Map* map = victim->GetMap();
        if (!map || !map->IsNonRaidDungeon())
            return;

        MythicPlus::MapData* mapData = sMythicPlus->GetMapData(map, false);
        if (mapData == nullptr || mapData->mythicLevel == nullptr || mapData->started || mapData->done)
            return;

        Creature* creature = victim->ToCreature();
        if (creature == nullptr || !sMythicPlus->CanProcessCreature(creature))
            return;

        if (!attacker->ToPlayer() && !attacker->IsControlledByPlayer())
            return;

        sMythicPlus->StartTimer(map);
    }

    void OnUnitDeath(Unit* unit, Unit* killer) override
    {
        if (!unit || !killer || unit->GetMap() != killer->GetMap())
            return;

        Creature* creature = unit->ToCreature();
        if (creature == nullptr)
            return;

        Map* map = creature->GetMap();
        MythicPlus::MapData* mapData = sMythicPlus->GetMapData(map, false);

        if (mapData != nullptr && mapData->mythicLevel != nullptr)
        {
            if (!mapData->done)
            {
                if (sMythicPlus->IsFinalBoss(map->GetId(), creature->GetEntry()))
                    sMythicPlus->CompleteRun(map, creature);
                else if (sMythicPlus->IsBoss(map->GetId(), creature->GetEntry()))
                    MythicPlus::BroadcastToMap(map, MythicPlus::Utils::GreenColored(
                        std::string(creature->GetName()) + " downed."));
            }

            return;
        }

        if (!sMythicPlus->CanMapBeMythicPlus(map))
            return;

        mapData = sMythicPlus->GetMapData(map);
        if (mapData->mythicLevel != nullptr || mapData->preCleared)
            return;

        if (!killer->ToPlayer() && !killer->IsControlledByPlayer())
            return;

        if (!sMythicPlus->CanProcessCreature(creature))
            return;

        sMythicPlus->BlockPreClearedInstance(map);
        MythicPlus::BroadcastToMap(map,
            "This instance is now marked as cleared without Mythic+. Reset it to start a run.");
    }

    void ModifyMeleeDamage(Unit* /*target*/, Unit* attacker, uint32& damage) override
    {
        ApplyDamageMultiplier(attacker, damage);
    }

    void ModifySpellDamageTaken(Unit* /*target*/, Unit* attacker, int32& damage,
        SpellInfo const* spellInfo) override
    {
        if (damage <= 0 || (spellInfo && spellInfo->IsPositive()))
            return;

        uint32 adjustedDamage = uint32(damage);
        ApplyDamageMultiplier(attacker, adjustedDamage);
        damage = int32(adjustedDamage);
    }

    void ModifyPeriodicDamageAurasTick(Unit* /*target*/, Unit* attacker, uint32& damage,
        SpellInfo const* spellInfo) override
    {
        if (spellInfo && spellInfo->IsPositive())
            return;

        ApplyDamageMultiplier(attacker, damage);
    }
};

void AddSC_mythic_plus_unitscript()
{
    new mythic_plus_unitscript();
}
