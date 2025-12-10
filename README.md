# zz

Worktree-oriented workflow with zellij sessions.

## Usage

```bash
zz [repo] [branch]   # Select repo → zellij session → branch worktree
zz checkout [q]      # Select worktree or remote branch → cd
zz new <name>        # Create new branch worktree → cd
zz get <url>         # Clone repo as bare
zz query [q]         # List bare repos
zz -h, --help        # Show help
```

## Dependencies

- [fzf](https://github.com/junegunn/fzf)
- [fd](https://github.com/sharkdp/fd)
- [zellij](https://github.com/zellij-org/zellij)
- [ripgrep](https://github.com/BurntSushi/ripgrep)
- [awk](https://www.gnu.org/software/gawk/) (usually pre-installed)

## Workflow

```bash
ghq get github.com/user/project    # Clone a repo
zz project                         # Jump to it
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
3. Each repo gets one zellij session (named `github.com.user.repo`)
4. Switch branches by opening new tabs and using `zz checkout`
