# ADR-033 — PvP rulesets: PvE, War Mode, High Risk, Mercenary and Outlaw

- Status: proposed (owner decisions folded in; acceptance pending)
- Date: 2026-11-23
- Proposal: [RFC-006](../rfcs/active/RFC-006-pvp-rulesets.md)
- Contract: a durable `specs/` file is created after this ADR is accepted; until then RFC-006 is the
  reviewable proposal and does not override any accepted spec.

## Context

The realm is one PvE realm (`GameType = 0`). Cross-faction social play is already on
([ADR-023](ADR-023-cross-faction-social-layer.md)) and the PvP queueing slice shipped
([ADR-024](ADR-024-pvp-queueing-slice.md)). The open-world PvP gap remains: no opt-in war mode, no
risk/reward tier, no mercenary play, and no consequence for killing your own faction.

The owner wants Ascension-style rulesets without splitting the realm. Each character chooses a mode.
The modes must not become pay-for-power, and the first slice must not need a large new gameplay
system or a client patch.

Phase note: this is Phase 2 custom content ([ADR-013](ADR-013-server-and-client-before-website.md)).
Acceptance of this ADR does not start implementation; the Phase 2 gate still applies.

## Decision

1. **One realm, three per-character modes.** `GameType` stays 0. `PvE` is the default; `War Mode`
   and `High Risk` are opt-in. The mode is a row in a module-owned characters table, not a realm
   type, account flag, or aura. Alts choose independently.
2. **Toggle in capitals.** `.pledge <pve|warmode|highrisk>` is the v1 surface. It works only in a
   capital city (`AreaTableEntry::flags & AREA_FLAG_CAPITAL`; Shattrath/Dalaran are unverified),
   out of combat, alive, not in an instance/BG/arena/battlefield, not while Outlaw, and after a
   5-minute cooldown. A gossip broker NPC wraps the same command later. The server is
   authoritative; the client cannot set a mode.
3. **PvE Mode.** No PvP flag from the mode, so the player is not attackable by players while
   unflagged. The native opt-ins remain: `/pvp` and attacking a flagged player. No XP bonus.
   **Owner decision:** keep the core's forced PvP flag in enemy capitals. Do not add a seam to
   suppress it; the fourth approved seam is only for guard aggro (decision 12). A PvE player in an
   enemy capital is flagged and can be attacked there.
4. **War Mode.** Persistent PvP flag, standard world PvP, no loot or gold loss, **+10% XP**.
   The flag is re-asserted on login, zone change, resurrection, and any unexpected clear. The
   client `/pvp` toggle is refused in War, High Risk and while Outlaw.
5. **High Risk.** War Mode plus **+20% XP** (owner decision 2026-11-26; the original text said
   +15%, and the code default and shipped config now say 20) and a death cost. On death by a player, the lost **10%
   of carried gold** (cap 100g) goes into **one runtime chest** at the death position. The killer
   has first claim for a grace period; if the killer does not claim it, the victim can claim the
   remaining gold for a recovery period. **V1 is gold-only:** no item moves. The stock loot window
   is not used because `SendLoot` grants `ALL_PERMISSION`, `rollWinnerGUID` does not gate gold, and
   `LootItem` re-creates items from template data without gems or durability. A custom
   `GameObjectScript` checks the owner and pays directly, then deletes the chest. No mail, no second
   container, no item path. The chest template uses `lootId=0`, `chestRestockTime=0`,
   `groupLootRules=1`, `consumable=1`, and zero `gameobject_template_addon` gold. There is no
   `gameobject_addon` row: that table is per-spawn and has no gold columns. The chest is runtime-only:
   a restart or despawn loses the remaining gold and never duplicates it.
   **Owner confirmed:** v1 is gold-only. Item loss is out of v1 and deferred until an exact-snapshot
   design exists; no item is moved in this contract.
6. **XP bonuses are outdoor-only.** War/High Risk XP applies to all XP sources in the open world,
   not in instances, BGs, arenas, battlefields, no-PvP areas or sanctuaries. This closes the
   capital quest-turn-in bank. It is not configurable in v1. Multiplicative with the global rate and
   with other percentage bonuses (Ancestral Wisdom). Values are playtest knobs.
