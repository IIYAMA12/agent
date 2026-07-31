--- Shared area/location map for agent navigation, plus area lookup, filtering, and closest-match helpers.

---@class Agent
Agent = Agent or {}

-- Map of notable San Andreas areas for agent navigation.
-- category: airport | city | district | town | landmark | rural | military | waterfront
-- region: Los Santos | San Fierro | Las Venturas | Red County | Flint County | Whetstone | Bone County | Tierra Robada

-- Map of notable San Andreas areas for agent navigation.
-- category: airport | city | district | town | landmark | rural | military | waterfront
--           hospital | paynspray | police | ammu | gang | casino | service | mission | transport | entertainment | commercial
-- region: Los Santos | San Fierro | Las Venturas | Red County | Flint County | Whetstone | Bone County | Tierra Robada

---@type AgentArea[]
Agent.AREAS = {
    -- ═══════════════════════════════════════════════════════════════════
    -- AIRPORTS
    -- ═══════════════════════════════════════════════════════════════════
    { id = "lsia", name = "Los Santos International Airport", category = "airport", region = "Los Santos", x = 1684.5, y = -2335.5, z = 13.5, rotation = 90 },
    { id = "sfia", name = "San Fierro International Airport", category = "airport", region = "San Fierro", x = -1263.5, y = -30.5, z = 14.1, rotation = 90 },
    { id = "lvia", name = "Las Venturas Airport", category = "airport", region = "Las Venturas", x = 1695.0, y = 1615.5, z = 10.2, rotation = 90 },
    { id = "verdant", name = "Verdant Meadows Airstrip", category = "airport", region = "Bone County", x = 417.0, y = 2536.6, z = 19.4, rotation = 90 },

    -- ═══════════════════════════════════════════════════════════════════
    -- LOS SANTOS — DISTRICTS & WATERFRONT
    -- ═══════════════════════════════════════════════════════════════════
    { id = "ls_grove_street", name = "Grove Street", category = "district", region = "Los Santos", x = 2495.0, y = -1690.0, z = 13.5, rotation = 90 },
    { id = "ls_ganton", name = "Ganton", category = "district", region = "Los Santos", x = 2350.0, y = -1710.0, z = 13.5, rotation = 90 },
    { id = "ls_idlewood", name = "Idlewood", category = "district", region = "Los Santos", x = 1950.0, y = -1760.0, z = 13.5, rotation = 180 },
    { id = "ls_jefferson", name = "Jefferson", category = "district", region = "Los Santos", x = 2185.0, y = -1440.0, z = 24.0, rotation = 0 },
    { id = "ls_glen_park", name = "Glen Park", category = "district", region = "Los Santos", x = 1990.0, y = -1280.0, z = 23.0, rotation = 180 },
    { id = "ls_east_ls", name = "East Los Santos", category = "district", region = "Los Santos", x = 2420.0, y = -1480.0, z = 24.0, rotation = 90 },
    { id = "ls_las_colinas", name = "Las Colinas", category = "district", region = "Los Santos", x = 2280.0, y = -1280.0, z = 24.0, rotation = 0 },
    { id = "ls_willowfield", name = "Willowfield", category = "district", region = "Los Santos", x = 2080.0, y = -2050.0, z = 13.5, rotation = 180 },
    { id = "ls_playa_del_seville", name = "Playa del Seville", category = "district", region = "Los Santos", x = 2820.0, y = -2100.0, z = 11.0, rotation = 90 },
    { id = "ls_el_corona", name = "El Corona", category = "district", region = "Los Santos", x = 1820.0, y = -2100.0, z = 13.5, rotation = 90 },
    { id = "ls_little_mexico", name = "Little Mexico", category = "district", region = "Los Santos", x = 1750.0, y = -1890.0, z = 13.5, rotation = 90 },
    { id = "ls_market", name = "Market", category = "district", region = "Los Santos", x = 1370.0, y = -1270.0, z = 13.5, rotation = 0 },
    { id = "ls_temple", name = "Temple", category = "district", region = "Los Santos", x = 1120.0, y = -1120.0, z = 24.0, rotation = 0 },
    { id = "ls_commerce", name = "Commerce", category = "district", region = "Los Santos", x = 1480.0, y = -1580.0, z = 13.5, rotation = 0 },
    { id = "ls_downtown", name = "Downtown Los Santos", category = "city", region = "Los Santos", x = 1480.0, y = -1730.0, z = 13.5, rotation = 0 },
    { id = "ls_pershing_square", name = "Pershing Square", category = "district", region = "Los Santos", x = 1481.0, y = -1771.0, z = 18.8, rotation = 0 },
    { id = "ls_conference_center", name = "Los Santos Conference Center", category = "landmark", region = "Los Santos", x = 1100.0, y = -1790.0, z = 14.0, rotation = 90 },
    { id = "ls_vinewood", name = "Vinewood", category = "district", region = "Los Santos", x = 1415.0, y = -768.0, z = 78.0, rotation = 0 },
    { id = "ls_mulholland", name = "Mulholland", category = "district", region = "Los Santos", x = 1460.0, y = -681.0, z = 95.0, rotation = 0 },
    { id = "ls_richman", name = "Richman", category = "district", region = "Los Santos", x = 720.0, y = -950.0, z = 42.0, rotation = 0 },
    { id = "ls_rodeo", name = "Rodeo", category = "district", region = "Los Santos", x = 450.0, y = -1480.0, z = 30.0, rotation = 90 },
    { id = "ls_verona_beach", name = "Verona Beach", category = "waterfront", region = "Los Santos", x = 1040.0, y = -1720.0, z = 13.5, rotation = 180 },
    { id = "ls_santa_maria", name = "Santa Maria Beach", category = "waterfront", region = "Los Santos", x = 377.0, y = -2067.0, z = 7.8, rotation = 180 },
    { id = "ls_marina", name = "Marina", category = "waterfront", region = "Los Santos", x = 780.0, y = -1900.0, z = 5.0, rotation = 180 },
    { id = "ls_east_beach", name = "East Beach", category = "waterfront", region = "Los Santos", x = 2650.0, y = -2000.0, z = 13.5, rotation = 90 },
    { id = "ls_docks", name = "Ocean Docks", category = "waterfront", region = "Los Santos", x = 2770.0, y = -2500.0, z = 13.5, rotation = 270 },
    { id = "ls_shipyard", name = "LS Naval Shipyard", category = "waterfront", region = "Los Santos", x = 2870.0, y = -2620.0, z = 11.0, rotation = 270 },

    -- LOS SANTOS — LANDMARKS & ENTERTAINMENT
    { id = "ls_stadium", name = "All Saints Stadium", category = "landmark", region = "Los Santos", x = 2695.0, y = -1707.0, z = 11.0, rotation = 0 },
    { id = "ls_forum", name = "Los Santos Forum", category = "entertainment", region = "Los Santos", x = 1830.0, y = -1680.0, z = 13.5, rotation = 0 },
    { id = "ls_golf_club", name = "Los Santos Golf Club", category = "entertainment", region = "Los Santos", x = 1450.0, y = -2750.0, z = 13.5, rotation = 0 },
    { id = "ls_vinewood_sign", name = "Vinewood Sign", category = "landmark", region = "Los Santos", x = 1410.0, y = -790.0, z = 90.0, rotation = 0 },
    { id = "ls_observatory", name = "Los Santos Observatory", category = "landmark", region = "Los Santos", x = 1120.0, y = -2030.0, z = 78.0, rotation = 180 },
    { id = "lighthouse", name = "Santa Maria Lighthouse", category = "landmark", region = "Los Santos", x = 153.0, y = -1955.0, z = 3.8, rotation = 0 },
    { id = "ls_unity_station", name = "Unity Station", category = "transport", region = "Los Santos", x = 1758.0, y = -1895.0, z = 13.5, rotation = 90 },
    { id = "ls_market_station", name = "Market Station", category = "transport", region = "Los Santos", x = 822.0, y = -1350.0, z = 13.5, rotation = 0 },

    -- LOS SANTOS — GANG TERRITORIES
    { id = "gang_gsf_grove", name = "Grove Street Families (Grove Street)", category = "gang", region = "Los Santos", x = 2495.0, y = -1660.0, z = 13.5, rotation = 90 },
    { id = "gang_ballas_idlewood", name = "Front Yard Ballas (Idlewood)", category = "gang", region = "Los Santos", x = 2000.0, y = -1860.0, z = 13.5, rotation = 180 },
    { id = "gang_ballas_glen_park", name = "Kilo Tray Ballas (Glen Park)", category = "gang", region = "Los Santos", x = 1995.0, y = -1260.0, z = 23.0, rotation = 0 },
    { id = "gang_vagos_east", name = "Los Santos Vagos (East LS)", category = "gang", region = "Los Santos", x = 2520.0, y = -1520.0, z = 24.0, rotation = 90 },
    { id = "gang_vagos_william", name = "Los Santos Vagos (Willowfield)", category = "gang", region = "Los Santos", x = 2800.0, y = -1950.0, z = 11.0, rotation = 90 },
    { id = "gang_aztecas", name = "Varrios Los Aztecas (El Corona)", category = "gang", region = "Los Santos", x = 1780.0, y = -2150.0, z = 13.5, rotation = 90 },

    -- LOS SANTOS — SERVICES
    { id = "hospital_all_saints", name = "All Saints General Hospital", category = "hospital", region = "Los Santos", x = 1172.7, y = -1323.2, z = 15.4, rotation = 270 },
    { id = "hospital_county_general", name = "County General Hospital", category = "hospital", region = "Los Santos", x = 2037.4, y = -1401.3, z = 17.2, rotation = 180 },
    { id = "police_ls", name = "Los Santos Police HQ (Pershing Square)", category = "police", region = "Los Santos", x = 1544.6, y = -1630.9, z = 13.5, rotation = 0 },
    { id = "paynspray_ls_idlewood", name = "Pay 'n' Spray (Idlewood)", category = "paynspray", region = "Los Santos", x = 487.4, y = -1734.4, z = 11.0, rotation = 0 },
    { id = "paynspray_ls_temple", name = "Pay 'n' Spray (Temple)", category = "paynspray", region = "Los Santos", x = 1024.8, y = -1029.1, z = 32.1, rotation = 270 },
    { id = "paynspray_ls_willowfield", name = "Pay 'n' Spray (Willowfield)", category = "paynspray", region = "Los Santos", x = 1976.4, y = -2176.7, z = 13.6, rotation = 180 },
    { id = "ammu_ls_market", name = "Ammu-Nation (Market)", category = "ammu", region = "Los Santos", x = 1368.5, y = -1279.3, z = 13.5, rotation = 0 },
    { id = "ammu_ls_jefferson", name = "Ammu-Nation (Jefferson)", category = "ammu", region = "Los Santos", x = 2398.8, y = -1897.8, z = 13.5, rotation = 90 },
    { id = "gym_ls_ganton", name = "Ganton Gym", category = "service", region = "Los Santos", x = 2229.5, y = -1722.2, z = 13.5, rotation = 90 },
    { id = "barber_ls_idlewood", name = "Barber Shop (Idlewood)", category = "service", region = "Los Santos", x = 2070.0, y = -1790.0, z = 13.5, rotation = 90 },
    { id = "tattoo_ls_el_corona", name = "Tattoo Parlor (El Corona)", category = "service", region = "Los Santos", x = 2065.0, y = -2120.0, z = 13.5, rotation = 90 },

    -- LOS SANTOS — MISSION / STORY LANDMARKS
    { id = "mission_cj_house", name = "CJ's Safe House (Grove Street)", category = "mission", region = "Los Santos", x = 2496.0, y = -1692.0, z = 14.0, rotation = 90 },
    { id = "mission_sweets_house", name = "Sweet's House", category = "mission", region = "Los Santos", x = 2525.0, y = -1680.0, z = 13.5, rotation = 90 },
    { id = "mission_ryder_house", name = "Ryder's House", category = "mission", region = "Los Santos", x = 2465.0, y = -1715.0, z = 13.5, rotation = 90 },
    { id = "mission_big_smoke_crack", name = "Big Smoke's Crack Palace", category = "mission", region = "Los Santos", x = 2540.0, y = -1300.0, z = 34.0, rotation = 0 },
    { id = "mission_madd_dogg", name = "Madd Dogg's Mansion", category = "mission", region = "Los Santos", x = 1260.0, y = -785.0, z = 92.0, rotation = 0 },
    { id = "burgershot_ls_marina", name = "Burger Shot (Marina)", category = "commercial", region = "Los Santos", x = 810.0, y = -1610.0, z = 13.5, rotation = 0 },
    { id = "cluckin_ls_market", name = "Cluckin' Bell (Market)", category = "commercial", region = "Los Santos", x = 928.0, y = -1352.0, z = 13.5, rotation = 0 },
    { id = "wellstacked_ls", name = "Well Stacked Pizza (Temple)", category = "commercial", region = "Los Santos", x = 1038.0, y = -1340.0, z = 13.5, rotation = 0 },

    -- ═══════════════════════════════════════════════════════════════════
    -- SAN FIERRO — DISTRICTS & WATERFRONT
    -- ═══════════════════════════════════════════════════════════════════
    { id = "sf_downtown", name = "Downtown San Fierro", category = "city", region = "San Fierro", x = -1982.0, y = 1117.0, z = 53.0, rotation = 0 },
    { id = "sf_doherty", name = "Doherty", category = "district", region = "San Fierro", x = -2039.0, y = 178.0, z = 28.8, rotation = 90 },
    { id = "sf_kings", name = "King's", category = "district", region = "San Fierro", x = -2320.0, y = 580.0, z = 35.0, rotation = 0 },
    { id = "sf_queens", name = "Queens", category = "district", region = "San Fierro", x = -2620.0, y = 220.0, z = 4.0, rotation = 90 },
    { id = "sf_garcia", name = "Garcia", category = "district", region = "San Fierro", x = -2270.0, y = -155.0, z = 35.3, rotation = 90 },
    { id = "sf_hashbury", name = "Hashbury", category = "district", region = "San Fierro", x = -2425.0, y = 1027.0, z = 52.0, rotation = 0 },
    { id = "sf_calton_heights", name = "Calton Heights", category = "district", region = "San Fierro", x = -2270.0, y = 960.0, z = 66.0, rotation = 0 },
    { id = "sf_chinatown", name = "Chinatown", category = "district", region = "San Fierro", x = -2120.0, y = 750.0, z = 69.0, rotation = 0 },
    { id = "sf_pallisades", name = "Palisades", category = "district", region = "San Fierro", x = -2780.0, y = 1420.0, z = 7.0, rotation = 270 },
    { id = "sf_paradiso", name = "Paradiso", category = "district", region = "San Fierro", x = -2740.0, y = 960.0, z = 54.0, rotation = 270 },
    { id = "sf_battery_point", name = "Battery Point", category = "district", region = "San Fierro", x = -2740.0, y = 1260.0, z = 55.0, rotation = 270 },
    { id = "sf_juniper_hollow", name = "Juniper Hollow", category = "district", region = "San Fierro", x = -2530.0, y = 960.0, z = 16.0, rotation = 90 },
    { id = "sf_easter_basin", name = "Easter Basin", category = "waterfront", region = "San Fierro", x = -696.0, y = 897.0, z = 13.5, rotation = 180 },
    { id = "sf_esplanade", name = "Esplanade North", category = "waterfront", region = "San Fierro", x = -1630.0, y = 1200.0, z = 7.0, rotation = 0 },
    { id = "sf_shipping", name = "San Fierro Bay (Shipping)", category = "waterfront", region = "San Fierro", x = -1850.0, y = 1480.0, z = 7.0, rotation = 270 },

    -- SAN FIERRO — LANDMARKS & BRIDGES
    { id = "sf_gant_bridge", name = "Gant Bridge", category = "landmark", region = "San Fierro", x = -2690.0, y = 1270.0, z = 55.0, rotation = 270 },
    { id = "sf_garver_bridge", name = "Garver Bridge", category = "landmark", region = "San Fierro", x = -1330.0, y = 430.0, z = 35.0, rotation = 90 },
    { id = "sf_kincaid_bridge", name = "Kincaid Bridge", category = "landmark", region = "San Fierro", x = -1080.0, y = 960.0, z = 42.0, rotation = 90 },
    { id = "sf_zero_shop", name = "Zero RC Shop", category = "mission", region = "San Fierro", x = -2240.0, y = 128.0, z = 35.0, rotation = 90 },
    { id = "sf_wu_zi_mu", name = "Four Dragons Casino (Wu Zi Mu)", category = "casino", region = "San Fierro", x = -2015.0, y = 156.0, z = 28.0, rotation = 90 },
    { id = "sf_jizzy_club", name = "Jizzy's Pleasure Domes", category = "entertainment", region = "San Fierro", x = -2620.0, y = 1410.0, z = 7.0, rotation = 270 },
    { id = "sf_train_station", name = "San Fierro Train Station", category = "transport", region = "San Fierro", x = -1980.0, y = 120.0, z = 27.0, rotation = 90 },

    -- SAN FIERRO — GANGS
    { id = "gang_triads_chinatown", name = "San Fierro Triads (Chinatown)", category = "gang", region = "San Fierro", x = -2120.0, y = 720.0, z = 69.0, rotation = 0 },
    { id = "gang_rifa", name = "San Fierro Rifa (Doherty)", category = "gang", region = "San Fierro", x = -2040.0, y = 120.0, z = 28.8, rotation = 90 },
    { id = "gang_da_nang", name = "Da Nang Boys (Easter Basin)", category = "gang", region = "San Fierro", x = -650.0, y = 870.0, z = 13.5, rotation = 180 },

    -- SAN FIERRO — SERVICES
    { id = "hospital_sf", name = "San Fierro Medical Center", category = "hospital", region = "San Fierro", x = -2655.2, y = 639.4, z = 14.5, rotation = 90 },
    { id = "police_sf", name = "San Fierro Police HQ", category = "police", region = "San Fierro", x = -1605.3, y = 711.4, z = 13.9, rotation = 0 },
    { id = "paynspray_sf_doherty", name = "Pay 'n' Spray (Doherty)", category = "paynspray", region = "San Fierro", x = -1904.5, y = 280.4, z = 41.0, rotation = 90 },
    { id = "paynspray_sf_hashbury", name = "Pay 'n' Spray (Hashbury)", category = "paynspray", region = "San Fierro", x = -2425.9, y = 1027.0, z = 52.1, rotation = 0 },
    { id = "ammu_sf_queens", name = "Ammu-Nation (Queens)", category = "ammu", region = "San Fierro", x = -2629.9, y = 209.9, z = 4.8, rotation = 90 },
    { id = "ammu_sf_downtown", name = "Ammu-Nation (Downtown)", category = "ammu", region = "San Fierro", x = -2001.9, y = 134.1, z = 27.7, rotation = 90 },
    { id = "gym_sf_garcia", name = "Garcia Gym", category = "service", region = "San Fierro", x = -2270.9, y = -155.1, z = 35.3, rotation = 90 },
    { id = "burgershot_sf_kings", name = "Burger Shot (King's)", category = "commercial", region = "San Fierro", x = -2330.0, y = -165.0, z = 35.0, rotation = 90 },

    -- ═══════════════════════════════════════════════════════════════════
    -- LAS VENTURAS — DISTRICTS & STRIP
    -- ═══════════════════════════════════════════════════════════════════
    { id = "lv_strip", name = "The Strip", category = "city", region = "Las Venturas", x = 2027.0, y = 1007.0, z = 10.8, rotation = 0 },
    { id = "lv_pilgrim", name = "Pilgrim", category = "district", region = "Las Venturas", x = 2597.0, y = 1903.0, z = 10.8, rotation = 0 },
    { id = "lv_prickle_pine", name = "Prickle Pine", category = "district", region = "Las Venturas", x = 1420.0, y = 2600.0, z = 10.8, rotation = 0 },
    { id = "lv_rockshore_west", name = "Rockshore West", category = "district", region = "Las Venturas", x = 1580.0, y = 2200.0, z = 10.8, rotation = 0 },
    { id = "lv_rockshore_east", name = "Rockshore East", category = "district", region = "Las Venturas", x = 2640.0, y = 2200.0, z = 10.8, rotation = 0 },
    { id = "lv_redsands_west", name = "Redsands West", category = "district", region = "Las Venturas", x = 1680.0, y = 1200.0, z = 10.8, rotation = 0 },
    { id = "lv_redsands_east", name = "Redsands East", category = "district", region = "Las Venturas", x = 2640.0, y = 1200.0, z = 10.8, rotation = 0 },
    { id = "lv_spinybed", name = "Spinybed", category = "district", region = "Las Venturas", x = 2140.0, y = 2780.0, z = 10.8, rotation = 0 },
    { id = "lv_creek", name = "Creek", category = "district", region = "Las Venturas", x = 2740.0, y = 2800.0, z = 10.8, rotation = 0 },
    { id = "lv_linden", name = "Linden Station", category = "district", region = "Las Venturas", x = 2740.0, y = 1260.0, z = 10.8, rotation = 0 },
    { id = "lv_old_vegas", name = "Old Venturas Strip", category = "district", region = "Las Venturas", x = 2360.0, y = 2450.0, z = 10.8, rotation = 0 },
    { id = "lv_whore", name = "The Camel's Toe", category = "district", region = "Las Venturas", x = 2080.0, y = 1280.0, z = 10.8, rotation = 0 },
    { id = "lv_greenpalacio", name = "Green Palms", category = "rural", region = "Las Venturas", x = 1760.0, y = 2800.0, z = 10.8, rotation = 0 },

    -- LAS VENTURAS — CASINOS & ENTERTAINMENT
    { id = "lv_caligula", name = "Caligula's Palace", category = "casino", region = "Las Venturas", x = 2233.0, y = 1715.0, z = 10.8, rotation = 0 },
    { id = "lv_pirates", name = "Pirates in Men's Pants", category = "casino", region = "Las Venturas", x = 2019.0, y = 1917.0, z = 12.0, rotation = 180 },
    { id = "lv_four_dragons", name = "Four Dragons Casino", category = "casino", region = "Las Venturas", x = 2020.0, y = 1007.0, z = 10.8, rotation = 0 },
    { id = "lv_come_a_lot", name = "Come-A-Lot Casino", category = "casino", region = "Las Venturas", x = 2160.0, y = 1590.0, z = 10.8, rotation = 0 },
    { id = "lv_clowns_pocket", name = "Clown's Pocket", category = "casino", region = "Las Venturas", x = 2240.0, y = 1280.0, z = 10.8, rotation = 0 },
    { id = "lv_visage", name = "The Visage", category = "casino", region = "Las Venturas", x = 2600.0, y = 1100.0, z = 10.8, rotation = 0 },
    { id = "lv_stadium", name = "Las Venturas Stadium", category = "entertainment", region = "Las Venturas", x = 1310.0, y = 2140.0, z = 11.0, rotation = 0 },
    { id = "lv_train_station", name = "Las Venturas Train Station", category = "transport", region = "Las Venturas", x = 1450.0, y = 2650.0, z = 10.8, rotation = 0 },

    -- LAS VENTURAS — SERVICES
    { id = "hospital_lv", name = "Las Venturas Hospital", category = "hospital", region = "Las Venturas", x = 1606.5, y = 1815.8, z = 10.8, rotation = 0 },
    { id = "police_lv", name = "Las Venturas Police HQ", category = "police", region = "Las Venturas", x = 2282.9, y = 2421.1, z = 10.8, rotation = 0 },
    { id = "paynspray_lv_redsands", name = "Pay 'n' Spray (Redsands East)", category = "paynspray", region = "Las Venturas", x = 2644.5, y = 110.8, z = 11.0, rotation = 0 },
    { id = "paynspray_lv_rockshore", name = "Pay 'n' Spray (Rockshore West)", category = "paynspray", region = "Las Venturas", x = 1584.7, y = 2207.7, z = 10.8, rotation = 0 },
    { id = "ammu_lv_old", name = "Ammu-Nation (Old Venturas Strip)", category = "ammu", region = "Las Venturas", x = 2538.9, y = 2084.0, z = 10.8, rotation = 0 },
    { id = "gym_lv_redsands", name = "Redsands Gym", category = "service", region = "Las Venturas", x = 1968.8, y = 2295.9, z = 10.8, rotation = 0 },
    { id = "burgershot_lv_strip", name = "Burger Shot (The Strip)", category = "commercial", region = "Las Venturas", x = 1870.0, y = 2070.0, z = 10.8, rotation = 0 },

    -- ═══════════════════════════════════════════════════════════════════
    -- COUNTRY TOWNS
    -- ═══════════════════════════════════════════════════════════════════
    { id = "angel_pine", name = "Angel Pine", category = "town", region = "Whetstone", x = -2325.0, y = -1636.0, z = 483.0, rotation = 0 },
    { id = "blueberry", name = "Blueberry", category = "town", region = "Red County", x = 233.0, y = -177.0, z = 1.5, rotation = 0 },
    { id = "dillimore", name = "Dillimore", category = "town", region = "Red County", x = 738.0, y = -494.0, z = 16.0, rotation = 0 },
    { id = "montgomery", name = "Montgomery", category = "town", region = "Red County", x = 1369.0, y = 273.0, z = 19.0, rotation = 0 },
    { id = "palomino_creek", name = "Palomino Creek", category = "town", region = "Red County", x = 2269.0, y = 49.0, z = 26.5, rotation = 0 },
    { id = "fort_carson", name = "Fort Carson", category = "town", region = "Bone County", x = -248.0, y = 1228.0, z = 12.0, rotation = 0 },
    { id = "el_quebrados", name = "El Quebrados", category = "town", region = "Tierra Robada", x = -1416.0, y = 2591.0, z = 55.0, rotation = 0 },
    { id = "las_barrancas", name = "Las Barrancas", category = "town", region = "Tierra Robada", x = -857.0, y = 1536.0, z = 22.0, rotation = 0 },
    { id = "las_paydas", name = "Las Payasadas", category = "town", region = "Tierra Robada", x = -354.0, y = 2589.0, z = 11.0, rotation = 0 },
    { id = "bayside", name = "Bayside", category = "town", region = "Tierra Robada", x = -2310.0, y = 2310.0, z = 4.8, rotation = 0 },
    { id = "paradiso_creek", name = "Paradiso (Tierra Robada)", category = "town", region = "Tierra Robada", x = -2740.0, y = 2170.0, z = 100.0, rotation = 0 },

    -- COUNTRY — SERVICES
    { id = "hospital_angel_pine", name = "Angel Pine Medical Center", category = "hospital", region = "Whetstone", x = -2219.8, y = -2296.6, z = 7.8, rotation = 0 },
    { id = "police_fort_carson", name = "Fort Carson Police Station", category = "police", region = "Bone County", x = -224.8, y = 979.3, z = 12.3, rotation = 0 },
    { id = "police_dillimore", name = "Dillimore Police Station", category = "police", region = "Red County", x = 738.3, y = -494.7, z = 16.0, rotation = 0 },
    { id = "paynspray_dillimore", name = "Pay 'n' Spray (Dillimore)", category = "paynspray", region = "Red County", x = 720.3, y = -462.5, z = 16.3, rotation = 0 },
    { id = "paynspray_palomino", name = "Pay 'n' Spray (Palomino Creek)", category = "paynspray", region = "Red County", x = 2269.6, y = 33.0, z = 26.5, rotation = 0 },
    { id = "paynspray_blueberry", name = "Pay 'n' Spray (Blueberry)", category = "paynspray", region = "Red County", x = 199.6, y = -26.0, z = 1.6, rotation = 0 },
    { id = "paynspray_tierra_robada", name = "Pay 'n' Spray (Tierra Robada)", category = "paynspray", region = "Tierra Robada", x = -1420.5, y = 2591.1, z = 55.7, rotation = 0 },
    { id = "ammu_fort_carson", name = "Ammu-Nation (Fort Carson)", category = "ammu", region = "Bone County", x = -315.0, y = 829.6, z = 14.2, rotation = 0 },
    { id = "cluckin_angel_pine", name = "Cluckin' Bell (Angel Pine)", category = "commercial", region = "Whetstone", x = -2155.0, y = -2460.0, z = 30.6, rotation = 0 },

    -- ═══════════════════════════════════════════════════════════════════
    -- LANDMARKS, RURAL & MILITARY
    -- ═══════════════════════════════════════════════════════════════════
    { id = "mount_chiliad", name = "Mount Chiliad Summit", category = "landmark", region = "Whetstone", x = -2237.0, y = -1742.0, z = 480.0, rotation = 0 },
    { id = "mount_chiliad_base", name = "Mount Chiliad (Base Camp)", category = "landmark", region = "Whetstone", x = -2320.0, y = -1610.0, z = 483.0, rotation = 0 },
    { id = "area_69", name = "Area 69", category = "military", region = "Bone County", x = 214.0, y = 1877.0, z = 13.0, rotation = 0 },
    { id = "area_69_restricted", name = "Area 69 (Restricted Zone)", category = "military", region = "Bone County", x = 360.0, y = 1950.0, z = 17.0, rotation = 0 },
    { id = "sherman_dam", name = "Sherman Dam", category = "landmark", region = "Tierra Robada", x = -816.0, y = 2227.0, z = 75.0, rotation = 0 },
    { id = "lv_ship", name = "Las Venturas Naval Ship", category = "landmark", region = "Bone County", x = -2353.0, y = 1525.0, z = 1.0, rotation = 90 },
    { id = "aircraft_carrier", name = "Aircraft Carrier (Easter Basin)", category = "military", region = "San Fierro", x = -1450.0, y = 1540.0, z = 11.0, rotation = 270 },
    { id = "quarry", name = "Hunter Quarry", category = "landmark", region = "Bone County", x = 590.0, y = 870.0, z = -42.0, rotation = 0 },
    { id = "lil_probe_inn", name = "Lil' Probe Inn", category = "landmark", region = "Bone County", x = -90.0, y = 1227.0, z = 19.7, rotation = 0 },
    { id = "the_farm", name = "The Farm", category = "rural", region = "Flint County", x = -110.0, y = -30.0, z = 3.1, rotation = 0 },
    { id = "flint_range", name = "Flint Range", category = "rural", region = "Flint County", x = -501.0, y = -108.0, z = 25.0, rotation = 0 },
    { id = "farm", name = "Blueberry Acres", category = "rural", region = "Red County", x = 1968.0, y = -1208.0, z = 19.0, rotation = 0 },
    { id = "leafy_hollow", name = "Leafy Hollow", category = "rural", region = "Flint County", x = -1126.0, y = -1058.0, z = 129.0, rotation = 0 },
    { id = "back_o_beyond", name = "Back o Beyond", category = "rural", region = "Whetstone", x = -1100.0, y = -1630.0, z = 76.0, rotation = 0 },
    { id = "shady_creeks", name = "Shady Creeks", category = "rural", region = "Whetstone", x = -1640.0, y = -2260.0, z = 31.0, rotation = 0 },
    { id = "foster_valley", name = "Foster Valley", category = "rural", region = "Flint County", x = -870.0, y = -1090.0, z = 95.0, rotation = 0 },
    { id = "fallen_tree", name = "Fallen Tree", category = "rural", region = "Flint County", x = -792.0, y = -70.0, z = 16.0, rotation = 0 },
    { id = "the_clown", name = "The Big Ear (Satellite Dish)", category = "landmark", region = "Bone County", x = -360.0, y = 1600.0, z = 75.0, rotation = 0 },
    { id = "mission_catalina", name = "Catalina's Hideout (Fern Ridge)", category = "mission", region = "Red County", x = 681.0, y = -473.0, z = 16.0, rotation = 0 },
    { id = "cluckin_factory", name = "Cluckin' Bell Factory", category = "commercial", region = "Bone County", x = -210.0, y = -250.0, z = 1.5, rotation = 0 },
    { id = "race_track_redsands", name = "Redsands Race Track", category = "entertainment", region = "Las Venturas", x = 1450.0, y = 980.0, z = 10.8, rotation = 0 },
    { id = "blackfield_chapel", name = "Blackfield Chapel", category = "landmark", region = "Las Venturas", x = 1370.0, y = 650.0, z = 10.8, rotation = 0 },
    { id = "blackfield_intersection", name = "Blackfield Intersection", category = "landmark", region = "Las Venturas", x = 980.0, y = 1760.0, z = 10.8, rotation = 0 },
    { id = "octane_springs", name = "Octane Springs", category = "rural", region = "Bone County", x = 580.0, y = 1650.0, z = 12.0, rotation = 0 },
    { id = "regular_tom", name = "Regular Tom's Trailer Park", category = "rural", region = "Bone County", x = 60.0, y = 1180.0, z = 18.0, rotation = 0 },
    { id = "robada_intersection", name = "Robada Intersection", category = "landmark", region = "Tierra Robada", x = -860.0, y = 2720.0, z = 45.0, rotation = 0 },
    { id = "bayside_tunnel", name = "Bayside Tunnel", category = "landmark", region = "Tierra Robada", x = -2690.0, y = 2180.0, z = 55.0, rotation = 0 },
    { id = "devils_tower", name = "Devil's Peak", category = "landmark", region = "Red County", x = -300.0, y = -850.0, z = 12.0, rotation = 0 },
    { id = "hankypanky", name = "Hankypanky Point", category = "landmark", region = "Red County", x = 2570.0, y = 80.0, z = 26.0, rotation = 0 },
}

