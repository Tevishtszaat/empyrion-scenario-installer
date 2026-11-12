import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useRef, useState } from "react";

export const Route = createFileRoute("/")({ component: Home });

const DEFAULT_URL =
  "https://drive.google.com/file/d/1jtetatjWTRW-JWj1YJkHJP77fXZLd-vh/view?usp=drive_link";

const EMPYRION = [
  "D:\\Steam\\steamapps\\common\\Empyrion - Galactic Survival",
  "D:\\SteamLibrary\\steamapps\\common\\Empyrion - Dedicated Server",
];

const SAVES = [
  { kind: "Games", name: "MySurvival", shared: true },
  { kind: "Games", name: "TestWorld", shared: false },
  { kind: "Cache", name: "Official_203.0.113.8_44100", shared: true },
] as const;

function stamp() {
  return new Date().toLocaleTimeString("en-GB", { hour12: false });
}

function Home() {
  const [view, setView] = useState<"windows" | "linux">("windows");
  return (
    <main className="min-h-screen bg-desk px-3 py-4 text-chrome-fg sm:px-6 sm:py-6">
      <div className="mx-auto flex max-w-4xl flex-col gap-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-chrome-fg/80">
            Scenario Installer 1.0.7 — the window players see on Windows. Linux uses the same steps in the console.
          </p>
          <div className="flex rounded-md border border-line/40 bg-chrome p-0.5 text-sm">
            <button
              type="button"
              onClick={() => setView("windows")}
              className={
                "min-h-11 rounded px-3 " +
                (view === "windows" ? "bg-form font-semibold text-ink" : "text-chrome-fg")
              }
            >
              Windows window
            </button>
            <button
              type="button"
              onClick={() => setView("linux")}
              className={
                "min-h-11 rounded px-3 " +
                (view === "linux" ? "bg-form font-semibold text-ink" : "text-chrome-fg")
              }
            >
              Linux console
            </button>
          </div>
        </div>
        {view === "windows" ? <WindowsWindow /> : <LinuxConsole />}
      </div>
    </main>
  );
}

