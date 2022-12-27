/*================================================================================
	
	------------------------------
	-*- [ZP] Game Mode: Plague -*-
	------------------------------ 
	
	This plugin is part of Zombie Plague Mod and is distributed under the
	terms of the GNU General Public License. Check ZP_ReadMe.txt for details.
	
================================================================================*/

#include <amxmodx>
#include <fun>
#include <amx_settings_api>
#include <cs_teams_api>
#include <zp50_gamemodes>
#include <zp50_class_nemesis>
#include <zp50_class_survivor>
#include <zp50_deathmatch>

// Settings file
new const ZP_SETTINGS_FILE[] = "zombieplague.ini"

// Default sounds
new const sound_plague[][] = { "zombie_plague/nemesis1.wav" , "zombie_plague/survivor1.wav" }

#define SOUND_MAX_LENGTH 64

new Array:g_sound_plague

// HUD messages
#define HUD_EVENT_X -1.0
#define HUD_EVENT_Y 0.17
#define HUD_EVENT_R 0
#define HUD_EVENT_G 50
#define HUD_EVENT_B 200

new g_MaxPlayers
new g_HudSync

new cvar_plague_chance, cvar_plague_min_players
new cvar_plague_ratio
new cvar_plague_nemesis_count, cvar_plague_nem_hp_multi
new cvar_plague_survivor_count, cvar_plague_surv_hp_multi
new cvar_plague_show_hud, cvar_plague_sounds
new cvar_plague_allow_respawn

public plugin_precache()
{
	// Register game mode at precache (plugin gets paused after this)
	register_plugin("[ZP] Game Mode: Plague", ZP_VERSION_STRING, "ZP Dev Team")
	zp_gamemodes_register("Plague Mode")
	
	// Create the HUD Sync Objects
	g_HudSync = CreateHudSyncObj()
	
	g_MaxPlayers = get_maxplayers()
	
	cvar_plague_chance = register_cvar("zp_plague_chance", "20")
	cvar_plague_min_players = register_cvar("zp_plague_min_players", "0")
	cvar_plague_ratio = register_cvar("zp_plague_ratio", "0.5")
	cvar_plague_nemesis_count = register_cvar("zp_plague_nemesis_count", "1")
	cvar_plague_nem_hp_multi = register_cvar("zp_plague_nem_hp_multi", "0.5")
	cvar_plague_survivor_count = register_cvar("zp_plague_survivor_count", "1")
	cvar_plague_surv_hp_multi = register_cvar("zp_plague_surv_hp_multi", "0.5")
	cvar_plague_show_hud = register_cvar("zp_plague_show_hud", "1")
	cvar_plague_sounds = register_cvar("zp_plague_sounds", "1")
	cvar_plague_allow_respawn = register_cvar("zp_plague_allow_respawn", "0")
	
	// Initialize arrays
	g_sound_plague = ArrayCreate(SOUND_MAX_LENGTH, 1)
	
	// Load from external file
	amx_load_setting_string_arr(ZP_SETTINGS_FILE, "Sounds", "ROUND PLAGUE", g_sound_plague)
	
	// If we couldn't load custom sounds from file, use and save default ones
	new index
	if (ArraySize(g_sound_plague) == 0)
	{
		for (index = 0; index < sizeof sound_plague; index++)
			ArrayPushString(g_sound_plague, sound_plague[index])
		
		// Save to external file
		amx_save_setting_string_arr(ZP_SETTINGS_FILE, "Sounds", "ROUND PLAGUE", g_sound_plague)
	}
	
	// Precache sounds
	new sound[SOUND_MAX_LENGTH]
	for (index = 0; index < ArraySize(g_sound_plague); index++)
	{
		ArrayGetString(g_sound_plague, index, sound, charsmax(sound))
		if (equal(sound[strlen(sound)-4], ".mp3"))
		{
			format(sound, charsmax(sound), "sound/%s", sound)
			precache_generic(sound)
		}
		else
			precache_sound(sound)
	}
}

// Deathmatch module's player respawn forward
public zp_fw_deathmatch_respawn_pre(id)
{
	// Respawning allowed?
	if (!get_pcvar_num(cvar_plague_allow_respawn))
		return PLUGIN_HANDLED;
	
	return PLUGIN_CONTINUE;
}

public zp_fw_gamemodes_choose_pre(game_mode_id, skipchecks)
{
	new alive_count = GetAliveCount()
	
	if (!skipchecks)
	{
		// Random chance
		if (random_num(1, get_pcvar_num(cvar_plague_chance)) != 1)
			return PLUGIN_HANDLED;
		
		// Min players
		if (alive_count < get_pcvar_num(cvar_plague_min_players))
			return PLUGIN_HANDLED;
	}
	
	// There should be enough players to have the desired amount of nemesis and survivors
	if (alive_count < get_pcvar_num(cvar_plague_nemesis_count) + get_pcvar_num(cvar_plague_survivor_count))
		return PLUGIN_HANDLED;
	
	// Game mode allowed
	return PLUGIN_CONTINUE;
}

