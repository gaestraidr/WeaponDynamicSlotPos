#include "PlayerLoadout"
#include "Misc"

void PluginInit()
{
	g_Module.ScriptInfo.SetAuthor( "Sh[A]rkMode (GaestraIDR)" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/gaestraidr" );

	g_Hooks.RegisterHook( Hooks::Player::ClientConnected, @WDSP_ClientConnected );
	g_Hooks.RegisterHook( Hooks::Player::ClientPutInServer, @WDSP_ClientPutInServer );
	g_Hooks.RegisterHook( Hooks::PickupObject::CanCollect, @WDSP_CanCollect );
	g_Hooks.RegisterHook( Hooks::Game::MapChange, @WDSP_MapChange );

	g_Hooks.RegisterHook( Hooks::Player::PlayerRevived, @WDSP_PlayerRevived );
	g_Hooks.RegisterHook( Hooks::Player::PlayerPostThink, @WDSP_PlayerPostThink );
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @WDSP_ClientSay );

    LoadSettingsFromFile();
    LoadWeaponListFromFile();
	g_WeaponKnownItemList = GetRegisteredEntries();
	lastSizeChange = g_WeaponKnownItemList.length();

    g_EngineFuncs.ServerPrint("[WDSP] Running!\n");
}

dictionary g_PlayerLoadouts;
dictionary g_PlayerHUDSettings;
array<string> g_WeaponKnownItemList;
uint lastSizeChange = 0;

void MapInit()
{
    g_Scheduler.SetTimeout("ScanMapEntityWeapon", 1.0f);
}

void ScanMapEntityWeapon()
{
	g_EngineFuncs.ServerPrint("[WDSP] Scanning map for entry list...\n");
	array<string> allMapEntities = GetAllWeaponEntitiesInMap();
    for (uint i = 0; i < allMapEntities.length(); i++) 
    {
        string weaponName = allMapEntities[i];
        if (g_WeaponKnownItemList.find(weaponName) < 0)
        {
            g_EngineFuncs.ServerPrint("[WDSP] Discovered: " + weaponName + "\n");
            g_WeaponKnownItemList.insertLast(weaponName);
        }
    }
}

// --- GAME ENGINE HOOKS ---

HookReturnCode WDSP_MapChange( const string& in szNextMap )
{
	if (g_WeaponKnownItemList.length() != lastSizeChange) {
		g_EngineFuncs.ServerPrint("[WDSP] Storing weapon entry list...\n");
		g_WeaponKnownItemList.sortAsc();
		lastSizeChange = g_WeaponKnownItemList.length();
		SaveWeaponListToFile(g_WeaponKnownItemList);
	}
	return HOOK_CONTINUE;
}

HookReturnCode WDSP_ClientConnected( edict_t@ pEdict, const string& in szPlayerName, const string& in szIPAddress, bool& out bDisallowJoin, string& out szRejectReason )
{
	string authId = g_EngineFuncs.GetPlayerAuthId( pEdict );
	PlayerLoadout@ loadout = GetLoadoutByAuthID(authId, null);
	if (loadout !is null) {
		loadout.ResetSpawnItemList();
		loadout.m_ReadyState = false;
		loadout.m_InitRefreshed = false;
		loadout.m_HasRefreshed = false;
	}

	return HOOK_CONTINUE;
}

HookReturnCode WDSP_ClientPutInServer( CBasePlayer@ pPlayer )
{
	if (pPlayer is null)
		return HOOK_CONTINUE;

	// Initialize loadout after spawning into the server
	PlayerLoadout@ loadout = GetLoadout(pPlayer);
	loadout.SetPlayer(pPlayer);

	if (HUDMODE(int(g_PlayerHUDSettings[PlayerID(pPlayer)])) == HUD_NONE_SELECTED) {
		loadout.ShowHUDModeMenu();
        g_PlayerFuncs.ClientPrint( pPlayer, HUD_PRINTTALK, "[WDSP] Type [!togglehudslot] to choose Weapon HUD Slot Mode. [!!IMPORTANT!! for ABCEnchance]\n" );
	}
    else {
		g_PlayerFuncs.ClientPrint( pPlayer, HUD_PRINTTALK, 
        	"[WDSP] Selected HUD Mode: " + ( int(g_PlayerHUDSettings[PlayerID(pPlayer)]) == 2 ? "ABCEnchance [MetaHook]" : "Vanilla HUD [HL/SC]")  + "\n" );
	}

	// Should be ready to send payload in this frame
	loadout.m_ReadyState = true;

	return HOOK_CONTINUE;
}

