/*
 * Credits: silviu20092
 */

#ifndef _MYTHIC_AFFIX_H_
#define _MYTHIC_AFFIX_H_

#include "Define.h"
#include <string>

class Creature;

enum MythicAffixType
{
    AFFIX_TYPE_HEALTH_INCREASE_TRASH,
    AFFIX_TYPE_HEALTH_INCREASE_BOSSES,
    AFFIX_TYPE_MULTIPLE_ENEMIES,
    AFFIX_TYPE_MORE_CREATURE_DAMAGE,
    MAX_AFFIX_TYPE
};

class MythicAffix
{
public:
    virtual ~MythicAffix() = default;

    [[nodiscard]] virtual MythicAffixType GetAffixType() const = 0;
    [[nodiscard]] virtual std::string ToString() const = 0;

    virtual void HandleStaticEffect(Creature* /*creature*/) {}

    static MythicAffix* AffixFactory(MythicAffixType type, float val1, float val2);

protected:
    [[nodiscard]] static bool IsCreatureProcessed(Creature* creature);
};

class HealthIncreaseAffix : public MythicAffix
{
private:
    float healthMod;
    [[nodiscard]] bool CanApplyHealthIncrease(Creature* creature) const;

public:
    explicit HealthIncreaseAffix(float healthMod) : healthMod(healthMod) {}

    [[nodiscard]] MythicAffixType GetAffixType() const override
    {
        return AFFIX_TYPE_HEALTH_INCREASE_TRASH;
    }

    [[nodiscard]] std::string ToString() const override;
    void HandleStaticEffect(Creature* creature) override;

    [[nodiscard]] virtual bool GetApplyForTrash() const
    {
        return true;
    }

    [[nodiscard]] virtual bool GetApplyForBosses() const
    {
        return false;
    }
};

class TrashHealthIncreaseAffix : public HealthIncreaseAffix
{
public:
    explicit TrashHealthIncreaseAffix(float healthMod) : HealthIncreaseAffix(healthMod) {}

    [[nodiscard]] MythicAffixType GetAffixType() const override
    {
        return AFFIX_TYPE_HEALTH_INCREASE_TRASH;
    }
};

class BossHealthIncreaseAffix : public HealthIncreaseAffix
{
public:
    explicit BossHealthIncreaseAffix(float healthMod) : HealthIncreaseAffix(healthMod) {}

    [[nodiscard]] MythicAffixType GetAffixType() const override
    {
        return AFFIX_TYPE_HEALTH_INCREASE_BOSSES;
    }

    [[nodiscard]] bool GetApplyForTrash() const override
    {
        return false;
    }

    [[nodiscard]] bool GetApplyForBosses() const override
    {
        return true;
    }
};

class MultipleEnemiesAffix : public MythicAffix
{
private:
    float chance;

public:
    explicit MultipleEnemiesAffix(float chance) : chance(chance) {}

    [[nodiscard]] MythicAffixType GetAffixType() const override
    {
        return AFFIX_TYPE_MULTIPLE_ENEMIES;
    }

    void HandleStaticEffect(Creature* creature) override;
    [[nodiscard]] std::string ToString() const override;
};

class MoreDamageForCreaturesAffix : public MythicAffix
{
private:
    float perc;

public:
    explicit MoreDamageForCreaturesAffix(float perc) : perc(perc) {}

    [[nodiscard]] MythicAffixType GetAffixType() const override
    {
        return AFFIX_TYPE_MORE_CREATURE_DAMAGE;
    }

    void HandleStaticEffect(Creature* creature) override;
    [[nodiscard]] std::string ToString() const override;
};

#endif
