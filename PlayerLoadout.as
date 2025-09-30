

enum HUDMODE
{
    HUD_NONE_SELECTED,
    HUD_VANILLA_HLSC,
    HUD_ABC_ENCHANCE
};

// --- UTILS ---
bool GetItemInfoByName(const string &in szName, ItemInfo& out info)
{
    CBaseEntity@ pEnt = g_EntityFuncs.CreateEntity(szName, null, false);
    CBasePlayerWeapon@ pWeapon = cast<CBasePlayerWeapon@>(pEnt);

    if (pWeapon is null)
        return false;

    bool result = pWeapon.GetItemInfo(info);

    g_EntityFuncs.Remove(pWeapon);

    return result;
}

string PlayerID( CBasePlayer@ pPlayer )
{
	return g_EngineFuncs.GetPlayerAuthId( pPlayer.edict() );
}

PlayerLoadout@ GetLoadout(CBasePlayer@ pPlayer)
{
    if (pPlayer is null)
        return null;

    return GetLoadoutByAuthID(PlayerID(pPlayer), pPlayer);
}

PlayerLoadout@ GetLoadoutByAuthID(const string& in szAuthId, CBasePlayer@ pPlayer)
{
	if (!g_PlayerLoadouts.exists(szAuthId))
    {
        PlayerLoadout@ newLoadout = PlayerLoadout(pPlayer);
        g_PlayerLoadouts.set(szAuthId, @newLoadout);
        return newLoadout;
    }

    PlayerLoadout@ loadout = cast<PlayerLoadout@>(g_PlayerLoadouts[szAuthId]);
    return loadout;
}

const string SETTINGS_FILENAME = "scripts/plugins/store/hudmode_player_setting.txt"; 
void SaveSettingsToFile()
{
	File@ f = g_FileSystem.OpenFile(SETTINGS_FILENAME, OpenFile::WRITE);
	if (f is null)
	{
		g_EngineFuncs.ServerPrint("[WDSP] Could not open " + SETTINGS_FILENAME + " for writing!\n");
		return;
	}

	array<string> playerIDs = g_PlayerHUDSettings.getKeys();
	for (uint i = 0; i < playerIDs.length(); i++)
	{
		string id = playerIDs[i];
		int hudMode = int(g_PlayerHUDSettings[id]);
		
		// Write the line: e.g., "76561198000000001=false"
		f.Write(id + "=" + hudMode + "\n");
	}

	f.Close();
}

void LoadSettingsFromFile()
{
	g_PlayerHUDSettings.deleteAll(); // Clear current settings before loading

	File@ f = g_FileSystem.OpenFile(SETTINGS_FILENAME, OpenFile::READ);
	if (f is null)
	{
		g_EngineFuncs.ServerPrint("[WDSP] Settings file not found. A new one will be created.\n");
		return;
	}

	while (!f.EOFReached())
	{
		string line = "";
		f.ReadLine(line);
		if (line.Length() == 0) continue;

		array<string> parts = line.Split("=");
		if (parts.length() == 2)
		{
			string id = parts[0];
			int hudMode = atoi(parts[1]);
			g_PlayerHUDSettings[id] = hudMode;
		}
	}

	f.Close();
}

void RestoreWeapon(CBasePlayer@ pPlayer, const string &in szName)
{
    if (pPlayer is null || !pPlayer.IsConnected() || pPlayer.edict() is null)
        return;

    pPlayer.GiveNamedItem( szName );
}

void OnConfirmHUDModeMenu(CTextMenu@ menu, CBasePlayer@ pPlayer, int iSlot, const CTextMenuItem@ pItem)
{
    if (pItem is null) return;

    int hudModeType;
    if (!pItem.m_pUserData.retrieve(hudModeType)) return;

    HUDMODE hudMode = HUDMODE(hudModeType);
    g_PlayerFuncs.ClientPrint( pPlayer, HUD_PRINTTALK, 
        "[WDSP] Selected HUD Mode: " + ( hudMode == HUD_VANILLA_HLSC ? "Vanilla HUD [HL/SC]" : "ABCEnchance [MetaHook] (Reconnect if its not working)")  + "\n" );
    
    PlayerLoadout@ loadout = GetLoadout(pPlayer);
    if (hudMode == HUD_VANILLA_HLSC && HUDMODE(int(g_PlayerHUDSettings[PlayerID(pPlayer)])) != HUD_VANILLA_HLSC) {
        loadout.ForceAllWeaponToPosGraveyard();
        loadout.ResendPosition();
    }

    g_PlayerHUDSettings[PlayerID(pPlayer)] = hudMode;
    SaveSettingsToFile();
}

