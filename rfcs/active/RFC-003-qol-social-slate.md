# RFC-003 — QoL and social slate (Whitemane Tiers 1+2+3 + sweep candidates)

- Status: accepted (implementation gated on the Phase 1 gate release and the owner's go)
- Date: 2026-11-20
- Author: agent session (modernization/realm-cleanup-and-features)
- Decisions: made by the owner on 2026-11-20 (see Decision record below)

## Problem

The owner asked for a reviewable feature slate for the server, drawn from Whitemane, Project
Ascension, and live private servers. Inputs: `.agents/plans/whitemane-research/whitemane-research.ANALYSIS.md`
(gitignored, 2026-11-18) plus a 2026-11-20 four-agent sweep. Players reward convenience and
account-wide progress; they punish custom combat systems (Whitemane custom-features rating 1.7/5)
and pay-to-win. Everything adopted must be free (no subscription gating, no sold power).

## Proposal — first slate, grouped for separate ADRs

**Group A — leveling QoL (server modules, small):**
- ~~Auto-learn class spells at level (module hook on level-up).~~ Withdrawn 2026-11-26; see the
  amendment at the end of this RFC and the
  [ADR-021 revision](../../decisions/ADR-021-leveling-qol-batch-1.md#revision-2026-11-26--auto-learn-class-spells-withdrawn):
  it removed a layer of transaction, and trainers must sell spells again for the planned
  class-trainer shop convenience to have anything to sell.
- Auto flight paths on level-up/login.
- Cheap dual spec (verify core cost config first).
- XP bonus sources, **small-balance rule** (owner decision 2026-11-20): gathering, rare kills, and
  BG wins award a small base XP that then passes through the global 2x rate; **Ancestral Wisdom at
  +10%** XP per max-level character on the account (reduced from Whitemane's 15%). ADR-012 is
  revised accordingly with explicit anti-abuse knobs (small bases, per-day caps where needed,
  values tuned at playtest). Target feel: slow but not too slow.

**Group B — account-wide (RFC-002 covers collections/transmog; here):**
- Account-wide mounts + pets (via mod-account-bound, RFC-002).

**Group C — client-facing (RFC-001 covers visuals/creation):**
- ~~AoE looting (`azerothcore/mod-aoe-loot`, drop-in).~~ Removed (ADR-022, 2026-11-21).

**Group D — social/PvP (owner scope, 2026-11-20):**
- Cross-faction core social layer: groups/raids, chat, trade, AH, battlegrounds, arenas, **plus
  guilds and mail shared across factions**. Hostile factions keep fighting each other, **except
  groupmates never fight each other** (same-group PvP suppression). Wintergrasp and rated BG
  matchmaking stay deferred. Module pieces: `mod-cfbg` (+ enhanced fork) for BGs/arenas,
  `mod-Faction-Free` for quest/rep access; guild/mail/group sharing needs a scoping ADR mapping
  each system to a module or small custom work.
- 3v3 solo queue (`azerothcore/mod-arena-3v3-solo-queue`, stable, separate solo MMR) — Whitemane's
  most popular arena mode.
- Personal arena teams (queue without team creation).
- Queue-from-anywhere chat command (`.join ab` shape, Netherwing).
- Currency consolidation (Justice/Valor, Honor/Conquest, rolling caps) — medium, defer behind
  Group D core.

**Group E — recurring:**
- Weekly event calendar: XP weekend, weekly 3v3 tournament for a cosmetic prize (Twinstar evidence),
  transmog contest after RFC-002 lands.

**Not in this slate (per Whitemane do-not-copy + owner):** custom Heroic raids with new mechanics,
Hardcore, Path of War, Paragon, Domination, Timewalking, Black Market AH, subscription QoL, sold
power. Ascension classless/wildcards recorded as owner-decision material, not proposed here
(`mod-classless-wildcard` exists as a base if ever wanted as an event mode).

Sequencing (post Phase 1 gate, per ADR-019's reading): RFC-002 collections first (owner instruction)
→ Group A batch → ~~AoE loot~~ (removed, ADR-022) → Group D core → E/events → deferred items.

## Alternatives

- Ship nothing until launch: loses the retention/QoL levers that every source says matter most.
- Ship a larger slate including raid/loot QoL (Determination, loot-by-difficulty, personal loot,
  flexible raids — Whitemane Tier 4): owner excluded Tier 4 from this round.

## Impact

- Each group = its own ADR + module + tests + a measurable verification step (house rule).
- ADR-012 revision needed before any XP-bonus feature lands.
- Cross-faction is the only medium-high effort item; everything else is small modules or config.
- Player-facing, so T3 verification (smoke + manual checklist) applies per feature.

## Open questions

Resolved by the owner on 2026-11-20:

1. ~~ADR-012 revision scope~~ → Bonus XP sources stay (gather/rares/BG at a small base × the 2x
   rate; Ancestral Wisdom at +10%). ADR-012 revision drafted at implementation, with anti-abuse
   knobs and playtest tuning.
2. ~~Cross-faction scope~~ → Core social layer **plus shared guilds and mail**; groupmates never
   fight each other; Wintergrasp + rated BGs deferred. Full system matrix in the scoping ADR.
3. ~~Group A order~~ → Agent's choice: auto-learn spells + auto flight paths + cheap dual spec
   batch first, then the XP-balance ADR, then Ancestral Wisdom.
4. ~~Faction-balance perks~~ → **Skipped.** Revisit only if launch population skews hard.

"Free riding skill + first mount at 20" was removed from Group A by owner instruction (2026-11-20).

## Decision record

Owner decisions, 2026-11-20: slate adopted as amended — "free mount at 20" removed; XP bonus
sources kept under the small-balance rule with Ancestral Wisdom at +10%; cross-faction scope =
core social layer + shared guilds + mail + same-group PvP suppression; faction-balance perks
skipped; sequencing per this RFC's Group order. Each group lands as its own ADR + module + tests +
verification. Implementation waits for the Phase 1 gate release and the owner's explicit go.

**Amendment 2026-11-20** (implementation session, [ADR-021](../../decisions/ADR-021-leveling-qol-batch-1.md)):
auto flight paths are **dropped** from Group A — players must discover flight paths (the core
`AllFlightPaths` config stays off). Dual spec is fixed at **level 30, free** (core verified free;
level gate lowered from 40). Auto-learn class ships as `mod-auto-learn-spells`, driven by the core
trainer data instead of a hand-maintained spell list.

**Amendment 2026-11-26**. Auto-learn class spells is **withdrawn**
([ADR-021 revision](../../decisions/ADR-021-leveling-qol-batch-1.md#revision-2026-11-26--auto-learn-class-spells-withdrawn)):
it removed a layer of transaction — spells had no price and no trainer visit — and the planned
class-trainer shop convenience needs trainers to be the sole spell source. `mod-auto-learn-spells`
is deleted; shamans get their totems from the stock class quests again. Dual spec at level 30
free and the dropped auto flight paths are unaffected.

<!-- When accepted, fold the durable content into specs/ or decisions/ and move the RFC to archived/. -->
