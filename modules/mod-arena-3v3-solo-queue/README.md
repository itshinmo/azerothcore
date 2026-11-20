# mod-arena-3v3-solo-queue

3v3 solo arena queue (RFC-003 Group D; see `decisions/ADR-024-pvp-queueing-slice.md`): players
queue rated 3v3 alone with `.qsolo rated` (or the Arena 3v3 Solo NPC template, entry `1000003`);
the matchmaker composes balanced teams (talent-role filtering, separate solo MMR starting at
1500) into temporary personal teams.

- Vendored from `azerothcore/mod-arena-3v3-solo-queue` `5cfecf79ba725db14371ed1d0841546c18e1ce4f`
  (2026-09-29, AGPL-3.0 — attribution retained; upstream repo glue, images, tests and the
  CMake template removed, source/conf/data as shipped).
- Module SQL self-applies at startup: a characters-DB MMR reseed plus the NPC template
  (creature entry `1000003`, template only, spawned nowhere by default — the `.qsolo` command
  path works without any NPC). ID recorded in the repository's ID registry.
- Config: module conf dist ships upstream defaults (Enable=1, code defaults enabled too, so no
  live config needed). `Solo.3v3.MinLevel = 80` gates team creation — endgame bracket only, per
  upstream default.
- Known upstream issue, open: #61 reports a slot-4 out-of-bounds write into the core character
  cache on solo-queue team joins. This fork patches the cache (bounds guards in
  `src/server/game/Cache/CharacterCache.cpp`) instead of relying on an upstream fix; the module's
  visible-field suppression for slot 4 was already present. Re-verify after any upstream update.
