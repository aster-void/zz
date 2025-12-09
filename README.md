# zz

A wrapper around [ghq](https://github.com/x-motemen/ghq), [fzf](https://github.com/junegunn/fzf), and [zellij](https://github.com/zellij-org/zellij) for quick repository navigation.

## Usage

```bash
zz              # Fuzzy-find repo with fzf
zz <query>      # Jump to first matching repo
zz -h, --help   # Show help
```

## Dependencies

- [ghq](https://github.com/x-motemen/ghq)
- [fzf](https://github.com/junegunn/fzf)
- [zellij](https://github.com/zellij-org/zellij)
- [ripgrep](https://github.com/BurntSushi/ripgrep)
- [awk](https://www.gnu.org/software/gawk/) (usually pre-installed)

## What it does

1. Lists repositories managed by `ghq`
2. Filters with `fzf` (interactive or query-based)
3. Attaches to existing zellij session or creates a new one with the repo as working directory
