#!/usr/bin/env bash
# Threat Intel Toolkit - IBM Bob installer (works in bash and zsh, Linux and macOS).
#
# Installs the two skills and the "Threat Intel Analyst" mode into IBM Bob, from either the
# fork or the original (upstream) repository, with backup, rollback and switch support.
#
# Usage:    scripts/install-bob.sh <command> [options]      (run with "help" for details)
# Settings: read from ".env" (see .env.example); real environment variables win.
#
# Change log:
#   Mon Nov  2 15:58:00 CET 2026  Initial version (install/update/switch/status/check/rollback/uninstall).
#   Mon Nov  2 16:27:10 CET 2026  Fix project directory normalization, auto-detect project scope, and cleanup nested .bob directories in rollback/uninstall.

set -eu
(set -o pipefail) 2> /dev/null && set -o pipefail

SELF=$0
SCRIPT_DIR=""
REPO_DIR=""
if [ -f "$SELF" ]; then
  SCRIPT_DIR=$(cd "$(dirname "$SELF")" && pwd)
  if [ -f "$SCRIPT_DIR/../.env.example" ]; then REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd); fi
fi

SKILL_NAMES="threat-intel-lookup exploit-availability-check"
MARKER="threat-intel-toolkit (managed"
ASSUME_YES=false
DRY_RUN=false
FROM_LOCAL=false
LOG_FILE=""
TMP_ROOT=""
BACKUP_DIR=""
BK_N=0
COMMITTED=false
HELPER=""
SRC=""
COMMIT=""

# ---------------------------------------------------------------- logging
# Numeric level for filtering. Mon Nov  2 15:58:00 CET 2026
level_num() {
  case $1 in DEBUG) echo 0 ;; INFO) echo 1 ;; WARN) echo 2 ;; ERROR) echo 3 ;; *) echo 1 ;; esac
}

# Print to the screen (filtered by LOG_LEVEL) and append a JSON line to the log file. Mon Nov  2 15:58:00 CET 2026
log() {
  lvl=$1; shift
  msg=$*
  if [ "$(level_num "$lvl")" -ge "$(level_num "${LOG_LEVEL:-INFO}")" ]; then
    case $lvl in
      WARN | ERROR) printf '[%s] %s\n' "$lvl" "$msg" >&2 ;;
      *) printf '[%s] %s\n' "$lvl" "$msg" ;;
    esac
  fi
  if [ -n "$LOG_FILE" ]; then
    esc=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"ts":"%s","level":"%s","msg":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$lvl" "$esc" >> "$LOG_FILE" 2> /dev/null || true
  fi
}

# Log an error and stop. Mon Nov  2 15:58:00 CET 2026
die() { log ERROR "$*"; exit 1; }

# ---------------------------------------------------------------- configuration
# Read allow-listed KEY=VALUE lines from a .env file (never executes it); real env wins. Mon Nov  2 15:58:00 CET 2026
load_env() {
  f=$1
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in '' | '#'*) continue ;; esac
    key=${line%%=*}
    val=${line#*=}
    case $key in
      TI_SOURCE | TI_FORK_URL | TI_UPSTREAM_URL | TI_CUSTOM_URL | TI_REF | TI_SCOPE | \
        TI_PROJECT_DIR | TI_BUILD_CACHE | BOB_HOME | LOG_LEVEL | TI_ALLOW_LOCAL_SOURCE) ;;
      *) continue ;;
    esac
    val=${val#\"}; val=${val%\"}; val=${val#\'}; val=${val%\'}
    if ! printenv "$key" > /dev/null 2>&1 && [ -n "$val" ]; then export "$key=$val"; fi
  done < "$f"
}

# Write or replace KEY=VALUE in the .env of the local checkout. Mon Nov  2 16:27:10 CET 2026
persist_env() {
  key=$1; val=$2
  if [ -z "$REPO_DIR" ]; then log WARN "No local checkout: '$key' applies to this run only."; return 0; fi
  envf="$REPO_DIR/.env"
  [ -f "$envf" ] || cp "$REPO_DIR/.env.example" "$envf"
  tmp="$envf.tmp.$$"
  grep -v "^${key}=" "$envf" > "$tmp" || true
  if [ -n "$val" ]; then
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
  fi
  mv "$tmp" "$envf"
}

