/*
 * PvP rulesets for AzerothCore (RFC-006, ADR-033). Slice 1: mode state, the pledge
 * command, the War Mode/High Risk PvP flag and the outdoor experience bonus.
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

#ifndef MOD_PVP_RULESETS_H
#define MOD_PVP_RULESETS_H

#include "Define.h"

#include <optional>
#include <string_view>

namespace PvpRulesets
{
    // One mode per character. The database stores the same tokens, so a mode survives a
    // worldserver restart without a numeric mapping to drift.
    enum class Mode : uint8
    {
        Pve      = 0,
        WarMode  = 1,
        HighRisk = 2,
    };

    std::optional<Mode> ParseMode(std::string_view token);
    char const* ModeToken(Mode mode);
    char const* ModeDisplayName(Mode mode);

    // War Mode and High Risk keep the player PvP-flagged. PvE never sets the flag, so the
    // native `/pvp` opt-in stays available.
    bool ModeUsesPvpFlag(Mode mode);

    uint32 XpBonusPercent(Mode mode, uint32 warModePercent, uint32 highRiskPercent);
    uint32 ApplyXpBonus(uint32 amount, uint32 percent);

    // Outdoor-only XP gate (RFC-006 section 5). Every field is a server-side location fact.
    struct OutdoorXpContext
    {
        bool inDungeon = false;
        bool inBattleground = false;
        bool inArena = false;
        bool inBattlefield = false;
        bool inNoPvpArea = false;
        bool inSanctuary = false;
    };

    bool IsOutdoorXpEligible(OutdoorXpContext const& context);

    // Pledge guards (RFC-006 section 3), evaluated in this fixed order.
    enum class ToggleResult : uint8
    {
        Ok = 0,
        Disabled,
        GameMaster,
        Dead,
        InCombat,
        InInstance,
        InBattleground,
        InArena,
        InBattlefield,
        NotInCapital,
        Cooldown,
    };

    struct ToggleContext
    {
        bool enabled = false;
        bool gameMaster = false;
        bool alive = false;
        bool inCombat = false;
        bool inInstance = false;
        bool inBattleground = false;
        bool inArena = false;
        bool inBattlefield = false;
        bool inCapital = false;
        int64 cooldownRemainingSeconds = 0;
    };

    ToggleResult EvaluateToggle(ToggleContext const& context);
    char const* ToggleRefusalMessage(ToggleResult result);

    // Seconds left on the persisted pledge cooldown. A clock that moved backwards reports a
    // full cooldown so a relog cannot bypass the wait.
    int64 CooldownRemainingSeconds(int64 now, int64 lastToggle, uint32 cooldownSeconds);
}

#endif
