#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"
#define MAX_MISSIONS_PER_CARD 4
#define MAX_CARDS 50
#define HUD_REFRESH_INTERVAL 1.0

// ============================================================
// MISSION TYPES
// ============================================================

enum MissionType
{
    MISSION_KILL_ANY = 0,
    MISSION_KILL_HEADSHOT,
    MISSION_KILL_KNIFE,
    MISSION_KILL_GRENADE,
    MISSION_KILL_PISTOL,
    MISSION_KILL_SHOTGUN,
    MISSION_KILL_SMG,
    MISSION_KILL_RIFLE,
    MISSION_KILL_SNIPER,
    MISSION_KILL_MG,
    MISSION_WIN_ROUND,
    MISSION_PLANT_BOMB,
    MISSION_DEFUSE_BOMB,
    MISSION_ASSIST,
    MISSION_SURVIVE_ROUND,
    MISSION_KILL_STREAK,
    MISSION_DEATH,
    MISSION_PLAY_ROUND
}

char g_sMissionTypeName[][] = {
    "Kill Enemy",
    "Headshot Kill",
    "Knife Kill",
    "Grenade Kill",
    "Pistol Kill",
    "Shotgun Kill",
    "SMG Kill",
    "Rifle Kill",
    "Sniper Kill",
    "Machine Gun Kill",
    "Win Round",
    "Plant Bomb",
    "Defuse Bomb",
    "Assist Kill",
    "Survive Round",
    "Kill Streak",
    "Die in Battle",
    "Play Round"
};

// ============================================================
// WEAPON CATEGORY
// ============================================================

enum WeaponCategory
{
    WCAT_UNKNOWN = 0,
    WCAT_PISTOL,
    WCAT_SHOTGUN,
    WCAT_SMG,
    WCAT_RIFLE,
    WCAT_SNIPER,
    WCAT_MG,
    WCAT_KNIFE,
    WCAT_GRENADE
}

// ============================================================
// CARD DATA - Flat storage (no nested struct)
// ============================================================

// Card info
char g_sCardName[MAX_CARDS][64];
char g_sCardTier[MAX_CARDS][16];
int g_iCardBonusPoints[MAX_CARDS];
int g_iCardBonusExp[MAX_CARDS];
int g_iCardMissionCount[MAX_CARDS];

// Mission info per card - [card_index][mission_index]
MissionType g_eMissionType[MAX_CARDS][MAX_MISSIONS_PER_CARD];
int g_iMissionTarget[MAX_CARDS][MAX_MISSIONS_PER_CARD];
int g_iMissionRewardPoints[MAX_CARDS][MAX_MISSIONS_PER_CARD];
int g_iMissionRewardExp[MAX_CARDS][MAX_MISSIONS_PER_CARD];
char g_sMissionDesc[MAX_CARDS * MAX_MISSIONS_PER_CARD][128]; // Flat: index = card * 4 + mission

int g_iCardCount;

// ============================================================
// PLAYER DATA
// ============================================================

int g_iPlayerCardIndex[MAXPLAYERS + 1];
bool g_bPlayerHasCard[MAXPLAYERS + 1];
bool g_bPlayerCardCompleted[MAXPLAYERS + 1];
int g_iPlayerMissionCurrent[MAXPLAYERS + 1][MAX_MISSIONS_PER_CARD];
bool g_bPlayerMissionDone[MAXPLAYERS + 1][MAX_MISSIONS_PER_CARD];
int g_iPlayerKillStreak[MAXPLAYERS + 1];
bool g_bPlayerSurvivedRound[MAXPLAYERS + 1];
int g_iPlayerPoints[MAXPLAYERS + 1];
int g_iPlayerEXP[MAXPLAYERS + 1];
int g_iRerollCount[MAXPLAYERS + 1];

// ConVars
ConVar g_cvEnabled;
ConVar g_cvDebug;
ConVar g_cvHudEnabled;
ConVar g_cvAutoAssign;
ConVar g_cvMaxReroll;

// HUD timer
Handle g_hHudTimer;

// ============================================================
// HELPER: Get mission description index (flat)
// ============================================================

int GetDescIndex(int card, int mission)
{
    return card * MAX_MISSIONS_PER_CARD + mission;
}

// ============================================================
// PLUGIN INFO
// ============================================================

public Plugin myinfo =
{
    name        = "PB Mission Card System",
    author      = "Kento Style",
    description = "Point Blank style mission card with 4 missions per card",
    version     = PLUGIN_VERSION,
    url         = ""
};

// ============================================================
// PLUGIN START
// ============================================================

public void OnPluginStart()
{
    g_cvEnabled    = CreateConVar("sm_mission_enabled", "1", "Enable mission card system", _, true, 0.0, true, 1.0);
    g_cvDebug      = CreateConVar("sm_mission_debug", "0", "Debug mode", _, true, 0.0, true, 1.0);
    g_cvHudEnabled = CreateConVar("sm_mission_hud", "1", "Show mission HUD", _, true, 0.0, true, 1.0);
    g_cvAutoAssign = CreateConVar("sm_mission_auto", "1", "Auto assign card on connect", _, true, 0.0, true, 1.0);
    g_cvMaxReroll  = CreateConVar("sm_mission_reroll", "3", "Max reroll per map", _, true, 0.0, true, 10.0);

    RegConsoleCmd("sm_mission", Cmd_Mission, "Show mission card");
    RegConsoleCmd("sm_misi", Cmd_Mission, "Show mission card");
    RegConsoleCmd("sm_card", Cmd_Mission, "Show mission card");
    RegConsoleCmd("sm_reroll", Cmd_Reroll, "Reroll mission card");
    RegConsoleCmd("sm_missions", Cmd_MissionMenu, "Mission menu");

    RegAdminCmd("sm_mission_reload", Cmd_Reload, ADMFLAG_ROOT, "Reload mission config");
    RegAdminCmd("sm_mission_give", Cmd_GiveCard, ADMFLAG_ROOT, "Give card to player");
    RegAdminCmd("sm_mission_reset", Cmd_ResetCard, ADMFLAG_ROOT, "Reset player card");

    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("round_start", Event_RoundStart);
    HookEvent("bomb_planted", Event_BombPlanted);
    HookEvent("bomb_defused", Event_BombDefused);

    AutoExecConfig(true, "pb_mission");

    PrintToServer("[PBMission] Plugin v%s loaded!", PLUGIN_VERSION);
}

