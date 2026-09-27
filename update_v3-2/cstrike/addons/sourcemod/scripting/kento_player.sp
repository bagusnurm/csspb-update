#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.1.0"
#define MAX_SOUNDS 55
#define MAX_MODELS 50
#define BREATH_CHECK_INTERVAL 0.5

// Original sounds yang bisa di-hook
char g_sPlayerSounds[][] = {
    "death1",
    "death2",
    "death3",
    "death4",
    "death5",
    "death6",
    "pl_burnpain1",
    "pl_burnpain2",
    "pl_burnpain3",
    "pl_pain5",
    "pl_pain6",
    "pl_pain7",
    "headshot1",
    "headshot2",
    "bhit_flesh-1",
    "bhit_flesh-2",
    "bhit_flesh-3",
    "bhit_helmet-1",
    "damage1",
    "damage2",
    "damage3",
    "pl_fallpain1",
    "pl_fallpain2",
    "pl_fallpain3",
    "pl_wade1",
    "pl_wade2",
    "pl_wade3",
    "pl_wade4",
    "breath"
};

// Index breath di array
#define SOUND_BREATH 28

// Default breath sound (bawaan game)
#define DEFAULT_BREATH_SOUND "player/breath.wav"

// Sniper weapon classnames (CS:Source)
char g_sSnipeWeapons[][] = {
    "weapon_awp",
    "weapon_scout",
    "weapon_sg550",
    "weapon_g3sg1",
    "weapon_m200",
    "weapon_l115a1"
};

// Storage config
char g_sCustomFiles[MAX_MODELS][MAX_SOUNDS][512];
char g_sModels[MAX_MODELS][512];
int g_iModelCount;

// Breath tracking per player
float g_fLastMoveTime[MAXPLAYERS + 1];
float g_fLastPosition[MAXPLAYERS + 1][3];
float g_fLastAngles[MAXPLAYERS + 1][3];
bool g_bIsBreathing[MAXPLAYERS + 1];
char g_sCurrentBreathSound[MAXPLAYERS + 1][512]; // track sound yg sedang play
Handle g_hBreathTimer[MAXPLAYERS + 1];
Handle g_hCheckTimer;

// ConVars
ConVar g_cvEnabled;
ConVar g_cvDebug;
ConVar g_cvBreathEnabled;
ConVar g_cvBreathIdleTime;
ConVar g_cvBreathLoopInterval;
ConVar g_cvBreathVolume;

public Plugin myinfo =
{
    name        = "Custom Player Sound + Breathing",
    author      = "Kento Style",
    description = "Custom player sounds per model with sniper scope breathing",
    version     = PLUGIN_VERSION,
    url         = ""
};

public void OnPluginStart()
{
    g_cvEnabled             = CreateConVar("sm_kplayer_enabled", "1", "Aktifkan custom player sound", _, true, 0.0, true, 1.0);
    g_cvDebug               = CreateConVar("sm_kplayer_debug", "0", "Debug mode", _, true, 0.0, true, 1.0);
    g_cvBreathEnabled       = CreateConVar("sm_kplayer_breath", "1", "Aktifkan breathing saat scope sniper dan diam", _, true, 0.0, true, 1.0);
    g_cvBreathIdleTime      = CreateConVar("sm_kplayer_breath_idle", "2.0", "Waktu diam (detik) sebelum mulai breathing", _, true, 0.5, true, 10.0);
    g_cvBreathLoopInterval  = CreateConVar("sm_kplayer_breath_loop", "3.0", "Interval loop breathing sound (detik)", _, true, 1.0, true, 10.0);
    g_cvBreathVolume        = CreateConVar("sm_kplayer_breath_vol", "0.6", "Volume breathing sound", _, true, 0.1, true, 1.0);

    AddNormalSoundHook(Hook_PlayerSound);

    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_start", Event_RoundStart);

    AutoExecConfig(true, "kento_player");

    PrintToServer("[KentoPlayer] Plugin v%s loaded!", PLUGIN_VERSION);
}

public void OnPluginEnd()
{
    StopAllBreathing();

    if (g_hCheckTimer != null)
    {
        KillTimer(g_hCheckTimer);
        g_hCheckTimer = null;
    }
}

