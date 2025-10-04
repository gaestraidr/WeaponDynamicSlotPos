array<string> GetRegisteredEntries()
{
    return g_AllKnownWeaponEntitiesStored;
}

array<string> GetAllWeaponEntitiesInMap()
{
    // Create an empty array to store our results.
    array<string> weaponEntities;

    // Loop through every possible entity slot on the server.
    // We start at 1 because entity 0 is the worldspawn.
    for (int i = 1; i < g_Engine.maxEntities; ++i)
    {
        // Get the "edict" (entity data block) for the current index.
        edict_t@ pEdict = g_EntityFuncs.IndexEnt(i);

        // Check if the edict is valid and in use.
        // If it's null or marked as 'free', it's not an active entity, so we skip it.
        if (pEdict is null)
            continue;

        // Get the CBaseEntity object associated with this edict.
        CBaseEntity@ pEntity = g_EntityFuncs.Instance(pEdict);
        if (pEntity is null)
            continue;

        // The core of the logic: Check if the entity's classname starts with "weapon_".
        // The StartsWith() method is case-sensitive, which is what we want here.
        string szName = pEntity.pev.classname;
        if (!szName.StartsWith("weapon_"))
            continue;
        
        // Make sure its really a player item
        CBasePlayerItem@ pItem = cast<CBasePlayerItem@>(pEntity);
        if (pItem !is null) {
            weaponEntities.insertLast(szName);
        }
    }

    CBaseEntity@ ent = null;
    while ((@ent = g_EntityFuncs.FindEntityByClassname(ent, "weapon_*")) !is null)
    {
        string szName = ent.pev.classname;

        // Make sure its really a player item
        CBasePlayerItem@ pItem = cast<CBasePlayerItem@>(ent);
        if (pItem !is null) {
            weaponEntities.insertLast(szName);
        }
    }

    // Return the completed list of weapon entities.
    return weaponEntities;
}

array<string> g_AllKnownWeaponEntitiesStored;

const string WEAPON_LIST_FILENAME = "scripts/plugins/store/weapon_stored_list.txt"; 
void SaveWeaponListToFile(array<string> arListWeapon)
{
	File@ f = g_FileSystem.OpenFile(WEAPON_LIST_FILENAME, OpenFile::WRITE);
	if (f is null)
	{
		g_EngineFuncs.ServerPrint("[WDSP] Could not open " + WEAPON_LIST_FILENAME + " for writing!\n");
		return;
	}

	for (uint i = 0; i < arListWeapon.length(); i++)
	{
		// Write the line
		f.Write(arListWeapon[i] + "\n");
	}

	f.Close();
}

void LoadWeaponListFromFile()
{
	File@ f = g_FileSystem.OpenFile(WEAPON_LIST_FILENAME, OpenFile::READ);
	if (f is null)
	{
		g_EngineFuncs.ServerPrint("[WDSP] Weapon file not found. A new one will be created.\n");
		g_AllKnownWeaponEntitiesStored = GetFilteredDuplicate();
        SaveWeaponListToFile(g_AllKnownWeaponEntitiesStored);
	}
    else {
        while (!f.EOFReached())
        {
            string line = "";
            f.ReadLine(line);
            if (line.Length() == 0) continue;

            g_AllKnownWeaponEntitiesStored.insertLast(line);
        }

        f.Close();
    }
	
}

array<string> GetFilteredDuplicate()
{
    array<string> allKnownWeaponEntitiesFiltered;

    // Using dictionary for extremely fast lookups to track what already added.
    dictionary seenItems;
    for (uint i = 0; i < g_AllKnownWeaponEntitiesTyped.length(); i++) 
    {
        string weaponName = g_AllKnownWeaponEntitiesTyped[i];
        if (!seenItems.exists(weaponName))
        {
            // If it doesn't exist, it's the first time seen this name.
            // Add it to the clean, filtered list.
            allKnownWeaponEntitiesFiltered.insertLast(weaponName);
            seenItems[weaponName] = true;
        }
    }

    // To make the data much easier to work with and debug later.
    allKnownWeaponEntitiesFiltered.sortAsc();

    return allKnownWeaponEntitiesFiltered;
}

