#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define L4D2_TEAM_SPECTATOR 1
#define L4D2_TEAM_SURVIVOR 2
#define L4D2_TEAM_INFECTED 3

bool fixTeam = false;

ArrayList winners;
ArrayList losers;

public Plugin myinfo =
{
	name		= "L4D2 - Fix team shuffle",
	author		= "Altair Sossai",
	description = "Fix teams shuffling during map switching",
	version		= "1.0.0",
	url			= "https://github.com/altair-sossai/l4d2-zone-server"
};

public void OnPluginStart()
{
	HookEvent("round_start", RoundStart_Event);
	HookEvent("player_team", PlayerTeam_Event, EventHookMode_Post);

	winners = CreateArray(64);
	losers = CreateArray(64);
}

public void OnRoundIsLive()
{
	DisableFixTeam();
	ClearTeamsData();
}

public void L4D2_OnEndVersusModeRound_Post()
{
	SaveTeams();
}

public void RoundStart_Event(Handle event, const char[] name, bool dontBroadcast)
{
	DisableFixTeam();

	if (IsNewGame())
		return;

	CreateTimer(1.0, EnableFixTeam_Timer);
}

public void PlayerTeam_Event(Event event, const char[] name, bool dontBroadcast)
{
	if (!fixTeam)
		return;

	CreateTimer(1.0, FixTeam_Timer);
}

public Action FixTeam_Timer(Handle timer)
{
	FixTeams();

	return Plugin_Continue;
}

public Action EnableFixTeam_Timer(Handle timer)
{
	EnableFixTeam();
	FixTeams();
	CreateTimer(30.0, DisableFixTeam_Timer);

	return Plugin_Continue;
}

public Action DisableFixTeam_Timer(Handle timer)
{
	DisableFixTeam();

	return Plugin_Continue;
}

public void SaveTeams()
{
	ClearTeamsData();

	bool survivorsAreWinning = SurvivorsAreWinning();

	CopySteamIdsToArray(winners, survivorsAreWinning ? L4D2_TEAM_SURVIVOR : L4D2_TEAM_INFECTED);
	CopySteamIdsToArray(losers, survivorsAreWinning ? L4D2_TEAM_INFECTED : L4D2_TEAM_SURVIVOR);
}

public void CopySteamIdsToArray(ArrayList arrayList, int team)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != team)
			continue;
		
		PushArrayCell(arrayList, client);
	}
}

public void FixTeams()
{
	if (!fixTeam)
		return;

	if (GetArraySize(winners) == 0 && GetArraySize(losers) == 0)
		return;

	DisableFixTeam();

	bool survivorsAreWinning = SurvivorsAreWinning();

	MoveToSpectatorWhoIsNotInTheTeam(winners, survivorsAreWinning ? L4D2_TEAM_SURVIVOR : L4D2_TEAM_INFECTED);
	MoveToSpectatorWhoIsNotInTheTeam(losers, survivorsAreWinning ? L4D2_TEAM_INFECTED : L4D2_TEAM_SURVIVOR);

	MoveSpectatorsToTheCorrectTeam(winners, survivorsAreWinning ? L4D2_TEAM_SURVIVOR : L4D2_TEAM_INFECTED);
	MoveSpectatorsToTheCorrectTeam(losers, survivorsAreWinning ? L4D2_TEAM_INFECTED : L4D2_TEAM_SURVIVOR);

	EnableFixTeam();
}

public void MoveToSpectatorWhoIsNotInTheTeam(ArrayList arrayList, int team)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != team)
			continue;

		bool correctTeam = false;
		int arraySize = GetArraySize(arrayList);

		for (int i = 0; !correctTeam && i < arraySize; i++)
			correctTeam = GetArrayCell(arrayList, i) == client;

		if (!correctTeam)
			MovePlayerToSpectator(client);
	}
}

public void MoveSpectatorsToTheCorrectTeam(ArrayList arrayList, int team)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != L4D2_TEAM_SPECTATOR)
			continue;

		bool wasOnTheTeam = false;
		int arraySize = GetArraySize(arrayList);

		for (int i = 0; !wasOnTheTeam && i < arraySize; i++)
			wasOnTheTeam = GetArrayCell(arrayList, i) == client;

		if (!wasOnTheTeam)
			continue;

		if (team == L4D2_TEAM_SURVIVOR)
			MovePlayerToSurvivor(client);
		else if (team == L4D2_TEAM_INFECTED)
			MovePlayerToInfected(client);
	}
}

public bool SurvivorsAreWinning()
{
	int flipped = GameRules_GetProp("m_bAreTeamsFlipped");

	int survivorIndex = flipped ? 1 : 0;
	int infectedIndex = flipped ? 0 : 1;

	int survivorScore = L4D2Direct_GetVSCampaignScore(survivorIndex);
	int infectedScore = L4D2Direct_GetVSCampaignScore(infectedIndex);

	return survivorScore > infectedScore;
}

public void EnableFixTeam()
{
	fixTeam = true;
}

public void DisableFixTeam()
{
	fixTeam = false;
}

public void ClearTeamsData()
{
	winners.Clear();
	losers.Clear();
}

public bool IsNewGame()
{
	int teamAScore = L4D2Direct_GetVSCampaignScore(0);
	int teamBScore = L4D2Direct_GetVSCampaignScore(1);

	return teamAScore == 0 && teamBScore == 0;
}

public void MovePlayerToSpectator(int client)
{
	ChangeClientTeam(client, L4D2_TEAM_SPECTATOR);
}

public void MovePlayerToSurvivor(int client)
{
	if (NumberOfPlayersInTheTeam(L4D2_TEAM_SURVIVOR) >= TeamSize())
		return;

	int bot = FindSurvivorBot();
	if (bot <= 0)
		return;

	int flags = GetCommandFlags("sb_takecontrol");
	SetCommandFlags("sb_takecontrol", flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "sb_takecontrol");
	SetCommandFlags("sb_takecontrol", flags);
}

public void MovePlayerToInfected(int client)
{
	if (NumberOfPlayersInTheTeam(L4D2_TEAM_INFECTED) >= TeamSize())
		return;

	ChangeClientTeam(client, L4D2_TEAM_INFECTED);
}

public int NumberOfPlayersInTheTeam(int team)
{
	int count = 0;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != team)
			continue;

		count++;
	}

	return count;
}

public int TeamSize()
{
	return GetConVarInt(FindConVar("survivor_limit"));
}

public int FindSurvivorBot()
{
	for (int client = 1; client <= MaxClients; client++)
		if(IsClientInGame(client) && IsFakeClient(client) && GetClientTeam(client) == L4D2_TEAM_SURVIVOR)
			return client;

	return -1;
}