/*
killEffectPB.sp

Description:
    A Copy of kill effect from the game named Point Blank, Kill & Round PB Counter, Bomb Timer, Overlays. Special Thanks to wTon. Connected to CSSDM from Baliopan.net. Optimization form previous version.

Versions:
    0.1
        *Initial Release
	1.0 
		*Headshot sound random
		*Separated resolution for 16:9 and 4:3
		*Killer Name (only for deathmatch)
		*combined with counterPB.smx
        *So Many Bug Fixed
        *improve code effectiveness
        *preparing match
*/

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <newoverlays>
#include <sdktools_sound>
#include <killassist>

#define MAX_FILE_LEN 256

#define PLUGIN_VERSION "0.1"

//overlay
#define announce_DK "overlays/ekillpb/announcement/2"  
#define announce_TK "overlays/ekillpb/announcement/3"  
#define announce_CK "overlays/ekillpb/announcement/4"  
#define announce_HS "overlays/ekillpb/announcement/hs1"
#define announce_CH "overlays/ekillpb/announcement/hs2"
#define announce_CStop "overlays/ekillpb/announcement/chain_stopper"
#define announce_CS "overlays/ekillpb/announcement/chain_slugger"   
#define announce_MK "overlays/ekillpb/announcement/mass_kill"   
#define announce_PS "overlays/ekillpb/announcement/piercing_shot" 

#define frag			"overlays/ekillpb/frag/frag"  
#define frag_gold 		"overlays/ekillpb/frag/frag_gold"  
#define frag_hs			"overlays/ekillpb/frag/frag_hs"  
#define frag_hs_gold 	"overlays/ekillpb/frag/frag_hs_gold"
#define frag_melee 		"overlays/ekillpb/frag/frag_melee"  
#define frag_melee_gold "overlays/ekillpb/frag/frag_melee_gold"
#define frag_assist "overlays/ekillpb/frag/frag_assist"

// #define eotech      "overlays/scope/eotech"

//sound
#define sound_FK "killeffect/kill1.wav"
#define sound_DK "killeffect/kill2.wav"
#define sound_TK "killeffect/kill3.wav"
#define sound_CK "killeffect/chain.wav"
#define sound_HS "killeffect/headshot.wav"
#define sound_CS "killeffect/chainSluger.wav"
#define sound_MK "killeffect/massKill.wav"
#define sound_CH "killeffect/ChainHeadshot.wav"
#define sound_CStop "killeffect/ChainStoper.wav"
#define sound_HP "killeffect/HelmetProtection.wav"
#define sound_PS "killeffect/PiercingShot.wav"
#define sound_HB "killeffect/heartbeat.wav"
#define sound_W "killeffect/whistle.wav"
#define sound_HSHit1 "player/f_headshot1.wav"
#define sound_HSHit2 "player/f_headshot2.wav"

new Handle:g_killCount[33];
new Handle:g_hsKillCount[33];
new Handle:g_bombKillCount[33];
new Handle:g_knifeKillCount[33];
new Handle:g_killSameCount[33];
new Handle:g_taskCountdown[33] = INVALID_HANDLE,Handle:g_taskSameKillClean[33] = INVALID_HANDLE;
new Handle:g_kvC4 = INVALID_HANDLE;
new Handle:g_CvarAnnounce = INVALID_HANDLE;
new Handle:g_CvarSoundDefault = INVALID_HANDLE;
new bool:g_lateLoaded;
new String:sWeaponName[64];


//var dari counterPB
#define Spec_Team 1
#define T_Team 2
#define CT_Team 3
#define MAX_FILE_LEN 256
#define blue_win "overlays/hud/bluewin"
#define red_win "overlays/hud/redwin"
#define draw "overlays/hud/draw"
#define respawnbar "overlays/hud/respawnbar"
#define sound_BW "announce/bluewin.wav"
#define sound_RW "announce/redwin.wav"

new Handle:g_CvarMPc4Timer, g_RoundLimit, g_dmProtectionNotif, g_dmStat;
new Handle:g_KillLimit, g_cdTimerPreMatch, g_cdMatch, g_cdTimerEndMatch, g_cdTimerShowScore, g_ratioCheck;
new Handle:hTimer = INVALID_HANDLE;
new Handle:g_bombCountdownRC[33] = INVALID_HANDLE;

new Float:g_explosionTime;
new g_bombcountdown, g_flProgressBarStartTime, g_iProgressBarDuration, g_countdown;
new Int:T_wins, CT_wins, g_classicCSMode, T_kills, CT_kills, cdPrepareMatch;
new bool:isPlanted, endMatch, showScore;