// Every weapon I could type manually, fell free to add some more yourself, don't worry about duplicating the entries
// You actually dont need to put anything new in here, aside of SCHL/OF weapon where the register is resided on the client.
// Since the plugin do auto-discovery if a player pickup a weapon thats not on the list, since custom weapon is never pre-registered in client
//
// NOTE: If you add a new name into this list, you need to the file "scripts/plugins/store/weapon_stored_list.txt" first, since it wont load this
//       after creating the file once.
const array<string> g_AllKnownWeaponEntitiesTyped = {
    // --- Half-Life 1 & Sven Co-op Weapons ---
    "weapon_9mmAR",
    "weapon_9mmhandgun",
    "weapon_357",
    "weapon_banana",
    "weapon_crowbar",
    "weapon_crossbow",
    "weapon_cycler",
    "weapon_ecrowbar",
    "weapon_egon",
    "weapon_gauss",
    "weapon_glock",         // Alias for 9mmhandgun
    "weapon_handgrenade",
    "weapon_hlhandgrenade", // Custom from Suspension
    "weapon_hornetgun",
    "weapon_m16",           // Often used instead of 9mmAR in custom maps
    "weapon_m16a2",
    "weapon_medkit",
    "weapon_minigun",
    "weapon_mp5",           // Alias for 9mmAR
    "weapon_python",        // Alias for 357
    "weapon_rpg",
    "weapon_satchel",
    "weapon_shotgun",
    "weapon_snark",
    "weapon_tripmine",
    "weapon_uzi",
    "weapon_uziakimbo",
    "weapon_wrench",

    // --- Opposing Force Weapons ---
    "weapon_displacer",
    "weapon_eagle",
    "weapon_grapple",
    "weapon_knife",
    "weapon_m249",
    "weapon_pipewrench",
    "weapon_saw",           // Alias for m249
    "weapon_shockrifle",
    "weapon_sniperrifle",
    "weapon_sporelauncher",

    // --- Common Counter-Strike Weapons ---
    "weapon_ak47",
    "weapon_awp",
    "weapon_deagle",
    "weapon_flashbang",
    "weapon_flamethrower",
    "weapon_g3sg1",
    "weapon_hegrenade",
    "weapon_m4a1",
    "weapon_mac10",
    "weapon_p90",
    "weapon_sg552",
    "weapon_smokegrenade",
    "weapon_tmp",
    "weapon_ump45",

    // --- They Hunger Weapons ---
    "weapon_shovel",        // Melee weapon
    "weapon_wrench",        // The custom wrench/spanner
    "weapon_umbrella",      // The iconic umbrella melee weapon
    "weapon_beretta",       // Beretta pistol
    "weapon_revolver",      // A custom .357 revolver
    "weapon_tommygun",      // The Thompson submachine gun
    "weapon_tnt",           // The custom dynamite/TNT
    "weapon_sniperrifle",   // The sniper rifle
    "weapon_flamethrower",  // They Hunger's flamethrower
    "weapon_skeleton",      // The skeleton that shoots projectiles
    "weapon_teddy",         // The explosive teddy bear

    // --- AoM: Director's Cut Weapons ---
    "weapon_colt",          // The custom Colt pistol
    "weapon_colt_akimbo",   // Dual Colts
    "weapon_mac10",         // Custom MAC-10
    "weapon_mac10_akimbo",  // Dual MAC-10s
    "weapon_goldengun",     // The iconic one-shot-kill Golden Gun
    "weapon_briefcase",     // Melee weapon
    "weapon_briefcase2",    // Another melee weapon (often a reskin)
    "weapon_pan",           // Frying pan melee weapon
    "weapon_p228",          // A custom P228 pistol
    "weapon_beretta",       // A custom Beretta M9
    "weapon_benelli",       // Benelli M3 shotgun
    "weapon_l85a2",         // L85A2 rifle
    "weapon_mp5k",          // MP5K SMG
    "weapon_deagle",        // AoM's version of the Desert Eagle
    "weapon_glock18",       // A custom Glock with burst/auto fire
    "weapon_anaconda",      // A powerful revolver

    // --- Poke646 Weapons ---
    "weapon_svd",           // SVD Dragunov sniper rifle
    "weapon_nailgun",       // The iconic Nailgun
    "weapon_jack",          // The Jack-in-the-box timed explosive
    "weapon_spanner",       // Spanner/Wrench melee weapon
    "weapon_akimbo",        // The dual pistols
    "weapon_rocket",        // A custom RPG variant
    "weapon_flamethrower",  // The Flamethrower
    "weapon_dynamite",      // Stick of dynamite

    // --- AfrikaKorps Weapons ---
    "weapon_357",
    "weapon_9mmAR",
    "weapon_9mmhandgun",
    "weapon_crowbar",
    "weapon_handgrenade",
    "weapon_rpg",
    "weapon_satchel",
    "weapon_sniperrifle",

};