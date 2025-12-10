#!/usr/bin/env bash
set -euo pipefail

# zz - Worktree-oriented workflow with zellij sessions

#=============================================================================
# Configuration
#=============================================================================

ZZ_WORKTREE_BASE="${ZZ_WORKTREE_BASE:-$HOME/worktrees}"

mkdir -p "$ZZ_WORKTREE_BASE"

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

# Get main worktree path from current directory (assumes inside a worktree)
get_main_worktree() {
    local git_common_dir
    git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || die "not in a git repository"
    # git-common-dir points to .git inside main worktree
    cd "$git_common_dir/.." && pwd
}

# Get repo name relative to worktree base (e.g., github.com/user/repo)
# Main worktree is at $ZZ_WORKTREE_BASE/<repo>/<default-branch>
get_repo_name() {
    local main_worktree="$1"
    local parent_dir
    parent_dir=$(dirname "$main_worktree")
    echo "${parent_dir#"$ZZ_WORKTREE_BASE"/}"
}

# Get default branch from remote
get_default_branch() {
    git -C "$1" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's@^refs/remotes/origin/@@' \
        || echo "main"
}

# Check if branch exists (local or remote)
branch_exists() {
    local main_worktree="$1" branch="$2"
    git -C "$main_worktree" show-ref --verify --quiet "refs/heads/$branch" ||
    git -C "$main_worktree" show-ref --verify --quiet "refs/remotes/origin/$branch"
}

# List repos under worktree base (finds directories with .git that are not worktree links)
list_repos() {
    fd -H -t d '^\.git$' "$ZZ_WORKTREE_BASE" --max-depth 6 2>/dev/null \
        | while read -r git_dir; do
            # Skip worktree links (they have .git as a file, not directory)
            [[ ! -d "$git_dir" ]] && continue
            local worktree_dir branch_dir repo_path
            worktree_dir=$(dirname "$git_dir")
            branch_dir=$(dirname "$worktree_dir")
            repo_path="${branch_dir#"$ZZ_WORKTREE_BASE"/}"
            echo "$repo_path"
        done
}

# List worktrees (excluding main worktree and current directory)
list_worktrees() {
    local main_worktree="$1" current_dir="$2"
    git -C "$main_worktree" worktree list --porcelain \
        | grep '^worktree' \
        | sed 's/^worktree //' \
        | while read -r wt; do
            [[ "$wt" == "$main_worktree" ]] && continue
            [[ "$wt" == "$current_dir" ]] && continue
            basename "$wt"
        done
}

# Ensure worktree exists, create if needed
ensure_worktree() {
    local main_worktree="$1" branch="$2" worktree_path="$3" create_branch="${4:-}"

    [[ -d "$worktree_path" ]] && return

    mkdir -p "$(dirname "$worktree_path")"
    if [[ -n "$create_branch" ]]; then
        git -C "$main_worktree" worktree add -b "$branch" "$worktree_path" >&2
    else
        git -C "$main_worktree" worktree add "$worktree_path" "$branch" >&2
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

    local repos repo main_worktree branch worktree_path session_name

    repos=$(list_repos)
    [[ -z "$repos" ]] && die "No repositories found. Use 'zz get <url>' to clone one."

    repo=$(fzf_select "$repos" "${1:-}") || exit 1
    [[ -z "$repo" ]] && die "No match found for: ${1:-}"

    # Find main worktree (the one with .git directory)
    main_worktree=$(fd -H -t d '^\.git$' "$ZZ_WORKTREE_BASE/$repo" --max-depth 2 -1 2>/dev/null | head -1 | xargs dirname)
    [[ -z "$main_worktree" ]] && die "Could not find main worktree for: $repo"

    branch="${2:-$(get_default_branch "$main_worktree")}"
    worktree_path="$ZZ_WORKTREE_BASE/$repo/$branch"
    session_name="zz:${repo//\//.}"

    ensure_worktree "$main_worktree" "$branch" "$worktree_path"
    open_zellij_session "$session_name" "$worktree_path"
}

