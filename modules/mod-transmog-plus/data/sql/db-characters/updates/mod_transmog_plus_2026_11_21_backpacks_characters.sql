-- Backpacks removal, characters side (ADR-021 revision 2026-11-21): the feature's three
-- characters-DB tables go with the code. The world-side remover (item 27621, world table) lives
-- in data/sql/world/mod_transmog_plus_2026_10_08_backpacks.sql.
DROP TABLE IF EXISTS `mod_transmog_plus_backpack_unlocks`;
DROP TABLE IF EXISTS `mod_transmog_plus_backpack_choice`;
DROP TABLE IF EXISTS `mod_transmog_plus_backpack_mail`;