# Apply defaults and derive all paths. Mon Nov  2 16:27:10 CET 2026
resolve_config() {
  : "${TI_SOURCE:=fork}"
  : "${TI_FORK_URL:=https://github.com/ncee-dp-tech-sme/threat-intel-toolkit.git}"
  : "${TI_UPSTREAM_URL:=https://github.com/kevinmhorvath/threat-intel-toolkit.git}"
  : "${TI_CUSTOM_URL:=}"
  : "${TI_REF:=main}"
  : "${TI_SCOPE:=global}"
  : "${TI_PROJECT_DIR:=}"
  : "${TI_BUILD_CACHE:=true}"
  : "${TI_ALLOW_LOCAL_SOURCE:=false}"
  : "${BOB_HOME:=$HOME/.bob}"
  : "${LOG_LEVEL:=INFO}"
  case $LOG_LEVEL in DEBUG | INFO | WARN | ERROR) ;; *) LOG_LEVEL=INFO ;; esac

  if [ -z "$CLI_SCOPE" ] && [ -n "$REPO_DIR" ] && [ "$TI_SCOPE" = global ]; then
    if [ -f "$REPO_DIR/.bob/threat-intel-toolkit.manifest" ] || [ -d "$REPO_DIR/.bob/backups/threat-intel-toolkit" ]; then
      TI_SCOPE=project
      TI_PROJECT_DIR=$REPO_DIR
    elif [ -f "$REPO_DIR/.bob/.bob/threat-intel-toolkit.manifest" ] || [ -d "$REPO_DIR/.bob/.bob/backups/threat-intel-toolkit" ]; then
      TI_SCOPE=project
      TI_PROJECT_DIR=$REPO_DIR/.bob/.bob
    fi
  fi

  case $TI_SCOPE in
    global) SCOPE_BOB=$BOB_HOME ;;
    project)
      if [ -z "$TI_PROJECT_DIR" ] && [ -n "$REPO_DIR" ]; then TI_PROJECT_DIR=$REPO_DIR; fi
      [ -n "$TI_PROJECT_DIR" ] || die "Project scope needs a folder: add --project-dir /path/to/your/project"
      [ -d "$TI_PROJECT_DIR" ] || die "Project folder not found: $TI_PROJECT_DIR"
      DIR_ABS=$(cd "$TI_PROJECT_DIR" && pwd)
      if [ -f "$DIR_ABS/threat-intel-toolkit.manifest" ] && [ "$(basename "$DIR_ABS")" = ".bob" ] && [ "$(basename "$(dirname "$DIR_ABS")")" = ".bob" ]; then
        SCOPE_BOB=$DIR_ABS
      elif [ "$(basename "$DIR_ABS")" = ".bob" ]; then
        SCOPE_BOB=$DIR_ABS
        TI_PROJECT_DIR=$(dirname "$DIR_ABS")
      else
        SCOPE_BOB=$DIR_ABS/.bob
        TI_PROJECT_DIR=$DIR_ABS
      fi
      ;;
    *) die "TI_SCOPE must be 'global' or 'project' (got '$TI_SCOPE')" ;;
  esac
  SKILLS_DIR=$SCOPE_BOB/skills
  MANIFEST=$SCOPE_BOB/threat-intel-toolkit.manifest
  BACKUP_ROOT=$SCOPE_BOB/backups/threat-intel-toolkit
  ALWAYS_FILE=$BOB_HOME/threat-intel-toolkit.always-allow

  if mkdir -p "$BOB_HOME/logs" 2> /dev/null; then
    LOG_FILE=$BOB_HOME/logs/threat-intel-install.log
    ( umask 077; : >> "$LOG_FILE" ) 2> /dev/null || LOG_FILE=""
  fi
}

# Custom-mode files used by the selected scope (Bob IDE and Bob Shell locations). Mon Nov  2 15:58:00 CET 2026
mode_files() {
  if [ "$TI_SCOPE" = global ]; then
    printf '%s\n' "$BOB_HOME/settings/custom_modes.yaml" "$BOB_HOME/custom_modes.yaml"
  else
    printf '%s\n' "$SCOPE_BOB/custom_modes.yaml"
  fi
}

# Allow only plain https URLs without credentials; allow only safe branch/tag names. Mon Nov  2 15:58:00 CET 2026
validate_url() {
  printf '%s' "$1" | grep -Eq '^https://[A-Za-z0-9.-]+(:[0-9]+)?/[A-Za-z0-9._~/-]+$' \
    || die "Not an allowed repository URL (must be https://host/owner/repo[.git], no passwords inside): $1"
}
validate_ref() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._/-]+$' || die "Invalid branch/tag name: $1"
  case $1 in -*) die "Invalid branch/tag name: $1" ;; esac
}

