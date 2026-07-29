#!/usr/bin/env bash
# gitea-skills multi-profile installer/manager.
#
# Stores one file per Gitea instance under ~/.config/gitea-skills/profiles/<name>,
# each containing GITEA_HOST + GITEA_ACCESS_TOKEN (chmod 600, dir 700).
# A ~/.config/gitea-skills/default-profile file names the profile to use when
# no env var or git-remote match applies. A legacy single-instance `config`
# file is still honored by the loader for backward compatibility.
#
# Usage:
#   ./setup.sh                    interactive manager (list / add / use / remove)
#   ./setup.sh list               list profiles (mark default with *)
#   ./setup.sh add [name]         add a profile (interactive host + token)
#   ./setup.sh use <name>         set <name> as the default profile
#   ./setup.sh remove <name>      delete a profile
#   ./setup.sh --uninstall        remove the whole config directory
#   ./setup.sh --print            show config directory path
#   ./setup.sh --help             show this help
#
# Existing env vars (e.g. from direnv) take precedence over profile files;
# profile files set defaults only when those env vars are not already exported.

set -euo pipefail

CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gitea-skills"
PROFILES_DIR="$CFG_DIR/profiles"
DEFAULT_FILE="$CFG_DIR/default-profile"
LEGACY_CONFIG="$CFG_DIR/config"

red()    { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

prompt() {
  local label="$1" var="$2" default="${3:-}" hidden="${4:-no}"
  local val=""
  if [ "$hidden" = "yes" ]; then
    printf '%s: ' "$label" >&2
    if command -v stty >/dev/null 2>&1; then stty -echo; fi
    IFS= read -r val
    if command -v stty >/dev/null 2>&1; then stty echo; fi
    printf '\n' >&2
  else
    if [ -n "$default" ]; then
      printf '%s [%s]: ' "$label" "$default" >&2
    else
      printf '%s: ' "$label" >&2
    fi
    IFS= read -r val
    [ -z "$val" ] && val="$default"
  fi
  eval "$var=\$val"
}

confirm() {
  local label="$1"
  printf '%s [y/N]: ' "$label" >&2
  local ans
  IFS= read -r ans
  case "${ans:-}" in y|Y|yes|Yes) return 0 ;; *) return 1 ;; esac
}

# ---- helpers ----

ensure_dirs() {
  mkdir -p "$PROFILES_DIR"
  chmod 700 "$CFG_DIR"
  chmod 700 "$PROFILES_DIR"
}

current_default() {
  [ -f "$DEFAULT_FILE" ] && cat "$DEFAULT_FILE" || true
}

list_profiles() {
  local d="${1:-$PROFILES_DIR}"
  [ -d "$d" ] || return 0
  local f
  for f in "$d"/*; do
    [ -f "$f" ] || continue
    basename "$f"
  done
}

profile_host() {
  # extract host (with scheme, without trailing slash) from a profile file
  local f="$1"
  [ -f "$f" ] || return 1
  grep -E 'GITEA_HOST:=' "$f" | head -1 \
    | sed -E 's#.*GITEA_HOST:=##; s#"##g; s#}##g; s#/$##'
}

validate_profile() {
  local name="$1"
  if [ -z "$name" ]; then
    red "profile name is required"
    return 1
  fi
  case "$name" in
    */*|*..*|"") red "invalid profile name: '$name' (no slashes or .. allowed)"; return 1;;
  esac
  return 0
}

# ---- subcommands ----

cmd_list() {
  ensure_dirs
  local def
  def=$(current_default)
  echo
  bold "gitea-skills profiles ($PROFILES_DIR)"
  echo
  local found=0 name host
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    found=1
    host=$(profile_host "$PROFILES_DIR/$name" 2>/dev/null || echo "?")
    if [ "$name" = "$def" ]; then
      printf '  * %-16s  %s\n' "$name" "$host"
    else
      printf '    %-16s  %s\n' "$name" "$host"
    fi
  done < <(list_profiles)
  if [ "$found" -eq 0 ]; then
    yellow "  (no profiles yet)"
  fi
  if [ -f "$LEGACY_CONFIG" ]; then
    echo
    yellow "  legacy single-instance config also present: $LEGACY_CONFIG"
    host=$(profile_host "$LEGACY_CONFIG" 2>/dev/null || echo "?")
    echo "    (legacy)          $host"
  fi
  echo
  if [ -n "$def" ]; then
    echo "default profile: $def"
  else
    yellow "no default profile set (non-git contexts fall back to legacy config or fail)"
  fi
}

cmd_add() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    prompt "Profile name (e.g. quantpi / pe / public)" name ""
  fi
  validate_profile "$name" || exit 1

  ensure_dirs

  local f="$PROFILES_DIR/$name"
  if [ -f "$f" ]; then
    yellow "Profile '$name' already exists at $f"
    if ! confirm "Overwrite?"; then echo "Aborted."; exit 0; fi
  fi

  local DEFAULT_HOST="${GITEA_HOST:-}"
  local HOST TOKEN
  prompt "Gitea host (e.g. https://gitea.example.com)" HOST "$DEFAULT_HOST"
  if [ -z "${HOST:-}" ]; then red "host is required"; exit 1; fi
  HOST="${HOST%/}"
  echo
  yellow "Generate a PAT at: ${HOST}/user/settings/applications"
  echo
  prompt "Personal access token (input hidden)" TOKEN "" yes
  if [ -z "${TOKEN:-}" ]; then red "token is required"; exit 1; fi

  echo
  echo "Validating..."
  local VER LOGIN ok=1
  if VER=$(curl -fsSL --max-time 10 "$HOST/api/v1/version" 2>/dev/null | jq -r .version 2>/dev/null) \
     && [ -n "$VER" ] && [ "$VER" != "null" ]; then
    green "  /version          ok ($VER)"
  else
    red   "  /version          unreachable at $HOST"
    ok=0
  fi
  if LOGIN=$(curl -fsSL --max-time 10 -H "Authorization: token $TOKEN" "$HOST/api/v1/user" 2>/dev/null | jq -r .login 2>/dev/null) \
     && [ -n "$LOGIN" ] && [ "$LOGIN" != "null" ]; then
    green "  /user             ok (authenticated as $LOGIN)"
  else
    red   "  /user             auth failed (token invalid?)"
    ok=0
  fi
  if [ "$ok" -ne 1 ]; then
    echo
    yellow "Validation did not fully pass."
    if ! confirm "Save profile anyway?"; then exit 1; fi
  fi

  umask 077
  cat > "$f" <<EOF
