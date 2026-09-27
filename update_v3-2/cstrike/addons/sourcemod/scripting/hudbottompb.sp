#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "3.0.0"
#define MAX_NAMETAGS   10
#define UPDATE_RATE    0.1
#define MAX_DISTANCE   3000.0

// ConVars
ConVar g_cvEnabled;
ConVar g_cvShowHP;
ConVar g_cvShowRank;
ConVar g_cvThroughWalls;

// Per-player data
int    g_iNametagEnts[MAXPLAYERS + 1][MAX_NAMETAGS];  // game_text entities per viewer
char   g_sRank[MAXPLAYERS + 1][32];
char   g_sClan[MAXPLAYERS + 1][32];
int    g_iKills[MAXPLAYERS + 1];

// Rank names
char g_sRankNames[][] = {
    "Trainee", "Private", "Corporal", "Sergeant", 
    "Staff Sgt", "Master Sgt", "2nd Lt", "1st Lt", 
    "Captain", "Major", "Lt Colonel", "Colonel", 
    "Brigadier", "Maj General", "Lt General", "General"
};

public Plugin myinfo =
{
    name        = "PB Nametag - Game Text Method",
    author      = "Assistant",
    description = "Nametag menggunakan game_text entity",
    version     = PLUGIN_VERSION,
    url         = ""
};

public void OnPluginStart()
{
    g_cvEnabled      = CreateConVar("sm_nt_enabled",      "1", "Aktifkan nametag");
    g_cvShowHP       = CreateConVar("sm_nt_hp",           "1", "Tampilkan HP");
    g_cvShowRank     = CreateConVar("sm_nt_rank",         "1", "Tampilkan rank");
    g_cvThroughWalls = CreateConVar("sm_nt_throughwalls", "1", "Tembus tembok");

    RegConsoleCmd("sm_setclan", Cmd_SetClan);
    
    HookEvent("player_death", Event_PlayerDeath);
    
    CreateTimer(UPDATE_RATE, Timer_UpdateNametags, _, TIMER_REPEAT);
    
    // Inisialisasi array
    for (int i = 1; i <= MaxClients; i++)
    {
        for (int j = 0; j < MAX_NAMETAGS; j++)
        {
            g_iNametagEnts[i][j] = -1;
        }
    }
    
    AutoExecConfig(true, "pb_nametag_v3");
}

public void OnMapStart()
{
    // Reset entities
    for (int i = 1; i <= MaxClients; i++)
    {
        for (int j = 0; j < MAX_NAMETAGS; j++)
        {
            g_iNametagEnts[i][j] = -1;
        }
    }
}

public void OnClientPutInServer(int client)
{
    g_sClan[client][0] = '\0';
    g_iKills[client] = 0;
    UpdateRank(client);
    
    for (int j = 0; j < MAX_NAMETAGS; j++)
    {
        g_iNametagEnts[client][j] = -1;
    }
}

public void OnClientDisconnect(int client)
{
    CleanupNametagEntities(client);
}

public Action Cmd_SetClan(int client, int args)
{
    if (args < 1)
    {
        PrintToChat(client, "\x04[NT]\x01 Usage: !setclan <name> or !setclan none");
        return Plugin_Handled;
    }
    
    char clan[32];
    GetCmdArgString(clan, sizeof(clan));
    
    if (StrEqual(clan, "none", false))
        g_sClan[client][0] = '\0';
    else
        strcopy(g_sClan[client], sizeof(g_sClan[]), clan);
    
    PrintToChat(client, "\x04[NT]\x01 Clan set!");
    return Plugin_Handled;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
    {
        g_iKills[attacker]++;
        UpdateRank(attacker);
    }
}

void UpdateRank(int client)
{
    int kills = g_iKills[client];
    int idx = 0;
    
    if (kills >= 150)      idx = 15;
    else if (kills >= 120) idx = 14;
    else if (kills >= 100) idx = 13;
    else if (kills >= 80)  idx = 12;
    else if (kills >= 65)  idx = 11;
    else if (kills >= 50)  idx = 10;
    else if (kills >= 40)  idx = 9;
    else if (kills >= 30)  idx = 8;
    else if (kills >= 25)  idx = 7;
    else if (kills >= 20)  idx = 6;
    else if (kills >= 15)  idx = 5;
    else if (kills >= 10)  idx = 4;
    else if (kills >= 5)   idx = 3;
    else if (kills >= 3)   idx = 2;
    else if (kills >= 1)   idx = 1;
    
    strcopy(g_sRank[client], sizeof(g_sRank[]), g_sRankNames[idx]);
}

