-- C-10 follow-up: keep the intentional stop and clean the orphans.
--
-- guid 131066 is the Ruby Sanctum firewall. db_world/2026_07_11_00.sql disabled it on purpose
-- ("stop spawn (intentional)"), so part 1 must not erase that decision. It is restored disabled
-- and waived in tools/dev/content-audit-waivers.json.
--
-- The other four spawnMask = 0 spawns stay deleted. Each delete is paired on guid, id, and the
-- mask, so a re-run after a spawn is re-enabled cannot remove a live NPC. Orphan rows that would
-- make ObjectMgr log at startup are removed too.
DELETE FROM `creature` WHERE `guid` = 131066 AND `id` = 23155;
INSERT INTO `creature` (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `equipment_id`, `position_x`, `position_y`, `position_z`, `orientation`, `spawntimesecs`, `wander_distance`, `currentwaypoint`, `curhealth`, `curmana`, `MovementType`, `npcflag`, `unit_flags`, `dynamicflags`, `ScriptName`, `VerifiedBuild`, `CreateObject`, `Comment`) VALUES
(131066, 23155, 571, 0, 0, 0, 1, 0, 3604.82, 191.464, -113.679, 2.19912, 180, 0, 0, 42, 0, 0, 0, 0, 0, '', 0, 0, 'Ruby Sanctum firewall, intentionally disabled by 2026_07_11_00');

DELETE FROM `game_event_creature` WHERE `guid` IN (152340, 152341, 152342, 152343);
DELETE FROM `creature_addon` WHERE `guid` IN (152340, 152341, 152342, 152343);

DELETE FROM `creature` WHERE `guid` = 152340 AND `id` = 27398 AND `spawnMask` = 0;
DELETE FROM `creature` WHERE `guid` = 152341 AND `id` = 27346 AND `spawnMask` = 0;
DELETE FROM `creature` WHERE `guid` = 152342 AND `id` = 27399 AND `spawnMask` = 0;
DELETE FROM `creature` WHERE `guid` = 152343 AND `id` = 27346 AND `spawnMask` = 0;
