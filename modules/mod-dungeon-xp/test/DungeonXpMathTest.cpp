#include "DungeonXpMath.h"

#include <gtest/gtest.h>

TEST(DungeonXpMathTest, TrashUsesTrashFactor)
{
    EXPECT_FLOAT_EQ(DungeonXp::Math::SelectKillFactor(true, false, true, false, 0.10f, 0.33f), 0.10f);
}

TEST(DungeonXpMathTest, BossUsesBossFactor)
{
    EXPECT_FLOAT_EQ(DungeonXp::Math::SelectKillFactor(true, false, true, true, 0.10f, 0.33f), 0.33f);
}

TEST(DungeonXpMathTest, WorldMapKeepsFullRate)
{
    EXPECT_FLOAT_EQ(DungeonXp::Math::SelectKillFactor(false, false, true, false, 0.10f, 0.33f), 1.0f);
    EXPECT_FLOAT_EQ(DungeonXp::Math::SelectKillFactor(false, false, true, true, 0.10f, 0.33f), 1.0f);
    EXPECT_FLOAT_EQ(DungeonXp::Math::SelectKillFactor(false, false, false, true, 0.0f, 0.0f), 1.0f);
}

TEST(DungeonXpMathTest, WorldMapKeepsFullRateEvenWithRaidsOff)
{
    // Distinct branch: a plain dungeon with IncludeRaids off must still take the split.
    EXPECT_FLOAT_EQ(DungeonXp::Math::SelectKillFactor(true, false, false, false, 0.10f, 0.33f), 0.10f);
    EXPECT_FLOAT_EQ(DungeonXp::Math::SelectKillFactor(true, false, false, true, 0.10f, 0.33f), 0.33f);
}

TEST(DungeonXpMathTest, BossKillNeedsAnInstanceAndAnyBossSignal)
{
    // Outside an instance nothing is a boss, whatever the flags say.
    EXPECT_FALSE(DungeonXp::Math::IsBossKill(false, true, true, true));
    // Inside, any one of the three signals is enough.
    EXPECT_TRUE(DungeonXp::Math::IsBossKill(true, true, false, false));   // dungeon-boss flag
    EXPECT_TRUE(DungeonXp::Math::IsBossKill(true, false, true, false));   // world-boss type flag
    EXPECT_TRUE(DungeonXp::Math::IsBossKill(true, false, false, true));   // cast-credited encounter
    EXPECT_FALSE(DungeonXp::Math::IsBossKill(true, false, false, false)); // plain trash
}

TEST(DungeonXpMathTest, RaidRespectsIncludeRaids)
{
    EXPECT_FLOAT_EQ(DungeonXp::Math::SelectKillFactor(true, true, false, false, 0.10f, 0.33f), 1.0f);
    EXPECT_FLOAT_EQ(DungeonXp::Math::SelectKillFactor(true, true, false, true, 0.10f, 0.33f), 1.0f);
    EXPECT_FLOAT_EQ(DungeonXp::Math::SelectKillFactor(true, true, true, false, 0.10f, 0.33f), 0.10f);
    EXPECT_FLOAT_EQ(DungeonXp::Math::SelectKillFactor(true, true, true, true, 0.10f, 0.33f), 0.33f);
}

TEST(DungeonXpMathTest, KillFactorsClampToUnitRange)
{
    EXPECT_FLOAT_EQ(DungeonXp::Math::ClampKillFactor(-0.5f), 0.0f);
    EXPECT_FLOAT_EQ(DungeonXp::Math::ClampKillFactor(0.10f), 0.10f);
    EXPECT_FLOAT_EQ(DungeonXp::Math::ClampKillFactor(1.0f), 1.0f);
    EXPECT_FLOAT_EQ(DungeonXp::Math::ClampKillFactor(2.5f), 1.0f);
}

TEST(DungeonXpMathTest, QuestFactorNeverCuts)
{
    EXPECT_FLOAT_EQ(DungeonXp::Math::ClampQuestFactor(0.0f), 1.0f);
    EXPECT_FLOAT_EQ(DungeonXp::Math::ClampQuestFactor(-2.0f), 1.0f);
    EXPECT_FLOAT_EQ(DungeonXp::Math::ClampQuestFactor(1.0f), 1.0f);
    EXPECT_FLOAT_EQ(DungeonXp::Math::ClampQuestFactor(3.0f), 3.0f);
}
