# bash_profile

if [ -f "$HOME/dotfiles/bash/sharedrc" ]; then
  . "$HOME/dotfiles/bash/sharedrc"
fi

# Source global definitions
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

. "$HOME/dotfiles/bash/startup_common"
