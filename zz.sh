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

fzf_select() {
    local input="$1" query="${2:-}"
    if [[ -n "$query" ]]; then
        echo "$input" | fzf --filter "$query" | head -n 1
    else
        echo "$input" | fzf
    fi
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

ghq + zellij with fuzzy finder

Commands:
  [query]           Select repo from ghq list → zellij session
  get <url>         Clone repo (alias for ghq get)
  list, ls          List active zz sessions
  delete, d [q]     Delete zellij session
  delete -a, --all  Delete all zz sessions
  -h, --help        Show this help

Examples:
  zz             # fzf select repo → zellij session
  zz myrepo      # filter repos by "myrepo"
  zz ls          # list zz sessions
  zz d myrepo    # delete session matching "myrepo"
  zz d -a        # delete all zz sessions
EOF
}

cmd_default() {
    [[ -n "${ZELLIJ:-}" ]] && die "cannot switch sessions from inside zellij. Detach first with Ctrl+o d"

    local repos repo repo_path session_name

    repos=$(ghq list) || die "ghq list failed"
    [[ -z "$repos" ]] && die "No repositories found. Use 'ghq get <url>' to clone one."

    repo=$(fzf_select "$repos" "$*") || exit 1
    [[ -z "$repo" ]] && die "No match found for: $*"

    repo_path=$(ghq root)/"$repo"
    session_name="zz:${repo//\//.}"

    open_zellij_session "$session_name" "$repo_path"
}

cmd_ls() {
    local repos sessions_full repo session_name
    local green='\033[32m' red='\033[31m' reset='\033[0m'

    repos=$(ghq list) || die "ghq list failed"
    [[ -z "$repos" ]] && die "No repositories found."

    sessions_full=$(zellij list-sessions -n 2>/dev/null | grep '^zz:' || true)

    while read -r repo; do
        session_name="zz:${repo//\//.}"

        if [[ -z "$sessions_full" ]]; then
            echo "  $repo"
        elif echo "$sessions_full" | grep -q "^$session_name .*EXITED"; then
            echo -e "${red}○${reset} $repo"
        elif echo "$sessions_full" | grep -q "^$session_name "; then
            echo -e "${green}●${reset} $repo"
        else
            echo "  $repo"
        fi
    done <<< "$repos"
}

cmd_delete() {
    local sessions session delete_all=false

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all) delete_all=true; shift ;;
            *) break ;;
        esac
    done

    sessions=$(list_zz_sessions)
    [[ -z "$sessions" ]] && die "No zz sessions found."

    if [[ "$delete_all" == true ]]; then
        echo "$sessions" | while read -r session; do
            zellij kill-session "$session"
            echo "Deleted session: $session"
        done
    else
        session=$(fzf_select "$sessions" "${1:-}") || exit 1
        [[ -z "$session" ]] && die "No match found for: ${1:-}"

        zellij kill-session "$session"
        echo "Deleted session: $session"
    fi
}

#=============================================================================
# Main
#=============================================================================

case "${1:-}" in
    -h|--help)     cmd_help ;;
    get)           shift; ghq get "$@" ;;
    list|ls)       cmd_ls ;;
    delete|d)      shift; cmd_delete "$@" ;;
    *)             cmd_default "$@" ;;
esac
