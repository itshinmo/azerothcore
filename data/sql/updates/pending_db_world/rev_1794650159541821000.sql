-- Clear a value that is not a script name from creature.ScriptName.
--
-- The three Baron Longshore (3467) spawns were added by db_world/2026_05_18_01.sql with '67511'
-- in the ScriptName column. That is not a registered script name; ObjectMgr::GetScriptId returns 0
-- for unknown names, so the value never bound a script and has no gameplay effect. It is still
-- wrong data and it fails content audit check C-08.
--
-- Filters: id and guid keep the statement lint-clean, ScriptName keeps a later intentional name
-- from being cleared by a re-run.
UPDATE `creature` SET `ScriptName`='' WHERE `id`=3467 AND `guid` IN (15066,15215,15217) AND `ScriptName`='67511';
