---
description: Add a system tweak (a scripts/*.ps1 file plus its manifest entry and check)
allowed-tools: Read, Edit, Write, Bash
---
Add a tweak that does: "$ARGUMENTS".

Steps:
1. Create `scripts/Set-<Name>.ps1` (approved verb, PascalCase). Target Windows
   PowerShell 5.1, wrap the work so a single failure warns rather than aborts, and
   note in the header whether it needs admin (HKLM) or is per-user (HKCU).
2. Add a `script`-method item to `config/apps.json` in the `Tweaks` category.
3. Add a `check` so the menu can detect when it's already applied:
   - `registry` → `{ "type": "registry", "path": "...", "name": "...", "value": N }`
     (use an array of these if the tweak sets several values; all must match).
   - `powerplan` → `{ "type": "powerplan", "guid": "..." }`.
4. Default to `default: false` unless it's a safe near-universal default.
5. Validate the JSON and summarize.
