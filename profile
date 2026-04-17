case $- in
  *i*)
    # Interactive session. Try switching to bash.
    if [ -z "$BASH" ]; then # do nothing if running under bash already
      bash=$(command -v bash)
      if [ -x "$bash" ]; then
        exec env SHELL="$bash" bash --login
      fi
    fi
esac

if [ -f "$HOME/mcp_bootstrap/bin/env" ]; then
  . "$HOME/mcp_bootstrap/bin/env"
fi

if [ -f "$HOME/.local/bin/env" ]; then
  . "$HOME/.local/bin/env"
fi

if [ -f "$HOME/dotfiles/bash/secret-env.sh" ]; then
  . "$HOME/dotfiles/bash/secret-env.sh"
fi
