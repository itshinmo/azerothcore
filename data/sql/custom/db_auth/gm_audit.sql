-- GM command audit log. Auth database so it survives character deletion and covers all realms.
CREATE TABLE IF NOT EXISTS `gm_audit_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `realm_id` int NOT NULL,
  `account_id` int unsigned NOT NULL DEFAULT '0',
  `account_name` varchar(32) NOT NULL DEFAULT '',
  `player_name` varchar(64) NOT NULL DEFAULT '',
  `player_guid` bigint unsigned NOT NULL DEFAULT '0',
  `command` varchar(64) NOT NULL,
  `arguments` text,
  `result` varchar(32) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_audit_account_time` (`account_id`,`created_at`),
  KEY `idx_audit_command_time` (`command`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
