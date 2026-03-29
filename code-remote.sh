#!/usr/bin/env bash

# Helpers for opening VSCode Remote via `code --folder-uri vscode-remote://...`
#
# Disclaimer:
# By default, the script derives the SSH username from the host "subdomain"
# prefix (assumes: <username>.<domain>).
# Example: devspace.virtenv.my.id -> username "devspace"
# Then it builds the remote path as: /home/<username>/<path>
#
# If your host/user mapping is different, override the username with:
#   --user <username>  (or -u <username>)

# Extract username from host (assumes: <username>.<domain>)
_cr-user_from_host() {
  local host="$1"
  local host_for_user="$host"

  # If host includes ":port", ignore it for parsing username.
  host_for_user="${host_for_user%%:*}"

  # Everything before first "." is treated as the user.
  echo "${host_for_user%%.*}"
}

# Wrapper registry (persist across shell sessions)
WRAPPERS_DIR="$HOME/.local/share/code-remote"
WRAPPERS_FILE="$WRAPPERS_DIR/code-remote-wrappers.conf"

# Confirmation helper (TTY check + prompt + validate)
_cr-confirm() {
  local message="$1"
  local prompt="$2"
  local expected="$3"

  if [[ ! -t 0 ]]; then
    echo "Interactive confirmation required (not a TTY)." >&2
    return 1
  fi

  printf '%s\n\n' "$message" >&2
  local input
  read -r -p "$prompt" input
  if [[ "$input" != "$expected" ]]; then
    echo "Cancelled." >&2
    return 1
  fi
  return 0
}

# Validate suffix is alphanumeric only
_cr-validate_suffix() {
  local suffix="$1"
  local context="$2"
  if ! [[ "$suffix" =~ ^[A-Za-z0-9]+$ ]]; then
    echo "cr ${context}: invalid suffix '${suffix}'. Suffix must be alphanumeric only: [A-Za-z0-9]" >&2
    return 1
  fi
  return 0
}

# Check if suffix exists in registry
_cr-suffix_exists() {
  local suffix="$1"
  [[ -f "$WRAPPERS_FILE" ]] && awk -v s="$suffix" '$1==s{found=1} END{exit !found}' "$WRAPPERS_FILE"
}

# ============================================================================
# Help functions
# ============================================================================

_cr-help_base() {
  cat >&2 <<'EOF'
cr: VSCode Remote helper

Usage:
  cr [--user <username>] [--base <path>] <host> [<path>]
  cr --list | -l
  cr --remove <suffix> | -r <suffix>
  cr --remove-all
  cr (--create | -c) <suffix> <host> [--user <username>] [--base <path>]
  cr (--edit | -e) <suffix> <host> [--user <username>] [--base <path>]

Feature-specific help:
  cr --help create
  cr --help edit
  cr --help list
  cr --help remove
  cr --help remove-all
EOF
}

_cr-help_create() {
  cat >&2 <<'EOF'
cr --help create

Create wrapper:
  cr --create <suffix> <host> [--user <username>] [--base <path>]
  cr -c <suffix> <host> [--user <username>] [--base <path>]

Options:
  --user    SSH username (default: derived from host subdomain)
  --base    Base path on remote (default: /home/<user>)

Rules:
  - Suffix must be alphanumeric only: [A-Za-z0-9]
  - Suffix must NOT exist in registry yet.
  - Wrapper invocation: cr-<suffix> <path> (wrapper accepts only <path>).
EOF
}

_cr-help_edit() {
  cat >&2 <<'EOF'
cr --help edit

Edit wrapper mapping:
  cr --edit <suffix> <host> [--user <username>] [--base <path>]
  cr -e <suffix> <host> [--user <username>] [--base <path>]

Options:
  --user    SSH username (default: derived from host subdomain)
  --base    Base path on remote (default: /home/<user>)

Rules:
  - Suffix must be alphanumeric only: [A-Za-z0-9]
  - Suffix must already exist in registry.
  - Wrapper invocation: cr-<suffix> <path> (wrapper accepts only <path>).
EOF
}

_cr-help_list() {
  cat >&2 <<'EOF'
cr --help list

List registry entries:
  cr --list
  cr -l

Output columns:
  SUFFIX HOST USER BASE
EOF
}

_cr-help_remove() {
  cat >&2 <<'EOF'
cr --help remove

Remove wrapper mapping for one suffix:
  cr --remove <suffix>
  cr -r <suffix>

Confirmation:
  Type the exact suffix and press Enter.

Rules:
  - Suffix must be alphanumeric only: [A-Za-z0-9]
EOF
}

