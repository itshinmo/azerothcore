-- Backpacks removal (ADR-021 revision 2026-11-21): the backpacks feature is removed from the
-- module. This file replaces the original backpacks setup: it deletes the unlock item and drops
-- the feature's world table. The characters-side tables (unlock records, chosen backpack,
-- intro-mail log) are dropped by data/sql/db-characters/updates/. The client model files lived
-- in a client patch that is already absent, so nothing client-side is removed here.
DELETE FROM `item_template` WHERE `entry` = 27621;
DROP TABLE IF EXISTS `mod_transmog_plus_backpacks`;
