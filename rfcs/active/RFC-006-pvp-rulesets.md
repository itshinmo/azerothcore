# RFC-006 — PvP rulesets: PvE, War Mode, High Risk, Mercenary and Outlaw

- Status: draft (owner decisions of 2026-11-23 applied; ADR-033 proposed)
- Date: 2026-11-23
- Author: agent session (feat/pvp-rulesets)
- Decisions: owner decisions on the reaction seam, enemy-capital flag, corpse chest, the Outlaw
  timer, live visibility and the client-patch follow-up; final decisions: gold-only High Risk chest,
  fourth guard LOS/aggro seam.
- Decision record: [ADR-033](../../decisions/ADR-033-pvp-rulesets.md) (proposed). This RFC is a
  proposal; it does not override an accepted spec.

## Problem

The realm is one PvE realm (`GameType = 0`) with cross-faction social play already enabled
([ADR-023](../../decisions/ADR-023-cross-faction-social-layer.md)) and PvP queueing shipped
([ADR-024](../../decisions/ADR-024-pvp-queueing-slice.md)). There is no opt-in open-world PvP mode,
no risk/reward tier, no mercenary play, and no consequence for killing your own faction.

The owner wants Ascension-style rulesets without splitting the realm. Each character chooses a
mode. The modes must not become pay-for-power, and the first slice must not need a large new
gameplay system or a client patch.

## Proposal

### 1. Realm and modes

- The realm is one PvE realm with `GameType = 0`. At startup, if `PvpRulesets.Enable = 1` and
  `GameType != 0`, the module logs one `ERROR` and disables itself. It never silently changes a
  realm's type.
- One mode per character, stored in `mod_pvp_rulesets_state.mode`:

| Value | Mode | PvP flag | Attacks players | Attackable by players | XP bonus | Death cost |
|-------|------|----------|-----------------|-----------------------|----------|------------|
| 0 | PvE | no | native opt-in only* | no while unflagged | none | none |
| 1 | War Mode | yes | opposite faction, mercenaries | yes | +10% | none |
| 2 | High Risk | yes | opposite faction, mercenaries | yes | +15% | gold chest |

\* PvE keeps the native opt-ins: `/pvp` works, and attacking a PvP-flagged player flags the
attacker under the core rule. The module does not block either opt-in and does not grant the XP
bonus for them. PvE also keeps the core's forced PvP flag in an enemy capital (owner decision).

- Modes are free. No item, gold, shop purchase, or GM grant selects a mode. The design sells no
  power; the High Risk chest moves existing gold, it does not generate a reward.
- Overlays are not modes: **Mercenary** is a persistent contract while in War/High Risk;
  **Outlaw** is a timed consequence. A character always has exactly one mode.

### 2. State machine

```text
                    .pledge warmode (capital)
        PvE  -------------------------------------->  War Mode
         ^  <--------------------------------------    |
         |      .pledge pve (capital)                 |  .pledge highrisk
         |                                            v
         +---------------------------------------  High Risk
              .pledge pve / warmode (capital)

War/High Risk --.pledge mercenary (capital, level 15+)--> Mercenary
Mercenary     --.pledge warmode / highrisk------------> War / High Risk (contract kept)
Mercenary     --.pledge pve---------------------------> REFUSED (renounce first)
Mercenary     --.pledge renounce (rested area)--------> no contract

Own-faction player kill (open world) --> Outlaw timer: first 5 min, +5 min per kill, cap 60 min
Outlaw --timer expiry----------------> cleared (the only exit in v1)
```

| From | Action | To | Requirements | Refusal result |
|------|--------|----|--------------|----------------|
| PvE | `.pledge warmode` | War | capital, alive, out of combat, no cooldown | chat reason, no change |
| PvE | `.pledge highrisk` | High Risk | same as War | chat reason, no change |
| War | `.pledge highrisk` | High Risk | same as War | chat reason, no change |
| High Risk | `.pledge warmode` | War | same as War | chat reason, no change |
| War/High Risk | `.pledge pve` | PvE | same as War, flag clears on core timer | chat reason, no change |
| War/High Risk | `.pledge mercenary` | Mercenary | capital, level 15+, no cooldown | chat reason, no change |
| Mercenary | `.pledge warmode` | War | capital, no cooldown, contract kept | chat reason, no change |
| Mercenary | `.pledge highrisk` | High Risk | capital, no cooldown, contract kept | chat reason, no change |
| Mercenary | `.pledge pve` | unchanged | renounce first | chat reason, no change |
| Mercenary | `.pledge renounce` | no contract | rested, out of combat, no instance/BG/arena, no Outlaw | chat reason |
| any | `.pledge <same mode>` | unchanged | mode already set | informational message |
| Outlaw | any pledge change | unchanged | Outlaw active | chat reason, no change |

- The Outlaw timer has no early-removal row. Death, guard kill, NPC kill, environment death,
  faction change, logout, sanctuary, instance, BG, arena and duel do not clear it.

### 3. Toggle contract

- `.pledge` is a player command gated by an RBAC permission in the project range, granted to the
  Player Commands role. The `command` row and the permission row ship in the implementing slice; the
  command index is regenerated in the same change.
- **Capital** means one of ten named areas, checked with `Player::GetZoneId()` and the player's
  faction (revised 2026-11-26, see [ADR-033](../../decisions/ADR-033-pvp-rulesets.md)): Stormwind,
  Ironforge, Darnassus, The Exodar, Orgrimmar, Undercity, Thunder Bluff, Silvermoon, plus Shattrath
  and Dalaran for both factions.
  `AREA_FLAG_CAPITAL` is **not** used, and the reason is measured: 35 rows carry it, but only ten of
  them are zone-level rows and they are exactly the list above. The flag is wider than the design,
  so the list is explicit. The flag is not a proxy for "capital city" at zone granularity.
- **Rested area** means `PLAYER_FLAGS_RESTING`, which inns, capitals and faction rest zones set.
- Refused while: dead, in combat, in an instance/BG/arena/battlefield, Outlaw active, cooldown active,
  config disabled, or (for mercenary) below level 15.
- A 5-minute cooldown starts on every accepted mode or contract change, persisted in
  `last_toggle`, so a relog cannot bypass it.
- Downgrading does not clear the PvP flag immediately. The module clears `PLAYER_FLAGS_IN_PVP`,
  stops re-asserting the flag, and starts the core's 5-minute out-of-combat timer, so a player
  cannot escape a fight by toggling.
- **`/pvp`:** allowed in PvE (native opt-in), refused in War/High Risk and while Outlaw. This
  preserves the native PvE opt-in instead of removing it.
- Duels, battlegrounds and arenas ignore the mode toggles and keep their own rules.

### 4. Flags and auras

The database row is the truth for the mode, the contract and the Outlaw deadline. The visible aura
is a carrier, not the state.