# Work out SOURCE_NAME / SOURCE_URL from the settings. Mon Nov  2 15:58:00 CET 2026
resolve_source() {
  if [ "$FROM_LOCAL" = true ]; then
    [ -n "$REPO_DIR" ] || die "--from-local must be run from inside a downloaded copy of the toolkit."
    SOURCE_NAME=local; SOURCE_URL=$REPO_DIR; return 0
  fi
  case $TI_SOURCE in
    fork) SOURCE_URL=$TI_FORK_URL ;;
    upstream) SOURCE_URL=$TI_UPSTREAM_URL ;;
    custom) SOURCE_URL=$TI_CUSTOM_URL ;;
    *) die "TI_SOURCE must be fork, upstream or custom (got '$TI_SOURCE')" ;;
  esac
  SOURCE_NAME=$TI_SOURCE
  [ -n "$SOURCE_URL" ] || die "No repository URL is set for source '$SOURCE_NAME'."
  if [ "$TI_ALLOW_LOCAL_SOURCE" = true ] && [ -d "$SOURCE_URL/.git" ]; then :; else validate_url "$SOURCE_URL"; fi
  validate_ref "$TI_REF"
}

# ---------------------------------------------------------------- prerequisites
# Verify git (unless --from-local) and Python 3.8+. Mon Nov  2 15:58:00 CET 2026
check_prereqs() {
  ok=true
  if [ "$FROM_LOCAL" != true ]; then
    if command -v git > /dev/null 2>&1; then log INFO "OK   git: $(git --version)"
    else log ERROR "MISSING git. Get it from https://git-scm.com/downloads (macOS: run 'xcode-select --install')."; ok=false; fi
  fi
  if command -v python3 > /dev/null 2>&1 \
    && python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2> /dev/null; then
    log INFO "OK   python3: $(python3 --version 2>&1)"
  else
    log ERROR "MISSING Python 3.8 or newer. Get it from https://www.python.org/downloads/"; ok=false
  fi
  if command -v bob > /dev/null 2>&1; then log INFO "OK   IBM Bob command found"
  elif [ -d "$BOB_HOME" ]; then log INFO "OK   IBM Bob settings folder found ($BOB_HOME)"
  else log WARN "IBM Bob not detected. Files are still installed to $SCOPE_BOB and work once Bob is installed."; fi
  [ "$ok" = true ] || die "Prerequisites missing - fix the items above and run again."
}

# ---------------------------------------------------------------- safety helpers
# Ask the user to confirm; "always" is remembered on disk. Mon Nov  2 15:58:00 CET 2026
confirm() {
  [ "$ASSUME_YES" = true ] && return 0
  if [ -f "$ALWAYS_FILE" ]; then log INFO "Auto-approved (always-allow set in $ALWAYS_FILE)"; return 0; fi
  ans=""
  printf 'Proceed? [y]es / [n]o / [a]lways allow: '
  if ! { read -r ans < /dev/tty; } 2> /dev/null; then
    die "No terminal available to ask for confirmation. Re-run with --yes."
  fi
  case $ans in
    y | Y | yes) return 0 ;;
    a | A | always)
      mkdir -p "$BOB_HOME" && : > "$ALWAYS_FILE" && chmod 600 "$ALWAYS_FILE"
      log INFO "Saved. Delete $ALWAYS_FILE to be asked again."; return 0 ;;
    *) log INFO "Cancelled. Nothing was changed."; exit 0 ;;
  esac
}

# Copy a path into the current backup (or note that it did not exist). Mon Nov  2 15:58:00 CET 2026
backup_path() {
  p=$1
  BK_N=$((BK_N + 1))
  if [ -e "$p" ]; then
    mkdir -p "$BACKUP_DIR/items"
    cp -Rp "$p" "$BACKUP_DIR/items/$BK_N"
    printf '%s|%s\n' "$BK_N" "$p" >> "$BACKUP_DIR/index"
  else
    printf '%s|%s\n' "-" "$p" >> "$BACKUP_DIR/index"
  fi
}

