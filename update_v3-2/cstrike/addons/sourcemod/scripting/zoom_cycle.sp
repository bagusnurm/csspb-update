#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.2"
#define MAX_WEAPONS 32

// ============================================================
// DATA
// ============================================================

char g_sWeaponName[MAX_WEAPONS][64];
int g_iWeaponMaxZoom[MAX_WEAPONS];
int g_iWeaponFOV1[MAX_WEAPONS];
int g_iWeaponFOV2[MAX_WEAPONS];
int g_iWeaponCount;

// Player tracking
int g_iPlayerZoomLevel[MAXPLAYERS + 1];   // 0=unzoom, 1=zoom1, 2=zoom2
int g_iPlayerLastFOV[MAXPLAYERS + 1];     // FOV frame sebelumnya
bool g_bBlockNextZoom[MAXPLAYERS + 1];    // Block zoom berikutnya (untuk 1x cycle)

ConVar g_cvEnabled;
ConVar g_cvDebug;

// ============================================================
// PLUGIN INFO
// ============================================================

public Plugin myinfo =
{
    name        = "Sniper Scope Cycle",
    author      = "Kento Style",
    description = "Control sniper zoom cycle (works with custom weapons)",
    version     = PLUGIN_VERSION,
    url         = ""
};

// ============================================================
// PLUGIN START
// ============================================================

public void OnPluginStart()
{
    g_cvEnabled = CreateConVar("sm_scope_enabled", "1", "Enable scope cycle control", _, true, 0.0, true, 1.0);
    g_cvDebug   = CreateConVar("sm_scope_debug", "0", "Debug mode", _, true, 0.0, true, 1.0);

    RegAdminCmd("sm_scope_reload", Cmd_Reload, ADMFLAG_ROOT, "Reload scope config");

    HookEvent("weapon_zoom", Event_WeaponZoom, EventHookMode_Post);
    HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);

    AutoExecConfig(true, "sniper_scope");

    PrintToServer("[Scope] Plugin v%s loaded!", PLUGIN_VERSION);
}

public void OnMapStart()
{
    LoadConfig();
}

public void OnClientPutInServer(int client)
{
    ResetClient(client);
    SDKHook(client, SDKHook_PreThinkPost, Hook_PreThinkPost);
}

public void OnClientDisconnect(int client)
{
    ResetClient(client);
    SDKUnhook(client, SDKHook_PreThinkPost, Hook_PreThinkPost);
}

void ResetClient(int client)
{
    g_iPlayerZoomLevel[client] = 0;
    g_iPlayerLastFOV[client] = 0;
    g_bBlockNextZoom[client] = false;
}

// ============================================================
// PRETHINK - Deteksi unzoom yang dilakukan oleh game
// (setelah menembak, ganti senjata, dll)
// ============================================================

public void Hook_PreThinkPost(int client)
{
    if (!g_cvEnabled.BoolValue)
        return;

    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return;

    int currentFOV = GetEntProp(client, Prop_Send, "m_iFOV");

    // Deteksi game melakukan unzoom (FOV kembali ke 0 atau default)
    // Ini terjadi saat:
    //   - Menembak (bolt action unzoom)
    //   - Ganti senjata
    //   - Mati
    if (g_iPlayerZoomLevel[client] > 0)
    {
        if (currentFOV == 0 || currentFOV == GetEntProp(client, Prop_Send, "m_iDefaultFOV"))
        {
            // Game sudah unzoom player -> sync state plugin
            if (g_cvDebug.BoolValue && g_iPlayerLastFOV[client] != currentFOV)
            {
                PrintToServer("[Scope] %N auto-unzoom detected (FOV: %d -> %d)",
                    client, g_iPlayerLastFOV[client], currentFOV);
            }

            g_iPlayerZoomLevel[client] = 0;
            g_bBlockNextZoom[client] = false;
        }
    }

    g_iPlayerLastFOV[client] = currentFOV;
}

