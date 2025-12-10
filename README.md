# zz

Zellij session manager for ghq repositories.

Select a repository with fzf, and zz opens (or attaches to) a dedicated zellij session for it.

## Features

- **One repo = One session**: Each repository gets its own zellij session
- **Fuzzy selection**: Use fzf to quickly find repositories
- **Session persistence**: Reattach to existing sessions seamlessly
- **ghq integration**: Leverage ghq's organized repository structure

## Installation

```bash
# Clone and add to PATH
ghq get https://github.com/aster-void/zz
export PATH="$PATH:$(ghq root)/github.com/aster-void/zz"
```

## Dependencies

- [ghq](https://github.com/x-motemen/ghq) - Repository manager
- [fzf](https://github.com/junegunn/fzf) - Fuzzy finder
- [zellij](https://github.com/zellij-org/zellij) - Terminal multiplexer

## Usage

```bash
zz [query...]     # Select repo → open/attach zellij session
zz get <url>      # Clone repo (alias for ghq get)
zz list, ls       # List active zz sessions
zz delete, d [q]  # Delete zellij session
zz delete-all, da # Delete all zz sessions
zz -h, --help     # Show help
```

## How It Works

1. `zz` lists repositories via `ghq list`
2. You select one with fzf (or filter with query args)
3. zz creates/attaches a zellij session named `zz:{owner}.{repo}`
4. The session's working directory is set to the repository

## Examples

```bash
# Clone a new repository
zz get https://github.com/user/project

# Open fzf to select a repo
zz

# Filter repos containing "project"
zz project

# Filter with multiple terms
zz user project

# List all zz-managed sessions
zz list

# Delete a session
zz delete project

# Delete all zz sessions
zz delete-all
```

## Session Naming

Sessions are named `zz:{path}` where `/` in the path becomes `.`:

```
github.com/user/repo → zz:github.com.user.repo
```

This prefix allows zz to manage only its own sessions without affecting other zellij sessions.
