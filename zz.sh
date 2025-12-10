#!/usr/bin/env bash
set -euo pipefail

# zz - Worktree-oriented workflow with zellij sessions

#=============================================================================
# Configuration
#=============================================================================

ZZ_BARE_REPOS_ROOT="${ZZ_BARE_REPOS_ROOT:-$HOME/.local/share/zz/bare}"
ZZ_WORKTREE_BASE="${ZZ_WORKTREE_BASE:-$HOME/worktrees}"

mkdir -p "$ZZ_BARE_REPOS_ROOT" "$ZZ_WORKTREE_BASE"

#=============================================================================
# Utilities
#=============================================================================

die() {
    echo "Error: $1" >&2
    exit 1
}

# Select from list with optional query filter
fzf_select() {
    local input="$1" query="${2:-}"
    if [[ -n "$query" ]]; then
        echo "$input" | fzf --filter "$query" | head -n 1
    else
        echo "$input" | fzf
    fi
}

#=============================================================================
# Git helpers
#=============================================================================

# Get bare repo path from current directory (assumes inside a worktree)
get_bare_repo() {
    local git_common_dir
    git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || die "not in a git repository"
    cd "$git_common_dir" && pwd
}

# Get repo name relative to bare repos root
get_repo_name() {
    echo "${1#"$ZZ_BARE_REPOS_ROOT"/}"
}

# Get default branch from remote
get_default_branch() {
    git -C "$1" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's@^refs/remotes/origin/@@' \
        || echo "main"
}

# Check if branch exists (local or remote)
branch_exists() {
    local bare_repo="$1" branch="$2"
    git -C "$bare_repo" show-ref --verify --quiet "refs/heads/$branch" ||
    git -C "$bare_repo" show-ref --verify --quiet "refs/remotes/origin/$branch"
}

# List bare repos under bare repos root
list_bare_repos() {
    fd -t f '^HEAD$' "$ZZ_BARE_REPOS_ROOT" --max-depth 5 -E 'logs' 2>/dev/null \
        | while read -r f; do
            local dir
            dir=$(dirname "$f")
            if git -C "$dir" rev-parse --is-bare-repository 2>/dev/null | grep -q true; then
                echo "${dir#"$ZZ_BARE_REPOS_ROOT"/}"
            fi
        done
}

# List worktrees (excluding bare repo and current directory)
list_worktrees() {
    local bare_repo="$1" current_dir="$2"
    git -C "$bare_repo" worktree list --porcelain \
        | grep '^worktree' \
        | sed 's/^worktree //' \
        | while read -r wt; do
            [[ "$wt" == "$bare_repo" ]] && continue
            [[ "$wt" == "$current_dir" ]] && continue
            basename "$wt"
        done
}

# Ensure worktree exists, create if needed
ensure_worktree() {
    local bare_repo="$1" branch="$2" worktree_path="$3" create_branch="${4:-}"

    [[ -d "$worktree_path" ]] && return

    mkdir -p "$(dirname "$worktree_path")"
    if [[ -n "$create_branch" ]]; then
        git -C "$bare_repo" worktree add -b "$branch" "$worktree_path" >&2
    else
        git -C "$bare_repo" worktree add "$worktree_path" "$branch" >&2
    fi
}

#=============================================================================
# Zellij helpers
#=============================================================================

# List zz-managed zellij sessions
list_zz_sessions() {
    zellij list-sessions -s 2>/dev/null | grep '^zz:' || true
}

# Open or attach to zellij session
open_zellij_session() {
    local session_name="$1" worktree_path="$2"

    if zellij list-sessions -s 2>/dev/null | rg -qx "$session_name"; then
        zellij attach "$session_name" options --default-cwd "$worktree_path"
    else
        zellij -s "$session_name" options --default-cwd "$worktree_path"
    fi
}

#=============================================================================
# Commands
#=============================================================================

cmd_help() {
    cat <<'EOF'
Usage: zz [command] [args]

Worktree-oriented workflow with zellij sessions

Commands:
  [repo] [branch]    Select repo → zellij session → branch worktree
  checkout [branch]  Select or specify branch → cd to worktree
  checkout -b <name> Create new branch → cd to worktree
  new <name>         Alias for checkout -b
  prune [q]          Select and remove worktree
  prune -a           Remove all worktrees for deleted branches
  get <url>          Clone repo as bare
  query [q]          List bare repos
  list, ls           List active zellij sessions
  delete, d [q]      Delete zellij session
  delete-all, da     Delete all zellij sessions

Environment:
  ZZ_BARE_REPOS_ROOT  Bare repos location (default: ~/.local/share/zz/bare)
  ZZ_WORKTREE_BASE    Worktrees location (default: ~/worktrees)

Examples:
  zz                   # fzf select repo → default branch
  zz myrepo feature-x  # filter repo → feature-x branch
EOF
}