# Put every path recorded in a backup back as it was. Mon Nov  2 16:27:10 CET 2026
restore_backup() {
  d=$1
  [ -f "$d/index" ] || return 0
  while IFS='|' read -r id p; do
    case $p in "$BOB_HOME"/* | "$SCOPE_BOB"/* | *"/.bob/.bob/"*) ;; *) log WARN "Skipping unexpected path in backup: $p"; continue ;; esac
    rm -rf "$p"
    if [ "$id" != "-" ]; then
      mkdir -p "$(dirname "$p")"
      cp -Rp "$d/items/$id" "$p"
    fi
  done < "$d/index"
}

# Clean up empty skills folder or accidental nested .bob/.bob folders. Mon Nov  2 16:27:10 CET 2026
cleanup_scope() {
  if [ -d "$SKILLS_DIR" ]; then
    rmdir "$SKILLS_DIR" 2> /dev/null || true
  fi
  case $SCOPE_BOB in
    */.bob/.bob)
      rm -rf "$SCOPE_BOB"
      log INFO "Cleaned up accidental nested folder: $SCOPE_BOB"
      ;;
    *)
      rmdir "$SCOPE_BOB" 2> /dev/null || true
      ;;
  esac
}

# Remove temp files; undo a half-finished change. Mon Nov  2 15:58:00 CET 2026
on_exit() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$BACKUP_DIR" ] && [ "$COMMITTED" != true ] && [ -f "$BACKUP_DIR/index" ]; then
    log WARN "Failed - restoring the previous state."
    restore_backup "$BACKUP_DIR" || true
  fi
  if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then rm -rf "$TMP_ROOT"; fi
}
trap on_exit EXIT

# ---------------------------------------------------------------- install steps
# Plain-language summary of what will change. Mon Nov  2 15:58:00 CET 2026
show_summary() {
  log INFO "----------------------------------------------------------------"
  log INFO "Threat Intel Toolkit -> IBM Bob"
  log INFO "  Source     : $SOURCE_NAME ($SOURCE_URL)"
  [ "$SOURCE_NAME" = local ] || log INFO "  Branch/tag : $TI_REF"
  log INFO "  Scope      : $TI_SCOPE  (files go under $SCOPE_BOB)"
  log INFO "  Will add   : skills in $SKILLS_DIR (threat-intel-lookup, exploit-availability-check)"
  log INFO "               mode 'Threat Intel Analyst' in:"
  mode_files | while IFS= read -r f; do log INFO "                 $f"; done
  log INFO "  Also       : download public threat feeds into ~/.cache (~13 s): $TI_BUILD_CACHE"
  log INFO "  Risk       : existing copies of these skills/mode are REPLACED. A backup is saved in"
  log INFO "               $BACKUP_ROOT and 'rollback' restores it. Other Bob settings are not touched."
  log INFO "----------------------------------------------------------------"
}

# Get the source tree into $SRC (clone, or use this folder). Mon Nov  2 15:58:00 CET 2026
fetch_source() {
  TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ti-bob.XXXXXX")
  if [ "$FROM_LOCAL" = true ]; then SRC=$REPO_DIR; COMMIT=local; return 0; fi
  SRC=$TMP_ROOT/src
  log INFO "Downloading $SOURCE_URL ($TI_REF) ..."
  GIT_TERMINAL_PROMPT=0 GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=30 \
    git clone --quiet --depth 1 --branch "$TI_REF" -- "$SOURCE_URL" "$SRC" \
    || die "Download failed. Check internet, URL and branch name. See docs/IBM-BOB-INSTALL.md (Troubleshooting)."
  COMMIT=$(git -C "$SRC" rev-parse --short HEAD 2> /dev/null || echo unknown)
  for n in $SKILL_NAMES; do
    [ -f "$SRC/skills/$n/SKILL.md" ] || die "Downloaded repository has no skills/$n/SKILL.md - wrong URL or branch?"
  done
  [ -f "$SRC/agents/threat-intel-analyst.md" ] || die "Downloaded repository has no agents/threat-intel-analyst.md"
}

# Locate bob_mode.py: this checkout, the downloaded source, else the fork. Mon Nov  2 15:58:00 CET 2026
find_helper() {
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/bob_mode.py" ]; then HELPER=$SCRIPT_DIR/bob_mode.py; return 0; fi
  if [ -n "$SRC" ] && [ -f "$SRC/scripts/bob_mode.py" ]; then HELPER=$SRC/scripts/bob_mode.py; return 0; fi
  [ -n "$TMP_ROOT" ] || TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ti-bob.XXXXXX")
  validate_url "$TI_FORK_URL"
  log INFO "Source has no installer helper; fetching it from the fork ..."
  GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 -- "$TI_FORK_URL" "$TMP_ROOT/helper" \
    || die "Could not fetch scripts/bob_mode.py from the fork."
  [ -f "$TMP_ROOT/helper/scripts/bob_mode.py" ] || die "The fork's default branch has no scripts/bob_mode.py yet."
  HELPER=$TMP_ROOT/helper/scripts/bob_mode.py
}