new String:g_planter[40];
new String:sNewWeaponName[256];
new String:sNewWeaponCoreName[256];
new String:ratioCheck[10];

bool g_bMatchStarted = false;
bool g_bCountdownStarted = false;
bool preparingMatch = false;

int g_roundStartedTime = -1;

public Plugin:myinfo = {
    name = "Overlay Pack PB",
    author = "WataAme",
    description = "A Copy of kill effect from the game named Point Blank, Kill & Round PB Counter, Bomb Timer, Overlays, Show Killer in DM mode. Connected to CSSDM from Baliopan.net. Optimization form previous version.",
    version = PLUGIN_VERSION,
    url = "https://www.youtube.com/channel/UCJhUfylSHmwlnGGsHK19g4w"
};

public OnPluginStart(){
    HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", SpawnEvent);
	HookEvent("player_hurt", OnPlayerHurt);
	
    //CSSDM respawn bar HUD
    HookEvent("player_death", Event_PlayerDeathPost, EventHookMode_PostNoCopy);
    //Bomb mission mode round counter 
    HookEvent("round_end", Event_RoundEnd);
    //reset kill and round counter
    HookEvent("round_start", Event_RoundStart);
    //hook for bomb timer
    HookEvent("bomb_planted", EventBombPlanted, EventHookMode_Pre);
	HookEvent("bomb_defused", EventBombDefused, EventHookMode_Post);    
    
	g_RoundLimit = CreateConVar("sm_round_limit", "9", "Limit of Round in bomb mission mode");
	g_KillLimit = CreateConVar("sm_kill_limit", "100", "Limit of Kill in deathmatch mode");
	g_dmProtectionNotif = CreateConVar("sm_dm_protectnotif", "1", "Progress Bar notif for CSSDM Protection. 1 = yes, 0 = no.");
    g_classicCSMode = CreateConVar("sm_classic_csmode","1","Not quitting game after match ended.  1 = not quitting after round ended, 0 = quit after round ended.");
    g_cdMatch = CreateConVar("sm_cdmatch","5","Countdown Prepare Match.");
    g_ratioCheck = CreateConVar("sm_aspect_ratio","16:9","Resolution ratio check");
    g_CvarMPc4Timer = FindConVar("mp_c4timer");

	g_flProgressBarStartTime = FindSendPropOffs("CCSPlayer", "m_flProgressBarStartTime");
	g_iProgressBarDuration = FindSendPropOffs("CCSPlayer", "m_iProgressBarDuration");

	if(g_flProgressBarStartTime == -1)
		PrintToChatAll("Couldnt find the m_flProgressBarStartTime offset!");
	if(g_iProgressBarDuration == -1)
		SetFailState("Couldnt find the m_iProgressBarDuration offset!");

    // g_hHudHp = CreateHudSynchronizer(); // bikin sinkronizer khusus HP bar
    // RegConsoleCmd("sm_hpbar", Command_HpBar);
    // // timer update
    // CreateTimer(0.3, Timer_UpdateHP, _, TIMER_REPEAT);

    ServerCommand("exec csspb/limiter.cfg");

}