public void OnMapStart()
{
    LoadMissionConfig();

    if (g_hHudTimer != null)
    {
        KillTimer(g_hHudTimer);
        g_hHudTimer = null;
    }
    g_hHudTimer = CreateTimer(HUD_REFRESH_INTERVAL, Timer_RefreshHUD, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
    if (g_hHudTimer != null)
    {
        KillTimer(g_hHudTimer);
        g_hHudTimer = null;
    }
}

public void OnClientPutInServer(int client)
{
    ResetPlayerProgress(client);

    if (g_cvAutoAssign.BoolValue && g_iCardCount > 0)
    {
        CreateTimer(3.0, Timer_AutoAssign, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnClientDisconnect(int client)
{
    ResetPlayerProgress(client);
}

// ============================================================
// LOAD CONFIG
// ============================================================

void LoadMissionConfig()
{
    char configFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configFile, sizeof(configFile), "configs/pb_missions.cfg");

    g_iCardCount = 0;

    if (!FileExists(configFile))
    {
        PrintToServer("[PBMission] Config not found: %s", configFile);
        PrintToServer("[PBMission] Generating default config...");
        GenerateDefaultConfig(configFile);
        return;
    }

    KeyValues kv = new KeyValues("MissionCards");

    if (!kv.ImportFromFile(configFile))
    {
        PrintToServer("[PBMission] Failed to read config!");
        delete kv;
        return;
    }

    if (!kv.GotoFirstSubKey())
    {
        PrintToServer("[PBMission] Config is empty!");
        delete kv;
        return;
    }

    char buffer[128];

    do
    {
        if (g_iCardCount >= MAX_CARDS)
            break;

        int c = g_iCardCount;

        kv.GetSectionName(g_sCardName[c], sizeof(g_sCardName[]));
        kv.GetString("tier", g_sCardTier[c], sizeof(g_sCardTier[]), "Bronze");
        g_iCardBonusPoints[c] = kv.GetNum("bonus_points", 100);
        g_iCardBonusExp[c] = kv.GetNum("bonus_exp", 50);
        g_iCardMissionCount[c] = 0;

        for (int m = 0; m < MAX_MISSIONS_PER_CARD; m++)
        {
            // Read type
            Format(buffer, sizeof(buffer), "mission%d_type", m + 1);
            char typeStr[32];
            kv.GetString(buffer, typeStr, sizeof(typeStr), "");

            if (StrEqual(typeStr, ""))
                continue;

            g_eMissionType[c][m] = ParseMissionType(typeStr);

            // Read target
            Format(buffer, sizeof(buffer), "mission%d_target", m + 1);
            g_iMissionTarget[c][m] = kv.GetNum(buffer, 1);

            // Read reward points
            Format(buffer, sizeof(buffer), "mission%d_points", m + 1);
            g_iMissionRewardPoints[c][m] = kv.GetNum(buffer, 50);

            // Read reward exp
            Format(buffer, sizeof(buffer), "mission%d_exp", m + 1);
            g_iMissionRewardExp[c][m] = kv.GetNum(buffer, 25);

            // Read description
            int descIdx = GetDescIndex(c, m);
            Format(buffer, sizeof(buffer), "mission%d_desc", m + 1);
            kv.GetString(buffer, g_sMissionDesc[descIdx], sizeof(g_sMissionDesc[]), "");

            // Auto generate jika kosong
            if (StrEqual(g_sMissionDesc[descIdx], ""))
            {
                Format(g_sMissionDesc[descIdx], sizeof(g_sMissionDesc[]),
                    "%s x%d",
                    g_sMissionTypeName[view_as<int>(g_eMissionType[c][m])],
                    g_iMissionTarget[c][m]);
            }

            g_iCardMissionCount[c]++;
        }

        if (g_cvDebug.BoolValue)
        {
            PrintToServer("[PBMission] Card: %s [%s] - %d missions",
                g_sCardName[c], g_sCardTier[c], g_iCardMissionCount[c]);
        }

        g_iCardCount++;

    } while (kv.GotoNextKey());

    delete kv;

    PrintToServer("[PBMission] Loaded %d mission card(s).", g_iCardCount);
}

// ============================================================
// GENERATE DEFAULT CONFIG
// ============================================================

void GenerateDefaultConfig(const char[] path)
{
    KeyValues kv = new KeyValues("MissionCards");

    // Card 1
    kv.JumpToKey("Beginner Card", true);
    kv.SetString("tier", "Bronze");
    kv.SetNum("bonus_points", 100);
    kv.SetNum("bonus_exp", 50);
    kv.SetString("mission1_type", "kill_any");
    kv.SetNum("mission1_target", 5);
    kv.SetNum("mission1_points", 50);
    kv.SetNum("mission1_exp", 25);
    kv.SetString("mission1_desc", "Kill 5 enemies");
    kv.SetString("mission2_type", "kill_headshot");
    kv.SetNum("mission2_target", 2);
    kv.SetNum("mission2_points", 75);
    kv.SetNum("mission2_exp", 40);
    kv.SetString("mission2_desc", "Get 2 headshot kills");
    kv.SetString("mission3_type", "win_round");
    kv.SetNum("mission3_target", 3);
    kv.SetNum("mission3_points", 60);
    kv.SetNum("mission3_exp", 30);
    kv.SetString("mission3_desc", "Win 3 rounds");
    kv.SetString("mission4_type", "play_round");
    kv.SetNum("mission4_target", 5);
    kv.SetNum("mission4_points", 30);
    kv.SetNum("mission4_exp", 15);
    kv.SetString("mission4_desc", "Play 5 rounds");
    kv.GoBack();

    // Card 2
    kv.JumpToKey("SMG Specialist", true);
    kv.SetString("tier", "Bronze");
    kv.SetNum("bonus_points", 120);
    kv.SetNum("bonus_exp", 60);
    kv.SetString("mission1_type", "kill_smg");
    kv.SetNum("mission1_target", 3);
    kv.SetNum("mission1_points", 60);
    kv.SetNum("mission1_exp", 30);
    kv.SetString("mission1_desc", "Kill 3 with Sub Machine Gun");
    kv.SetString("mission2_type", "kill_headshot");
    kv.SetNum("mission2_target", 1);
    kv.SetNum("mission2_points", 50);
    kv.SetNum("mission2_exp", 25);
    kv.SetString("mission2_desc", "Get 1 headshot kill");
    kv.SetString("mission3_type", "kill_any");
    kv.SetNum("mission3_target", 7);
    kv.SetNum("mission3_points", 70);
    kv.SetNum("mission3_exp", 35);
    kv.SetString("mission3_desc", "Kill 7 enemies");
    kv.SetString("mission4_type", "survive_round");
    kv.SetNum("mission4_target", 2);
    kv.SetNum("mission4_points", 80);
    kv.SetNum("mission4_exp", 40);
    kv.SetString("mission4_desc", "Survive 2 rounds");
    kv.GoBack();

    // Card 3
    kv.JumpToKey("Sniper Elite", true);
    kv.SetString("tier", "Silver");
    kv.SetNum("bonus_points", 200);
    kv.SetNum("bonus_exp", 100);
    kv.SetString("mission1_type", "kill_sniper");
    kv.SetNum("mission1_target", 5);
    kv.SetNum("mission1_points", 100);
    kv.SetNum("mission1_exp", 50);
    kv.SetString("mission1_desc", "Kill 5 with Sniper Rifle");
    kv.SetString("mission2_type", "kill_headshot");
    kv.SetNum("mission2_target", 3);
    kv.SetNum("mission2_points", 120);
    kv.SetNum("mission2_exp", 60);
    kv.SetString("mission2_desc", "Get 3 headshot kills");
    kv.SetString("mission3_type", "kill_streak");
    kv.SetNum("mission3_target", 3);
    kv.SetNum("mission3_points", 150);
    kv.SetNum("mission3_exp", 75);
    kv.SetString("mission3_desc", "3 kill streak in 1 round");
    kv.SetString("mission4_type", "win_round");
    kv.SetNum("mission4_target", 5);
    kv.SetNum("mission4_points", 100);
    kv.SetNum("mission4_exp", 50);
    kv.SetString("mission4_desc", "Win 5 rounds");
    kv.GoBack();

    // Card 4
    kv.JumpToKey("Close Combat", true);
    kv.SetString("tier", "Silver");
    kv.SetNum("bonus_points", 180);
    kv.SetNum("bonus_exp", 90);
    kv.SetString("mission1_type", "kill_knife");
    kv.SetNum("mission1_target", 2);
    kv.SetNum("mission1_points", 100);
    kv.SetNum("mission1_exp", 50);
    kv.SetString("mission1_desc", "Kill 2 with Knife");
    kv.SetString("mission2_type", "kill_shotgun");
    kv.SetNum("mission2_target", 3);
    kv.SetNum("mission2_points", 80);
    kv.SetNum("mission2_exp", 40);
    kv.SetString("mission2_desc", "Kill 3 with Shotgun");
    kv.SetString("mission3_type", "kill_grenade");
    kv.SetNum("mission3_target", 1);
    kv.SetNum("mission3_points", 120);
    kv.SetNum("mission3_exp", 60);
    kv.SetString("mission3_desc", "Kill 1 with Grenade");
    kv.SetString("mission4_type", "kill_any");
    kv.SetNum("mission4_target", 10);
    kv.SetNum("mission4_points", 80);
    kv.SetNum("mission4_exp", 40);
    kv.SetString("mission4_desc", "Kill 10 enemies total");
    kv.GoBack();

    // Card 5
    kv.JumpToKey("Demolition Expert", true);
    kv.SetString("tier", "Gold");
    kv.SetNum("bonus_points", 300);
    kv.SetNum("bonus_exp", 150);
    kv.SetString("mission1_type", "plant_bomb");
    kv.SetNum("mission1_target", 2);
    kv.SetNum("mission1_points", 100);
    kv.SetNum("mission1_exp", 50);
    kv.SetString("mission1_desc", "Plant bomb 2 times");
    kv.SetString("mission2_type", "defuse_bomb");
    kv.SetNum("mission2_target", 1);
    kv.SetNum("mission2_points", 120);
    kv.SetNum("mission2_exp", 60);
    kv.SetString("mission2_desc", "Defuse bomb 1 time");
    kv.SetString("mission3_type", "kill_any");
    kv.SetNum("mission3_target", 15);
    kv.SetNum("mission3_points", 100);
    kv.SetNum("mission3_exp", 50);
    kv.SetString("mission3_desc", "Kill 15 enemies");
    kv.SetString("mission4_type", "win_round");
    kv.SetNum("mission4_target", 7);
    kv.SetNum("mission4_points", 120);
    kv.SetNum("mission4_exp", 60);
    kv.SetString("mission4_desc", "Win 7 rounds");
    kv.GoBack();

    kv.ExportToFile(path);
    delete kv;

    PrintToServer("[PBMission] Default config generated: %s", path);
    LoadMissionConfig();
}

// ============================================================
// PARSE MISSION TYPE
// ============================================================

MissionType ParseMissionType(const char[] typeStr)
{
    if (StrEqual(typeStr, "kill_any", false))        return MISSION_KILL_ANY;
    if (StrEqual(typeStr, "kill_headshot", false))    return MISSION_KILL_HEADSHOT;
    if (StrEqual(typeStr, "kill_knife", false))       return MISSION_KILL_KNIFE;
    if (StrEqual(typeStr, "kill_grenade", false))     return MISSION_KILL_GRENADE;
    if (StrEqual(typeStr, "kill_pistol", false))      return MISSION_KILL_PISTOL;
    if (StrEqual(typeStr, "kill_shotgun", false))     return MISSION_KILL_SHOTGUN;
    if (StrEqual(typeStr, "kill_smg", false))         return MISSION_KILL_SMG;
    if (StrEqual(typeStr, "kill_rifle", false))       return MISSION_KILL_RIFLE;
    if (StrEqual(typeStr, "kill_sniper", false))      return MISSION_KILL_SNIPER;
    if (StrEqual(typeStr, "kill_mg", false))          return MISSION_KILL_MG;
    if (StrEqual(typeStr, "win_round", false))        return MISSION_WIN_ROUND;
    if (StrEqual(typeStr, "plant_bomb", false))       return MISSION_PLANT_BOMB;
    if (StrEqual(typeStr, "defuse_bomb", false))      return MISSION_DEFUSE_BOMB;
    if (StrEqual(typeStr, "assist", false))           return MISSION_ASSIST;
    if (StrEqual(typeStr, "survive_round", false))    return MISSION_SURVIVE_ROUND;
    if (StrEqual(typeStr, "kill_streak", false))      return MISSION_KILL_STREAK;
    if (StrEqual(typeStr, "death", false))            return MISSION_DEATH;
    if (StrEqual(typeStr, "play_round", false))       return MISSION_PLAY_ROUND;
    return MISSION_KILL_ANY;
}

// ============================================================
// WEAPON CLASSIFIER
// ============================================================

WeaponCategory ClassifyWeapon(const char[] weapon)
{
    if (StrEqual(weapon, "weapon_knife", false))
        return WCAT_KNIFE;

    if (StrEqual(weapon, "weapon_hegrenade", false) ||
        StrEqual(weapon, "weapon_flashbang", false) ||
        StrEqual(weapon, "weapon_smokegrenade", false))
        return WCAT_GRENADE;

    if (StrEqual(weapon, "weapon_glock", false) ||
        StrEqual(weapon, "weapon_usp", false) ||
        StrEqual(weapon, "weapon_p228", false) ||
        StrEqual(weapon, "weapon_deagle", false) ||
        StrEqual(weapon, "weapon_fiveseven", false) ||
        StrEqual(weapon, "weapon_elite", false))
        return WCAT_PISTOL;

    if (StrEqual(weapon, "weapon_m3", false) ||
        StrEqual(weapon, "weapon_xm1014", false))
        return WCAT_SHOTGUN;

    if (StrEqual(weapon, "weapon_mac10", false) ||
        StrEqual(weapon, "weapon_tmp", false) ||
        StrEqual(weapon, "weapon_mp5navy", false) ||
        StrEqual(weapon, "weapon_ump45", false) ||
        StrEqual(weapon, "weapon_p90", false))
        return WCAT_SMG;

    if (StrEqual(weapon, "weapon_scout", false) ||
        StrEqual(weapon, "weapon_awp", false) ||
        StrEqual(weapon, "weapon_sg550", false) ||
        StrEqual(weapon, "weapon_g3sg1", false))
        return WCAT_SNIPER;

    if (StrEqual(weapon, "weapon_m249", false))
        return WCAT_MG;

    if (StrEqual(weapon, "weapon_ak47", false) ||
        StrEqual(weapon, "weapon_m4a1", false) ||
        StrEqual(weapon, "weapon_sg552", false) ||
        StrEqual(weapon, "weapon_aug", false) ||
        StrEqual(weapon, "weapon_famas", false) ||
        StrEqual(weapon, "weapon_galil", false))
        return WCAT_RIFLE;

    return WCAT_UNKNOWN;
}

// ============================================================
// EVENT: PLAYER DEATH
// ============================================================

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue)
        return;

    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    bool headshot = event.GetBool("headshot");

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    char weaponFull[64];
    Format(weaponFull, sizeof(weaponFull), "weapon_%s", weapon);

    WeaponCategory wcat = ClassifyWeapon(weaponFull);

    // --- ATTACKER missions ---
    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && attacker != victim)
    {
        if (g_bPlayerHasCard[attacker])
        {
            g_iPlayerKillStreak[attacker]++;

            int c = g_iPlayerCardIndex[attacker];

            for (int m = 0; m < g_iCardMissionCount[c]; m++)
            {
                if (g_bPlayerMissionDone[attacker][m])
                    continue;

                MissionType mtype = g_eMissionType[c][m];
                bool counted = false;

                switch (mtype)
                {
                    case MISSION_KILL_ANY:      counted = true;
                    case MISSION_KILL_HEADSHOT:  counted = headshot;
                    case MISSION_KILL_KNIFE:     counted = (wcat == WCAT_KNIFE);
                    case MISSION_KILL_GRENADE:   counted = (wcat == WCAT_GRENADE);
                    case MISSION_KILL_PISTOL:    counted = (wcat == WCAT_PISTOL);
                    case MISSION_KILL_SHOTGUN:   counted = (wcat == WCAT_SHOTGUN);
                    case MISSION_KILL_SMG:       counted = (wcat == WCAT_SMG);
                    case MISSION_KILL_RIFLE:     counted = (wcat == WCAT_RIFLE);
                    case MISSION_KILL_SNIPER:    counted = (wcat == WCAT_SNIPER);
                    case MISSION_KILL_MG:        counted = (wcat == WCAT_MG);
                    case MISSION_KILL_STREAK:
                    {
                        if (g_iPlayerKillStreak[attacker] >= g_iMissionTarget[c][m])
                        {
                            g_iPlayerMissionCurrent[attacker][m] = g_iMissionTarget[c][m];
                            CheckMissionComplete(attacker, m);
                        }
                    }
                }

                if (counted)
                {
                    g_iPlayerMissionCurrent[attacker][m]++;
                    CheckMissionComplete(attacker, m);
                }
            }

            ShowMissionHUD(attacker);
        }
    }

    // --- VICTIM missions ---
    if (victim > 0 && victim <= MaxClients && IsClientInGame(victim))
    {
        if (g_bPlayerHasCard[victim])
        {
            g_iPlayerKillStreak[victim] = 0;
            g_bPlayerSurvivedRound[victim] = false;

            int c = g_iPlayerCardIndex[victim];

            for (int m = 0; m < g_iCardMissionCount[c]; m++)
            {
                if (g_bPlayerMissionDone[victim][m])
                    continue;

                if (g_eMissionType[c][m] == MISSION_DEATH)
                {
                    g_iPlayerMissionCurrent[victim][m]++;
                    CheckMissionComplete(victim, m);
                }
            }

            ShowMissionHUD(victim);
        }
    }
}

