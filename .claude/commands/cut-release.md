---
description: Cut a pinned release — point $BaseUrl at a tag, commit, tag, push
allowed-tools: Read, Edit, Bash
---
Cut release version "$ARGUMENTS" (e.g. v1.0.0).

Steps:
1. In `launcher.ps1`, set `$BaseUrl` to
   `https://raw.githubusercontent.com/TAND-Inc/tand-windows-setup/$ARGUMENTS`
   so the tagged launcher fetches its manifest and scripts from the same immutable
   tag. Also update the `irm ... | iex` examples in the launcher's help block and in
   `README.md` to that tag.
2. Validate `config/apps.json`.
3. Commit with the message "Release $ARGUMENTS".
4. Create an annotated tag `$ARGUMENTS` on that commit.
5. **Confirm with me** before running `git push` and `git push origin $ARGUMENTS`.

Note: a 400 from raw.githubusercontent.com means a malformed URL — verify the base
resolves in a browser before pushing. After release, remember to set `$BaseUrl` back
to `.../main` on the main branch for ongoing development.