public OnMapStart()
{
    cdPrepareMatch = GetConVarInt(g_cdMatch);
    g_bMatchStarted = false;
    g_bCountdownStarted = false;
    preparingMatch = true;
    endMatch = false;
    new String:rW[MAX_FILE_LEN]; 
	new String:bW[MAX_FILE_LEN]; 
    
	Format(rW, sizeof(rW), "sound/%s", sound_RW);
	Format(bW, sizeof(bW), "sound/%s", sound_BW);

	PrecacheDecalAnyDownload(respawnbar);
	PrecacheDecalAnyDownload(blue_win);
	PrecacheDecalAnyDownload(red_win);
	PrecacheDecalAnyDownload(draw);

    g_dmStat = GetConVarInt(FindConVar("cssdm_enabled"));
    if(g_dmStat == 1){
        ServerCommand("mp_ignore_round_win_conditions 1");
    }else{
        ServerCommand("mp_ignore_round_win_conditions 0");
    }    

	decl String:fK[MAX_FILE_LEN]; 
	decl String:dK[MAX_FILE_LEN]; 
	decl String:tK[MAX_FILE_LEN]; 
	decl String:cK[MAX_FILE_LEN]; 
	decl String:hS[MAX_FILE_LEN]; 
	decl String:cS[MAX_FILE_LEN];
	decl String:mK[MAX_FILE_LEN];
	decl String:cH[MAX_FILE_LEN];
	decl String:cStop[MAX_FILE_LEN];
	decl String:hP[MAX_FILE_LEN];
	decl String:pS[MAX_FILE_LEN];
	decl String:hSHit1[MAX_FILE_LEN];
	decl String:hSHit2[MAX_FILE_LEN];
	decl String:hB[MAX_FILE_LEN];
	decl String:w[MAX_FILE_LEN];

	Format(fK, sizeof(fK), "sound/%s", sound_FK);
	Format(dK, sizeof(dK), "sound/%s", sound_DK);
	Format(tK, sizeof(tK), "sound/%s", sound_TK);
	Format(cK, sizeof(cK), "sound/%s", sound_CK);
	Format(hS, sizeof(hS), "sound/%s", sound_HS);
	Format(cS, sizeof(cS), "sound/%s", sound_CS);
	Format(mK, sizeof(mK), "sound/%s", sound_MK);
	Format(cH, sizeof(cH), "sound/%s", sound_CH);
	Format(cStop, sizeof(cStop), "sound/%s", sound_CStop);
	Format(hP, sizeof(hP), "sound/%s", sound_HP);
	Format(pS, sizeof(pS), "sound/%s", sound_PS);
	Format(hSHit1, sizeof(hSHit1), "sound/%s", sound_HSHit1);
	Format(hSHit2, sizeof(hSHit2), "sound/%s", sound_HSHit2);
	Format(hB, sizeof(hB), "sound/%s", sound_HB);
	Format(w, sizeof(w), "sound/%s", sound_W);

	if(FileExists(fK) && 
    FileExists(dK) && 
    FileExists(tK) && 
    FileExists(cK) && 
    FileExists(hS) && 
    FileExists(cS) && 
    FileExists(mK) && 
    FileExists(cH) && 
    FileExists(cStop) && 
    FileExists(hP) && 
    FileExists(pS) &&
    FileExists(hSHit1) && 
    FileExists(hSHit2) && 
    FileExists(rW) && 
    FileExists(bW)){
		AddFileToDownloadsTable(fK);
		AddFileToDownloadsTable(dK);
		AddFileToDownloadsTable(tK);
		AddFileToDownloadsTable(cK);
		AddFileToDownloadsTable(hS);
		AddFileToDownloadsTable(cS);
		AddFileToDownloadsTable(mK);
		AddFileToDownloadsTable(cH);
		AddFileToDownloadsTable(cStop);
		AddFileToDownloadsTable(hP);
		AddFileToDownloadsTable(pS);
		AddFileToDownloadsTable(hSHit1);
		AddFileToDownloadsTable(hSHit2);
		AddFileToDownloadsTable(hB);
		AddFileToDownloadsTable(w);
		AddFileToDownloadsTable(rW);
		AddFileToDownloadsTable(bW);

		PrecacheSound(sound_FK);
		PrecacheSound(sound_DK);
		PrecacheSound(sound_TK);
		PrecacheSound(sound_CK);
		PrecacheSound(sound_HS);
		PrecacheSound(sound_CS);
		PrecacheSound(sound_MK);
		PrecacheSound(sound_CH);
		PrecacheSound(sound_CStop);
		PrecacheSound(sound_HP);
		PrecacheSound(sound_PS);
		PrecacheSound(sound_HSHit1);
		PrecacheSound(sound_HSHit2);
		PrecacheSound(sound_HB);
		PrecacheSound(sound_W);
        PrecacheSound(sound_RW);
        PrecacheSound(sound_BW);
	}
	else {
		PrintToChatAll("Not all sound files exists.");
	}

	PrecacheDecalAnyDownload(announce_DK);
	PrecacheDecalAnyDownload(announce_TK);
	PrecacheDecalAnyDownload(announce_CK);
	PrecacheDecalAnyDownload(announce_HS);
	PrecacheDecalAnyDownload(announce_CH);
	PrecacheDecalAnyDownload(announce_CStop);
	PrecacheDecalAnyDownload(announce_CS);
	PrecacheDecalAnyDownload(announce_MK);
	PrecacheDecalAnyDownload(announce_PS);

	PrecacheDecalAnyDownload(frag);
	PrecacheDecalAnyDownload(frag_gold);
	PrecacheDecalAnyDownload(frag_hs);
	PrecacheDecalAnyDownload(frag_hs_gold);
	PrecacheDecalAnyDownload(frag_melee);
	PrecacheDecalAnyDownload(frag_melee_gold);
	PrecacheDecalAnyDownload(frag_assist);
	// PrecacheDecalAnyDownload(eotech);
}

public void OnMapEnd()
{
    // Cleanup
    if (g_cdTimerPreMatch != INVALID_HANDLE)
    {
        KillTimer(g_cdTimerPreMatch);
        g_cdTimerPreMatch = INVALID_HANDLE;
    }
}

