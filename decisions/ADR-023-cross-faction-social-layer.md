# ADR-023 — Cross-faction core social layer

- Status: accepted
- Date: 2026-11-20
- Implements: [RFC-003](../rfcs/active/RFC-003-qol-social-slate.md) Group D core (owner scoping decisions of 2026-11-20)

## Decision

The cross-faction social layer is mostly **built into this core** — no new code. Mapping agreed
with the owner (every listed feature confirmed ON):

1. **Config flips** (both `worldserver.conf.dist` and the live config), all previously 0:
   `AllowTwoSide.Interaction.Calendar / Chat / Channel / Group / Guild / Arena / Auction = 1`.
   - **Shared AH**: with `Interaction.Auction` on, every auction house becomes the neutral
     house (`AuctionHouseMgr.cpp`), so both factions bid in one market. Accepted economy cost
     (DBC values): seller cut 5% → 15% and deposit 5% → 25% for every auction (neutral house
     rates), scaled by `Rate.Auction.Cut`/deposit settings.
   - **Groups/raids** across factions gate on `Interaction.Group` (GroupHandler, Group, LFG,
     instance logic all honor it).
   - **Guilds**: invites and charter creation honor `Interaction.Guild` (Guild.cpp).
   - **Arena teams**: cross-faction petitions honor `Interaction.Arena` (PetitionsHandler).
   - **Calendar invites** honor `Interaction.Calendar`.
2. **RBAC grants ship via custom SQL** (`data/sql/custom/db_auth/crossfaction_player_rbac.sql`):
   mail (27, MailHandler), who list (28, SocialMgr), add friend (29, SocialHandler), trade (51,
   TradeHandler) and nearby text-emote delivery (25, Player.cpp) are RBAC-gated in this core with
   no config override. This fork's shipped data gives those permissions to role 194 ("Sec Level
   Moderator", which is why GM accounts appeared to have them) but normal players hold role 195
   ("Sec Level Player"); the SQL links 25, 26, 27, 28, 29 and 51 into 195, idempotently.
   Say/yell deliver cross-faction unconditionally (no gate in the core), whisper needs the chat
   config plus RBAC, and the guild/group/auction/calendar/arena gates run on the configs above.
3. **Same-group PvP suppression is native**: `Unit::GetReactionTo` returns friendly for players
   `IsInRaidWith` each other regardless of faction (the comment explicitly names the Group
   config), and the group check runs before the FFA check — groupmates never fight each other.
   Non-grouped opposite-faction players stay hostile. Wintergrasp and rated BG
   matchmaking stay deferred per RFC-003.
4. **Battlegrounds/arenas queueing** (`modules/mod-cfbg`, vendored from
   azerothcore/mod-cfbg `78771c6d0d9d5fcd80206eaeb9668452adcbf4ee`, MIT): mixed-faction BGs with
   balanced/even team options and optional race morph. `CFBG.Battlefield.Enable` (Wintergrasp)
   turned off in the module conf — RFC-003 defers Wintergrasp. The live module config
   (`env/dist/etc/modules/CFBG.conf`, gitignored, mirrors the dist) exists because the module's
   code defaults would otherwise leave CFBG off. Module SQL (commands + AV creature faction fix)
   self-applies at startup.
5. **Deferred: quest/reputation access** (`gitdalisar/mod-Faction-Free`): unvendorable — it ships
   whole replacement core files (its 2407-line `PlayerUpdates.cpp` vs this fork's diverged
   2515-line one) plus client DBC/MPQ changes, so it cannot be adopted as a module and would
   wipe this fork's customizations. Revisit as its own slice (module-level hooks or data patch)
   only if the owner wants it after the social layer settles.
6. **Deferred per RFC-003 sequencing**: 3v3 solo queue, personal arena teams,
   queue-from-anywhere, currency consolidation — their own slices after the core layer.

## Tests and verification

- `make build` (cfbg module) + `make test`; server restart applies the config flips.
- T3 manual checklist (owner in game):
  1. Alliance and Horde characters: `/say` at each other is readable both ways.
  2. Cross-faction group invite works; in-group PvP is impossible (suppression), out-of-group
     attacks still work.
  3. Cross-faction guild invite/charter works.
  4. Both factions bid in one shared AH (neutral cut applies).
  5. Mail/trade/friends/who across factions work for a **normal player account** (the RBAC
     grants came from `crossfaction_player_rbac.sql`; they were Moderator-only before it).
  6. `mod-cfbg`: mixed-faction BG fill; `.cfbg` command present; Wintergrasp path stays off.
- Rollback note: the 7 config flips are individually reversible in the configs; only
  `Interaction.Channel` leaves residual state if switched off after shared channels were used
  (two same-named channel managers exist until restart).
