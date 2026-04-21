#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2.1.0"

ConVar g_cvEnabled;
int g_iVelModOffset = -1;

public Plugin myinfo =
{
    name        = "No Tagging / No Slowdown on Hit",
    author      = "Assistant",
    description = "Menghilangkan efek melambat saat ditembak",
    version     = PLUGIN_VERSION,
    url         = ""
};

public void OnPluginStart()
{
    g_cvEnabled = CreateConVar("sm_notagging_enabled", "1", "Aktifkan anti-tagging", _, true, 0.0, true, 1.0);
    RegConsoleCmd("sm_checkvelmod", Command_CheckVelMod, "Cek velocity modifier");

    AutoExecConfig(true, "no_tagging");
    
    // Cari offset m_flVelocityModifier
    g_iVelModOffset = FindSendPropInfo("CCSPlayer", "m_flVelocityModifier");
    
    if (g_iVelModOffset == -1)
    {
        PrintToServer("[NoTagging] WARNING: m_flVelocityModifier tidak ditemukan!");
        PrintToServer("[NoTagging] Mencoba metode alternatif...");
    }
    else
    {
        PrintToServer("[NoTagging] m_flVelocityModifier offset: %d", g_iVelModOffset);
    }
    
    // Hook semua pemain
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_PreThinkPost, OnPreThinkPost);
        }
    }
    
    // Timer backup - setiap 0.1 detik
    CreateTimer(0.1, Timer_ResetVelocityMod, _, TIMER_REPEAT);
    
    PrintToServer("[NoTagging] Plugin v%s loaded!", PLUGIN_VERSION);
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_PreThinkPost, OnPreThinkPost);
}

// ============================================================
// PreThinkPost - Setelah game process, kita override
// ============================================================
public void OnPreThinkPost(int client)
{
    if (!g_cvEnabled.BoolValue)
        return;
    
    if (!IsPlayerAlive(client))
        return;
    
    ResetVelocityModifier(client);
}

// ============================================================
// Timer backup
// ============================================================
public Action Timer_ResetVelocityMod(Handle timer)
{
    if (!g_cvEnabled.BoolValue)
        return Plugin_Continue;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i))
        {
            ResetVelocityModifier(i);
        }
    }
    
    return Plugin_Continue;
}

// ============================================================
// Reset velocity modifier ke 1.0
// ============================================================
void ResetVelocityModifier(int client)
{
    if (g_iVelModOffset != -1)
    {
        // Gunakan offset langsung
        SetEntDataFloat(client, g_iVelModOffset, 1.0, true);
    }
    else
    {
        // Fallback: coba HasEntProp
        if (HasEntProp(client, Prop_Send, "m_flVelocityModifier"))
        {
            SetEntPropFloat(client, Prop_Send, "m_flVelocityModifier", 1.0);
        }
    }
}

public Action Command_CheckVelMod(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    
    float velMod = -1.0;
    
    if (g_iVelModOffset != -1)
    {
        velMod = GetEntDataFloat(client, g_iVelModOffset);
    }
    else if (HasEntProp(client, Prop_Send, "m_flVelocityModifier"))
    {
        velMod = GetEntPropFloat(client, Prop_Send, "m_flVelocityModifier");
    }
    
    PrintToChat(client, "[Debug] Velocity Modifier: %.3f (offset: %d)", velMod, g_iVelModOffset);
    
    return Plugin_Handled;
}