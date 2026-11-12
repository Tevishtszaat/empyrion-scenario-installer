# Changelog

## 1.0.7 - 2026-11-12
- Empyrion auto-detect scans **all fixed drives** (C:, D:, E:, …), not only Steam libraries already known on one drive.
- **Browse…** folder picker starts at “This PC” so every drive is listed; the dialog is brought to the front.
- Empyrion path box accepts **paste/type** of any path; Browse adds the chosen folder to the list.
- Hint when Browse is cancelled: paste the path from Steam → Manage → Browse local files.
- The "delete the downloaded zip" checkbox no longer always says it frees ~19 GB. That size is only shown for the built-in Ascension-Reborn download. Any other link leaves the size off. If you already have the zip, the note uses that file's real size.
- Launcher assembly version set to 1.0.7.

## 1.0.6 - 2026-11-11
- Linux and macOS support: Steam library detection now looks in the usual places (`~/.steam/steam`, `~/.local/share/Steam`, Flatpak Steam, macOS Application Support). Console mode is used automatically on non-Windows (the WinForms GUI remains Windows-only).
- Added `Install-Scenario.sh` launcher (requires PowerShell Core / `pwsh`).
- Version bump to 1.0.6.

## 1.0.5 - 2026-11-09
- `installer.json` next to the exe / .ps1 (or `-Config <path>`): `defaultUrl`, `scenarioName`, `testFolderName`, `title`.
  Invalid files are ignored and logged; the built-in Ascension-Reborn defaults stay when there is no config.
- The exe tells the script where it lives, so `installer.json` next to the exe is found.
- Generic wording for a configured default link; the known Ascension-Reborn size is only used for that file.
- Public repository layout, deterministic build script, test runner, MIT license.

## 1.0.4 - 2026-11-09
- Window fits small screens: Install / Close, progress and status pinned at the bottom (Dock=Bottom); the rest
  scrolls (Dock=Fill + AutoScroll); size clamped to the screen's working area and centred; resizable and maximizable.
- Smaller log (about 5 lines) and save list. DPI aware (system DPI, AutoScaleMode Dpi).
- Layout math tested for 1024x560 to 1920x1040 at 100/125/150 %.

## 1.0.3 - 2026-11-09
- *Download link* box: paste your own link (Google Drive, Dropbox, OneDrive/SharePoint, direct .zip), *Reset to default*,
  `-DownloadUrl`. MEGA and Drive folder links get a clear message; non-http(s) links are refused.
- Downloads are checked to really be zips; resume state is tied to the link; the log records only the host.

## 1.0.2 - 2026-11-09
- Renamed to **Scenario Installer** (`ScenarioInstaller.exe`, `Install-Scenario.ps1/.bat`, `%TEMP%\ScenarioInstaller.log`).
- The scenario folder name comes from the zip's top folder (fallback: the zip's file name, then the default),
  sanitized, and shown in the window.

## 1.0.1 - 2026-11-09
- Folder-in-use handling: rename test before the download, Retry / Cancel, all-or-nothing moves, rollback,
  `Scenarios_Backups` created only when needed (and removed again if empty and created by the installer).
- Test install mode (default `<Empyrion drive>\AR_InstallTest`, with a TestGame save).

## 1.0.0 - 2026-11-09
- First version: Steam / Empyrion auto-detection (registry, `libraryfolders.vdf`, game and dedicated server),
  resumable chunked Google Drive download, extraction with progress, backup of an existing scenario (moved, never
  deleted), SharedData copy into `Saves\Games` / `Saves\Cache` folders, disk-space check, GUI + console modes,
  exe launcher + .bat fallback.
