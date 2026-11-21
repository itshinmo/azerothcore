-- Account-wide toy collection (ADR-023 social stack, owner decision 2026-11-21): a toy stays
-- collected once any character on the account has obtained it, retail toybox style. The table
-- records (account, toy item) pairs; the journal's owned-toys handler records currently held
-- toys into it and reports the union of recorded and held.
CREATE TABLE IF NOT EXISTS `mod_forever_journal_account_toys` (
  `account_id` int(10) unsigned NOT NULL,
  `item_id` int(10) unsigned NOT NULL,
  PRIMARY KEY (`account_id`, `item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
