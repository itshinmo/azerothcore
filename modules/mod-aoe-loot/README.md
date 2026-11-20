# mod-aoe-loot

Area looting (RFC-003 Group C, [ADR-022](../../decisions/ADR-022-aoe-looting.md)): player-toggled
AoE loot — one loot window collects nearby corpses. In groups, the group's loot rules apply to
the window. Items that do not fit the bags can be mailed (`AOELoot.MailEnable`, default off).

- Vendored from `azerothcore/mod-aoe-loot` `957f9a1a686141d96c8b55e9431bfe2a0fb26e46`
  (2026-10-31, official AzerothCore module). License: AGPL-3.0 (LICENSE retained) — modified
  versions stay AGPL; the public repository satisfies the network-source requirement.
- Upstream repo glue removed (`include.sh`, `.github`, dotfiles); source, conf, and `data/sql`
  kept as shipped. The module's SQL self-applies at worldserver startup (module `data/sql/db-*`
  import) — it only seeds the core `module_string` table with the module's messages.
- Player commands: `.aoeloot off/on` per character — **on by default for every character**
  (upstream default). Config: `AOELoot.Enable` (default 1), `AOELoot.Message` (1),
  `AOELoot.Range` (55), `AOELoot.Group` (1), `AOELoot.MailEnable` (0).
- Compiles against this fork without changes (uses `Object::CustomData`, verified present).
- Local divergence (1 line): the shipped `conf/mod_aoe_loot.conf.dist` described
  `AOELoot.Message` as "Enables area loot if the player is in a group" (upstream copy-paste
  from the Group option); corrected to describe the login message.
