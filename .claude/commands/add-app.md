---
description: Add an application to the manifest (winget primary + download fallback)
allowed-tools: Read, Edit, WebFetch, WebSearch, Bash
---
Add the application "$ARGUMENTS" to `config/apps.json`.

Steps:
1. Confirm the winget ID (search the web / winget docs if unsure) and use it as the
   primary `winget` method.
2. Pick a category matching the existing ones (Browsers, Utilities, Dev / IT, Comms,
   Productivity, Remote, System), or propose a new one.
3. Add a `download` **fallback**: find the vendor's official installer URL and silent
   switches. Prefer an evergreen URL; if only versioned URLs exist, pin a known-good
   version (GitHub/vendor release assets are permanent). `.msi` → `/qn /norestart`;
   Inno → `/VERYSILENT /NORESTART`; NSIS → `/S`.
4. Set `default: false` unless it's a near-universal install.
5. Add a `detect` string only if the registry DisplayName differs from `name`.
6. Validate the JSON, then summarize what you added and why.

Do not hardcode anything into `launcher.ps1` — this is a manifest edit only. If the
app isn't in winget, make the `download` the primary method instead of the fallback.