public Action OnPlayerRunCmd(client, &buttons, &impulse, float vel[3], float angles[3], &weapon)
{
    new roundLimit=GetConVarInt(g_RoundLimit);
    new killLimit=GetConVarInt(g_KillLimit);
    g_dmStat = GetConVarInt(FindConVar("cssdm_enabled"));
    GetConVarString(g_ratioCheck,ratioCheck,sizeof(ratioCheck));
    GetClientWeapon(client, sWeaponName, sizeof(sWeaponName));

    char tKills[8], ctKills[8], buffer[32];

   //COUNTER SHOW & ROUND END MESSAGE SECTION
    if(g_dmStat == 0){
        ServerCommand("mp_ignore_round_win_conditions 0");

        Format(buffer, sizeof(buffer), "%-23d%d", T_wins, CT_wins);

        if(StrEqual(ratioCheck,"4:3")){
            SetHudTextParams(0.403, 0.027, 600.0, 255, 255, 255, 0);
        } else if(StrEqual(ratioCheck,"16:9")){
            SetHudTextParams(0.425, 0.027, 600.0, 255, 255, 255, 0);
        }

        ShowHudText(client, -1, buffer);

        // if(StrEqual(ratioCheck,"4:3")){
        //     SetHudTextParams(0.402, 0.027, 600.0, 255, 255, 255, 0);
        // }else if(StrEqual(ratioCheck,"16:9")){
        //     SetHudTextParams(0.425, 0.027, 600.0, 255, 255, 255, 0);
        // }

        // ShowHudText(client, -1, "%d",T_wins);

        // if(StrEqual(ratioCheck,"4:3")){
        //     SetHudTextParams(0.592, 0.027, 600.0, 255, 255, 255, 0);
        // }else if(StrEqual(ratioCheck,"16:9")){
        //      SetHudTextParams(0.567, 0.027, 600.0, 255, 255, 255, 0);
        // }       

        // ShowHudText(client, -1, "%d",CT_wins);

        if(StrEqual(ratioCheck,"4:3")){
            SetHudTextParams(0.485, 0.027, 600.0, 255, 255, 0, 0);
        }else if(StrEqual(ratioCheck,"16:9")){
            SetHudTextParams(0.487, 0.027, 600.0, 255, 255, 0, 0);
        } 

        ShowHudText(client, -1, "%d R",roundLimit);

        if(CT_wins == roundLimit || T_wins == roundLimit){
            if(buttons & IN_ATTACK){
                SetEntityFlags(client, (buttons |= FL_FROZEN));
            }
            else if(buttons & IN_FORWARD){
                SetEntityFlags(client, (buttons |= FL_FROZEN));
            }
            else if(buttons & IN_BACK){
                SetEntityFlags(client, (buttons |= FL_FROZEN));
            }
            else if(buttons & IN_MOVELEFT){
                SetEntityFlags(client, (buttons |= FL_FROZEN));
            }
            else if(buttons & IN_MOVERIGHT){
                SetEntityFlags(client, (buttons |= FL_FROZEN));
            }
        
            endMatch = true;
            showScore = true;
            if(showScore) g_cdTimerShowScore = CreateTimer(3.0, ShowScore);
            g_bombCountdownRC[client] = CreateTimer(3 , reset_win, client);
            
        }
        
        if(isPlanted == true){
            if(g_bombcountdown <= 9){
                SetHudTextParams(0.495, 0.08, 600.0, 255, 0, 0, 0);
            }else{
                SetHudTextParams(0.49, 0.08, 600.0, 255, 255, 255, 0);             
            }
            ShowHudText(client, -1, "%d",g_bombcountdown);   
        }

    }else{        
        ServerCommand("mp_ignore_round_win_conditions 1");

        // Format dengan leading zero 3 digit
        Format(tKills, sizeof(tKills), "%03d", T_kills);
        Format(ctKills, sizeof(ctKills), "%03d", CT_kills);

        // Gabung
        Format(buffer, sizeof(buffer), "%-22s%s", tKills, ctKills);
        // if(StrEqual(ratioCheck,"4:3")){
        //     SetHudTextParams(0.387, 0.027, 600.0, 255, 255, 255, 0);
        // }else if(StrEqual(ratioCheck,"16:9")){
        //     SetHudTextParams(0.415, 0.027, 600.0, 255, 255, 255, 0);
        // }


        // if(T_kills < 10)
        // {
        //     ShowHudText(client, -1, "00%d",T_kills);
        // }
        // else if(T_kills < 100){
        //     ShowHudText(client, -1, "0%d",T_kills);
        // }
        // else{
        //     ShowHudText(client, -1, "%d",T_kills);
        // }

        // if(StrEqual(ratioCheck,"4:3")){
        //     SetHudTextParams(0.577, 0.027, 600.0, 255, 255, 255, 0);
        // }else if(StrEqual(ratioCheck,"16:9")){
        //     SetHudTextParams(0.557, 0.027, 600.0, 255, 255, 255, 0);
        // }

        
        // if(CT_kills < 10)
        // {
        //     ShowHudText(client, -1, "00%d",CT_kills);
        // }
        // else if(CT_kills < 100){
        //     ShowHudText(client, -1, "0%d",CT_kills);
        // }
        // else {
        //     ShowHudText(client, -1, "%d",CT_kills);
        // }
        if(StrEqual(ratioCheck,"4:3")){
            SetHudTextParams(0.387, 0.027, 600.0, 255, 255, 255, 0);
        } else if(StrEqual(ratioCheck,"16:9")){
            SetHudTextParams(0.415, 0.027, 600.0, 255, 255, 255, 0);
        }

        ShowHudText(client, -1, buffer);

        if(StrEqual(ratioCheck,"4:3")){
            SetHudTextParams(0.480, 0.027, 600.0, 255, 255, 0, 0);
        }else if(StrEqual(ratioCheck,"16:9")){
            SetHudTextParams(0.485, 0.027, 600.0, 255, 255, 0, 0); //x = 0.508
        }

        if(killLimit < 10)
        {
            ShowHudText(client, -1, "00%d",killLimit);
        }
        else if(killLimit < 100){
            ShowHudText(client, -1, "0%d",killLimit);
        }
        else{
            ShowHudText(client, -1, "%d",killLimit);
        }

        new roundTime = GetTotalRoundTime() - GetCurrentRoundTime();
        //MAX DM ROUND TIME 9 MINUTES
        if(CT_kills == killLimit || T_kills == killLimit || roundTime == 0 ){
            showScore = true;
            if(showScore) g_cdTimerShowScore = CreateTimer(3.0, ShowScore);

            if(roundTime == 0 && CT_kills == T_kills){
                ShowOverlay(client, draw, 3.0);  //there is bug 1:10 chance, but its okay i think lol
            }

            if(roundTime == 0 && T_kills > CT_kills){
                EmitSoundToClient(client,sound_RW);
                ShowOverlay(client, red_win, 3.0);
            }else if(roundTime == 0 && CT_kills > T_kills){
                EmitSoundToClient(client,sound_BW);
                ShowOverlay(client, blue_win, 3.0);       
            }        


             CreateTimer(1.0 , KillClear);

            if(buttons & IN_ATTACK){
                SetEntityFlags(client, (buttons |= FL_FROZEN));
            }
            else if(buttons & IN_FORWARD){
                SetEntityFlags(client, (buttons |= FL_FROZEN));
            }
            else if(buttons & IN_BACK){
                SetEntityFlags(client, (buttons |= FL_FROZEN));
            }
            else if(buttons & IN_MOVELEFT){
                SetEntityFlags(client, (buttons |= FL_FROZEN));
            }
            else if(buttons & IN_MOVERIGHT){
                SetEntityFlags(client, (buttons |= FL_FROZEN));
            }


        }   

    }
//COUNTER SHOW & ROUND END MESSAGE SECTION ENDED

}