| State | Server state | Visible carrier |
|-------|--------------|-----------------|
| PvE | none | none |
| War Mode | `UNIT_BYTE2_FLAG_PVP` + `PLAYER_FLAGS_IN_PVP` | stock aura, chat |
| High Risk | same as War | stock aura, chat |
| Mercenary | `UNIT_BYTE2_FLAG_FFA_PVP` | stock aura, chat |
| Outlaw | `PLAYER_FLAGS_CONTESTED_PVP` + `UNIT_BYTE2_FLAG_PVP` + `PLAYER_FLAGS_IN_PVP` + aura | stock debuff, chat |

- The table lists module-owned state only; core flags from enemy capitals, battlegrounds, duels and
  quests are separate.
- War/High Risk re-assert `SetPvP(true)` on login, zone change, resurrection, and an unexpected
  `OnPlayerPVPFlagChange(false)` while the mode is active. The module never clears a flag owned by a
  battleground, arena, duel, hostile area, or quest.
- Mercenary re-asserts the FFA byte flag on login, zone change, resurrection, and a core clear while
  the contract is active, **except** in `pvpInfo.IsInNoPvPArea` (which includes non-sanctuary
  capitals), `IsInSanctuary()`, a battleground, an arena, an instance or a duel. This suppresses
  own-faction attacks in cities, not only in sanctuaries.
- Outlaw applies the contested-PvP flag, keeps `SetPvP(true)` and `PLAYER_FLAGS_IN_PVP` asserted for
  the whole duration, and carries an aura for display and timing. It does **not** carry
  `UNIT_STATE_ATTACK_PLAYER`: that state makes the core's assisting rule in `Spell.cpp` flag a
  friendly healer or buffer, which would break the grouping contract. The contested flag alone is
  what makes contested guards hostile.
- The Outlaw deadline is `mod_pvp_rulesets_state.outlaw_until`. The 1-second aura tick re-asserts
  the contested and PvP flags if a core timer or auras clear them, except for the contested flag in
  an instance, BG, arena, duel or sanctuary, and expires the state at the deadline. It never
  refreshes the duration while in combat; the 5/+5/60 rule is the only clock.
- On death the aura may be removed; the deadline is durable. `OnPlayerResurrect` re-applies the
  aura, contested flag and PvP flag if `outlaw_until` is still in the future. Death, release and
  resurrection never shorten the timer.
- On expiry: clear the aura and `ResetContestedPvP()`. Clear the Outlaw-owned `PLAYER_FLAGS_IN_PVP`
  and PvP flag unless a battleground, arena, duel or hostile area owns them; let the core manage
  those. If the player is War/High Risk, re-assert the mode flag. A PvE player drops the Outlaw
  flag; a native `/pvp` opt-in held before Outlaw is not restored. The player can re-enable `/pvp`
  in PvE. This is the documented expiry behavior.
- The visible carrier must be a stock, undispellable, mechanic-free client spell; exact IDs are
  chosen at implementation. A dedicated icon and tooltip need the client-patch pipeline.
- **GM mode is outside the contract.** There is no `SetGameMaster` script hook; the module does not
  claim to suspend, re-apply or log on `.gm on`/`.gm off`. Event handlers skip a character where
  `IsGameMaster()` is true, and GM testing uses a normal character. No GM seam is added; the fourth
  approved seam is the guard fallback in section 10.

### 5. XP bonus

- Applied in `OnPlayerGiveXP`, the one hook that covers kill, quest, quest-DF, explore and BG XP:
  `amount = amount * (1 + percent / 100)`, truncated to an integer.
- Percentages: War Mode 10, High Risk 15. Config knobs.
- **Outdoor only, not configurable in v1.** No bonus when `Map::IsDungeon()` is true, or
  `InBattleground()`, `InArena()`, in a battlefield zone (Wintergrasp), in
  `pvpInfo.IsInNoPvPArea` (capitals), or in `IsInSanctuary()`. This excludes capital quest turn-ins,
  so a player cannot bank the mode bonus with zero exposure. The owner requires outdoor-only; there
  is no `OpenWorldOnly` switch.
- Applied after the global rate (`Rate.XP.*`) and multiplicatively with other percentage bonuses such
  as Ancestral Wisdom. Hook order can change the result by ±1 XP; accepted.
- No bonus while in a duel (no XP is granted) or while dead (no XP is granted).

### 6. High Risk death and the chest

**V1 is gold-only (owner confirmed).** Item loss is out of v1. The stock `LootItem` /
`StoreLootItem` path re-creates an item from `itemid` and `randomPropertyId`; it cannot preserve
gems, durability, enchantments, charges or an exact instance snapshot. Shipping item transfer on
that path would be a dupe or a loss. Items return only with the exact-snapshot design described at
the end of this section.

- Trigger: `UnitScript::OnUnitDeath(victim, killer)`, filtered to a player victim. Resolve the
  killing player from `killer->GetCharmerOrOwnerPlayerOrPlayerItself()`, so a pet or guardian kill
  credits its owner. The victim's mode is High Risk, the victim is PvP-flagged, and the killer is a
  player, passes the anti-abuse gates in section 15, is not the victim and is not on the same
  account.
- Excluded: any death in an instance, battleground, arena, battlefield or duel, and any death to an
  NPC, guard or environment source.
- **Loss:** `floor(GetMoney() * GoldLossPercent / 100)`, capped by `GoldLossCapCopper` (default 100g).
  No item is touched in v1. If the computed gold is 0 (for example 9 copper carried), no chest is
  created and no gold moves.
- **One runtime chest per death event**, spawned at the victim's death position from the custom
  template. It stores the gold in the module's runtime state, not in a stock `Loot` object. Order:
  create the chest and runtime state, remove the gold from the victim once, then arm the timer. If
  the chest cannot be created, no gold is removed. If the removal fails, delete the chest and state.
  The runtime state is the only holder after removal; the GO's `Loot` is empty.
- **No stock loot window.** The chest is claimed by a `GameObjectScript` use gate; the script never
  calls `Player::SendLoot` and never creates a `Loot`/`LootItem`. The stock window's
  `ALL_PERMISSION`, `rollWinnerGUID` and `LootItemInSlot` behavior is not part of the path. The
  script checks the runtime owner and pays directly.
- **Ownership state machine:**

```text
  create chest + runtime state
      |
      v
  KILLER_CLAIM (0 .. GraceSeconds, default 300)
      |  killer uses the chest
      |      -> pay gold to killer, delete chest, erase state
      |
      |  grace ends with no use
      v
  VICTIM_RECOVERY (GraceSeconds .. GraceSeconds + RecoverySeconds, default 600)
      |  victim uses the chest
      |      -> pay gold to victim, delete chest, erase state
      |
      |  recovery ends
      v
  DESPAWN (delete chest, erase state, gold lost)
```

- The killer has first claim. Only the killer can use the chest during `KILLER_CLAIM`; group members
  cannot. The victim has recovery only after the grace period. The first successful use deletes the
  chest, so there is no partial-claim state.
