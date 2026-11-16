#include "XpOverride.h"

#include <gtest/gtest.h>

using XpOverride::SelectRate;
using XpOverride::XpRate;

TEST(XpOverrideTest, DividesRealmRate)
{
    EXPECT_EQ(XpOverride::ComputeOverriddenXp(300, 3.0f), 100u);
    EXPECT_EQ(XpOverride::ComputeOverriddenXp(30, 3.0f), 10u);
}

TEST(XpOverrideTest, RoundsToNearest)
{
    EXPECT_EQ(XpOverride::ComputeOverriddenXp(100, 3.0f), 33u);
    EXPECT_EQ(XpOverride::ComputeOverriddenXp(101, 3.0f), 34u);
}

TEST(XpOverrideTest, NeverReturnsZeroForPositiveAmount)
{
    EXPECT_EQ(XpOverride::ComputeOverriddenXp(1, 3.0f), 1u);
}

TEST(XpOverrideTest, LeavesAmountWhenSourceDisabled)
{
    EXPECT_EQ(XpOverride::ComputeOverriddenXp(120, 0.0f), 120u);
    EXPECT_EQ(XpOverride::ComputeOverriddenXp(120, -1.0f), 120u);
    EXPECT_EQ(XpOverride::ComputeOverriddenXp(0, 3.0f), 0u);
}

TEST(XpOverrideTest, UpscalesWhenRealmRateIsBelowOne)
{
    EXPECT_EQ(XpOverride::ComputeOverriddenXp(50, 0.5f), 100u);
}

TEST(XpOverrideTest, KillOutsideBattlegroundUsesKillRate)
{
    EXPECT_EQ(SelectRate(XPSOURCE_KILL, false, 1), XpRate::Kill);
    EXPECT_EQ(SelectRate(XPSOURCE_KILL, false, MAP_ALTERAC_VALLEY), XpRate::Kill);
}

TEST(XpOverrideTest, KillInsideBattlegroundUsesMapRate)
{
    EXPECT_EQ(SelectRate(XPSOURCE_KILL, true, MAP_ALTERAC_VALLEY), XpRate::BgKillAV);
    EXPECT_EQ(SelectRate(XPSOURCE_KILL, true, MAP_WARSONG_GULCH), XpRate::BgKillWSG);
    EXPECT_EQ(SelectRate(XPSOURCE_KILL, true, MAP_ARATHI_BASIN), XpRate::BgKillAB);
    EXPECT_EQ(SelectRate(XPSOURCE_KILL, true, MAP_EYE_OF_THE_STORM), XpRate::BgKillEOTS);
    EXPECT_EQ(SelectRate(XPSOURCE_KILL, true, MAP_STRAND_OF_THE_ANCIENTS), XpRate::BgKillSOTA);
    EXPECT_EQ(SelectRate(XPSOURCE_KILL, true, MAP_ISLE_OF_CONQUEST), XpRate::BgKillIC);
}

TEST(XpOverrideTest, UnknownBattlegroundMapIdSkipsOverride)
{
    EXPECT_EQ(SelectRate(XPSOURCE_KILL, true, 999), XpRate::None);
}

TEST(XpOverrideTest, NonKillSources)
{
    EXPECT_EQ(SelectRate(XPSOURCE_QUEST, false, 0), XpRate::Quest);
    EXPECT_EQ(SelectRate(XPSOURCE_QUEST_DF, false, 0), XpRate::QuestDf);
    EXPECT_EQ(SelectRate(XPSOURCE_EXPLORE, false, 0), XpRate::Explore);
    EXPECT_EQ(SelectRate(XPSOURCE_BATTLEGROUND, false, 0), XpRate::BattlegroundBonus);
}

TEST(XpOverrideTest, UnknownSourceSkipsOverride)
{
    EXPECT_EQ(SelectRate(255, false, 0), XpRate::None);
}