public void OnPlayerHurt(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));    
    
	EmitSoundToClient(attacker,sound_FK);
} 

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	effect_Killer(event);	
}

public Action:SpawnEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
	effect_Killer(event);

    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    new ProtectionNotif=GetConVarInt(g_dmProtectionNotif);
    if(g_dmStat == 1 && ProtectionNotif == 1){
        ProgressBarShowProtection(client);
    }


    // ===== GUARD CLAUSES =====
    
    // Match sudah mulai? Skip
    if (g_bMatchStarted)
        return;
    
    // Countdown sudah jalan? Skip
    if (g_bCountdownStarted)
        return;
    
    // Validasi client
    if (client <= 0)
        return;
        
    if (!IsClientInGame(client))
        return;
    
    // Harus di team CT atau T
    int team = GetClientTeam(client);
    if (team < 2)
        return;
    
    // ===== MULAI PREPARING =====
    
    g_bCountdownStarted = true;
    preparingMatch = true;
    cdPrepareMatch = GetConVarInt(g_cdMatch);
    g_roundStartedTime = GetTime();
    
    PrintToChatAll("[Match] Player ready. Preparing match...");
    
    // Start countdown
    if (g_cdTimerPreMatch != INVALID_HANDLE)
    {
        KillTimer(g_cdTimerPreMatch);
    }
    g_cdTimerPreMatch = CreateTimer(1.0, Timer_CountDown);


} 