7. **Mercenary for Hire.** Level 15+, requires War or High Risk, accepted in a capital. Grants the
   FFA flag and the ability to attack own-faction players who are in War/High Risk, and to be
   attacked by them. Cross-faction grouping is allowed; mercenaries can group with each other and
   assist each other. Removal is `.pledge renounce` in any rested area, out of combat, not in an
   instance/BG/arena, not while Outlaw. The contract does not change faction, race, reputation,
   vendors, or guards by itself.
   **Owner decision:** the narrow `OnPlayerGetReactionTo` seam is approved for mercenary
   own-faction attacks and Outlaw hunting; it is hostile in both directions.
   **Client verification gate:** the stock 3.3.5 client may refuse to start a same-faction attack
   even when the server seam is hostile. Two same-faction clients must verify it before the feature
   is marked complete. If the client refuses, v1 sets the FFA byte on the mercenary and the Outlaw
   as a client hint, with the documented grouping consequences. Rows 11 and 18 of the RFC test plan
   stay conditional until that test passes.
8. **Outlaw.** Killing an own-faction player in the open world applies Outlaw:
   - the first kill starts a **5-minute** timer;
   - each further own-faction kill **adds 5 minutes**;
   - the remaining time is capped at **60 minutes**;
   - **the timer is the only exit in v1.** Death, a guard kill, an NPC kill, an environment death,
     a faction change, a logout, a sanctuary, an instance, a BG, an arena or a duel do not remove
     it.
   Effects: a debuff carrier, the contested-PvP flag, `SetPvP(true)` for the duration, hostile
   own-faction guards, blocked city services, and own-faction PvP-flagged players can hunt the
   Outlaw through the approved reaction seam. Groupmates are exempt. **Killing an existing Outlaw
   does not create or extend the hunter's Outlaw timer**; the hunt must not self-punish. The Outlaw
   does **not** carry `UNIT_STATE_ATTACK_PLAYER`; that state would flag friendly healers and buffers
   through the core assisting rule. Duels, BGs, arenas and FFA areas do not create Outlaw. NPC kills
   do not extend it.
9. **Grouping.** Cross-faction grouping stays as ADR-023. A PvE player cannot land a positive spell
   on a groupmate who is PvP-flagged and in PvP combat. Same-faction War/High Risk players assist
   each other. Group membership always overrides FFA hostility. Area-of-effect heals are not
   filtered; the core may flag the caster and that is documented.
10. **Anti-abuse.** Same-account kills are ignored entirely. Same-IP kills (socket peer address), a
    pair within 30 minutes in either direction, more than 3 credited kills per pair per day, a
    gray-level victim, or a victim flagged for under 15 seconds **do not create a High Risk chest**;
    the Outlaw timer still extends because it is a penalty, not a reward. NPC kills never count.
11. **Live visibility.** V1 has no broadcast position feed. A runtime Outlaw registry and
    `.pledge status` show the Outlaws in the same zone on demand. On each own-faction kill the
    server sends one map-scoped chat alert to the same continent naming killer, victim, zone and
    subzone; every own-faction kill sends one map-scoped chat alert on the continent open-world map,
    with no cooldown or suppression. The map POI feed (zone-scoped, 5 seconds) was withdrawn with
    the general layer on 2026-11-27 (ADR-032 → ADR-037). V1 has no consumer; a future Outlaw marker
    needs a new decision and client contract. Players outside the zone see the alert and must travel
    to the zone for that future marker.
12. **Architecture.** Tracked module `modules/mod-pvp-rulesets`, custom characters and world SQL,
    event-driven script hooks, no per-tick player scans, no per-kill database writes except one small
    update of the Outlaw deadline. Four narrow core seams, all approved: an NPC/gameobject
    interaction gate, a PvP-toggle gate, a player reaction override, and a guard LOS/aggro fallback
    for capitals whose guards lack the contested-guard DBC flag. GM mode has no seam: there is no
    `SetGameMaster` hook, the module skips GM characters, and automatic re-application after
    `.gm off` is not promised.
    The chest is a custom `GameObjectScript` use gate with direct gold payment, not a stock loot
    window. The world SQL creates the chest template with `lootId=0`, `chestRestockTime=0`,
    `groupLootRules=1`, `consumable=1`, zero `gameobject_template_addon` gold and the script name;
    no `gameobject_addon` row.
