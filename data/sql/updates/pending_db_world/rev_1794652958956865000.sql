-- Content audit triage, part 1: SmartAI and spawn fixes.
--
-- Evidence and decisions: runbook/audits/2026-11-14-content-audit.md.
-- Every SmartAI block is rewritten in full (DELETE + INSERT), never a partial UPDATE.

-- C-05: SmartScript skips the roll when chance >= 100, so 101 and 100 behave the same.

DELETE FROM `smart_scripts` WHERE `entryorguid` = 2202 AND `source_type` = 0;
INSERT INTO `smart_scripts` (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`, `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`, `event_param6`, `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`, `target_type`, `target_param1`, `target_param2`, `target_param3`, `target_param4`, `target_x`, `target_y`, `target_z`, `target_o`, `comment`) VALUES
(2202, 0, 0, 0, 2, 0, 100, 1, 10, 15, 500, 1500, 0, 0, 25, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 'Greymist Coastrunner - On Health Percent - Flee');

-- C-06: drop a link to a SmartAI id that does not exist. The action still runs;
-- only the nonexistent chain is removed, so runtime behaviour is unchanged.

DELETE FROM `smart_scripts` WHERE `entryorguid` = 21231 AND `source_type` = 0;
INSERT INTO `smart_scripts` (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`, `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`, `event_param6`, `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`, `target_type`, `target_param1`, `target_param2`, `target_param3`, `target_param4`, `target_x`, `target_y`, `target_z`, `target_o`, `comment`) VALUES
(21231, 0, 0, 0, 0, 0, 100, 0, 5000, 12000, 10000, 15000, 0, 0, 11, 38631, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 'Greyheart Shield-Bearer - In Combat - Cast Avenger''s Shield'),
(21231, 0, 1, 0, 0, 0, 100, 0, 8, 25, 10000, 15000, 0, 0, 11, 38630, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 'Greyheart Shield-Bearer - In Combat - Cast Shield Charge');

-- C-06: drop a link to a SmartAI id that does not exist. The action still runs;
-- only the nonexistent chain is removed, so runtime behaviour is unchanged.

DELETE FROM `smart_scripts` WHERE `entryorguid` = 24043 AND `source_type` = 0;
INSERT INTO `smart_scripts` (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`, `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`, `event_param6`, `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`, `target_type`, `target_param1`, `target_param2`, `target_param3`, `target_param4`, `target_x`, `target_y`, `target_z`, `target_o`, `comment`) VALUES
(24043, 0, 0, 0, 1, 0, 100, 3, 0, 0, 1000, 1000, 0, 0, 11, 42943, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 'Amani Lynx Cub - Out of Combat - Cast ''Stealth'''),
(24043, 0, 1, 0, 4, 0, 100, 512, 0, 0, 0, 0, 0, 0, 28, 42943, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 'Amani Lynx Cub - On Aggro - Remove Aura ''Stealth'''),
(24043, 0, 3, 0, 0, 0, 100, 2, 5000, 5000, 35000, 35000, 0, 0, 11, 43357, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 'Amani Lynx Cub - In Combat - Cast ''Feral Swipe''');

-- C-06: drop a link to a SmartAI id that does not exist. The action still runs;
-- only the nonexistent chain is removed, so runtime behaviour is unchanged.

DELETE FROM `smart_scripts` WHERE `entryorguid` = 30956 AND `source_type` = 0;
INSERT INTO `smart_scripts` (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`, `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`, `event_param6`, `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`, `target_type`, `target_param1`, `target_param2`, `target_param3`, `target_param4`, `target_x`, `target_y`, `target_z`, `target_o`, `comment`) VALUES
(30956, 0, 0, 0, 4, 0, 100, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 'Sapph - On Aggro - Say Line 0'),
(30956, 0, 1, 0, 9, 0, 100, 0, 0, 0, 9000, 13000, 10, 40, 11, 61077, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 'Sapph - Within 10-40 Range - Cast ''Chains of Ice'''),
(30956, 0, 2, 0, 106, 0, 100, 0, 18000, 25000, 18000, 25000, 0, 8, 11, 61058, 1, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 'Sapph - Within 0-8 Range - Cast ''Hungering Cold'''),
(30956, 0, 3, 0, 0, 0, 100, 0, 60000, 120000, 120000, 240000, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 'Sapph - In Combat - Say Line 1'),
(30956, 0, 4, 0, 5, 0, 100, 1, 0, 0, 0, 0, 0, 0, 1, 2, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 'Sapph - On Killed Unit - Say Line 2'),
(30956, 0, 5, 0, 6, 0, 100, 1, 0, 0, 0, 0, 0, 0, 1, 3, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 'Sapph - On Just Died - Say Line 3 (No Repeat)');

-- C-07: these rows were authored but never ran, because the template has no AIName.
-- Activating SmartAI restores the intended behaviour. Each entry was read before the change.
UPDATE `creature_template` SET `AIName` = 'SmartAI' WHERE `entry` IN (10182, 14690, 18703, 21271);
UPDATE `gameobject_template` SET `AIName` = 'SmartGameObjectAI' WHERE `entry` = 201937;

-- C-07: rows shadowed by a C++ ScriptName are inert; removing them changes no runtime behaviour.
DELETE FROM `smart_scripts` WHERE `entryorguid` = 25367 AND `source_type` = 0;
DELETE FROM `smart_scripts` WHERE `entryorguid` = 25744 AND `source_type` = 0;
DELETE FROM `smart_scripts` WHERE `entryorguid` = 190635 AND `source_type` = 1;
DELETE FROM `smart_scripts` WHERE `entryorguid` = 190636 AND `source_type` = 1;

-- C-10: spawnMask 0 means the row never loads on any difficulty. These four are removed with
-- paired guid, id, and mask filters so a re-run can never touch an enabled spawn. guid 131066 is
-- the exception: it is the Ruby Sanctum firewall, restored disabled by the C-10 follow-up file.
DELETE FROM `creature` WHERE `guid` = 152340 AND `id` = 27398 AND `spawnMask` = 0;
DELETE FROM `creature` WHERE `guid` = 152341 AND `id` = 27346 AND `spawnMask` = 0;
DELETE FROM `creature` WHERE `guid` = 152342 AND `id` = 27399 AND `spawnMask` = 0;
DELETE FROM `creature` WHERE `guid` = 152343 AND `id` = 27346 AND `spawnMask` = 0;
