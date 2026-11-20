-- Collections: guard directions to the Warpweaver.
-- Guards (and, in Dalaran, the Violet Citadel teleport-service NPCs) get a
-- "The transmogrifier" gossip option that shows a minimap POI marker at the
-- city's Warpweaver (entry 910012). Mechanism: gossip_menu_option.ActionPoiID
-- -> server `points_of_interest` table -> SMSG_GOSSIP_POI (GossipDef.cpp
-- SendPointOfInterest); no client data involved.
-- IDs: POIs 950110-950119 and npc_text 950120, misc range per the ID registry.
-- Re-applicable: DELETE + INSERT; guard menus and their next free OptionID:
--   Stormwind City Guard 435 -> 16 | Ironforge Guard 2121 -> 13
--   Darnassus Sentinel 2352 -> 12  | Exodar Peacekeeper 7777 -> 11
--   Orgrimmar Grunt 1951 -> 15     | Undercity Guardian 2849 -> 14
--   Bluffwatcher 721 -> 13         | Silvermoon City Guardian 7633 -> 12
--   Shattrath City Peacekeeper 8282 -> 11 | Dalaran teleport service 10043 -> 15

-- Shared spoken answer when a player picks the option.
DELETE FROM `npc_text` WHERE `ID` = 950120;
INSERT INTO `npc_text` (`ID`, `text0_0`, `VerifiedBuild`) VALUES
(950120, 'Over there, $n — the Warpweaver is marked on your minimap.', 0);

-- Minimap markers at each capital's Warpweaver.
DELETE FROM `points_of_interest` WHERE `ID` BETWEEN 950110 AND 950119;
INSERT INTO `points_of_interest` (`ID`, `PositionX`, `PositionY`, `Icon`, `Flags`, `Importance`, `Name`) VALUES
(950110, -8438.9, 335.6, 7, 99, 0, 'Stormwind Warpweaver'),
(950111, -4863.2, -1020.2, 7, 99, 0, 'Ironforge Warpweaver'),
(950112, 9665.0, 2527.1, 7, 99, 0, 'Darnassus Warpweaver'),
(950113, -3991.2, -11411.2, 7, 99, 0, 'Exodar Warpweaver'),
(950114, 1916.3, -4125.3, 7, 99, 0, 'Orgrimmar Warpweaver'),
(950115, 1292.9, 318.7, 7, 99, 0, 'Undercity Warpweaver'),
(950116, -1207.1, -110.2, 7, 99, 0, 'Thunder Bluff Warpweaver'),
(950117, 9993.0, -7050.0, 7, 99, 0, 'Silvermoon Warpweaver'),
(950118, -1857.4, 5422.6, 7, 99, 0, 'Shattrath Warpweaver'),
(950119, 5805.5, 726.7, 7, 99, 0, 'Dalaran Warpweaver');

-- The option on each guard's existing direction menu. Re-apply keys on the natural
-- (MenuID, OptionID) pairs, so an edited ActionPoiID cannot dodge the DELETE.
-- (Two DELETEs to keep each line inside the 120-column style limit.)
DELETE FROM `gossip_menu_option` WHERE (`MenuID`, `OptionID`) IN
((435,16),(2121,13),(2352,12),(7777,11),(1951,15));
DELETE FROM `gossip_menu_option` WHERE (`MenuID`, `OptionID`) IN ((2849,14),(721,13),(7633,12),(8282,11),(10043,15));
INSERT INTO `gossip_menu_option` (`MenuID`, `OptionID`, `OptionIcon`, `OptionText`, `OptionBroadcastTextID`,
  `OptionType`, `OptionNpcFlag`, `ActionMenuID`, `ActionPoiID`, `BoxCoded`, `BoxMoney`, `BoxText`,
  `BoxBroadcastTextID`, `VerifiedBuild`) VALUES
(435, 16, 0, 'The transmogrifier', 0, 1, 1, 950120, 950110, 0, 0, '', 0, 0),
(2121, 13, 0, 'The transmogrifier', 0, 1, 1, 950120, 950111, 0, 0, '', 0, 0),
(2352, 12, 0, 'The transmogrifier', 0, 1, 1, 950120, 950112, 0, 0, '', 0, 0),
(7777, 11, 0, 'The transmogrifier', 0, 1, 1, 950120, 950113, 0, 0, '', 0, 0),
(1951, 15, 0, 'The transmogrifier', 0, 1, 1, 950120, 950114, 0, 0, '', 0, 0),
(2849, 14, 0, 'The transmogrifier', 0, 1, 1, 950120, 950115, 0, 0, '', 0, 0),
(721, 13, 0, 'The transmogrifier', 0, 1, 1, 950120, 950116, 0, 0, '', 0, 0),
(7633, 12, 0, 'The transmogrifier', 0, 1, 1, 950120, 950117, 0, 0, '', 0, 0),
(8282, 11, 0, 'The transmogrifier', 0, 1, 1, 950120, 950118, 0, 0, '', 0, 0),
(10043, 15, 0, 'The transmogrifier', 0, 1, 1, 950120, 950119, 0, 0, '', 0, 0);
