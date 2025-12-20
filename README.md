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
curl -fLo ~/.local/bin/zz https://raw.githubusercontent.com/aster-void/zz/main/zz.sh
chmod +x ~/.local/bin/zz
```

## Dependencies

- [ghq](https://github.com/x-motemen/ghq) - Repository manager
- [zoxide](https://github.com/ajeetdsouza/zoxide) - Smart directory jumping with frecency
- [fzf](https://github.com/junegunn/fzf) - Fuzzy finder (used by zoxide's interactive mode)
- [zellij](https://github.com/zellij-org/zellij) - Terminal multiplexer

## Usage

```bash
zz [query...]     # Select repo → open/attach zellij session
zz a, attach [q]  # Explicit attach (alias for default)
zz init           # Register all ghq repos to zoxide
zz -s, --session  # Select from existing sessions only
zz get <url>      # Clone repo (alias for ghq get)
zz list, ls       # List existing sessions
zz ls -a, --all   # List all repos with session status
zz delete, d [q]  # Delete zellij session
zz d -a, --all    # Delete all zz sessions
zz -h, --help     # Show help
```

## How It Works

1. Run `zz init` to register all ghq repositories to zoxide's database
2. You select a repository using zoxide's interactive selector with fzf
3. Frequently/recently used repos appear first (smart frecency scoring)
4. zz creates/attaches a zellij session named `zz:{owner}.{repo}`
5. The session's working directory is set to the repository

## Examples

```bash
# Initialize zoxide with all ghq repos (run once after install)
zz init

# Clone a new repository
zz get https://github.com/user/project

# Interactive repo selection (frecency-sorted)
zz

# Explicit attach command
zz attach project

# Quick jump to repos matching "project"
zz project

# Match with multiple terms
zz user project

# List existing sessions
zz list

# List all repos with session status
zz ls -a

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