// ============================================================
// EVENT: ROUND START
// ============================================================

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue)
        return;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;

        g_iPlayerKillStreak[i] = 0;
        g_bPlayerSurvivedRound[i] = true;
    }
}

// ============================================================
// EVENT: ROUND END
// ============================================================

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue)
        return;

    int winner = event.GetInt("winner");

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !g_bPlayerHasCard[i])
            continue;

        int c = g_iPlayerCardIndex[i];
        int team = GetClientTeam(i);

        for (int m = 0; m < g_iCardMissionCount[c]; m++)
        {
            if (g_bPlayerMissionDone[i][m])
                continue;

            MissionType mtype = g_eMissionType[c][m];

            switch (mtype)
            {
                case MISSION_WIN_ROUND:
                {
                    if (team == winner)
                    {
                        g_iPlayerMissionCurrent[i][m]++;
                        CheckMissionComplete(i, m);
                    }
                }
                case MISSION_SURVIVE_ROUND:
                {
                    if (IsPlayerAlive(i) && g_bPlayerSurvivedRound[i])
                    {
                        g_iPlayerMissionCurrent[i][m]++;
                        CheckMissionComplete(i, m);
                    }
                }
                case MISSION_PLAY_ROUND:
                {
                    g_iPlayerMissionCurrent[i][m]++;
                    CheckMissionComplete(i, m);
                }
                case MISSION_KILL_STREAK:
                {
                    if (g_iPlayerKillStreak[i] >= g_iMissionTarget[c][m])
                    {
                        if (g_iPlayerMissionCurrent[i][m] < g_iMissionTarget[c][m])
                        {
                            g_iPlayerMissionCurrent[i][m] = g_iMissionTarget[c][m];
                            CheckMissionComplete(i, m);
                        }
                    }
                }
            }
        }

        ShowMissionHUD(i);
    }
}

