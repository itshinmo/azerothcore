-- World treasures: server item_dbc rows for the custom item IDs.
--
-- The server's sItemStore is seeded from DataDir/dbc/Item.dbc and the `item_dbc` table. A custom
-- item_template row whose ID is missing from sItemStore is skipped at load. These rows mirror
-- data/client-patches/item-data/dist/Item.dbc (patch-X), which gives the client the same entries.
-- Keep both sides in sync when an item changes.
--
-- IDs: 901001-901020 (batch 1). Re-applicable: REPLACE on the primary key.

REPLACE INTO `item_dbc` (`ID`, `ClassID`, `SubclassID`, `Sound_Override_Subclassid`,
    `Material`, `DisplayInfoID`, `InventoryType`, `SheatheType`) VALUES
(901001, 4, 0, -1, 7, 54808, 23, 0),
(901002, 4, 0, -1, 7, 36575, 23, 0),
(901003, 4, 0, -1, 4, 9657, 2, 0),
(901004, 4, 0, -1, 1, 9845, 11, 0),
(901005, 4, 2, -1, 8, 28802, 6, 0),
(901006, 4, 1, -1, 7, 19563, 1, 0),
(901007, 4, 0, -1, 3, 6562, 12, 0),
(901008, 4, 1, -1, 7, 23136, 16, 0),
(901009, 4, 0, -1, 4, 32008, 2, 0),
(901010, 2, 5, -1, 2, 8585, 17, 1),
(901011, 4, 2, -1, 8, 18322, 1, 0),
(901012, 2, 2, -1, 2, 28543, 15, 0),
(901013, 4, 6, -1, 1, 40781, 14, 0),
(901014, 4, 0, -1, 7, 44544, 23, 0),
(901015, 4, 0, -1, 3, 37552, 12, 0),
(901016, 2, 19, -1, 2, 43449, 26, 0),
(901017, 4, 1, -1, 7, 50050, 16, 0),
(901018, 2, 15, -1, 1, 52445, 13, 3),
(901019, 4, 0, -1, 3, 34188, 12, 0),
(901020, 4, 0, -1, 1, 35313, 11, 0);