// ============================================================
// TIMER UPDATE
// ============================================================

public Action Timer_UpdateNametags(Handle timer)
{
    if (!g_cvEnabled.BoolValue)
        return Plugin_Continue;
    
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
            continue;
        
        UpdateNametagsForClient(client);
    }
    
    return Plugin_Continue;
}

void UpdateNametagsForClient(int viewer)
{
    float viewerPos[3], viewerAng[3];
    GetClientEyePosition(viewer, viewerPos);
    GetClientEyeAngles(viewer, viewerAng);
    
    int viewerTeam = GetClientTeam(viewer);
    bool throughWalls = g_cvThroughWalls.BoolValue;
    
    int slot = 0;
    
    for (int target = 1; target <= MaxClients && slot < MAX_NAMETAGS; target++)
    {
        if (target == viewer) continue;
        if (!IsClientInGame(target) || !IsPlayerAlive(target)) continue;
        if (GetClientTeam(target) != viewerTeam) continue; // Teammate only
        
        float targetPos[3];
        GetClientAbsOrigin(target, targetPos);
        targetPos[2] += 80.0;
        
        float dist = GetVectorDistance(viewerPos, targetPos);
        if (dist > MAX_DISTANCE) continue;
        
        // FOV check
        if (!IsInFOV(viewerPos, viewerAng, targetPos, 110.0))
            continue;
        
        // Wall check
        if (!throughWalls && !CanSeeTarget(viewerPos, targetPos))
            continue;
        
        // Screen position
        float screenX, screenY;
        if (!WorldToScreen(viewerPos, viewerAng, targetPos, screenX, screenY))
            continue;
        
        // Show nametag using game_text
        ShowNametagGameText(viewer, target, slot, screenX, screenY, dist);
        slot++;
    }
    
    // Clear unused slots
    for (int i = slot; i < MAX_NAMETAGS; i++)
    {
        HideNametagSlot(viewer, i);
    }
}

// ============================================================
// GAME_TEXT ENTITY
// ============================================================

void ShowNametagGameText(int viewer, int target, int slot, float x, float y, float dist)
{
    // Build text
    char text[256];
    BuildNametagText(target, dist, text, sizeof(text));
    
    // Warna berdasarkan team
    int team = GetClientTeam(target);
    char color[32];
    if (team == CS_TEAM_CT)
        strcopy(color, sizeof(color), "100 180 255");
    else
        strcopy(color, sizeof(color), "255 200 80");
    
    // Clamp posisi
    if (x < 0.01) x = 0.01;
    if (x > 0.99) x = 0.99;
    if (y < 0.01) y = 0.01;
    if (y > 0.99) y = 0.99;
    
    // Buat atau reuse entity
    int ent = GetOrCreateGameText(viewer, slot);
    if (ent == -1) return;
    
    // Set properties
    char xStr[16], yStr[16];
    FloatToString(x, xStr, sizeof(xStr));
    FloatToString(y, yStr, sizeof(yStr));
    
    DispatchKeyValue(ent, "message", text);
    DispatchKeyValue(ent, "x", xStr);
    DispatchKeyValue(ent, "y", yStr);
    DispatchKeyValue(ent, "color", color);
    DispatchKeyValue(ent, "color2", "255 255 255");
    DispatchKeyValue(ent, "fadein", "0");
    DispatchKeyValue(ent, "fadeout", "0");
    DispatchKeyValue(ent, "holdtime", "0.15");
    DispatchKeyValue(ent, "fxtime", "0");
    DispatchKeyValue(ent, "effect", "0");
    DispatchKeyValue(ent, "channel", "0");  // Auto channel
    
    // Fire ke viewer saja
    SetVariantString("!activator");
    AcceptEntityInput(ent, "Display", viewer, ent);
}