// ============================================================
// EVENT: BOMB
// ============================================================

public void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client) || !g_bPlayerHasCard[client])
        return;

    int c = g_iPlayerCardIndex[client];

    for (int m = 0; m < g_iCardMissionCount[c]; m++)
    {
        if (g_bPlayerMissionDone[client][m])
            continue;

        if (g_eMissionType[c][m] == MISSION_PLANT_BOMB)
        {
            g_iPlayerMissionCurrent[client][m]++;
            CheckMissionComplete(client, m);
        }
    }

    ShowMissionHUD(client);
}

public void Event_BombDefused(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client) || !g_bPlayerHasCard[client])
        return;

    int c = g_iPlayerCardIndex[client];

    for (int m = 0; m < g_iCardMissionCount[c]; m++)
    {
        if (g_bPlayerMissionDone[client][m])
            continue;

        if (g_eMissionType[c][m] == MISSION_DEFUSE_BOMB)
        {
            g_iPlayerMissionCurrent[client][m]++;
            CheckMissionComplete(client, m);
        }
    }

    ShowMissionHUD(client);
}

// ============================================================
// CHECK MISSION COMPLETE
// ============================================================

void CheckMissionComplete(int client, int missionIdx)
{
    int c = g_iPlayerCardIndex[client];
    int target = g_iMissionTarget[c][missionIdx];
    int current = g_iPlayerMissionCurrent[client][missionIdx];

    if (current >= target && !g_bPlayerMissionDone[client][missionIdx])
    {
        g_bPlayerMissionDone[client][missionIdx] = true;
        g_iPlayerMissionCurrent[client][missionIdx] = target;

        int points = g_iMissionRewardPoints[c][missionIdx];
        int exp = g_iMissionRewardExp[c][missionIdx];
        g_iPlayerPoints[client] += points;
        g_iPlayerEXP[client] += exp;

        int descIdx = GetDescIndex(c, missionIdx);

        PrintToChat(client, " \x04[MISSION]\x01 Completed: \x03%s\x01 | +%d Points +%d EXP",
            g_sMissionDesc[descIdx], points, exp);

        ClientCommand(client, "play buttons/bell1.wav");

        CheckCardComplete(client);
    }
}

