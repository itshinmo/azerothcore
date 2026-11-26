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

    // Is this kill a boss for the XP split?
    //
    // Three ways to qualify, because the core only flags one of them:
    //   * CREATURE_FLAG_EXTRA_DUNGEON_BOSS (`IsDungeonBoss()`), set from `instance_encounters`
    //     rows with creditType 0 (credit on kill);
    //   * CREATURE_TYPE_FLAG_BOSS_MOB (`isWorldBoss()`), the type flag;
    //   * the creature is the credit target of an `instance_encounters` row with creditType 1
    //     (credit on cast). Those rows never set the flag, so the final boss of Drak'Tharon
    //     Keep (The Prophet Tharon'ja), Culling of Stratholme (Mal'Ganis), Halls of Stone
    //     (Sjonnir) and Trial of the Champion (Paletress, Eadric, Black Knight) would otherwise
    //     pay the trash rate. The caller supplies that lookup as `creditTargetOfCastEncounter`.
    constexpr bool IsBossKill(bool isDungeonMap, bool isDungeonBossFlag, bool isWorldBossFlag,
        bool creditTargetOfCastEncounter)
    {
        if (!isDungeonMap)
            return false;

        return isDungeonBossFlag || isWorldBossFlag || creditTargetOfCastEncounter;
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
