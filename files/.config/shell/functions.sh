# Shared functions sourced by both zsh and bash.

# Interactive process killer with fzf. BSD ps: -m sorts by memory.
fkill() {
  local sig="${1:--15}"
  local pid_list
  pid_list=$(
    ps aux -m |
    awk 'BEGIN {OFS="\t"}
      NR==1 {next}
      { printf "\033[1;33m%s\033[0m\t\033[36m%s\033[0m\t\033[32m%5.1f%%\033[0m\t\033[35m%5.1f%%\033[0m\t%s\n",
        $2, $1, $3, $4, substr($0, index($0,$11)) }' |
    fzf --ansi --multi \
        --header=$'PID\tUSER\tCPU\tMEM\tCOMMAND' \
        --header-lines=0 \
        --preview='ps -p {1} -o pid=,ppid=,user=,%cpu=,%mem=,etime=,stat=,args= | fold -s -w $FZF_PREVIEW_COLUMNS' \
        --preview-window=down:3:wrap \
        --prompt='kill › ' \
        --pointer='▶' \
        --marker='✓' |
    awk '{print $1}'
  )
  [[ -z "$pid_list" ]] && return 0
  echo "$pid_list" | while read -r pid; do
    printf '\033[1;31m killing\033[0m %s (%s)\n' "$pid" "$(ps -p "$pid" -o comm= 2>/dev/null)"
    kill "$sig" "$pid" 2>/dev/null
  done
}

# Yank working directory to clipboard: OSC 52 over SSH, pbcopy locally.
ywd() {
  local dir="${PWD:-$(pwd)}"
  if [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_TTY:-}" ]]; then
    printf '\033]52;c;%s\a' "$(printf '%s' "$dir" | base64 | tr -d '\r\n')"
    return
  fi
  printf '%s' "$dir" | pbcopy
}

# Run a command with an alternate GitHub token without changing `gh auth`.
gh_alt() {
  if [[ -z "${GH_ALT_TOKEN:-}" ]]; then
    printf 'gh_alt: set GH_ALT_TOKEN first\n' >&2
    return 1
  fi

  if [[ "$#" -eq 0 ]]; then
    printf 'usage: gh_alt <command> [args...]\n' >&2
    return 2
  fi

  GH_TOKEN="$GH_ALT_TOKEN" GITHUB_TOKEN="$GH_ALT_TOKEN" "$@"
}

# Interactively select unstaged files to git add (Tab to multi-select, Enter to confirm)
gselect() {
  local files
  files=$(git diff --name-only | fzf -m --preview 'git diff --color {}')
  [[ -n "$files" ]] && echo "$files" | xargs git add && git status -s
}

# Create a git worktree with a date-prefixed directory (YYYY_MM_DD_<name>) and
# branch <prefix>/<name>. The prefix defaults to $USER — set GIT_BRANCH_PREFIX
# (e.g. in ~/.config/shell/work) where the account name isn't what you push as.
gworktree() {
  local name="$1"
  local dir="../$(date +%Y_%m_%d)_${name}"
  git worktree add "$dir" -b "${GIT_BRANCH_PREFIX:-$USER}/$name" && cd "$dir"
}

# Show 10 most recently committed local branches
recent_branches() {
  git for-each-ref --color=always --sort=-committerdate refs/heads \
    --format='%(if)%(HEAD)%(then)%(color:bold green)*%(color:reset) %(else)  %(end)%(color:yellow)%(align:16,left)%(committerdate:relative)%(end)%(color:reset) %(color:cyan)%(align:35,left)%(refname:short)%(end)%(color:reset) %(color:green)%(objectname:short)%(color:reset) %(contents:subject)' |
    head -10
}

# Show key git config values with color
gconf() {
  local reset='\033[0m'
  local keyc='\033[1;36m'   # cyan
  local valc='\033[1;33m'   # yellow
  local miss='\033[0;90m'   # gray

  local name email pager

  name="$(git config --get user.name)"
  email="$(git config --get user.email)"
  pager="$(git config --get core.pager)"

  printf "${keyc}user.name ${reset} ${valc}%s${reset}\n" "${name:-${miss}<unset>${reset}}"
  printf "${keyc}user.email${reset} ${valc}%s${reset}\n" "${email:-${miss}<unset>${reset}}"
  printf "${keyc}core.pager${reset} ${valc}%s${reset}\n" "${pager:-${miss}<unset>${reset}}"
}

# Date shortcuts for file operations
today() { date +%Y-%m-%d; }
tstamp() { date +%Y-%m-%d_%H-%M-%S; }

alias backup_branch='git branch backup/$(date +%F)/$(git rev-parse --abbrev-ref HEAD)'
alias y="yazi"
alias mserve="miniserve -u"
alias urp="uv run poe" # task runner inside uv envs
alias g="git"
alias j="just"

export EDITOR="vim"
export PATH="$HOME/.local/bin:$PATH"

# Machine-local, untracked additions (work hostnames, tokens, GIT_BRANCH_PREFIX).
[ -r "$HOME/.config/shell/work" ] && . "$HOME/.config/shell/work"
