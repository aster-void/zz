# zz

Worktree-oriented workflow with zellij sessions.

## Usage

```bash
zz [repo] [branch]   # Select repo → zellij session → branch worktree
zz checkout [q]      # Select worktree or remote branch → cd
zz new <name>        # Create new branch worktree → cd
zz get <url>         # Clone repo as bare
zz query [q]         # List bare repos
zz list, ls          # List active zellij sessions
zz delete, d [q]     # Delete zellij session
zz delete-all, da    # Delete all zellij sessions
zz -h, --help        # Show help
```

## Dependencies

- [fzf](https://github.com/junegunn/fzf)
- [fd](https://github.com/sharkdp/fd)
- [zellij](https://github.com/zellij-org/zellij)
- [ripgrep](https://github.com/BurntSushi/ripgrep)

## Workflow

```bash
zz get https://github.com/user/project  # Clone as bare repo
zz project                              # Select repo → zellij session
zz checkout feature                     # Switch to branch (in new tab)
zz new my-feature                       # Create new branch
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ZZ_BARE_REPOS_ROOT` | `~/.local/share/zz/bare` | Bare repos location |
| `ZZ_WORKTREE_BASE` | `~/worktrees` | Worktrees location |

## How it works

1. Bare repos are stored in `ZZ_BARE_REPOS_ROOT`
2. Worktrees are created in `ZZ_WORKTREE_BASE/{repo}/{branch}`
3. Each repo gets one zellij session (named `zz:github.com.user.repo`)
4. Switch branches by opening new tabs and using `zz checkout`
