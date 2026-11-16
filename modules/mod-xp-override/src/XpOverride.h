#ifndef MOD_XP_OVERRIDE_H
#define MOD_XP_OVERRIDE_H

#include "AreaDefines.h"
#include "Define.h"
#include "Player.h"

#include <algorithm>
#include <cmath>

namespace XpOverride
{
    enum class XpRate
    {
        None,
        Kill,
        BgKillAV,
        BgKillWSG,
        BgKillAB,
        BgKillEOTS,
        BgKillSOTA,
        BgKillIC,
        Quest,
        QuestDf,
        Explore,
        BattlegroundBonus
    };

    /// Selects the realm rate that produced an XP amount. Kill XP inside a battleground uses the
    /// per-map battleground rate. An unrecognised battleground map returns None so the caller can
    /// skip the override instead of dividing by the wrong rate.
    inline XpRate SelectRate(uint8 xpSource, bool inBattleground, uint32 mapId)
    {
        if (xpSource == XPSOURCE_KILL)
        {
            if (!inBattleground)
                return XpRate::Kill;

            switch (mapId)
            {
                case MAP_ALTERAC_VALLEY: return XpRate::BgKillAV;
                case MAP_WARSONG_GULCH: return XpRate::BgKillWSG;
                case MAP_ARATHI_BASIN: return XpRate::BgKillAB;
                case MAP_EYE_OF_THE_STORM: return XpRate::BgKillEOTS;
                case MAP_STRAND_OF_THE_ANCIENTS: return XpRate::BgKillSOTA;
                case MAP_ISLE_OF_CONQUEST: return XpRate::BgKillIC;
                default: return XpRate::None;
            }
        }

        switch (xpSource)
        {
            case XPSOURCE_QUEST:        return XpRate::Quest;
            case XPSOURCE_QUEST_DF:     return XpRate::QuestDf;
            case XPSOURCE_EXPLORE:      return XpRate::Explore;
            case XPSOURCE_BATTLEGROUND: return XpRate::BattlegroundBonus;
            default:                    return XpRate::None;
        }
    }

    /// Converts an amount that already includes the realm XP rate back to its 1x value.
    /// A non-positive rate means the source is disabled; the amount is returned unchanged.
    inline uint32 ComputeOverriddenXp(uint32 amount, float rate)
    {
        if (amount == 0 || rate <= 0.0f)
            return amount;

        uint32 const base = static_cast<uint32>(std::lround(static_cast<double>(amount) / rate));
        return std::max<uint32>(1, base);
    }
}

#endif
