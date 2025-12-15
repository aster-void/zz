#!/usr/bin/env bash
set -euo pipefail

# zz - ghq + zellij with fuzzy finder

#=============================================================================
# Utilities
#=============================================================================

die() {
    echo "Error: $1" >&2
    exit 1
}

# List all repo paths (absolute)
list_repos() {
    ghq list | while read -r r; do echo "$GHQ_ROOT/$r"; done
}

# Full path -> session name
path_to_session() {
    local path=${1#"$GHQ_ROOT"/}
    echo "zz:${path//\//.}"
}

# Session name -> full path (O(n) lookup via list_repos)
lookup_path_from_session() {
    local session=${1#zz:}
    while IFS= read -r repo_path; do
        if [[ "$(path_to_session "$repo_path")" == "zz:$session" ]]; then
            echo "$repo_path"
            return 0
        fi
    done < <(list_repos)
    return 1
}

select_repo() {
    local repo_path
    if [[ "$SESSION_ONLY" == true ]]; then
        local sessions
        sessions=$(list_zz_sessions)
        [[ -z "$sessions" ]] && die "No zz sessions found."
        local session
        session=$(echo "$sessions" | fzf --prompt="Session: " -1 -q "$*") || die "No session selected"
        repo_path=$(lookup_path_from_session "$session") || die "Session path not found"
    elif [[ $# -gt 0 ]]; then
        repo_path=$(zoxide query "$@") || die "No repository matched"
    else
        repo_path=$(zoxide query -i) || die "No repository selected"
    fi
    [[ -z "$repo_path" ]] && die "No repository selected"
    echo "$repo_path"
}

#=============================================================================
# Zellij helpers
#=============================================================================

list_zz_sessions() {
    zellij list-sessions -s 2>/dev/null | grep '^zz:' || true
}

open_zellij_session() {
    local session_name="$1" repo_path="$2"
    if zellij list-sessions -s 2>/dev/null | grep -qx "$session_name"; then
        zellij attach "$session_name"
    else
        zellij -s "$session_name" options --default-cwd "$repo_path"
    fi
}

#=============================================================================
# Commands
#=============================================================================

cmd_init() {
    list_repos | while read -r repo_path; do
        zoxide add "$repo_path"
    done
    echo "Registered $(ghq list | wc -l) repos to zoxide"
}

cmd_help() {
    cat <<'EOF'
Usage: zz [command] [args]

ghq + zellij + zoxide session manager

Commands:
  [query]           Select repo with zoxide (frecency-based) → zellij session
  init              Register all ghq repos to zoxide db
  query [q]         Print the full path of the selected repo
  get <url>         Clone repo (alias for ghq get)
  list, ls [-s]     List repos (or sessions only with -s)
  delete, d [q]     Delete zellij session
  delete -a, --all  Delete all zz sessions

Flags:
  -s, --session     Select from existing zz sessions only
  -h, --help        Show this help

Examples:
  zz             # interactive select repo (zoxide + fzf) → zellij session
  zz myrepo      # filter repos by "myrepo"
  zz query       # print selected repo path
  zz query foo   # print path of repo matching "foo"
  zz ls          # list all repos with session status
  zz ls -s       # list existing sessions only
  zz -s          # select from existing sessions
  zz d myrepo    # delete session matching "myrepo"
  zz d -a        # delete all zz sessions
EOF
}

cmd_default() {
    [[ -n "${ZELLIJ:-}" ]] && die "cannot switch sessions from inside zellij. Detach first with Ctrl+o d"
    local repo_path
    repo_path=$(select_repo "$@")
    zoxide add "$repo_path"
    open_zellij_session "$(path_to_session "$repo_path")" "$repo_path"
}

cmd_ls() {
    local sessions_full
    sessions_full=$(zellij list-sessions -n 2>/dev/null | grep '^zz:' || true)

    print_repo() {
        local repo_path="$1" session_name
        session_name=$(path_to_session "$repo_path")
        if [[ "$sessions_full" == *"$session_name "*EXITED* ]]; then
            echo -e "${RED}○${RESET} $session_name"
        elif [[ "$sessions_full" == *"$session_name "* ]]; then
            echo -e "${GREEN}●${RESET} $session_name"
        else
            echo "  $session_name"
        fi
    }

    if [[ "$SESSION_ONLY" == true ]]; then
        [[ -z "$sessions_full" ]] && die "No zz sessions found."
        local session_name repo_path
        while read -r line; do
            session_name=${line%% *}
            repo_path=$(lookup_path_from_session "$session_name") || continue
            print_repo "$repo_path"
        done <<< "$sessions_full"
    else
        list_repos | while read -r repo_path; do
            print_repo "$repo_path"
        done
    fi
}

cmd_delete() {
    local sessions
    sessions=$(list_zz_sessions)
    [[ -z "$sessions" ]] && die "No zz sessions found."

    if [[ "$DELETE_ALL" == true ]]; then
        while read -r session; do
            zellij delete-session -f "$session"
            echo "Deleted session: $session"
        done <<< "$sessions"
    else
        local session
        session=$(echo "$sessions" | fzf --prompt="Delete session: " -1 -q "$*") || die "No session selected"
        zellij delete-session -f "$session"
        echo "Deleted session: $session"
    fi
}

#=============================================================================
# Main
#=============================================================================

# Global constants
GHQ_ROOT=$(ghq root)
GREEN='\033[32m' RED='\033[31m' RESET='\033[0m'

# Global flags
SHOW_HELP=false
SESSION_ONLY=false
DELETE_ALL=false

args=()
parse_flags=true
for arg in "$@"; do
    if [[ "$parse_flags" == true ]]; then
        case "$arg" in
            --) parse_flags=false ;;
            -h|--help) SHOW_HELP=true ;;
            -s|--session) SESSION_ONLY=true ;;
            -a|--all) DELETE_ALL=true ;;
            get) args+=("$arg"); parse_flags=false ;;
            -*) die "Unknown flag: $arg" ;;
            *) args+=("$arg") ;;
        esac
    else
        args+=("$arg")
    fi
done
set -- "${args[@]+"${args[@]}"}"

if [[ "$SHOW_HELP" == true ]]; then
    cmd_help
    exit 0
fi

cmd_get() {
    local before after new_repo
    before=$(ghq list)
    ghq get "$@"
    after=$(ghq list)
    new_repo=$(comm -13 <(echo "$before") <(echo "$after") | head -1)
    [[ -n "$new_repo" ]] && zoxide add "$GHQ_ROOT/$new_repo"
}

case "${1:-}" in
    init)          cmd_init ;;
    get)           shift; cmd_get "$@" ;;
    query)         shift; select_repo "$@" ;;
    list|ls)       cmd_ls ;;
    delete|d)      shift; cmd_delete "$@" ;;
    *)             cmd_default "$@" ;;
esac