const int SF_ITEM_USE_ONLY = 256;
HookReturnCode WDSP_CanCollect( CBaseEntity@ pPickup, CBaseEntity@ pOther, bool& out bResult )
{
	// Item only interactable with +use, ignore it
	if ((pPickup.pev.spawnflags & SF_ITEM_USE_ONLY) != 0)
		return HOOK_CONTINUE;

	// Make sure it's a player collecting
    CBasePlayer@ pPlayer = cast<CBasePlayer@>(pOther);
    if (pPlayer is null || pPlayer.edict() is null)
        return HOOK_CONTINUE;
	
    // Make sure the pickup is a weapon
    CBasePlayerWeapon@ pWeapon = cast<CBasePlayerWeapon@>(pPickup);
    if (pWeapon is null)
        return HOOK_CONTINUE;

	// Make sure loadout is available
	PlayerLoadout@ loadout = GetLoadout(pPlayer);
	if (loadout is null || HUDMODE(int(g_PlayerHUDSettings[PlayerID(pPlayer)])) == HUD_ABC_ENCHANCE)
		return HOOK_CONTINUE;

	if (loadout.m_InitRefreshed && !loadout.m_HasRefreshed)
		return HOOK_CONTINUE;

	// Just precaution for segmentation fault
	if (!loadout.m_ReadyState)
		loadout.SetPlayer(pPlayer);

    // Probably won't be needed as we already got CBasePlayerWeapon, just to be sure
    string szName = pWeapon.pszName();
	if (szName.StartsWith("weapon_")) {
        // Auto discover new weapon being picked up to the list
		if (g_WeaponKnownItemList.find(szName) < 0) {
			g_WeaponKnownItemList.insertLast(szName);
			loadout.ForceSpecificWeaponToPosGraveyard(szName);
		}

		if (loadout.m_ReadyState) 
			loadout.Snapshot("");

		loadout.ForceAddWeapon(szName);
		bResult = loadout.m_ReadyState;
		if (loadout.m_ReadyState && HUDMODE(int(g_PlayerHUDSettings[PlayerID(pPlayer)])) == HUD_NONE_SELECTED) {
			g_PlayerFuncs.ClientPrint( pPlayer, HUD_PRINTTALK, "[WDSP] Type [!togglehudslot] if the weapon sprite not showing / can't be selected in HUD!\n" );
		}
	}
	
	return HOOK_CONTINUE; // allow pickup to proceed normally
}

HookReturnCode WDSP_PlayerRevived( CBasePlayer@ pPlayer )	
{ 
	if (pPlayer is null || !pPlayer.IsConnected() || pPlayer.edict() is null)
		return HOOK_CONTINUE;

	PlayerLoadout@ loadout = GetLoadout(pPlayer);
    if (loadout is null)
		return HOOK_CONTINUE;

	if (loadout.m_InitRefreshed && !loadout.m_HasRefreshed) {
		g_Scheduler.SetTimeout("RestoreInv", 1.0f, @pPlayer);
	}

	return HOOK_CONTINUE;
}

HookReturnCode WDSP_PlayerPostThink( CBasePlayer@ pPlayer )
{
	if (pPlayer is null) 
		return HOOK_CONTINUE;

	PlayerLoadout@ loadout = GetLoadout(pPlayer);
    if (loadout !is null) {
		if (loadout.m_ReadyState && !loadout.m_InitRefreshed) {
			loadout.m_InitRefreshed = true;
			loadout.ForceAllWeaponToPosGraveyard(true);
			if (pPlayer.IsAlive()) {
				g_Scheduler.SetTimeout("RestoreInv", 1.0f, @pPlayer);
			}
		}
	}

	return HOOK_CONTINUE;
}

// void RefreshInv( CBasePlayer@ pPlayer )
// {
// 	if (pPlayer is null || !pPlayer.IsConnected() || pPlayer.edict() is null)
// 		return;

// 	if (!pPlayer.IsAlive() || int(g_PlayerHUDSettings[PlayerID(pPlayer)]) == 2)
// 		return;

// 	PlayerLoadout@ loadout = GetLoadout(pPlayer);
//     if (loadout !is null) {
// 		loadout.Snapshot("");
// 		g_Scheduler.SetTimeout("RestoreInv", 1.0f, @pPlayer);
// 	}
// }

void RestoreInv( CBasePlayer@ pPlayer )
{
	if (pPlayer is null || !pPlayer.IsConnected() || pPlayer.edict() is null)
		return;

	if (!pPlayer.IsAlive() || HUDMODE(int(g_PlayerHUDSettings[PlayerID(pPlayer)])) == HUD_ABC_ENCHANCE)
		return;

	PlayerLoadout@ loadout = GetLoadout(pPlayer);
	if (loadout is null)
		return;

	loadout.Restore();
	loadout.m_HasRefreshed = true;
}

HookReturnCode WDSP_ClientSay( SayParameters@ pParams )
{
	CBasePlayer@ pPlayer = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();
	string command = args.Arg(0).ToLowercase();

    // Handle the !togglehudslot command
    if (command == "!togglehudslot" || command == "/togglehudslot" || command == ".togglehudslot")
    {
        pParams.ShouldHide = true; // Hide the message from chat
		PlayerLoadout@ loadout = GetLoadout(pPlayer);

        if (args.ArgC() < 2)
        {
			loadout.ShowHUDModeMenu();
            return HOOK_CONTINUE;
        }
        
        string option = args.Arg(1).ToLowercase();
        string playerID = PlayerID(pPlayer);

        if (option == "1")
        {
			if (HUDMODE(int(g_PlayerHUDSettings[PlayerID(pPlayer)])) != HUD_VANILLA_HLSC) {
				loadout.ForceAllWeaponToPosGraveyard();
				loadout.ResendPosition();
			}

            g_PlayerHUDSettings[playerID] = HUD_VANILLA_HLSC;
            g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTTALK, "[WDSP] Selected HUD Mode: Vanilla HUD [HL/SC]\n");
        }
        else if (option == "2")
        {
            g_PlayerHUDSettings[playerID] = HUD_ABC_ENCHANCE;
            g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTTALK, "[WDSP] Selected HUD Mode: ABCEnchance [MetaHook] (Reconnect if its not working)\n");
        }
        else
        {
            g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTTALK, "[WDSP] Usage: !togglehudslot <mode> | 1=(Vanilla HUD [HL/SC]) 2=(ABCEnchance [MetaHook])\n");
            return HOOK_CONTINUE;
        }

        // Save the settings immediately after changing them
        SaveSettingsToFile();
        
        // Return here so the game doesn't process other buy commands
        return HOOK_CONTINUE;
    }
	
	return HOOK_CONTINUE;
}