- The victim must resurrect and travel to the chest. A ghost cannot use it. The recovery window is a
  playtest knob and must be long enough for a normal corpse run.
- **Direct payment:** the script checks the owner and the available gold space, then removes the
  runtime state (marking the claim) **before** calling `ModifyMoney(+gold)`, then deletes the chest.
  A second use after the state is gone is refused, so a failed delete cannot pay twice; an orphan
  chest without runtime state is refused and deleted. If the player cannot receive the full amount
  (gold cap), the state is kept and the message explains why, so the gold is not destroyed.
- **No mail, no second container, no refund.** One chest, one owner at a time, one lifetime. There
  is no item path and no mail fallback.
- **Logout/disconnect:** the chest persists while the server runs. Owner GUIDs are in runtime state.
  If the killer returns within the grace, the claim is still theirs; otherwise victim recovery
  starts. If both are offline, the timers still run and the chest despawns.
- **Server restart/crash:** the chest is runtime-only and disappears. Remaining gold is lost. This
  is the anti-dupe rule: loss is accepted, duplication is not. A map unload has the same effect; the
  stale runtime entry is dropped and the chest is never recreated.
- **Invalid location:** if the death position is on a transport/vehicle, in water/lava/void, or
  otherwise cannot hold the chest, no chest is created and the victim keeps the gold. A container
  that cannot be placed is never faked at another location.
- **Second death:** a new death creates a new chest for the new loss; containers are never merged
  and never recreated for an old death.
- **Template plan:** `data/sql/custom/db_world/pvp_rulesets.sql` creates the custom
  `gameobject_template` row (project GameObject range) with `type=3` (chest), a stock chest
  `displayId`, `ScriptName=go_pvp_rulesets_chest`, `lootId=0`, `chestRestockTime=0`,
  `groupLootRules=1` and `consumable=1`. The per-entry `gameobject_template_addon` row for the same
  entry carries default `faction`/`flags`, `mingold=0`, `maxgold=0` and zero `artkit0..3`.
  `gameobject_addon` is per-spawn
  (`guid`, rotations, invisibility) and has no gold columns, so no row belongs there.
  `lootId=0` and zero template-addon gold stop `SendLoot` from clearing/filling/regenerating.
  The world SQL is re-appliable: `DELETE` + `INSERT`/`REPLACE` for both rows, like the characters
  SQL. The chest's gold is in module state, not the GO's `Loot`, so even a stock-window bypass has
  nothing to show. The chest is spawned at runtime; there is no DB spawn row.
- **Use and direct-loot gate:** the script returns true for every use, owner or not, so the use
  path never calls `SendLoot`. A synthetic direct `CMSG_LOOT` is gated by the existing
  `PlayerScript::OnAllowedToLootContainerCheck`: it refuses any player who is not the current
  runtime owner. Even a bypassed window is empty: `lootId=0`, zero template-addon gold, and the
  gold lives only in module state.
- **No durability loss** is added; the core's normal durability rules still apply.
- **Future item loss (not v1):** if items return, use a module table with an exact snapshot (entry,
  random properties, gems, durability, enchantments, charges, count), remove the victim's item
  first, create the chest row and restore the exact snapshot on any failure. The stock loot window
  cannot preserve gems/durability and must not be used for this.

### 7. Mercenary for Hire

- A persistent `mercenary = 1` state. It requires War or High Risk; downgrading to PvE requires
  renouncing the contract first.
- Level 15 minimum. Accepted only in a capital through `.pledge mercenary`.
- Grants the FFA flag and the right to attack own-faction players who are in War or High Risk, and to
  be attacked by them. PvE-mode own-faction players are never attackable by a mercenary.
- **Owner decision:** the narrow `OnPlayerGetReactionTo` seam is approved. It must return hostile in
  **both directions** for the pair; `Unit.cpp` reads `GetReactionTo` both ways, and a one-way result
  refuses the attack.
- **Client verification gate:** the server seam cannot make the stock 3.3.5 client start an attack
  on a same-faction target it considers friendly. Two same-faction clients must verify the attack
  before the mercenary/Outlaw rows are marked complete. If the client refuses, v1 sets the FFA byte
  on the mercenary and the Outlaw as a client hint; FFA-flagged players are mutually hostile, the
  group check still makes groupmates friendly, and non-FFA same-faction players remain friendly.
  This is a client-visibility fallback, not a new seam. Test rows 11 and 18 are conditional until
  this passes.
- The FFA flag is suppressed in `pvpInfo.IsInNoPvPArea` (non-sanctuary capitals), `IsInSanctuary()`,
  BGs, arenas, instances and duels. Own-faction attacks are an open-world activity.
- Cross-faction grouping stays as ADR-023. A mercenary can group with other mercenaries and with
  non-mercenaries; group membership makes both sides friendly. Two ungrouped mercenaries are hostile
  to each other even in the same faction, which is the intended free-for-all.
- Removal: `.pledge renounce` in any rested area, out of combat, not in an instance/BG/arena, not
  while Outlaw. The FFA flag and the contract clear immediately; the mode stays.
- The contract changes no faction, race, reputation, vendor, quest, guard, or chat behavior by
  itself. Guards become hostile only through Outlaw.

### 8. Outlaw

- Trigger: a player kills an own-faction player in the open world. The killing blow player is the
  only one marked; group members are not.
- **Hunting an Outlaw is exempt:** if the victim is already an Outlaw, the kill does not create or
  extend the killer's Outlaw timer. The hunt must not self-punish. The victim's own timer continues.
- Excluded sources: duels, battlegrounds, arenas, battlefields, and FFA areas (Gurubashi Arena, Dire
  Maul arena). Those are consensual or instanced PvP and never create Outlaw.
- The victim must be a player, not self, not the same account (same-account kills are ignored
  entirely), and PvP-flagged. The killer must be PvP-flagged. Apart from the same-account gate, the
  anti-abuse gates do not stop Outlaw; they stop the High Risk chest.
- **Timer (v1 rule):**
  - first qualifying kill: `outlaw_until = now + InitialMinutes` (5);
  - each further qualifying kill: `outlaw_until = min(max(now, outlaw_until) + PerKillMinutes,
    now + MaxMinutes)` (5 and 60);
  - the remaining time is capped at 60 minutes;
  - the deadline is persisted in `mod_pvp_rulesets_state.outlaw_until` on every extension.
- **No early removal in v1.** The timer is the only exit. Death by a player, a guard, an NPC, the
  environment, or self does not clear it. Faction change does not clear it. Logout, disconnect,
  sanctuary, instance, BG, arena and duel do not clear it. GM mode is outside the contract
  (section 4).