function safeFolder(name: string) {
  const cleaned = name.replace(/[<>:"/\\|?*]/g, "").replace(/\.+$/g, "").trim();
  return cleaned || "Scenario";
}

const LINK_NOISE = new Set([
  "view",
  "edit",
  "file",
  "open",
  "uc",
  "download",
  "folders",
  "drive",
  "share",
  "s",
  "d",
]);

function nameFromUrl(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed || trimmed === DEFAULT_URL) return trimmed === DEFAULT_URL ? "Ascension-Reborn" : "";
  const bits: string[] = [];
  try {
    const u = new URL(trimmed);
    bits.push(...u.pathname.split("/"));
    for (const [key, value] of u.searchParams) {
      if (key.toLowerCase() === "usp") continue;
      bits.push(value);
    }
  } catch {
    bits.push(trimmed);
  }
  let candidate = "";
  for (const bit of bits) {
    let decoded = bit;
    try {
      decoded = decodeURIComponent(bit);
    } catch {
      decoded = bit;
    }
    decoded = decoded.replace(/\.zip$/i, "").trim();
    if (!decoded || LINK_NOISE.has(decoded.toLowerCase())) continue;
    if (/^(drive_link|sharing|download|drivesdk)$/i.test(decoded)) continue;
    if (/^[A-Za-z0-9_-]{20,}$/.test(decoded)) continue;
    if (!/[A-Za-z]/.test(decoded)) continue;
    if (/^https?:/i.test(decoded)) continue;
    candidate = decoded;
  }
  return candidate;
}

function WindowsWindow() {
  const [empyrion, setEmpyrion] = useState(EMPYRION[0]);
  const [url, setUrl] = useState(DEFAULT_URL);
  const [downloadDir, setDownloadDir] = useState("C:\\Users\\You\\Downloads");
  const [haveZip, setHaveZip] = useState(false);
  const [zipPath, setZipPath] = useState("");
  const [folderName, setFolderName] = useState("Ascension-Reborn");
  const [folderLocked, setFolderLocked] = useState(false);
  const [customInstall, setCustomInstall] = useState(false);
  const [customPath, setCustomPath] = useState("");
  const [checked, setChecked] = useState<boolean[]>(() => SAVES.map(() => false));
  const [overwrite, setOverwrite] = useState(false);
  const [deleteZip, setDeleteZip] = useState(false);
  const [extractAfter, setExtractAfter] = useState(true);
  const [watch, setWatch] = useState(true);
  const [schedule, setSchedule] = useState<"open" | "hour" | "day">("hour");
  const [installedUrl, setInstalledUrl] = useState(DEFAULT_URL);
  const [watchNote, setWatchNote] = useState("Up to date. The next check follows the schedule.");
  const [testMode, setTestMode] = useState(false);
  const [testFolder, setTestFolder] = useState("D:\\AR_InstallTest");
  const [log, setLog] = useState("");
  const [status, setStatus] = useState("Ready.");
  const [progress, setProgress] = useState(0);
  const [busy, setBusy] = useState(false);
  const cancelRef = useRef(false);
  const busyRef = useRef(false);
  const logRef = useRef<HTMLTextAreaElement>(null);
  const checkRef = useRef<() => Promise<void>>(async () => {});

  const detected = useMemo(() => {
    if (haveZip) {
      const base = zipPath.split(/[/\\]/).pop()?.replace(/\.zip$/i, "").trim() ?? "";
      return base;
    }
    return nameFromUrl(url);
  }, [haveZip, zipPath, url]);

  useEffect(() => {
    if (!folderLocked) setFolderName(detected);
  }, [detected, folderLocked]);

  const scenario = folderName.trim() ? safeFolder(folderName) : "";
  const destRoot = testMode ? testFolder : empyrion;
  const standardDest = `${destRoot}\\Content\\Scenarios\\${scenario}`;
  const dest = customInstall ? customPath.trim() : standardDest;
  const pathReady = dest.length > 0;

  const nameLine = useMemo(() => {
    if (haveZip && !zipPath) return { tone: "bad" as const, text: "Pick your zip to see the scenario name." };
    if (haveZip) {
      return {
        tone: "ok" as const,
        text: `Name from the zip: ${detected || "unknown"}   (you can install it under a different folder below)`,
      };
    }
    if (url.trim() === DEFAULT_URL && !folderLocked) {
      return {
        tone: "ink" as const,
        text: "Scenario name: Ascension-Reborn   (default download; confirmed from the zip after downloading)",
      };
    }
    if (scenario) {
      return {
        tone: "ok" as const,
        text: `Scenario name: ${scenario}   (from the link, not the previous scenario)`,
      };
    }
    return {
      tone: "link" as const,
      text: "This link has no scenario name in it. Ascension-Reborn was cleared — type the folder, or leave it blank and use the zip's top folder.",
    };
  }, [haveZip, zipPath, url, detected, folderLocked, scenario]);

  function append(line: string) {
    setLog((prev) => prev + `${stamp()}  ${line}\n`);
  }

  useEffect(() => {
    const lines = [
      "Looking for Steam and Empyrion...",
      "Steam library: D:\\Steam",
      "Steam library: D:\\SteamLibrary",
      "Found Game: " + EMPYRION[0],
      "Found Dedicated Server: " + EMPYRION[1],
    ];
    setLog(lines.map((l) => `${stamp()}  ${l}`).join("\n") + "\n");
  }, []);

  useEffect(() => {
    if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
  }, [log]);

  function toggleSave(i: number) {
    setChecked((prev) => prev.map((v, n) => (n === i ? !v : v)));
  }

  async function runSteps(steps: readonly (readonly [number, string])[]) {
    for (const [pct, text] of steps) {
      if (cancelRef.current) {
        setStatus("Stopped.");
        append("Cancelled.");
        return false;
      }
      setProgress(pct);
      setStatus(text);
      append(text);
      await new Promise((r) => setTimeout(r, 420));
    }
    return true;
  }

  async function install() {
    if (busyRef.current) return;
    const link = url.trim();
    if (watch && !haveZip && link !== installedUrl) {
      setWatchNote("That link is newer. It stays uninstalled until a check finishes the download.");
      append("Install held. The new file is not ready.");
      return;
    }
    cancelRef.current = false;
    busyRef.current = true;
    setBusy(true);
    setProgress(0);
    const steps = extractAfter
      ? ([
          [8, "Checking free space..."],
          [18, haveZip ? "Using the zip you already have." : "Downloading scenario zip (resumable)..."],
          [42, testMode ? "TEST MODE — writing into the scratch folder." : "Download finished."],
          [68, `Extracting to ${dest}`],
          [84, overwrite
            ? "Updating the existing scenario folder in place."
            : "Existing copy would be moved to Content\\Scenarios_Backups (never deleted)."],
          [94, checked.some(Boolean) ? "Copying SharedData into the ticked saves." : "No saves ticked — a new game copies SharedData itself."],
          [100, deleteZip ? "Install finished. Downloaded zip removed." : "Install finished."],
        ] as const)
      : ([
          [12, "Checking free space..."],
          [55, haveZip ? "Zip already on disk. Extract is off, so it was left as-is." : "Downloading scenario zip (resumable)..."],
          [100, "Download finished. Scenario was not extracted."],
        ] as const);
    const ok = await runSteps(steps);
    if (ok && !haveZip) {
      setInstalledUrl(link);
      setWatchNote("Installed. This link is watched. A newer file installs only after it has fully downloaded.");
    }
    busyRef.current = false;
    setBusy(false);
  }

  async function checkLink() {
    if (busyRef.current) return;
    const link = url.trim();
    if (!link) {
      setWatchNote("Paste a scenario link to watch.");
      return;
    }
    cancelRef.current = false;
    busyRef.current = true;
    setBusy(true);
    setProgress(0);
    setStatus("Checking the scenario link...");
    append("Checking the scenario link for a newer file...");
    await new Promise((r) => setTimeout(r, 500));
    if (cancelRef.current) {
      setStatus("Stopped.");
      append("Check cancelled.");
      busyRef.current = false;
      setBusy(false);
      return;
    }
    if (link === installedUrl) {
      setWatchNote("No newer file. The installed scenario was left as it is.");
      setStatus("Up to date.");
      append("No newer file on the link.");
      setProgress(0);
      busyRef.current = false;
      setBusy(false);
      return;
    }
    setWatchNote("Newer file found. Downloading it. Install waits until the file is complete.");
    const downloaded = await runSteps([
      [30, "Newer file on the link. Downloading..."],
      [70, "Still downloading. Not installing yet."],
      [100, "Download complete. The update is ready."],
    ] as const);
    if (!downloaded) {
      busyRef.current = false;
      setBusy(false);
      return;
    }
    if (!extractAfter) {
      setInstalledUrl(link);
      setWatchNote("Ready file saved. Extract is off, so the scenario folder was not changed.");
      append("Update downloaded and left as a zip.");
      busyRef.current = false;
      setBusy(false);
      return;
    }
    setWatchNote("Ready. Installing the update now.");
    append("Update is ready. Installing.");
    const installed = await runSteps([
      [20, testMode ? "TEST MODE — writing into the scratch folder." : "Update is ready. Installing."],
      [55, `Extracting to ${dest}`],
      [80, overwrite
        ? "Updating the existing scenario folder in place."
        : "Existing copy would be moved to Content\\Scenarios_Backups (never deleted)."],
      [100, checked.some(Boolean) ? "Copying SharedData into the ticked saves. Update installed." : "Update installed."],
    ] as const);
    if (installed) {
      setInstalledUrl(link);
      setWatchNote("Updated. The next check installs only if this link has a newer file, and only after that file is ready.");
    }
    busyRef.current = false;
    setBusy(false);
  }

  checkRef.current = checkLink;

  useEffect(() => {
    if (!watch || haveZip || schedule === "open") return;
    const ms = schedule === "hour" ? 14000 : 28000;
    const id = window.setInterval(() => {
      void checkRef.current();
    }, ms);
    return () => window.clearInterval(id);
  }, [watch, haveZip, schedule]);

  useEffect(() => {
    if (!watch || haveZip || schedule !== "open") return;
    void checkRef.current();
  }, [watch, haveZip, schedule]);

  function onClose() {
    if (busy) {
      cancelRef.current = true;
      setStatus("Cancelling...");
      return;
    }
    setStatus("Ready.");
    append("Close would exit the window.");
  }

  const tone =
    nameLine.tone === "ok"
      ? "text-ok"
      : nameLine.tone === "bad"
        ? "text-bad"
        : nameLine.tone === "link"
          ? "text-link"
          : "text-ink";

  return (
    <section className="flex min-h-[36rem] flex-col overflow-hidden rounded-win border border-chrome bg-form text-ink shadow-lg">
      <header className="flex h-9 shrink-0 items-center justify-between bg-chrome px-3 text-sm text-chrome-fg">
        <span className="truncate font-medium">
          Scenario Installer 1.0.7{testMode ? "   [TEST MODE]" : ""}
        </span>
        <span className="flex gap-1.5" aria-hidden="true">
          <span className="size-3 rounded-sm bg-btn" />
          <span className="size-3 rounded-sm bg-btn" />
          <span className="size-3 rounded-sm bg-bad" />
        </span>
      </header>

      <div className="min-h-0 flex-1 space-y-2 overflow-y-auto px-3 py-2.5 text-sm leading-snug">
        <h1 className={"text-lg font-bold " + (testMode ? "text-warn" : "text-ink")}>
          {testMode
            ? "Scenario Installer - TEST INSTALL MODE"
            : "Scenario Installer for Empyrion - Galactic Survival"}
        </h1>
        <p className="text-ink">
          Scenario: {scenario || "name from the zip"} — installs it into the path below, then copies its SharedData into the save(s) you pick.
        </p>

        <p>1. Empyrion folder (auto-detects all drives via Steam + scan — Browse or paste if needed):</p>
        <div className="flex gap-2">
          <input
            className="h-8 min-w-0 flex-1 border border-line bg-field px-2"
            list="empyrion-paths"
            value={empyrion}
            onChange={(e) => setEmpyrion(e.target.value)}
            disabled={busy}
            aria-label="Empyrion folder"
          />
          <datalist id="empyrion-paths">
            {EMPYRION.map((p) => (
              <option key={p} value={p} />
            ))}
          </datalist>
          <button
            type="button"
            className="h-8 min-w-24 shrink-0 border border-line bg-btn px-2 hover:bg-btn-hot"
            disabled={busy}
            onClick={() =>
              append(
                "Browse lists every drive (This PC). If it is cancelled, paste the path from Steam → Manage → Browse local files.",
              )
            }
          >
            Browse...
          </button>
        </div>
        {( !pathReady || testMode || customInstall) && (
          <p className={"font-medium " + (!pathReady ? "text-bad" : "text-warn")}>
            {!pathReady
              ? "Enter an install path."
              : testMode
                ? `TEST MODE - will install to: ${dest}  (real scenario untouched)`
                : `Custom path - will install to: ${dest}`}
          </p>
        )}

        <p>2. Download link (paste your own: Google Drive, Dropbox, OneDrive or a direct .zip link) and download folder:</p>
        <div className="flex flex-col gap-2 sm:flex-row">
          <input
            className="h-8 min-w-0 flex-1 border border-line bg-field px-2 disabled:bg-form disabled:text-muted"
            value={url}
            disabled={haveZip || busy}
            onFocus={(e) => {
              const el = e.currentTarget;
              el.select();
              queueMicrotask(() => el.select());
            }}
            onMouseUp={(e) => {
              e.preventDefault();
              e.currentTarget.select();
            }}
            onChange={(e) => {
              const next = e.target.value;
              setUrl(next);
              if (watch && next.trim() !== installedUrl) {
                setWatchNote("Link changed. Nothing installs until a check finishes downloading the new file.");
              }
            }}
          />
          <button
            type="button"
            className="h-8 shrink-0 border border-line bg-btn px-3 hover:bg-btn-hot disabled:opacity-50"
            disabled={haveZip || busy}
            onClick={() => {
              setUrl(DEFAULT_URL);
              append("Download link reset to the default.");
            }}
          >
            Reset to default
          </button>
        </div>
        <div className="space-y-2 border border-line bg-field p-2">
          <label className="flex min-h-8 items-start gap-2">
            <input
              className="mt-1"
              type="checkbox"
              checked={watch}
              disabled={busy || haveZip}
              onChange={(e) => setWatch(e.target.checked)}
            />
            <span>Watch this link. Check it on a schedule, and install only when a newer file is fully ready.</span>
          </label>
          <div className="flex flex-col gap-2 sm:flex-row">
            <select
              className="h-8 min-w-0 flex-1 border border-line bg-field px-2 disabled:bg-form disabled:text-muted"
              value={schedule}
              disabled={!watch || busy || haveZip}
              aria-label="Update check schedule"
              onChange={(e) => setSchedule(e.target.value as "open" | "hour" | "day")}
            >
              <option value="open">Check when the installer opens</option>
              <option value="hour">Check every hour</option>
              <option value="day">Check every day</option>
            </select>
            <button
              type="button"
              className="h-8 shrink-0 border border-line bg-btn px-3 hover:bg-btn-hot disabled:opacity-50"
              disabled={!watch || busy || haveZip}
              onClick={() => void checkLink()}
            >
              Check now
            </button>
          </div>
          <p className={watchNote.startsWith("No newer") || watchNote.startsWith("Up to date") || watchNote.startsWith("Installed") || watchNote.startsWith("Updated") ? "text-ok" : "text-warn"}>
            {watchNote}
          </p>
          <p className="text-muted">
            A different link counts as a new build. The preview runs the hourly check every 14 seconds and the daily check every 28 seconds. The file is downloaded first. Install starts only after that download is complete.
          </p>
        </div>
        <div className="flex gap-2">
          <input
            className="h-8 min-w-0 flex-1 border border-line bg-field px-2 disabled:bg-form disabled:text-muted"
            value={downloadDir}
            disabled={haveZip || busy}
            onChange={(e) => setDownloadDir(e.target.value)}
          />
          <button type="button" className="h-8 min-w-24 border border-line bg-btn px-2 hover:bg-btn-hot disabled:opacity-50" disabled={haveZip || busy}>
            Browse...
          </button>
        </div>
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
          <label className="flex min-h-8 items-center gap-2">
            <input type="checkbox" checked={haveZip} disabled={busy} onChange={(e) => setHaveZip(e.target.checked)} />
            I already have the zip (skip download):
          </label>
          <input
            className="h-8 min-w-0 flex-1 border border-line bg-field px-2 disabled:bg-form disabled:text-muted"
            value={zipPath}
            disabled={!haveZip || busy}
            placeholder="path to .zip"
            onChange={(e) => setZipPath(e.target.value)}
          />
          <button type="button" className="h-8 min-w-24 border border-line bg-btn px-2 hover:bg-btn-hot disabled:opacity-50" disabled={!haveZip || busy}>
            Browse...
          </button>
        </div>
        <p className={"font-semibold " + tone}>{nameLine.text}</p>
        <label className="flex min-h-8 items-start gap-2">
          <input
            className="mt-1"
            type="checkbox"
            checked={extractAfter}
            disabled={busy}
            onChange={(e) => setExtractAfter(e.target.checked)}
          />
          <span>Extract the scenario after download</span>
        </label>

        <p>Install path (other scenario authors set this to their own folder):</p>
        <div className="flex gap-2">
          <input
            className="h-8 min-w-0 flex-1 border border-line bg-field px-2 disabled:bg-form disabled:text-muted"
            value={folderName}
            disabled={customInstall || busy}
            aria-label="Scenario folder name"
            placeholder="NewDawn"
            onChange={(e) => {
              setFolderLocked(true);
              setFolderName(e.target.value);
            }}
          />
          <button
            type="button"
            className="h-8 shrink-0 border border-line bg-btn px-3 hover:bg-btn-hot disabled:opacity-50"
            disabled={customInstall || busy || !detected}
            onClick={() => {
              setFolderLocked(false);
              if (detected) setFolderName(detected);
              append("Install folder reset to the name from the zip.");
            }}
          >
            Use zip name
          </button>
        </div>
        <p className="text-muted">
          {scenario
            ? `Goes in Content\\Scenarios\\${scenario}. Empyrion lists that folder under New Game.`
            : "Ascension-Reborn was cleared because this link is a different scenario. Type the folder name (NewDawn) or leave it blank to use the zip's top folder."}
        </p>
        <label className="flex min-h-8 items-start gap-2">
          <input
            className="mt-1"
            type="checkbox"
            checked={customInstall}
            disabled={busy}
            onChange={(e) => setCustomInstall(e.target.checked)}
          />
          <span>Use a full custom install path instead of Content\Scenarios</span>
        </label>
        {customInstall && (
          <div className="flex gap-2 pl-6">
            <input
              className="h-8 min-w-0 flex-1 border border-line bg-field px-2"
              value={customPath}
              disabled={busy}
              placeholder="D:\Steam\steamapps\common\Empyrion - Galactic Survival\Content\Scenarios\MyScenario"
              aria-label="Custom install path"
              onChange={(e) => setCustomPath(e.target.value)}
            />
            <button type="button" className="h-8 min-w-24 border border-line bg-btn px-2 hover:bg-btn-hot" disabled={busy}>
              Browse...
            </button>
          </div>
        )}

        <p>
          3. Copy SharedData into these saves (tick one or more). Single-player saves are in Saves\Games; servers you joined are in Saves\Cache:
        </p>
        <div className="flex gap-2">
          <ul className="h-24 min-w-0 flex-1 overflow-auto border border-line bg-field">
            {SAVES.map((s, i) => (
              <li key={s.name}>
                <label className="flex min-h-8 items-center gap-2 px-2 hover:bg-btn-hot">
                  <input type="checkbox" checked={checked[i]} disabled={busy} onChange={() => toggleSave(i)} />
                  <span className="truncate">
                    [{s.kind}] {s.name}
                    {s.shared ? "  (has SharedData)" : ""}
                  </span>
                </label>
              </li>
            ))}
          </ul>
          <div className="flex flex-col gap-2">
            <button type="button" className="h-8 min-w-24 border border-line bg-btn px-2 hover:bg-btn-hot" disabled={busy}>
              Add folder...
            </button>
            <button
              type="button"
              className="h-8 min-w-24 border border-line bg-btn px-2 hover:bg-btn-hot"
              disabled={busy}
              onClick={() => append("Refreshed save list.")}
            >
              Refresh
            </button>
          </div>
        </div>
        <p className="text-muted">
          Starting a brand-new game? You can leave all unticked: the game copies SharedData itself when you create a game from the scenario.
        </p>

        <label className="flex min-h-8 items-start gap-2">
          <input className="mt-1" type="checkbox" checked={overwrite} disabled={busy || !extractAfter} onChange={(e) => setOverwrite(e.target.checked)} />
          <span>Update an existing copy of this scenario in place (default: move the old copy to Content\Scenarios_Backups first)</span>
        </label>
        <label className="flex min-h-8 items-start gap-2">
          <input className="mt-1" type="checkbox" checked={deleteZip} disabled={busy || !extractAfter} onChange={(e) => setDeleteZip(e.target.checked)} />
          <span>
            Delete the downloaded zip after a successful install
            {!haveZip && url.trim() === DEFAULT_URL ? " (frees ~19 GB)" : ""}
          </span>
        </label>
        <label className="flex min-h-8 items-start gap-2 font-semibold text-warn">
          <input className="mt-1" type="checkbox" checked={testMode} disabled={busy} onChange={(e) => setTestMode(e.target.checked)} />
          <span>TEST INSTALL - install to a test folder instead (does not touch your real scenario):</span>
        </label>
        <div className="flex gap-2 pl-6">
          <input
            className="h-8 min-w-0 flex-1 border border-line bg-field px-2 disabled:bg-form disabled:text-muted"
            value={testFolder}
            disabled={!testMode || busy}
            onChange={(e) => setTestFolder(e.target.value)}
          />
          <button type="button" className="h-8 min-w-24 border border-line bg-btn px-2 hover:bg-btn-hot disabled:opacity-50" disabled={!testMode || busy}>
            Browse...
          </button>
        </div>

        <p>Log:</p>
        <textarea
          ref={logRef}
          readOnly
          value={log}
          className="h-24 w-full resize-none border border-line bg-field p-2 font-mono text-xs leading-5"
        />
      </div>

      <footer className="shrink-0 space-y-2 border-t border-line bg-form px-3 py-2">
        <div className="h-5 w-full overflow-hidden border border-line bg-bar-track" role="progressbar" aria-valuenow={progress} aria-valuemin={0} aria-valuemax={100}>
          <div className="h-full bg-bar transition-[width] duration-200" style={{ width: `${progress}%` }} />
        </div>
        <p className="truncate text-sm">{status}</p>
        <div className="flex justify-end gap-2">
          <button
            type="button"
            onClick={install}
            disabled={busy || !pathReady || (watch && !haveZip && url.trim() !== installedUrl)}
            className="h-9 min-w-28 border border-line bg-btn px-3 font-semibold hover:bg-btn-hot disabled:opacity-60"
          >
            {testMode ? "Test install" : "Install"}
          </button>
          <button type="button" onClick={onClose} className="h-9 min-w-28 border border-line bg-btn px-3 hover:bg-btn-hot">
            {busy ? "Cancel" : "Close"}
          </button>
        </div>
      </footer>
    </section>
  );
}

function LinuxConsole() {
  const [folderName, setFolderName] = useState("Ascension-Reborn");
  const [customInstall, setCustomInstall] = useState(false);
  const [customPath, setCustomPath] = useState("");
  const [extractAfter, setExtractAfter] = useState(true);
  const [watch, setWatch] = useState(true);
  const scenario = safeFolder(folderName);
  const dest = customInstall
    ? customPath.trim() || "(enter a path)"
    : `/home/you/.steam/steam/steamapps/common/Empyrion - Galactic Survival/Content/Scenarios/${scenario}`;
  const [done, setDone] = useState(false);
  const [ran, setRan] = useState<string[] | null>(null);

  const draft = [
    "$ ./Install-Scenario.sh",
    "Scenario Installer 1.0.7  (console — no window on Linux)",
    "Looking for Steam and Empyrion...",
    "Steam library: /home/you/.steam/steam",
    "Found Game: /home/you/.steam/steam/steamapps/common/Empyrion - Galactic Survival",
    "",
    `Scenario folder: ${scenario}`,
    `Install to: ${dest}`,
    extractAfter ? "Extract after download: yes" : "Extract after download: no (zip only)",
    watch
      ? "Watch link: on. A newer file installs only after it has fully downloaded."
      : "Watch link: off. Install runs only when you answer Y.",
    "SharedData saves: none ticked (a new game copies SharedData itself)",
    "",
    "Proceed with install? [Y/n]",
  ];

  function run() {
    if (done || (customInstall && !customPath.trim())) return;
    setRan([
      ...draft,
      "Y",
      "Checking free space...",
      extractAfter ? `Extracting to ${dest}` : "Extract is off. Zip kept, scenario not extracted.",
      extractAfter
        ? `Done. Start Empyrion > New Game > Scenarios > ${scenario}.`
        : "Done. Zip is in the download folder.",
    ]);
    setDone(true);
  }

  return (
    <section className="overflow-hidden rounded-win border border-chrome bg-chrome text-chrome-fg shadow-lg">
      <header className="flex h-9 items-center px-3 text-sm">Linux — Install-Scenario.sh</header>
      <div className="space-y-2 border-b border-line/30 px-4 py-3 text-sm">
        <label className="block text-chrome-fg/80">Scenario install folder</label>
        <input
          className="h-11 w-full rounded border border-line bg-form px-2 text-ink disabled:opacity-50"
          value={folderName}
          disabled={customInstall || done}
          onChange={(e) => setFolderName(e.target.value)}
        />
        <label className="flex min-h-11 items-center gap-2">
          <input
            type="checkbox"
            checked={extractAfter}
            disabled={done}
            onChange={(e) => setExtractAfter(e.target.checked)}
          />
          Extract the scenario after download
        </label>
        <label className="flex min-h-11 items-center gap-2">
          <input type="checkbox" checked={watch} disabled={done} onChange={(e) => setWatch(e.target.checked)} />
          Watch the link and install only when an update is ready
        </label>
        <label className="flex min-h-11 items-center gap-2">
          <input
            type="checkbox"
            checked={customInstall}
            disabled={done}
            onChange={(e) => setCustomInstall(e.target.checked)}
          />
          Use a full custom install path
        </label>
        {customInstall && (
          <input
            className="h-11 w-full rounded border border-line bg-form px-2 text-ink"
            value={customPath}
            disabled={done}
            placeholder="/path/to/Empyrion/Content/Scenarios/MyScenario"
            onChange={(e) => setCustomPath(e.target.value)}
          />
        )}
      </div>
      <pre className="max-h-[28rem] overflow-auto px-4 py-3 font-mono text-sm leading-6 whitespace-pre-wrap">
        {(ran ?? draft).join("\n")}
        {!done && <span className="ml-1 inline-block h-4 w-2 translate-y-0.5 bg-bar" />}
      </pre>
      <div className="flex justify-end gap-2 border-t border-line/30 px-3 py-2">
        <button
          type="button"
          onClick={run}
          disabled={done || (customInstall && !customPath.trim())}
          className="h-11 min-w-28 rounded bg-form px-3 font-semibold text-ink disabled:opacity-50"
        >
          {done ? "Finished" : "Answer Y"}
        </button>
      </div>
    </section>
  );
}