public zp_fw_gamemodes_start()
{
	// Calculate player counts
	new id, alive_count = GetAliveCount()
	new survivor_count = get_pcvar_num(cvar_plague_survivor_count)
	new nemesis_count = get_pcvar_num(cvar_plague_nemesis_count)
	new zombie_count = floatround((alive_count - (nemesis_count + survivor_count)) * get_pcvar_float(cvar_plague_ratio), floatround_ceil)
	
	// Turn specified amount of players into Survivors
	new iSurvivors, iMaxSurvivors = survivor_count
	while (iSurvivors < iMaxSurvivors)
	{
		// Choose random guy
		id = GetRandomAlive(random_num(1, alive_count))
		
		// Already a survivor?
		if (zp_class_survivor_get(id))
			continue;
		
		// If not, turn him into one
		zp_class_survivor_set(id)
		iSurvivors++
		
		// Apply survivor health multiplier
		set_user_health(id, floatround(get_user_health(id) * get_pcvar_float(cvar_plague_surv_hp_multi)))
	}
	
	// Turn specified amount of players into Nemesis
	new iNemesis, iMaxNemesis = nemesis_count
	while (iNemesis < iMaxNemesis)
	{
		// Choose random guy
		id = GetRandomAlive(random_num(1, alive_count))
		
		// Already a survivor or nemesis?
		if (zp_class_survivor_get(id) || zp_class_nemesis_get(id))
			continue;
		
		// If not, turn him into one
		zp_class_nemesis_set(id)
		iNemesis++
		
		// Apply nemesis health multiplier
		set_user_health(id, floatround(get_user_health(id) * get_pcvar_float(cvar_plague_nem_hp_multi)))
	}
	
	// Randomly turn iMaxZombies players into zombies
	new iZombies, iMaxZombies = zombie_count
	while (iZombies < iMaxZombies)
	{
		// Choose random guy
		id = GetRandomAlive(random_num(1, alive_count))
		
		// Already a zombie/nemesis or survivor
		if (zp_class_survivor_get(id) || zp_core_is_zombie(id))
			continue;
		
		// Turn into a zombie
		zp_core_infect(id, 0)
		iZombies++
	}
	
	// Turn the remaining players into humans
	for (id = 1; id <= g_MaxPlayers; id++)
	{
		// Not alive
		if (!is_user_alive(id))
			continue;
		
		// Only those who aren't zombies/nemesis or survivors
		if (zp_class_survivor_get(id) || zp_core_is_zombie(id))
			continue;
		
		// Switch to CT
		cs_set_player_team(id, CS_TEAM_CT)
	}
	
	// Play Plague sound
	if (get_pcvar_num(cvar_plague_sounds))
	{
		new sound[SOUND_MAX_LENGTH]
		ArrayGetString(g_sound_plague, random_num(0, ArraySize(g_sound_plague) - 1), sound, charsmax(sound))
		PlaySoundToClients(sound)
	}
	
	if (get_pcvar_num(cvar_plague_show_hud))
	{
		// Show Plague HUD notice
		set_hudmessage(HUD_EVENT_R, HUD_EVENT_G, HUD_EVENT_B, HUD_EVENT_X, HUD_EVENT_Y, 1, 0.0, 5.0, 1.0, 1.0, -1)
		ShowSyncHudMsg(0, g_HudSync, "%L", LANG_PLAYER, "NOTICE_PLAGUE")
	}
}

// Plays a sound on clients
PlaySoundToClients(const sound[])
{
	if (equal(sound[strlen(sound)-4], ".mp3"))
		client_cmd(0, "mp3 play ^"sound/%s^"", sound)
	else
		client_cmd(0, "spk ^"%s^"", sound)
}

// Get Alive Count -returns alive players number-
GetAliveCount()
{
	new iAlive, id
	
	for (id = 1; id <= g_MaxPlayers; id++)
	{
		if (is_user_alive(id))
			iAlive++
	}
	
	return iAlive;
}

// Get Random Alive -returns index of alive player number target_index -
GetRandomAlive(target_index)
{
	new iAlive, id
	
	for (id = 1; id <= g_MaxPlayers; id++)
	{
		if (is_user_alive(id))
			iAlive++
		
		if (iAlive == target_index)
			return id;
	}
	
	return -1;
}