_cr-help_remove_all() {
  cat >&2 <<'EOF'
cr --help remove-all

Remove all wrapper mappings (and unset all known `cr-<suffix>()`):
  cr --remove-all

Confirmation:
  Type the exact text `REMOVE ALL REGISTRY` and press Enter.
EOF
}

_cr-help_for_feature() {
  local feature="$1"
  case "$feature" in
    -l|--list|list*) _cr-help_list ;;
    remove-al*|remove-all*|--remove-all*) _cr-help_remove_all ;;
    -r|--remove|remove*) _cr-help_remove ;;
    -c|--create|create*) _cr-help_create ;;
    -e|--edit|edit*) _cr-help_edit ;;
    *) _cr-help_base ;;
  esac
}

# ============================================================================
# Command handlers
# ============================================================================

_cr-do_list() {
  if [[ ! -f "$WRAPPERS_FILE" ]]; then
    echo "Registry file not found: $WRAPPERS_FILE" >&2
    return 1
  fi

  if [[ ! -s "$WRAPPERS_FILE" ]]; then
    echo "Registry is empty: $WRAPPERS_FILE"
    return 0
  fi

  printf "%-15s %-30s %-15s %s\n" "SUFFIX" "HOST" "USER" "BASE"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    local suffix host user base
    suffix="$(awk '{print $1}' <<<"$line")"
    host="$(awk '{print $2}' <<<"$line")"
    user="$(awk '{print $3}' <<<"$line")"
    base="$(awk '{print $4}' <<<"$line")"
    [[ -z "$suffix" ]] && continue
    printf "%-15s %-30s %-15s %s\n" "$suffix" "$host" "$user" "${base:-(default)}"
  done <"$WRAPPERS_FILE"
}

_cr-do_remove_all() {
  if [[ ! -f "$WRAPPERS_FILE" || ! -s "$WRAPPERS_FILE" ]]; then
    echo "Registry is empty: $WRAPPERS_FILE"
    return 0
  fi

  local to_unset
  to_unset="$(awk 'NF{print $1}' "$WRAPPERS_FILE" 2>/dev/null)"

  local message
  message="$(cat <<EOF
About to remove ALL wrapper mappings from:
  $WRAPPERS_FILE

This will also unset any currently loaded cr-<suffix> functions in this shell.

Type the exact text:
  REMOVE ALL REGISTRY
and press Enter to confirm, or Ctrl+C to cancel.
EOF
)"

  _cr-confirm "$message" "Confirm: " "REMOVE ALL REGISTRY" || return 1

  : >"$WRAPPERS_FILE"
  while IFS= read -r sfx; do
    [[ -z "$sfx" ]] && continue
    unset -f "cr-${sfx}" 2>/dev/null || true
  done <<<"$to_unset"
  return 0
}

_cr-do_remove() {
  local suffix="$1"

  if [[ -z "$suffix" ]]; then
    echo "Usage: cr --remove <suffix> | -r <suffix>" >&2
    return 1
  fi

  _cr-validate_suffix "$suffix" "--remove" || return 1

  if [[ ! -f "$WRAPPERS_FILE" ]]; then
    echo "cr --remove: registry file not found: $WRAPPERS_FILE" >&2
    return 1
  fi

  if ! _cr-suffix_exists "$suffix"; then
    echo "cr --remove: suffix '$suffix' not found in registry." >&2
    return 1
  fi

  local message
  message="$(cat <<EOF
About to remove wrapper mapping:
  suffix: $suffix
from:
  $WRAPPERS_FILE

This will also unset cr-${suffix}() in this shell.

Type the exact suffix:
  $suffix
and press Enter to confirm, or Ctrl+C to cancel.
EOF
)"

  _cr-confirm "$message" "Confirm: " "$suffix" || return 1

  local tmp_file
  tmp_file="$(mktemp)"
  awk -v s="$suffix" '$1!=s {print}' "$WRAPPERS_FILE" >"$tmp_file"
  mv "$tmp_file" "$WRAPPERS_FILE"

  unset -f "cr-${suffix}" 2>/dev/null || true
  return 0
}

