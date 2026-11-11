import { i as __toESM } from "../_runtime.mjs";
import { K as require_react, b as require_jsx_runtime } from "../_libs/@tanstack/react-router+[...].mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/routes-BzrH5jQq.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
var DEFAULT_URL = "https://drive.google.com/file/d/1jtetatjWTRW-JWj1YJkHJP77fXZLd-vh/view?usp=drive_link";
var EMPYRION = ["D:\\Steam\\steamapps\\common\\Empyrion - Galactic Survival", "D:\\SteamLibrary\\steamapps\\common\\Empyrion - Dedicated Server"];
var SAVES = [
	{
		kind: "Games",
		name: "MySurvival",
		shared: true
	},
	{
		kind: "Games",
		name: "TestWorld",
		shared: false
	},
	{
		kind: "Cache",
		name: "Official_203.0.113.8_44100",
		shared: true
	}
];
function stamp() {
	return (/* @__PURE__ */ new Date()).toLocaleTimeString("en-GB", { hour12: false });
}
function Home() {
	const [view, setView] = (0, import_react.useState)("windows");
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("main", {
		className: "min-h-screen bg-desk px-3 py-4 text-chrome-fg sm:px-6 sm:py-6",
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
			className: "mx-auto flex max-w-4xl flex-col gap-3",
			children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "flex flex-wrap items-center justify-between gap-3",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "text-sm text-chrome-fg/80",
					children: "Scenario Installer 1.0.6 — the window players see on Windows. Linux uses the same steps in the console."
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "flex rounded-md border border-line/40 bg-chrome p-0.5 text-sm",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
						type: "button",
						onClick: () => setView("windows"),
						className: "min-h-11 rounded px-3 " + (view === "windows" ? "bg-form font-semibold text-ink" : "text-chrome-fg"),
						children: "Windows window"
					}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
						type: "button",
						onClick: () => setView("linux"),
						className: "min-h-11 rounded px-3 " + (view === "linux" ? "bg-form font-semibold text-ink" : "text-chrome-fg"),
						children: "Linux console"
					})]
				})]
			}), view === "windows" ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(WindowsWindow, {}) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)(LinuxConsole, {})]
		})
	});
}
function safeFolder(name) {
	return name.replace(/[<>:"/\\|?*]/g, "").replace(/\.+$/g, "").trim() || "Scenario";
}
var LINK_NOISE = /* @__PURE__ */ new Set([
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
	"d"
]);
function nameFromUrl(raw) {
	const trimmed = raw.trim();
	if (!trimmed || trimmed === DEFAULT_URL) return trimmed === DEFAULT_URL ? "Ascension-Reborn" : "";
	const bits = [];
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
	const [empyrion, setEmpyrion] = (0, import_react.useState)(EMPYRION[0]);
	const [url, setUrl] = (0, import_react.useState)(DEFAULT_URL);
	const [downloadDir, setDownloadDir] = (0, import_react.useState)("C:\\Users\\You\\Downloads");
	const [haveZip, setHaveZip] = (0, import_react.useState)(false);
	const [zipPath, setZipPath] = (0, import_react.useState)("");
	const [folderName, setFolderName] = (0, import_react.useState)("Ascension-Reborn");
	const [folderLocked, setFolderLocked] = (0, import_react.useState)(false);
	const [customInstall, setCustomInstall] = (0, import_react.useState)(false);
	const [customPath, setCustomPath] = (0, import_react.useState)("");
	const [checked, setChecked] = (0, import_react.useState)(() => SAVES.map(() => false));
	const [overwrite, setOverwrite] = (0, import_react.useState)(false);
	const [deleteZip, setDeleteZip] = (0, import_react.useState)(false);
	const [extractAfter, setExtractAfter] = (0, import_react.useState)(true);
	const [watch, setWatch] = (0, import_react.useState)(true);
	const [schedule, setSchedule] = (0, import_react.useState)("hour");
	const [installedUrl, setInstalledUrl] = (0, import_react.useState)(DEFAULT_URL);
	const [watchNote, setWatchNote] = (0, import_react.useState)("Up to date. The next check follows the schedule.");
	const [testMode, setTestMode] = (0, import_react.useState)(false);
	const [testFolder, setTestFolder] = (0, import_react.useState)("D:\\AR_InstallTest");
	const [log, setLog] = (0, import_react.useState)("");
	const [status, setStatus] = (0, import_react.useState)("Ready.");
	const [progress, setProgress] = (0, import_react.useState)(0);
	const [busy, setBusy] = (0, import_react.useState)(false);
	const cancelRef = (0, import_react.useRef)(false);
	const busyRef = (0, import_react.useRef)(false);
	const logRef = (0, import_react.useRef)(null);
	const checkRef = (0, import_react.useRef)(async () => {});
	const detected = (0, import_react.useMemo)(() => {
		if (haveZip) return zipPath.split(/[/\\]/).pop()?.replace(/\.zip$/i, "").trim() ?? "";
		return nameFromUrl(url);
	}, [
		haveZip,
		zipPath,
		url
	]);
	(0, import_react.useEffect)(() => {
		if (!folderLocked) setFolderName(detected);
	}, [detected, folderLocked]);
	const scenario = folderName.trim() ? safeFolder(folderName) : "";
	const standardDest = `${testMode ? testFolder : empyrion}\\Content\\Scenarios\\${scenario}`;
	const dest = customInstall ? customPath.trim() : standardDest;
	const pathReady = dest.length > 0;
	const nameLine = (0, import_react.useMemo)(() => {
		if (haveZip && !zipPath) return {
			tone: "bad",
			text: "Pick your zip to see the scenario name."
		};
		if (haveZip) return {
			tone: "ok",
			text: `Name from the zip: ${detected || "unknown"}   (you can install it under a different folder below)`
		};
		if (url.trim() === DEFAULT_URL && !folderLocked) return {
			tone: "ink",
			text: "Scenario name: Ascension-Reborn   (default download; confirmed from the zip after downloading)"
		};
		if (scenario) return {
			tone: "ok",
			text: `Scenario name: ${scenario}   (from the link, not the previous scenario)`
		};
		return {
			tone: "link",
			text: "This link has no scenario name in it. Ascension-Reborn was cleared — type the folder, or leave it blank and use the zip's top folder."
		};
	}, [
		haveZip,
		zipPath,
		url,
		detected,
		folderLocked,
		scenario
	]);
	function append(line) {
		setLog((prev) => prev + `${stamp()}  ${line}\n`);
	}
	(0, import_react.useEffect)(() => {
		const lines = [
			"Looking for Steam and Empyrion...",
			"Steam library: D:\\Steam",
			"Steam library: D:\\SteamLibrary",
			"Found Game: " + EMPYRION[0],
			"Found Dedicated Server: " + EMPYRION[1]
		];
		setLog(lines.map((l) => `${stamp()}  ${l}`).join("\n") + "\n");
	}, []);
	(0, import_react.useEffect)(() => {
		if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
	}, [log]);
	function toggleSave(i) {
		setChecked((prev) => prev.map((v, n) => n === i ? !v : v));
	}
	async function runSteps(steps) {
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
		if (await runSteps(extractAfter ? [
			[8, "Checking free space..."],
			[18, haveZip ? "Using the zip you already have." : "Downloading scenario zip (resumable)..."],
			[42, testMode ? "TEST MODE — writing into the scratch folder." : "Download finished."],
			[68, `Extracting to ${dest}`],
			[84, overwrite ? "Updating the existing scenario folder in place." : "Existing copy would be moved to Content\\Scenarios_Backups (never deleted)."],
			[94, checked.some(Boolean) ? "Copying SharedData into the ticked saves." : "No saves ticked — a new game copies SharedData itself."],
			[100, deleteZip ? "Install finished. Downloaded zip removed." : "Install finished."]
		] : [
			[12, "Checking free space..."],
			[55, haveZip ? "Zip already on disk. Extract is off, so it was left as-is." : "Downloading scenario zip (resumable)..."],
			[100, "Download finished. Scenario was not extracted."]
		]) && !haveZip) {
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
		if (!await runSteps([
			[30, "Newer file on the link. Downloading..."],
			[70, "Still downloading. Not installing yet."],
			[100, "Download complete. The update is ready."]
		])) {
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
		if (await runSteps([
			[20, testMode ? "TEST MODE — writing into the scratch folder." : "Update is ready. Installing."],
			[55, `Extracting to ${dest}`],
			[80, overwrite ? "Updating the existing scenario folder in place." : "Existing copy would be moved to Content\\Scenarios_Backups (never deleted)."],
			[100, checked.some(Boolean) ? "Copying SharedData into the ticked saves. Update installed." : "Update installed."]
		])) {
			setInstalledUrl(link);
			setWatchNote("Updated. The next check installs only if this link has a newer file, and only after that file is ready.");
		}
		busyRef.current = false;
		setBusy(false);
	}
	checkRef.current = checkLink;
	(0, import_react.useEffect)(() => {
		if (!watch || haveZip || schedule === "open") return;
		const ms = schedule === "hour" ? 14e3 : 28e3;
		const id = window.setInterval(() => {
			checkRef.current();
		}, ms);
		return () => window.clearInterval(id);
	}, [
		watch,
		haveZip,
		schedule
	]);
	(0, import_react.useEffect)(() => {
		if (!watch || haveZip || schedule !== "open") return;
		checkRef.current();
	}, [
		watch,
		haveZip,
		schedule
	]);
	function onClose() {
		if (busy) {
			cancelRef.current = true;
			setStatus("Cancelling...");
			return;
		}
		setStatus("Ready.");
		append("Close would exit the window.");
	}
	const tone = nameLine.tone === "ok" ? "text-ok" : nameLine.tone === "bad" ? "text-bad" : nameLine.tone === "link" ? "text-link" : "text-ink";
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
		className: "flex min-h-[36rem] flex-col overflow-hidden rounded-win border border-chrome bg-form text-ink shadow-lg",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("header", {
				className: "flex h-9 shrink-0 items-center justify-between bg-chrome px-3 text-sm text-chrome-fg",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
					className: "truncate font-medium",
					children: ["Scenario Installer 1.0.6", testMode ? "   [TEST MODE]" : ""]
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
					className: "flex gap-1.5",
					"aria-hidden": "true",
					children: [
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { className: "size-3 rounded-sm bg-btn" }),
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { className: "size-3 rounded-sm bg-btn" }),
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { className: "size-3 rounded-sm bg-bad" })
					]
				})]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "min-h-0 flex-1 space-y-2 overflow-y-auto px-3 py-2.5 text-sm leading-snug",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h1", {
						className: "text-lg font-bold " + (testMode ? "text-warn" : "text-ink"),
						children: testMode ? "Scenario Installer - TEST INSTALL MODE" : "Scenario Installer for Empyrion - Galactic Survival"
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
						className: "text-ink",
						children: [
							"Scenario: ",
							scenario || "name from the zip",
							" — installs it into the path below, then copies its SharedData into the save(s) you pick."
						]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", { children: "1. Empyrion folder (found automatically - change it if needed):" }),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "flex gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("select", {
							className: "h-8 min-w-0 flex-1 border border-line bg-field px-2",
							value: empyrion,
							onChange: (e) => setEmpyrion(e.target.value),
							disabled: busy,
							children: EMPYRION.map((p) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("option", { children: p }, p))
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
							type: "button",
							className: "h-8 min-w-24 shrink-0 border border-line bg-btn px-2 hover:bg-btn-hot",
							disabled: busy,
							children: "Browse..."
						})]
					}),
					(!pathReady || testMode || customInstall) && /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "font-medium " + (!pathReady ? "text-bad" : "text-warn"),
						children: !pathReady ? "Enter an install path." : testMode ? `TEST MODE - will install to: ${dest}  (real scenario untouched)` : `Custom path - will install to: ${dest}`
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", { children: "2. Download link (paste your own: Google Drive, Dropbox, OneDrive or a direct .zip link) and download folder:" }),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "flex flex-col gap-2 sm:flex-row",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							className: "h-8 min-w-0 flex-1 border border-line bg-field px-2 disabled:bg-form disabled:text-muted",
							value: url,
							disabled: haveZip || busy,
							onFocus: (e) => {
								const el = e.currentTarget;
								el.select();
								queueMicrotask(() => el.select());
							},
							onMouseUp: (e) => {
								e.preventDefault();
								e.currentTarget.select();
							},
							onChange: (e) => {
								const next = e.target.value;
								setUrl(next);
								if (watch && next.trim() !== installedUrl) setWatchNote("Link changed. Nothing installs until a check finishes downloading the new file.");
							}
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
							type: "button",
							className: "h-8 shrink-0 border border-line bg-btn px-3 hover:bg-btn-hot disabled:opacity-50",
							disabled: haveZip || busy,
							onClick: () => {
								setUrl(DEFAULT_URL);
								append("Download link reset to the default.");
							},
							children: "Reset to default"
						})]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "space-y-2 border border-line bg-field p-2",
						children: [
							/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
								className: "flex min-h-8 items-start gap-2",
								children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
									className: "mt-1",
									type: "checkbox",
									checked: watch,
									disabled: busy || haveZip,
									onChange: (e) => setWatch(e.target.checked)
								}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { children: "Watch this link. Check it on a schedule, and install only when a newer file is fully ready." })]
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
								className: "flex flex-col gap-2 sm:flex-row",
								children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("select", {
									className: "h-8 min-w-0 flex-1 border border-line bg-field px-2 disabled:bg-form disabled:text-muted",
									value: schedule,
									disabled: !watch || busy || haveZip,
									"aria-label": "Update check schedule",
									onChange: (e) => setSchedule(e.target.value),
									children: [
										/* @__PURE__ */ (0, import_jsx_runtime.jsx)("option", {
											value: "open",
											children: "Check when the installer opens"
										}),
										/* @__PURE__ */ (0, import_jsx_runtime.jsx)("option", {
											value: "hour",
											children: "Check every hour"
										}),
										/* @__PURE__ */ (0, import_jsx_runtime.jsx)("option", {
											value: "day",
											children: "Check every day"
										})
									]
								}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
									type: "button",
									className: "h-8 shrink-0 border border-line bg-btn px-3 hover:bg-btn-hot disabled:opacity-50",
									disabled: !watch || busy || haveZip,
									onClick: () => void checkLink(),
									children: "Check now"
								})]
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
								className: watchNote.startsWith("No newer") || watchNote.startsWith("Up to date") || watchNote.startsWith("Installed") || watchNote.startsWith("Updated") ? "text-ok" : "text-warn",
								children: watchNote
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
								className: "text-muted",
								children: "A different link counts as a new build. The preview runs the hourly check every 14 seconds and the daily check every 28 seconds. The file is downloaded first. Install starts only after that download is complete."
							})
						]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "flex gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							className: "h-8 min-w-0 flex-1 border border-line bg-field px-2 disabled:bg-form disabled:text-muted",
							value: downloadDir,
							disabled: haveZip || busy,
							onChange: (e) => setDownloadDir(e.target.value)
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
							type: "button",
							className: "h-8 min-w-24 border border-line bg-btn px-2 hover:bg-btn-hot disabled:opacity-50",
							disabled: haveZip || busy,
							children: "Browse..."
						})]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "flex flex-col gap-2 sm:flex-row sm:items-center",
						children: [
							/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
								className: "flex min-h-8 items-center gap-2",
								children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
									type: "checkbox",
									checked: haveZip,
									disabled: busy,
									onChange: (e) => setHaveZip(e.target.checked)
								}), "I already have the zip (skip download):"]
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
								className: "h-8 min-w-0 flex-1 border border-line bg-field px-2 disabled:bg-form disabled:text-muted",
								value: zipPath,
								disabled: !haveZip || busy,
								placeholder: "path to .zip",
								onChange: (e) => setZipPath(e.target.value)
							}),
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
								type: "button",
								className: "h-8 min-w-24 border border-line bg-btn px-2 hover:bg-btn-hot disabled:opacity-50",
								disabled: !haveZip || busy,
								children: "Browse..."
							})
						]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "font-semibold " + tone,
						children: nameLine.text
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
						className: "flex min-h-8 items-start gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							className: "mt-1",
							type: "checkbox",
							checked: extractAfter,
							disabled: busy,
							onChange: (e) => setExtractAfter(e.target.checked)
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { children: "Extract the scenario after download" })]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", { children: "Install path (other scenario authors set this to their own folder):" }),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "flex gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							className: "h-8 min-w-0 flex-1 border border-line bg-field px-2 disabled:bg-form disabled:text-muted",
							value: folderName,
							disabled: customInstall || busy,
							"aria-label": "Scenario folder name",
							placeholder: "NewDawn",
							onChange: (e) => {
								setFolderLocked(true);
								setFolderName(e.target.value);
							}
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
							type: "button",
							className: "h-8 shrink-0 border border-line bg-btn px-3 hover:bg-btn-hot disabled:opacity-50",
							disabled: customInstall || busy || !detected,
							onClick: () => {
								setFolderLocked(false);
								if (detected) setFolderName(detected);
								append("Install folder reset to the name from the zip.");
							},
							children: "Use zip name"
						})]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "text-muted",
						children: scenario ? `Goes in Content\\Scenarios\\${scenario}. Empyrion lists that folder under New Game.` : "Ascension-Reborn was cleared because this link is a different scenario. Type the folder name (NewDawn) or leave it blank to use the zip's top folder."
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
						className: "flex min-h-8 items-start gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							className: "mt-1",
							type: "checkbox",
							checked: customInstall,
							disabled: busy,
							onChange: (e) => setCustomInstall(e.target.checked)
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { children: "Use a full custom install path instead of Content\\Scenarios" })]
					}),
					customInstall && /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "flex gap-2 pl-6",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							className: "h-8 min-w-0 flex-1 border border-line bg-field px-2",
							value: customPath,
							disabled: busy,
							placeholder: "D:\\Steam\\steamapps\\common\\Empyrion - Galactic Survival\\Content\\Scenarios\\MyScenario",
							"aria-label": "Custom install path",
							onChange: (e) => setCustomPath(e.target.value)
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
							type: "button",
							className: "h-8 min-w-24 border border-line bg-btn px-2 hover:bg-btn-hot",
							disabled: busy,
							children: "Browse..."
						})]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", { children: "3. Copy SharedData into these saves (tick one or more). Single-player saves are in Saves\\Games; servers you joined are in Saves\\Cache:" }),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "flex gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("ul", {
							className: "h-24 min-w-0 flex-1 overflow-auto border border-line bg-field",
							children: SAVES.map((s, i) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("li", { children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
								className: "flex min-h-8 items-center gap-2 px-2 hover:bg-btn-hot",
								children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
									type: "checkbox",
									checked: checked[i],
									disabled: busy,
									onChange: () => toggleSave(i)
								}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
									className: "truncate",
									children: [
										"[",
										s.kind,
										"] ",
										s.name,
										s.shared ? "  (has SharedData)" : ""
									]
								})]
							}) }, s.name))
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
							className: "flex flex-col gap-2",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
								type: "button",
								className: "h-8 min-w-24 border border-line bg-btn px-2 hover:bg-btn-hot",
								disabled: busy,
								children: "Add folder..."
							}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
								type: "button",
								className: "h-8 min-w-24 border border-line bg-btn px-2 hover:bg-btn-hot",
								disabled: busy,
								onClick: () => append("Refreshed save list."),
								children: "Refresh"
							})]
						})]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "text-muted",
						children: "Starting a brand-new game? You can leave all unticked: the game copies SharedData itself when you create a game from the scenario."
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
						className: "flex min-h-8 items-start gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							className: "mt-1",
							type: "checkbox",
							checked: overwrite,
							disabled: busy || !extractAfter,
							onChange: (e) => setOverwrite(e.target.checked)
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { children: "Update an existing copy of this scenario in place (default: move the old copy to Content\\Scenarios_Backups first)" })]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
						className: "flex min-h-8 items-start gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							className: "mt-1",
							type: "checkbox",
							checked: deleteZip,
							disabled: busy || !extractAfter,
							onChange: (e) => setDeleteZip(e.target.checked)
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { children: "Delete the downloaded zip after a successful install (frees ~19 GB)" })]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
						className: "flex min-h-8 items-start gap-2 font-semibold text-warn",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							className: "mt-1",
							type: "checkbox",
							checked: testMode,
							disabled: busy,
							onChange: (e) => setTestMode(e.target.checked)
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { children: "TEST INSTALL - install to a test folder instead (does not touch your real scenario):" })]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "flex gap-2 pl-6",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							className: "h-8 min-w-0 flex-1 border border-line bg-field px-2 disabled:bg-form disabled:text-muted",
							value: testFolder,
							disabled: !testMode || busy,
							onChange: (e) => setTestFolder(e.target.value)
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
							type: "button",
							className: "h-8 min-w-24 border border-line bg-btn px-2 hover:bg-btn-hot disabled:opacity-50",
							disabled: !testMode || busy,
							children: "Browse..."
						})]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", { children: "Log:" }),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("textarea", {
						ref: logRef,
						readOnly: true,
						value: log,
						className: "h-24 w-full resize-none border border-line bg-field p-2 font-mono text-xs leading-5"
					})
				]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("footer", {
				className: "shrink-0 space-y-2 border-t border-line bg-form px-3 py-2",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "h-5 w-full overflow-hidden border border-line bg-bar-track",
						role: "progressbar",
						"aria-valuenow": progress,
						"aria-valuemin": 0,
						"aria-valuemax": 100,
						children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
							className: "h-full bg-bar transition-[width] duration-200",
							style: { width: `${progress}%` }
						})
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "truncate text-sm",
						children: status
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "flex justify-end gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
							type: "button",
							onClick: install,
							disabled: busy || !pathReady || watch && !haveZip && url.trim() !== installedUrl,
							className: "h-9 min-w-28 border border-line bg-btn px-3 font-semibold hover:bg-btn-hot disabled:opacity-60",
							children: testMode ? "Test install" : "Install"
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
							type: "button",
							onClick: onClose,
							className: "h-9 min-w-28 border border-line bg-btn px-3 hover:bg-btn-hot",
							children: busy ? "Cancel" : "Close"
						})]
					})
				]
			})
		]
	});
}
function LinuxConsole() {
	const [folderName, setFolderName] = (0, import_react.useState)("Ascension-Reborn");
	const [customInstall, setCustomInstall] = (0, import_react.useState)(false);
	const [customPath, setCustomPath] = (0, import_react.useState)("");
	const [extractAfter, setExtractAfter] = (0, import_react.useState)(true);
	const [watch, setWatch] = (0, import_react.useState)(true);
	const scenario = safeFolder(folderName);
	const dest = customInstall ? customPath.trim() || "(enter a path)" : `/home/you/.steam/steam/steamapps/common/Empyrion - Galactic Survival/Content/Scenarios/${scenario}`;
	const [done, setDone] = (0, import_react.useState)(false);
	const [ran, setRan] = (0, import_react.useState)(null);
	const draft = [
		"$ ./Install-Scenario.sh",
		"Scenario Installer 1.0.6  (console — no window on Linux)",
		"Looking for Steam and Empyrion...",
		"Steam library: /home/you/.steam/steam",
		"Found Game: /home/you/.steam/steam/steamapps/common/Empyrion - Galactic Survival",
		"",
		`Scenario folder: ${scenario}`,
		`Install to: ${dest}`,
		extractAfter ? "Extract after download: yes" : "Extract after download: no (zip only)",
		watch ? "Watch link: on. A newer file installs only after it has fully downloaded." : "Watch link: off. Install runs only when you answer Y.",
		"SharedData saves: none ticked (a new game copies SharedData itself)",
		"",
		"Proceed with install? [Y/n]"
	];
	function run() {
		if (done || customInstall && !customPath.trim()) return;
		setRan([
			...draft,
			"Y",
			"Checking free space...",
			extractAfter ? `Extracting to ${dest}` : "Extract is off. Zip kept, scenario not extracted.",
			extractAfter ? `Done. Start Empyrion > New Game > Scenarios > ${scenario}.` : "Done. Zip is in the download folder."
		]);
		setDone(true);
	}
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
		className: "overflow-hidden rounded-win border border-chrome bg-chrome text-chrome-fg shadow-lg",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("header", {
				className: "flex h-9 items-center px-3 text-sm",
				children: "Linux — Install-Scenario.sh"
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "space-y-2 border-b border-line/30 px-4 py-3 text-sm",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("label", {
						className: "block text-chrome-fg/80",
						children: "Scenario install folder"
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
						className: "h-11 w-full rounded border border-line bg-form px-2 text-ink disabled:opacity-50",
						value: folderName,
						disabled: customInstall || done,
						onChange: (e) => setFolderName(e.target.value)
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
						className: "flex min-h-11 items-center gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							type: "checkbox",
							checked: extractAfter,
							disabled: done,
							onChange: (e) => setExtractAfter(e.target.checked)
						}), "Extract the scenario after download"]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
						className: "flex min-h-11 items-center gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							type: "checkbox",
							checked: watch,
							disabled: done,
							onChange: (e) => setWatch(e.target.checked)
						}), "Watch the link and install only when an update is ready"]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
						className: "flex min-h-11 items-center gap-2",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							type: "checkbox",
							checked: customInstall,
							disabled: done,
							onChange: (e) => setCustomInstall(e.target.checked)
						}), "Use a full custom install path"]
					}),
					customInstall && /* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
						className: "h-11 w-full rounded border border-line bg-form px-2 text-ink",
						value: customPath,
						disabled: done,
						placeholder: "/path/to/Empyrion/Content/Scenarios/MyScenario",
						onChange: (e) => setCustomPath(e.target.value)
					})
				]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("pre", {
				className: "max-h-[28rem] overflow-auto px-4 py-3 font-mono text-sm leading-6 whitespace-pre-wrap",
				children: [(ran ?? draft).join("\n"), !done && /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { className: "ml-1 inline-block h-4 w-2 translate-y-0.5 bg-bar" })]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "flex justify-end gap-2 border-t border-line/30 px-3 py-2",
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
					type: "button",
					onClick: run,
					disabled: done || customInstall && !customPath.trim(),
					className: "h-11 min-w-28 rounded bg-form px-3 font-semibold text-ink disabled:opacity-50",
					children: done ? "Finished" : "Answer Y"
				})
			})
		]
	});
}
//#endregion
export { Home as component };
