#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

#define UPDATE_RATE 0.3

ConVar g_cvEnabled;
ConVar g_cvCssDm;
bool g_bDMActive;

public Plugin myinfo =
{
    name = "Dead Team Panel Compact",
    author = "Assistant",
    description = "Team status compact - nonaktif saat DM",
    version = "1.4"
};

public void OnPluginStart()
{
    g_cvEnabled = CreateConVar("sm_deadpanel_enabled", "1", "Aktifkan panel", _, true, 0.0, true, 1.0);
    CreateTimer(UPDATE_RATE, Timer_Update, _, TIMER_REPEAT);
    AutoExecConfig(true, "dead_panel");

    // Cari ConVar cssdm_enabled
    g_cvCssDm = FindConVar("cssdm_enabled");

    if (g_cvCssDm != null)
    {
        // Baca nilai awal
        g_bDMActive = g_cvCssDm.BoolValue;

        // Hook perubahan nilai
        g_cvCssDm.AddChangeHook(OnDMChanged);

        PrintToServer("[DeadPanel] cssdm_enabled ditemukan. DM: %s", g_bDMActive ? "ON" : "OFF");
    }
    else
    {
        g_bDMActive = false;
        PrintToServer("[DeadPanel] cssdm_enabled tidak ditemukan. Panel aktif.");
    }
}

// ============================================================
// Deteksi perubahan cssdm_enabled
// ============================================================

public void OnDMChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_bDMActive = convar.BoolValue;

    if (g_bDMActive)
        PrintToServer("[DeadPanel] DM aktif - Panel NONAKTIF");
    else
        PrintToServer("[DeadPanel] DM nonaktif - Panel AKTIF");
}

// ============================================================
// Timer Update
// ============================================================

public Action Timer_Update(Handle timer)
{
    if (!g_cvEnabled.BoolValue)
        return Plugin_Continue;

    // cssdm_enabled = 1 -> jangan aktifkan panel
    // cssdm_enabled = 0 -> aktifkan panel
    if (g_bDMActive)
        return Plugin_Continue;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
            continue;
        if (IsPlayerAlive(client))
            continue;
        if (GetClientTeam(client) < CS_TEAM_T)
            continue;

        ShowPanel(client);
    }
    return Plugin_Continue;
}

// ============================================================
// Panel
// ============================================================

void ShowPanel(int client)
{
    int specTarget = -1;
    int obsMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

    if (obsMode == 4 || obsMode == 5)
    {
        int t = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
        if (t > 0 && t <= MaxClients && IsClientInGame(t) && IsPlayerAlive(t))
            specTarget = t;
    }

    int team = GetClientTeam(client);
    char msg[240];
    msg[0] = '\0';

    // Header
    if (team == CS_TEAM_CT)
        StrCat(msg, sizeof(msg), "=Counter-Terrorist=\n");
    else
        StrCat(msg, sizeof(msg), "=Terrorist=\n");

    // List players
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) != team)
            continue;

        if (strlen(msg) > 195)
            break;

        char name[10];
        GetClientName(i, name, sizeof(name));
        if (strlen(name) > 8) name[8] = '\0';

        char line[32];

        if (IsPlayerAlive(i))
        {
            int hp = GetClientHealth(i);
            if (hp > 100) hp = 100;

            char hbar[9];
            int f = hp / 13;
            if (f > 8) f = 8;
            for (int x = 0; x < 8; x++)
                hbar[x] = (x < f) ? '#' : '.';
            hbar[8] = '\0';

            if (i == specTarget)
                Format(line, sizeof(line), ">%s %s %d\n", name, hbar, hp);
            else if (i == client)
                Format(line, sizeof(line), "*%s %s %d\n", name, hbar, hp);
            else
                Format(line, sizeof(line), "%s %s %d\n", name, hbar, hp);
        }
        else
        {
            if (i == client)
                Format(line, sizeof(line), "*%s [Dead]\n", name);
            else
                Format(line, sizeof(line), "%s [Dead]\n", name);
        }

        if (strlen(msg) + strlen(line) < 230)
            StrCat(msg, sizeof(msg), line);
    }

    // Footer
    int alive = 0, dead = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) != team) continue;
        if (IsPlayerAlive(i)) alive++;
        else dead++;
    }

    char foot[24];
    Format(foot, sizeof(foot), "Alive: %d Dead: %d", alive, dead);
    if (strlen(msg) + strlen(foot) < 240)
        StrCat(msg, sizeof(msg), foot);

    Handle hMsg = StartMessageOne("KeyHintText", client);
    if (hMsg != null)
    {
        BfWriteByte(hMsg, 1);
        BfWriteString(hMsg, msg);
        EndMessage();
    }
}