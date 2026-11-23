-- First playable Mythic+ slice: character-side tables.
-- Re-applicable: CREATE TABLE IF NOT EXISTS only.
-- Derived from silviu20092/mod-mythic-plus (MIT), commit e2a487d.

CREATE TABLE IF NOT EXISTS `mod_mythic_plus_progress` (
    `guid` int unsigned NOT NULL,
    `era` tinyint unsigned NOT NULL DEFAULT '0',
    `highest_key` tinyint unsigned NOT NULL DEFAULT '0',
    PRIMARY KEY (`guid`, `era`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mythic_plus_dungeon` (
    `id` int unsigned NOT NULL,
    `map` smallint unsigned NOT NULL,
    `timelimit` int unsigned NOT NULL DEFAULT '0',
    `starttime` bigint unsigned NOT NULL DEFAULT '0',
    `mythiclevel` tinyint unsigned NOT NULL DEFAULT '0',
    `done` tinyint unsigned NOT NULL DEFAULT '0',
    `penalty_on_death` int unsigned NOT NULL DEFAULT '0',
    `deaths` int unsigned NOT NULL DEFAULT '0',
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Migration: active-run rows never survive a restart and may carry the previous slice's schema.
DELETE FROM `mythic_plus_dungeon` WHERE `id` > 0;