// ============================================================
// EVENT: WEAPON FIRE - Deteksi tembakan saat zoom
// ============================================================

public void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
        return;

    // Jika player sedang zoom dan menembak,
    // game akan unzoom otomatis (terutama bolt-action)
    // Kita delay sedikit untuk menunggu game selesai unzoom
    if (g_iPlayerZoomLevel[client] > 0)
    {
        char weapon[64];
        GetClientWeapon(client, weapon, sizeof(weapon));

        int wIdx = FindWeaponIndex(weapon);
        if (wIdx == -1)
            return;

        // Delay reset agar PreThink sempat mendeteksi unzoom dari game
        CreateTimer(0.1, Timer_CheckAfterFire, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_CheckAfterFire(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    int currentFOV = GetEntProp(client, Prop_Send, "m_iFOV");

    // Jika setelah tembak FOV kembali ke default = game unzoom
    if (currentFOV == 0 || currentFOV == GetEntProp(client, Prop_Send, "m_iDefaultFOV"))
    {
        g_iPlayerZoomLevel[client] = 0;
        g_bBlockNextZoom[client] = false;

        if (g_cvDebug.BoolValue)
            PrintToServer("[Scope] %N post-fire unzoom confirmed", client);
    }

    return Plugin_Stop;
}

// ============================================================
// EVENT: WEAPON ZOOM
// ============================================================

public void Event_WeaponZoom(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
        return;

    char weapon[64];
    GetClientWeapon(client, weapon, sizeof(weapon));

    int wIdx = FindWeaponIndex(weapon);
    if (wIdx == -1)
        return;

    // Baca FOV yang baru di-set oleh game
    int gameFOV = GetEntProp(client, Prop_Send, "m_iFOV");
    int defaultFOV = GetEntProp(client, Prop_Send, "m_iDefaultFOV");

    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[Scope] %N event zoom | weapon: %s | gameFOV: %d | level: %d | block: %s",
            client, weapon, gameFOV, g_iPlayerZoomLevel[client],
            g_bBlockNextZoom[client] ? "YES" : "NO");
    }

    // Game baru saja zoom IN (FOV berubah dari default ke sesuatu)
    bool gameZoomingIn = (gameFOV != 0 && gameFOV != defaultFOV);

    // Game baru saja zoom OUT (FOV kembali ke 0 atau default)
    bool gameZoomingOut = (gameFOV == 0 || gameFOV == defaultFOV);

    if (g_iWeaponMaxZoom[wIdx] == 1)
        HandleSingleZoom(client, wIdx, gameZoomingIn, gameZoomingOut);
    else
        HandleDoubleZoom(client, wIdx, gameZoomingIn, gameZoomingOut, gameFOV);
}

// ============================================================
// HANDLE SINGLE ZOOM (1x cycle)
// ============================================================