public void OnMapStart()
{
    LoadConfig();

    // Precache default breath sound
    PrecacheSound(DEFAULT_BREATH_SOUND, true);

    // Start global check timer
    if (g_hCheckTimer != null)
    {
        KillTimer(g_hCheckTimer);
        g_hCheckTimer = null;
    }
    g_hCheckTimer = CreateTimer(BREATH_CHECK_INTERVAL, Timer_CheckPlayers, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
    StopAllBreathing();

    if (g_hCheckTimer != null)
    {
        KillTimer(g_hCheckTimer);
        g_hCheckTimer = null;
    }
}

public void OnClientPutInServer(int client)
{
    ResetClientBreathData(client);
}

public void OnClientDisconnect(int client)
{
    StopBreathing(client);
    ResetClientBreathData(client);
}

// ============================================================
// EVENTS
// ============================================================

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && client <= MaxClients)
    {
        StopBreathing(client);
    }
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    StopAllBreathing();
}

// ============================================================
// LOAD CONFIG
// ============================================================

void LoadConfig()
{
    char configFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configFile, sizeof(configFile), "configs/kento_player.cfg");

    g_iModelCount = 0;

    if (!FileExists(configFile))
    {
        PrintToServer("[KentoPlayer] Config tidak ditemukan: %s", configFile);
        PrintToServer("[KentoPlayer] Semua suara akan default.");
        return;
    }

    KeyValues kv = new KeyValues("PlayerSounds");

    if (!kv.ImportFromFile(configFile))
    {
        PrintToServer("[KentoPlayer] Gagal baca config: %s", configFile);
        delete kv;
        return;
    }

    if (!kv.GotoFirstSubKey())
    {
        PrintToServer("[KentoPlayer] Config kosong. Semua suara default.");
        delete kv;
        return;
    }

    char model[512];
    char file[512];

    do
    {
        if (g_iModelCount >= MAX_MODELS)
            break;

        kv.GetSectionName(model, sizeof(model));
        strcopy(g_sModels[g_iModelCount], sizeof(g_sModels[]), model);

        // Reset semua sound untuk model ini
        for (int i = 0; i < sizeof(g_sPlayerSounds); i++)
        {
            g_sCustomFiles[g_iModelCount][i][0] = '\0';
        }

        // Baca setiap sound dari config
        for (int i = 0; i < sizeof(g_sPlayerSounds); i++)
        {
            kv.GetString(g_sPlayerSounds[i], file, sizeof(file), "");

            if (!StrEqual(file, ""))
            {
                strcopy(g_sCustomFiles[g_iModelCount][i], sizeof(g_sCustomFiles[][]), file);

                PrecacheSound(file, true);

                char filepath[512];
                Format(filepath, sizeof(filepath), "sound/%s", file);
                AddFileToDownloadsTable(filepath);

                PrintToServer("[KentoPlayer] Model: %s | %s -> %s",
                    model, g_sPlayerSounds[i], file);
            }
        }

        g_iModelCount++;

    } while (kv.GotoNextKey());

    delete kv;

    PrintToServer("[KentoPlayer] Loaded %d model(s) dari config.", g_iModelCount);
}

// ============================================================
// SOUND HOOK
// ============================================================

public Action Hook_PlayerSound(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH],
    int &entity, int &channel, float &volume, int &level, int &pitch, int &flags)
{
    if (!g_cvEnabled.BoolValue)
        return Plugin_Continue;

    if (entity < 1 || entity > MaxClients)
        return Plugin_Continue;

    if (!IsClientInGame(entity))
        return Plugin_Continue;

    // ---- Hook breath sound dari engine ----
    // Jika game/engine emit "breath" sound, kita replace jika ada custom
    if (StrContains(sample, "breath", false) != -1)
    {
        return HandleBreathHook(entity, sample);
    }

    // ---- Hook player sounds biasa ----
    if (StrContains(sample, "player/") == -1 && StrContains(sample, "player\\") == -1)
        return Plugin_Continue;

    if (g_iModelCount == 0)
        return Plugin_Continue;

    char model[512];
    GetClientModel(entity, model, sizeof(model));

    int mid = FindModelID(model);
    if (mid == -1)
        return Plugin_Continue;

    int sid = FindSoundID(sample);
    if (sid == -1)
        return Plugin_Continue;

    if (g_sCustomFiles[mid][sid][0] == '\0')
        return Plugin_Continue;

    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[KentoPlayer] Replace: %s -> %s (model: %s)",
            sample, g_sCustomFiles[mid][sid], model);
    }

    strcopy(sample, sizeof(sample), g_sCustomFiles[mid][sid]);
    return Plugin_Changed;
}

// ============================================================
// HANDLE BREATH HOOK - ketika engine/game emit breath sound
// ============================================================

