-- Per-account 1x experience override used by modules/mod-xp-override.
-- Auth database so one row covers every character on the account and survives character deletion.
-- No foreign key: OnBeforeAccountDelete removes the row, but a direct SQL account delete can leave it
-- behind. Account ids are never reused, so a stale row only affects a nonexistent account.
CREATE TABLE IF NOT EXISTS `account_xp_override` (
  `account_id` int unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
