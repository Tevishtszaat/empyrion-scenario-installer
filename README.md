# Scenario Installer for Empyrion - Galactic Survival

A one-click installer for Empyrion scenarios. It finds your Empyrion folder, downloads the
scenario zip (resumable), installs it into `Content/Scenarios/<ScenarioName>` and copies the scenario's
**SharedData** into the saves you pick. An existing copy is always **moved to a backup, never deleted**.

The built-in default is the **Ascension-Reborn** scenario (about 19 GB zip on Google Drive), but players can
paste any link, and server admins / scenario makers can ship their own default with an `installer.json`.

- **Windows** 10/11: Windows PowerShell 5.1 (built in). No install, no admin rights needed (unless your Empyrion folder is write-protected). Download the `.exe` or `.zip` from Releases.
- **Linux / macOS**: Requires [PowerShell Core](https://github.com/PowerShell/PowerShell) (`pwsh`). Use the `Install-Scenario.sh` launcher (or run the `.ps1` directly). Console mode is used automatically. Steam libraries are detected in the usual places (including Flatpak Steam on Linux).
- Download: [Releases](../../releases) -> `ScenarioInstaller_v1.0.6.zip` (Windows) or the source files for Linux.

---

## For players

1. Close Empyrion (and any local dedicated server).
2. **Windows**: Unzip the release and double-click **ScenarioInstaller.exe**
   (fallback: keep `Install-Scenario.ps1` and `Install-Scenario.bat` together and run the `.bat`).
   **Linux / macOS**: Make sure `pwsh` is installed, then run `./Install-Scenario.sh` (or `pwsh -File Install-Scenario.ps1`).
3. In the window (Windows) or prompts (Linux/macOS):
   1. **Empyrion folder**: found automatically through Steam (Windows registry + `libraryfolders.vdf`, or Linux/macOS common Steam paths; app 383120 and the dedicated server 530870). Change it with *Browse...* if needed (Windows) or by passing `-EmpyrionPath`.
   2. **Download link**: keep the default or paste your own (see [link types](#link-types)).
      Already downloaded the zip in your browser? Tick *I already have the zip* and pick it (or use `-ArchivePath`).
      The *Scenario name* line shows where it will be installed.
   3. **Saves**: tick the saves that should get the new SharedData (see below), or none for a brand-new game.
   4. Click **Install** (or confirm in the console), then *Empyrion > New Game > Scenarios > <ScenarioName>*.

### What gets installed where

| What | Where |
|---|---|
| Scenario | `<Empyrion>/Content/Scenarios/<ScenarioName>` (name = the zip's top folder, else the zip's file name) |
| Previous copy of that scenario | moved to `<Empyrion>/Content/Scenarios_Backups/<ScenarioName>_<date>_<time>` |
| SharedData for a **single-player** save | `<Empyrion>/Saves/Games/<YourGame>/SharedData` |
| SharedData for a **server you joined** | `<Empyrion>/Saves/Cache/<Server>_<IP>_<id>/SharedData` (exists after joining once) |

SharedData is merged: newer files overwrite older ones, nothing is deleted. A new game started from the
scenario copies SharedData by itself, so you can leave every save unticked for that.
If a server's SharedData version differs from yours, the game downloads the server's copy anyway.

Disk space is checked first (download + scenario + one copy per ticked save, for Ascension-Reborn about
19 + 21 + 21 GB). Tick *Delete the downloaded zip after a successful install* to get the download space back.

Small screens: the window fits itself to the screen; Install / Close, the progress bar and status stay pinned
at the bottom and the rest scrolls. The window can be resized and maximized. (Windows GUI only.)

### Windows SmartScreen ("Windows protected your PC")

The exe is not code-signed, so SmartScreen may warn about it. Click **More info > Run anyway** - after checking it:

1. Download only from this repository's Releases page.
2. Compare the SHA-256 with `SHA256SUMS.txt` on the release:
   ```powershell
   Get-FileHash .\ScenarioInstaller.exe -Algorithm SHA256
   ```
3. The exe is only a small launcher: it writes the embedded `Install-Scenario.ps1` (the same file as in the zip,
   plain text, readable in Notepad) to `%TEMP%\ScenarioInstaller\` and runs it with Windows PowerShell.
   Prefer not to run an exe? Use `Install-Scenario.bat` + `Install-Scenario.ps1` from the zip instead.
4. The build is deterministic: [building from source](#building-from-source) with the same PowerShell version
   gives a byte-identical exe, so you can compare the hash yourself.

### Test install mode

Tick **TEST INSTALL** to install into a separate folder (default `<your Empyrion drive>/AR_InstallTest`,
e.g. `D:\AR_InstallTest` or `/home/you/AR_InstallTest`) instead of the real game. The scenario goes to `<test>/Content/Scenarios/<ScenarioName>`
and SharedData to `<test>/Saves/Games/TestGame/SharedData` (unless you tick real saves - you'll be asked to confirm).
Title, header and button say TEST MODE and every log line is marked. Your real scenario is not touched.
Delete the test folder yourself when done.

### When a folder is in use

Windows refuses to move a folder while something has it open (File Explorer, an editor, Empyrion,
Empyrion Admin Helper, a dedicated server, antivirus or backup scans). The installer:

- checks that the existing scenario folder can be moved **before** a long download (a quick rename test);
- moves it all-or-nothing (same-drive rename), so there are never half-moved folders;
- shows **Retry / Cancel** with a list of the usual culprits; nothing is changed until the move works;
- rolls back if a later step fails right after the move, and creates `Scenarios_Backups` only when it actually
  moves something (an empty one it created is removed again). Files that can't be written during extraction get
  the same Retry / Cancel prompt.

(On Linux the same logic applies using the filesystem.)

### If something goes wrong

- **"Quota exceeded"** (Google Drive): Drive limits how often a big file can be downloaded per day. Progress is
  saved; run the installer again later, or download the zip in your browser and use *I already have the zip*.
- **"Not a zip" / "web page"**: the link isn't a direct download or needs a sign-in. Share the file as
  "Anyone with the link", or download it in a browser.
- **"No write access"**: on Windows right-click the installer > *Run as administrator*. On Linux check directory permissions.
- Full log: `%TEMP%\ScenarioInstaller.log` on Windows, or `$TMPDIR/ScenarioInstaller.log` / `/tmp/ScenarioInstaller.log` on Linux/macOS (it records only the website name of your link, never the full link).

---

## For server admins and scenario makers

Put an **`installer.json` next to `ScenarioInstaller.exe`** (or next to `Install-Scenario.ps1`, or pass
`-Config <path>`) to make the installer default to your scenario. Start from
[`installer.example.json`](installer.example.json):

```json
{
  "defaultUrl": "https://www.dropbox.com/s/your-share-id/MyScenario.zip?dl=0",
  "scenarioName": "MyScenario",
  "testFolderName": "MyScenario_InstallTest",
  "title": "MyScenario Installer"
}
```

| Field | Meaning |
|---|---|
| `defaultUrl` | The link the *Download link* box starts with (and *Reset to default* returns to). Any [supported link](#link-types). |
| `scenarioName` | Optional. Folder name under `Content/Scenarios` for downloads from `defaultUrl` (overrides the zip's top folder). Players' own links and own zips are still named from the zip. Without it the name is read from the zip. |
| `testFolderName` | Optional. Name of the test-mode folder on the Empyrion drive (default `AR_InstallTest`). |
| `title` | Optional. Window title / header text (max 80 characters). |

All fields are optional; keys starting with `_` are ignored (use them for comments). Names must be plain folder
names (no `/ \ .. : * ? " < > |`). If the file is not valid JSON (or not a JSON object), it is **ignored and logged**,
and the built-in defaults are used; a single bad field is ignored on its own and the rest still applies.
Without any `installer.json`, the exe uses the built-in Ascension-Reborn defaults.

Ship it to players as a zip: `ScenarioInstaller.exe`, `installer.json`, `Install-Scenario.ps1`, `Install-Scenario.bat` (and `Install-Scenario.sh` for Linux users).
(Want your link baked into the exe instead? Change `$script:DefaultDownloadUrl`, `$script:DriveFileId` and
`$script:ScenarioName` at the top of `src/Install-Scenario.ps1` and [rebuild](#building-from-source).)

### Link types

| Host | Notes |
|---|---|
| Google Drive | Any file link form (`/file/d/<id>/view`, `open?id=`, `uc?id=`, `drive.usercontent...`). Share as "Anyone with the link". Folder links are refused with a tip. Downloaded in 256 MB chunks with resume. |
| Dropbox | `dl=0` is switched to `dl=1` automatically. |
| OneDrive / 1drv.ms / SharePoint | Best effort (converted to a direct download link). |
| Any direct `http(s)` link to a `.zip` | Your own web server, GitHub Releases asset, S3/R2/B2 bucket, etc. Range requests (resume) are used when the server supports them. |
| MEGA | Can't be downloaded by a script (MEGA decrypts in the browser): players download it in the browser and use *I already have the zip*. |

Only `http://` and `https://` links are accepted. The download must really be a zip (checked by its `PK`
signature), otherwise the installer stops and says so.

**Google Drive quota warning:** Drive throttles popular large files ("Quota exceeded" / "Too many users have
viewed or downloaded this file"), often for 24 hours, and a 20 GB scenario hits that quickly when many players
download at once. The installer retries and resumes, but for big files prefer a host without a download quota:
**Cloudflare R2** (no egress fees), **Backblaze B2**, any **S3-compatible bucket** or your own **web server**
(direct links with Range support resume best), or **Dropbox** for moderate traffic. Keep Drive as a mirror if you like.

Dedicated servers: point step 1 at your *Empyrion - Dedicated Server* folder (it is detected too) and use
*Add folder...* to pick the server's `Saves/Games/<SaveGameName>`. Players who join get SharedData from the server.

---

## Command line

```
Install-Scenario.bat -NoGui -ListOnly
Install-Scenario.bat -NoGui [-EmpyrionPath "<Empyrion folder>"] [-SaveFolder "<save1>","<save2>"]
                     [-ArchivePath "<zip>"] [-DownloadUrl "<link>"] [-DownloadFolder "<folder>"]
                     [-OverwriteInPlace] [-DeleteArchiveAfter] [-SkipSharedData] [-SkipSpaceCheck]
                     [-TestInstall [-TestFolder "<folder>"]] [-Config "<installer.json>"]
```

On Linux/macOS use `./Install-Scenario.sh` or `pwsh -File Install-Scenario.ps1` with the same flags.
`ScenarioInstaller.exe` accepts the same parameters.

| Flag | Meaning |
|---|---|
| `-NoGui` | Console install (no window). Automatically used on non-Windows. |
| `-ListOnly` | Print the Steam libraries, Empyrion installs and save folders found, then exit. |
| `-EmpyrionPath` | Use this Empyrion folder instead of auto-detection. |
| `-ArchivePath` | Use a zip you already have (no download). |
| `-DownloadUrl` | Download from this link instead of the default. |
| `-DownloadFolder` | Where the zip is downloaded (default `%USERPROFILE%\Downloads` or `~/Downloads`). |
| `-SaveFolder` | One or more save / cache folders that get SharedData (comma or semicolon separated). |
| `-SkipSharedData` | Don't copy SharedData into any save. |
| `-OverwriteInPlace` | Update an existing scenario folder in place instead of moving it to `Scenarios_Backups`. |
| `-DeleteArchiveAfter` | Delete the downloaded zip after a successful install. |
| `-SkipSpaceCheck` | Skip the free-space check. |
| `-TestInstall`, `-TestFolder` | Test mode (see above). |
| `-Config` | Use this `installer.json`. |

---

## Building from source

Requirements: [PowerShell 7](https://github.com/PowerShell/PowerShell) (`pwsh`, it ships the Roslyn C# compiler);
Windows, Linux or macOS. The .NET Framework 4.8 reference assemblies are downloaded once from nuget.org
(`Microsoft.NETFramework.ReferenceAssemblies.net48` 1.0.3) into `.build/`.

```
pwsh -NoProfile -File src/launcher/build.ps1        # -> dist/ScenarioInstaller.exe, Install-Scenario.ps1 (CRLF + BOM), .bat, .sh, example json
pwsh -NoProfile -File tests/run-all.ps1             # all test suites
```

Layout:

```
src/Install-Scenario.ps1      the installer (GUI + console), Windows PowerShell 5.1 compatible, plain ASCII
src/launcher/Launcher.cs      the exe: embeds the .ps1, runs it with powershell.exe -STA
src/launcher/app.manifest     asInvoker manifest; app.ico: icon
src/launcher/build.ps1        build script
Install-Scenario.bat          fallback launcher for the .ps1 (Windows)
Install-Scenario.sh           launcher for the .ps1 (Linux / macOS, requires pwsh)
installer.example.json        config example
docs/README.txt               plain-text player readme that goes into the release zip
tests/                        unit, name, lock (folder-in-use), url (links + downloads against tests/mockserver.py),
                              config (installer.json) and gui (window layout math) suites
```

Tests run on Linux with pwsh 7.4 (the WinForms window itself can only be tested on Windows); the url suite needs
`python3` for the local mock HTTP server; the lock suite uses `chmod`.

## License

[MIT](LICENSE) (c) 2026 Don Patterson. Empyrion - Galactic Survival is a trademark of Eleon Game Studios; this
project is not affiliated with Eleon. Scenario content belongs to its authors.