Action HandleBreathHook(int entity, char sample[PLATFORM_MAX_PATH])
{
    if (g_iModelCount == 0)
        return Plugin_Continue;

    char model[512];
    GetClientModel(entity, model, sizeof(model));

    int mid = FindModelID(model);
    if (mid == -1)
        return Plugin_Continue;

    // Cek ada custom breath di config?
    if (g_sCustomFiles[mid][SOUND_BREATH][0] == '\0')
        return Plugin_Continue; // tidak ada custom -> play default (player/breath.wav)

    // Ada custom -> replace
    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[KentoPlayer] Breath Hook: %s -> %s (model: %s)",
            sample, g_sCustomFiles[mid][SOUND_BREATH], model);
    }

    strcopy(sample, sizeof(sample), g_sCustomFiles[mid][SOUND_BREATH]);
    return Plugin_Changed;
}

// ============================================================
// GLOBAL CHECK TIMER - Cek semua player
// ============================================================

public Action Timer_CheckPlayers(Handle timer)
{
    if (!g_cvEnabled.BoolValue || !g_cvBreathEnabled.BoolValue)
        return Plugin_Continue;

    float currentTime = GetGameTime();

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsPlayerAlive(client))
        {
            if (g_bIsBreathing[client])
                StopBreathing(client);
            continue;
        }

        bool isScoped = IsPlayerScoped(client);
        bool hasSniper = IsHoldingSniper(client);
        bool isIdle = IsPlayerIdle(client);

        // Kondisi breathing: pegang sniper + scope + diam
        if (hasSniper && isScoped && isIdle)
        {
            float idleTime = currentTime - g_fLastMoveTime[client];

            if (idleTime >= g_cvBreathIdleTime.FloatValue && !g_bIsBreathing[client])
            {
                StartBreathing(client);
            }
        }
        else
        {
            // Kondisi tidak terpenuhi -> stop breathing
            if (g_bIsBreathing[client])
                StopBreathing(client);

            // Update waktu terakhir bergerak jika tidak idle
            if (!isIdle)
                g_fLastMoveTime[client] = currentTime;
        }

        // Simpan posisi & angle terakhir untuk cek frame berikutnya
        float pos[3], ang[3];
        GetClientAbsOrigin(client, pos);
        GetClientEyeAngles(client, ang);
        g_fLastPosition[client] = pos;
        g_fLastAngles[client] = ang;
    }

    return Plugin_Continue;
}

// ============================================================
// CEK STATUS PLAYER
// ============================================================

bool IsPlayerScoped(int client)
{
    int fov = GetEntProp(client, Prop_Send, "m_iFOV");
    int defaultFov = GetEntProp(client, Prop_Send, "m_iDefaultFOV");

    // FOV lebih kecil dari default = sedang scope
    // FOV 0 = memakai default FOV (tidak scope)
    if (fov > 0 && fov < defaultFov)
        return true;

    return false;
}

bool IsHoldingSniper(int client)
{
    char weapon[64];
    GetClientWeapon(client, weapon, sizeof(weapon));

    for (int i = 0; i < sizeof(g_sSnipeWeapons); i++)
    {
        if (StrEqual(weapon, g_sSnipeWeapons[i], false))
            return true;
    }
    return false;
}

bool IsPlayerIdle(int client)
{
    float pos[3], ang[3];
    GetClientAbsOrigin(client, pos);
    GetClientEyeAngles(client, ang);

    float posDiff = GetVectorDistance(pos, g_fLastPosition[client]);

    float angDiff = FloatAbs(ang[0] - g_fLastAngles[client][0]) +
                    FloatAbs(ang[1] - g_fLastAngles[client][1]);

    // Threshold kecil untuk floating point noise
    if (posDiff > 1.0 || angDiff > 0.5)
        return false;

    return true;
}

// ============================================================
// BREATHING CONTROL
// ============================================================

void StartBreathing(int client)
{
    if (g_bIsBreathing[client])
        return;

    g_bIsBreathing[client] = true;

    // Play pertama kali
    PlayBreathSound(client);

    // Loop timer
    float interval = g_cvBreathLoopInterval.FloatValue;
    g_hBreathTimer[client] = CreateTimer(interval, Timer_BreathLoop, GetClientUserId(client),
        TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    if (g_cvDebug.BoolValue)
        PrintToServer("[KentoPlayer] Client %d started breathing", client);
}

void StopBreathing(int client)
{
    if (!g_bIsBreathing[client])
        return;

    g_bIsBreathing[client] = false;

    if (g_hBreathTimer[client] != null)
    {
        KillTimer(g_hBreathTimer[client]);
        g_hBreathTimer[client] = null;
    }

    // Stop sound yang sedang play
    if (IsClientInGame(client) && g_sCurrentBreathSound[client][0] != '\0')
    {
        StopSound(client, SNDCHAN_VOICE, g_sCurrentBreathSound[client]);
        g_sCurrentBreathSound[client][0] = '\0';
    }

    if (g_cvDebug.BoolValue)
        PrintToServer("[KentoPlayer] Client %d stopped breathing", client);
}

void StopAllBreathing()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        StopBreathing(i);
        ResetClientBreathData(i);
    }
}

