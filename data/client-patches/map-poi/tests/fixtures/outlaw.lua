-- Test fixture for the Outlaw client-patch visual contract.
-- It contains no player data; names, token and coordinates are invented.
return {
    token = "fixture-token-42",
    position = {
        killer = "Korgath",
        victim = "Elwynn",
        continent = 1, -- GetCurrentMapContinent(): 1 = Eastern Kingdoms
        zone = 1519, -- GetCurrentMapZone(): Stormwind City
        zoneName = "Stormwind City",
        subzone = "Trade District",
        mapX = 0.65,
        mapY = 0.72,
        continentX = 0.42,
        continentY = 0.58,
        ttl = 15,
    },
    -- CHAT_MSG_ADDON prefix SMPOI, tab-separated, version 2. AUTH comes first.
    auth = "2\tAUTH\tfixture-token-42",
    addon = table.concat({
        "2", "OUTLAW", "fixture-token-42", "Korgath", "Elwynn", "1", "1519",
        "Stormwind City", "Trade District", "0.65", "0.72", "0.42", "0.58", "15",
    }, "\t"),
    spoof = table.concat({
        "2", "OUTLAW", "wrong-token", "Mallory", "Elwynn", "1", "1519",
        "Stormwind City", "Trade District", "0.65", "0.72", "0.42", "0.58", "15",
    }, "\t"),
    clear = "2\tCLEAR\tfixture-token-42\tKorgath",
    kill = "2\tKILL\tfixture-token-42\tKorgath\tElwynn\tStormwind City\tTrade District",
    chat = "[OUTLAW] Korgath killed Elwynn in Stormwind City (Trade District).",
}
