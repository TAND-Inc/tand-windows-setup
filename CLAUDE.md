# TAND Windows Setup Toolkit — Claude Code guide

A config-driven PowerShell provisioning tool for new Windows machines. A single
PowerShell one-liner downloads `launcher.ps1`, which renders a WPF menu from a JSON
manifest and installs the selected apps / runs the selected tweaks.

Run target:
`irm https://raw.githubusercontent.com/TAND-Inc/tand-windows-setup/main/launcher.ps1 | iex`

## Target environment (read this first)
- Machines are freshly-imaged **Windows 11 IoT Enterprise LTSC**. These ship
  **without the Microsoft Store**, so **winget is absent on a clean box**.
- The launcher bootstraps winget on demand (`Install-Winget`) via the
  `Microsoft.WinGet.Client` module + `Repair-WinGetPackageManager`.
- **Never hardcode VCLibs / UI.Xaml / msixbundle URLs** — Microsoft retired the old
  VCLibs link, so pinned-dependency bootstrap scripts fail *silently*.
- Because the bootstrap can fail on a stripped image, must-have apps carry a
  direct-download **fallback** so they install either way.

## Repo layout
- `launcher.ps1` — the irm target. Stays thin: TLS 1.2 → admin check → fetch manifest
  → WPF menu (auto-checks winget, marks installed/applied items) → run loop that
  reopens after each batch.
- `config/apps.json` — the manifest. **This is where apps/tweaks are added.**
- `scripts/*.ps1` — tweak/utility scripts referenced by `script`-method items.
- `docs/conventions.md` — mirror of these conventions (used as the Claude.ai Project
  instructions). Keep it in sync with this file.
- `README.md`, `LICENSE` (MIT, TAND Inc.), `.gitignore`.

## Architecture rules
- The launcher stays thin. New apps/tweaks are **manifest edits**, never hardcoded
  into `launcher.ps1`. Adding a thing = append an object to `items` in
  `config/apps.json` (and drop a `.ps1` in `scripts/` for a `script` item).
- Prefer winget; use a `download` item for a direct vendor installer; `script` for
  anything that isn't a package install; `irm` to launch an external `irm|iex` tool;
  `choco` only when winget lacks a package.

## Manifest item schema
Common fields: `id`, `name`, `description`, `category`, `method`, `payload` (where
applicable), `default`.

Methods:
- `winget`   — `payload` = winget ID.
- `choco`    — `payload` = Chocolatey package name.
- `script`   — `payload` = filename in `scripts/`.
- `download` — direct installer. Fields: `url`; optional `file` (output name, which
  also decides `.msi` vs `.exe` handling); optional `args` (silent switches — for
  `.msi`, `msiexec /i <file>` is prepended automatically).
- `irm`      — `payload` = URL run as `irm <url> | iex`. Runs third-party remote code;
  the launcher prompts for confirmation first. Only point at trusted sources.

Optional:
- `fallback` — a nested spec (its own method + fields) run if the primary is
  unavailable or fails. Common pattern: winget primary + `download` fallback.
- `detect` — substring matched against installed programs' registry DisplayName to
  mark an item installed (with version). Defaults to `name`; set it where the
  registry name differs (VS Code → "Visual Studio Code"; Git → "Git version").
  MSIX/Store apps (e.g. Windows Terminal) are NOT registry-detectable.
- `check` — for tweaks: a condition or array of conditions (all must hold) describing
  the applied state, so the menu marks it before/after running. Types: `registry`
  (`path`/`name`/`value`) and `powerplan` (`guid`).

## PowerShell style
- Target **Windows PowerShell 5.1** (must run on a fresh box before PS7 exists).
- Approved verbs, PascalCase function names (e.g. `Set-ExplorerTweaks`).
- Wrap each item's execution in try/catch; warn and continue, never abort the run.
- Per-user tweaks → HKCU; machine-wide → HKLM (needs admin; note it in the header).
- Keep the existing catppuccin-style WPF palette in the launcher.

## Gotchas learned the hard way
- Angle brackets (`<you>`) left in a raw URL → GitHub's CDN returns **400**, not 404.
  A 400 means a malformed URL; a 404 means missing/private.
- `$BaseUrl` is baked into the launcher. If you pin the one-liner to a git tag, point
  `$BaseUrl` at that same tag in that commit for a truly frozen snapshot.
- Pinned fallback versions are intentional snapshots — winget keeps primaries
  current; fallback URLs only need to resolve.
- The repo must stay **public**, or the `irm|iex` one-liner can't fetch (raw → 404).

## Common tasks
Slash commands encode the routine workflows:
- `/add-app <name>` — add a winget app (+ download fallback), confirming the winget ID
  and the vendor's silent-install switches.
- `/add-tweak <description>` — add a `scripts/*.ps1` tweak plus its manifest entry and `check`.
- `/cut-release <version>` — point `$BaseUrl` at the tag, commit, tag, push.

When adding an app manually: confirm the winget ID, default to `default: false`
unless near-universal, and add a `download` fallback for must-haves.

## Working agreement
- After editing `config/apps.json`, validate it (it must be valid JSON).
- This repo runs on Windows, so you can actually run and lint the PowerShell here.
- Commit with clear messages and push to `origin main` (TAND-Inc/tand-windows-setup).
  **Ask before tagging a release** or pushing.