- Effects while active:
  - a debuff carrier aura for the remaining time;
  - `PLAYER_FLAGS_CONTESTED_PVP`, which makes own-faction guards with the contested-guard faction
    flag hostile (section 10);
  - `SetPvP(true)` and `PLAYER_FLAGS_IN_PVP` for the whole duration, so own-faction hunters can
    attack the Outlaw after the core's normal PvP timer would have cleared a flag;
  - blocked city services (section 9);
  - own-faction PvP-flagged players can attack the Outlaw and be attacked back through the reaction
    seam; groupmates are exempt;
  - no `.pledge` changes and no contract renounce.
- The Outlaw does **not** carry `UNIT_STATE_ATTACK_PLAYER`. That state causes the core assisting rule
  in `Spell.cpp` to flag friendly healers and buffers. Guards are hostile from the contested flag
  alone.
- **Suspended in instances, BGs, arenas, duels and sanctuaries:** the contested flag, guards, city
  service block, reaction hunt and live feed are off; the timer and the database deadline keep
  running. Leaving re-applies the effects.
- **PvE in an enemy capital:** the core forced flag wins. A PvE player forced-flagged in an enemy
  capital is PvP-flagged, so an Outlaw can attack them and they can attack the Outlaw. The mercenary
  own-faction rule still requires War/High Risk; the Outlaw reaction rule covers any own-faction
  PvP-flagged player.
- NPC kills do not extend the timer. The old civilian-kill extension is removed.
- The only faction path is the GM `.character changefaction`; there is no paid faction change. There
  is no clear on `OnPlayerUpdateFaction`, which also fires at login, `.gm off` and `.reset`; the
  timer continues.

### 9. City services blocked

The block applies to an Outlaw in any capital city zone, and is suspended in sanctuaries
and duels.

| Service | Gate | Blocked |
|---------|------|---------|
| Vendor buy/sell/repair | `UNIT_NPC_FLAG_VENDOR`, `UNIT_NPC_FLAG_REPAIR` | yes |
| Trainer list and learn | `UNIT_NPC_FLAG_TRAINER` | yes |
| Auctioneer | `UNIT_NPC_FLAG_AUCTIONEER` | yes |
| Banker | `UNIT_NPC_FLAG_BANKER` | yes |
| Innkeeper / hearthstone set | `UNIT_NPC_FLAG_INNKEEPER` | yes |
| Flight master | `UNIT_NPC_FLAG_FLIGHTMASTER` | yes |
| Stable master | `UNIT_NPC_FLAG_STABLEMASTER` | yes |
| Tabard designer, petitioner, barber | matching NPC flags | yes |
| Mailbox (NPC or gameobject) | `UNIT_NPC_FLAG_MAILBOX`, `GAMEOBJECT_TYPE_MAILBOX` | yes |
| Guild vault | guild vault gameobject | yes |
| Spirit healer | `UNIT_NPC_FLAG_SPIRITHEALER` | no |
| Quest giver | `UNIT_NPC_FLAG_QUESTGIVER` | no |
| Battlemaster | `UNIT_NPC_FLAG_BATTLEMASTER` | no |

- Enforcement is one server-side seam in `Player::GetNPCIfCanInteractWith` and
  `Player::GetGameObjectIfCanInteractWith`, called through a new `PlayerScript` hook. Returning
  false makes every existing handler refuse with its standard error.
- **The exception is mask-scoped, not creature-wide.** The hook decides on the requested
  `npcflagmask`:
  - `UNIT_NPC_FLAG_NONE`: allow only when the creature has `QUESTGIVER` (quest hello); a pure
    vendor/banker/etc. gossip is refused.
  - Exactly `QUESTGIVER`, `SPIRITHEALER` or `BATTLEMASTER`: allow.
  - Any mask that intersects a blocked service flag: refuse, even if the creature also carries an
    allowed flag.
  - Other masks: refuse; no service is silently allowed.
- A combined questgiver/vendor creature can open the quest gossip through `NONE`; the vendor option
  and every vendor/trainer/mail/auction handler still refuse. The gossip handler must not bypass
  those handlers: defense in depth is the same mask check on the service handler, not a creature
  blanket allow.
- First refusal sends one chat line, rate-limited to once per 5 seconds per player. Later refusals
  are silent.
- The spirit healer stays available so an Outlaw can never be soft-locked. Quest givers stay
  available so the state cannot block progression. Battlemasters stay available; queueing is PvP,
  not a city convenience.

### 10. Guard hostility

- Outlaw uses the native contested-PvP mechanism: `PLAYER_FLAGS_CONTESTED_PVP` plus a faction
  template carrying `FACTION_TEMPLATE_FLAG_ATTACK_PVP_ACTIVE_PLAYERS`. `GetFactionReactionTo`
  returns hostile, the guard's normal aggro and combat run, and no creature data is changed.
- No faction swap, no reputation edit, no per-guard script, no `UNIT_STATE_ATTACK_PLAYER`.
- Enemy-faction guards are hostile already. Non-guard city NPCs stay friendly; the service block
  handles them.
- **A guard kill does not clear Outlaw.** The timer is the only exit.
- Where the guard faction carries `FACTION_TEMPLATE_FLAG_ATTACK_PVP_ACTIVE_PLAYERS`, the native
  contested-PvP path is used unchanged.
- **Fourth seam, guard LOS/aggro fallback (owner-approved):** one hook,
  `AllCreatureScript::OnCreatureCanAggroPlayer(Creature* creature, Player* player, bool& canAggro)`,
  with two narrow call sites on the same path:
  `Creature::_IsTargetAcceptable` before the `IsFriendlyTo` rejection, and
  `Unit::_IsValidAttackTarget` for a creature attacker and player target before the friendly-target
  rejection. For a guard in a capital whose guard faction lacks the contested flag, a same-zone
  Outlaw player makes `canAggro = true`; the normal LOS/aggro path starts combat. No timer, no
  per-tick scan. The hook is branch-only: guard check, Outlaw check, zone/capital check, DBC-flag
  check, suspension check; no DB, allocation or aura scan. Where the DBC flag is present the hook
  returns false and the native path runs.
- Sanctuaries suspend guard hostility through the contested-flag suspension.

### 11. Live visibility

- V1 keeps a runtime Outlaw registry: character GUID, `outlaw_until`, zone, subzone and last known
  position. The position is read from the online player on demand; there is **no v1 broadcast
  feed**. `.pledge status` shows the player's own mode, contract and remaining Outlaw time, plus
  the Outlaws currently in the same zone with subzone and last-seen age. This is the v1 surface.
- **Kill alert:** every own-faction kill sends one chat alert to players on the same continent,
  naming killer, victim, zone and subzone. Delivery is one map-scoped `Map::SendToPlayers` packet
  on the continent open-world map, O(players on that map); the open-world map is the continent, not
  a zone. There is no cooldown and no suppression: one message per kill. It is a broadcast, not a
  per-tick scan. own-faction kills are rare enough for the 5-7k-player target.
