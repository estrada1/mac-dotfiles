# mac-dotfiles

A snapshot of how I set up a Mac for work: the tools I use, how they're
configured, and the reasons behind the choices that aren't obvious. It's
distilled from my multi-machine Nix dotfiles down to the macOS profile alone,
plus everything that profile shares with my Linux machines.

It is two things at once:

- **A reference.** This README is the whole setup in prose and tables. If you
  rebuild it without Nix, this page and the [`files/`](files) tree are all you
  need.
- **A working config.** [`flake.nix`](flake.nix) is a single-file nix-darwin +
  Home Manager system. `just apply` applies all of it.

```
flake.nix   the whole system: identity, packages, macOS defaults, Homebrew,
            launchd, shell, git, editor, tmux, agents
files/      raw config files, at the path they're deployed to under $HOME
justfile    apply / build / check / update / fmt
```

## Fresh Mac, in order

1. **Xcode Command Line Tools:** `xcode-select --install`. They provide the C
   compiler (Apple clang) that nvim-treesitter uses; Nix deliberately ships none.
2. **Homebrew** from brew.sh. nix-darwin drives Homebrew but doesn't install it.
3. **Nix** (upstream or Determinate installer). nix-darwin is told *not* to
   manage Nix itself (`nix.enable = false`).
4. Edit the `identity` block at the top of `flake.nix` (account short name, git
   name/email), and the `features` switches if needed.