// --- CLASS DEFINITIONS ---

// This class PlayerLoadout, is used to manipulate weapon HUD position to make the list filling dynamic instead of static typed position,
// this is a workaround the engine limit until the SC Dev implemented a new better inventory system...

const int GRAVEYARD_POS_INDEX = 0;
const int SLOTS_POS_START_INDEX = 1;
const int MAX_ITEM_SLOTS_POS = 24;
class PlayerLoadout
{
    private CBasePlayer@ m_pPlayer;
    private edict_t@ m_pPlayerEdict;

    // === WEAPON INFO ===
    private dictionary m_WeaponPos; // classname -> {slot,pos}
    private array<string> m_TempWeaponKeys;
    private array<array<bool>> m_FreePos; // [slot][pos] availability

    // === AMMO INFO === [Need AmmoInfo exposed...]
    // private dictionary m_AmmoNameIndex; // classname -> ammo index
    // private array<bool> m_AmmoPosIndex; // [index] availability

    private CTextMenu@ m_pUserTextMenu = null;
    private CTextMenu@ m_pOldUserTextMenu = null;

    bool m_NewlyCreated = true;

    bool m_pGraveyardSent = false;
    bool m_ReadyState = false;
    bool m_InitRefreshed = false;
    bool m_HasRefreshed = false;

    // === GET SETTER ===
    // Gets the player associated with this object.
    CBasePlayer@ GetPlayer()
    {
        return @m_pPlayer;
    }

    // Sets the player for this object, with a null check.
    void SetPlayer(CBasePlayer@ pNewPlayer)
    {
        if (pNewPlayer !is null)
        {
            @m_pPlayer = pNewPlayer;
            @m_pPlayerEdict = pNewPlayer.edict();
        }
    }

    // Gets the player edict associated with this object.
    edict_t@ GetPlayerEdict()
    {
        return @m_pPlayerEdict;
    }

    // Sets the player edict for this object, with a null check.
    void SetPlayerEdict(edict_t@ pNewEdict)
    {
        if (pNewEdict !is null)
        {
            @m_pPlayerEdict = pNewEdict;
        }
    }

    // Gets the text menu associated with this object.
    CTextMenu@ GetPlayerTextMenu()
    {
        return @m_pUserTextMenu;
    }

    void UnregisterTextMenu()
    {
        if (m_pUserTextMenu !is null && m_pUserTextMenu.IsRegistered())
            m_pUserTextMenu.Unregister();
    }

    // Sets the text menu, automatically unregistering the old one if it exists.
    void SetPlayerTextMenu(CTextMenu@ pNewMenu)
    {
        // Important: Clean up the old menu before assigning a new one
        // to prevent orphaned/unusable menu registrations.
        UnregisterTextMenu();
        
        @m_pOldUserTextMenu = m_pUserTextMenu;
        @m_pUserTextMenu = pNewMenu;
    }
    // #endregion

    PlayerLoadout(CBasePlayer@ pPlayer)
    {
        if (pPlayer !is null) {
            @m_pPlayer = pPlayer;
            @m_pPlayerEdict = pPlayer.edict();
        }

        ResetEdict();
    }
    
    void Refresh()
    {
        if (m_pPlayer is null || !m_pPlayer.IsConnected() || m_pPlayerEdict is null)
            return;

        if (HUDMODE(int(g_PlayerHUDSettings[PlayerID(m_pPlayer)])) == HUD_ABC_ENCHANCE)
            return;

        array<string> weaponKeys = m_WeaponPos.getKeys();
        if (weaponKeys.length() == 0)
            return;

        // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, "Executing refresh inventory...\n" );
        
        // Try to snapshot first
        Snapshot("");

        // Check Existing first
        for (uint i = 0; i < weaponKeys.length(); i++)
        {
            string wepName = weaponKeys[i];
            CBaseEntity@ pEnt = m_pPlayer.DropItem(wepName);
            g_EntityFuncs.Remove(pEnt);

            // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, "Removing: " + wepName + "\n" );
        }

        m_TempWeaponKeys = weaponKeys;
        Snapshot("");

        ResetEdict();
    }