- **Map feed is deferred to the client patch (section 22).** There is no v1 5-second position
  broadcast with no consumer. The future feed contract is zone-scoped, 5 seconds, hidden in
  instances, BGs, arenas, duels and sanctuaries; it is not implemented until the client can render
  it.
- Players outside the zone see the chat alert and must travel to the zone for the future live
  marker and the v1 `.pledge status` list.
- **No live feed for Outlaws in instances/BGs/arenas/duels/sanctuaries.** The timer still runs. On
  return to the open world, the status list reappears.

### 12. Grouping and assistance

| Pair | Positive spells | Notes |
|------|-----------------|-------|
| Groupmates, any modes | allowed unless the rule below refuses | group check runs before FFA/faction |
| PvE caster, PvP-flagged groupmate in PvP combat | refused | `OnSpellCheckCast`, `SPELL_FAILED_BAD_TARGETS` |
| Same-faction War/High Risk pair | allowed | both already flagged |
| Mercenary + mercenary, grouped | allowed | group check overrides FFA |
| Mercenary + mercenary, ungrouped | refused | hostile through FFA |
| Mercenary + non-mercenary same-faction War/High Risk | refused | hostile through the reaction seam |
| PvE caster, non-flagged groupmate | allowed | no PvP participation |

- The refusal is single-target positive spells: heals, buffs, dispels, resurrection. It fires when
  the target `IsPvP()` and `GetCombatManager().HasPvPCombat()` is true. A flagged but idle groupmate
  can still be healed, and so can a flagged groupmate fighting only NPCs.
- Pre-combat buffs are allowed; the rule is combat-time assistance only. A buff cast before the
  groupmate engages carries into the fight and is an accepted edge case.
- **AoE heals are not filtered.** The core's assisting rule in `Spell.cpp` may flag the PvE caster
  when the healed groupmate is in PvP combat (`UNIT_STATE_ATTACK_PLAYER`). That flag gain is
  documented and accepted; there is no stock-spell DBC filter. The Outlaw does not carry the unit
  state, so an Outlaw groupmate does not flag a PvE healer by itself.
- A PvE player can attack a flagged enemy under the core rule and flags themselves; that is the
  explicit opt-in. The assistance rule is separate and still refuses positive spells on a
  PvP-engaged groupmate.
- Grouping does not change a mode, and leaving a group restores the normal hostility.
- Cross-faction groups keep the ADR-023 behavior.

### 13. Persistence and lifecycle

```text
mod_pvp_rulesets_state
  guid PK, mode, mercenary, last_toggle, outlaw_until

mod_pvp_rulesets_pair
  account_low, account_high, day, kills, last_kill
  PK (account_low, account_high, day)
  KEY idx_pair_high_day (account_high, day)
```

- Tables ship in `data/sql/custom/db_characters/pvp_rulesets.sql`, re-appliable, no foreign keys.
- The pair is normalized to `(min(accountA, accountB), max(accountA, accountB))`. A credited kill in
  either direction updates the same row. The pair is by account, not character, so alt swapping
  does not reset it. It gates the High Risk chest only.
- Load at login: **one state row plus the current day's pair rows** where the account is either
  side. Use two indexed queries (`account_low = ?` via the PK prefix and `account_high = ?` via
  `idx_pair_high_day`), not one OR scan. Cap at `PvpRulesets.AntiAbuse.MaxPairsPerDay` (default 64)
  and prune the oldest at the daily rollover; no account daily row.
- Writes: mode, contract and toggle timestamp on change; `outlaw_until` on every Outlaw extension
  and on expiry; pair rows on a 60-second flush and at logout. No per-kill write other than the
  Outlaw deadline.
- A missing table at runtime is detected with an `information_schema` check at startup. If absent,
  the module logs one `ERROR` and disables itself. It never issues a query against a missing table:
  MySQL errno 1146 aborts the worldserver.
- Logout: mode, contract, `outlaw_until` and the pair rows persist. The Outlaw aura is re-applied at
  login if the deadline is still in the future. The chest is runtime-only; if the server keeps
  running it survives logout, and if the server restarts it is lost.
- Death: the Outlaw timer persists. A High Risk death creates the chest; a non-High-Risk death has
  no chest.
- **Faction change:** no clear. `OnPlayerUpdateFaction` also fires at login, `.gm off` and `.reset`,
  so it is not a faction-change signal. The only faction path is the GM `.character changefaction`;
  the timer continues and applies to the new faction. No paid faction change exists.
- Race change: keep everything.
- Character deletion removes the state row in `OnPlayerDelete`; pair rows stay for the day's cap.
- Config disabled: the module ignores stored modes and `outlaw_until`, applies PvE at next login,
  and keeps the rows for a re-enable.
- Server crash: pair state can lose at most the 60-second flush window; a relog flushes it.
  `outlaw_until` is durable; chests are lost. No duplication path exists.

### 14. Exemptions

| Area | Mode XP | PvP effect | High Risk chest | Outlaw timer | Live status |
|------|---------|------------|-----------------|--------------|----------------|
| Open world | yes | yes | yes | runs/creates | yes |
| Dungeon/raid instance | no | no player PvP | no | runs | no |
| Battleground, arena | no | suspended, BG rules | no | runs | no |
| Wintergrasp/battlefield | no | suspended | no | runs | no |
| Sanctuary (Shattrath, Dalaran) | no | contested flag suspended | no | runs | no |
| Duel | no | duel rules | no | runs | no |
| FFA area (Gurubashi, Dire Maul) | yes | FFA rules | yes, if High Risk | no trigger | yes |
| Enemy capital | no | core forced flag | yes, if High Risk | runs | status only |
| GM mode | no | out of contract | no | out of contract | no |

\* A mercenary's FFA is suppressed in a non-sanctuary capital, so a new Outlaw is not created there
by a mercenary kill. An existing Outlaw in a capital keeps the state. A PvE player forced flagged in
an enemy capital is PvP-flagged and can fight or be fought by the Outlaw.

- Mode XP is also off in a player's own capital or any no-PvP area; the table lists the main cases.
- A PvE-mode player in an FFA area is FFA-flagged by the core and can fight; that is the existing
  consensual world-PvP rule.
- Dead players cannot toggle, cannot be attacked, and cannot use a chest until resurrected.

### 15. Anti-abuse

All gates are server-side, event-time, and O(1). They block the High Risk chest and its gold move,
not the Outlaw timer (except the same-account rule, which ignores the kill entirely).

| Rule | Default | Effect |
|------|---------|--------|
| Same account | always | no Outlaw, no chest, no gold move |
| Same socket peer address | `PvpRulesets.AntiAbuse.SameIp = 1` | no chest; Outlaw still extends |
| Pair cooldown, either direction | 30 min | no chest; Outlaw still extends |
| Credited kills per pair per day | 3 | no chest after the third; Outlaw still extends |
| Gray-level victim | core gray level | no chest; Outlaw still extends |
| Victim flagged continuously | 15 s minimum | no chest; Outlaw still extends |
| NPC or guard kill | always | no chest, no Outlaw |
| Same group | core | groupmates are never hostile, so no kill |

