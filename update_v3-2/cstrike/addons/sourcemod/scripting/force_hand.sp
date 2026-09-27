#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.4.0"
#define MAX_WEAPONS 128

char g_sForceWeapons[MAX_WEAPONS][32];
int g_iForceWeaponCount;

bool g_bPlayerOriginalHand[MAXPLAYERS + 1];
bool g_bPlayerQueryDone[MAXPLAYERS + 1];
char g_sPlayerCurrentWeapon[MAXPLAYERS + 1][32];
int g_iPlayerCurrentHand[MAXPLAYERS + 1]; // Track current applied hand

ConVar g_cvEnabled;
ConVar g_cvDebug;

public Plugin myinfo =
{
    name        = "Force Reverse Hand",
    author      = "Kento Style",
    description = "Force reverse viewmodel hand for specific weapons",
    version     = PLUGIN_VERSION,
    url         = ""
};

public void OnPluginStart()
{
    g_cvEnabled = CreateConVar("sm_forcehand_enabled", "1", "Enable force reverse hand", _, true, 0.0, true, 1.0);
    g_cvDebug = CreateConVar("sm_forcehand_debug", "0", "Debug mode", _, true, 0.0, true, 1.0);

    // Remove FCVAR_CHEAT flag dari cl_righthand agar bisa diubah server
    ConVar cvRight = FindConVar("cl_righthand");
    if (cvRight != null)
    {
        int flags = cvRight.Flags;
        flags &= ~FCVAR_CHEAT;
        flags &= ~FCVAR_NOT_CONNECTED;
        cvRight.Flags = flags;
    }

    RegAdminCmd("sm_forcehand_reload", Cmd_Reload, ADMFLAG_ROOT, "Reload config");
    RegConsoleCmd("sm_myhand", Cmd_MyHand, "Show current hand info");

    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);

    AutoExecConfig(true, "force_hand");

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            OnClientPutInServer(i);
    }

    PrintToServer("[ForceHand] Plugin v%s loaded!", PLUGIN_VERSION);
}

public void OnMapStart()
{
    LoadConfig();
}