public Action:effect_Killer(event){
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	new bool:headshot = GetEventBool(event, "headshot");
	new headshots = GetEventInt(event, "headshot");
	new String:weapon[32];
	char name[32], buffer[128];

	GetEventString(event, "weapon",weapon, sizeof(weapon));
	
	g_killCount[victim] = 0;
	g_hsKillCount[victim] = 0;
	g_bombKillCount[victim] = 0;
	g_knifeKillCount[victim] = 0;

	if(attacker <1) return;
	
	g_killCount[attacker]++;
	g_killSameCount[attacker]++;
	if(headshots == 1){
		g_hsKillCount[attacker]++;
	}
	else if(StrEqual(weapon,"knife")){
		g_knifeKillCount[attacker]++;
	}
	else if(StrEqual(weapon,"hegrenade")){
		g_bombKillCount[attacker]++;		
	}

	if(g_taskCountdown[attacker] !=INVALID_HANDLE)
	{
		KillTimer(g_taskCountdown[attacker]);
		g_taskCountdown[attacker] =INVALID_HANDLE;
	}
	g_taskCountdown[attacker] = CreateTimer(0.0,task_Countdown,attacker,1);

	if(g_killCount[attacker] == 1)
	{
		if(StrEqual(weapon,"hegrenade")){
			EmitSoundToClient(attacker,sound_FK);
			ShowOverlay(attacker, frag, 3.0);
		}
		else if(StrEqual(weapon,"knife")){
			EmitSoundToClient(attacker,sound_FK);
			ShowOverlay(attacker, frag_melee, 3.0);	
		}
		else if(headshots == 1){
			switch(GetRandomInt(0,1)){
				case 0: EmitSoundToClient(attacker,sound_HSHit1);
            	case 1: EmitSoundToClient(attacker,sound_HSHit2);
			}
			EmitSoundToClient(attacker,sound_HS);
			ShowOverlay(attacker, announce_HS, 3.0);
		}
		else{
			EmitSoundToClient(attacker,sound_FK);
			ShowOverlay(attacker, frag, 3.0);
		}
	}
	else if(g_killSameCount[attacker] == 2){
		if(StrEqual(weapon,"hegrenade")){
			StopSound(attacker, SNDCHAN_AUTO,sound_HS);
			StopSound(attacker, SNDCHAN_AUTO,sound_CH);
			StopSound(attacker, SNDCHAN_AUTO,sound_CS);
			StopSound(attacker, SNDCHAN_AUTO,sound_DK);
			StopSound(attacker, SNDCHAN_AUTO,sound_TK);
			StopSound(attacker, SNDCHAN_AUTO,sound_CK);
			EmitSoundToClient(attacker,sound_MK);
			ShowOverlay(attacker, announce_MK, 3.0);
		}
		else {
			StopSound(attacker, SNDCHAN_AUTO,sound_HS);
			StopSound(attacker, SNDCHAN_AUTO,sound_CH);
			StopSound(attacker, SNDCHAN_AUTO,sound_CS);
			StopSound(attacker, SNDCHAN_AUTO,sound_DK);
			StopSound(attacker, SNDCHAN_AUTO,sound_TK);
			StopSound(attacker, SNDCHAN_AUTO,sound_CK);
			EmitSoundToClient(attacker,sound_PS);
			ShowOverlay(attacker, announce_PS, 3.0);
		}
	}
	else if(headshots == 1){
		if(g_killCount[attacker] > 1 && g_hsKillCount[attacker] == 1 ){
			switch(GetRandomInt(0,1)){
				case 0: EmitSoundToClient(attacker,sound_HSHit1);
            	case 1: EmitSoundToClient(attacker,sound_HSHit2);
			}
			EmitSoundToClient(attacker,sound_HS);
			ShowOverlay(attacker, announce_HS, 3.0);
		}
		else {
			switch(GetRandomInt(0,1)){
				case 0: EmitSoundToClient(attacker,sound_HSHit1);
            	case 1: EmitSoundToClient(attacker,sound_HSHit2);
			}
			EmitSoundToClient(attacker,sound_CH);
			ShowOverlay(attacker, announce_CH, 3.0);
		}
	}
	else if(StrEqual(weapon,"knife") ) {
		if(g_knifeKillCount[attacker] == 1){
			EmitSoundToClient(attacker,sound_FK);
			ShowOverlay(attacker, frag_melee, 3.0);
		} 
		else {
			EmitSoundToClient(attacker,sound_CS);
			ShowOverlay(attacker, announce_CS, 3.0);
		}
	}
	else if(g_killCount[attacker] == 2)
	{
			EmitSoundToClient(attacker,sound_DK);
			ShowOverlay(attacker, announce_DK, 3.0);
	}
	else if(g_killCount[attacker] == 3)
	{
			EmitSoundToClient(attacker,sound_TK);
			ShowOverlay(attacker, announce_TK, 3.0);
	}
	else if(g_killCount[attacker] > 3)
	{
			EmitSoundToClient(attacker,sound_CK);
			ShowOverlay(attacker, announce_CK, 3.0);
	}

	if(g_taskSameKillClean[attacker] !=INVALID_HANDLE)
	{
		KillTimer(g_taskSameKillClean[attacker]);
		g_taskSameKillClean[attacker] =INVALID_HANDLE;
	}
	g_taskSameKillClean[attacker] = CreateTimer(0.0,task_SameKillClean,attacker);
}