13. **No purchased power.** Modes are free. No shop item, gold cost, stat or gear advantage, and no
    purchasable reward or XP. The chest moves existing property; it does not generate a reward.
14. **Client-patch follow-up.** Stock carrier spells, chat and `.pledge status` ship first. A client
    patch is required later for the Outlaw map marker (not implemented) and the unit/status visual
    (mode and Outlaw display, icons, tooltips). The old general POI layer and its Outlaw protocol
    were withdrawn on 2026-11-27 (ADR-032 → ADR-037); the Outlaw marker needs a new decision.
    Commands and chat are not a substitute for the visual layer.
15. **Out of scope.** Item loss in the chest until an exact-snapshot design exists; War Mode
    materials, Bloodforged, Marks of War, Hidden Caches; the broker NPC content; cross-realm play;
    rated PvP changes.

## Alternatives considered

- **Separate PvP or War Mode realms.** Splits the population and changes the realm strategy
  ([ADR-018](ADR-018-realm-strategy.md)). Rejected: one realm, opt-in modes.
- **Client `/pvp` toggle as the mode.** Not authoritative and trivially exploitable. Rejected:
  server-owned mode row and server-side flag application.
- **All-in-core implementation.** Merge burden and a large fork diff. Rejected: module plus four
  approved seams.
- **Stock loot window for the chest.** `SendLoot` grants `ALL_PERMISSION`, `rollWinnerGUID` does not
  gate gold, and `LootItem` loses gems/durability. Rejected: custom use gate, direct gold payment.
- **Item transfer in v1.** Needs an exact snapshot for gems, durability, enchantments and charges.
  Deferred; gold-only v1.
- **Mail fallback for chest contents.** Creates a second delivery path and a dupe surface. Rejected:
  one runtime chest, no mail.
- **Custom spell auras and map marker in v1.** Need the client-patch pipeline. Deferred to the
  client-patch follow-up; stock carriers plus chat in v1.
- **Flat versus multiplicative XP stacking.** Multiplicative is consistent with Ancestral Wisdom and
  simpler to reason about, with a documented ±1 XP rounding tolerance.

## Consequences and tradeoffs

- Positive: opt-in risk/reward with no realm split; reuses the native PvP, FFA and contested-guard
  mechanisms; the reaction seam is approved; the High Risk chest has one owner and one lifetime; no
  generated reward economy, only a property move.
- **Native opt-in in PvE is preserved:** `/pvp` remains available in PvE mode and attacking a flagged
  player still flags the attacker. The mode blocks the flag, not the native opt-in.
- Costs: chest support and a real dupe review; the Outlaw timer needs a durable deadline; the v1
  client has no map marker; same-faction attacks need a client test and may need the FFA fallback;
  guard hostility depends on a DBC faction flag that must be verified per capital; XP and gold
  values are playtest knobs.
- Rollback: set `PvpRulesets.Enable = 0`; every character returns to PvE at next login, flags are
  cleared by the normal timers, Outlaw rows are ignored, and the tables stay for a later re-enable.
  Runtime chests disappear on restart; their gold is lost, never duplicated.

## Open decisions

None. The owner resolved the last two on 2026-11-23. The remaining gates are verification-only:

- same-faction client attack (FFA fallback if the stock client refuses);
- per-capital `AREA_FLAG_CAPITAL` and guard DBC flag checks;
- Shattrath/Dalaran capital status.

These are recorded in the RFC-006 test plan, not as open design questions.

## Revision 2026-11-26 — the pledge is allowed in ten listed capitals, faction-checked

This revision replaces decision 2's location gate only. Nothing else in the ADR changes.

**Owner decision.** `.pledge` is allowed **only** in these ten zones, and only when the player's
faction is the zone's faction or the zone is shared:

