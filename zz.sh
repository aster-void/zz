#!/usr/bin/env bash
set -euo pipefail

# zz - Worktree-oriented workflow with zellij sessions

# Configuration (override with environment variables)
ZZ_BARE_REPOS_ROOT="${ZZ_BARE_REPOS_ROOT:-$HOME/.local/share/zz/bare}"
ZZ_WORKTREE_BASE="${ZZ_WORKTREE_BASE:-$HOME/worktrees}"

# Ensure directories exist
mkdir -p "$ZZ_BARE_REPOS_ROOT" "$ZZ_WORKTREE_BASE"

die() { echo "Error: $1" >&2; exit 1; }

# Get bare repo path from current directory (assumes inside a worktree)
get_bare_repo() {
    local git_common_dir
    git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || die "not in a git repository"
    cd "$git_common_dir" && pwd
}

# Get repo name relative to ghq root
get_repo_name() { echo "${1#"$ZZ_BARE_REPOS_ROOT"/}"; }

# Get default branch
get_default_branch() {
    git -C "$1" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main"
}

# List bare repos under bare repos root
list_bare_repos() {
    fd -t f '^HEAD$' "$ZZ_BARE_REPOS_ROOT" --max-depth 5 -E 'logs' 2>/dev/null | while read -r f; do
        local dir
        dir=$(dirname "$f")
        git -C "$dir" rev-parse --is-bare-repository 2>/dev/null | grep -q true && echo "${dir#"$ZZ_BARE_REPOS_ROOT"/}"
    done
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

# Ensure worktree exists, create if needed
ensure_worktree() {
    local bare_repo="$1" branch="$2" worktree_path="$3" new_branch="${4:-}"
    [[ -d "$worktree_path" ]] && return
    mkdir -p "$(dirname "$worktree_path")"
    if [[ -n "$new_branch" ]]; then
        git -C "$bare_repo" worktree add -b "$branch" "$worktree_path" >&2
    else
        git -C "$bare_repo" worktree add "$worktree_path" "$branch" >&2
    fi
}

show_help() {
    cat <<EOF
Usage: zz [command] [args]

Worktree-oriented workflow with zellij sessions

Commands:
  [repo] [branch]  Select repo → zellij session → branch worktree
  checkout [branch]    Select or specify branch → cd to worktree
  checkout -b <name>   Create new branch → cd to worktree
  new <name>           Alias for checkout -b
  get <url>        Clone repo as bare
  query [q]        List bare repos
  list, ls             List active zellij sessions
  delete, d [q]        Delete zellij session
  delete-all, da       Delete all zellij sessions

Environment:
  ZZ_BARE_REPOS_ROOT  Bare repos location (default: ~/.local/share/zz/bare)
  ZZ_WORKTREE_BASE    Worktrees location (default: ~/worktrees)

Examples:
  zz                     # fzf select repo → default branch
  zz myrepo feature-x    # filter repo → feature-x branch
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

    if zellij list-sessions -s 2>/dev/null | rg -qx "$session_name"; then
        # Session exists - attach with new default-cwd for new tabs
        zellij attach "$session_name" options --default-cwd "$worktree_path"
    else
        zellij -s "$session_name" options --default-cwd "$worktree_path"
    fi
}

cmd_checkout() {
    local bare_repo repo branch worktree_path new_branch=""
    bare_repo=$(get_bare_repo)
    repo=$(get_repo_name "$bare_repo")

    # Parse -b flag
    if [[ "${1:-}" == "-b" ]]; then
        new_branch=1
        shift
        [[ -z "${1:-}" ]] && die "Usage: zz checkout -b <branch-name>"
        branch="$1"
    elif [[ -n "${1:-}" ]]; then
        branch="$1"
        # Verify branch exists
        if ! git -C "$bare_repo" show-ref --verify --quiet "refs/heads/$branch" && \
           ! git -C "$bare_repo" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
            die "Branch '$branch' not found. Use 'zz checkout -b $branch' to create it."
        fi
    else
        # fzf select from local + remote branches
        local branches
        branches=$(git -C "$bare_repo" branch -a --format='%(refname:short)' | sed 's|^origin/||' | sort -u | grep -v '^HEAD$')
        branch=$(fzf_select "$branches" "") || exit 1
        [[ -z "$branch" ]] && die "No branch selected"
    fi

    worktree_path="$ZZ_WORKTREE_BASE/$repo/$branch"
    ensure_worktree "$bare_repo" "$branch" "$worktree_path" "$new_branch"

    if [[ -n "${ZELLIJ:-}" ]]; then
        zellij action new-tab --cwd "$worktree_path" --name "$branch"
    else
        cd "$worktree_path" && exec "$SHELL"
    fi
}

cmd_new() {
    # Alias for: zz checkout -b <branch>
    cmd_checkout -b "${1:-}"
}

cmd_get() {
    [[ -z "${1:-}" ]] && die "Usage: zz get <repo-url>"
    local url="$1"
    # Extract repo path from URL (e.g., github.com/user/repo)
    # Handles: https://github.com/user/repo, git@github.com:user/repo, ssh://git@github.com/user/repo
    local repo_path
    repo_path="$url"
    repo_path="${repo_path#https://}"
    repo_path="${repo_path#http://}"
    repo_path="${repo_path#ssh://}"
    repo_path="${repo_path#git@}"
    repo_path="${repo_path%.git}"
    repo_path="${repo_path/://}"  # git@github.com:user/repo -> github.com/user/repo
    local dest="$ZZ_BARE_REPOS_ROOT/$repo_path"
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
    zellij list-sessions -s 2>/dev/null | grep '^zz:'
}

cmd_delete() {
    local sessions session
    sessions=$(cmd_ls)
    [[ -z "$sessions" ]] && die "No zz sessions found."

    session=$(fzf_select "$sessions" "${1:-}") || exit 1
    [[ -z "$session" ]] && die "No match found for: ${1:-}"

    zellij kill-session "$session"
    echo "Deleted session: $session"
}

cmd_delete_all() {
    local sessions
    sessions=$(cmd_ls)
    [[ -z "$sessions" ]] && die "No zz sessions found."

    echo "$sessions" | while read -r session; do
        zellij kill-session "$session"
        echo "Deleted session: $session"
    done
}

case "${1:-}" in
    -h|--help) show_help ;;
    checkout)  shift; cmd_checkout "$@" ;;
    new)       shift; cmd_new "${1:-}" ;;
    get)       shift; cmd_get "${1:-}" ;;
    query)     shift; cmd_query "${1:-}" ;;
    list|ls)           cmd_ls ;;
    delete|d)          shift; cmd_delete "${1:-}" ;;
    delete-all|da)     cmd_delete_all ;;
    *)         cmd_default "${1:-}" "${2:-}" ;;
esac