public OnAssistedKill( const any:assisters[], const nbAssisters, const killerId, const victimId )
{
	for( new i; i < nbAssisters; ++i){
		EmitSoundToClient(assisters [ i ],sound_HB);
		EmitSoundToClient(assisters [ i ],sound_W);
		ShowOverlay(assisters [ i ], frag_assist, 3.0);
	}
}

public Action:task_Countdown(Handle:Timer, any:client)
{
	g_killSameCount[client]--;
	if(!IsPlayerAlive(client) || g_killSameCount[client]==0 || g_killSameCount[client] < 0)
	{
		KillTimer(Timer);
		g_taskCountdown[client] = INVALID_HANDLE;
	}
}

public Action:task_SameKillClean(Handle:Timer, any:client)
{
	KillTimer(Timer);
	g_taskSameKillClean[client] = INVALID_HANDLE;
}

public int GetTotalRoundTime() {
  return GameRules_GetProp("m_iRoundTime");
}

public int GetCurrentRoundTime() {
  Handle h_freezeTime = FindConVar("mp_freezetime"); // Freezetime Handle
  int freezeTime = GetConVarInt(h_freezeTime); // Freezetime in seconds (5 by default)
  return (GetTime() - g_roundStartedTime) - freezeTime;
}

public Event_PlayerDeathPost(Handle:event, const String:name[], bool:dontBroadcast){
    new victim = GetClientOfUserId(GetEventInt(event, "userid"));
    new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
    new killLimit = GetConVarInt(g_KillLimit);    
    new roundTime = GetTotalRoundTime() - GetCurrentRoundTime();
    
    // decl String:nicknameVictim[64];
    // decl String:nicknameAttacker[64];

    // GetClientName(victim , nicknameVictim, sizeof(nicknameVictim));
    // GetClientName(attacker, nicknameAttacker, sizeof(nicknameAttacker));

    // PrintToConsole(victim, "%s membunuh %s",nicknameAttacker, nicknameVictim);



    for(int i = 1; i <= MaxClients; i++)
    {


        if(IsClientInGame(i) && !IsFakeClient(i))
        {	

            if(g_dmStat == 1){
                if(GetClientTeam(victim) == T_Team){
                    CT_kills++;
                }else if(GetClientTeam(victim) == CT_Team){
                    T_kills++;
                }

                ProgressBarShowDead(victim);
                ShowOverlay(victim, respawnbar, 4.0);

                if(CT_kills == killLimit || T_kills == killLimit || roundTime == 0){
                    endMatch = true;
                    if(T_kills == killLimit){
                        EmitSoundToClient(i,sound_RW);
                        ShowOverlay(i, red_win, 3.0);
                    }else if(CT_kills == killLimit){
                        EmitSoundToClient(i,sound_BW);
                        ShowOverlay(i, blue_win, 3.0);
                    }else if(T_kills > CT_kills){
                        EmitSoundToClient(i,sound_RW);
                        ShowOverlay(i, red_win, 3.0);
                    }else if(CT_kills > T_kills){
                        EmitSoundToClient(i,sound_BW);
                        ShowOverlay(i, blue_win, 3.0);       
                    }        
                    
                }

            }   

        }
    }


}


public Action:ProgressBarShowProtection(any:client){
    SetEntDataFloat(client, g_flProgressBarStartTime, GetGameTime(), true);
    SetEntData(client, g_iProgressBarDuration, 4, true);

    CreateTimer(4.0, ProgressBarClear, client);
}

public Action:ProgressBarShowDead(any:client){
    SetEntDataFloat(client, g_flProgressBarStartTime, GetGameTime(), true);
    SetEntData(client, g_iProgressBarDuration, 4, true);

    CreateTimer(4.0, ProgressBarClear, client);
}

public Action:ProgressBarClear(Handle:Timer, any:client){
    SetEntData(client, g_iProgressBarDuration, 0, true);
}