void ResetClientBreathData(int client)
{
    g_fLastMoveTime[client] = GetGameTime();
    g_fLastPosition[client][0] = 0.0;
    g_fLastPosition[client][1] = 0.0;
    g_fLastPosition[client][2] = 0.0;
    g_fLastAngles[client][0] = 0.0;
    g_fLastAngles[client][1] = 0.0;
    g_fLastAngles[client][2] = 0.0;
    g_bIsBreathing[client] = false;
    g_sCurrentBreathSound[client][0] = '\0';
    g_hBreathTimer[client] = null;
}

// ============================================================
// BREATH LOOP TIMER
// ============================================================

public Action Timer_BreathLoop(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        if (client > 0)
        {
            g_bIsBreathing[client] = false;
            g_hBreathTimer[client] = null;
        }
        return Plugin_Stop;
    }

    if (!g_bIsBreathing[client])
    {
        g_hBreathTimer[client] = null;
        return Plugin_Stop;
    }

    // Double check kondisi masih terpenuhi
    if (!IsHoldingSniper(client) || !IsPlayerScoped(client))
    {
        StopBreathing(client);
        return Plugin_Stop;
    }

    PlayBreathSound(client);
    return Plugin_Continue;
}

// ============================================================
// PLAY BREATH SOUND
// ============================================================
// Logika:
//   1. Cek model player di config
//   2. Jika ada key "breath" di config -> pakai custom file
//   3. Jika TIDAK ada key "breath" di config -> pakai DEFAULT_BREATH_SOUND
//   4. Jika model TIDAK ada di config sama sekali -> pakai DEFAULT_BREATH_SOUND
// ============================================================

void PlayBreathSound(int client)
{
    char breathSound[512];

    // Tentukan sound yang akan dipakai
    ResolveBreathSound(client, breathSound, sizeof(breathSound));

    if (breathSound[0] == '\0')
        return;

    float vol = g_cvBreathVolume.FloatValue;

    // Simpan sound yang sedang play (untuk StopSound nanti)
    strcopy(g_sCurrentBreathSound[client], sizeof(g_sCurrentBreathSound[]), breathSound);

    EmitSoundToAll(breathSound, client, SNDCHAN_VOICE, SNDLEVEL_NORMAL, SND_NOFLAGS, vol);

    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[KentoPlayer] Breath play: %s for client %d (vol: %.2f)",
            breathSound, client, vol);
    }
}

// ============================================================
// RESOLVE BREATH SOUND
// ============================================================
// Cari sound breath yang tepat untuk client ini:
//   - Ada di config dengan key "breath"? -> pakai custom
//   - Tidak ada? -> pakai player/breath.wav (default)
// ============================================================

void ResolveBreathSound(int client, char[] buffer, int maxlen)
{
    char model[512];
    GetClientModel(client, model, sizeof(model));

    int mid = FindModelID(model);

    // Model ditemukan di config
    if (mid != -1)
    {
        // Ada custom breath di config?
        if (g_sCustomFiles[mid][SOUND_BREATH][0] != '\0')
        {
            // PAKAI CUSTOM dari config
            strcopy(buffer, maxlen, g_sCustomFiles[mid][SOUND_BREATH]);

            if (g_cvDebug.BoolValue)
            {
                PrintToServer("[KentoPlayer] Breath resolve: custom -> %s (model: %s)",
                    buffer, model);
            }
            return;
        }
    }

    // TIDAK ADA custom breath di config ATAU model tidak ada di config
    // -> pakai DEFAULT: player/breath.wav
    strcopy(buffer, maxlen, DEFAULT_BREATH_SOUND);

    if (g_cvDebug.BoolValue)
    {
        PrintToServer("[KentoPlayer] Breath resolve: default -> %s (model: %s)",
            buffer, model);
    }
}

// ============================================================
// FIND MODEL
// ============================================================

int FindModelID(const char[] model)
{
    for (int i = 0; i < g_iModelCount; i++)
    {
        if (StrContains(model, g_sModels[i], false) != -1)
            return i;
    }
    return -1;
}

// ============================================================
// FIND SOUND
// ============================================================

int FindSoundID(const char[] sample)
{
    for (int i = 0; i < sizeof(g_sPlayerSounds); i++)
    {
        if (StrContains(sample, g_sPlayerSounds[i], false) != -1)
            return i;
    }
    return -1;
}