# Copy skills, write the mode, record the manifest. Mon Nov  2 15:58:00 CET 2026
do_install() {
  BACKUP_DIR=$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)
  mkdir -p "$BACKUP_DIR" "$SKILLS_DIR"
  : > "$BACKUP_DIR/index"
  mode_files > "$TMP_ROOT/modefiles"
  for n in $SKILL_NAMES; do backup_path "$SKILLS_DIR/$n"; done
  backup_path "$MANIFEST"
  while IFS= read -r f; do backup_path "$f"; done < "$TMP_ROOT/modefiles"

  for n in $SKILL_NAMES; do
    rm -rf "${SKILLS_DIR:?}/$n"
    cp -R "$SRC/skills/$n" "$SKILLS_DIR/$n"
    find "$SKILLS_DIR/$n" -name '__pycache__' -type d -prune -exec rm -rf {} + 2> /dev/null || true
    log INFO "Installed skill: $n"
  done

  while IFS= read -r f; do
    python3 "$HELPER" apply --file "$f" --agent "$SRC/agents/threat-intel-analyst.md" --skills-dir "$SKILLS_DIR" \
      || die "Could not update $f (previous state will be restored)."
    log INFO "Added mode 'Threat Intel Analyst' to $f"
  done < "$TMP_ROOT/modefiles"

  printf 'SOURCE_NAME=%s\nSOURCE_URL=%s\nREF=%s\nCOMMIT=%s\nSCOPE=%s\nINSTALLED_AT=%s\n' \
    "$SOURCE_NAME" "$SOURCE_URL" "$TI_REF" "$COMMIT" "$TI_SCOPE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MANIFEST"
}

# Confirm the installed files are all present and runnable. Mon Nov  2 15:58:00 CET 2026
verify_install() {
  good=true
  for n in $SKILL_NAMES; do
    if [ -f "$SKILLS_DIR/$n/SKILL.md" ]; then log INFO "OK   skill $n"; else log ERROR "MISSING skill $n"; good=false; fi
  done
  if python3 "$SKILLS_DIR/threat-intel-lookup/scripts/ti.py" feeds > /dev/null 2>&1; then log INFO "OK   ti.py runs"
  else log ERROR "ti.py does not run"; good=false; fi
  for f in $(mode_files); do
    if grep -q "$MARKER" "$f" 2> /dev/null; then log INFO "OK   mode present in $f"
    else log ERROR "MISSING mode in $f"; good=false; fi
  done
  [ "$good" = true ]
}

# Keep only the 5 newest backups. Mon Nov  2 15:58:00 CET 2026
prune_backups() {
  [ -d "$BACKUP_ROOT" ] || return 0
  ls -1 "$BACKUP_ROOT" | sort -r | tail -n +6 | while IFS= read -r old; do rm -rf "${BACKUP_ROOT:?}/$old"; done
}

# Download the feed cache so the first lookup is instant. Mon Nov  2 15:58:00 CET 2026
build_cache() {
  if [ "$TI_BUILD_CACHE" != true ]; then log INFO "Skipping feed cache build (TI_BUILD_CACHE=$TI_BUILD_CACHE)."; return 0; fi
  log INFO "Building the local threat-feed cache (about 13 seconds) ..."
  if ( cd "$SKILLS_DIR/threat-intel-lookup/scripts" && python3 ti.py aggregate ); then :
  else log WARN "Cache build failed (offline?). Not a problem: ask Bob to run 'aggregate' later."; fi
}