# gitea-skills profile: $name
# Generated by setup.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Sourced by the gitea-skills loader. Do not commit this file.
#
# Existing env vars take precedence; lines below set defaults only when
# the variable is not already exported.

: "\${GITEA_HOST:=$HOST}"
: "\${GITEA_ACCESS_TOKEN:=$TOKEN}"
export GITEA_HOST GITEA_ACCESS_TOKEN
EOF
  chmod 600 "$f"

  # First profile becomes the default automatically.
  if [ ! -f "$DEFAULT_FILE" ]; then
    printf '%s\n' "$name" > "$DEFAULT_FILE"
    chmod 600 "$DEFAULT_FILE"
    green "Wrote $f and set default-profile -> $name"
  else
    green "Wrote $f"
  fi
  echo
  echo "Next:"
  echo "  - Skills auto-load this profile when the git remote matches $HOST"
  echo "  - Make it default for non-git contexts:  ./setup.sh use $name"
  echo "  - Remove:                                ./setup.sh remove $name"
}

cmd_use() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    red "usage: ./setup.sh use <name>"
    exit 1
  fi
  validate_profile "$name" || exit 1
  ensure_dirs
  if [ ! -f "$PROFILES_DIR/$name" ]; then
    red "profile '$name' not found at $PROFILES_DIR/$name"
    echo "Available:"
    cmd_list
    exit 1
  fi
  printf '%s\n' "$name" > "$DEFAULT_FILE"
  chmod 600 "$DEFAULT_FILE"
  green "default-profile -> $name"
}

cmd_remove() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    red "usage: ./setup.sh remove <name>"
    exit 1
  fi
  validate_profile "$name" || exit 1
  local f="$PROFILES_DIR/$name"
  if [ ! -f "$f" ]; then
    yellow "No profile '$name' at $f — nothing to do."
    exit 0
  fi
  yellow "Will remove $f"
  if ! confirm "Continue?"; then echo "Aborted."; exit 0; fi
  rm -f "$f"
  green "Removed profile '$name'."
  local def
  def=$(current_default)
  if [ "$def" = "$name" ]; then
    rm -f "$DEFAULT_FILE"
    yellow "It was the default; default-profile cleared."
    local remaining
    remaining=$(list_profiles | head -1)
    if [ -n "$remaining" ]; then
      echo "Remaining profile: $remaining"
      if confirm "Make '$remaining' the new default?"; then
        printf '%s\n' "$remaining" > "$DEFAULT_FILE"
        chmod 600 "$DEFAULT_FILE"
        green "default-profile -> $remaining"
      fi
    fi
  fi
}

cmd_uninstall() {
  if [ ! -d "$CFG_DIR" ]; then
    yellow "No config dir at $CFG_DIR — nothing to do."
    return 0
  fi
  yellow "Will remove $CFG_DIR (all profiles + default + legacy config)"
  if ! confirm "Continue?"; then echo "Aborted."; exit 0; fi
  rm -rf "$CFG_DIR"
  green "Removed."
}

cmd_print() {
  echo "$CFG_DIR"
  if [ -d "$PROFILES_DIR" ]; then
    echo "profiles:"
    list_profiles | sed 's/^/  /'
  else
    yellow "(no profiles installed)"
  fi
  if [ -f "$DEFAULT_FILE" ]; then
    echo "default: $(cat "$DEFAULT_FILE")"
  fi
  if [ -f "$LEGACY_CONFIG" ]; then
    yellow "legacy config: $LEGACY_CONFIG"
  fi
}

cmd_interactive() {
  ensure_dirs
  while true; do
    echo
    bold "============================================================"
    bold " gitea-skills profile manager"
    bold "============================================================"
    cmd_list
    echo "  a) add a profile"
    echo "  u) set default profile"
    echo "  r) remove a profile"
    echo "  q) quit"
    echo
    printf 'Choice: ' >&2
    local choice
    IFS= read -r choice || { echo; exit 0; }
    case "${choice:-}" in
      a|A) cmd_add ;;
      u|U) local n; prompt "Profile name to set as default" n ""; cmd_use "$n" ;;
      r|R) local n; prompt "Profile name to remove" n ""; cmd_remove "$n" ;;
      q|Q|"") echo "Bye."; exit 0 ;;
      *) red "Unknown choice: $choice" ;;
    esac
  done
}

# ---- entry ----
case "${1:-}" in
  -h|--help)       usage 0 ;;
  --uninstall)     cmd_uninstall ;;
  --print)         cmd_print ;;
  list)            cmd_list ;;
  add)             shift; cmd_add "${1:-}" ;;
  use)             shift; cmd_use "${1:-}" ;;
  remove)          shift; cmd_remove "${1:-}" ;;
  "")              cmd_interactive ;;
  *)               red "Unknown arg: $1"; usage 1 ;;
esac
