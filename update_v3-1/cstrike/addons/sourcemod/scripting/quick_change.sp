#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2.0.0"

// ConVars
ConVar g_cvEnabled;
ConVar g_cvDeploySpeed;
ConVar g_cvAllowAllWeapons;
ConVar g_cvAutoQC;

// Per-player data
bool  g_bQCEnabled[MAXPLAYERS + 1];
float g_flLastShotTime[MAXPLAYERS + 1];
int   g_iLastShotWeapon[MAXPLAYERS + 1];
bool  g_bWaitingSwitch[MAXPLAYERS + 1];
bool  g_bSwitchedAway[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name        = "Point Blank Quick Change v2",
    author      = "Assistant",
    description = "QC otomatis - ganti senjata setelah tembak = cancel recovery",
    version     = PLUGIN_VERSION,
    url         = ""
};

public void OnPluginStart()
{
    g_cvEnabled         = CreateConVar("sm_qc_enabled",     "1",    "Aktifkan Quick Change", _, true, 0.0, true, 1.0);
    g_cvDeploySpeed     = CreateConVar("sm_qc_deploy",      "0.35", "Deploy time setelah QC (detik)", _, true, 0.05, true, 1.0);
    g_cvAllowAllWeapons = CreateConVar("sm_qc_allweapons",  "0",    "QC semua senjata (1) atau sniper/shotgun saja (0)", _, true, 0.0, true, 1.0);
    g_cvAutoQC          = CreateConVar("sm_qc_auto",        "0",    "Auto QC setelah tembak (1) atau manual ganti senjata (0)", _, true, 0.0, true, 1.0);

    RegConsoleCmd("sm_toggleqc", Command_ToggleQC, "Toggle QC on/off per pemain");

    HookEvent("weapon_fire", Event_WeaponFire);

    AutoExecConfig(true, "quick_change_v2");

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            OnClientPutInServer(i);
        }
    }

    PrintToServer("[QC] Point Blank Quick Change v%s loaded!", PLUGIN_VERSION);
}

public void OnClientPutInServer(int client)
{
    g_bQCEnabled[client]      = true;
    g_flLastShotTime[client]  = 0.0;
    g_iLastShotWeapon[client] = -1;
    g_bWaitingSwitch[client]  = false;
    g_bSwitchedAway[client]   = false;

    SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitchPost);
}

public void OnClientDisconnect(int client)
{
    g_bQCEnabled[client]     = false;
    g_bWaitingSwitch[client] = false;
    g_bSwitchedAway[client]  = false;
}

// ============================================================
// Toggle Command
// ============================================================

public Action Command_ToggleQC(int client, int args)
{
    if (client == 0) return Plugin_Handled;

    g_bQCEnabled[client] = !g_bQCEnabled[client];

    if (g_bQCEnabled[client])
        PrintToChat(client, "\x04[QC]\x01 Quick Change \x04AKTIF\x01 - Ganti senjata setelah tembak untuk cancel recovery!");
    else
        PrintToChat(client, "\x04[QC]\x01 Quick Change \x02NONAKTIF");

    return Plugin_Handled;
}

// ============================================================
// Event: Pemain Menembak
// ============================================================

public void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
        return;

    if (!g_bQCEnabled[client])
        return;

    // Dapatkan senjata yang ditembak
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon == -1) return;

    // Cek apakah senjata ini support QC
    if (!g_cvAllowAllWeapons.BoolValue && !IsQCWeapon(weapon))
        return;

    // Tandai: pemain baru menembak senjata ini
    g_flLastShotTime[client]  = GetGameTime();
    g_iLastShotWeapon[client] = EntIndexToEntRef(weapon);
    g_bWaitingSwitch[client]  = true;  // Menunggu pemain ganti senjata
    g_bSwitchedAway[client]   = false;

    // Kalau mode AUTO QC aktif
    if (g_cvAutoQC.BoolValue)
    {
        // Otomatis lakukan QC
        float qcDelay = 0.05;
        DataPack pack = new DataPack();
        pack.WriteCell(GetClientUserId(client));
        pack.WriteCell(EntIndexToEntRef(weapon));
        CreateTimer(qcDelay, Timer_AutoQC, pack, TIMER_DATA_HNDL_CLOSE);
    }
}

