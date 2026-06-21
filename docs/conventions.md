# Project conventions (paste into Claude Project custom instructions)

This project maintains the Windows Setup Toolkit: a config-driven PowerShell
provisioning tool launched via `irm <url>/launcher.ps1 | iex`.

## Target environment
- Machines are freshly-imaged **Windows 11 IoT Enterprise LTSC**. These ship
  **without the Microsoft Store**, so **winget is not present** out of the box.
- The launcher bootstraps winget on demand (`Install-Winget`) via the
  `Microsoft.WinGet.Client` module + `Repair-WinGetPackageManager`. Do **not**
  hardcode VCLibs / UI.Xaml / msixbundle download URLs — Microsoft deprecated the
  old VCLibs link, so pinned-URL bootstrap scripts now fail silently.
- The bootstrap needs internet + admin and can still fail on a stripped image, so
  any must-have app should also carry a direct-download `fallback` (see below).

## Architecture rules
- The launcher stays thin. New apps/tweaks are added to `config/apps.json`, never
  by hardcoding into `launcher.ps1`.
- App installs prefer winget; use Chocolatey only when winget lacks the package;
  use a `download` item for a direct vendor installer; use a `script` item for
  anything that isn't a package install; use an `irm` item to launch an external
  `irm <url> | iex` tool (e.g. Chris Titus WinUtil).
- Each manifest item has: id, name, description, category, method
  (winget|choco|download|script|irm), payload, default, and an optional `fallback`.

## Manifest item schema
- `method: winget`   — `payload` is the winget ID.
- `method: choco`    — `payload` is the Chocolatey package name.
- `method: script`   — `payload` is a filename in `scripts/`.
- `method: download` — direct vendor installer. Fields: `url`; optional `file`
  (output filename, which also decides `.msi` vs `.exe` handling); optional `args`
  (silent switches — for `.msi`, `msiexec /i <file>` is prepended automatically).
- `method: irm`      — `payload` is a URL run as `irm <url> | iex`. Runs third-party
  remote code, so the launcher prompts for confirmation first; only point it at
  trusted sources.
- `fallback` (optional) — a nested spec with its own `method` (+ fields) that runs
  if the primary is unavailable or fails. Typical pattern: a winget primary with a
  `download` fallback, so the app still installs on a box where winget won't bootstrap.
- `detect` (optional) — substring matched against installed programs' registry
  DisplayName to flag an item as already installed (and show its version) in the menu.
  Defaults to the item `name`; set it where the registry name differs (e.g. VS Code's
  DisplayName is "Microsoft Visual Studio Code"). MSIX/Store apps aren't detected this way.
- `check` (optional, mainly for tweaks) — a condition (or array of conditions, all of
  which must hold) describing when the tweak is already applied, so the menu can mark it
  before/after running. Types: `registry` (`path`, `name`, `value`) and `powerplan`
  (`guid` of the active scheme).

## PowerShell style
- Target Windows PowerShell 5.1 (the launcher must run on a fresh box before
  PowerShell 7 is installed).
- Use approved verbs and PascalCase function names (e.g. Set-ExplorerTweaks).
- Wrap each item's execution in try/catch; warn and continue rather than abort the
  whole run on one failure.
- Per-user tweaks go under HKCU; machine-wide tweaks under HKLM and require admin —
  note the requirement in the script header.

## When asked to add an app
1. Confirm the winget ID (`winget search`).
2. Append the manifest entry with `method: winget`.
3. For a must-have app, add a `download` fallback — confirm the vendor's silent-install
   switches and a stable installer URL (pin a version if there's no evergreen link).
4. Default to `default: false` unless it's a near-universal install.
