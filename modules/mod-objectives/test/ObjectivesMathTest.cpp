#include "ObjectivesMath.h"

#include <gtest/gtest.h>

#include <limits>

TEST(ObjectivesMathTest, StaleDailyDoesNotRebuildWeekly)
{
    Objectives::Math::BoardValidation validation;
    validation.dailyValid = true;
    validation.weeklyValid = true;
    validation.dailyInvalid = true;

    EXPECT_TRUE(Objectives::Math::RebuildDaily(validation));
    EXPECT_FALSE(Objectives::Math::RebuildWeekly(validation));

    validation.dailyInvalid = false;
    validation.weeklyInvalid = true;
    EXPECT_FALSE(Objectives::Math::RebuildDaily(validation));
    EXPECT_TRUE(Objectives::Math::RebuildWeekly(validation));
}

TEST(ObjectivesMathTest, ProgressClampsAtRequirement)
{
    EXPECT_EQ(Objectives::Math::ApplyProgress(0, 3, 10), 3u);
    EXPECT_EQ(Objectives::Math::ApplyProgress(9, 1, 10), 10u);
    EXPECT_EQ(Objectives::Math::ApplyProgress(7, 99, 10), 10u);
    EXPECT_EQ(Objectives::Math::ApplyProgress(10, 5, 10), 10u);
    EXPECT_EQ(Objectives::Math::ApplyProgress(0, 1, 0), 0u);
}

TEST(ObjectivesMathTest, ProgressDoesNotWrap)
{
    EXPECT_EQ(Objectives::Math::ApplyProgress(std::numeric_limits<uint32>::max() - 2, 10, 100),
        100u);
    EXPECT_EQ(Objectives::Math::ApplyProgress(1, std::numeric_limits<uint32>::max(), 100), 100u);
}

TEST(ObjectivesMathTest, CompletionNeedsARequirement)
{
    EXPECT_FALSE(Objectives::Math::IsComplete(0, 0));
    EXPECT_FALSE(Objectives::Math::IsComplete(1, 2));
    EXPECT_TRUE(Objectives::Math::IsComplete(2, 2));
    EXPECT_TRUE(Objectives::Math::IsComplete(3, 2));
}

TEST(ObjectivesMathTest, ResetIsDueAtItsResetTime)
{
    EXPECT_TRUE(Objectives::Math::ResetDue(0, 1000));
    EXPECT_FALSE(Objectives::Math::ResetDue(1001, 1000));
    EXPECT_TRUE(Objectives::Math::ResetDue(1000, 1000));
    EXPECT_TRUE(Objectives::Math::ResetDue(999, 1000));
}

TEST(ObjectivesMathTest, RerollCostRisesPerPurchase)
{
    EXPECT_EQ(Objectives::Math::RerollCost(5000, 0), 5000u);
    EXPECT_EQ(Objectives::Math::RerollCost(5000, 1), 10000u);
    EXPECT_EQ(Objectives::Math::RerollCost(5000, 3), 20000u);
    EXPECT_EQ(Objectives::Math::RerollCost(0, 7), 0u);
    EXPECT_EQ(Objectives::Math::RerollCost(std::numeric_limits<uint32>::max(), 1),
        uint64(std::numeric_limits<uint32>::max()));
}

TEST(ObjectivesMathTest, SlotCountIsCapped)
{
    EXPECT_EQ(Objectives::Math::ClampSlots(5, 7), 5u);
    EXPECT_EQ(Objectives::Math::ClampSlots(7, 7), 7u);
    EXPECT_EQ(Objectives::Math::ClampSlots(8, 7), 7u);
    EXPECT_EQ(Objectives::Math::ClampSlots(0, 7), 0u);
    EXPECT_EQ(Objectives::Math::ClampSlots(3, 1), 1u);
}