--- Rounds a distance value to one decimal place.
---@param distance number
---@return number
local function roundDistance(distance)
    return math.floor(distance * 10 + 0.5) / 10
end

--- Lowercases a string value, or returns nil for non-strings/empty strings.
---@param value string|nil
---@return string|nil
local function normalizeString(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    return value:lower()
end

--- Copies an AgentArea's public fields into a plain table.
---@param area AgentArea|nil
---@return AgentArea|nil
function Agent.describeArea(area)
    if not area then
        return nil
    end
    return {
        id = area.id,
        name = area.name,
        category = area.category,
        region = area.region,
        x = area.x,
        y = area.y,
        z = area.z,
        rotation = area.rotation,
    }
end

--- Alias of Agent.describeArea, used when building result lists.
---@param area AgentArea
---@return AgentArea|nil
local function copyAreaSummary(area)
    return Agent.describeArea(area)
end

--- Normalizes area filter options (locationId/category/region/search) from various legacy field names.
---@param options AgentAreaFilters|table|nil
---@return AgentAreaFilters
local function normalizeAreaFilters(options)
    options = type(options) == "table" and options or {}

    local locationId = options.locationId or options.airportId or options.areaId or options.id
    local category = options.category or options.type
    local region = options.region
    local search = normalizeString(options.search or options.name)

    return {
        locationId = locationId,
        category = category,
        region = region,
        search = search,
    }
end

--- Checks whether an area matches the given normalized filters.
---@param area AgentArea
---@param filters AgentAreaFilters
---@return boolean matches
local function areaMatchesFilters(area, filters)
    if filters.locationId and area.id ~= filters.locationId then
        return false
    end
    if filters.category and area.category ~= filters.category then
        return false
    end
    if filters.region and area.region ~= filters.region then
        return false
    end
    if filters.search then
        local haystack = (area.name .. " " .. area.id .. " " .. area.region):lower()
        if not haystack:find(filters.search, 1, true) then
            return false
        end
    end
    return true
end

--- Lists all areas matching the given filters, sorted by region then name.
---@param options AgentAreaFilters|table|nil
---@return AgentArea[]
function Agent.listAreas(options)
    local filters = normalizeAreaFilters(options)
    local results = {}

    for i = 1, #Agent.AREAS do
        local area = Agent.AREAS[i]
        if areaMatchesFilters(area, filters) then
            results[#results + 1] = copyAreaSummary(area)
        end
    end

    table.sort(results, function(a, b)
        if a.region == b.region then
            return a.name < b.name
        end
        return a.region < b.region
    end)

    return results
end

--- Finds an area by its exact id.
---@param locationId string
---@return AgentArea|nil
function Agent.findAreaById(locationId)
    if type(locationId) ~= "string" or locationId == "" then
        return nil
    end

    for i = 1, #Agent.AREAS do
        local area = Agent.AREAS[i]
        if area.id == locationId then
            return area
        end
    end

    return nil
end

--- Finds the closest matching area to a 3D position, or resolves an exact locationId.
---@param x number
---@param y number
---@param z number
---@param options AgentAreaFilters|table|nil
---@return AgentArea|nil area
---@return number|string|nil distanceOrErr Rounded distance on success, error message on failure.
function Agent.findClosestArea(x, y, z, options)
    options = type(options) == "table" and options or {}
    local filters = normalizeAreaFilters(options)

    if filters.locationId then
        local area = Agent.findAreaById(filters.locationId)
        if not area then
            return nil, "Unknown location id: " .. filters.locationId
        end
        local distance = getDistanceBetweenPoints3D(x, y, z, area.x, area.y, area.z)
        return area, roundDistance(distance)
    end

    local closestArea
    local closestDistance

    for i = 1, #Agent.AREAS do
        local area = Agent.AREAS[i]
        if areaMatchesFilters(area, filters) then
            local distance = getDistanceBetweenPoints3D(x, y, z, area.x, area.y, area.z)
            if not closestDistance or distance < closestDistance then
                closestDistance = distance
                closestArea = area
            end
        end
    end

    if not closestArea then
        return nil, "No matching areas found"
    end

    return closestArea, roundDistance(closestDistance)
end

-- Backward-compatible airport helpers
---@type AgentArea[]
Agent.AIRPORTS = Agent.AREAS

--- Lists all airport-category areas.
---@return AgentArea[]
function Agent.getAirports()
    return Agent.listAreas({ category = "airport" })
end

--- Finds an airport area by its exact id (alias of Agent.findAreaById).
---@param airportId string
---@return AgentArea|nil
function Agent.findAirportById(airportId)
    return Agent.findAreaById(airportId)
end

--- Finds the closest airport (or a specific airport by id) to a 3D position.
---@param x number
---@param y number
---@param z number
---@param airportId string|nil When provided, resolves this exact area instead of searching by category.
---@return AgentArea|nil area
---@return number|string|nil distanceOrErr Rounded distance on success, error message on failure.
function Agent.findClosestAirport(x, y, z, airportId)
    local options = {}
    if airportId then
        options.locationId = airportId
    else
        options.category = "airport"
    end
    return Agent.findClosestArea(x, y, z, options)
end

--- Builds a full area map summary: total count, counts by category/region, and the full area list.
---@return AgentAreaMap
function Agent.getAreaMap()
    local categories = {}
    local regions = {}

    for i = 1, #Agent.AREAS do
        local area = Agent.AREAS[i]
        categories[area.category] = (categories[area.category] or 0) + 1
        regions[area.region] = (regions[area.region] or 0) + 1
    end

    return {
        total = #Agent.AREAS,
        categories = categories,
        regions = regions,
        areas = Agent.listAreas({}),
    }
end