    void Restore()
    {
        if (HUDMODE(int(g_PlayerHUDSettings[PlayerID(m_pPlayer)])) == HUD_ABC_ENCHANCE)
            return;

        // Its needed because somehow the server engine send multiple same entity weapon to client for no reason at all....
        // Nevermind weapon like satchel needs multiple time give...
        // dictionary seenItems;
        array<string> wpKeys = m_TempWeaponKeys;
        for (uint i = 0; i < wpKeys.length(); i++)
        {
            if (m_pPlayer is null || !m_pPlayer.IsConnected() || m_pPlayerEdict is null)
                break;

            string wepName = wpKeys[i];
            // if (seenItems.exists(wepName))
            //     continue;
            
            // seenItems[wepName] = true;
            if (m_WeaponPos.exists(wepName)) {
                // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, "Sending: " + wepName + "\n" );

                ItemInfo II;
                if (!GetItemInfoByName(wepName, II))
                    continue;
                
                string packed;
                m_WeaponPos.get(wepName, packed);

                array<string> parts = packed.Split(",");
                int slot = atoi(parts[0]);
                int pos  = atoi(parts[1]);

                SendWeaponList(wepName, II, slot, pos + SLOTS_POS_START_INDEX);
            }
            else OnPickup(wepName);

            // give weapon back
            m_pPlayer.SetItemPickupTimes( 0.0 );
            m_pPlayer.GiveNamedItem( wepName );
            m_pPlayer.SelectItem( wepName );

            // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, "Adding: " + wepName + "\n" );
        }

        m_TempWeaponKeys.removeRange(0, m_TempWeaponKeys.length());
    }

    bool HasWeaponQueued() { return m_TempWeaponKeys.length() > 0; }
    void RestoreIterate()
    {
        if (m_pPlayer is null || !m_pPlayer.IsConnected() || m_pPlayerEdict is null)
            return;

        if (HasWeaponQueued()) {
            string wepName = m_TempWeaponKeys[0];

            if (m_WeaponPos.exists(wepName)) {
                ItemInfo II;
                if (GetItemInfoByName(wepName, II)) {
                    string packed;
                    m_WeaponPos.get(wepName, packed);

                    array<string> parts = packed.Split(",");
                    int slot = atoi(parts[0]);
                    int pos  = atoi(parts[1]);
                    int posABC  = atoi(parts[2]);

                    SendWeaponList(wepName, II, slot, pos + SLOTS_POS_START_INDEX);
                }
            }
            else OnPickup(wepName);

            // give weapon back
            m_pPlayer.SetItemPickupTimes( 0.0 );
            m_pPlayer.GiveNamedItem( wepName );
            m_pPlayer.SelectItem( wepName );

            m_TempWeaponKeys.removeAt(0);
        }
    }    

    void ResetSpawnItemList() { m_TempWeaponKeys.removeRange(0, m_TempWeaponKeys.length()); }
    void Reset(CBasePlayer@ pPlayer)
    {
        if (pPlayer !is null) {
            @m_pPlayer = pPlayer;
            @m_pPlayerEdict = pPlayer.edict();
        }

        m_ReadyState = false;
		m_InitRefreshed = false;
		m_HasRefreshed = false;

        ResetEdict();
    }

    void Snapshot(const string &in szForceName)
    {
        if (m_pPlayer is null || !m_pPlayer.IsConnected() || m_pPlayerEdict is null)
            return;

        if (HUDMODE(int(g_PlayerHUDSettings[PlayerID(m_pPlayer)])) == HUD_ABC_ENCHANCE)
            return;

        // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, "Snapshotting...\n" );
        // snapshot inventory
        dictionary curInv;
        if (!szForceName.IsEmpty())
            curInv[szForceName] = true;

        for (int i = 0; i < MAX_ITEM_TYPES; i++)
        {
            CBasePlayerItem@ pItem = m_pPlayer.m_rgpPlayerItems(i);
            while (pItem !is null)
            {
                string szName = pItem.pszName();
                if (g_WeaponKnownItemList.find(szName) >= 0)
                    curInv[szName] = true;

                @pItem = GetNextItem(pItem);
            }
        }

        // detect pickups
        array<string> curKeys = curInv.getKeys();
        for (uint i = 0; i < curKeys.length(); i++)
        {
            if (!m_WeaponPos.exists(curKeys[i]))
                OnPickup(curKeys[i]);
        }

        // detect drops
        array<string> oldKeys = m_WeaponPos.getKeys();
        for (uint i = 0; i < oldKeys.length(); i++)
        {
            if (!curInv.exists(oldKeys[i]))
                OnDrop(oldKeys[i]);
        }
    }

