# bash interactive config, appended after ~/.config/shell/functions.sh.
# zsh is the login shell; this keeps bash usable when something drops into it.

export HISTSIZE=50000
export HISTFILESIZE=100000
export HISTCONTROL=ignoreboth:erasedups
export HISTTIMEFORMAT="%F %T "
shopt -s histappend
PROMPT_COMMAND="history -a;${PROMPT_COMMAND:-}"

# jj completions — lazy-loaded to avoid ~70ms startup cost
_jj_lazy_completion() {
  unset -f _jj_lazy_completion
  source <(jj util completion bash)
}
complete -F _jj_lazy_completion -o bashdefault -o default jj
eval "$(starship init bash)"
eval "$(zoxide init bash)"
eval "$(direnv hook bash)"
eval "$(wt config shell init bash)"
eval "$(try init ~/tries)"

alias bazel="bazelisk"
alias brc="source ~/.bashrc"

[ -f ~/.bashrc.local ] && source ~/.bashrc.local