void CheckCardComplete(int client)
{
    int c = g_iPlayerCardIndex[client];
    bool allDone = true;

    for (int m = 0; m < g_iCardMissionCount[c]; m++)
    {
        if (!g_bPlayerMissionDone[client][m])
        {
            allDone = false;
            break;
        }
    }

    if (allDone && !g_bPlayerCardCompleted[client])
    {
        g_bPlayerCardCompleted[client] = true;

        int bonusPts = g_iCardBonusPoints[c];
        int bonusExp = g_iCardBonusExp[c];
        g_iPlayerPoints[client] += bonusPts;
        g_iPlayerEXP[client] += bonusExp;

        PrintToChatAll(" ");
        PrintToChatAll(" \x04[MISSION COMPLETE]\x03 %N\x01 completed: \x04%s\x01 [%s]",
            client, g_sCardName[c], g_sCardTier[c]);
        PrintToChatAll(" \x04[BONUS]\x01 +%d Points +%d EXP", bonusPts, bonusExp);
        PrintToChatAll(" ");

        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
                ClientCommand(i, "play buttons/button17.wav");
        }

        CreateTimer(5.0, Timer_AutoAssign, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

// ============================================================
// HUD - KeyHintText
// ============================================================

void ShowMissionHUD(int client)
{
    if (!g_cvHudEnabled.BoolValue || !IsClientInGame(client) || IsFakeClient(client))
        return;

    if (!g_bPlayerHasCard[client])
    {
        ShowEmptyHUD(client);
        return;
    }

    int c = g_iPlayerCardIndex[client];
    char hudText[512];
    char line[128];

    // Header
    Format(hudText, sizeof(hudText),
        "==============================\n");
    Format(hudText, sizeof(hudText),
        "%s  MISSION CARD [%s]\n", hudText, g_sCardTier[c]);
    Format(hudText, sizeof(hudText),
        "%s  %s\n", hudText, g_sCardName[c]);
    Format(hudText, sizeof(hudText),
        "%s==============================\n", hudText);

    // Missions
    for (int m = 0; m < g_iCardMissionCount[c]; m++)
    {
        int current = g_iPlayerMissionCurrent[client][m];
        int target = g_iMissionTarget[c][m];
        bool done = g_bPlayerMissionDone[client][m];

        if (current > target) current = target;

        int descIdx = GetDescIndex(c, m);

        char status[8];
        if (done)
            strcopy(status, sizeof(status), "[V]");
        else
            strcopy(status, sizeof(status), "[  ]");

        // Progress bar
        char progBar[32];
        BuildProgressBar(current, target, progBar, sizeof(progBar));

        Format(line, sizeof(line), "  %s %s\n       %s %d/%d\n",
            status,
            g_sMissionDesc[descIdx],
            progBar,
            current,
            target);

        StrCat(hudText, sizeof(hudText), line);
    }

    // Footer
    int completedCount = 0;
    for (int m = 0; m < g_iCardMissionCount[c]; m++)
    {
        if (g_bPlayerMissionDone[client][m])
            completedCount++;
    }

    Format(hudText, sizeof(hudText),
        "%s==============================\n", hudText);

    if (g_bPlayerCardCompleted[client])
    {
        Format(hudText, sizeof(hudText),
            "%s  ** CARD COMPLETE! **\n", hudText);
        Format(hudText, sizeof(hudText),
            "%s  Bonus: +%dP +%dEXP\n", hudText,
            g_iCardBonusPoints[c], g_iCardBonusExp[c]);
    }
    else
    {
        Format(hudText, sizeof(hudText),
            "%s  Progress: %d/%d missions\n", hudText,
            completedCount, g_iCardMissionCount[c]);
        Format(hudText, sizeof(hudText),
            "%s  !mission | !reroll\n", hudText);
    }

    // Send KeyHintText
    Handle msg = StartMessageOne("KeyHintText", client);
    if (msg != null)
    {
        BfWriteByte(msg, 1);
        BfWriteString(msg, hudText);
        EndMessage();
    }
}

void ShowEmptyHUD(int client)
{
    char hudText[256];

    Format(hudText, sizeof(hudText),
        "==============================\n");
    Format(hudText, sizeof(hudText),
        "%s  MISSION CARD\n", hudText);
    Format(hudText, sizeof(hudText),
        "%s==============================\n", hudText);
    Format(hudText, sizeof(hudText),
        "%s  No active mission\n", hudText);
    Format(hudText, sizeof(hudText),
        "%s  Type !mission to get\n", hudText);
    Format(hudText, sizeof(hudText),
        "%s  a mission card!\n", hudText);
    Format(hudText, sizeof(hudText),
        "%s==============================\n", hudText);

    Handle msg = StartMessageOne("KeyHintText", client);
    if (msg != null)
    {
        BfWriteByte(msg, 1);
        BfWriteString(msg, hudText);
        EndMessage();
    }
}

// ============================================================
// PROGRESS BAR
// ============================================================

void BuildProgressBar(int current, int target, char[] buffer, int maxlen)
{
    if (target <= 0) target = 1;
    if (current > target) current = target;

    int barLen = 10;
    int filled = RoundToFloor(float(current) / float(target) * float(barLen));

    buffer[0] = '\0';
    StrCat(buffer, maxlen, "[");

    for (int i = 0; i < barLen; i++)
    {
        if (i < filled)
            StrCat(buffer, maxlen, "|");
        else
            StrCat(buffer, maxlen, ".");
    }

    StrCat(buffer, maxlen, "]");
}

// ============================================================
// HUD REFRESH TIMER
// ============================================================

public Action Timer_RefreshHUD(Handle timer)
{
    if (!g_cvEnabled.BoolValue || !g_cvHudEnabled.BoolValue)
        return Plugin_Continue;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
            continue;

        ShowMissionHUD(i);
    }

    return Plugin_Continue;
}

// ============================================================
// AUTO ASSIGN
// ============================================================

public Action Timer_AutoAssign(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client))
        return Plugin_Stop;

    if (g_bPlayerHasCard[client] && !g_bPlayerCardCompleted[client])
        return Plugin_Stop;

    AssignRandomCard(client);
    return Plugin_Stop;
}