    void ResendPosition()
    {
        array<string> weapList = m_WeaponPos.getKeys();
        for (uint i = 0; i < weapList.length(); i++) {
            string wepName = weapList[i];

            ItemInfo II;
            if (!GetItemInfoByName(wepName, II))
                continue;
            
            string packed;
            m_WeaponPos.get(wepName, packed);

            array<string> parts = packed.Split(",");
            int slot = atoi(parts[0]);
            int pos  = atoi(parts[1]);

            SendWeaponList(wepName, II, slot, pos + SLOTS_POS_START_INDEX);
        }
    }

    void ForceAddWeapon(const string &in szName)
    {
        if (!m_ReadyState)
            m_TempWeaponKeys.insertLast(szName);
        else Snapshot(szName);
    }    

    void ForceAllWeaponToPosGraveyard(bool forceOwnedWeap = false)
    {
        // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, "Sending GRAVEYARD list...\n" );
        if (HUDMODE(int(g_PlayerHUDSettings[PlayerID(m_pPlayer)])) == HUD_ABC_ENCHANCE)
            return;

        array<string> weaponKeys = m_WeaponPos.getKeys();
        for (uint i = 0; i < g_WeaponKnownItemList.length(); i++) {
            string szName = g_WeaponKnownItemList[i];
            if (weaponKeys.find(szName) >= 0 && !forceOwnedWeap)
                continue;

            ItemInfo info;
            if (GetItemInfoByName(szName, info)) {
                SendWeaponList(szName, info, info.iSlot, GRAVEYARD_POS_INDEX);
                // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, "Throwing [" + szName + "] to pos GRAVEYARD...\n" );
            }
        }

    }

    void ForceSpecificWeaponToPosGraveyard(const string &in szName)
    {
        ItemInfo II;
        if (GetItemInfoByName(szName, II)) {
            // Send them first to the client that found it
            SendWeaponList(szName, II, II.iSlot, GRAVEYARD_POS_INDEX);

            // Broadcast to all vanilla player
            for (int i = 1; i <= g_Engine.maxClients; ++i)
            {
                CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex(i);
                if (p is null || !p.IsConnected() || p.edict() is null)
                    continue;

                if (p.entindex() == m_pPlayer.entindex() || int(g_PlayerHUDSettings[PlayerID(p)]) == 2)
                    continue;
                
                NetworkMessage msg(MSG_ONE, NetworkMessages::WeaponList, p.edict());
                    msg.WriteString(szName);
                    msg.WriteByte(g_PlayerFuncs.GetAmmoIndex(II.szAmmo1()));
                    msg.WriteLong(II.iMaxAmmo1);   // SC uses long
                    msg.WriteByte(g_PlayerFuncs.GetAmmoIndex(II.szAmmo2()));
                    msg.WriteLong(II.iMaxAmmo2);   // SC uses long
                    msg.WriteByte(II.iSlot);
                    msg.WriteByte(GRAVEYARD_POS_INDEX);
                    msg.WriteShort(II.iId);        // SC uses short
                    msg.WriteByte(II.iFlags | 1);
                msg.End();
            }
            // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, "Throwing [" + szName + "] to pos GRAVEYARD...\n" );
        }
    }

    void ShowHUDModeMenu()
    {
        SetPlayerTextMenu(CTextMenu(@OnConfirmHUDModeMenu));
        m_pUserTextMenu.SetTitle("What HUD Mod are you using right now?\\d");

        m_pUserTextMenu.AddItem("\\gVanilla HUD [HL/SC]\\d", any(HUD_VANILLA_HLSC));
        m_pUserTextMenu.AddItem("\\yABCEnchance [MetaHook]\\d", any(HUD_ABC_ENCHANCE));
        
        m_pUserTextMenu.Register();
        m_pUserTextMenu.Open(0, 0, m_pPlayer);

        m_NewlyCreated = false;
    }