public void OnClientPutInServer(int client)
{
    g_bPlayerOriginalHand[client] = true;
    g_bPlayerQueryDone[client] = false;
    g_sPlayerCurrentWeapon[client][0] = '\0';
    g_iPlayerCurrentHand[client] = -1;

    SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch);

    if (!IsFakeClient(client))
    {
        CreateTimer(3.0, Timer_QueryHand, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnClientDisconnect(int client)
{
    // Restore original sebelum disconnect
    if (IsClientInGame(client) && !IsFakeClient(client) && g_bPlayerQueryDone[client])
    {
        SetClientHand(client, g_bPlayerOriginalHand[client] ? 1 : 0);
    }

    g_bPlayerOriginalHand[client] = true;
    g_bPlayerQueryDone[client] = false;
    g_sPlayerCurrentWeapon[client][0] = '\0';
    g_iPlayerCurrentHand[client] = -1;
}

// ============================================================
// QUERY HAND
// ============================================================

public Action Timer_QueryHand(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Stop;

    QueryClientConVar(client, "cl_righthand", OnQueryRightHand);
    return Plugin_Stop;
}

public void OnQueryRightHand(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
    if (!IsClientInGame(client))
        return;

    if (result != ConVarQuery_Okay)
        return;

    g_bPlayerOriginalHand[client] = (StringToInt(cvarValue) == 1);
    g_bPlayerQueryDone[client] = true;

    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[ForceHand] %N original: cl_righthand %s (%s)",
            client, cvarValue,
            g_bPlayerOriginalHand[client] ? "RIGHT" : "LEFT");
    }

    g_sPlayerCurrentWeapon[client][0] = '\0';
    CreateTimer(0.1, Timer_CheckAndApply, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

// ============================================================
// PLAYER SPAWN
// ============================================================

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client))
        return;

    g_sPlayerCurrentWeapon[client][0] = '\0';
    g_iPlayerCurrentHand[client] = -1;

    if (!IsFakeClient(client))
    {
        CreateTimer(0.5, Timer_CheckAndApply, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

// ============================================================
// WEAPON SWITCH
// ============================================================

public void OnWeaponSwitch(int client, int weapon)
{
    if (!g_cvEnabled.BoolValue)
        return;

    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return;

    if (IsFakeClient(client) || !g_bPlayerQueryDone[client])
        return;

    if (!IsValidEntity(weapon))
        return;

    CreateTimer(0.05, Timer_CheckAndApply, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

// ============================================================
// CHECK AND APPLY
// ============================================================

public Action Timer_CheckAndApply(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    if (IsFakeClient(client) || !g_bPlayerQueryDone[client])
        return Plugin_Stop;

    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon == -1 || !IsValidEntity(weapon))
        return Plugin_Stop;

    char classname[64];
    GetEdictClassname(weapon, classname, sizeof(classname));

    char weaponName[32];
    if (strncmp(classname, "weapon_", 7, false) == 0)
        strcopy(weaponName, sizeof(weaponName), classname[7]);
    else
        strcopy(weaponName, sizeof(weaponName), classname);

    // Skip jika weapon sama DAN hand sudah benar
    if (StrEqual(weaponName, g_sPlayerCurrentWeapon[client], false) && g_iPlayerCurrentHand[client] != -1)
        return Plugin_Stop;

    strcopy(g_sPlayerCurrentWeapon[client], sizeof(g_sPlayerCurrentWeapon[]), weaponName);

    bool shouldReverse = IsWeaponInList(weaponName);
    bool originalHand = g_bPlayerOriginalHand[client];
    int targetValue;

    if (shouldReverse)
        targetValue = originalHand ? 0 : 1;
    else
        targetValue = originalHand ? 1 : 0;

    // Skip jika hand sudah benar
    if (g_iPlayerCurrentHand[client] == targetValue)
        return Plugin_Stop;

    SetClientHand(client, targetValue);
    g_iPlayerCurrentHand[client] = targetValue;

    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[ForceHand] %N | %s | reverse: %s | cl_righthand %d",
            client, weaponName,
            shouldReverse ? "YES" : "NO",
            targetValue);
    }

    return Plugin_Stop;
}

// ============================================================
// SET CLIENT HAND - Multiple methods untuk memastikan berhasil
// ============================================================

void SetClientHand(int client, int value)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return;

    char sValue[4];
    IntToString(value, sValue, sizeof(sValue));

    // ==========================================
    // METHOD 1: SendConVarValue
    // Mengubah network-side value
    // ==========================================
    ConVar cvRight = FindConVar("cl_righthand");
    if (cvRight != null)
    {
        SendConVarValue(client, cvRight, sValue);
    }

    // ==========================================
    // METHOD 2: sv_cheats trick
    // Temporarily enable cheats, set convar, restore
    // ==========================================
    ConVar svCheats = FindConVar("sv_cheats");
    if (svCheats != null)
    {
        int oldCheats = svCheats.IntValue;

        // Temporary enable cheats (silent)
        int svFlags = svCheats.Flags;
        svCheats.Flags = svFlags & ~FCVAR_NOTIFY;
        svCheats.IntValue = 1;

        // Send command via engine
        char cmd[64];
        Format(cmd, sizeof(cmd), "cl_righthand %d", value);

        // Kirim sebagai engine command
        ClientCommand(client, cmd);

        // Restore cheats (silent)
        svCheats.IntValue = oldCheats;
        svCheats.Flags = svFlags;
    }

    // ==========================================
    // METHOD 3: Direct entity prop manipulation
    // Ubah m_bFlipViewModel pada player entity
    // ==========================================
    if (HasEntProp(client, Prop_Send, "m_bFlipViewModel"))
    {
        // m_bFlipViewModel: true = LEFT hand, false = RIGHT hand
        // cl_righthand 1 = RIGHT = m_bFlipViewModel false
        // cl_righthand 0 = LEFT = m_bFlipViewModel true
        SetEntProp(client, Prop_Send, "m_bFlipViewModel", value == 0);

        if (g_cvDebug.BoolValue)
        {
            PrintToServer("[ForceHand] %N m_bFlipViewModel = %d", client, value == 0);
        }
    }
}

