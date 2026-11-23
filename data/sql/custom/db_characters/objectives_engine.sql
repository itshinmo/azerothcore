-- mod-objectives: character-side state for the Adventure Board and Chronicle.
-- Re-applicable: CREATE TABLE IF NOT EXISTS only. The worldserver applies this file on restart
-- (Updates include data/sql/custom/db_characters, state CUSTOM).
-- Schema notes:
--   * board rows are per character, per scope (1 daily, 2 weekly) and slot;
--   * period_key is the reset unix time the row belongs to; a row is stale when period_key <= now;
--   * chronicle rows are per account, not per character;
--   * currency is split because Adventure Marks are account-wide.

CREATE TABLE IF NOT EXISTS `mod_objectives_board` (
  `guid` int unsigned NOT NULL,
  `scope` tinyint unsigned NOT NULL,
  `slot` tinyint unsigned NOT NULL,
  `task_id` int unsigned NOT NULL,
  `period_key` int unsigned NOT NULL,
  `progress` int unsigned NOT NULL DEFAULT 0,
  `completed` tinyint unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `scope`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mod_objectives_focus` (
  `guid` int unsigned NOT NULL,
  `period_key` int unsigned NOT NULL,
  `zone_id` int unsigned NOT NULL DEFAULT 0,
  `rerolls` int unsigned NOT NULL DEFAULT 0,
  `focus_changed` tinyint unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mod_objectives_chronicle` (
  `account_id` int unsigned NOT NULL,
  `slot` tinyint unsigned NOT NULL,
  `task_id` int unsigned NOT NULL,
  `period_key` int unsigned NOT NULL,
  `progress` int unsigned NOT NULL DEFAULT 0,
  `completed` tinyint unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mod_objectives_character_currency` (
  `guid` int unsigned NOT NULL,
  `mythic_coins` int unsigned NOT NULL DEFAULT 0,
  `commendations` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mod_objectives_account_currency` (
  `account_id` int unsigned NOT NULL,
  `adventure_marks` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