    private void OnPickup(const string &in szName)
    {
        ItemInfo II;
        if (!GetItemInfoByName(szName, II))
            return;

        int slot = II.iSlot;
        int pos = AllocPos(slot);
        if (pos < 0)
            // no free position
            return;

        m_WeaponPos[szName] = formatInt(slot) + "," + formatInt(pos);

        SendWeaponList(szName, II, slot, pos + SLOTS_POS_START_INDEX);
        
        // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, "You picked up: " + szName + " in slot [" + slot + "] pos [" + pos +"].\n" );
        // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, "Weapon: " + szName 
        //     + " | iAmmo1: " + g_PlayerFuncs.GetAmmoIndex(II.szAmmo1()) + " | iAmmo2: " + g_PlayerFuncs.GetAmmoIndex(II.szAmmo2()) +"\n" );
    }

    private void OnDrop(const string &in szName)
    {
        ItemInfo II;
        if (!GetItemInfoByName(szName, II))
            return;

        string packed;
        m_WeaponPos.get(szName, packed);

        array<string> parts = packed.Split(",");
        int slot = atoi(parts[0]);
        int pos  = atoi(parts[1]);

        FreePos(slot, pos);
        SendWeaponList(szName, II, slot, GRAVEYARD_POS_INDEX); // mark as hidden

        m_WeaponPos.delete(szName);

        // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, "You dropped: " + szName + " in slot [" + slot + "] pos [" + pos +"].\n" );
    }

    private void ResetEdict()
    {
        m_WeaponPos.deleteAll();
        m_FreePos.resize(MAX_ITEM_TYPES);
        for (int slot = 0; slot < MAX_ITEM_TYPES; slot++)
        {
            m_FreePos[slot].resize(MAX_ITEM_SLOTS_POS);
            for (int pos = 0; pos < MAX_ITEM_SLOTS_POS; pos++)
                m_FreePos[slot][pos] = false; // all free initially
        }
    }

    private int AllocPos(int slot)
    {
        for (int pos = 0; pos < MAX_ITEM_SLOTS_POS; pos++)
        {
            if (!m_FreePos[slot][pos] && pos != GRAVEYARD_POS_INDEX)
            {
                m_FreePos[slot][pos] = true;
                return pos;
            }
        }
        return -1; // no free position
    }

    private void FreePos(int slot, int pos)
    {
        if (slot >= 0 && slot < int(m_FreePos.length()) &&
            pos >= 0 && pos < int(m_FreePos[slot].length()))
        {
            m_FreePos[slot][pos] = false;
        }
    }

    private void SendWeaponList(const string &in szName, ItemInfo &in II, int slot, int pos)
    {
        if (m_pPlayer is null || !m_pPlayer.IsConnected() || m_pPlayerEdict is null)
            return;

        if (HUDMODE(int(g_PlayerHUDSettings[PlayerID(m_pPlayer)])) == HUD_ABC_ENCHANCE)
            return;

        // HUD Weapon List Payload
        NetworkMessage msg(MSG_ONE, NetworkMessages::WeaponList, m_pPlayerEdict);
            msg.WriteString(szName);
            msg.WriteByte(g_PlayerFuncs.GetAmmoIndex(II.szAmmo1()));
            // msg.WriteByte(g_PlayerFuncs.GetAmmoIndex(II.szAmmo1()) != -1 ? 1 : -1);
            msg.WriteLong(II.iMaxAmmo1);   // SC uses long
            msg.WriteByte(g_PlayerFuncs.GetAmmoIndex(II.szAmmo2()));
            // msg.WriteByte(g_PlayerFuncs.GetAmmoIndex(II.szAmmo2()) != -1 ? 1 : -1);
            msg.WriteLong(II.iMaxAmmo2);   // SC uses long
            msg.WriteByte(slot);
            msg.WriteByte(pos);
            msg.WriteShort(II.iId);        // SC uses short
            msg.WriteByte(II.iFlags);
        msg.End();
    }

    private CBasePlayerItem@ GetNextItem(CBasePlayerItem@ pItem)
    {
        if (pItem is null)
            return null;

        EHandle hNext = pItem.m_hNextItem;
        if (hNext.IsValid())
            return cast<CBasePlayerItem@>(hNext.GetEntity());

        return null;
    }
}
