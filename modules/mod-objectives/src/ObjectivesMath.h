/*
 * mod-objectives: pure progress, reset, reroll and board-validation math.
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

#ifndef MOD_OBJECTIVES_MATH_H
#define MOD_OBJECTIVES_MATH_H

#include "Define.h"

#include <algorithm>
#include <cstdint>

namespace Objectives::Math
{
    // A board load is validated per scope, so a stale daily row cannot force the weekly board to be
    // re-rolled at a daily reset.
    struct BoardValidation
    {
        bool dailyValid = false;
        bool weeklyValid = false;
        bool dailyInvalid = false;
        bool weeklyInvalid = false;
        bool dailySizeOk = true;
        bool weeklySizeOk = true;
    };

    constexpr bool RebuildDaily(BoardValidation const& validation)
    {
        return !validation.dailyValid || validation.dailyInvalid || !validation.dailySizeOk;
    }

    constexpr bool RebuildWeekly(BoardValidation const& validation)
    {
        return !validation.weeklyValid || validation.weeklyInvalid || !validation.weeklySizeOk;
    }

    // Progress is clamped to the requirement and never wraps.
    constexpr uint32 ApplyProgress(uint32 current, uint32 delta, uint32 required)
    {
        if (required == 0)
            return 0;
        if (current >= required)
            return required;

        uint64 const sum = uint64(current) + uint64(delta);
        return sum >= required ? required : uint32(sum);
    }

    constexpr bool IsComplete(uint32 progress, uint32 required)
    {
        return required != 0 && progress >= required;
    }

    // A stored period is stale as soon as its reset time is reached. A zero key is always stale.
    constexpr bool ResetDue(uint32 resetAt, uint32 now)
    {
        return resetAt == 0 || resetAt <= now;
    }

    // The first reroll costs the base price, each later one costs one more base price.
    constexpr uint64 RerollCost(uint32 base, uint32 rerolls)
    {
        return std::min<uint64>(uint64(base) * (uint64(rerolls) + 1), UINT32_MAX);
    }

    constexpr uint32 ClampSlots(uint32 configured, uint32 maximum)
    {
        return std::min(configured, maximum);
    }
}

#endif
