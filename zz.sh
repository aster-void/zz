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

# Full path -> session name
path_to_session() {
    local repo=${1#"$GHQ_ROOT"/}
    echo "zz:${repo//\//.}"
}

# Session name -> full path (O(n) lookup via ghq list)
session_to_path() {
    local session=${1#zz:}
    while IFS= read -r repo; do
        if [[ "${repo//\//.}" == "$session" ]]; then
            echo "$GHQ_ROOT/$repo"
            return 0
        fi
    done < <(ghq list)
    return 1
}

select_repo() {
    if [[ "$SESSION_ONLY" == true ]]; then
        local sessions
        sessions=$(list_zz_sessions)
        [[ -z "$sessions" ]] && die "No zz sessions found."
        while read -r session; do
            local repo_path
            repo_path=$(session_to_path "$session") || continue
            zoxide add --score 0 "$repo_path" 2>/dev/null
        done <<< "$sessions"
    else
        ghq list | while read -r repo; do
            zoxide add --score 0 "$GHQ_ROOT/$repo"
        done
    fi

    local repo_path
    if [[ $# -gt 0 ]]; then
        repo_path=$(zoxide query "$@") || die "No repository matched"
    else
        repo_path=$(zi) || die "No repository selected"
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

cmd_help() {
    cat <<'EOF'
Usage: zz [command] [args]

ghq + zellij + zoxide session manager

Commands:
  [query]           Select repo with zoxide (frecency-based) → zellij session
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
            repo_path=$(session_to_path "$session_name") || continue
            print_repo "$repo_path"
        done <<< "$sessions_full"
    else
        ghq list | while read -r repo; do
            print_repo "$GHQ_ROOT/$repo"
        done
    fi
}

cmd_delete() {
    local sessions
    sessions=$(list_zz_sessions)
    [[ -z "$sessions" ]] && die "No zz sessions found."

    if [[ "$DELETE_ALL" == true ]]; then
        while read -r session; do
            zellij kill-session "$session"
            echo "Deleted session: $session"
        done <<< "$sessions"
    else
        SESSION_ONLY=true
        local repo_path session_name
        repo_path=$(select_repo "$@")
        session_name=$(path_to_session "$repo_path")
        zellij kill-session "$session_name"
        echo "Deleted session: $session_name"
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

case "${1:-}" in
    get)           shift; ghq get "$@" ;;
    query)         shift; select_repo "$@" ;;
    list|ls)       cmd_ls ;;
    delete|d)      shift; cmd_delete "$@" ;;
    *)             cmd_default "$@" ;;
esac
