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

#include <array>
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

    // Pledge area allow-list (ADR-033 revision 2026-11-26). This is a game-design decision,
    // not a tuning knob, so it stays a code constant and is not configurable: the stock
    // `AREA_FLAG_CAPITAL` flag covers 35 rows, including Stormwind Harbor (4411), Acherus:
    // The Ebon Hold (4281), every Dalaran sub-area and The Forlorn Cavern (4679), so the flag
    // cannot be used as the gate.
    // Ids are `AreaTableEntry::ID` rows; the area's `team` column (AREATEAM_*) must be
    // neutral or match the player's faction.
    //
    // `Player::GetAreaId()` reports the most specific area, not the zone: standing in
    // Darnassus' Cenarion Enclave reports the sub-area, not 1657, and Dalaran has 20
    // sub-areas. The command path therefore passes the *zone* (`GetZoneId()`), which the core
    // resolves from the sub-area's parent in `WorldObject::ProcessPositionDataChanged`. Passing
    // the area id instead would refuse a pledge in most of Darnassus and all of Dalaran.
    // Consequence: a pledge is allowed in Stormwind Harbor too, because its zone is 1519. That
    // is accepted: the harbour is a normal part of the city a player walks around in.
    enum class PledgeFaction : uint8
    {
        Alliance = 0,
        Horde,
        Any,
    };

    struct PledgeArea
    {
        uint32 AreaId;
        PledgeFaction Faction;
    };

    inline constexpr std::array<PledgeArea, 10> PLEDGE_AREAS = {{
        { 1519, PledgeFaction::Alliance }, // Stormwind City
        { 1537, PledgeFaction::Alliance }, // Ironforge
        { 1657, PledgeFaction::Alliance }, // Darnassus
        { 3557, PledgeFaction::Alliance }, // The Exodar
        { 1637, PledgeFaction::Horde },    // Orgrimmar
        { 1497, PledgeFaction::Horde },    // Undercity
        { 1638, PledgeFaction::Horde },    // Thunder Bluff
        { 3487, PledgeFaction::Horde },    // Silvermoon City
        { 3703, PledgeFaction::Any },      // Shattrath City
        { 4395, PledgeFaction::Any },      // Dalaran
    }};

    // The player faction must be Alliance or Horde; `Any` is an area requirement only.
    // An area whose list entry is `Any` accepts both factions.
    // Takes a ZONE id (Player::GetZoneId()), not an area id.
    bool IsPledgeAreaAllowed(uint32 zoneId, PledgeFaction playerFaction);

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
        NotInPledgeArea,
        WrongFaction,
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
        // A zone id, not an area id: `Player::GetZoneId()`. Do not "fix" this to GetAreaId(),
        // which reports the most specific sub-area and would refuse every city that has one.
        uint32 zoneId = 0;
        // Neutral default: a context that forgets to set this is refused, not silently Alliance.
        PledgeFaction faction = PledgeFaction::Any;
        int64 cooldownRemainingSeconds = 0;
    };

    ToggleResult EvaluateToggle(ToggleContext const& context);
    char const* ToggleRefusalMessage(ToggleResult result);

    // Seconds left on the persisted pledge cooldown. A clock that moved backwards reports a
    // full cooldown so a relog cannot bypass the wait.
    int64 CooldownRemainingSeconds(int64 now, int64 lastToggle, uint32 cooldownSeconds);
}

#endif
