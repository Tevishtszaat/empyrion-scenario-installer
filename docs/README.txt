SCENARIO INSTALLER v1.0.5  (for Empyrion - Galactic Survival)
====================================================================
Installs an Empyrion scenario and its SharedData in one go.
Default scenario: Ascension-Reborn (downloaded from its Google Drive link).

SMALL SCREENS
  The window fits itself to your screen. The Install / Close buttons, the
  progress bar and the status line stay pinned at the bottom; if the screen
  is small, scroll the upper part (mouse wheel or scroll bar), or resize or
  maximize the window.

WHAT IT DOES
  1. Finds your Empyrion folder automatically (through Steam, including extra
     Steam library drives). You can change it with "Browse...".
  2. Gets the scenario zip: downloads it from the "Download link" box, or uses
     a zip you already have. The box starts with the default link
     (Ascension-Reborn, about 19 GB, on Google Drive); paste your own link to
     install another scenario, or click "Reset to default". Supported links:
       - Google Drive file links (any form: .../file/d/<id>/view, open?id=,
         uc?id=, drive.usercontent...). Folder links are refused with a tip.
       - Dropbox (switched to dl=1 automatically)
       - OneDrive / 1drv.ms / SharePoint (best effort)
       - any direct http(s) link to a .zip
       - MEGA can't be downloaded by the installer: download it in your
         browser, then tick "I already have the zip".
     An interrupted download picks up where it left off when you run the
     installer again with the same link (a different link starts over).
     If the link gives a web page instead of a zip, the installer stops and
     tells you.
  3. Works out the scenario name from the zip: the zip's top folder (the one
     holding Content, Playfields, Sectors). If the zip has no top folder, the
     zip's file name is used, then "Ascension-Reborn". Unsafe names (with \ / or
     ..) are refused. The name is shown in the window before you install.
  4. Installs the scenario to:
        <Empyrion>\Content\Scenarios\<ScenarioName>
        e.g.  <Empyrion>\Content\Scenarios\Ascension-Reborn
     If that scenario is already installed, the old copy is MOVED (not deleted)
     to <Empyrion>\Content\Scenarios_Backups\<ScenarioName>_<date>.
     The move is all-or-nothing: if Windows refuses it because something is
     using the folder, nothing is changed and you get a Retry/Cancel box.
  5. Copies the scenario's SharedData folder into each save you tick, so that
     save sees the new models and assets:
        <Empyrion>\Saves\Games\<YourGame>\SharedData        (single player)
        <Empyrion>\Saves\Cache\<Server>_<IP>_<id>\SharedData (servers you joined)
     Files are merged: newer files overwrite older ones, nothing is deleted.

BEFORE YOU START
  * Close Empyrion (and any local dedicated server).
  * Free disk space (Ascension-Reborn example): about 19 GB for the download
    + 21 GB for the scenario + 21 GB for every save you tick. The installer
    checks this first. Tick "Delete the downloaded zip after a successful
    install" to get the download space back afterwards.

