-- C-07 follow-up: per-spawn SmartAI rows for Sunblade Arch Mage (25367).
--
-- The template uses ScriptedAI (ScriptName npc_sunblade_arch_mage) and has no AIName, so rows keyed
-- by -guid are never loaded. Removing them is behaviour-neutral and completes the C-07 cleanup.
DELETE FROM `smart_scripts` WHERE `source_type` = 0 AND `entryorguid` IN (-54835, -54834, -54832, -54829);
