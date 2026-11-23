/*
 * Credits: silviu20092
 */

#include "Creature.h"
#include "Map.h"
#include "Random.h"
#include "TemporarySummon.h"
#include "Unit.h"
#include "mythic_affix.h"
#include "mythic_plus.h"
#include <algorithm>
#include <iomanip>
#include <sstream>

/*static*/ bool MythicAffix::IsCreatureProcessed(Creature* creature)
{
    MythicPlus::CreatureData* creatureData = sMythicPlus->GetCreatureData(creature, false);
    if (creatureData == nullptr)
        return false;

    return creatureData->processed;
}

/*static*/ MythicAffix* MythicAffix::AffixFactory(MythicAffixType type, float val1, float val2)
{
    switch (type)
    {
        case AFFIX_TYPE_HEALTH_INCREASE_TRASH:
            return new TrashHealthIncreaseAffix(val1);
        case AFFIX_TYPE_HEALTH_INCREASE_BOSSES:
            return new BossHealthIncreaseAffix(val1);
        case AFFIX_TYPE_MULTIPLE_ENEMIES:
            return new MultipleEnemiesAffix(val1);
        case AFFIX_TYPE_MORE_CREATURE_DAMAGE:
            return new MoreDamageForCreaturesAffix(val1);
        default:
            return nullptr;
    }
}

bool HealthIncreaseAffix::CanApplyHealthIncrease(Creature* creature) const
{
    if (!IsCreatureProcessed(creature))
        return false;

    Map* map = creature->GetMap();
    bool boss = sMythicPlus->IsBoss(map->GetId(), creature->GetEntry());

    if (!GetApplyForTrash() && !boss)
        return false;

    if (!GetApplyForBosses() && boss)
        return false;

    return true;
}

void HealthIncreaseAffix::HandleStaticEffect(Creature* creature)
{
    if (!CanApplyHealthIncrease(creature))
        return;

    uint32 currentHealth = creature->GetMaxHealth();
    uint32 newMaxHealth = currentHealth + uint32(healthMod * currentHealth);
    if (newMaxHealth == 0)
        return;

    float healthPct = creature->GetHealthPct();
    creature->SetCreateHealth(newMaxHealth);
    creature->SetMaxHealth(newMaxHealth);
    creature->SetStatFlatModifier(UNIT_MOD_HEALTH, BASE_VALUE, float(newMaxHealth));
    creature->SetHealth(std::max<uint32>(1, uint32(newMaxHealth * (healthPct / 100.0f))));
    creature->ResetPlayerDamageReq();
}

std::string HealthIncreaseAffix::ToString() const
{
    std::ostringstream oss;
    oss << "Health increased by ";
    oss << std::fixed << std::setprecision(2) << healthMod * 100 << "% for ";
    if (GetApplyForTrash() && GetApplyForBosses())
        oss << "trash and bosses";
    else if (!GetApplyForTrash())
        oss << "bosses only";
    else
        oss << "trash only";

    return oss.str();
}

void MultipleEnemiesAffix::HandleStaticEffect(Creature* creature)
{
    if (!IsCreatureProcessed(creature))
        return;

    Map* map = creature->GetMap();
    MythicPlus::MapData* mapData = sMythicPlus->GetMapData(map, false);
    if (mapData == nullptr || mapData->done || mapData->spawningCopy)
        return;

    if (sMythicPlus->IsBoss(map->GetId(), creature->GetEntry()))
        return;

    if (creature->isDead())
        return;

    MythicPlus::CreatureData* creatureData = sMythicPlus->GetCreatureData(creature, false);
    if (creatureData == nullptr || creatureData->copy)
        return;

    if (!roll_chance_f(chance))
        return;

    float x = creature->GetPositionX() + irand(-10, 10);
    float y = creature->GetPositionY() + irand(-10, 10);
    float z = creature->GetPositionZ();

    mapData->spawningCopy = true;
    TempSummon* summon = creature->SummonCreature(creature->GetEntry(), x, y, z, 0.0f,
        TEMPSUMMON_CORPSE_DESPAWN);
    mapData->spawningCopy = false;

    if (summon == nullptr)
        return;

    MythicPlus::CreatureData* summonData = sMythicPlus->GetCreatureData(summon);
    summonData->copy = true;
}

std::string MultipleEnemiesAffix::ToString() const
{
    std::ostringstream oss;
    oss << "Trash enemies can spawn a copy of each other";
    oss << " (";
    oss << MythicPlus::Utils::FormatFloat(chance) << "% chance per creature)";
    return oss.str();
}

void MoreDamageForCreaturesAffix::HandleStaticEffect(Creature* creature)
{
    if (!IsCreatureProcessed(creature))
        return;

    MythicPlus::CreatureData* creatureData = sMythicPlus->GetCreatureData(creature, false);
    if (creatureData == nullptr)
        return;

    creatureData->extraDamageMultiplier *= (1.0f + perc / 100.0f);
}

std::string MoreDamageForCreaturesAffix::ToString() const
{
    std::ostringstream oss;
    oss << "All enemies deal ";
    oss << MythicPlus::Utils::FormatFloat(perc) << "% more damage";
    return oss.str();
}