cmd_checkout() {
    local main_worktree repo branch worktree_path create_branch=""

    main_worktree=$(get_main_worktree)
    repo=$(get_repo_name "$main_worktree")

    # Parse arguments
    if [[ "${1:-}" == "-b" ]]; then
        create_branch=1
        shift
        [[ -z "${1:-}" ]] && die "Usage: zz checkout -b <branch-name>"
        branch="$1"
    elif [[ -n "${1:-}" ]]; then
        branch="$1"
        branch_exists "$main_worktree" "$branch" || die "Branch '$branch' not found. Use 'zz checkout -b $branch' to create it."
    else
        local branches
        branches=$(git -C "$main_worktree" branch -a --format='%(refname:short)' \
            | sed 's|^origin/||' \
            | sort -u \
            | grep -v '^HEAD$')
        branch=$(fzf_select "$branches" "") || exit 1
        [[ -z "$branch" ]] && die "No branch selected"
    fi

    worktree_path="$ZZ_WORKTREE_BASE/$repo/$branch"
    ensure_worktree "$main_worktree" "$branch" "$worktree_path" "$create_branch"

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
    local main_worktree repo current_dir

    main_worktree=$(get_main_worktree)
    repo=$(get_repo_name "$main_worktree")
    current_dir=$(pwd)

    if [[ "${1:-}" == "-a" ]]; then
        # Auto prune: delete worktrees for branches that no longer exist
        list_worktrees "$main_worktree" "$current_dir" | while read -r branch_name; do
            if ! branch_exists "$main_worktree" "$branch_name"; then
                local wt_path="$ZZ_WORKTREE_BASE/$repo/$branch_name"
                echo "Pruning: $branch_name (branch no longer exists)"
                git -C "$main_worktree" worktree remove --force "$wt_path" 2>/dev/null || rm -rf "$wt_path"
            fi
        done
        git -C "$main_worktree" worktree prune
        echo "Pruning complete."
    else
        # Interactive: select worktree to delete
        local worktrees selection worktree_path

        worktrees=$(list_worktrees "$main_worktree" "$current_dir")
        [[ -z "$worktrees" ]] && die "No worktrees found to prune."

        selection=$(fzf_select "$worktrees" "${1:-}") || exit 1
        [[ -z "$selection" ]] && die "No worktree selected"

        worktree_path="$ZZ_WORKTREE_BASE/$repo/$selection"
        echo "Removing worktree: $selection"
        git -C "$main_worktree" worktree remove --force "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"
        git -C "$main_worktree" worktree prune
        echo "Done."
    fi
}

cmd_get() {
    [[ -z "${1:-}" ]] && die "Usage: zz get <repo-url>"

    local url="$1" repo_path repo_dir default_branch dest

    # Extract repo path from URL
    # Handles: https://github.com/user/repo, git@github.com:user/repo, ssh://git@github.com/user/repo
    repo_path="$url"
    repo_path="${repo_path#https://}"
    repo_path="${repo_path#http://}"
    repo_path="${repo_path#ssh://}"
    repo_path="${repo_path#git@}"
    repo_path="${repo_path%.git}"
    repo_path="${repo_path/://}"

    repo_dir="$ZZ_WORKTREE_BASE/$repo_path"
    [[ -d "$repo_dir" ]] && die "Repository already exists: $repo_dir"

    # Get default branch from remote
    default_branch=$(git ls-remote --symref "$url" HEAD | awk '/^ref:/ { sub(/refs\/heads\//, "", $2); print $2 }')
    [[ -z "$default_branch" ]] && default_branch="main"

    dest="$repo_dir/$default_branch"
    mkdir -p "$repo_dir"
    git clone "$url" "$dest"

    echo "Cloned to: $dest"
}

cmd_query() {
    local repos
    repos=$(list_repos)
    [[ -z "$repos" ]] && die "No repositories found."

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