void AssignRandomCard(int client)
{
    if (g_iCardCount == 0)
    {
        PrintToChat(client, " \x04[MISSION]\x01 No mission cards available.");
        return;
    }

    int cardIdx = GetRandomInt(0, g_iCardCount - 1);

    ResetPlayerProgress(client);

    g_iPlayerCardIndex[client] = cardIdx;
    g_bPlayerHasCard[client] = true;

    PrintToChat(client, " ");
    PrintToChat(client, " \x04[MISSION]\x01 New card: \x03%s\x01 [%s]",
        g_sCardName[cardIdx], g_sCardTier[cardIdx]);

    for (int m = 0; m < g_iCardMissionCount[cardIdx]; m++)
    {
        int descIdx = GetDescIndex(cardIdx, m);
        PrintToChat(client, " \x04[%d]\x01 %s \x03(+%dP +%dEXP)",
            m + 1,
            g_sMissionDesc[descIdx],
            g_iMissionRewardPoints[cardIdx][m],
            g_iMissionRewardExp[cardIdx][m]);
    }

    PrintToChat(client, " ");

    ClientCommand(client, "play items/gunpickup2.wav");
    ShowMissionHUD(client);
}

// ============================================================
// RESET
// ============================================================

void ResetPlayerProgress(int client)
{
    g_bPlayerHasCard[client] = false;
    g_bPlayerCardCompleted[client] = false;
    g_iPlayerCardIndex[client] = 0;
    g_iPlayerKillStreak[client] = 0;
    g_bPlayerSurvivedRound[client] = true;

    for (int m = 0; m < MAX_MISSIONS_PER_CARD; m++)
    {
        g_iPlayerMissionCurrent[client][m] = 0;
        g_bPlayerMissionDone[client][m] = false;
    }
}

