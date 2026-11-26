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
    context.zoneId = 1519;
    context.faction = PledgeFaction::Alliance;

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
    EXPECT_EQ(EvaluateToggle(context), ToggleResult::NotInPledgeArea);

    context.zoneId = 1519;
    context.faction = PledgeFaction::Alliance;
    context.cooldownRemainingSeconds = 1;
    EXPECT_EQ(EvaluateToggle(context), ToggleResult::Cooldown);

    context.cooldownRemainingSeconds = 0;
    EXPECT_EQ(EvaluateToggle(context), ToggleResult::Ok);
}

TEST(PvpRulesetsToggleTest, AreaAndCooldownAreBothRequired)
{
    ToggleContext context;
    context.enabled = true;
    context.alive = true;
    context.zoneId = 0;
    context.faction = PledgeFaction::Alliance;
    context.cooldownRemainingSeconds = 300;

    EXPECT_EQ(EvaluateToggle(context), ToggleResult::NotInPledgeArea);
}

TEST(PvpRulesetsToggleTest, UnsetFactionIsRefusedNotTreatedAsAlliance)
{
    // The context defaults faction to Any so a caller that forgets to set it fails closed.
    ToggleContext context;
    context.enabled = true;
    context.alive = true;
    context.zoneId = 1519; // Stormwind City, an Alliance capital

    EXPECT_EQ(EvaluateToggle(context), ToggleResult::WrongFaction);
}

TEST(PvpRulesetsToggleTest, EveryRefusalHasAMessage)
{
    for (ToggleResult result : { ToggleResult::Disabled, ToggleResult::GameMaster,
             ToggleResult::Dead, ToggleResult::InCombat, ToggleResult::InInstance,
             ToggleResult::InBattleground, ToggleResult::InArena, ToggleResult::InBattlefield,
             ToggleResult::NotInPledgeArea, ToggleResult::WrongFaction, ToggleResult::Cooldown })
    {
        EXPECT_STRNE(ToggleRefusalMessage(result), "");
    }

    EXPECT_STREQ(ToggleRefusalMessage(ToggleResult::Ok), "");
}

TEST(PvpRulesetsPledgeAreaTest, AllowsEveryFactionCapitalForItsFaction)
{
    EXPECT_TRUE(IsPledgeAreaAllowed(1519, PledgeFaction::Alliance)); // Stormwind City
    EXPECT_TRUE(IsPledgeAreaAllowed(1537, PledgeFaction::Alliance)); // Ironforge
    EXPECT_TRUE(IsPledgeAreaAllowed(1657, PledgeFaction::Alliance)); // Darnassus
    EXPECT_TRUE(IsPledgeAreaAllowed(3557, PledgeFaction::Alliance)); // The Exodar
    EXPECT_TRUE(IsPledgeAreaAllowed(1637, PledgeFaction::Horde));    // Orgrimmar
    EXPECT_TRUE(IsPledgeAreaAllowed(1497, PledgeFaction::Horde));    // Undercity
    EXPECT_TRUE(IsPledgeAreaAllowed(1638, PledgeFaction::Horde));    // Thunder Bluff
    EXPECT_TRUE(IsPledgeAreaAllowed(3487, PledgeFaction::Horde));    // Silvermoon City
}

TEST(PvpRulesetsPledgeAreaTest, AllowsNeutralHubsForBothFactions)
{
    for (uint32 areaId : { 3703u, 4395u }) // Shattrath City, Dalaran
    {
        EXPECT_TRUE(IsPledgeAreaAllowed(areaId, PledgeFaction::Alliance));
        EXPECT_TRUE(IsPledgeAreaAllowed(areaId, PledgeFaction::Horde));
    }
}

TEST(PvpRulesetsPledgeAreaTest, RefusesTheOtherFactionsCapitals)
{
    EXPECT_FALSE(IsPledgeAreaAllowed(1519, PledgeFaction::Horde));
    EXPECT_FALSE(IsPledgeAreaAllowed(1537, PledgeFaction::Horde));
    EXPECT_FALSE(IsPledgeAreaAllowed(1657, PledgeFaction::Horde));
    EXPECT_FALSE(IsPledgeAreaAllowed(3557, PledgeFaction::Horde));

    EXPECT_FALSE(IsPledgeAreaAllowed(1637, PledgeFaction::Alliance));
    EXPECT_FALSE(IsPledgeAreaAllowed(1497, PledgeFaction::Alliance));
    EXPECT_FALSE(IsPledgeAreaAllowed(1638, PledgeFaction::Alliance));
    EXPECT_FALSE(IsPledgeAreaAllowed(3487, PledgeFaction::Alliance));
}

