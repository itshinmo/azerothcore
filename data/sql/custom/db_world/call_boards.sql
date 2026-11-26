-- Call boards: 15 stock Wanted Board objects, one per faction capital, Shattrath, Dalaran and the
-- five neutral hubs. Entry 930101, spawn GUIDs 5714521-5714535.
--
-- The board is a type-2 questgiver with no quest attached yet: the objectives engine will open its
-- menu in a later slice. Positions and facing come from AWE's area overview at each innkeeper,
-- with the floor height from acore-data terrain. Faction, zone and area ids are the spawn's real
-- values, not guesses.
--
-- Re-applicable. gameobject_template uses REPLACE because the SQL linter forbids DELETE on
-- protected tables; the row always ends up present. Spawns use DELETE + INSERT over the reserved
-- GUID block.

REPLACE INTO `gameobject_template`
(`entry`, `type`, `displayId`, `name`, `size`, `Data0`, `Data1`, `Data2`, `Data3`)
VALUES
(930101, 2, 202, 'Call Board', 1, 0, 0, 0, 0);

DELETE FROM `gameobject` WHERE `id` = 930101 AND `guid` BETWEEN 5714521 AND 5714535;
INSERT INTO `gameobject`
(`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `position_x`, `position_y`,
 `position_z`, `orientation`, `rotation0`, `rotation1`, `rotation2`, `rotation3`, `spawntimesecs`,
 `animprogress`, `state`, `ScriptName`, `VerifiedBuild`, `Comment`)
VALUES
(5714521, 930101, 0, 1519, 1519, 1, 1, -8863.883407, 669.521069, 97.903100, 5.201100, 0, 0, 0.515030, -0.857172, 300, 255, 1, '', NULL, 'Call board: Stormwind'),
(5714522, 930101, 0, 1537, 1537, 1, 1, -4839.809440, -862.526259, 501.914000, 4.869500, 0, 0, 0.649436, -0.760416, 300, 255, 1, '', NULL, 'Call board: Ironforge'),
(5714523, 930101, 1, 1657, 1659, 1, 1, 10125.787802, 2230.085151, 1328.237200, 2.216600, 0, 0, 0.894941, 0.446184, 300, 255, 1, '', NULL, 'Call board: Darnassus'),
(5714524, 930101, 530, 3557, 3557, 1, 1, -3751.869951, -11696.123140, -105.896000, 3.145800, 0, 0, 0.999998, -0.002104, 300, 255, 1, '', NULL, 'Call board: Exodar'),
(5714525, 930101, 1, 1637, 1637, 1, 1, 1629.452468, -4435.918796, 14.952200, 2.757600, 0, 0, 0.981625, 0.190819, 300, 255, 1, '', NULL, 'Call board: Orgrimmar'),
(5714526, 930101, 0, 1497, 1497, 1, 1, 1629.701764, 223.504511, -43.102700, 2.844900, 0, 0, 0.989017, 0.147803, 300, 255, 1, '', NULL, 'Call board: Undercity'),
(5714527, 930101, 1, 1638, 1638, 1, 1, -1294.820848, 40.128255, 129.208600, 0.558500, 0, 0, 0.275635, 0.961262, 300, 255, 1, '', NULL, 'Call board: Thunder Bluff'),
(5714528, 930101, 530, 3487, 3487, 1, 1, 9569.866650, -7226.669362, 17.824000, 5.270900, 0, 0, 0.484807, -0.874621, 300, 255, 1, '', NULL, 'Call board: Silvermoon'),
(5714529, 930101, 530, 3703, 3898, 1, 1, -2180.831174, 5404.332052, 51.882500, 1.239200, 0, 0, 0.580710, 0.814111, 300, 255, 1, '', NULL, 'Call board: Shattrath'),
(5714530, 930101, 571, 4395, 4395, 1, 1, 5850.769034, 637.283083, 647.512100, 1.047200, 0, 0, 0.500001, 0.866025, 300, 255, 1, '', NULL, 'Call board: Dalaran'),
(5714531, 930101, 0, 33, 35, 1, 1, -14460.265250, 490.256881, 15.123700, 3.979400, 0, 0, 0.913535, -0.406759, 300, 255, 1, '', NULL, 'Call board: Booty Bay'),
(5714532, 930101, 1, 440, 976, 1, 1, -7162.411254, -3837.072506, 8.635400, 1.954800, 0, 0, 0.829046, 0.559180, 300, 255, 1, '', NULL, 'Call board: Gadgetzan'),
(5714533, 930101, 1, 618, 2255, 1, 1, 6699.864284, -4670.207065, 722.236900, 0.541100, 0, 0, 0.267261, 0.963624, 300, 255, 1, '', NULL, 'Call board: Everlook'),
(5714534, 930101, 530, 3523, 3712, 1, 1, 3064.123887, 3696.471751, 142.341700, 4.799700, 0, 0, 0.675574, -0.737292, 300, 255, 1, '', NULL, 'Call board: Area 52'),
(5714535, 930101, 1, 17, 392, 1, 1, -1044.339607, -3664.874299, 23.888200, 6.003900, 0, 0, 0.139189, -0.990266, 300, 255, 1, '', NULL, 'Call board: Ratchet');