// ============================================================
// COMMANDS
// ============================================================

public Action Cmd_Mission(int client, int args)
{
    if (client <= 0) return Plugin_Handled;

    if (!g_bPlayerHasCard[client])
        AssignRandomCard(client);
    else
        ShowMissionChat(client);

    ShowMissionHUD(client);
    return Plugin_Handled;
}

public Action Cmd_Reroll(int client, int args)
{
    if (client <= 0) return Plugin_Handled;

    if (g_iCardCount <= 1)
    {
        PrintToChat(client, " \x04[MISSION]\x01 Not enough cards to reroll.");
        return Plugin_Handled;
    }

    int maxReroll = g_cvMaxReroll.IntValue;

    if (g_iRerollCount[client] >= maxReroll)
    {
        PrintToChat(client, " \x04[MISSION]\x01 No rerolls left. (Max: %d)", maxReroll);
        return Plugin_Handled;
    }

    if (g_bPlayerCardCompleted[client])
    {
        PrintToChat(client, " \x04[MISSION]\x01 Card already completed!");
        return Plugin_Handled;
    }

    g_iRerollCount[client]++;
    int remaining = maxReroll - g_iRerollCount[client];

    int oldCard = g_iPlayerCardIndex[client];
    int newCard = oldCard;
    int attempts = 0;

    while (newCard == oldCard && attempts < 20)
    {
        newCard = GetRandomInt(0, g_iCardCount - 1);
        attempts++;
    }

    ResetPlayerProgress(client);
    g_iPlayerCardIndex[client] = newCard;
    g_bPlayerHasCard[client] = true;

    PrintToChat(client, " \x04[MISSION]\x01 Rerolled! New: \x03%s\x01 [%s] (Left: %d)",
        g_sCardName[newCard], g_sCardTier[newCard], remaining);

    ClientCommand(client, "play items/gunpickup2.wav");
    ShowMissionHUD(client);

    return Plugin_Handled;
}

