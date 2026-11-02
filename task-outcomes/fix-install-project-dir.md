I accidentially installed the toolkit in 
erwin@kakomati threat-intel-toolkit % ./scripts/install-bob.sh install  --scope project --project-dir  /Users/erwin/development/threat-intel-toolkit/.bob so it now lives in 
erwin@kakomati threat-intel-toolkit % ./scripts/install-bob.sh install  --scope project --project-dir  /Users/erwin/development/threat-intel-toolkit/.bob/.bobBoth rollback and uninstall scripts do not function as expected now so please check and fix

Timestamp: Mon Nov  2 16:30:49 CET 2026

## Summary of Investigation and Root Causes

1. **Path Resolution / Project Directory Normalization**:
   - `scripts/install-bob.sh` previously appended `/.bob` unconditionally to whatever path was passed in `--project-dir`.
   - When a user specified `--project-dir /path/to/project/.bob`, it derived `SCOPE_BOB` as `/path/to/project/.bob/.bob`.

2. **Rollback & Uninstall Scope Resolution**:
   - When running `rollback` or `uninstall` without explicit `--scope project` / `--project-dir` flags, the script defaulted to `global` (`$BOB_HOME`, `~/.bob`), failing to locate backups or manifest in the project repository.
   - Even when `--project-dir` was supplied, nested `.bob/.bob` paths were not cleaned up because `restore_backup` and `cmd_uninstall` left directory structures and backup folders intact.
   - In `cmd_uninstall`, creating a new backup in `$BACKUP_ROOT` inside the target directory recreated `.bob/.bob/backups/...`, preventing the folder from ever being removed.

## Changes Made

1. **Normalized `--project-dir` resolution in `scripts/install-bob.sh`**:
   - If `--project-dir` points to a `.bob` folder (e.g. `/path/to/project/.bob`), `SCOPE_BOB` is normalized to `/path/to/project/.bob` rather than appending a second `/.bob`.
   - If `--project-dir` points to `/path/to/project`, `SCOPE_BOB` is `/path/to/project/.bob`.
   - If `--scope project` is used inside a repository checkout without `--project-dir`, `TI_PROJECT_DIR` defaults to `$REPO_DIR`.

2. **Auto-detection of project scope**:
   - When running `status`, `check`, `rollback`, or `uninstall` inside a project checkout without explicit `--scope` flags, the script checks if a manifest or backup exists in `$REPO_DIR/.bob` or an existing `$REPO_DIR/.bob/.bob`, automatically selecting the correct scope and target directory.

3. **Cleanup of Accidental Nested Directories in Rollback and Uninstall**:
   - Added `cleanup_scope()` to remove empty skill directories and automatically clean up accidental nested `.bob/.bob` folders.
   - Configured `cmd_uninstall` to store uninstall backups in the parent directory when removing an accidental nested `.bob/.bob`.
   - Updated `restore_backup` security filter to permit restoring paths from nested `.bob/.bob` backups.

4. **Executed Rollback and Cleanup**:
   - Successfully rolled back the accidental `.bob/.bob` installation.
   - Cleaned up the nested `.bob/.bob` directory while preserving project settings such as `.bob/mcp.json`.
