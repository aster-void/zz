# zz

ghq + zellij with fuzzy finder

## Usage

```bash
zz [query]        # Select repo from ghq list → zellij session
zz get <url>      # Clone repo (alias for ghq get)
zz list, ls       # List active zz sessions
zz delete, d [q]  # Delete zellij session
zz delete-all, da # Delete all zz sessions
zz -h, --help     # Show help
```

## Dependencies

- [ghq](https://github.com/x-motemen/ghq)
- [fzf](https://github.com/junegunn/fzf)
- [zellij](https://github.com/zellij-org/zellij)

## Examples

```bash
zz get https://github.com/user/project   # Clone repo
zz                                       # Select repo → zellij session
zz project                               # Filter by "project"
zz ls                                    # List zz sessions
zz d project                             # Delete session
```
