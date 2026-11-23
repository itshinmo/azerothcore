-- PvP rulesets per-character state (RFC-006, ADR-033). Slice 1 stores the mode and the
-- persisted pledge cooldown. Re-applicable: `CREATE TABLE IF NOT EXISTS` only.

CREATE TABLE IF NOT EXISTS `mod_pvp_rulesets_state` (
  `guid` INT UNSIGNED NOT NULL COMMENT 'characters.guid',
  `mode` ENUM('pve','warmode','highrisk') NOT NULL DEFAULT 'pve',
  `last_toggle` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'unix seconds of the last accepted pledge change',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
