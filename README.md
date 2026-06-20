# Windows Setup Toolkit

A config-driven PowerShell toolkit for provisioning new Windows machines. Run a
single one-liner, pick apps and tweaks from a WPF menu, and let it install/run
the selection.

```powershell
irm https://raw.githubusercontent.com/<you>/windows-setup-toolkit/main/launcher.ps1 | iex
```

## How it works

The launcher is intentionally thin. It does a handful of things: enforce TLS 1.2,
check for admin, download the manifest, render a WPF menu from it, bootstrap winget
if the selection needs it, and execute the selected items. Everything you'd actually
want to change lives in data, not code.

```
windows-setup-toolkit/
├── launcher.ps1            # the irm target (rarely edited)
├── config/
│   └── apps.json           # the manifest — THIS is where you add things
├── scripts/
│   ├── Set-PowerPlanHigh.ps1
│   ├── Set-ExplorerTweaks.ps1
│   └── Disable-Telemetry.ps1
└── docs/
    └── conventions.md      # paste into your Claude Project instructions
```

## Target environment & winget

This is built for freshly-imaged **Windows 11 IoT Enterprise LTSC**, which ships
**without the Microsoft Store** — so `winget` is **not present** on a clean box. The
launcher bootstraps it on demand (`Install-Winget`) using the `Microsoft.WinGet.Client`
PowerShell module and `Repair-WinGetPackageManager`, which pulls the right
dependencies itself (don't hardcode VCLibs/UI.Xaml URLs — the old ones are dead).

Because that bootstrap needs internet + admin and can still fail on a stripped image,
must-have apps carry a direct-download **fallback** so they install either way.

## Adding things

Adding an app or tweak is a manifest edit, not a code change. Append an object
to `items` in `config/apps.json`:

| field       | meaning                                                              |
|-------------|----------------------------------------------------------------------|
| id          | unique short key                                                     |
| name        | label shown in the menu                                              |
| description | tooltip text                                                         |
| category    | groups items under a heading in the UI                               |
| method      | `winget`, `choco`, `download`, or `script`                           |
| payload     | winget ID, choco package, or script filename (not used by `download`)|
| default     | `true` to pre-check the box                                          |
| fallback    | *(optional)* nested spec run if the primary fails — e.g. winget → download |

For a `winget` item, find the ID with `winget search "<app>"`. For a `script` item,
drop the `.ps1` file in `scripts/` and set `payload` to its filename.

### The `download` method

A direct vendor installer, used as a primary method or (more often) as a `fallback`:

| field | meaning                                                                     |
|-------|-----------------------------------------------------------------------------|
| url   | installer URL (redirects are followed)                                      |
| file  | *(optional)* output filename — also decides `.msi` vs `.exe` handling       |
| args  | *(optional)* silent switches; for `.msi`, `msiexec /i <file>` is prepended  |

Example — winget primary with a direct-download fallback:

```json
{
  "id": "chrome", "name": "Google Chrome", "description": "Web browser",
  "category": "Browsers", "method": "winget", "payload": "Google.Chrome",
  "default": true,
  "fallback": {
    "method": "download",
    "url": "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi",
    "file": "googlechromestandaloneenterprise64.msi",
    "args": "/qn /norestart"
  }
}
```

## Publishing

1. Create a GitHub repo and push this folder to it. Use a **public** repo — private
   repos require a token in the URL, which breaks the clean one-liner.
2. Set `$BaseUrl` at the top of `launcher.ps1` to your repo's raw base
   (`https://raw.githubusercontent.com/<you>/<repo>/main`).
3. Optionally point a short/custom URL at the raw `launcher.ps1` so the command
   stays memorable and you can re-point it without changing what people type.

**Security note:** `irm | iex` is the same pattern malware droppers use, so EDR/AV
may flag it. For production rollout, pin to a git **tag** rather than `main` so a
bad commit can't silently propagate, and review the launcher before wide use. Note
that `raw.githubusercontent.com` caches branch URLs briefly, so a push to `main`
can take a few minutes to propagate — pinning to a tag/SHA also avoids that surprise.

## Claude Project setup

This repo is meant to live in a dedicated Claude Project so context carries across
sessions.

1. In Claude's left sidebar, click **Projects → Create project**. Name it
   something like *Windows Setup Toolkit*.
2. Add **project knowledge**: upload `launcher.ps1`, `config/apps.json`, and one or
   two example scripts so Claude always has the current structure and the manifest
   schema on hand.
3. Add **custom instructions**: paste the contents of `docs/conventions.md` so every
   chat follows the same PowerShell style and manifest conventions without you
   re-explaining them.
