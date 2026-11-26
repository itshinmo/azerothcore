/*
 * mod-dungeon-xp: pure kill-factor selection and knob clamps.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Affero General Public License as published by the
 * Free Software Foundation; either version 3 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public
 * License for more details.
 */

#ifndef MOD_DUNGEON_XP_MATH_H
#define MOD_DUNGEON_XP_MATH_H

#include <algorithm>

namespace DungeonXp::Math
{
    // Kill factors are multipliers: below 0 would be undefined behaviour in the hook's
    // float->uint32 conversion, above 1 would punish instead of reward.
    constexpr float ClampKillFactor(float factor)
    {
        return std::clamp(factor, 0.0f, 1.0f);
    }

    // Quest factor only multiplies up; a value below 1 would cut dungeon quest XP.
    constexpr float ClampQuestFactor(float factor)
    {
        return std::max(1.0f, factor);
    }

    // The kill multiplier for one victim. Outside an instance map the world rate stays 1.0;
    // raids share the split only when they are included.
    constexpr float SelectKillFactor(bool isDungeonMap, bool isRaidMap, bool includeRaids, bool isBoss,
        float trashFactor, float bossFactor)
    {
        if (!isDungeonMap)
            return 1.0f;

        if (isRaidMap && !includeRaids)
            return 1.0f;

        return isBoss ? bossFactor : trashFactor;
    }
}

#endif