- The same-IP check compares `WorldSession::GetRemoteAddress()` for both online players. It is the
  socket peer, not a database lookup, and the address is never logged. The config key is
  `PvpRulesets.AntiAbuse.SameIp`.
- Track `pvpFlagSince` on `OnPlayerPVPFlagChange(true)`; logging in while flagged starts the clock at
  login. A flag drop clears it. The 15-second gate reads this value.
- NAT and shared connections are a known false positive. The players keep the Outlaw state but get
  no chest. For the two-client local test, `PvpRulesets.AntiAbuse.SameIp = 0` is the documented
  exception; production keeps it at 1.
- The pair table is keyed by account, so deleting or swapping characters does not reset it. Cap and
  prune per section 13.
- Anti-abuse state is memory-first and flushed; a relog flushes it, a crash can lose at most the
  60-second window. Neither can reset it beyond that.
- No per-kill INFO log for a kill that changes nothing. An Outlaw extension, a chest creation, a
  claim, a recovery or an expiry logs one line. Rejections are `DEBUG`; there is no player-facing
  spam.

### 16. Implementation surface

- New tracked module `modules/mod-pvp-rulesets`, following the local module layout:
  `src/`, `conf/PvpRulesets.conf.dist`, `README.md`, `CMakeLists.txt`.
- Config is read once at startup with `sConfigMgr->GetOption<T>` and cached. No per-call reads.
- Event hooks used: `PlayerScript::OnPlayerLogin`, `OnPlayerLogout`, `OnPlayerUpdateZone`,
  `OnPlayerPVPFlagChange`, `OnPlayerFfaPvpStateUpdate`, `OnPlayerResurrect`, `OnPlayerGiveXP`,
  `OnPlayerCreatureKill`, `OnPlayerDelete`; `UnitScript::OnUnitDeath` for every PvP death (player,
  pet or guardian kill) and guard kill; `AllSpellScript::OnSpellCheckCast` for the assistance rule;
  the chest `GameObjectScript` use gate; and the `.pledge` command handler. `OnPlayerUpdateFaction`
  is **not** used for a clear.
- **Chest script:** a `GameObjectScript` registered as `go_pvp_rulesets_chest` and bound through the
  template's `ScriptName`. `OnGossipHello` checks the runtime owner, pays the gold directly and
  deletes the chest, and returns true for every use, owner or not, so the use path never calls
  `SendLoot`. A direct `CMSG_LOOT` is refused for non-owners by
  `PlayerScript::OnAllowedToLootContainerCheck`; any bypassed window is empty. An unknown runtime
  state refuses and deletes the chest; a GM-spawned orphan is not a generic chest.
- **Core seam 1, interaction gate:** `PlayerScript::OnPlayerCanInteractWithNpc` and
  `OnPlayerCanInteractWithGameObject` called at the end of the two `Get*IfCanInteractWith` functions.
  The NPC side uses the requested mask with the section 9 rules, not a creature-wide allow.
  `GetGameObjectIfCanInteractWith` is `const`, so the hook takes a `Player const*` or the seam uses a
  local `const_cast`; keep the hook const-correct.
- **Core seam 2, PvP toggle gate:** `PlayerScript::OnPlayerCanTogglePvP` called at the top of
  `WorldSession::HandleTogglePvP`. Returns false in War/High Risk and while Outlaw; PvE otherwise
  keeps the native `/pvp` opt-in. Three lines.
- **Core seam 3, reaction override:** `PlayerScript::OnPlayerGetReactionTo` called in
  `Unit::GetReactionTo` after the group check and before the FFA check. It returns hostile in both
  directions for:
  - a mercenary and an own-faction War/High Risk target, outside `pvpInfo.IsInNoPvPArea`,
    `IsInSanctuary()`, BG, arena, instance and duel;
  - an Outlaw and an own-faction PvP-flagged player, outside `IsInSanctuary()`, BG, arena, instance
    and duel. Capitals are allowed for Outlaw hunting.
  It is branch-only: no DB, no allocation, no aura scan.
- **Core seam 4, guard LOS/aggro fallback:** one hook,
  `AllCreatureScript::OnCreatureCanAggroPlayer`, called in `Creature::_IsTargetAcceptable` before the
  `IsFriendlyTo` rejection and in `Unit::_IsValidAttackTarget` for a creature attacker and player
  target before the friendly-target rejection. It returns true only for a guard in a capital whose
  guard faction lacks `FACTION_TEMPLATE_FLAG_ATTACK_PVP_ACTIVE_PLAYERS`, against a same-zone Outlaw,
  outside sanctuary/instance/BG/arena/duel. The normal LOS/aggro path starts combat. It is
  branch-only and const-correct (both methods are const; use const hooks or local `const_cast`).
- **Client verification gate:** the same-faction attack test in section 7 must pass before the
  mercenary/Outlaw attack is marked complete. If it fails, the FFA byte fallback is required.
- **GM mode:** no `SetGameMaster` hook. Handlers check `IsGameMaster()` and skip; there is no
  automatic re-apply claim after `.gm off`.
- The mode, contract, Outlaw deadline and pair state are not derived from client data. No packet can
  set them. `.pledge` validates the player's own object state.
- IDs (chest GameObject, spell carrier, RBAC command) are allocated in the implementing change and
  recorded in [runbook/database/id-registry.md](../../runbook/database/id-registry.md).
- SQL: `data/sql/custom/db_characters/pvp_rulesets.sql` for the two tables;
  `data/sql/custom/db_world/pvp_rulesets.sql` for the chest template and its
  `gameobject_template_addon` row. Both files are re-appliable (`DELETE` + `INSERT`/`REPLACE`).

### 17. Performance

- Event-driven only. No `Map::DoForAllPlayers`, no per-tick loop over online players, no grid scans.
- The Outlaw aura ticks once per second for Outlaw characters only. It re-asserts flags and checks
  the deadline. There is **no v1 position broadcast**; `.pledge status` reads the registry on
  demand. The guard hook sits on the `_IsTargetAcceptable` hot path but is branch-only: guard,
  Outlaw, capital, DBC flag, suspension; no DB, allocation or aura scan.
- The kill alert is one map-scoped `Map::SendToPlayers` packet per kill on the continent open-world
  map, O(players on that map); `Map::SendToPlayers` is map-scoped and the open-world map is the
  continent. There is no cooldown or suppression; no per-tick scan.
- The chest timer is one 1-second check over active chests only, not over players. It is bounded by
  concurrent High Risk deaths and each chest is removed on use/despawn.
- Database: one state row plus the current-day pair rows at login; writes on a mode/contract change,
  an Outlaw extension/expiry, the 60-second pair flush, and logout. No per-kill write other than the
  Outlaw deadline.