// ============================================================
// WEAPON LIST
// ============================================================

bool IsWeaponInList(const char[] weaponName)
{
    for (int i = 0; i < g_iForceWeaponCount; i++)
    {
        if (StrEqual(g_sForceWeapons[i], weaponName, false))
            return true;
    }
    return false;
}

// ============================================================
// LOAD CONFIG
// ============================================================

void LoadConfig()
{
    char configFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configFile, sizeof(configFile), "configs/force_hand.cfg");

    g_iForceWeaponCount = 0;

    for (int i = 0; i < MAX_WEAPONS; i++)
        g_sForceWeapons[i][0] = '\0';

    if (!FileExists(configFile))
    {
        GenerateDefaultConfig(configFile);
        return;
    }

    File file = OpenFile(configFile, "r");
    if (file == null)
        return;

    char line[64];
    while (file.ReadLine(line, sizeof(line)))
    {
        if (g_iForceWeaponCount >= MAX_WEAPONS)
            break;

        TrimString(line);

        if (line[0] == '\0' || line[0] == '/' || line[0] == '#' || line[0] == ';')
            continue;

        if (strncmp(line, "weapon_", 7, false) == 0)
            strcopy(g_sForceWeapons[g_iForceWeaponCount], sizeof(g_sForceWeapons[]), line[7]);
        else
            strcopy(g_sForceWeapons[g_iForceWeaponCount], sizeof(g_sForceWeapons[]), line);

        PrintToServer("[ForceHand] Loaded: %s", g_sForceWeapons[g_iForceWeaponCount]);
        g_iForceWeaponCount++;
    }

    delete file;
    PrintToServer("[ForceHand] Total %d weapon(s).", g_iForceWeaponCount);
}

void GenerateDefaultConfig(const char[] path)
{
    File file = OpenFile(path, "w");
    if (file == null)
        return;

    file.WriteLine("// ============================================");
    file.WriteLine("// Force Reverse Hand Config");
    file.WriteLine("// ============================================");
    file.WriteLine("// Tulis nama senjata TANPA prefix 'weapon_'");
    file.WriteLine("// Senjata di list = hand TERBALIK");
    file.WriteLine("// Senjata TIDAK di list = hand NORMAL");
    file.WriteLine("// ============================================");
    file.WriteLine("");
    file.WriteLine("awp");
    file.WriteLine("scout");
    file.WriteLine("sg550");
    file.WriteLine("g3sg1");

    delete file;
    LoadConfig();
}

// ============================================================
// COMMANDS
// ============================================================

public Action Cmd_Reload(int client, int args)
{
    LoadConfig();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            g_sPlayerCurrentWeapon[i][0] = '\0';
            g_iPlayerCurrentHand[i] = -1;
            CreateTimer(0.1, Timer_CheckAndApply, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
        }
    }

    ReplyToCommand(client, "[ForceHand] Reloaded. %d weapon(s).", g_iForceWeaponCount);
    return Plugin_Handled;
}

public Action Cmd_MyHand(int client, int args)
{
    if (client <= 0)
        return Plugin_Handled;

    PrintToChat(client, " \x04[ForceHand]");
    PrintToChat(client, " \x01  Original: \x03%s",
        g_bPlayerOriginalHand[client] ? "RIGHT" : "LEFT");
    PrintToChat(client, " \x01  Current hand: \x03%s",
        g_iPlayerCurrentHand[client] == 1 ? "RIGHT" :
        g_iPlayerCurrentHand[client] == 0 ? "LEFT" : "UNKNOWN");
    PrintToChat(client, " \x01  Weapon: \x03%s", g_sPlayerCurrentWeapon[client]);
    PrintToChat(client, " \x01  Reversed: \x03%s",
        IsWeaponInList(g_sPlayerCurrentWeapon[client]) ? "YES" : "NO");

    return Plugin_Handled;
}