int GetOrCreateGameText(int viewer, int slot)
{
    int ent = g_iNametagEnts[viewer][slot];
    
    // Cek apakah entity masih valid
    if (ent != -1 && IsValidEntity(ent))
        return ent;
    
    // Buat baru
    ent = CreateEntityByName("game_text");
    if (ent == -1)
        return -1;
    
    DispatchKeyValue(ent, "spawnflags", "0");
    DispatchSpawn(ent);
    
    g_iNametagEnts[viewer][slot] = ent;
    return ent;
}

void HideNametagSlot(int viewer, int slot)
{
    int ent = g_iNametagEnts[viewer][slot];
    if (ent != -1 && IsValidEntity(ent))
    {
        AcceptEntityInput(ent, "Kill");
        g_iNametagEnts[viewer][slot] = -1;
    }
}

void CleanupNametagEntities(int client)
{
    for (int i = 0; i < MAX_NAMETAGS; i++)
    {
        HideNametagSlot(client, i);
    }
}

// ============================================================
// BUILD TEXT
// ============================================================

void BuildNametagText(int target, float dist, char[] buffer, int maxlen)
{
    char name[32];
    GetClientName(target, name, sizeof(name));
    if (strlen(name) > 14)
    {
        name[14] = '\0';
        StrCat(name, sizeof(name), "..");
    }
    
    buffer[0] = '\0';
    
    // Clan + Rank
    if (g_cvShowRank.BoolValue)
    {
        if (g_sClan[target][0] != '\0')
            Format(buffer, maxlen, "[%s] %s\n", g_sClan[target], g_sRank[target]);
        else
            Format(buffer, maxlen, "%s\n", g_sRank[target]);
    }
    
    // Name
    StrCat(buffer, maxlen, name);
    
    // HP Bar
    if (g_cvShowHP.BoolValue)
    {
        int hp = GetClientHealth(target);
        if (hp > 100) hp = 100;
        if (hp < 0) hp = 0;
        
        char hpBar[24];
        int filled = hp / 10;
        
        for (int i = 0; i < 10; i++)
        {
            if (i < filled)
                StrCat(hpBar, sizeof(hpBar), "|");
            else
                StrCat(hpBar, sizeof(hpBar), ".");
        }
        
        Format(buffer, maxlen, "%s\n%s %d", buffer, hpBar, hp);
    }
}

// ============================================================
// HELPER FUNCTIONS
// ============================================================

bool IsInFOV(float eyePos[3], float eyeAng[3], float targetPos[3], float fov)
{
    float dir[3], fwd[3];
    SubtractVectors(targetPos, eyePos, dir);
    NormalizeVector(dir, dir);
    GetAngleVectors(eyeAng, fwd, NULL_VECTOR, NULL_VECTOR);
    
    float dot = GetVectorDotProduct(fwd, dir);
    float angle = ArcCosine(dot) * (180.0 / 3.14159);
    
    return angle <= (fov / 2.0);
}

bool CanSeeTarget(float start[3], float end[3])
{
    Handle trace = TR_TraceRayFilterEx(start, end, MASK_SOLID, RayType_EndPoint, TraceFilter_NoPlayers);
    bool hit = TR_DidHit(trace);
    CloseHandle(trace);
    return !hit;
}

public bool TraceFilter_NoPlayers(int entity, int contentsMask)
{
    return entity > MaxClients;
}

bool WorldToScreen(float eyePos[3], float eyeAng[3], float targetPos[3], float &screenX, float &screenY)
{
    float dir[3], fwd[3], right[3], up[3];
    SubtractVectors(targetPos, eyePos, dir);
    GetAngleVectors(eyeAng, fwd, right, up);
    
    float dotFwd = GetVectorDotProduct(dir, fwd);
    if (dotFwd <= 1.0) return false;
    
    float dotRight = GetVectorDotProduct(dir, right);
    float dotUp = GetVectorDotProduct(dir, up);
    
    float fovRad = DegToRad(45.0);
    float tanFov = Tangent(fovRad);
    
    screenX = 0.5 + (dotRight / (dotFwd * tanFov * 1.33)) * 0.5;
    screenY = 0.5 - (dotUp / (dotFwd * tanFov)) * 0.5;
    
    return (screenX >= 0.0 && screenX <= 1.0 && screenY >= 0.0 && screenY <= 1.0);
}