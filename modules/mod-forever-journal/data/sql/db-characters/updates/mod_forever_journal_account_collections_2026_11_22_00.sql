-- Account-wide mount and pet collection (owner decision 2026-11-22): a mount or pet stays
-- collected once any character on the account has obtained it, retail collection style. The
-- spell is materialized into character_spell for every character of the account, as the toybox
-- does; these tables are the durable record, so deleting the character that obtained it changes
-- nothing. Learned spells are recorded as they are learned; characters that already knew one are
-- backfilled at login.
CREATE TABLE IF NOT EXISTS `mod_forever_journal_account_mounts` (
  `account_id` int(10) unsigned NOT NULL,
  `spell_id` int(10) unsigned NOT NULL,
  PRIMARY KEY (`account_id`, `spell_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mod_forever_journal_account_pets` (
  `account_id` int(10) unsigned NOT NULL,
  `spell_id` int(10) unsigned NOT NULL,
  PRIMARY KEY (`account_id`, `spell_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
