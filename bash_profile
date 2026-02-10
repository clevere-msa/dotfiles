# bash_profile

# exit non-interactive shell now
if [[ $- != *i* ]]; then
  return
fi

# Source global definitions
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

. "$HOME/dotfiles/bash/startup_common"