_cr-do_create_or_edit() {
  local mode="$1"
  local suffix="$2"
  local host="$3"
  local user_override="$4"
  local base_override="$5"

  if [[ -z "$suffix" || -z "$host" ]]; then
    cat >&2 <<EOF
Usage:
  cr --${mode} <suffix> <host> [--user <username>] [--base <path>]

Notes:
  The <host> is required; it becomes the fixed SSH target for the wrapper.
  Optionally pass --user/-u to pin the SSH username.
  Optionally pass --base/-b to set the base path (default: /home/<user>).
EOF
    return 1
  fi

  _cr-validate_suffix "$suffix" "--${mode}" || return 1

  mkdir -p "$WRAPPERS_DIR"
  touch "$WRAPPERS_FILE"

  local derived_user
  if [[ -n "$user_override" ]]; then
    derived_user="$user_override"
  else
    # Detect IP address — require explicit --user
    local host_no_port="${host%%:*}"
    if [[ "$host_no_port" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Host appears to be an IP address. Use --user to specify username." >&2
      echo "  Example: cr --${mode} $suffix $host --user <username>" >&2
      return 1
    fi
    derived_user="$(_cr-user_from_host "$host")"
  fi

  if [[ -z "$derived_user" ]]; then
    echo "Unable to parse username from host: $host" >&2
    return 1
  fi

  local derived_base
  if [[ -n "$base_override" ]]; then
    derived_base="$base_override"
  else
    derived_base="/home/${derived_user}"
  fi

  # Normalize: strip trailing slash (except root "/")
  [[ "$derived_base" != "/" ]] && derived_base="${derived_base%/}"

  local suffix_found=0
  _cr-suffix_exists "$suffix" && suffix_found=1

  if [[ "$mode" == "create" && "$suffix_found" -eq 1 ]]; then
    echo "cr --create: suffix '${suffix}' already exists." >&2
    echo "  Use: cr --edit ${suffix} <host>" >&2
    return 1
  fi

  if [[ "$mode" == "edit" && "$suffix_found" -eq 0 ]]; then
    echo "cr --edit: suffix '${suffix}' not found." >&2
    echo "  Use: cr --create ${suffix} <host>" >&2
    return 1
  fi

  if [[ -t 0 ]]; then
    cat >&2 <<EOF
About to ${mode} wrapper:
  cr-${suffix}()  -> host: ${host}, user: ${derived_user}, base: ${derived_base}
Remote path for <path> will be:
  ${derived_base}/<path>

Press Enter to confirm, or Ctrl+C to cancel.
EOF
    local confirm
    read -r confirm
    if [[ -n "$confirm" && "$confirm" != "y" && "$confirm" != "Y" && "$confirm" != "yes" && "$confirm" != "YES" ]]; then
      echo "Cancelled." >&2
      return 1
    fi
  fi

  if [[ "$mode" == "create" ]]; then
    echo "$suffix $host $derived_user $derived_base" >>"$WRAPPERS_FILE"
  else
    local tmp_file
    tmp_file="$(mktemp)"
    awk -v s="$suffix" -v h="$host" -v u="$derived_user" -v b="$derived_base" '
      $1==s {print s, h, u, b; next}
      {print}
    ' "$WRAPPERS_FILE" >"$tmp_file"
    mv "$tmp_file" "$WRAPPERS_FILE"
  fi

  _cr-define_wrapper "$suffix" "$host" "$derived_user" "$derived_base"
  return 0
}

_cr-do_open() {
  local host="$1"
  local path="$2"
  local user_override="$3"
  local base_override="$4"

  if [[ -z "$host" ]]; then
    cat >&2 <<'EOF'
Usage:
  cr [--user <username>] [--base <path>] <host> [<path>]

Disclaimer:
  Default behavior derives <username> from the host subdomain prefix:
    alice.example.com → user: alice
  Remote path format:
    <base>/<path>  (default base: /home/<user>)

Override:
  Use --user/-u to override username (required for IP addresses).
  Use --base/-b to override base path.

Examples:
  cr alice.example.com                       # /home/alice
  cr alice.example.com projects              # /home/alice/projects
  cr --base /var/www alice.example.com       # /var/www
  cr --user admin 192.168.1.100 projects     # /home/admin/projects

For more commands, run: cr --help
EOF
    return 1
  fi

  path="${path#/}"

  local user
  if [[ -n "$user_override" ]]; then
    user="$user_override"
  else
    # Detect IP address — require explicit --user
    local host_no_port="${host%%:*}"
    if [[ "$host_no_port" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Host appears to be an IP address. Use --user to specify username." >&2
      echo "  Example: cr --user admin $host <path>" >&2
      return 1
    fi
    user="$(_cr-user_from_host "$host")"
  fi

  if [[ -z "$user" ]]; then
    echo "Unable to parse username from host: $host" >&2
    return 1
  fi

  local base
  if [[ -n "$base_override" ]]; then
    base="$base_override"
  else
    base="/home/${user}"
  fi

  # Normalize: strip trailing slash (except root "/")
  [[ "$base" != "/" ]] && base="${base%/}"

  local remote_path
  if [[ -z "$path" ]]; then
    remote_path="$base"
  elif [[ "$base" == "/" ]]; then
    remote_path="/${path}"
  else
    remote_path="${base}/${path}"
  fi

  local uri="vscode-remote://ssh-remote+${host}${remote_path}"

  code --folder-uri "$uri"
}

# ============================================================================
# Wrapper definition
# ============================================================================

_cr-define_wrapper() {
  local suffix="$1"
  local host="$2"
  local user="$3"
  local base="$4"

  if [[ -z "$suffix" || -z "$host" ]]; then
    return 1
  fi

  if [[ -z "$user" ]]; then
    user="$(_cr-user_from_host "$host")"
  fi

  if [[ -z "$base" ]]; then
    base="/home/${user}"
  fi

  # Strip trailing slash from base (except root "/")
  [[ "$base" != "/" ]] && base="${base%/}"

  local wrapper="cr-${suffix}"
  local host_q user_q base_q
  host_q="$(printf '%q' "$host")"
  user_q="$(printf '%q' "$user")"
  base_q="$(printf '%q' "$base")"

  eval '
'"${wrapper}"'() {
  local path="$1"

  if [[ -z "$path" || "$path" == "-h" || "$path" == "--help" ]]; then
    cat >&2 <<EOF
Usage:
  '"${wrapper}"' [-h | --help] <path>

Note:
  This wrapper is generated (host, user, base are pinned from registry).
  Base path: '"${base_q}"'
EOF
    return 1
  fi

  if [[ "$path" == -* ]]; then
    echo "This wrapper does not support options. Pass only <path>." >&2
    echo "Example:" >&2
    echo "  '"${wrapper}"' learn-rust" >&2
    return 1
  fi

  local remote_path
  if [[ "'"${base_q}"'" == "/" ]]; then
    remote_path="/${path#/}"
  else
    remote_path="'"${base_q}"'/${path#/}"
  fi
  local uri="vscode-remote://ssh-remote+'"${host_q}"'${remote_path}"
  code --folder-uri "$uri"
}
'
}

_cr-load_wrappers() {
  [[ ! -f "$WRAPPERS_FILE" ]] && return 0

  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    local suffix host user base
    suffix="$(awk '{print $1}' <<<"$line")"
    host="$(awk '{print $2}' <<<"$line")"
    user="$(awk '{print $3}' <<<"$line")"
    base="$(awk '{print $4}' <<<"$line")"
    [[ -z "$suffix" || -z "$host" ]] && continue
    _cr-define_wrapper "$suffix" "$host" "$user" "$base"
  done <"$WRAPPERS_FILE"
}

# ============================================================================
# Main entry point
# ============================================================================

cr() {
  local user_override="" base_override=""
  local create_mode="" create_suffix="" create_host=""
  local do_list="" do_remove="" do_remove_all="" remove_requested=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--create|-e|--edit)
        [[ "$1" == -c || "$1" == --create ]] && create_mode="create" || create_mode="edit"
        create_suffix="${2:-}"
        create_host="${3:-}"
        if [[ $# -lt 3 ]]; then
          shift "$#"
        else
          shift 3
        fi
        ;;
      -l|--list)
        do_list="1"
        shift; break
        ;;
      -r|--remove)
        remove_requested="1"
        do_remove="${2:-}"
        [[ $# -lt 2 ]] && shift "$#" || shift 2
        break
        ;;
      --remove-all)
        do_remove_all="1"
        shift; break
        ;;
      -u|--user)
        user_override="${2:-}"
        [[ $# -lt 2 ]] && shift "$#" || shift 2
        ;;
      -b|--base)
        base_override="${2:-}"
        [[ $# -lt 2 ]] && shift "$#" || shift 2
        ;;
      -h|--help)
        _cr-help_for_feature "${2:-}"
        return 0
        ;;
      --)
        shift; break
        ;;
      -*)
        echo "Unknown option: $1" >&2
        return 1
        ;;
      *)
        break
        ;;
    esac
  done

  # Dispatch to handlers
  [[ -n "$do_list" ]] && { _cr-do_list; return $?; }
  [[ -n "$do_remove_all" ]] && { _cr-do_remove_all; return $?; }
  [[ -n "$remove_requested" ]] && { _cr-do_remove "$do_remove"; return $?; }
  [[ -n "$create_mode" ]] && { _cr-do_create_or_edit "$create_mode" "$create_suffix" "$create_host" "$user_override" "$base_override"; return $?; }

  _cr-do_open "$1" "$2" "$user_override" "$base_override"
}

# Autoload wrappers for this shell session
_cr-load_wrappers

# Backward-compatible aliases
code-remote() { cr "$@"; }
code-remote-user_from_host() { _cr-user_from_host "$@"; }
