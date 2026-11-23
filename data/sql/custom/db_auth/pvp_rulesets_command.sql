-- PvP rulesets pledge command permission (RFC-006, ADR-033). A player command needs a
-- specific RBAC permission id; 950151 sits in the project RBAC range (id-registry) and is
-- linked into role 199 ("Role: Player Commands"), which the Player role 195 already links.
-- Re-applicable: DELETE + INSERT; touches only the project rows.
DELETE FROM `rbac_permissions` WHERE `id` = 950151;

INSERT INTO `rbac_permissions` (`id`, `name`) VALUES
(950151, 'Command: pledge (project)');

DELETE FROM `rbac_linked_permissions` WHERE `id` = 199 AND `linkedId` = 950151;

INSERT INTO `rbac_linked_permissions` (`id`, `linkedId`) VALUES
(199, 950151);
