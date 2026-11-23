-- Transmog: hidden off-hand preview items.
--
-- 3.3.5 DressUpModel:TryOn has no hand argument; it picks the hand from the item's InventoryType.
-- A generic one-hand weapon (INVTYPE_WEAPON, 13) always lands in the main hand. For each such
-- item, this file adds a hidden copy at entry + 2000000 with InventoryType = INVTYPE_WEAPONOFFHAND
-- (22) and the same display id. The addon tries the copy on for the off-hand slot, so the left hand
-- shows the selected appearance while the right hand keeps its own.
--
-- Thrown weapons (INVTYPE_THROWN, 25) get a main-hand copy (INVTYPE_WEAPONMAINHAND, 21) at the
-- same offset. The client does not show a thrown model in the ranged slot on the preview; the
-- addon uses the main-hand copy while the ranged slot is selected, then returns to the real main
-- hand when another slot is selected.
--
-- The copies are not obtainable: no stats, no damage, no spells, no loot, no vendor, no set, and
-- BuyPrice/SellPrice are zero. They exist only for the client preview. The addon derives the id as
-- original + 2000000; the server answers the item query from item_template.
--
-- IDs: preview items 2000000-2999999 (generated range; see runbook/database/id-registry.md).
-- Source items must stay below 1000000, so entry + 2000000 stays inside the reserved range.
-- Re-applicable: REPLACE rebuilds every generated row on each apply, so items added later are
-- covered without editing this file. A preview row whose source item was removed stays behind; it
-- is hidden and unreachable, and the fixed range cannot collide with content.

DROP TEMPORARY TABLE IF EXISTS `tmp_transmog_preview_items`;
CREATE TEMPORARY TABLE `tmp_transmog_preview_items` AS
SELECT * FROM `item_template`
WHERE `class` = 2 AND `InventoryType` IN (13, 25) AND `entry` < 1000000;

UPDATE `tmp_transmog_preview_items` SET `entry` = `entry` + 2000000,
    `name` = CONCAT('Preview - ', `name`),
    `InventoryType` = CASE WHEN `InventoryType` = 13 THEN 22 ELSE 21 END,
    `RequiredLevel` = 1,
    `AllowableClass` = -1,
    `AllowableRace` = -1,
    `maxcount` = 0,
    `stackable` = 1,
    `BuyPrice` = 0,
    `SellPrice` = 0,
    `bonding` = 0,
    `itemset` = 0,
    `startquest` = 0,
    `ScalingStatDistribution` = 0,
    `ScalingStatValue` = 0,
    `Flags` = 0,
    `FlagsExtra` = 0,
    `FlagsCustom` = 0,
    `RandomProperty` = 0,
    `RandomSuffix` = 0,
    `stat_type1` = 0, `stat_value1` = 0,
    `stat_type2` = 0, `stat_value2` = 0,
    `stat_type3` = 0, `stat_value3` = 0,
    `stat_type4` = 0, `stat_value4` = 0,
    `stat_type5` = 0, `stat_value5` = 0,
    `stat_type6` = 0, `stat_value6` = 0,
    `stat_type7` = 0, `stat_value7` = 0,
    `stat_type8` = 0, `stat_value8` = 0,
    `stat_type9` = 0, `stat_value9` = 0,
    `stat_type10` = 0, `stat_value10` = 0,
    `dmg_min1` = 0, `dmg_max1` = 0, `dmg_type1` = 0,
    `dmg_min2` = 0, `dmg_max2` = 0, `dmg_type2` = 0,
    `armor` = 0,
    `holy_res` = 0, `fire_res` = 0, `nature_res` = 0,
    `frost_res` = 0, `shadow_res` = 0, `arcane_res` = 0,
    `delay` = 0,
    `spellid_1` = 0, `spelltrigger_1` = 0, `spellcharges_1` = 0,
    `spellppmRate_1` = 0, `spellcooldown_1` = 0, `spellcategory_1` = 0, `spellcategorycooldown_1` = 0,
    `spellid_2` = 0, `spelltrigger_2` = 0, `spellcharges_2` = 0,
    `spellppmRate_2` = 0, `spellcooldown_2` = 0, `spellcategory_2` = 0, `spellcategorycooldown_2` = 0,
    `spellid_3` = 0, `spelltrigger_3` = 0, `spellcharges_3` = 0,
    `spellppmRate_3` = 0, `spellcooldown_3` = 0, `spellcategory_3` = 0, `spellcategorycooldown_3` = 0,
    `spellid_4` = 0, `spelltrigger_4` = 0, `spellcharges_4` = 0,
    `spellppmRate_4` = 0, `spellcooldown_4` = 0, `spellcategory_4` = 0, `spellcategorycooldown_4` = 0,
    `spellid_5` = 0, `spelltrigger_5` = 0, `spellcharges_5` = 0,
    `spellppmRate_5` = 0, `spellcooldown_5` = 0, `spellcategory_5` = 0, `spellcategorycooldown_5` = 0,
    `MaxDurability` = 0,
    `socketColor_1` = 0, `socketContent_1` = 0,
    `socketColor_2` = 0, `socketContent_2` = 0,
    `socketColor_3` = 0, `socketContent_3` = 0,
    `socketBonus` = 0,
    `GemProperties` = 0,
    `ArmorDamageModifier` = 0,
    `duration` = 0,
    `ItemLimitCategory` = 0,
    `HolidayId` = 0,
    `DisenchantID` = 0,
    `FoodType` = 0,
    `minMoneyLoot` = 0,
    `maxMoneyLoot` = 0;

REPLACE INTO `item_template` SELECT * FROM `tmp_transmog_preview_items`;
DROP TEMPORARY TABLE `tmp_transmog_preview_items`;
