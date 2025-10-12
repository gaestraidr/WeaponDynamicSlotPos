// BuyMenu_Classes.as
// Contains player class definitions for the BuyMenu system.

namespace BuyMenu
{

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

void RestoreWeapon(CBasePlayer@ pPlayer, const string &in szName)
{
    if (pPlayer is null || !pPlayer.IsConnected() || pPlayer.edict() is null)
        return;

    pPlayer.GiveNamedItem( szName );
}

void OnConfirmHUDModeMenu(CTextMenu@ menu, CBasePlayer@ pPlayer, int iSlot, const CTextMenuItem@ pItem)
{
    if (pItem is null) return;

    int hudMode;
    if (!pItem.m_pUserData.retrieve(hudMode)) return;

    
    g_PlayerFuncs.ClientPrint( pPlayer, HUD_PRINTTALK, 
        BuyMenuPrefix + " Selected HUD Mode: " + ( hudMode == 1 ? "Vanilla HUD [HL/SC]" : "ABCEnchance [MetaHook] (Reconnect if its not working)")  + "\n" );
    
    PlayerLoadout@ loadout = GetLoadout(pPlayer);
    if (hudMode == 1 && int(g_PlayerHUDSettings[PlayerID(pPlayer)]) != 1) {
        loadout.ForceVanillaWeaponToPosGraveyard();
        loadout.ResendPosition();
    }

    g_PlayerHUDSettings[PlayerID(pPlayer)] = hudMode;
    SaveSettingsToFile();
}

// --- CLASS DEFINITIONS ---

// Rewritten by: Sh[A]rkMode
// Description: 
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

    // === AMMO INFO ===
    private dictionary m_AmmoNameIndex; // classname -> ammo index
    private array<bool> m_AmmoPosIndex; // [index] availability

    private CTextMenu@ m_pUserTextMenu = null;
    private CTextMenu@ m_pOldUserTextMenu = null;

    bool m_NewlyCreated = true;

    dictionary m_PickupCache;
    int m_SnapshotCalledCount = 0;
    bool m_ReadyState = false;
    bool m_InitRefreshed = false;
    bool m_HasRefreshed = false;
    float m_NextCacheCleanUp = 0.0f;

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
        {
            m_pUserTextMenu.Unregister();
        }
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

        array<string> weaponKeys = m_WeaponPos.getKeys();
        if (weaponKeys.length() == 0)
            return;

        // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, BuyMenuPrefix + " Executing refresh inventory...\n" );
        
        // Try to snapshot first
        Snapshot("");

        // Check Existing first
        for (uint i = 0; i < weaponKeys.length(); i++)
        {
            string wepName = weaponKeys[i];
            CBaseEntity@ pEnt = m_pPlayer.DropItem(wepName);
            g_EntityFuncs.Remove(pEnt);

            // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, BuyMenuPrefix + " Removing: " + wepName + "\n" );
        }

        m_TempWeaponKeys = weaponKeys;
        Snapshot("");

