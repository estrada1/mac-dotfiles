# zsh interactive config, appended after ~/.config/shell/functions.sh.

bindkey -e  # Force emacs keybindings (prevent vi mode from EDITOR=vim)

################################################################################
# History
################################################################################
export HISTSIZE=50000
export SAVEHIST=100000
setopt APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_EXPIRE_DUPS_FIRST
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY
setopt EXTENDED_HISTORY

################################################################################
# Completion styles
################################################################################
setopt COMPLETE_IN_WORD
setopt AUTO_MENU
setopt ALWAYS_TO_END
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}── %d ──%f'
zstyle ':completion:*:warnings' format '%F{red}no matches%f'

################################################################################
# Shell init
################################################################################
# Source `<tool> init zsh`-style output from a cache file instead of eval'ing
# it, saving one fork per tool on every shell start. The cache header records
# the resolved binary (a nix store path), so upgrades regenerate it; the -nt
# check covers non-nix binaries replaced in place. No-op if the tool is absent.
_cached_init() {
  local bin="${commands[$1]}"
  [[ -n "$bin" ]] || return 0
  bin="${bin:A}"
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-init/$1.zsh" header=
  [[ -s "$cache" ]] && IFS= read -r header < "$cache"
  if [[ "$header" != "# $bin" || "$bin" -nt "$cache" ]]; then
    mkdir -p "${cache:h}"
    { print -r -- "# $bin"; command "$@"; } > "$cache"
  fi
  source "$cache"
}

_cached_init starship init zsh
_cached_init zoxide init zsh
_cached_init direnv hook zsh
_cached_init wt config shell init zsh
_cached_init try init "$HOME/tries"

# Syntax highlighting via zsh-patina (daemon-backed, replaces
# zsh-syntax-highlighting). launchd keeps the daemon alive; see flake.nix.
_cached_init zsh-patina activate

# Lazy-load heavy completions on first Tab press.
_lazy_completions_loaded=0
_load_lazy_completions() {
  if (( !_lazy_completions_loaded )); then
    _lazy_completions_loaded=1
    source <(jj util completion zsh)
    source <(just --completions zsh)
  fi
}
autoload -Uz add-zsh-hook
_lazy_comp_precmd() { compdef _load_lazy_completions jj just; add-zsh-hook -d precmd _lazy_comp_precmd; }
add-zsh-hook precmd _lazy_comp_precmd

# ESC-ESC prepends sudo (replaces oh-my-zsh sudo plugin)
_sudo_command_line() {
  [[ -z "$BUFFER" ]] && BUFFER=$(fc -ln -1) && zle accept-line && return
  if [[ "$BUFFER" == sudo\ * ]]; then
    LBUFFER="${LBUFFER#sudo }"
  else
    LBUFFER="sudo $LBUFFER"
  fi
}
zle -N _sudo_command_line
bindkey '\e\e' _sudo_command_line

# Ctrl-X Ctrl-E opens the current command line in $EDITOR
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

alias zrc="source ~/.zshrc"
alias brc="source ~/.zshrc"

[ -f ~/.zshrc.local ] && source ~/.zshrc.local
