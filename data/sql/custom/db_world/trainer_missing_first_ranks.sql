-- Missing rank-1/form trainer rows (ADR-021 revision 2026-11-21): the trainer data shipped
-- without twelve acquire-method-0 rank-1 spells that later trainer ranks require by chain
-- (ReqAbility) or spell_required. Without them, characters — fresh GM-leveled, legacy, and
-- normally-leveled alike — could never learn those chains (the trainer never offered rank 1).
-- Retail levels taken from the spell level in Spell.dbc; MoneyCost 0 (free learning, per the
-- server's QoL direction).
-- Coverage: all classes, found by a data audit (trainer references vs trainer rows):
--   druid: Bear Form, Maul, Mangle (Cat/Bear), Insect Swarm, Starfall, Typhoon, Wild Growth
--   (Bash/Swipe/Demoralizing Roar/Enrage/Lacerate/Savage Defense chains root at Bear Form via
--   spell_required)
--   shaman: Searing Totem, Healing Stream Totem, Stoneskin Totem
--   paladin: Redemption
-- Re-applicable: DELETE + INSERT keyed on (TrainerId, SpellId).
DELETE FROM `trainer_spell` WHERE (`TrainerId`, `SpellId`) IN ((33,5487),(34,5487),(33,6807),(34,6807),(33,33876),(34,33876),(33,33878),(34,33878),(14,3599),(15,3599),(14,5394),(15,5394),(14,8071),(15,8071),(3,7328),(4,7328),(33,5570),(34,5570),(33,48505),(34,48505),(33,50516),(34,50516),(33,48438),(34,48438));

INSERT INTO `trainer_spell` (`TrainerId`, `SpellId`, `MoneyCost`, `ReqSkillLine`, `ReqSkillRank`, `ReqAbility1`, `ReqAbility2`, `ReqAbility3`, `ReqLevel`) VALUES
-- druid trainers 33, 34
(33, 5487,  0, 0,   0,    0,    0, 0, 10), -- Bear Form
(34, 5487,  0, 0,   0,    0,    0, 0, 10),
(33, 6807,  0, 0,   0,    0,    0, 0, 10), -- Maul
(34, 6807,  0, 0,   0,    0,    0, 0, 10),
(33, 33876, 0, 0,   0,    0,    0, 0, 50), -- Mangle (Cat)
(34, 33876, 0, 0,   0,    0,    0, 0, 50),
(33, 33878, 0, 0,   0,    0,    0, 0, 50), -- Mangle (Bear)
(34, 33878, 0, 0,   0,    0,    0, 0, 50),
(33, 5570,  0, 0,   0,    0,    0, 0, 20), -- Insect Swarm
(34, 5570,  0, 0,   0,    0,    0, 0, 20),
(33, 48505, 0, 0,   0,    0,    0, 0, 60), -- Starfall
(34, 48505, 0, 0,   0,    0,    0, 0, 60),
(33, 50516, 0, 0,   0,    0,    0, 0, 50), -- Typhoon
(34, 50516, 0, 0,   0,    0,    0, 0, 50),
(33, 48438, 0, 0,   0,    0,    0, 0, 60), -- Wild Growth
(34, 48438, 0, 0,   0,    0,    0, 0, 60),
-- shaman trainers 14, 15
(14, 3599,  0, 0,   0,    0,    0, 0, 10), -- Searing Totem
(15, 3599,  0, 0,   0,    0,    0, 0, 10),
(14, 5394,  0, 0,   0,    0,    0, 0, 20), -- Healing Stream Totem
(15, 5394,  0, 0,   0,    0,    0, 0, 20),
(14, 8071,  0, 0,   0,    0,    0, 0, 4),  -- Stoneskin Totem
(15, 8071,  0, 0,   0,    0,    0, 0, 4),
-- paladin trainers 3, 4
(3,  7328,  0, 0,   0,    0,    0, 0, 12), -- Redemption
(4,  7328,  0, 0,   0,    0,    0, 0, 12);