- No pathfinding, line-of-sight, spell scan, or item scan. The chest is gold-only.
- Flag re-assertion is event-driven. There is no periodic "am I flagged" sweep over all players.

### 18. Security

- The server owns the mode. A client cannot send a mode, a flag, an Outlaw deadline or a chest
  ownership; the only input is `.pledge`.
- Every command validates location, combat, death, instance/BG/arena, level, cooldown and Outlaw
  state against server objects. Argument strings are parsed against a fixed table.
- All SQL uses `PreparedStatement`. The schema has no user-supplied keys.
- **Chest ownership is server-side and the stock loot window is not used.** The `GameObjectScript`
  checks the runtime owner before paying and returns true for every use; a non-owner gets no payment.
  A direct `CMSG_LOOT` is refused by `OnAllowedToLootContainerCheck`, and any bypassed window is
  empty. No `SendLoot`, no `Loot`, no `LootItem`, no `rollWinnerGUID` and no
  `OnPlayerBeforeLootMoney` are part of the path.
- Gold is paid directly with `ModifyMoney` after the owner and capacity checks. The runtime state is
  removed before payment, so a failed delete cannot pay twice; an orphan chest is refused. A failed
  capacity check keeps the chest; after the state transition a failure cannot duplicate the gold.
  There is no mail, no second container and no item path.
- A server restart loses the runtime chest and never duplicates it. This is the deliberate
  anti-dupe trade: loss is accepted, duplication is not.
- The same-IP check uses the socket peer and never writes the address to a log or a table.
- RBAC gates `.pledge`. Player commands are not GM actions and do not write `gm_audit_log`. GM mode
  is out of contract; the module skips GM characters.
- The anti-abuse rules limit collusion, not a modified client. A VPN can evade the IP check; that is
  accepted residual risk. Gold selection is server-side and cannot be steered by a packet.
- No secrets, no connection strings, no player data beyond character names and GUIDs in logs.

### 19. Observability

- Startup: one `INFO` line with enabled state, `GameType`, XP percentages and gold cap. One `ERROR`
  and disabled state on a wrong `GameType`, a missing table, or a bad config value.
- `INFO` on an accepted mode change, contract change, Outlaw create/extension/expiry, chest
  create/claim/recovery/despawn (gold amount), and each delivered kill alert.
- `DEBUG` on an anti-abuse rejection and the first service refusal per 5 seconds.
- No per-kill `INFO` spam and no per-kill database write beyond the Outlaw deadline.
- Support reads the two tables plus the runtime Outlaw/chest registries; `.pledge status` is the
  player view.

### 20. Test plan

**Tiers:** T0 docs (link check, reviewer); T1 SQL lint when the custom SQL lands; T2 C++ (codestyle,
cppcheck, `-Werror` build, unit tests); T3 two-client manual checklist.

**Unit tests (T2, pure logic, no world):** mode parse and validation; toggle guards; Outlaw timer
math (5/+5/cap 60); Outlaw-hunt exemption; anti-abuse predicates (same account, same IP, pair
cooldown, daily cap, gray level, flagged time); gold percentage and cap math; XP percentage and
location gate; one alert per own-faction kill.

**Two-client setup:** local realm, `GameType = 0`, `PvpRulesets.Enable = 1`, two accounts and two
clients, one Alliance character and one Horde character at level 80, one level 10 alt, and one
same-faction partner. Set `PvpRulesets.AntiAbuse.SameIp = 0` for the functional pass because both
clients share one machine, then set it to 1 for the anti-abuse pass. Never ship the local exception.

| # | Scenario | Expected |
|---|----------|----------|
| 1 | `.pledge warmode` in Stormwind | flag on, `.pledge status` reports War, +10% outdoor XP |
| 2 | same toggle in Elwynn, in combat, dead, on cooldown | each refused with a chat reason, no change |
| 3 | `/pvp` in PvE and in War | allowed in PvE, refused in War |
| 4 | relog and reconnect | mode, flag, contract and `outlaw_until` persist |
| 5 | enemy kills a War victim | no chest, no money move |
| 6 | enemy kills a High Risk victim | one chest with 10% gold (capped); no item move |
| 7 | killer does not use the chest until grace ends | victim can claim the gold |
| 8 | non-owner uses the chest | refused, no payment, no loot response; chest remains |
| 9 | owner uses the chest | gold paid once, chest deleted, no loot window, no second claim |
| 10 | High Risk death in a duel, instance, BG, arena | no chest (BG/arena noted below) |
| 11 | mercenary at level 15 attacks own-faction War target | **gate:** client must send; FFA fallback |
| 12 | mercenary kills own faction | Outlaw 5 minutes, contested flag, guards hostile |
| 13 | further own-faction kills | +5 minutes each, capped at 60 |
| 14 | Outlaw dies to a player, a guard and fall damage | state persists in all three cases |
| 15 | Outlaw waits out the timer | aura, guard hostility and service block clear |
| 16 | Outlaw stands near a capital guard | guard attacks; vendor, trainer, bank, AH, mail, flight refused |
| 17 | Outlaw uses spirit healer, quest giver, battlemaster | allowed; a combined vendor still refuses the vendor |
| 18 | own-faction PvP-flagged hunter attacks an Outlaw | **gate:** hostile both ways; no create/extend Outlaw |
| 19 | own-faction kill alert | names killer, victim, zone and subzone; same continent only |
| 20 | rapid own-faction kills | one chat alert per kill; no cooldown or suppression |
| 21 | live position feed | deferred to the client patch; code-review-only, no v1 send |
| 22 | PvE heals a War groupmate in PvP combat | refused; idle or fighting an NPC it lands |
| 23 | PvE AoE heals a groupmate in PvP combat | lands; the caster may gain the PvP flag |
| 24 | mercenary + non-mercenary same-faction War pair | hostile; positive spells refused |
| 25 | mixed-mode group enters a dungeon | no PvP, no XP bonus, no chest |
| 26 | capitals: pledge and guards | **gate:** `AREA_FLAG_CAPITAL` and guard flag recorded; missing -> row 35 |
| 27 | pair cooldown or 3/day cap, across relog | no chest; Outlaw still extends |
| 28 | same IP, gray victim, short flagged time | no chest; Outlaw still extends |
| 29 | server restart with an active chest | chest lost, no duplication |
| 30 | `PvpRulesets.Enable = 0` and relog | PvE enforced, no flags, tables intact |
| 31 | GM `.character changefaction` on an Outlaw | timer continues, no clear |
| 32 | logs after the run | no `ERROR`; no per-kill DB writes beyond the Outlaw deadline |
| 33 | Outlaw expiry with a pre-Outlaw `/pvp` | expires; `/pvp` can be re-enabled in PvE |
| 34 | chest template | `lootId=0`, restock 0, groupLootRules 1, consumable 1, template-addon gold 0, script bound |
| 35 | test guard without the DBC flag | guard aggros an Outlaw via the fourth seam; native path unchanged |
| 36 | victim with under 10 copper | no chest, no loss |

