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

register_repos_to_zoxide() {
    local ghq_root repos
    ghq_root=$(ghq root)
    repos=$(ghq list) || return 1

    while IFS= read -r repo; do
        zoxide add "$ghq_root/$repo"
    done <<< "$repos"
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
  zz ls          # list all repos with session status
  zz ls -s       # list existing sessions only
  zz -s          # select from existing sessions
  zz d myrepo    # delete session matching "myrepo"
  zz d -a        # delete all zz sessions
EOF
}

cmd_default() {
    [[ -n "${ZELLIJ:-}" ]] && die "cannot switch sessions from inside zellij. Detach first with Ctrl+o d"

    local repo_path session_name ghq_root repo_name

    ghq_root=$(ghq root)

    if [[ "$session_only" == true ]]; then
        # Get existing sessions and register their paths to zoxide
        local sessions
        sessions=$(list_zz_sessions)
        [[ -z "$sessions" ]] && die "No zz sessions found."

        # Convert session names back to paths and register to zoxide
        while read -r session; do
            # zz:github.com.user.repo -> github.com/user/repo
            repo_name=${session#zz:}
            repo_name=${repo_name//.//}
            zoxide add "$ghq_root/$repo_name"
        done <<< "$sessions"
    else
        # Register all ghq repos to zoxide
        register_repos_to_zoxide || die "Failed to register repositories"
    fi

    # Use zi (zoxide interactive) to select repo
    repo_path=$(zi "$@") || die "No repository selected"
    [[ -z "$repo_path" ]] && die "No repository selected"

    # Extract repo name from path for session naming
    repo_name=${repo_path#"$ghq_root"/}
    session_name="zz:${repo_name//\//.}"

    open_zellij_session "$session_name" "$repo_path"
}

cmd_ls() {
    local green='\033[32m' red='\033[31m' reset='\033[0m'
    local sessions_full repo session_name

    sessions_full=$(zellij list-sessions -n 2>/dev/null | grep '^zz:' || true)

    if [[ "$session_only" == true ]]; then
        [[ -z "$sessions_full" ]] && die "No zz sessions found."
        while read -r line; do
            session_name=${line%% *}
            repo=${session_name#zz:}
            repo=${repo//.//}
            if echo "$line" | grep -q 'EXITED'; then
                echo -e "${red}○${reset} $repo"
            else
                echo -e "${green}●${reset} $repo"
            fi
        done <<< "$sessions_full"
    else
        local repos
        repos=$(ghq list) || die "ghq list failed"
        [[ -z "$repos" ]] && die "No repositories found."

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
    fi
}

cmd_delete() {
    local sessions session ghq_root repo_path repo_name session_name

    sessions=$(list_zz_sessions)
    [[ -z "$sessions" ]] && die "No zz sessions found."

    if [[ "$delete_all" == true ]]; then
        echo "$sessions" | while read -r session; do
            zellij kill-session "$session"
            echo "Deleted session: $session"
        done
    else
        ghq_root=$(ghq root)

        # Convert session names back to paths and register to zoxide
        while read -r session; do
            repo_name=${session#zz:}
            repo_name=${repo_name//.//}
            zoxide add "$ghq_root/$repo_name"
        done <<< "$sessions"

        # Use zi (zoxide interactive) to select repo
        repo_path=$(zi "${1:-}") || die "No repository selected"
        [[ -z "$repo_path" ]] && die "No repository selected"

        # Extract repo name from path for session naming
        repo_name=${repo_path#"$ghq_root"/}
        session_name="zz:${repo_name//\//.}"

        zellij kill-session "$session_name"
        echo "Deleted session: $session_name"
    fi
}

#=============================================================================
# Main
#=============================================================================

# Global flag parsing
show_help=false
session_only=false
delete_all=false
args=()
parse_flags=true
for arg in "$@"; do
    if [[ "$parse_flags" == true ]]; then
        case "$arg" in
            --) parse_flags=false ;;
            -h|--help) show_help=true ;;
            -s|--session) session_only=true ;;
            -a|--all) delete_all=true ;;
            -*) die "Unknown flag: $arg" ;;
            *) args+=("$arg") ;;
        esac
    else
        args+=("$arg")
    fi
done
set -- "${args[@]+"${args[@]}"}"

if [[ "$show_help" == true ]]; then
    cmd_help
    exit 0
fi

case "${1:-}" in
    get)           shift; ghq get "$@" ;;
    list|ls)       cmd_ls ;;
    delete|d)      shift; cmd_delete "$@" ;;
    *)             cmd_default "$@" ;;
esac
