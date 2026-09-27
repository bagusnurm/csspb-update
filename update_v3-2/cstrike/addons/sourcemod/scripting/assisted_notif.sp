#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <killassist>

#pragma semicolon 1

#define PLUGIN_VERSION "1.0.0"
#define ASSIST_DISPLAY_TIME 1.0

new Handle:g_cvEnabled;

new bool:g_bShowAssist[MAXPLAYERS + 1];
new Float:g_flAssistTime[MAXPLAYERS + 1];
new String:g_sAssistVictim[MAXPLAYERS + 1][32];
new String:g_sAssistKiller[MAXPLAYERS + 1][32];

public Plugin:myinfo =
{
    name        = "Assist Notification",
    author      = "Assistant",
    description = "Tampilkan assist notification saat hidup",
    version     = PLUGIN_VERSION,
    url         = ""
};

public OnPluginStart()
{
    g_cvEnabled = CreateConVar("sm_assist_enabled", "1", "Aktifkan assist notification", _, true, 0.0, true, 1.0);

    CreateTimer(0.1, Timer_ShowAssist, _, TIMER_REPEAT);

    AutoExecConfig(true, "assist_notification");

    PrintToServer("[Assist] Plugin v%s loaded!", PLUGIN_VERSION);
}

public OnClientPutInServer(client)
{
    g_bShowAssist[client] = false;
    g_flAssistTime[client] = 0.0;
    g_sAssistVictim[client][0] = '\0';
    g_sAssistKiller[client][0] = '\0';
}

// ============================================================
// KILL ASSIST HOOK - Old Syntax
// ============================================================

public OnAssistedKill(const any:assisters[], const nbAssisters, const killerId, const victimId)
{
    if (!GetConVarBool(g_cvEnabled))
        return;

    if (killerId < 1 || killerId > MaxClients || !IsClientInGame(killerId))
        return;
    if (victimId < 1 || victimId > MaxClients || !IsClientInGame(victimId))
        return;

    decl String:victimName[32];
    decl String:killerName[32];
    GetClientName(victimId, victimName, sizeof(victimName));
    GetClientName(killerId, killerName, sizeof(killerName));

    if (strlen(victimName) > 14) victimName[14] = '\0';
    if (strlen(killerName) > 14) killerName[14] = '\0';

    for (new i = 0; i < nbAssisters; i++)
    {
        new assister = _:assisters[i];

        if (assister < 1 || assister > MaxClients || !IsClientInGame(assister))
            continue;

        if (!IsPlayerAlive(assister))
            continue;

        if (assister == killerId)
            continue;

        g_bShowAssist[assister] = true;
        g_flAssistTime[assister] = GetGameTime() + ASSIST_DISPLAY_TIME;
        strcopy(g_sAssistVictim[assister], sizeof(g_sAssistVictim[]), victimName);
        strcopy(g_sAssistKiller[assister], sizeof(g_sAssistKiller[]), killerName);
    }
}

// ============================================================
// TIMER
// ============================================================

public Action:Timer_ShowAssist(Handle:timer)
{
    new Float:gameTime = GetGameTime();

    for (new client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
            continue;

        if (!IsPlayerAlive(client))
        {
            g_bShowAssist[client] = false;
            continue;
        }

        if (!g_bShowAssist[client])
            continue;

        if (gameTime > g_flAssistTime[client])
        {
            g_bShowAssist[client] = false;
            continue;
        }

        ShowAssistPanel(client);
    }

    return Plugin_Continue;
}

// ============================================================
// KEYHINT PANEL
// ============================================================

ShowAssistPanel(client)
{
    decl String:msg[200];
    msg[0] = '\0';

    StrCat(msg, sizeof(msg), "=ASSIST=\n\n");
    StrCat(msg, sizeof(msg), "You assisted killing\n");

    decl String:line[64];
    Format(line, sizeof(line), "%s\n\n", g_sAssistVictim[client]);
    StrCat(msg, sizeof(msg), line);

    Format(line, sizeof(line), "Killed by: %s", g_sAssistKiller[client]);
    StrCat(msg, sizeof(msg), line);

    new Handle:hMsg = StartMessageOne("KeyHintText", client);
    if (hMsg != INVALID_HANDLE)
    {
        BfWriteByte(hMsg, 1);
        BfWriteString(hMsg, msg);
        EndMessage();
    }
}