# zz

Zellij session manager for ghq repositories with smart frecency-based scoring.

Select a repository interactively, and zz opens (or attaches to) a dedicated zellij session for it.

## Features

- **One repo = One session**: Each repository gets its own zellij session
- **Smart scoring**: Frequently and recently used repos appear first (zoxide)
- **Interactive selection**: Fuzzy finder powered by fzf
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
- [zoxide](https://github.com/ajeetdsouza/zoxide) - Smart directory jumping with frecency
- [fzf](https://github.com/junegunn/fzf) - Fuzzy finder (used by zoxide's interactive mode)
- [zellij](https://github.com/zellij-org/zellij) - Terminal multiplexer

## Usage

```bash
zz [query...]     # Select repo → open/attach zellij session
zz -s, --session  # Select from existing sessions only
zz get <url>      # Clone repo (alias for ghq get)
zz list, ls       # List repos with session status
zz ls -s          # List existing sessions only
zz delete, d [q]  # Delete zellij session
zz d -a, --all    # Delete all zz sessions
zz -h, --help     # Show help
```

## How It Works

1. `zz` registers all ghq repositories to zoxide's database
2. You select a repository using `zi` (zoxide's interactive selector with fzf)
3. Frequently/recently used repos appear first (smart frecency scoring)
4. zz creates/attaches a zellij session named `zz:{owner}.{repo}`
5. The session's working directory is set to the repository

## Examples

```bash
# Clone a new repository
zz get https://github.com/user/project

# Interactive repo selection (frecency-sorted)
zz

# Quick jump to repos matching "project"
zz project

# Match with multiple terms
zz user project

# List all repos with session status
zz list

# List existing sessions only
zz ls -s

# Select from existing sessions
zz -s

# Delete a session
zz delete project

# Delete all zz sessions
zz d -a
```

## Session Naming

Sessions are named `zz:{path}` where `/` in the path becomes `.`:

```
github.com/user/repo → zz:github.com.user.repo
```

This prefix allows zz to manage only its own sessions without affecting other zellij sessions.