**Known test limits:** the 3.3.5 client on this rig cannot join a battleground with two local
clients (status memory, 2026-11-21). Row 10 (BG/arena death) and row 21 (deferred feed) are verified
by code review and a future multi-client run; the instance and duel parts of row 10 are testable
now. Rows 11 and 18 are gated on the same-faction client attack test; they are not unconditional.
The per-capital gate in row 26 must be recorded for Stormwind, Ironforge, Darnassus, Exodar,
Orgrimmar, Thunder Bluff, Undercity,
Silvermoon, Shattrath and Dalaran.

### 21. Config contract

The module ships `conf/PvpRulesets.conf.dist` with these proposed defaults. They are playtest knobs,
not accepted balance values:

```ini
PvpRulesets.Enable = 0
PvpRulesets.WarMode.XpBonusPercent = 10
PvpRulesets.HighRisk.XpBonusPercent = 15
PvpRulesets.ToggleCooldownMinutes = 5
PvpRulesets.Mercenary.MinLevel = 15
PvpRulesets.Outlaw.InitialMinutes = 5
PvpRulesets.Outlaw.PerKillMinutes = 5
PvpRulesets.Outlaw.MaxMinutes = 60
PvpRulesets.HighRisk.GoldLossPercent = 10
PvpRulesets.HighRisk.GoldLossCapCopper = 1000000
PvpRulesets.HighRisk.Chest.GraceSeconds = 300
PvpRulesets.HighRisk.Chest.RecoverySeconds = 600
PvpRulesets.AntiAbuse.SameIp = 1
PvpRulesets.AntiAbuse.PairCooldownMinutes = 30
PvpRulesets.AntiAbuse.PairDailyKills = 3
PvpRulesets.AntiAbuse.MaxPairsPerDay = 64
PvpRulesets.AntiAbuse.MinFlaggedSeconds = 15
```

One gold is 10,000 copper: `1000000` is 100g. XP is outdoor-only and not configurable in v1.
`Enable = 0` is the shipping default until the ADR is accepted. The config is not live
configuration; it is the contract the implementing slice must provide.

### 22. Client-patch follow-up

The server contract is not the visual contract. Stock carrier spells, chat and `.pledge status` are
the v1 surface. A client patch is required later for:

- **Map pins (not implemented):** the live Outlaw marker. The general POI layer and its `SMPOI`
  Outlaw protocol were withdrawn on 2026-11-27 (ADR-032 → ADR-037); only world bosses and custom
  services ship. A future Outlaw marker needs a new decision, a new client contract and a fresh
  map layer; the old zone-scoped 5-second contract is retained here only as the server-side design
  input. The server registry in section 11 is the data source; the map layer is client data. There
  is no v1 broadcast with no consumer.
- **Unit/status visual:** mode and Outlaw state on the unit frame, a visible debuff, correct icons
  and tooltips. Stock carriers show the wrong tooltip and cannot show the remaining time properly.
- **Mode/status display:** a dedicated panel for the current mode, contract and Outlaw timer.
  `.pledge status` is a text stopgap, not a substitute.

Do not claim the feature is visually complete until this patch exists. If the owner wants the map
marker and status display at launch, the client patch is a launch dependency. The 5-second feed is
designed but not sent in v1.

### 23. Out of scope and future

- Item loss in the High Risk chest; v1 is gold-only. A future exact-snapshot design is required
  before any item is moved.
- War Mode materials, Bloodforged, Marks of War, Hidden Caches, and any currency reward.
- The broker NPC content; v1 uses `.pledge`.
- Cross-realm play, rated PvP changes, arena team changes, and Wintergrasp changes.
- Any shop product, paid toggle, or paid reward.
- A durable `specs/pvp-rulesets.md`; that move happens after ADR-033 is accepted.

## Alternatives

- **Separate PvP or War Mode realms.** Splits the population and changes the realm strategy
  ([ADR-018](../../decisions/ADR-018-realm-strategy.md)). Rejected: one realm, opt-in modes.
- **Client `/pvp` toggle as the mode.** Not authoritative and trivially exploitable. Rejected:
  server-owned mode row and server-side flag application.
- **All-in-core implementation.** Merge burden and a large fork diff. Rejected: module plus four
  approved seams.
- **Stock loot window for the chest.** `SendLoot` grants `ALL_PERMISSION`, `rollWinnerGUID` does not
  gate gold, and `LootItem` re-creates items from template data. Rejected: a custom use gate with
  direct gold payment.
- **Item transfer in v1.** Needs an exact snapshot for gems, durability, enchantments and charges.
  Deferred; gold-only v1.
- **Mail fallback for chest contents.** Creates a second delivery path and a dupe surface. Rejected:
  one runtime chest, no mail.
- **Custom spell auras and map marker in v1.** Need the client-patch pipeline. Deferred to the
  client-patch follow-up; stock carriers plus chat in v1.
- **Flat versus multiplicative XP stacking.** Multiplicative is consistent with Ancestral Wisdom and
  simpler to reason about, with a documented ±1 XP rounding tolerance.

## Impact

- **Players:** opt-in risk/reward without a realm split. High Risk death puts gold on the ground, so
  the loss is visible and recoverable, not mailed. Outlaw creates a timed open-world objective
  instead of a permanent flag.
- **Operations:** one new module, two characters tables, one runtime chest, no item path. The v1
  alert is a bounded map-scoped broadcast; there is no position feed until the client patch.
- **Security:** the chest is a custom use-to-claim object with server-side ownership and direct
  payment. No stock loot window, no mail, no item clone. A crash loses the chest and cannot duplicate
  it.
- **Client:** v1 is visually incomplete. The map marker and unit/status visual need the client patch;
  the server registry is ready for it.
- **Verification:** T0 docs now; T2/T3 when the module lands. Same-faction attack rows are gated on
  the client test, and capital flags are checked per capital.

## Open questions

None. The owner resolved the last two on 2026-11-23. These are verification gates only:

- same-faction client attack (FFA fallback if the stock client refuses);
- per-capital `AREA_FLAG_CAPITAL` and guard DBC flag checks;
- Shattrath/Dalaran capital status.

## Decision record

- [ADR-033](../../decisions/ADR-033-pvp-rulesets.md) is **proposed**. The owner decisions are folded
  in: reaction seam approved, enemy-capital forced flag kept, gold-only corpse chest with custom
  claim, Outlaw 5/+5/cap 60 with no early removal, same-zone marker deferred to the client patch,
  continent chat alert, client-patch visual follow-up.
- **Owner confirmed:** v1 High Risk is gold-only; item loss is out of v1 until an exact-snapshot
  design exists. The guard LOS/aggro fallback is the approved fourth seam.
- On acceptance, fold the durable contract into `specs/pvp-rulesets.md`, move this RFC to
  `rfcs/archived/`, and update the indexes. Do not create a durable spec before acceptance.
