-- Collections: Warpweaver (transmogrifier) spawns in the ten capitals.
-- Module: mod-transmog-plus (ScriptName npc_transmogrifier, entry 910012 per the ID registry).
-- Spawn GUID block 5400001-5400010 is reserved for this file (base MAX(guid) was 5,300,678 at
-- creation; the block sits ~100k above it so upstream spawn updates land well below).
-- Anchors are the faction leaders' own spawns (Stormwind 29611, Ironforge 2784, Darnassus 7999,
-- Exodar 17468, Orgrimmar 31412, Undercity 10181, Thunder Bluff 3057, Silvermoon 16802,
-- Shattrath 18166, Dalaran 32681). Every NPC sits at +2.5/+2.5 from its anchor, so the one
-- orientation 3.9270 faces back at it. zoneId matches the anchor rows (0, Orgrimmar 1637).
-- Re-applicable: DELETE + INSERT, per data/sql/custom conventions.

SET @Entry = 910012;

-- guid filter required by the SQL linter; the open-ended BETWEEN also sweeps later `.npc add`
-- strays, which take generator guids above this block.
DELETE FROM `creature` WHERE `id` = @Entry AND `guid` BETWEEN 5400001 AND 999999999;
INSERT INTO `creature` (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `equipment_id`,
  `position_x`, `position_y`, `position_z`, `orientation`, `spawntimesecs`, `wander_distance`,
  `currentwaypoint`, `curhealth`, `curmana`, `MovementType`, `npcflag`, `unit_flags`, `dynamicflags`, `VerifiedBuild`)
VALUES
-- Stormwind (King Varian Wrynn's dais)
(5400001, @Entry, 0, 0, 0, 1, 1, 0, -8438.9, 335.6, 122.7, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Ironforge (King Magni Bronzebeard's throne)
(5400002, @Entry, 0, 0, 0, 1, 1, 0, -4863.2, -1020.2, 505.8, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Darnassus (Tyrande Whisperwind)
(5400003, @Entry, 1, 0, 0, 1, 1, 0, 9665.0, 2527.1, 1360.1, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- The Exodar (Prophet Velen)
(5400004, @Entry, 530, 0, 0, 1, 1, 0, -3991.2, -11411.2, -122.1, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Orgrimmar (Thrall, Grommash Hold)
(5400005, @Entry, 1, 1637, 0, 1, 1, 0, 1916.3, -4125.3, 43.3, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Undercity (Lady Sylvanas Windrunner)
(5400006, @Entry, 0, 0, 0, 1, 1, 0, 1292.9, 318.7, -57.2, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Thunder Bluff (Cairne Bloodhoof)
(5400007, @Entry, 1, 0, 0, 1, 1, 0, -1207.1, -110.2, 163.9, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Silvermoon City (Lor'themar Theron)
(5400008, @Entry, 530, 0, 0, 1, 1, 0, 9993.0, -7050.0, 45.4, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Shattrath City (Khadgar's terrace)
(5400009, @Entry, 530, 0, 0, 1, 1, 0, -1857.4, 5422.6, -10.4, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0),
-- Dalaran (Eventide, near The Magnificent Merleaux)
(5400010, @Entry, 571, 0, 0, 1, 1, 0, 5805.5, 726.7, 641.0, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0);
