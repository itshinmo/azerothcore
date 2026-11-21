-- Dual spec is free (ADR-021 revision 2026-11-21): the fork's gossip_menu_option data charged
-- 1000 gold (BoxMoney = 10000000) on the dual-spec purchase/info options that class trainer
-- gossip chains present. The chain is menu-based (e.g. trainer menu -> "I wish to know about
-- Dual Talent Specialization" -> "Purchase a Dual Talent Specialization") and the option TEXT
-- and OptionID vary per menu, so the fix is scoped by the dual-spec wording instead.
-- The level gate (MinDualSpecLevel = 30) is config; this clears the price. Unrelated priced
-- rows (e.g. menu 10995 contribution rows) are untouched.
-- Re-applicable: the UPDATE no-ops once the prices are already 0.
UPDATE `gossip_menu_option` SET `BoxMoney` = 0 WHERE (`OptionText` LIKE '%Dual Talent Specialization%' OR `OptionText` LIKE '%Dual Specialization%') AND `BoxMoney` > 0;
