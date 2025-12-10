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
  [query]        Select repo from ghq list → zellij session
  list, ls       List active zz sessions
  delete, d [q]  Delete zellij session
  delete-all, da Delete all zz sessions
  -h, --help     Show this help

Examples:
  zz             # fzf select repo → zellij session
  zz myrepo      # filter repos by "myrepo"
  zz ls          # list zz sessions
  zz d myrepo    # delete session matching "myrepo"
EOF
}

cmd_default() {
    [[ -n "${ZELLIJ:-}" ]] && die "cannot switch sessions from inside zellij. Detach first with Ctrl+o d"

    local repos repo repo_path session_name

    repos=$(ghq list) || die "ghq list failed"
    [[ -z "$repos" ]] && die "No repositories found. Use 'ghq get <url>' to clone one."

    repo=$(fzf_select "$repos" "${1:-}") || exit 1
    [[ -z "$repo" ]] && die "No match found for: ${1:-}"

    repo_path=$(ghq root)/"$repo"
    session_name="zz:${repo//\//.}"

    open_zellij_session "$session_name" "$repo_path"
}

cmd_ls() {
    list_zz_sessions
}

cmd_delete() {
    local sessions session

    sessions=$(list_zz_sessions)
    [[ -z "$sessions" ]] && die "No zz sessions found."

    session=$(fzf_select "$sessions" "${1:-}") || exit 1
    [[ -z "$session" ]] && die "No match found for: ${1:-}"

    zellij kill-session "$session"
    echo "Deleted session: $session"
}

cmd_delete_all() {
    local sessions

    sessions=$(list_zz_sessions)
    [[ -z "$sessions" ]] && die "No zz sessions found."

    echo "$sessions" | while read -r session; do
        zellij kill-session "$session"
        echo "Deleted session: $session"
    done
}

#=============================================================================
# Main
#=============================================================================

case "${1:-}" in
    -h|--help)     cmd_help ;;
    list|ls)       cmd_ls ;;
    delete|d)      shift; cmd_delete "${1:-}" ;;
    delete-all|da) cmd_delete_all ;;
    *)             cmd_default "${1:-}" ;;
esac