public Action:EventBombPlanted(Handle:event, const String:name[], bool:dontBroadcast)
{
    isPlanted = true;
	g_explosionTime = GetEngineTime() + GetConVarFloat(g_CvarMPc4Timer);
	
	GetClientName(GetClientOfUserId(GetEventInt(event, "userid")), g_planter, sizeof(g_planter));
	
	g_bombcountdown = GetConVarInt(g_CvarMPc4Timer) - 1;

	hTimer = CreateTimer((g_explosionTime - float(g_bombcountdown)) - GetEngineTime(), BombTimerCountdown);
	
	return Plugin_Continue;
}

public EventBombDefused(Handle:event, const String:name[], bool:dontBroadcast)
{
	isPlanted = false;
}

public Action:BombTimerCountdown(Handle:timer, any:data)
{
	if(--g_bombcountdown)
	{
		hTimer = CreateTimer((g_explosionTime - float(g_bombcountdown)) - GetEngineTime(), BombTimerCountdown);
	}

    if(g_bombcountdown == 0){
        isPlanted = false;
    }
}


public Action:Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{  
    // g_dmStat = GetConVarInt(FindConVar("cssdm_enabled"));
    isPlanted = false;
    new reasonId = GetEventInt(event, "reason");
    new roundLimit=GetConVarInt(g_RoundLimit);

    if(reasonId == 1 || reasonId == 4 || reasonId == 5 || reasonId == 6 || reasonId == 7 || reasonId == 10 || reasonId == 11 || reasonId == 13 || reasonId == 17 || reasonId == 19){
        CT_wins++;
    }else if(reasonId == 0 || reasonId == 2 || reasonId == 3 || reasonId == 8 || reasonId == 12 || reasonId == 14 || reasonId == 16 || reasonId == 18){
        T_wins++;
    }

    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && !IsFakeClient(i))
        {	
            
            if(T_wins == roundLimit){
                EmitSoundToClient(i,sound_RW);
                ShowOverlay(i, red_win, 3.0);
            }else if(CT_wins == roundLimit){
                EmitSoundToClient(i,sound_BW);
                ShowOverlay(i, blue_win, 3.0);
            }


        }
    }
   

}

public Action:reset_win(any:client){
    T_wins = 0;
    CT_wins = 0;
}

public Action Timer_CountDown(Handle timer) 
{
    if(cdPrepareMatch > 1) 
    {
        PrintCenterTextAll("Preparing match. Restarting in: %d.", cdPrepareMatch);
        
        // Bunuh semua player setiap countdown
        // Ini memaksa respawn sehingga weapon model reload
        ForceKillAllPlayers();
        
        g_cdTimerPreMatch = CreateTimer(1.0, Timer_CountDown);        
        --cdPrepareMatch;
    }
    else 
    {
        // Terakhir: bunuh sekali lagi sebelum restart
        ForceKillAllPlayers();
        
        preparingMatch = false;
        g_cdTimerPreMatch = INVALID_HANDLE;
        ServerCommand("mp_restartgame 1");    
    }
}

void ForceKillAllPlayers()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;
            
        if (!IsPlayerAlive(i))
            continue;
            
        // Metode 1: ForcePlayerSuicide (paling clean)
        ForcePlayerSuicide(i);
    }
}

public Action ShowScore(Handle timer) 
{
 
    if(showScore) 
    {
        ServerCommand("+showscores");
        g_cdTimerEndMatch = CreateTimer(5.0, CDRoundEnded);        
    }
	
}

public Action notShowScore (Handle timer)
{
    ServerCommand("-showscores");
}

public Action CDRoundEnded(Handle timer) 
{
    new classicCSMode=GetConVarInt(g_classicCSMode);
    endMatch = false;
    if(classicCSMode == 1){
        CreateTimer(0.1, notShowScore);
        ServerCommand("mp_restartgame 3");
    }else{
        ServerCommand("quit");
    }	
}

//ubah jadi tiap round start awal langsung mp_restartgame 20
//cari cara abis win dm 3 detik tim win +showscores 5 detik abis itu langsung disconnect
//cari cara buat ambil data kayak kill/death/assist/defuse/plant
public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast){
    
    g_roundStartedTime = GetTime();
    g_dmStat = GetConVarInt(FindConVar("cssdm_enabled"));
    // if(preparingMatch && g_dmStat == 1) g_cdTimerPreMatch = CreateTimer(1.0, Timer_CountDown);   

    T_kills = 0;
    CT_kills = 0;
}

public Action:KillClear(Handle:Timer){    
    T_kills = 0;
    CT_kills = 0;
}

stock bool:IsEven(num)
{
    return (num & 1) == 0;
}