// ============================================================
// Hook: Pemain Ganti Senjata (MANUAL QC)
// ============================================================

public void OnWeaponSwitchPost(int client, int weapon)
{
    if (!g_cvEnabled.BoolValue || !g_bQCEnabled[client])
        return;

    if (!IsPlayerAlive(client))
        return;

    if (!g_bWaitingSwitch[client])
        return;

    float gameTime = GetGameTime();
    int lastWeapon = EntRefToEntIndex(g_iLastShotWeapon[client]);

    // Cek apakah masih dalam window QC (1 detik setelah tembak)
    if (gameTime - g_flLastShotTime[client] > 1.0)
    {
        // Terlalu lama, reset
        g_bWaitingSwitch[client] = false;
        g_bSwitchedAway[client]  = false;
        return;
    }

    if (lastWeapon == INVALID_ENT_REFERENCE || !IsValidEntity(lastWeapon))
    {
        g_bWaitingSwitch[client] = false;
        return;
    }

    // === STEP 1: Pemain ganti KE senjata lain (away dari senjata tembak) ===
    if (!g_bSwitchedAway[client] && weapon != lastWeapon)
    {
        g_bSwitchedAway[client] = true;

        // Percepat deploy senjata perantara (pisau/pistol)
        SpeedUpDeploy(weapon, 0.05);

        return;
    }

    // === STEP 2: Pemain ganti BALIK ke senjata asal ===
    if (g_bSwitchedAway[client] && weapon == lastWeapon)
    {
        // QC BERHASIL! Cancel recovery!
        float deploySpeed = g_cvDeploySpeed.FloatValue;
        SpeedUpRecovery(client, weapon, deploySpeed);

        // Reset state
        g_bWaitingSwitch[client] = false;
        g_bSwitchedAway[client]  = false;

        // Feedback ke pemain
        // PrintCenterText(client, "★ Quick Change! ★");

        return;
    }
}

// ============================================================
// Timer: Auto QC
// ============================================================

public Action Timer_AutoQC(Handle timer, DataPack pack)
{
    pack.Reset();

    int userid    = pack.ReadCell();
    int weaponRef = pack.ReadCell();

    int client = GetClientOfUserId(userid);
    if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    int weapon = EntRefToEntIndex(weaponRef);
    if (weapon == INVALID_ENT_REFERENCE || !IsValidEntity(weapon))
        return Plugin_Stop;

    // Cari senjata lain untuk switch
    int switchWeapon = FindSwitchWeapon(client, weapon);
    if (switchWeapon == -1) return Plugin_Stop;

    // Step 1: Ganti ke senjata lain
    FakeClientCommand(client, "use %s", GetWeaponClassname(switchWeapon));

    // Step 2: Timer ganti balik
    DataPack pack2 = new DataPack();
    pack2.WriteCell(GetClientUserId(client));
    pack2.WriteCell(EntIndexToEntRef(weapon));

    CreateTimer(0.1, Timer_AutoSwitchBack, pack2, TIMER_DATA_HNDL_CLOSE);

    return Plugin_Stop;
}

public Action Timer_AutoSwitchBack(Handle timer, DataPack pack)
{
    pack.Reset();

    int userid    = pack.ReadCell();
    int weaponRef = pack.ReadCell();

    int client = GetClientOfUserId(userid);
    if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    int weapon = EntRefToEntIndex(weaponRef);
    if (weapon == INVALID_ENT_REFERENCE || !IsValidEntity(weapon))
        return Plugin_Stop;

    // Ganti balik ke senjata asal
    FakeClientCommand(client, "use %s", GetWeaponClassname(weapon));

    // Percepat recovery
    float deploySpeed = g_cvDeploySpeed.FloatValue;

    DataPack pack2 = new DataPack();
    pack2.WriteCell(GetClientUserId(client));
    pack2.WriteCell(EntIndexToEntRef(weapon));
    pack2.WriteFloat(deploySpeed);

    CreateTimer(0.05, Timer_SpeedUpFinal, pack2, TIMER_DATA_HNDL_CLOSE);

    return Plugin_Stop;
}