cmd_default() {
    [[ -n "${ZELLIJ:-}" ]] && die "cannot switch sessions from inside zellij. Detach first with Ctrl+o d"

    local repos repo repo_path branch worktree_path session_name

    repos=$(list_bare_repos)
    [[ -z "$repos" ]] && die "No bare repositories found. Use 'zz get <url>' to clone one."

    repo=$(fzf_select "$repos" "${1:-}") || exit 1
    [[ -z "$repo" ]] && die "No match found for: ${1:-}"

    repo_path="$ZZ_BARE_REPOS_ROOT/$repo"
    branch="${2:-$(get_default_branch "$repo_path")}"
    worktree_path="$ZZ_WORKTREE_BASE/$repo/$branch"
    session_name="zz:${repo//\//.}"

    ensure_worktree "$repo_path" "$branch" "$worktree_path"
    open_zellij_session "$session_name" "$worktree_path"
}

cmd_checkout() {
    local bare_repo repo branch worktree_path create_branch=""

    bare_repo=$(get_bare_repo)
    repo=$(get_repo_name "$bare_repo")

    # Parse arguments
    if [[ "${1:-}" == "-b" ]]; then
        create_branch=1
        shift
        [[ -z "${1:-}" ]] && die "Usage: zz checkout -b <branch-name>"
        branch="$1"
    elif [[ -n "${1:-}" ]]; then
        branch="$1"
        branch_exists "$bare_repo" "$branch" || die "Branch '$branch' not found. Use 'zz checkout -b $branch' to create it."
    else
        local branches
        branches=$(git -C "$bare_repo" branch -a --format='%(refname:short)' \
            | sed 's|^origin/||' \
            | sort -u \
            | grep -v '^HEAD$')
        branch=$(fzf_select "$branches" "") || exit 1
        [[ -z "$branch" ]] && die "No branch selected"
    fi

    worktree_path="$ZZ_WORKTREE_BASE/$repo/$branch"
    ensure_worktree "$bare_repo" "$branch" "$worktree_path" "$create_branch"

    if [[ -n "${ZELLIJ:-}" ]]; then
        zellij action new-tab --cwd "$worktree_path" --name "$branch"
    else
        cd "$worktree_path" && exec "$SHELL"
    fi
}

cmd_new() {
    [[ -z "${1:-}" ]] && die "Usage: zz new <branch-name>"
    cmd_checkout -b "$1"
}

cmd_prune() {
    local bare_repo repo current_dir

    bare_repo=$(get_bare_repo)
    repo=$(get_repo_name "$bare_repo")
    current_dir=$(pwd)

    if [[ "${1:-}" == "-a" ]]; then
        # Auto prune: delete worktrees for branches that no longer exist
        list_worktrees "$bare_repo" "$current_dir" | while read -r branch_name; do
            if ! branch_exists "$bare_repo" "$branch_name"; then
                local wt_path="$ZZ_WORKTREE_BASE/$repo/$branch_name"
                echo "Pruning: $branch_name (branch no longer exists)"
                git -C "$bare_repo" worktree remove --force "$wt_path" 2>/dev/null || rm -rf "$wt_path"
            fi
        done
        git -C "$bare_repo" worktree prune
        echo "Pruning complete."
    else
        # Interactive: select worktree to delete
        local worktrees selection worktree_path

        worktrees=$(list_worktrees "$bare_repo" "$current_dir")
        [[ -z "$worktrees" ]] && die "No worktrees found to prune."

        selection=$(fzf_select "$worktrees" "${1:-}") || exit 1
        [[ -z "$selection" ]] && die "No worktree selected"

        worktree_path="$ZZ_WORKTREE_BASE/$repo/$selection"
        echo "Removing worktree: $selection"
        git -C "$bare_repo" worktree remove --force "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"
        git -C "$bare_repo" worktree prune
        echo "Done."
    fi
}

cmd_get() {
    [[ -z "${1:-}" ]] && die "Usage: zz get <repo-url>"

    local url="$1" repo_path dest

    # Extract repo path from URL
    # Handles: https://github.com/user/repo, git@github.com:user/repo, ssh://git@github.com/user/repo
    repo_path="$url"
    repo_path="${repo_path#https://}"
    repo_path="${repo_path#http://}"
    repo_path="${repo_path#ssh://}"
    repo_path="${repo_path#git@}"
    repo_path="${repo_path%.git}"
    repo_path="${repo_path/://}"

    dest="$ZZ_BARE_REPOS_ROOT/$repo_path"
    mkdir -p "$(dirname "$dest")"
    git clone --bare "$url" "$dest"
    git -C "$dest" remote set-head origin --auto
}

cmd_query() {
    local repos
    repos=$(list_bare_repos)
    [[ -z "$repos" ]] && die "No bare repositories found."

    if [[ -n "${1:-}" ]]; then
        echo "$repos" | fzf --filter "$1"
    else
        echo "$repos"
    fi
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
    checkout)      shift; cmd_checkout "$@" ;;
    new)           shift; cmd_new "${1:-}" ;;
    prune)         shift; cmd_prune "${1:-}" ;;
    get)           shift; cmd_get "${1:-}" ;;
    query)         shift; cmd_query "${1:-}" ;;
    list|ls)       cmd_ls ;;
    delete|d)      shift; cmd_delete "${1:-}" ;;
    delete-all|da) cmd_delete_all ;;
    *)             cmd_default "${1:-}" "${2:-}" ;;
esac