void HandleSingleZoom(int client, int wIdx, bool gameZoomingIn, bool gameZoomingOut)
{
    if (gameZoomingOut)
    {
        // Game melakukan unzoom -> sync
        g_iPlayerZoomLevel[client] = 0;
        g_bBlockNextZoom[client] = false;

        if (g_cvDebug.BoolValue)
            PrintToServer("[Scope] %N -> UNZOOM (game)", client);

        return;
    }

    if (gameZoomingIn)
    {
        if (g_iPlayerZoomLevel[client] == 0)
        {
            // Zoom pertama: izinkan, set FOV custom
            g_iPlayerZoomLevel[client] = 1;
            g_bBlockNextZoom[client] = true; // Block zoom berikutnya

            SetEntProp(client, Prop_Send, "m_iFOV", g_iWeaponFOV1[wIdx]);

            if (g_cvDebug.BoolValue)
                PrintToServer("[Scope] %N -> ZOOM IN (FOV: %d)", client, g_iWeaponFOV1[wIdx]);
        }
        else if (g_bBlockNextZoom[client])
        {
            // Ini zoom kedua yang di-trigger game, tapi kita mau 1x cycle
            // Force UNZOOM
            g_iPlayerZoomLevel[client] = 0;
            g_bBlockNextZoom[client] = false;

            // Set FOV ke 0 (default/unzoom)
            SetEntProp(client, Prop_Send, "m_iFOV", 0);

            // Delay kecil untuk memastikan unzoom
            CreateTimer(0.0, Timer_ForceUnzoom, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

            if (g_cvDebug.BoolValue)
                PrintToServer("[Scope] %N -> FORCE UNZOOM (1x cycle)", client);
        }
    }
}

// ============================================================
// HANDLE DOUBLE ZOOM (2x cycle)
// ============================================================

void HandleDoubleZoom(int client, int wIdx, bool gameZoomingIn, bool gameZoomingOut, int gameFOV)
{
    if (gameZoomingOut)
    {
        g_iPlayerZoomLevel[client] = 0;

        if (g_cvDebug.BoolValue)
            PrintToServer("[Scope] %N -> UNZOOM (game)", client);

        return;
    }

    if (gameZoomingIn)
    {
        if (g_iPlayerZoomLevel[client] == 0)
        {
            // Zoom pertama
            g_iPlayerZoomLevel[client] = 1;
            SetEntProp(client, Prop_Send, "m_iFOV", g_iWeaponFOV1[wIdx]);

            if (g_cvDebug.BoolValue)
                PrintToServer("[Scope] %N -> ZOOM 1 (FOV: %d)", client, g_iWeaponFOV1[wIdx]);
        }
        else if (g_iPlayerZoomLevel[client] == 1)
        {
            // Zoom kedua
            g_iPlayerZoomLevel[client] = 2;
            SetEntProp(client, Prop_Send, "m_iFOV", g_iWeaponFOV2[wIdx]);

            if (g_cvDebug.BoolValue)
                PrintToServer("[Scope] %N -> ZOOM 2 (FOV: %d)", client, g_iWeaponFOV2[wIdx]);
        }
        else
        {
            // Zoom ketiga = unzoom
            g_iPlayerZoomLevel[client] = 0;
            SetEntProp(client, Prop_Send, "m_iFOV", 0);

            CreateTimer(0.0, Timer_ForceUnzoom, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

            if (g_cvDebug.BoolValue)
                PrintToServer("[Scope] %N -> UNZOOM (3rd click)", client);
        }
    }
}

// ============================================================
// FORCE UNZOOM TIMER
// ============================================================

public Action Timer_ForceUnzoom(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    // Double check: pastikan FOV benar-benar 0
    int currentFOV = GetEntProp(client, Prop_Send, "m_iFOV");
    if (currentFOV != 0 && g_iPlayerZoomLevel[client] == 0)
    {
        SetEntProp(client, Prop_Send, "m_iFOV", 0);

        if (g_cvDebug.BoolValue)
            PrintToServer("[Scope] %N -> Force FOV=0 (was %d)", client, currentFOV);
    }

    return Plugin_Stop;
}

// ============================================================
// EVENTS
// ============================================================

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && client <= MaxClients)
        ResetClient(client);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && client <= MaxClients)
        ResetClient(client);
}

// ============================================================
// FIND WEAPON
// ============================================================

int FindWeaponIndex(const char[] weapon)
{
    for (int i = 0; i < g_iWeaponCount; i++)
    {
        if (StrEqual(weapon, g_sWeaponName[i], false))
            return i;
    }
    return -1;
}

// ============================================================
// LOAD CONFIG
// ============================================================

