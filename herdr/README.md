# herdr

Config for [Herdr](https://herdr.dev), the terminal workspace manager this host
uses in place of tmux.

Only hand-written files live here. Everything else Herdr keeps in
`~/.config/herdr` is runtime state it rewrites on its own — logs, sockets,
`session.json`, `plugins.json`, `release-notes.json` — and stays out of the
repo.

## Link

```bash
for f in config.toml start-claude.sh start-codex.sh; do
  ln -sfn "$HOME/dotfiles/herdr/$f" "$HOME/.config/herdr/$f"
done
```

Herdr rewrites `config.toml` itself when you change something in Settings. If
it ever writes a new file rather than editing in place it will replace the
symlink, and changes will stop reaching this repo without any error. Check with:

```bash
ls -la ~/.config/herdr/config.toml    # should print a '->' arrow
```

If it has become a regular file, copy it back over `herdr/config.toml` and
re-run the link loop above.

## Plugin

`plugins/tmux-tabs` is a submodule of
[clevere-msa/herdr-tmux-tabs](https://github.com/clevere-msa/herdr-tmux-tabs),
which gives Herdr tmux-style numbered tabs, `Ctrl-A ,` renaming and the
`Ctrl-A a` last-tab toggle. `config.toml` binds those through
`[[keys.command]]` entries.

The submodule is a pinned reference for a fresh machine. The working checkout
is `~/src/herdr-tmux-tabs`, and that is the path `herdr plugin link` registers:

```bash
git clone git@github.com:clevere-msa/herdr-tmux-tabs.git ~/src/herdr-tmux-tabs
herdr plugin link ~/src/herdr-tmux-tabs
```
