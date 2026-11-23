-- Treasure placer command permission (ADR-031). GM-only development tool; never grant
-- to players. Re-applicable: DELETE + INSERT, project rows only.
DELETE FROM `rbac_permissions` WHERE `id` = 950152;

INSERT INTO `rbac_permissions` (`id`, `name`) VALUES
(950152, 'Command: treasure placer (project, GM only)')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

DELETE FROM `rbac_linked_permissions` WHERE `id` IN (950101, 950103, 950104) AND `linkedId` = 950152;

INSERT INTO `rbac_linked_permissions` (`id`, `linkedId`) VALUES
(950101, 950152),
(950103, 950152);
