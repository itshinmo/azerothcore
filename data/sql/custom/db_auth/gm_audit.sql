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
  KEY `idx_audit_account_name_time` (`account_name`,`id`),
  KEY `idx_audit_command_time` (`command`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Existing installs: the audit read filters by account name and pages by id, so give that pair an
-- index. Guarded because a plain CREATE TABLE IF NOT EXISTS does not alter a table that exists.
SET @index_exists = (SELECT 1 FROM `INFORMATION_SCHEMA`.`STATISTICS` WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = 'gm_audit_log' AND `INDEX_NAME` = 'idx_audit_account_name_time' LIMIT 1);
SET @sql = IF(@index_exists IS NULL, 'ALTER TABLE `gm_audit_log` ADD INDEX `idx_audit_account_name_time` (`account_name`,`id`)', 'SELECT 1');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
