-- `.help xp` text for the player command in modules/mod-xp-override.
-- The command is security 0 (SEC_PLAYER); no RBAC permission row is required.
DELETE FROM `command` WHERE `name` = 'xp';
INSERT INTO `command` (`name`, `security`, `help`) VALUES
('xp', 0, 'Syntax: .xp\n\nToggle this account between 1x experience and the realm default.');
