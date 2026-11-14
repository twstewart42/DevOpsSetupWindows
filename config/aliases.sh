# shellcheck shell=sh
# Sourced by bash and zsh via wsl-setup.sh
export EDITOR="vim"
alias k="kubectl"
alias kx="kubectx"
alias g="git"
alias ga="git add"
alias gb="git branch"
alias gbd="git branch -D"
alias gci="git commit"
alias gco="git checkout"
alias gp="git push"
alias gt="git tag"
alias docker="podman"
alias gpg2="gpg"
alias vzsh="vim $HOME/.zshrc && source $HOME/.zshrc"
alias tf="terraform"
alias tfdocs-make="terraform-docs markdown table --output-file README.md ."

function gbn(){
  git branch $1 && git checkout $1
}

export GPG_TTY=$(tty)
export HISTCONTROL=ignorespace
if test -f ~/.gnupg/.gpg-agent-info -a -n "$(pgrep gpg-agent)"; then
  # TODO: where does this 1489:1 come from?
  export GPG_AGENT_INFO=~/.gnupg/S.gpg-agent:1489:1
  GPG_TTY=$(tty)
  export GPG_TTY
else
   eval $(gpg-agent --daemon)
fi

