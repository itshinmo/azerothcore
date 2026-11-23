/*
 * Unit tests for the pure PvP ruleset logic (RFC-006, ADR-033).
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

#include <gtest/gtest.h>

using namespace PvpRulesets;

TEST(PvpRulesetsModeTest, ParsesEverySupportedToken)
{
    EXPECT_EQ(ParseMode("pve"), Mode::Pve);
    EXPECT_EQ(ParseMode("warmode"), Mode::WarMode);
    EXPECT_EQ(ParseMode("highrisk"), Mode::HighRisk);
}

TEST(PvpRulesetsModeTest, RejectsUnknownAndMixedCaseTokens)
{
    EXPECT_FALSE(ParseMode(""));
    EXPECT_FALSE(ParseMode("pvp"));
    EXPECT_FALSE(ParseMode("war"));
    EXPECT_FALSE(ParseMode("WarMode"));
    EXPECT_FALSE(ParseMode("high risk"));
}

TEST(PvpRulesetsModeTest, TokensRoundTrip)
{
    for (Mode mode : { Mode::Pve, Mode::WarMode, Mode::HighRisk })
    {
        std::optional<Mode> const parsed = ParseMode(ModeToken(mode));
        ASSERT_TRUE(parsed.has_value());
        EXPECT_EQ(*parsed, mode);
    }
}

TEST(PvpRulesetsModeTest, DisplayNames)
{
    EXPECT_STREQ(ModeDisplayName(Mode::Pve), "PvE");
    EXPECT_STREQ(ModeDisplayName(Mode::WarMode), "War Mode");
    EXPECT_STREQ(ModeDisplayName(Mode::HighRisk), "High Risk");
}

TEST(PvpRulesetsModeTest, PvpFlagOnlyForWarAndHighRisk)
{
    EXPECT_FALSE(ModeUsesPvpFlag(Mode::Pve));
    EXPECT_TRUE(ModeUsesPvpFlag(Mode::WarMode));
    EXPECT_TRUE(ModeUsesPvpFlag(Mode::HighRisk));
}

TEST(PvpRulesetsXpTest, PercentPerMode)
{
    EXPECT_EQ(XpBonusPercent(Mode::Pve, 10, 15), 0u);
    EXPECT_EQ(XpBonusPercent(Mode::WarMode, 10, 15), 10u);
    EXPECT_EQ(XpBonusPercent(Mode::HighRisk, 10, 15), 15u);
}

TEST(PvpRulesetsXpTest, BonusIsTruncated)
{
    EXPECT_EQ(ApplyXpBonus(100, 10), 110u);
    EXPECT_EQ(ApplyXpBonus(105, 15), 120u);
    EXPECT_EQ(ApplyXpBonus(1, 15), 1u);
    EXPECT_EQ(ApplyXpBonus(7, 0), 7u);
    EXPECT_EQ(ApplyXpBonus(0, 15), 0u);
}

TEST(PvpRulesetsXpTest, OutdoorGateAllowsOpenWorld)
{
    EXPECT_TRUE(IsOutdoorXpEligible(OutdoorXpContext{}));
}

TEST(PvpRulesetsXpTest, OutdoorGateRefusesEveryExcludedLocation)
{
    OutdoorXpContext context;
    context.inDungeon = true;
    EXPECT_FALSE(IsOutdoorXpEligible(context));

    context = {};
    context.inBattleground = true;
    EXPECT_FALSE(IsOutdoorXpEligible(context));

    context = {};
    context.inArena = true;
    EXPECT_FALSE(IsOutdoorXpEligible(context));

    context = {};
    context.inBattlefield = true;
    EXPECT_FALSE(IsOutdoorXpEligible(context));

    context = {};
    context.inNoPvpArea = true;
    EXPECT_FALSE(IsOutdoorXpEligible(context));

    context = {};
    context.inSanctuary = true;
    EXPECT_FALSE(IsOutdoorXpEligible(context));
}

TEST(PvpRulesetsToggleTest, AcceptsAliveOutOfCombatCapital)
{
    ToggleContext context;
    context.enabled = true;
    context.alive = true;
    context.inCapital = true;

    EXPECT_EQ(EvaluateToggle(context), ToggleResult::Ok);
}

TEST(PvpRulesetsToggleTest, GuardsInFixedOrder)
{
    ToggleContext context;

    EXPECT_EQ(EvaluateToggle(context), ToggleResult::Disabled);

    context.enabled = true;
    EXPECT_EQ(EvaluateToggle(context), ToggleResult::Dead);

    context.alive = true;
    context.gameMaster = true;
    EXPECT_EQ(EvaluateToggle(context), ToggleResult::GameMaster);

    context.gameMaster = false;
    context.inCombat = true;
    EXPECT_EQ(EvaluateToggle(context), ToggleResult::InCombat);

    context.inCombat = false;
    context.inInstance = true;
    EXPECT_EQ(EvaluateToggle(context), ToggleResult::InInstance);

    context.inInstance = false;
    context.inBattleground = true;
    EXPECT_EQ(EvaluateToggle(context), ToggleResult::InBattleground);

    context.inBattleground = false;
    context.inArena = true;
    EXPECT_EQ(EvaluateToggle(context), ToggleResult::InArena);

    context.inArena = false;
    context.inBattlefield = true;
    EXPECT_EQ(EvaluateToggle(context), ToggleResult::InBattlefield);

    context.inBattlefield = false;
    EXPECT_EQ(EvaluateToggle(context), ToggleResult::NotInCapital);

    context.inCapital = true;
    context.cooldownRemainingSeconds = 1;
    EXPECT_EQ(EvaluateToggle(context), ToggleResult::Cooldown);

    context.cooldownRemainingSeconds = 0;
    EXPECT_EQ(EvaluateToggle(context), ToggleResult::Ok);
}

TEST(PvpRulesetsToggleTest, CapitalAndCooldownAreBothRequired)
{
    ToggleContext context;
    context.enabled = true;
    context.alive = true;
    context.inCapital = false;
    context.cooldownRemainingSeconds = 300;

    EXPECT_EQ(EvaluateToggle(context), ToggleResult::NotInCapital);
}

TEST(PvpRulesetsToggleTest, EveryRefusalHasAMessage)
{
    for (ToggleResult result : { ToggleResult::Disabled, ToggleResult::GameMaster,
             ToggleResult::Dead, ToggleResult::InCombat, ToggleResult::InInstance,
             ToggleResult::InBattleground, ToggleResult::InArena, ToggleResult::InBattlefield,
             ToggleResult::NotInCapital, ToggleResult::Cooldown })
    {
        EXPECT_STRNE(ToggleRefusalMessage(result), "");
    }

    EXPECT_STREQ(ToggleRefusalMessage(ToggleResult::Ok), "");
}

TEST(PvpRulesetsCooldownTest, RemainingSeconds)
{
    EXPECT_EQ(CooldownRemainingSeconds(1000, 0, 300), 0);
    EXPECT_EQ(CooldownRemainingSeconds(1000, 1000, 300), 300);
    EXPECT_EQ(CooldownRemainingSeconds(1000, 700, 300), 0);
    EXPECT_EQ(CooldownRemainingSeconds(1000, 999, 300), 299);
    EXPECT_EQ(CooldownRemainingSeconds(1000, 1000, 0), 0);
}

TEST(PvpRulesetsCooldownTest, BackwardsClockDoesNotBypassTheWait)
{
    EXPECT_EQ(CooldownRemainingSeconds(1000, 1200, 300), 300);
}
