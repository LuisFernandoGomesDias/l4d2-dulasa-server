#include <ripext>
#include <regex>
#include <sourcemod>

public Plugin myinfo =
{
	name		= "L4D2 - Player Statistics Sync",
	author		= "Altair Sossai",
	description = "Sends the information generated by plugin l4d2_playstats.smx to the API of l4d2_playstats",
	version		= "1.0.0",
	url			= "https://github.com/altair-sossai/l4d2-zone-server"
};

ConVar cvar_playstats_endpoint;
ConVar cvar_playstats_server;
ConVar cvar_playstats_access_token;

public void OnPluginStart()
{
	cvar_playstats_endpoint = CreateConVar("playstats_endpoint", "https://l4d2-playstats-api.azurewebsites.net", "Play Stats endpoint", FCVAR_PROTECTED);
	cvar_playstats_server = CreateConVar("playstats_server", "", "vanilla4mod", FCVAR_PROTECTED);
	cvar_playstats_access_token = CreateConVar("playstats_access_token", "", "Play Stats Access Token", FCVAR_PROTECTED);

	RegAdminCmd("sm_syncstats", SyncStats, ADMFLAG_BAN);

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

	CreateTimer(150.0, DisplayStatsUrlTick, _, TIMER_REPEAT);
}

public void Event_RoundStart(Event hEvent, const char[] eName, bool dontBroadcast)
{
	Sync();
}

public Action:SyncStats(client, args)
{
	Sync();
}

public Action DisplayStatsUrlTick(Handle timer)
{
	new String:server[100];
	GetConVarString(cvar_playstats_server, server, sizeof(server));

	PrintToChatAll("Estatísticas/ranking disponível em:");
	PrintToChatAll("\x03https://l4d2-playstats.azurewebsites.net/server/%s", server);

	return Plugin_Continue;
}

public void Sync()
{
	char logsPath[128] = "logs/";
	BuildPath(Path_SM, logsPath, PLATFORM_MAX_PATH, logsPath);

	Regex regex = new Regex("^\\w{4}-\\w{2}-\\w{2}_\\w{2}-\\w{2}_\\d{4}.*\\.txt$");
	DirectoryListing directoryListing = OpenDirectory(logsPath);

	char fileName[128];
	while (directoryListing.GetNext(fileName, sizeof(fileName))) 
	{
		if (!regex.Match(fileName))
			continue;

		SyncFile(fileName);
	}
}

public void SyncFile(String:fileName[])
{
	char filePath[128];
	FormatEx(filePath, sizeof(filePath), "%s%s", "logs/", fileName);
	BuildPath(Path_SM, filePath, PLATFORM_MAX_PATH, filePath);

	File file = OpenFile(filePath, "r");
	if (!file)
		return;

	char content[40000];
	file.ReadString(content, sizeof(content), -1);

	JSONObject command = new JSONObject();

	command.SetString("fileName", fileName);
	command.SetString("content", content);

	HTTPRequest request = BuildHTTPRequest("/api/statistics");
	request.Post(command, SyncFileResponse);
}

void SyncFileResponse(HTTPResponse httpResponse, any value)
{
	if (httpResponse.Status != HTTPStatus_OK)
		return;

	JSONObject response = view_as<JSONObject>(httpResponse.Data);

	bool mustBeDeleted = response.GetBool("mustBeDeleted");
	if (!mustBeDeleted)
		return;

	char fileName[128];
	response.GetString("fileName", fileName, sizeof(fileName));

	char filePath[128];
	FormatEx(filePath, sizeof(filePath), "%s%s", "logs/", fileName);
	BuildPath(Path_SM, filePath, PLATFORM_MAX_PATH, filePath);

	DeleteFile(filePath);
}

HTTPRequest BuildHTTPRequest(char[] path)
{
	new String:endpoint[255];
	GetConVarString(cvar_playstats_endpoint, endpoint, sizeof(endpoint));
	StrCat(endpoint, sizeof(endpoint), path);

	new String:access_token[100];
	GetConVarString(cvar_playstats_access_token, access_token, sizeof(access_token));

	HTTPRequest request = new HTTPRequest(endpoint);
	request.SetHeader("Authorization", access_token);

	return request;
}