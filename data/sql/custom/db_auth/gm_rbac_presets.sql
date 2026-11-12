-- Project GM role presets. Group ids 950100-950104 are auth-only; see runbook/gm/rbac-roles.md.
-- Re-applicable: role rows are upserted, never deleted, so account grants survive a re-apply.
DELETE FROM `rbac_linked_permissions` WHERE `id` IN (950100, 950101, 950102, 950103, 950104);

INSERT INTO `rbac_permissions` (`id`, `name`) VALUES
(950100, 'Role: support (project)'),
(950101, 'Role: content-tester (project)'),
(950102, 'Role: economy (project)'),
(950103, 'Role: admin (project)'),
(950104, 'Role: superadmin (project)')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

REPLACE INTO `rbac_linked_permissions` (`id`, `linkedId`) VALUES
-- support: account/character lookup, unstuck, mute, tickets
(950100, 224), (950100, 444), (950100, 447), (950100, 449), (950100, 450),
(950100, 452), (950100, 453), (950100, 454), (950100, 456), (950100, 459),
(950100, 515), (950100, 517), (950100, 532), (950100, 534), (950100, 632), (950100, 743),
(950100, 744), (950100, 745), (950100, 746), (950100, 747), (950100, 749), (950100, 750),
(950100, 751), (950100, 752), (950100, 754), (950100, 755), (950100, 756), (950100, 758),
(950100, 759), (950100, 760), (950100, 945),
-- content-tester: teleport, GM mode, temporary spawns, instance inspect, content reloads
(950101, 371), (950101, 373), (950101, 374), (950101, 375), (950101, 376), (950101, 413),
(950101, 415), (950101, 459), (950101, 575), (950101, 593), (950101, 594),
(950101, 616), (950101, 629), (950101, 639), (950101, 640), (950101, 651),
(950101, 652), (950101, 673), (950101, 679), (950101, 689), (950101, 699), (950101, 737),
(950101, 740), (950101, 741), (950101, 796), (950101, 865),
-- economy: item, mail, and refund workflow
(950102, 447), (950102, 453), (950102, 484), (950102, 485), (950102, 487), (950102, 488),
(950102, 489), (950102, 509), (950102, 517), (950102, 886), (950102, 887), (950102, 888),
(950102, 930), (950102, 931),
-- admin: standard admin/GM commands plus bans, destructive tickets, RBAC and server reloads
(950103, 196), (950103, 197), (950103, 198), (950103, 199), (950103, 240), (950103, 241),
(950103, 242), (950103, 243), (950103, 245), (950103, 246), (950103, 247), (950103, 249),
(950103, 250), (950103, 251), (950103, 253), (950103, 254), (950103, 255), (950103, 256),
(950103, 282), (950103, 630), (950103, 680), (950103, 748), (950103, 753), (950103, 757),
(950103, 839), (950103, 840), (950103, 939),
-- superadmin: security-level administrator plus the project admin role
(950104, 192), (950104, 950103);