void LoadConfig()
{
    char configFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configFile, sizeof(configFile), "configs/sniper_scope.cfg");

    g_iWeaponCount = 0;

    if (!FileExists(configFile))
    {
        PrintToServer("[Scope] Config not found. Generating default...");
        GenerateDefaultConfig(configFile);
        return;
    }

    KeyValues kv = new KeyValues("SniperScope");

    if (!kv.ImportFromFile(configFile))
    {
        PrintToServer("[Scope] Failed to read config!");
        delete kv;
        return;
    }

    if (!kv.GotoFirstSubKey())
    {
        PrintToServer("[Scope] Config empty!");
        delete kv;
        return;
    }

    do
    {
        if (g_iWeaponCount >= MAX_WEAPONS)
            break;

        int idx = g_iWeaponCount;

        kv.GetSectionName(g_sWeaponName[idx], sizeof(g_sWeaponName[]));
        g_iWeaponMaxZoom[idx] = kv.GetNum("max_zoom", 2);
        g_iWeaponFOV1[idx] = kv.GetNum("fov_zoom1", 40);
        g_iWeaponFOV2[idx] = kv.GetNum("fov_zoom2", 15);

        if (g_iWeaponMaxZoom[idx] < 1) g_iWeaponMaxZoom[idx] = 1;
        if (g_iWeaponMaxZoom[idx] > 2) g_iWeaponMaxZoom[idx] = 2;
        if (g_iWeaponFOV1[idx] < 5) g_iWeaponFOV1[idx] = 5;
        if (g_iWeaponFOV1[idx] > 90) g_iWeaponFOV1[idx] = 90;
        if (g_iWeaponFOV2[idx] < 5) g_iWeaponFOV2[idx] = 5;
        if (g_iWeaponFOV2[idx] > 90) g_iWeaponFOV2[idx] = 90;

        PrintToServer("[Scope] %s | max_zoom: %d | fov1: %d | fov2: %d",
            g_sWeaponName[idx], g_iWeaponMaxZoom[idx],
            g_iWeaponFOV1[idx], g_iWeaponFOV2[idx]);

        g_iWeaponCount++;

    } while (kv.GotoNextKey());

    delete kv;
    PrintToServer("[Scope] Loaded %d weapon(s).", g_iWeaponCount);
}

void GenerateDefaultConfig(const char[] path)
{
    KeyValues kv = new KeyValues("SniperScope");

    kv.JumpToKey("weapon_awp", true);
    kv.SetNum("max_zoom", 1); kv.SetNum("fov_zoom1", 40); kv.SetNum("fov_zoom2", 15);
    kv.GoBack();

    kv.JumpToKey("weapon_scout", true);
    kv.SetNum("max_zoom", 2); kv.SetNum("fov_zoom1", 40); kv.SetNum("fov_zoom2", 15);
    kv.GoBack();

    kv.JumpToKey("weapon_sg550", true);
    kv.SetNum("max_zoom", 1); kv.SetNum("fov_zoom1", 40); kv.SetNum("fov_zoom2", 15);
    kv.GoBack();

    kv.JumpToKey("weapon_g3sg1", true);
    kv.SetNum("max_zoom", 1); kv.SetNum("fov_zoom1", 40); kv.SetNum("fov_zoom2", 15);
    kv.GoBack();

    kv.JumpToKey("weapon_aug", true);
    kv.SetNum("max_zoom", 1); kv.SetNum("fov_zoom1", 55); kv.SetNum("fov_zoom2", 55);
    kv.GoBack();

    kv.JumpToKey("weapon_sg552", true);
    kv.SetNum("max_zoom", 1); kv.SetNum("fov_zoom1", 55); kv.SetNum("fov_zoom2", 55);
    kv.GoBack();

    kv.JumpToKey("weapon_m200", true);
    kv.SetNum("max_zoom", 1); kv.SetNum("fov_zoom1", 35); kv.SetNum("fov_zoom2", 35);
    kv.GoBack();

    kv.ExportToFile(path);
    delete kv;
    PrintToServer("[Scope] Default config generated.");
    LoadConfig();
}

// ============================================================
// COMMANDS
// ============================================================

public Action Cmd_Reload(int client, int args)
{
    LoadConfig();
    ReplyToCommand(client, "[Scope] Reloaded. %d weapon(s).", g_iWeaponCount);
    return Plugin_Handled;
}