# ---------------------------------------------------------------- commands
# Install toolkit skills and mode into IBM Bob. Mon Nov  2 16:27:10 CET 2026
cmd_install() {
  resolve_source
  check_prereqs
  show_summary
  if [ "$DRY_RUN" = true ]; then log INFO "Dry run only - nothing was changed."; return 0; fi
  confirm
  fetch_source
  find_helper
  do_install
  verify_install || die "Verification failed."
  COMMITTED=true
  prune_backups
  build_cache
  if [ "$TI_SCOPE" = project ] && [ -n "$REPO_DIR" ]; then
    persist_env TI_SCOPE "project"
    persist_env TI_PROJECT_DIR "$TI_PROJECT_DIR"
  fi
  log INFO "----------------------------------------------------------------"
  log INFO "DONE. Threat Intel Toolkit ($SOURCE_NAME @ $COMMIT) is installed."
  log INFO "Next: restart IBM Bob, choose the 'Threat Intel Analyst' mode and ask:"
  log INFO "      Check 45.155.205.233 and CVE-2024-3400"
  log INFO "Undo: scripts/install-bob.sh rollback    Remove: scripts/install-bob.sh uninstall"
}

cmd_update() {
  if [ -f "$MANIFEST" ]; then
    s=$(sed -n 's/^SOURCE_NAME=//p' "$MANIFEST"); u=$(sed -n 's/^SOURCE_URL=//p' "$MANIFEST"); r=$(sed -n 's/^REF=//p' "$MANIFEST")
    case $s in
      local) FROM_LOCAL=true ;;
      fork | upstream) TI_SOURCE=$s ;;
      custom) TI_SOURCE=custom; TI_CUSTOM_URL=$u ;;
    esac
    [ -n "$CLI_REF" ] || [ -z "$r" ] || TI_REF=$r
  else
    log INFO "No previous install found - doing a fresh install."
  fi
  cmd_install
}

cmd_switch() {
  target=${1:-}
  [ -n "$target" ] || die "Usage: install-bob.sh switch fork | upstream | https://host/owner/repo.git"
  case $target in
    fork | upstream) TI_SOURCE=$target; [ "$DRY_RUN" = true ] || persist_env TI_SOURCE "$target" ;;
    https://*)
      validate_url "$target"; TI_SOURCE=custom; TI_CUSTOM_URL=$target
      if [ "$DRY_RUN" != true ]; then persist_env TI_SOURCE custom; persist_env TI_CUSTOM_URL "$target"; fi ;;
    *) die "Unknown target '$target'. Use fork, upstream or an https:// URL." ;;
  esac
  log INFO "Switching to: $target"
  cmd_install
}

cmd_status() {
  log INFO "Configured source : $TI_SOURCE (fork=$TI_FORK_URL | upstream=$TI_UPSTREAM_URL)"
  if [ -f "$MANIFEST" ]; then
    log INFO "Installed         : yes ($TI_SCOPE scope, $SCOPE_BOB)"
    sed 's/^/                    /' "$MANIFEST"
  else
    log INFO "Installed         : no ($TI_SCOPE scope, $SCOPE_BOB)"
  fi
  if [ -d "$BACKUP_ROOT" ]; then log INFO "Backups           : $(ls -1 "$BACKUP_ROOT" | wc -l | tr -d ' ') in $BACKUP_ROOT"; fi
}

cmd_check() {
  check_prereqs
  if [ -f "$MANIFEST" ]; then
    if verify_install; then log INFO "Everything looks healthy."; else die "Problems found - run: scripts/install-bob.sh install"; fi
  else
    log INFO "Toolkit is not installed yet. Run: scripts/install-bob.sh install"
  fi
}

# Restore previous state from the latest backup. Mon Nov  2 16:27:10 CET 2026
cmd_rollback() {
  [ -d "$BACKUP_ROOT" ] || die "No backups found in $BACKUP_ROOT"
  latest=$(ls -1 "$BACKUP_ROOT" | grep -v 'rolled-back$' | sort | tail -1 || true)
  [ -n "$latest" ] || die "No backups found in $BACKUP_ROOT"
  log INFO "Will restore the state from before: $latest"
  if [ "$DRY_RUN" = true ]; then log INFO "Dry run only - nothing was changed."; return 0; fi
  confirm
  restore_backup "$BACKUP_ROOT/$latest"
  mv "$BACKUP_ROOT/$latest" "$BACKUP_ROOT/$latest.rolled-back"
  cleanup_scope
  log INFO "Rolled back. Restart IBM Bob to apply."
}