5. `just apply`. The first run bootstraps `darwin-rebuild`.
6. Grant the permissions listed under [Permissions](#permissions-tcc-checklist)
   below, then quit and reopen Rectangle, Ghostty and Hammerspoon.

## Design rules

- **CLI tools come from Nix, GUI apps from Homebrew casks.** macOS ties
  permission grants (Accessibility, Microphone, Input Monitoring) to an app's
  path and code signature. A Nix store path changes with every update, so
  every update would lose the grants. Casks live at a stable `/Applications`
  path.
- **Nix wins PATH.** `brew shellenv` prepends `/opt/homebrew/bin`, which
  quietly shadows every tool both provide. `~/.zprofile` runs it, then moves
  the Nix profile dirs back to the front. Brews are limited to things nixpkgs
  doesn't cover as well.
- **Homebrew activation is additive and offline.** No auto-update, no implicit
  upgrade, `cleanup = "none"` until the lists are proven complete (then
  `"uninstall"`, never `"zap"`).
- **Login Items, not launchd, for GUI apps that need permissions.** A launchd
  agent makes macOS attribute the app's permissions to launchd, so the app's
  own grants don't apply. Ghostty and Voxtype are registered as Login Items;
  Hammerspoon uses its own `autoLaunch`.
- **Local state stays local.** Bookmarks, work shell variables and agent
  config are seeded or symlinked out of the store and are not tracked here:
  `~/.config/shell/work`, `~/.zshrc.local`, `~/.config/lnks/bookmarks.txt`,
  `~/.config/gcal/calendars`.
- **The Mac mirrors a tiling-WM workflow.** Most of the hotkeys below are
  translations of a sway setup: vim-direction keys everywhere, no title bars,
  tabs and splits in tmux instead of the terminal.

## macOS system settings

| Setting | Value | Why |
|---|---|---|
| Key repeat | `InitialKeyRepeat = 15`, `KeyRepeat = 2` | Faster than the Settings UI allows |
| Press-and-hold accents | off (`ApplePressAndHoldEnabled = false`) | Held keys repeat in every text field |
| Appearance | Dark | |
| Dock | autohide | |
| Finder | column view | |
| Trackpad | tap to click, three-finger drag | Three-finger drag is buried in Accessibility > Pointer Control |
| Caps Lock | Esc (tap) / Cmd (hold) via kanata; plain Esc via native remap when kanata is off | Never both: the native remap would collapse kanata's tap/hold |
| Default video player | mpv, bound per UTI with `duti` | `public.movie` alone leaves .mp4/.mov with QuickTime |
| `/etc/zshrc`, `/etc/zshenv` | managed by nix-darwin | Login shells get the system profile |

Hostname is deliberately left unset, so applying the config never renames a
machine.

## Keyboard map

One modifier scheme per layer, chosen so they don't collide:

| Layer | Modifier | Owner |
|---|---|---|
| Window snapping | Ctrl+Opt | Rectangle |
| Window focus / move | Ctrl+Cmd (+Shift) | Hammerspoon |
| Spaces, hints, Exposé | Ctrl+Opt+Cmd ("hyper", = holding Tab) | Hammerspoon |
| Terminal multiplexing | Alt | tmux |
| Global new terminal | Cmd+Shift+Enter | Ghostty |

**Kanata** (`files/.config/kanata/kanata.kbd`). Only two dual-role keys:

| Key | Tap | Hold |
|---|---|---|
| Caps | Esc | Cmd |
| Tab | Tab | Ctrl+Opt+Cmd |

`tap-hold-press` picks the hold action as soon as another key goes down, so a
quick Tab+l acts as the chord rather than typing Tab then l.

**Rectangle** (Ctrl+Opt +):

| Key | Action | Key | Action |
|---|---|---|---|
| h / j / k / l | left / bottom / top / right half | u / i | top-left / top-right corner |
| Return | maximize | m / , | bottom-left / bottom-right corner |
| c | center | | |

Corners are on u/i/m/, (a 2x2 grid on the keyboard) because Rectangle's Todo
mode holds N and B.

**Hammerspoon** (`files/.hammerspoon/init.lua`):

| Keys | Action |
|---|---|
| Ctrl+Cmd + h/j/k/l | Focus nearest window in that direction |
| Ctrl+Opt+Cmd + h/l | Previous / next Space (replays Mission Control's Ctrl+Arrow) |
| Ctrl+Cmd+Shift + h/l | Throw window to previous / next Space (title-bar drag trick; no working API since macOS 14.5) |
| Ctrl+Cmd+Shift + j/k | Throw window to the display on the left / right |
| Ctrl+Opt + Space | Tile all windows on the current screen |
| Ctrl+Opt+Cmd + Space | Window hints: one home-row letter per window |
| Ctrl+Opt+Cmd + E | Exposé across all Spaces |

Window animations are off (`hs.window.animationDuration = 0`). "Move
left/right a space" must stay enabled under Keyboard Shortcuts > Mission
Control, because the Space binds rely on it.

**Ghostty**: `Cmd+Shift+Enter` (global) opens a new window from anywhere.
Ghostty starts at login with no window and stays running after its last window
closes, so the hotkey always has a process to receive it. `Cmd+Enter` was
avoided because a global binding steals it from every app.
`ctrl+shift+space` / `k` / `l` dump screen / scrollback / selection (with ANSI
colours) into a file and open it; `ctrl+shift+d` / `u` page down / up.

**tmux** (prefix `C-a`, secondary `C-Space`; everything below is prefix-less):

| Keys | Action |
|---|---|
| Alt + h/j/k/l | Select pane; Alt+Shift resizes by 5 |
| Alt + _ / - | Split side-by-side / stacked |
| Alt + x / z | Kill / zoom pane |
| Alt + c / n / p / 1–6 | New / next / prev / jump to window |
| Alt + r / $ | Rename window / session |
| Alt + s / C | Session picker (sessionx + zoxide) / new session |
| Alt + Space | Copy mode (vi keys, `y` → pbcopy) |
| Alt + t | tmux-thumbs hint-copy |
| Alt + e | Open the pane's scrollback in a read-only nvim popup |
| Alt + B / R | Toggle status bar / reload config |
| prefix Space | easy-motion |

Windows and panes are numbered from 1, renumber on close, mouse is on,
100k-line history, Nord theme with a highlighted active window.

**zsh**: emacs keymap; `Esc Esc` adds or removes a leading `sudo` (on an empty
line, re-runs the last command with it); `Ctrl-X Ctrl-E` edits the command
line in `$EDITOR`.

## Packages

**From Nix** (CLI tools, all pinned by `flake.lock`; the AI tools and a few
fast-moving CLIs track nixpkgs-unstable):

| Area | Tools |
|---|---|
| Files & search | ripgrep, fd, fzf, bat, eza, zoxide, yazi (+ glow, ffmpegthumbnailer), dust, duf, diskus, sd, jq |
| Git | git (+ lfs), gh, jujutsu, delta, tig, worktrunk (`wt`) |
| Shell | zsh, starship, zsh-patina, direnv + nix-direnv, try (`~/tries`), just, gum |
| System | btop, fastfetch, tokei, miniserve, speedtest-cli, cloudflared |
| Editor | neovim (LazyVim), tree-sitter, nodejs, marksman, lua-language-server, nil, stylua |
| Python | python3, uv, ruff |
| Formatters / linters | shfmt, nixfmt, statix, prettierd |
| Media | ffmpeg, mpv, yt-dlp |
| AI agents | claude-code, codex, github-copilot-cli (+ `hcopilot` wrapper), herdr, tuicr, mcp-nixos |
| Misc | basalt (TUI Obsidian viewer), `gcal-agenda`, `lnks` |

**Homebrew casks**: ghostty, alacritty, hammerspoon, rectangle, alt-tab,
voxtype, obsidian, bitwarden, JetBrains Mono and Sauce Code Pro Nerd Fonts.

**Homebrew brews**: cargo-binstall, htop, libomp, poppler, rbenv, sox, unbound,
vifm, wget.

## Shell

zsh is the login shell; bash gets the same functions and aliases.

- **Fast startup.** `tool init zsh` output (starship, zoxide, direnv, wt, try,
  zsh-patina) is cached to a file, and the cache is regenerated only when the
  resolved binary changes. `compinit` rebuilds its dump at most once a day.
  jj and just completions load on first use.
- **zsh-patina** handles syntax highlighting through a daemon, which stays
  fast where zsh-syntax-highlighting re-highlights the whole line on every
  keystroke. A launchd agent keeps the daemon alive, because the cached
  `activate` never restarts it.
- Plugins: autosuggestions, history-substring-search. History: 50k in memory,
  100k saved, shared between sessions, timestamped, no duplicates, and
  space-prefixed commands are not saved.
- **Aliases:** `ls/ll/la/lt/tree` → eza, `g` git, `j` just, `y` yazi, `jap`
  just apply, `hm` home-manager, `mserve` miniserve, `urp` uv run poe.
- **Functions** (`files/.config/shell/functions.sh`):

  | Function | What it does |
  |---|---|
  | `fkill` | fzf process killer |
  | `ywd` | Copy the working directory (OSC 52 over SSH) |
  | `gselect` | fzf `git add` |
  | `gworktree <name>` | Dated worktree on branch `$GIT_BRANCH_PREFIX/<name>` |
  | `recent_branches` | Ten most recently committed branches |
  | `gconf` | Show the effective git identity |
  | `gh_alt` | Run a command under `$GH_ALT_TOKEN` |
  | `backup_branch` | Branch the current HEAD as `backup/<date>/<branch>` |
  | `today` / `tstamp` | Date stamps for file names |

- `~/.config/shell/work` (untracked) holds anything specific to the employer,
  such as `GIT_BRANCH_PREFIX`, internal hosts or tokens.

## Git & jujutsu

```
push.default = current      pull.rebase = true       fetch.prune = true
rebase.autoStash = true     rerere.enabled = true    merge.conflictStyle = diff3
diff.algorithm = patience   diff.colorMoved = default
column.ui = auto            branch.sort = -committerdate
```

- `gh auth git-credential` is the credential helper for github.com and
  gist.github.com.
- delta is the pager: navigate on, line numbers on, unified view.
- jj uses git-style conflict markers (the same as diff3) and git-format diffs
  piped through delta.
- tig: `H` copies the short hash and shows a notification.

## Neovim

LazyVim, with lazy.nvim bootstrapped from `init.lua`. The plugin lockfile is
not managed, so lazy.nvim can write it (`files/.config/nvim/lazy-lock.json` is
a point-in-time copy).

- **Extras:** python, yaml, nix, json, toml, markdown, prettier, copilot +
  copilot-chat, dial.
- **Added plugins:** nvim-surround, baleia (ANSI colours), urlview
  (`<leader>su`), render-markdown (adds a `[/]` in-progress checkbox),
  markdown-table-wrap (reader-mode previews for tables), bullets.vim,
  icon-picker (`<leader>si`), no-neck-pain (`<leader>uc`, width 100).
- **LSPs and formatters come from Nix, not mason:** marksman, lua_ls, ruff,
  nil, stylua. Markdownlint diagnostics are off.
- The clipboard is the system clipboard (`unnamedplus`), via OSC 52 over SSH.
- **Custom keymaps** (`files/.config/nvim/lua/config/keymaps.lua`):

  | Keys | Action |
  |---|---|
  | `<leader>ml` | Paste the clipboard URL as a markdown link with the page's title |
  | `<leader>mt` | Cycle a checkbox `[ ]` → `[/]` → `[x]` (visual mode works on several lines; `<Tab>` does the same inside `todo/`) |
  | `<leader>cs` | Split a one-line shell command into one flag per line |
  | `<leader>cp` | Copy the file path |
  | `Alt+h` / `Alt+l` | Indent left / right |

## Terminal & TUIs

- **Ghostty** (`files/.config/ghostty/config`): Nix zsh as a login shell, no
  title bar, block cursor with no blink, copy on select, no confirmation on
  close or on multi-line paste. `Alt+←/→` moves by word.
- **yazi**: newest files first, size line mode, git status column, markdown
  previewed with glow. Keys: `!` opens a shell here, `y` / `C-y` also copy the
  paths, `gn` opens Finder, `gs` serves the directory with miniserve, `gz`
  zips the selection, `S` copies an scp command (over SSH), `T` maximizes the
  preview.
- **herdr**: prefix `ctrl+a`; Alt+Shift+j/k switches agents.
- **tuicr**: nvim as editor, unified diffs, whitespace changes kept visible.
- **lnks**: fzf picker over `~/.config/lnks/*.txt` (`Name URL` per line),
  opened with `open`.
- **gcal-agenda**: today's and tomorrow's events from the iCal URLs in
  `~/.config/gcal/calendars` (`--json` for status bars).

## AI agents

- Claude Code, Codex and Copilot CLI come from nixpkgs-unstable.
- `CLAUDE_CODE_CERT_STORE=bundled,system`: nixpkgs defaults Claude Code to the
  OS certificate store only, so this adds its bundled public roots back while
  keeping the system (corporate) roots.
- Shared instructions, settings and skills can live in a separate repo: set
  `agentfilesRepo` in `flake.nix` to its git URL (it's `null`, meaning off, by
  default). It's cloned to `~/agentfiles` and symlinked outside the Nix store
  (`~/.claude/{CLAUDE.md,settings.json,statusline-command.sh}`,
  `~/.codex/instructions.md`). Every `common/skills/*/SKILL.md` is linked into
  `~/.claude/skills`, `~/.codex/skills` and `~/.copilot/skills/custom`.
- `hcopilot` runs Copilot's bundled node entry point directly with
  auto-update off, so herdr can use it.

## Dictation (Voxtype)

Push-to-talk on **Fn**, local Whisper `base.en`, voice-activity detection on,
text typed at the cursor (clipboard fallback), filler words removed. The
vocabulary prompt and replacement rules
(`files/Library/Application Support/voxtype/vocabulary.toml`) fix the tool
names Whisper keeps getting wrong. The cask ships a CLI;
`voxtype setup app-bundle` builds the `/Applications` bundle that holds the
Microphone and Accessibility grants.

## Permissions (TCC) checklist

| App | Grant | Notes |
|---|---|---|
| Hammerspoon | Accessibility | |
| Ghostty | Accessibility | For the `global:` keybind |
| Rectangle | Accessibility | |
| AltTab | Accessibility, Screen Recording | |
| Voxtype | Microphone, Accessibility, Input Monitoring | Prompts on first launch |
| kanata | Input Monitoring | Bound to its Nix store path, so re-grant after each kanata update |
| Karabiner DriverKit | Approve the system extension | Install Karabiner-DriverKit-VirtualHIDDevice from its GitHub releases, then `sudo …/Karabiner-VirtualHIDDevice-Manager activate` |
| Terminal running `just apply` | Automation → System Events | Used to add Login Items, once |

Clear any Caps Lock remap under Keyboard > Modifier Keys before turning on
kanata. That pane's remap is per keyboard and would win over kanata.

## Changes from the Linux originals

This snapshot is macOS-only, so shared configs were trimmed or ported:

- Clipboard calls use `pbcopy` (tmux copy mode, tmux-thumbs, tig, yazi, `ywd`)
  instead of `wl-copy`; tig notifies through `osascript`.
- `fkill` uses BSD `ps` flags.
- yazi's "open file manager" opens Finder; the Wayland drag-and-drop and paste
  bindings are gone.
- Dropped as Linux-only: sway, waybar, Wayland screen recording, the systemd
  `sites` helper, and the nixGL/GPU workarounds.
- Dropped as personal-only: the personal git identity, the identity-switching
  script, and the personal machine names in the dictation vocabulary.
