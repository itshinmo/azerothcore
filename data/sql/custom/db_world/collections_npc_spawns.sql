-- Collections: Warpweaver (transmogrifier) spawns in the ten capitals.
-- Module: mod-transmog-plus (ScriptName npc_transmogrifier, entry 910012 per the ID registry).
-- Spawn GUID block 5400001-5400010 is reserved for this file (base MAX(guid) was 5,300,678 at
-- creation; the block sits ~100k above it so upstream spawn updates land well below).
-- Placement (owner decision): next to each capital's auction house — where players gather.
-- Shattrath has no auction house, so its Warpweaver stands at the Lower City bank. Dalaran is
-- the exception: the owner placed it in Simply Enchanting, beside the enchanting trainer, where
-- the transmog playtest happens.
-- Anchors (trade-district NPCs standing at or beside the auction house / bank square; the
-- nearest creature to each crowd point): Stormwind Thurman Mullby 1285, Ironforge Bryllia
-- Ironbrand 5101, Darnassus Ariyell Skyshadow 4203, Exodar Onnis 16732, Orgrimmar Asoran 3350,
-- Undercity Auctioneer Stockton 15675, Thunder Bluff Hogor Thunderhoof 3018, Silvermoon Celana
-- 16619, Shattrath banker L'lura Goldspun 19338. Every NPC sits at +2.5/+2.5 from its anchor
-- (anchor z, 1 dp), so the one orientation 3.9270 faces it. Dalaran uses the Simply Enchanting
-- floor at (5842.8, 721.8, 642.0), beside Enchanter Nalthanis 28693 and the shop sign.
-- Re-applicable: DELETE + INSERT, per data/sql/custom conventions.

SET @Entry = 910012;

-- guid filter required by the SQL linter; the open-ended BETWEEN also sweeps later `.npc add`
-- strays, which take generator guids above this block.
DELETE FROM `creature` WHERE `id` = @Entry AND `guid` BETWEEN 5400001 AND 999999999;
INSERT INTO `creature` (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `equipment_id`,
  `position_x`, `position_y`, `position_z`, `orientation`, `spawntimesecs`, `wander_distance`,
  `currentwaypoint`, `curhealth`, `curmana`, `MovementType`, `npcflag`, `unit_flags`, `dynamicflags`, `VerifiedBuild`)
VALUES
-- Stormwind, Trade District auction house
(5400001, @Entry, 0, 0, 0, 1, 1, 0, -8829.3, 598.9, 95.8, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Ironforge, auction house
(5400002, @Entry, 0, 0, 0, 1, 1, 0, -4959.6, -1021.3, 504, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Darnassus, bank and auction trader
(5400003, @Entry, 1, 0, 0, 1, 1, 0, 9926.8, 2319.0, 1330.9, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- The Exodar, auction house
(5400004, @Entry, 530, 0, 0, 1, 1, 0, -3931.7, -11625.6, -138.4, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Orgrimmar, auction house
(5400005, @Entry, 1, 1637, 0, 1, 1, 0, 1894.1, -4324.3, 23.5, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Undercity, Trade Quarter auction house
(5400006, @Entry, 0, 0, 0, 1, 1, 0, 1581.6, 190.5, -56.8, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Thunder Bluff, auction house
(5400007, @Entry, 1, 0, 0, 1, 1, 0, -1244.6, -60.6, 163, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Silvermoon City, Bazaar auction house
(5400008, @Entry, 530, 0, 0, 1, 1, 0, 9870.2, -7442.9, 13.7, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Shattrath City, Lower City bank (no auction house in this city)
(5400009, @Entry, 530, 0, 0, 1, 1, 0, -2006.6, 5371.1, -9.3, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Dalaran, Simply Enchanting (beside the enchanting trainer and the shop sign)
(5400010, @Entry, 571, 0, 0, 1, 1, 0, 5842.8, 721.8, 642.0, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0);