public Action Cmd_MissionMenu(int client, int args)
{
    if (client <= 0) return Plugin_Handled;
    ShowMissionMenu(client);
    return Plugin_Handled;
}

public Action Cmd_Reload(int client, int args)
{
    LoadMissionConfig();
    ReplyToCommand(client, "[PBMission] Config reloaded. %d cards loaded.", g_iCardCount);
    return Plugin_Handled;
}

public Action Cmd_GiveCard(int client, int args)
{
    if (args < 2)
    {
        ReplyToCommand(client, "Usage: sm_mission_give <#userid|name> <card_index>");
        return Plugin_Handled;
    }

    char arg1[64], arg2[16];
    GetCmdArg(1, arg1, sizeof(arg1));
    GetCmdArg(2, arg2, sizeof(arg2));

    int target = FindTarget(client, arg1, true, false);
    if (target == -1) return Plugin_Handled;

    int cardIdx = StringToInt(arg2);
    if (cardIdx < 0 || cardIdx >= g_iCardCount)
    {
        ReplyToCommand(client, "Invalid card index. (0-%d)", g_iCardCount - 1);
        return Plugin_Handled;
    }

    ResetPlayerProgress(target);
    g_iPlayerCardIndex[target] = cardIdx;
    g_bPlayerHasCard[target] = true;

    PrintToChat(target, " \x04[MISSION]\x01 Admin gave you: \x03%s", g_sCardName[cardIdx]);
    ReplyToCommand(client, "Gave '%s' to %N", g_sCardName[cardIdx], target);

    ShowMissionHUD(target);
    return Plugin_Handled;
}

public Action Cmd_ResetCard(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "Usage: sm_mission_reset <#userid|name>");
        return Plugin_Handled;
    }

    char arg1[64];
    GetCmdArg(1, arg1, sizeof(arg1));

    int target = FindTarget(client, arg1, true, false);
    if (target == -1) return Plugin_Handled;

    ResetPlayerProgress(target);
    PrintToChat(target, " \x04[MISSION]\x01 Your card has been reset.");
    ReplyToCommand(client, "Reset card for %N", target);

    ShowMissionHUD(target);
    return Plugin_Handled;
}

// ============================================================
// MENU
// ============================================================

void ShowMissionMenu(int client)
{
    Menu menu = new Menu(MissionMenuHandler);
    menu.SetTitle("=== Mission Card ===");

    menu.AddItem("view", "View Current Mission");
    menu.AddItem("reroll", "Reroll Card");
    menu.AddItem("stats", "My Stats");

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MissionMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[32];
            menu.GetItem(param2, info, sizeof(info));

            if (StrEqual(info, "view"))
            {
                ShowMissionChat(param1);
                ShowMissionHUD(param1);
            }
            else if (StrEqual(info, "reroll"))
            {
                Cmd_Reroll(param1, 0);
            }
            else if (StrEqual(info, "stats"))
            {
                ShowPlayerStats(param1);
            }

            ShowMissionMenu(param1);
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    return 0;
}

// ============================================================
// CHAT DISPLAY
// ============================================================

void ShowMissionChat(int client)
{
    if (!g_bPlayerHasCard[client])
    {
        PrintToChat(client, " \x04[MISSION]\x01 No active card. Type \x03!mission");
        return;
    }

    int c = g_iPlayerCardIndex[client];

    PrintToChat(client, " ");
    PrintToChat(client, " \x04==============================");
    PrintToChat(client, " \x04[MISSION CARD]\x01 %s \x03[%s]",
        g_sCardName[c], g_sCardTier[c]);
    PrintToChat(client, " \x04==============================");

    for (int m = 0; m < g_iCardMissionCount[c]; m++)
    {
        int current = g_iPlayerMissionCurrent[client][m];
        int target = g_iMissionTarget[c][m];
        bool done = g_bPlayerMissionDone[client][m];
        int descIdx = GetDescIndex(c, m);

        if (current > target) current = target;

        if (done)
        {
            PrintToChat(client, " \x04  [V] %s (%d/%d) +%dP +%dEXP",
                g_sMissionDesc[descIdx], current, target,
                g_iMissionRewardPoints[c][m], g_iMissionRewardExp[c][m]);
        }
        else
        {
            PrintToChat(client, " \x01  [  ] %s \x03(%d/%d)\x01 +%dP +%dEXP",
                g_sMissionDesc[descIdx], current, target,
                g_iMissionRewardPoints[c][m], g_iMissionRewardExp[c][m]);
        }
    }

    PrintToChat(client, " \x04==============================");

    if (g_bPlayerCardCompleted[client])
    {
        PrintToChat(client, " \x04  ** ALL COMPLETE! **");
    }
    else
    {
        PrintToChat(client, " \x01  Complete all for bonus: \x04+%dP +%dEXP",
            g_iCardBonusPoints[c], g_iCardBonusExp[c]);
    }

    PrintToChat(client, " ");
}

void ShowPlayerStats(int client)
{
    PrintToChat(client, " ");
    PrintToChat(client, " \x04[MY STATS]");
    PrintToChat(client, " \x01  Points: \x03%d", g_iPlayerPoints[client]);
    PrintToChat(client, " \x01  EXP: \x03%d", g_iPlayerEXP[client]);
    PrintToChat(client, " \x01  Rerolls Used: \x03%d/%d",
        g_iRerollCount[client], g_cvMaxReroll.IntValue);
    PrintToChat(client, " ");
}