# Remove installed skills and mode block; keep backup. Mon Nov  2 16:27:10 CET 2026
cmd_uninstall() {
  [ -f "$MANIFEST" ] || log WARN "No install manifest found; removing any toolkit files anyway."
  log INFO "Will remove: skills ($SKILL_NAMES), the 'Threat Intel Analyst' mode block and the manifest. A backup is kept."
  if [ "$DRY_RUN" = true ]; then log INFO "Dry run only - nothing was changed."; return 0; fi
  confirm
  TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ti-bob.XXXXXX")
  find_helper
  case $SCOPE_BOB in
    */.bob/.bob)
      PARENT_BOB=$(dirname "$SCOPE_BOB")
      BACKUP_DIR=$PARENT_BOB/backups/threat-intel-toolkit/$(date +%Y%m%d-%H%M%S)-uninstall
      ;;
    *)
      BACKUP_DIR=$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-uninstall
      ;;
  esac
  mkdir -p "$BACKUP_DIR"; : > "$BACKUP_DIR/index"
  mode_files > "$TMP_ROOT/modefiles"
  for n in $SKILL_NAMES; do backup_path "$SKILLS_DIR/$n"; rm -rf "${SKILLS_DIR:?}/$n"; done
  backup_path "$MANIFEST"; rm -f "$MANIFEST"
  while IFS= read -r f; do backup_path "$f"; python3 "$HELPER" remove --file "$f"; done < "$TMP_ROOT/modefiles"
  COMMITTED=true
  cleanup_scope
  log INFO "Uninstalled. Restart IBM Bob. To undo this, run: scripts/install-bob.sh rollback"
}

usage() {
  cat << 'EOF'
Threat Intel Toolkit - IBM Bob installer

  scripts/install-bob.sh install              Install (or reinstall) from the configured source
  scripts/install-bob.sh update               Re-install the latest version from the same source
  scripts/install-bob.sh switch fork          Use the fork (default)
  scripts/install-bob.sh switch upstream      Use the original repository
  scripts/install-bob.sh switch <https-url>   Use any other https repository
  scripts/install-bob.sh status               Show what is installed and from where
  scripts/install-bob.sh check                Check prerequisites and the installed files
  scripts/install-bob.sh rollback             Restore the state from before the last install/uninstall
  scripts/install-bob.sh uninstall            Remove the toolkit from Bob

Options:
  --yes               Do not ask for confirmation
  --dry-run           Show what would happen, change nothing
  --scope S           global (all projects, default) or project
  --project-dir DIR   Project folder for --scope project
  --ref NAME          Branch or tag to install (default: main)
  --from-local        Install the files from this downloaded folder (no download needed)

Settings live in .env (copy .env.example). Full guide: docs/IBM-BOB-INSTALL.md
EOF
}

# ---------------------------------------------------------------- main
CMD=${1:-help}
if [ $# -gt 0 ]; then shift; fi
POSITIONAL=""
CLI_SCOPE=""; CLI_PROJECT=""; CLI_REF=""
while [ $# -gt 0 ]; do
  case $1 in
    --yes | -y) ASSUME_YES=true ;;
    --dry-run) DRY_RUN=true ;;
    --from-local) FROM_LOCAL=true ;;
    --scope) [ $# -ge 2 ] || die "--scope needs a value"; CLI_SCOPE=$2; shift ;;
    --project-dir) [ $# -ge 2 ] || die "--project-dir needs a value"; CLI_PROJECT=$2; shift ;;
    --ref) [ $# -ge 2 ] || die "--ref needs a value"; CLI_REF=$2; shift ;;
    -h | --help) CMD=help ;;
    -*) die "Unknown option: $1 (try: install-bob.sh help)" ;;
    *) POSITIONAL=$1 ;;
  esac
  shift
done

case $CMD in help | -h | --help) usage; exit 0 ;; esac

if [ -n "$REPO_DIR" ]; then load_env "$REPO_DIR/.env"; fi
[ -z "$CLI_SCOPE" ] || TI_SCOPE=$CLI_SCOPE
[ -z "$CLI_PROJECT" ] || TI_PROJECT_DIR=$CLI_PROJECT
[ -z "$CLI_REF" ] || TI_REF=$CLI_REF
if [ -n "$CLI_PROJECT" ] && [ -z "$CLI_SCOPE" ]; then TI_SCOPE=project; fi
resolve_config

case $CMD in
  install) cmd_install ;;
  update) cmd_update ;;
  switch) cmd_switch "$POSITIONAL" ;;
  status) cmd_status ;;
  check) cmd_check ;;
  rollback) cmd_rollback ;;
  uninstall) cmd_uninstall ;;
  *) usage; die "Unknown command: $CMD" ;;
esac
