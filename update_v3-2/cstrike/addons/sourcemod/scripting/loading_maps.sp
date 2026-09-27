#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"

public Plugin myinfo =
{
    name        = "Loading Screen Manager",
    author      = "Kento Style",
    description = "Check and generate loading screen files",
    version     = PLUGIN_VERSION,
    url         = ""
};

public void OnPluginStart()
{
    RegAdminCmd("sm_checkloading", Cmd_CheckLoading, ADMFLAG_ROOT, "Check loading screen files");
    RegAdminCmd("sm_generatevmt", Cmd_GenerateVMT, ADMFLAG_ROOT, "Generate missing VMT files");
}

public void OnMapStart()
{
    char mapName[64];
    GetCurrentMap(mapName, sizeof(mapName));

    char vmtPath[PLATFORM_MAX_PATH];
    char vtfPath[PLATFORM_MAX_PATH];

    Format(vmtPath, sizeof(vmtPath), "materials/vgui/maps/%s.vmt", mapName);
    Format(vtfPath, sizeof(vtfPath), "materials/vgui/maps/%s.vtf", mapName);

    bool hasVMT = FileExists(vmtPath, true);
    bool hasVTF = FileExists(vtfPath, true);

    if (hasVMT && hasVTF)
    {
        PrintToServer("[Loading] Map '%s' loading screen: OK", mapName);
    }
    else
    {
        if (!hasVMT)
            PrintToServer("[Loading] MISSING: %s", vmtPath);
        if (!hasVTF)
            PrintToServer("[Loading] MISSING: %s", vtfPath);
        PrintToServer("[Loading] Map '%s' will NOT have loading screen!", mapName);
    }
}

// ============================================================
// CHECK LOADING SCREENS
// ============================================================

public Action Cmd_CheckLoading(int client, int args)
{
    char mapDir[PLATFORM_MAX_PATH];
    Format(mapDir, sizeof(mapDir), "maps");

    DirectoryListing dir = OpenDirectory(mapDir, true);
    char fileName[128];
    FileType fileType;
    int total = 0;
    int hasScreen = 0;
    int missing = 0;

    if (dir == null)
    {
        ReplyToCommand(client, "[Loading] Cannot open maps directory!");
        return Plugin_Handled;
    }

    ReplyToCommand(client, "");
    ReplyToCommand(client, "=== Loading Screen Check ===");

    while (dir.GetNext(fileName, sizeof(fileName), fileType))
    {
        if (fileType != FileType_File)
            continue;

        int len = strlen(fileName);
        if (len < 5)
            continue;

        if (strcmp(fileName[len - 4], ".bsp", false) != 0)
            continue;

        // Hapus .bsp
        char mapName[128];
        strcopy(mapName, sizeof(mapName), fileName);
        mapName[len - 4] = '\0';

        // Cek files - pakai useValvefs = true
        char vmtFile[PLATFORM_MAX_PATH];
        char vtfFile[PLATFORM_MAX_PATH];
        Format(vmtFile, sizeof(vmtFile), "materials/vgui/maps/%s.vmt", mapName);
        Format(vtfFile, sizeof(vtfFile), "materials/vgui/maps/%s.vtf", mapName);

        bool vmt = FileExists(vmtFile, true);
        bool vtf = FileExists(vtfFile, true);

        total++;

        if (vmt && vtf)
        {
            hasScreen++;
            ReplyToCommand(client, "  [OK] %s", mapName);
        }
        else
        {
            missing++;
            char status[32];
            if (!vmt && !vtf)
                strcopy(status, sizeof(status), "NO VMT+VTF");
            else if (!vmt)
                strcopy(status, sizeof(status), "NO VMT");
            else
                strcopy(status, sizeof(status), "NO VTF");

            ReplyToCommand(client, "  [!!] %s (%s)", mapName, status);
        }
    }

    delete dir;

    ReplyToCommand(client, "");
    ReplyToCommand(client, "Total: %d maps | OK: %d | Missing: %d", total, hasScreen, missing);
    ReplyToCommand(client, "=============================");

    return Plugin_Handled;
}

// ============================================================
// GENERATE VMT FILES
// ============================================================

public Action Cmd_GenerateVMT(int client, int args)
{
    // Buat output directory pakai BuildPath
    char outDir[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, outDir, sizeof(outDir), "../../materials/vgui/maps");

    // Cek dan buat folder
    if (!DirExists(outDir))
    {
        if (!CreateDirectory(outDir, 511))
        {
            // Coba buat parent folders dulu
            char parent1[PLATFORM_MAX_PATH];
            char parent2[PLATFORM_MAX_PATH];
            char parent3[PLATFORM_MAX_PATH];

            BuildPath(Path_SM, parent1, sizeof(parent1), "../../materials");
            BuildPath(Path_SM, parent2, sizeof(parent2), "../../materials/vgui");
            BuildPath(Path_SM, parent3, sizeof(parent3), "../../materials/vgui/maps");

            if (!DirExists(parent1))
                CreateDirectory(parent1, 511);
            if (!DirExists(parent2))
                CreateDirectory(parent2, 511);
            if (!DirExists(parent3))
                CreateDirectory(parent3, 511);
        }

        PrintToServer("[Loading] Created directory: %s", outDir);
    }

    // Scan maps
    DirectoryListing dir = OpenDirectory("maps", true);
    char fileName[128];
    FileType fileType;
    int created = 0;
    int skipped = 0;

    if (dir == null)
    {
        ReplyToCommand(client, "[Loading] Cannot open maps directory!");
        return Plugin_Handled;
    }

    while (dir.GetNext(fileName, sizeof(fileName), fileType))
    {
        if (fileType != FileType_File)
            continue;

        int len = strlen(fileName);
        if (len < 5)
            continue;

        if (strcmp(fileName[len - 4], ".bsp", false) != 0)
            continue;

        char mapName[128];
        strcopy(mapName, sizeof(mapName), fileName);
        mapName[len - 4] = '\0';

        // Cek VMT sudah ada?
        char vmtPath[PLATFORM_MAX_PATH];
        Format(vmtPath, sizeof(vmtPath), "%s/%s.vmt", outDir, mapName);

        if (FileExists(vmtPath))
        {
            skipped++;
            continue;
        }

        // Generate VMT
        File vmtFile = OpenFile(vmtPath, "w");
        if (vmtFile != null)
        {
            vmtFile.WriteLine("\"UnlitGeneric\"");
            vmtFile.WriteLine("{");
            vmtFile.WriteLine("\t\"$basetexture\"\t\"vgui/maps/%s\"", mapName);
            vmtFile.WriteLine("\t\"$translucent\"\t\"1\"");
            vmtFile.WriteLine("\t\"$ignorez\"\t\"1\"");
            vmtFile.WriteLine("}");
            delete vmtFile;

            created++;
            ReplyToCommand(client, "  [OK] Created: %s.vmt", mapName);
        }
        else
        {
            ReplyToCommand(client, "  [!!] Failed: %s.vmt", mapName);
        }
    }

    delete dir;

    ReplyToCommand(client, "");
    ReplyToCommand(client, "[Loading] Created: %d | Skipped: %d", created, skipped);
    ReplyToCommand(client, "[Loading] NOTE: VTF files still needed!");
    ReplyToCommand(client, "[Loading] Put VTF files in: cstrike/materials/vgui/maps/");

    return Plugin_Handled;
}