public Action Timer_SpeedUpFinal(Handle timer, DataPack pack)
{
    pack.Reset();

    int userid      = pack.ReadCell();
    int weaponRef   = pack.ReadCell();
    float deployTime = pack.ReadFloat();

    int client = GetClientOfUserId(userid);
    if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    int weapon = EntRefToEntIndex(weaponRef);
    if (weapon == INVALID_ENT_REFERENCE || !IsValidEntity(weapon))
        return Plugin_Stop;

    SpeedUpRecovery(client, weapon, deployTime);
    PrintCenterText(client, "★ Quick Change! ★");

    return Plugin_Stop;
}

// ============================================================
// Fungsi Bantuan
// ============================================================

/**
 * Cek apakah senjata support QC
 */
bool IsQCWeapon(int weapon)
{
    if (!IsValidEntity(weapon)) return false;

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));

    // Sniper
    if (StrEqual(classname, "weapon_awp"))    return true;
    if (StrEqual(classname, "weapon_scout"))  return true;
    if (StrEqual(classname, "weapon_g3sg1"))  return true;
    if (StrEqual(classname, "weapon_sg550"))  return true;
    if (StrEqual(classname, "weapon_m200"))  return true;
    if (StrEqual(classname, "weapon_l115a1"))  return true;

    // Shotgun
    if (StrEqual(classname, "weapon_m3"))     return true;
    if (StrEqual(classname, "weapon_xm1014")) return true;
    if (StrEqual(classname, "weapon_m1887"))  return true;

    return false;
}

/**
 * Cari senjata lain untuk switch
 */
int FindSwitchWeapon(int client, int currentWeapon)
{
    // Prioritas: Pisau > Pistol > Primary
    int knife = GetPlayerWeaponSlot(client, 2);
    if (knife != -1 && knife != currentWeapon)
        return knife;

    int pistol = GetPlayerWeaponSlot(client, 1);
    if (pistol != -1 && pistol != currentWeapon)
        return pistol;

    int primary = GetPlayerWeaponSlot(client, 0);
    if (primary != -1 && primary != currentWeapon)
        return primary;

    return -1;
}

/**
 * Dapatkan classname senjata
 */
char[] GetWeaponClassname(int weapon)
{
    char classname[64];
    if (IsValidEntity(weapon))
        GetEntityClassname(weapon, classname, sizeof(classname));
    return classname;
}

/**
 * Percepat deploy senjata
 */
void SpeedUpDeploy(int weapon, float time)
{
    if (!IsValidEntity(weapon)) return;

    float gameTime = GetGameTime();

    SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", gameTime + time);
    SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", gameTime + time);

    if (HasEntProp(weapon, Prop_Send, "m_flTimeWeaponIdle"))
        SetEntPropFloat(weapon, Prop_Send, "m_flTimeWeaponIdle", gameTime + time);
}

/**
 * Percepat recovery - senjata langsung siap tembak
 */
void SpeedUpRecovery(int client, int weapon, float deployTime)
{
    if (!IsValidEntity(weapon)) return;

    float gameTime = GetGameTime();
    float readyTime = gameTime + deployTime;

    SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", readyTime);
    SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", readyTime);

    if (HasEntProp(weapon, Prop_Send, "m_flTimeWeaponIdle"))
        SetEntPropFloat(weapon, Prop_Send, "m_flTimeWeaponIdle", readyTime);

    SetEntPropFloat(client, Prop_Send, "m_flNextAttack", gameTime + 0.01);
}