| Faction | Zones |
|---------|-------|
| Alliance | 1519 Stormwind City, 1537 Ironforge, 1657 Darnassus, 3557 The Exodar |
| Horde | 1637 Orgrimmar, 1497 Undercity, 1638 Thunder Bluff, 3487 Silvermoon City |
| Both | 3703 Shattrath City, 4395 Dalaran |

Everything else is refused.

**The defect this fixes.** The replaced gate read `IsCapitalZone(player->GetZoneId())`, so it
already resolved to the parent zone. Measured against the stock `AreaTable.dbc`, only **10** of the
35 rows that carry `AREA_FLAG_CAPITAL` are zone-level rows, and they are exactly the ten above; the
other 25 are sub-areas whose zone id is their parent, which is why Stormwind Harbor (4411, zone
1519) and every Dalaran sub-area were already accepted, and why Acherus (4281, zone 139 Eastern
Plaguelands) was already refused. A flag-based gate was therefore not the broken part.

The broken part was **faction**: the gate never read it, so a Horde character could pledge in
Stormwind. That is what this revision closes. An explicit list replaces the flag so the design
decision is auditable in one place rather than inferred from a DBC flag whose meaning is wider than
the design.

**Implementation.** `PLEDGE_AREAS` in `modules/mod-pvp-rulesets/src/PvpRulesets.h` is the single
list of `{ zone id, faction }`; `EvaluateToggle()` applies it through `IsPledgeAreaAllowed()`, one
copy of the rule, with separate refusal results for "not a pledge zone" and "wrong faction".
`ToggleContext::zoneId` carries `Player::GetZoneId()` and defaults to faction `Any`, so a caller
that forgets to set the faction is refused rather than silently treated as Alliance. The list is a
code constant, not a config option: it is a game-design decision, not a tuning knob. The faction in
the list is a hand-written constant, **not** read from the AreaTable `team` column. Every other
guard (out of combat, alive, not in an instance/BG/arena/battlefield, not while Outlaw, not in GM
mode, the persisted cooldown) is unchanged.

**Sub-areas pass with their city.** Because the id is a zone, a player standing in Stormwind Harbor
reports 1519, and one in The Underbelly reports 4395. That is intended: the listed zones are the
cities a player moves around in. A unit test on the pure function cannot see this wiring, so it
asserts only that the list is an exact match on ten zone ids; the zone-versus-area intent is pinned
by the field comment and by a test that an unset faction is refused.

This closes the "per-capital `AREA_FLAG_CAPITAL` … checks" and "Shattrath/Dalaran capital status"
verification gates. The per-capital guard DBC flag check stays open.

### Accepted residue — quest turn-in XP

The owner chose not to add a per-quest mode snapshot, so the mode bonus can still reach a quest
turn-in. The mechanism is narrower than "pledge then hand in", and this is the measured behaviour,
not a live test:

- `IsOutdoorXpEligible()` excludes `inNoPvPArea`, and the core sets `IsInNoPvPArea = true` on
  entering any area flagged `AREA_FLAG_CAPITAL` (`PlayerUpdates.cpp`, the capital branch). All ten
  listed zones carry that flag, so **on first entering the city the mode bonus does not apply**.
- `IsInNoPvPArea` is cleared by `ProcessPositionDataChanged` on any intra-zone area change and is
  only re-set if the new area is a sanctuary. Moving between two sub-areas of the same city
  therefore clears it.
- So the residue is reachable by entering the city, walking from one sub-area to another, then
  turning the quest in. It is not reachable by standing still.

The owner accepted this. It is recorded as an open, known residue to revisit when quest XP is next
touched, and **not** as a closed hole: the ten-zone gate does not close it. A live test is still
owed, since no in-game run measured the flag transitions above.

## References

- [RFC-006](../rfcs/active/RFC-006-pvp-rulesets.md)
- [ADR-012](ADR-012-progression-rates.md), [ADR-013](ADR-013-server-and-client-before-website.md)
- [ADR-023](ADR-023-cross-faction-social-layer.md), [ADR-024](ADR-024-pvp-queueing-slice.md)
- [specs/security.md](../specs/security.md),
  [specs/testing-and-release.md](../specs/testing-and-release.md)
- [runbook/database/id-registry.md](../runbook/database/id-registry.md)