        ResetEdict();
    }

    void Restore()
    {
        if (m_pPlayer is null || !m_pPlayer.IsConnected() || m_pPlayerEdict is null)
            return;

        // Its needed because somehow the server engine send multiple same entity weapon to client for no reason at all....
        // Nevermind weapon like satchel needs multiple time give...
        // dictionary seenItems;
        array<string> wpKeys = m_TempWeaponKeys;
        for (uint i = 0; i < wpKeys.length(); i++)
        {
            string wepName = wpKeys[i];
            // if (seenItems.exists(wepName))
            //     continue;
            
            // seenItems[wepName] = true;
            if (m_WeaponPos.exists(wepName)) {
                // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, BuyMenuPrefix + " Sending: " + wepName + "\n" );

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

            // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, BuyMenuPrefix + " Adding: " + wepName + "\n" );
        }

        m_TempWeaponKeys.removeRange(0, m_TempWeaponKeys.length());
        ResetHUDClient();
    }

    void CleanCachePickup() { m_PickupCache.deleteAll(); m_NextCacheCleanUp = g_Engine.time + 0.25f; }
    bool WasInCachePickup(const string &in szWeapName) { return m_PickupCache.exists(szWeapName); }
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

    void ResetState() 
    { 
        m_TempWeaponKeys.removeRange(0, m_TempWeaponKeys.length());
        m_PickupCache.deleteAll();

        m_SnapshotCalledCount = 0;
        m_ReadyState = false;
        m_InitRefreshed = false;
        m_HasRefreshed = false;
        m_NextCacheCleanUp = 0.0f;
    }

    void Reset(CBasePlayer@ pPlayer)
    {
        if (pPlayer !is null) {
            @m_pPlayer = pPlayer;
            @m_pPlayerEdict = pPlayer.edict();
        }

        ResetState();
        ResetEdict();
    }

    void Snapshot(const string &in szForceName)
    {
        if (m_pPlayer is null || !m_pPlayer.IsConnected() || m_pPlayerEdict is null)
            return;

        if (int(g_PlayerHUDSettings[PlayerID(m_pPlayer)]) == 2)
            return;

        // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, BuyMenuPrefix + " Snapshotting...\n" );
        // snapshot inventory
        dictionary curInv;
        for (int i = 0; i < MAX_ITEM_TYPES; i++)
        {
            CBasePlayerItem@ pItem = m_pPlayer.m_rgpPlayerItems(i);
            while (pItem !is null)
            {
                string szName = pItem.pszName();
                if (g_Ins2MenuItemList.find(szName) >= 0)
                    curInv[szName] = true;

                @pItem = GetNextItem(pItem);
            }
        }

        bool invChanged = false;

        // detect drops
        array<string> oldKeys = m_WeaponPos.getKeys();
        for (uint i = 0; i < oldKeys.length(); i++)
        {
            if (!curInv.exists(oldKeys[i])) {
                OnDrop(oldKeys[i]);
                invChanged = true;
            }
        }

        if (!szForceName.IsEmpty()) {
            m_PickupCache[szForceName] = true;
            curInv[szForceName] = true;
        }

        // detect pickups
        array<string> curKeys = curInv.getKeys();
        for (uint i = 0; i < curKeys.length(); i++)
        {
            if (!m_WeaponPos.exists(curKeys[i])) {
                OnPickup(curKeys[i]);
                invChanged = true;
            }
        }

        if (invChanged) {
            m_SnapshotCalledCount++;
            // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, "Snapshot Called Count: " + m_SnapshotCalledCount + "\n" );
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

    void ResetHUDClient()
    {
        SendResetHUD();
        ResendAmmoHUD();
    }

    void ResendAmmoHUD()
    {
        array<string> weapList = m_WeaponPos.getKeys();
        for (uint i = 0; i < weapList.length(); i++) {
            if (m_pPlayer is null || !m_pPlayer.IsConnected() || m_pPlayerEdict is null)
                return;

            if (int(g_PlayerHUDSettings[PlayerID(m_pPlayer)]) == 2)
                return;

            string wepName = weapList[i];

            ItemInfo II;
            if (!GetItemInfoByName(wepName, II))
                continue;
            
            int primAmmoI = g_PlayerFuncs.GetAmmoIndex(II.szAmmo1());
            if (primAmmoI >= 0) SendAmmoHUD(primAmmoI, m_pPlayer.m_rgAmmo(primAmmoI));
            int secAmmoI = g_PlayerFuncs.GetAmmoIndex(II.szAmmo2());
            if (secAmmoI >= 0) SendAmmoHUD(secAmmoI, m_pPlayer.m_rgAmmo(secAmmoI));
        }
    }

    void ForceAddWeapon(const string &in szName)
    {
        if (!m_ReadyState)
            m_TempWeaponKeys.insertLast(szName);
        else Snapshot(szName);
    }    

    void ForceVanillaWeaponToPosGraveyard(bool forceOwnedWeap = false)
    {
        // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, BuyMenuPrefix + " Sending GRAVEYARD list...\n" );
        if (int(g_PlayerHUDSettings[PlayerID(m_pPlayer)]) == 2)
            return;

        array<string> weaponKeys = m_WeaponPos.getKeys();
        for (uint i = 0; i < g_VanillaMapWeaponList.length(); i++) {
            string szName = g_VanillaMapWeaponList[i];
            if (weaponKeys.find(szName) >= 0 && !forceOwnedWeap)
                continue;

            ItemInfo info;
            if (GetItemInfoByName(szName, info)) {
                SendWeaponList(szName, info, info.iSlot, GRAVEYARD_POS_INDEX);
                // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, BuyMenuPrefix + " Throwing [" + szName + "] to pos GRAVEYARD...\n" );
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
            // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, BuyMenuPrefix + " Throwing [" + szName + "] to pos GRAVEYARD...\n" );
        }
    }

    void ShowHUDModeMenu()
    {
        SetPlayerTextMenu(CTextMenu(@OnConfirmHUDModeMenu));
        m_pUserTextMenu.SetTitle("What HUD Mod are you using right now?\\d");

        m_pUserTextMenu.AddItem("\\gVanilla HUD [HL/SC]\\d", any(1));
        m_pUserTextMenu.AddItem("\\yABCEnchance [MetaHook]\\d", any(2));
        
        m_pUserTextMenu.Register();
        m_pUserTextMenu.Open(0, 0, m_pPlayer);

        m_NewlyCreated = false;
    }

    private void OnPickup(const string &in szName)
    {
        ItemInfo II;
        if (!GetItemInfoByName(szName, II))
            return;

        // The preferred slot for this item
        int preferredSlot = II.iSlot;
        dictionary newLocation = AllocPos(preferredSlot);
        if (int(newLocation['pos']) < 0)
        {
            // No free position found on every slot, damn this guy saving arsenal for doomsday
            return;
        }

        int slot = int(newLocation["slot"]);
        int pos  = int(newLocation["pos"]);

        m_WeaponPos[szName] = formatInt(slot) + "," + formatInt(pos);

        SendWeaponList(szName, II, slot, pos + SLOTS_POS_START_INDEX);
        
        // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, BuyMenuPrefix + " You picked up: " + szName + " in slot [" + slot + "] pos [" + pos +"].\n" );
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

        // g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTTALK, BuyMenuPrefix + " You dropped: " + szName + " in slot [" + slot + "] pos [" + pos +"].\n" );
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

    private dictionary AllocPos(int initialSlot)
    {
        // Create a dictionary to return both the slot and position.
        dictionary result;

        // The outer loop iterates through all possible slots exactly once.
        // We assume MAX_ITEM_TYPES is the total number of weapon slots (e.g., 10 for slots 0-9).
        for (int i = 0; i < MAX_ITEM_TYPES; i++)
        {
            // Calculate the current slot to check using the modulo operator for circular logic.
            // Example: if initialSlot is 8, the sequence will be 8, 9, 0, 1, 2, ... , 7
            int currentSlot = (initialSlot + i) % MAX_ITEM_TYPES;

            // The inner loop checks for a free position within the current slot.
            for (int pos = 0; pos < MAX_ITEM_SLOTS_POS; pos++)
            {
                // If we find a free position...
                if (!m_FreePos[currentSlot][pos])
                {
                    // Mark it as used.
                    m_FreePos[currentSlot][pos] = true;
                    result["slot"] = currentSlot;
                    result["pos"] = pos;
                    
                    // Return the result immediately.
                    return result;
                }
            }
        }

        // If the outer loop completes, it means we have checked every position
        // in every slot and found nothing. The inventory is completely full.
        result["slot"] = initialSlot;
        result["pos"] = -1;
        return result; // Return pos -1 to signal failure.
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

        if (int(g_PlayerHUDSettings[PlayerID(m_pPlayer)]) == 2)
            return;

        // HUD Weapon List Payload
        NetworkMessage msg(MSG_ONE, NetworkMessages::WeaponList, m_pPlayerEdict);
            msg.WriteString(szName);
            msg.WriteByte(g_PlayerFuncs.GetAmmoIndex(II.szAmmo1()));
            msg.WriteLong(II.iMaxAmmo1);   // SC uses long
            msg.WriteByte(g_PlayerFuncs.GetAmmoIndex(II.szAmmo2()));
            msg.WriteLong(II.iMaxAmmo2);   // SC uses long
            msg.WriteByte(slot);
            msg.WriteByte(pos);
            msg.WriteShort(II.iId);        // SC uses short
            msg.WriteByte(II.iFlags | 1);
        msg.End();
    }

    private void SendResetHUD()
    {
        if (m_pPlayer is null || !m_pPlayer.IsConnected() || m_pPlayerEdict is null)
            return;

        if (int(g_PlayerHUDSettings[PlayerID(m_pPlayer)]) == 2)
            return;

        NetworkMessage msg(MSG_ONE, NetworkMessages::ResetHUD, m_pPlayerEdict);
            msg.WriteByte(0);
        msg.End();
    }

    private void SendAmmoHUD(int iAmmoIndex, int iAmount)
    {
        if (m_pPlayer is null || !m_pPlayer.IsConnected() || m_pPlayerEdict is null)
            return;

        if (int(g_PlayerHUDSettings[PlayerID(m_pPlayer)]) == 2)
            return;

        NetworkMessage msg(MSG_ONE, NetworkMessages::AmmoX, m_pPlayerEdict);
            // Ammo index 
            msg.WriteByte(iAmmoIndex);
            // Ammo amount
            msg.WriteLong(iAmount);
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


} // End of namespace BuyMenu