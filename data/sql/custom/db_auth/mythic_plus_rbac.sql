-- RBAC for the Mythic+ first slice.
-- 950160: .mythic info (Player role)
-- 950163: .mythic status / .mythic reload (admin role)
-- Derived from silviu20092/mod-mythic-plus (MIT), commit e2a487d.

DELETE FROM `rbac_permissions` WHERE `id` IN (950160, 950163);

INSERT INTO `rbac_permissions` (`id`, `name`) VALUES
(950160, 'Command: mythic info (project)'),
(950163, 'Command: mythic status and reload (project)');

REPLACE INTO `rbac_linked_permissions` (`id`, `linkedId`) VALUES
(199, 950160),
(950103, 950163);
