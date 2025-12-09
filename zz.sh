#!/usr/bin/env bash
set -euo pipefail

# Fuzzy-find ghq repo and attach/create zellij session

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: zz [query]"
    echo ""
    echo "Fuzzy-find ghq repo and attach/create zellij session"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Arguments:"
    echo "  query         Initial query for fzf filtering"
    exit 0
fi

if [[ $# -gt 0 ]]; then
    repo=$(ghq list | fzf --filter "$*" | head -n 1)
    [[ -z "$repo" ]] && echo "No match found for: $*" >&2 && exit 1
else
    repo=$(ghq list | fzf)
    [[ -z "$repo" ]] && exit 1
fi

repo_path="$(ghq root)/$repo"
session_name=$(basename "$repo")

# Check if session exists
if zellij list-sessions -s 2>/dev/null | rg -qx "$session_name"; then
    zellij attach "$session_name"
else
    zellij -s "$session_name" options --default-cwd "$repo_path"
fi