HOW TO RUN
  Double-click ScenarioInstaller.exe.
    Windows may show "Windows protected your PC" (the file isn't code-signed).
    Check the file first: in PowerShell run
      Get-FileHash .\ScenarioInstaller.exe -Algorithm SHA256
    and compare it with SHA256SUMS.txt on the GitHub release page. Then click
    "More info" > "Run anyway".
  If the .exe won't start or your antivirus blocks it, use the fallback:
    keep Install-Scenario.ps1 and Install-Scenario.bat in the same folder and
    double-click Install-Scenario.bat.

  Then:
    1. Check the Empyrion folder (green "OK" line).
    2. Keep the default download link or paste your own. Leave the download
       folder as is, or pick another drive with more space.
       Already have the zip (downloaded in your browser, or another scenario)?
       Tick "I already have the zip" and pick it. Check the "Scenario name"
       line under it.
    3. Tick the save(s) that should get the new assets. Starting a brand-new
       game? You can leave them all unticked: Empyrion copies SharedData itself
       when you create a new game from the scenario.
    4. Click Install. Then start Empyrion > New Game > Scenarios > <ScenarioName>.

TEST INSTALL (try it without touching your real scenario)
  Tick "TEST INSTALL - install to a test folder instead". The default test
  folder is <your Empyrion drive>\AR_InstallTest (e.g. D:\AR_InstallTest).
  The scenario goes to <test folder>\Content\Scenarios\<ScenarioName> and
  SharedData to <test folder>\Saves\Games\TestGame\SharedData, unless you tick
  real saves (you'll be asked to confirm). The window title, header and Install
  button say TEST MODE, and the log marks every test run. Disk space is
  checked on the test folder's drive. Delete the test folder yourself when done.

DEDICATED SERVER OWNERS
  Point step 1 at your "Empyrion - Dedicated Server" folder (it's detected too),
  and in step 3 use "Add folder..." to pick the server's
  Saves\Games\<SaveGameName> folder. Players who join get SharedData from the
  server automatically. A player can also pre-load it by ticking their
  Saves\Cache\<Server...> folder; that folder only exists after joining the
  server once. If the server's SharedData version differs, the game downloads
  the server's copy anyway.

SERVER ADMINS / SCENARIO MAKERS: YOUR OWN DEFAULT (installer.json)
  Put an installer.json next to ScenarioInstaller.exe (or Install-Scenario.ps1),
  or run it with -Config <path>. Start from installer.example.json:
    {
      "defaultUrl": "https://www.dropbox.com/s/your-share-id/MyScenario.zip?dl=0",
      "scenarioName": "MyScenario",
      "testFolderName": "MyScenario_InstallTest",
      "title": "MyScenario Installer"
    }
  Every field is optional. defaultUrl = the link the Download link box starts
  with; scenarioName = folder name for downloads from that link (otherwise read
  from the zip); testFolderName = test-mode folder name; title = window title.
  An invalid file is ignored (noted in the log) and the built-in defaults
  (Ascension-Reborn) are used. Big files on Google Drive often hit "Quota
  exceeded"; a host without download quotas (Cloudflare R2, Backblaze B2, an S3
  bucket, your own web server) works best.
  More: https://github.com/Tevishtszaat/empyrion-scenario-installer

IF SOMETHING GOES WRONG
  * "Quota exceeded": Google Drive limits how often a big file can be downloaded
    each day. Your progress is saved, so run the installer again later. Or
    download the zip in your browser and use "I already have the zip".
  * "No write access": right-click the installer > Run as administrator.
  * "Folder in use" / "Access to the path ... is denied": close File Explorer
    windows showing the scenario folder, editors with scenario files open,
    Empyrion, Empyrion Admin Helper (EAH) or a dedicated server, and wait for any
    antivirus/backup scan to finish (or run as administrator). Then click Retry.
    Nothing is changed until the move works.
  * "Not a zip" / "web page": the link isn't a direct download (or needs a
    sign-in). Use the file's share link with "Anyone with the link" access,
    or download it in your browser and tick "I already have the zip".
  * A full log is written to %TEMP%\ScenarioInstaller.log (it records only
    the website name of your link, not the full link).

ADVANCED (command line)
  Install-Scenario.bat -NoGui -ListOnly
      Lists the Steam libraries, Empyrion installs and save folders it finds.
  Install-Scenario.bat -NoGui -EmpyrionPath "D:\SteamLibrary\steamapps\common\Empyrion - Galactic Survival"
                       -SaveFolder "D:\...\Saves\Games\MyGame" [-ArchivePath "D:\Downloads\MyScenario.zip"]
                       [-DownloadUrl "https://www.dropbox.com/s/.../MyScenario.zip?dl=0"]
                       [-DownloadFolder D:\Temp] [-OverwriteInPlace] [-DeleteArchiveAfter] [-SkipSharedData]
                       [-TestInstall [-TestFolder D:\AR_InstallTest]] [-Config D:\path\installer.json]

Ascension-Reborn Discord: https://discord.gg/VTXkdf9Pbf
