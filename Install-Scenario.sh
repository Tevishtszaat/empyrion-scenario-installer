#!/usr/bin/env bash
# Scenario Installer launcher for Linux / macOS
# Requires PowerShell Core (pwsh). Install from https://github.com/PowerShell/PowerShell
cd "$(dirname "$0")"
if ! command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell Core (pwsh) is required."
  echo "Install it from https://github.com/PowerShell/PowerShell (or your package manager)."
  exit 1
fi
exec pwsh -NoProfile -File ./Install-Scenario.ps1 "$@"
