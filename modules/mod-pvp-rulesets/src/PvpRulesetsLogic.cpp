/*
 * Pure PvP ruleset logic (RFC-006, ADR-033). No world state, so the unit tests cover the
 * mode transitions, the pledge guards and the outdoor XP gate without a live realm.
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

#include "PvpRulesets.h"

namespace PvpRulesets
{
    std::optional<Mode> ParseMode(std::string_view token)
    {
        if (token == "pve")
            return Mode::Pve;
        if (token == "warmode")
            return Mode::WarMode;
        if (token == "highrisk")
            return Mode::HighRisk;
        return std::nullopt;
    }

    char const* ModeToken(Mode mode)
    {
        switch (mode)
        {
            case Mode::WarMode:
                return "warmode";
            case Mode::HighRisk:
                return "highrisk";
            case Mode::Pve:
            default:
                return "pve";
        }
    }

    char const* ModeDisplayName(Mode mode)
    {
        switch (mode)
        {
            case Mode::WarMode:
                return "War Mode";
            case Mode::HighRisk:
                return "High Risk";
            case Mode::Pve:
            default:
                return "PvE";
        }
    }

    bool ModeUsesPvpFlag(Mode mode)
    {
        return mode == Mode::WarMode || mode == Mode::HighRisk;
    }

    uint32 XpBonusPercent(Mode mode, uint32 warModePercent, uint32 highRiskPercent)
    {
        switch (mode)
        {
            case Mode::WarMode:
                return warModePercent;
            case Mode::HighRisk:
                return highRiskPercent;
            case Mode::Pve:
            default:
                return 0;
        }
    }

    uint32 ApplyXpBonus(uint32 amount, uint32 percent)
    {
        if (percent == 0)
            return amount;

        return uint32(uint64(amount) * (100ull + percent) / 100ull);
    }

    bool IsOutdoorXpEligible(OutdoorXpContext const& context)
    {
        return !context.inDungeon
            && !context.inBattleground
            && !context.inArena
            && !context.inBattlefield
            && !context.inNoPvpArea
            && !context.inSanctuary;
    }

    namespace
    {
        PledgeArea const* FindPledgeArea(uint32 areaId)
        {
            for (PledgeArea const& area : PLEDGE_AREAS)
                if (area.AreaId == areaId)
                    return &area;

            return nullptr;
        }
    }

    bool IsPledgeAreaAllowed(uint32 areaId, PledgeFaction playerFaction)
    {
        if (playerFaction != PledgeFaction::Alliance && playerFaction != PledgeFaction::Horde)
            return false;

        PledgeArea const* area = FindPledgeArea(areaId);
        return area && (area->Faction == PledgeFaction::Any || area->Faction == playerFaction);
    }

    ToggleResult EvaluateToggle(ToggleContext const& context)
    {
        if (!context.enabled)
            return ToggleResult::Disabled;
        if (context.gameMaster)
            return ToggleResult::GameMaster;
        if (!context.alive)
            return ToggleResult::Dead;
        if (context.inCombat)
            return ToggleResult::InCombat;
        if (context.inInstance)
            return ToggleResult::InInstance;
        if (context.inBattleground)
            return ToggleResult::InBattleground;
        if (context.inArena)
            return ToggleResult::InArena;
        if (context.inBattlefield)
            return ToggleResult::InBattlefield;

        // A sub-area has its own AreaTable row (Stormwind Harbor 4411, The Underbelly 4560,
        // Krasus' Landing 4564, ...), so only the listed city rows themselves pass.
        PledgeArea const* pledgeArea = FindPledgeArea(context.areaId);
        if (!pledgeArea)
            return ToggleResult::NotInPledgeArea;
        if (context.faction != PledgeFaction::Alliance && context.faction != PledgeFaction::Horde)
            return ToggleResult::WrongFaction;
        if (pledgeArea->Faction != PledgeFaction::Any && pledgeArea->Faction != context.faction)
            return ToggleResult::WrongFaction;

        if (context.cooldownRemainingSeconds > 0)
            return ToggleResult::Cooldown;
        return ToggleResult::Ok;
    }

    char const* ToggleRefusalMessage(ToggleResult result)
    {
        switch (result)
        {
            case ToggleResult::Disabled:
                return "PvP rulesets are disabled.";
            case ToggleResult::GameMaster:
                return "You cannot change your pledge in GM mode.";
            case ToggleResult::Dead:
                return "You cannot change your pledge while dead.";
            case ToggleResult::InCombat:
                return "You cannot change your pledge in combat.";
            case ToggleResult::InInstance:
                return "You cannot change your pledge in an instance.";
            case ToggleResult::InBattleground:
                return "You cannot change your pledge in a battleground.";
            case ToggleResult::InArena:
                return "You cannot change your pledge in an arena.";
            case ToggleResult::InBattlefield:
                return "You cannot change your pledge in a battlefield.";
            case ToggleResult::NotInPledgeArea:
                return "You can only change your pledge in a capital city (Stormwind, Ironforge, Darnassus, "
                       "The Exodar, Orgrimmar, Undercity, Thunder Bluff, Silvermoon, Shattrath or Dalaran).";
            case ToggleResult::WrongFaction:
                return "You can only change your pledge in a capital city of your own faction.";
            case ToggleResult::Cooldown:
                return "You must wait before changing your pledge again.";
            case ToggleResult::Ok:
            default:
                return "";
        }
    }

    int64 CooldownRemainingSeconds(int64 now, int64 lastToggle, uint32 cooldownSeconds)
    {
        if (lastToggle <= 0 || cooldownSeconds == 0)
            return 0;

        int64 const elapsed = now - lastToggle;
        if (elapsed < 0)
            return int64(cooldownSeconds);
        if (elapsed >= int64(cooldownSeconds))
            return 0;

        return int64(cooldownSeconds) - elapsed;
    }
}