TEST(PvpRulesetsPledgeAreaTest, RefusesAreaIdsOtherThanTheTenZones)
{
    // These are AREA ids, not zone ids. The command path passes Player::GetZoneId(), so a player
    // standing in one of these rooms reports its parent zone (Stormwind Harbor -> 1519, The
    // Underbelly -> 4395) and is allowed there. This test only says the allow-list is an exact
    // match on the ten zone ids: it must never widen to "any area under a listed city".
    //
    // A unit test on this pure function cannot see the wiring in PvpRulesets.cpp, so it cannot
    // prove the command path passes a zone. That intent is pinned by
    // UnsetFactionIsRefusedNotTreatedAsAlliance and by the comment on ToggleContext::zoneId.
    EXPECT_FALSE(IsPledgeAreaAllowed(4411, PledgeFaction::Alliance)); // Stormwind Harbor
    EXPECT_FALSE(IsPledgeAreaAllowed(4281, PledgeFaction::Alliance)); // Acherus: The Ebon Hold
    EXPECT_FALSE(IsPledgeAreaAllowed(4560, PledgeFaction::Alliance)); // The Underbelly
    EXPECT_FALSE(IsPledgeAreaAllowed(4564, PledgeFaction::Alliance)); // Krasus' Landing
    EXPECT_FALSE(IsPledgeAreaAllowed(4564, PledgeFaction::Horde));
    EXPECT_FALSE(IsPledgeAreaAllowed(4619, PledgeFaction::Horde));    // The Violet Citadel
    EXPECT_FALSE(IsPledgeAreaAllowed(4620, PledgeFaction::Horde));    // Magus Commerce Exchange
    EXPECT_FALSE(IsPledgeAreaAllowed(4679, PledgeFaction::Alliance)); // The Forlorn Cavern
    EXPECT_FALSE(IsPledgeAreaAllowed(3704, PledgeFaction::Horde));    // The Shepherd's Gate
    EXPECT_FALSE(IsPledgeAreaAllowed(1617, PledgeFaction::Alliance)); // Valley of Heroes
    EXPECT_FALSE(IsPledgeAreaAllowed(0, PledgeFaction::Alliance));
    EXPECT_FALSE(IsPledgeAreaAllowed(12, PledgeFaction::Horde)); // Elwynn Forest
}

TEST(PvpRulesetsPledgeAreaTest, NeutralFactionPlayerIsRefused)
{
    EXPECT_FALSE(IsPledgeAreaAllowed(1519, PledgeFaction::Any));
    EXPECT_FALSE(IsPledgeAreaAllowed(3703, PledgeFaction::Any));
}

TEST(PvpRulesetsToggleTest, NonPlayableFactionIsRefusedEvenInANeutralHub)
{
    ToggleContext context;
    context.enabled = true;
    context.alive = true;
    context.zoneId = 4395; // Dalaran
    context.faction = PledgeFaction::Any;

    EXPECT_EQ(EvaluateToggle(context), ToggleResult::WrongFaction);
}

TEST(PvpRulesetsPledgeAreaTest, ListHoldsExactlyTheOwnerApprovedTenAreas)
{
    ASSERT_EQ(PLEDGE_AREAS.size(), 10u);

    for (PledgeArea const& area : PLEDGE_AREAS)
    {
        EXPECT_NE(area.AreaId, 0u);
        EXPECT_TRUE(area.Faction == PledgeFaction::Alliance || area.Faction == PledgeFaction::Horde
            || area.Faction == PledgeFaction::Any);
    }
}

TEST(PvpRulesetsToggleTest, RefusesWrongFactionCapitalWithItsOwnReason)
{
    ToggleContext context;
    context.enabled = true;
    context.alive = true;
    context.zoneId = 1519; // Stormwind City
    context.faction = PledgeFaction::Horde;

    EXPECT_EQ(EvaluateToggle(context), ToggleResult::WrongFaction);
    EXPECT_STREQ(ToggleRefusalMessage(ToggleResult::WrongFaction),
        "You can only change your pledge in a capital city of your own faction.");
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
