{
  # A work Mac, end to end, in one file: nix-darwin for the system layer and an
  # embedded Home Manager generation for the user. One `darwin-rebuild switch`
  # applies both. Raw config files live under ./files at the path they are
  # deployed to relative to $HOME; everything expressible as Nix is inline here.
  #
  # Sections, in order:
  #   1. identity + feature switches   (the only things to edit for a new Mac)
  #   2. packages / overlays
  #   3. system layer   — macOS defaults, keyboard, Homebrew, kanata, Rectangle
  #   4. user layer     — shell, git/jj, editor, terminal, tmux, yazi, agents,
  #                       macOS apps (Ghostty, Hammerspoon, Voxtype, mpv)
  description = "Work Mac — nix-darwin + Home Manager in one flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    try.url = "github:tobi/try-cli";
    yazi-plugins = {
      url = "github:yazi-rs/plugins";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      nix-darwin,
      try,
      yazi-plugins,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      system = "aarch64-darwin";

      # ══ 1. Identity + feature switches ══════════════════════════════════════
      identity = {
        username = "me"; # macOS short name of the account (`id -un`)
        gitName = "Your Name";
        gitEmail = "you@example.com";
      };

      # Git URL of a repo holding shared Claude Code / Codex / Copilot config
      # (cloned to ~/agentfiles and symlinked in). null skips the clone and the
      # symlinks entirely.
      agentfilesRepo = null;

      features = {
        # Caps = Esc/Cmd, Tab = Tab/Hyper. Needs the Karabiner DriverKit
        # extension and an Input Monitoring grant (see README "Permissions").
        # When off, Caps Lock → Escape comes from the native macOS remap.
        kanata = true;
        # Push-to-talk dictation (Voxtype cask + Login Item).
        voxtype = true;
      };

      # ══ 2. Packages ═════════════════════════════════════════════════════════
      # Taken from nixpkgs-unstable so they track upstream faster than the
      # release channel. Missing names are skipped rather than failing eval.
      unstablePkgs = [
        "claude-code"
        "jujutsu"
        "codex"
        "yazi"
        "yt-dlp"
        "direnv"
        "kanata"
        "herdr"
        "tuicr"
      ];

      unfreeNames = [
        "claude-code"
        "github-copilot-cli"
        "codex"
      ];

      pkgs =
        let
          allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) unfreeNames;
          unstable = import nixpkgs-unstable {
            inherit system;
            config = { inherit allowUnfreePredicate; };
          };
          overlay =
            _final: _prev:
            lib.genAttrs (lib.filter (n: unstable ? ${n}) unstablePkgs) (n: unstable.${n})
            // lib.optionalAttrs (unstable ? github-copilot-cli) {
              github-copilot-cli = unstable.github-copilot-cli.overrideAttrs {
                doInstallCheck = false; # upstream version-check broken (EACCES in SEA extraction)
              };
            };
        in
        import nixpkgs {
          inherit system;
          config = { inherit allowUnfreePredicate; };
          overlays = [ overlay ];
        };

      tryPackage = try.packages.${system}.default or null;
      voxtypeDir = ./files + "/Library/Application Support/voxtype";

      # ══ 3. System layer (nix-darwin) ════════════════════════════════════════
      darwinModule =
        { config, ... }:
        {
          system.stateVersion = 7;
          system.primaryUser = identity.username;
          users.users.${identity.username} = {
            name = identity.username;
            home = "/Users/${identity.username}";
          };

          # Nix itself stays owned by its installer (upstream or Determinate).
          # Handing nix.conf and the daemon to nix-darwin is the most disruptive
          # step of a migration and nothing below needs it. Flakes are enabled
          # per-user in ~/.config/nix/nix.conf (user layer).
          nix.enable = false;

          # nix-darwin owns /etc/zshrc + /etc/zshenv so login shells get the
          # system profile; interactive config comes from Home Manager.
          programs.zsh.enable = true;

          system.keyboard = {
            enableKeyMapping = true;
            # Kanata handles Caps itself; both remapping it collapses kanata's
            # tap/hold into a plain Escape.
            remapCapsLockToEscape = !features.kanata;
          };

          system.defaults = {
            NSGlobalDomain = {
              # Held keys repeat instead of opening the accent popup.
              ApplePressAndHoldEnabled = false;
              # Units of 15ms; both below the fastest the Settings UI offers.
              InitialKeyRepeat = 15;
              KeyRepeat = 2;
              AppleInterfaceStyle = "Dark";
            };
            dock.autohide = true;
            finder.FXPreferredViewStyle = "clmv"; # column view
            trackpad = {
              Clicking = true; # tap to click
              TrackpadThreeFingerDrag = true; # Accessibility > Pointer Control
            };

            # Rectangle: vim-style snapping on Ctrl+Opt. Keys set by hand in
            # Rectangle's own prefs are left alone. Quit and reopen Rectangle
            # after the first apply so it re-reads them.
            #   h/j/k/l  halves        u/i/m/,  corners (2x2 grid on the keyboard)
            #   Return   maximize      c        center
            CustomUserPreferences."com.knollsoft.Rectangle" =
              let
                ctrlOpt = 262144 + 524288; # Carbon modifier masks
                bind = keyCode: {
                  inherit keyCode;
                  modifierFlags = ctrlOpt;
                };
              in
              {
                leftHalf = bind 4; # h
                bottomHalf = bind 38; # j
                topHalf = bind 40; # k
                rightHalf = bind 37; # l
                topLeft = bind 32; # u
                topRight = bind 34; # i
                bottomLeft = bind 46; # m
                bottomRight = bind 43; # ,
                maximize = bind 36; # Return
                center = bind 8; # c
              };
          };

          # Homebrew stays the installer for GUI apps: macOS binds TCC
          # permission grants (Accessibility, Microphone, Input Monitoring) to a
          # stable /Applications path and code signature, which a churning
          # /nix/store path would lose on every update. CLI tools come from Nix;
          # brews are only what nixpkgs doesn't cover as well.
          homebrew = {
            enable = true;
            # Activation is fast and offline-safe; upgrade deliberately with
            # `brew upgrade`. Switch cleanup to "uninstall" once the lists are
            # proven complete — never "zap", which also deletes app data.
            onActivation = {
              autoUpdate = false;
              upgrade = false;
              cleanup = "none";
            };
            # brew shellenv runs from ~/.zprofile instead (user layer), which
            # has to re-prepend Nix right after it anyway.
            enableZshIntegration = false;

            taps = lib.optionals features.voxtype [ "peteonrails/voxtype" ];
            brews = [
              "cargo-binstall" # prebuilt-binary installer for cargo crates
              "htop" # nixpkgs side ships btop
              "libomp" # OpenMP runtime for prebuilt Python/ML wheels
              "poppler" # pdftotext and friends
              "rbenv" # Ruby version manager
              "sox" # audio conversion/effects CLI
              "unbound" # local validating DNS resolver
              "vifm" # vi-style file manager
              "wget"
            ];
            casks = [
              "alacritty" # backup terminal
              "alt-tab" # Windows-style per-window Alt+Tab switcher
              "bitwarden"
              "ghostty" # primary terminal
              "hammerspoon" # window focus/hints/Spaces hotkeys
              "obsidian"
              "rectangle" # window snapping
              "font-jetbrains-mono-nerd-font"
              "font-sauce-code-pro-nerd-font"
            ]
            ++ lib.optionals features.voxtype [ "voxtype" ];
          };

          # ── Kanata (root launchd daemon) ──
          # Prerequisites, done once by hand: install
          # Karabiner-DriverKit-VirtualHIDDevice, activate it, approve the
          # system extension, grant Input Monitoring to the kanata binary
          # (re-grant after each kanata update — the grant is bound to its
          # store path), and clear any Caps remap under Keyboard > Modifier Keys.
          environment.systemPackages = lib.optionals features.kanata [ pkgs.kanata ];
          environment.etc = lib.mkIf features.kanata {
            "kanata/kanata.kbd".source = ./files/.config/kanata/kanata.kbd;
          };
          launchd.daemons = lib.mkIf features.kanata {
            # The driver's user-space half; kanata emits keys through it.
            karabiner-vhid-daemon.serviceConfig = {
              ProgramArguments = [
                "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
              ];
              KeepAlive = true;
              RunAtLoad = true;
              ProcessType = "Interactive";
            };
            kanata.serviceConfig = {
              ProgramArguments = [
                "${pkgs.kanata}/bin/kanata"
                "--cfg"
                "/etc/kanata/kanata.kbd"
              ];
              KeepAlive = true;
              RunAtLoad = true;
              StandardErrorPath = "/var/log/kanata.log";
              StandardOutPath = "/var/log/kanata.log";
            };
          };

          assertions = [
            {
              assertion = !(features.kanata && config.system.keyboard.remapCapsLockToEscape);
              message = "kanata and the native Caps Lock remap must not both be on.";
            }
          ];
        };

      # ══ 4. User layer (Home Manager) ════════════════════════════════════════
      homeModule =
        { config, lib, ... }:
        let
          link = config.lib.file.mkOutOfStoreSymlink;
          agentfiles = "${config.home.homeDirectory}/agentfiles";

          # Herdr-compatible Copilot wrapper: runs Copilot's bundled node entry
          # point directly, as `copilot`, with auto-update off.
          hcopilot = pkgs.writeShellScriptBin "hcopilot" ''
            set -euo pipefail
            real_copilot="${pkgs.github-copilot-cli}/bin/copilot"
            node="$(${pkgs.binutils}/bin/strings "$real_copilot" | ${pkgs.gnugrep}/bin/grep -m1 -E '^/nix/store/.*/bin/node$' || true)"
            entry="$(${pkgs.binutils}/bin/strings "$real_copilot" | ${pkgs.gnugrep}/bin/grep -m1 -E '/github-copilot-cli/index\.js$' || true)"
            ssl_dir="$(${pkgs.binutils}/bin/strings "$real_copilot" | ${pkgs.gnugrep}/bin/grep -m1 -E '^/nix/store/.*/etc/ssl/certs$' || true)"
            if [[ -z "$node" || -z "$entry" ]]; then
              echo "hcopilot: could not find node/index.js inside $real_copilot" >&2
              exit 127
            fi
            export NODE_NO_WARNINGS="''${NODE_NO_WARNINGS:-1}"
            if [[ -n "$ssl_dir" && -z "''${SSL_CERT_DIR:-}" ]]; then
              export SSL_CERT_DIR="$ssl_dir"
            fi
            exec -a copilot "$node" "$entry" --no-auto-update "$@"
          '';

          gcal-agenda = pkgs.writeShellScriptBin "gcal-agenda" ''
            exec ${
              pkgs.python3.withPackages (ps: [
                ps.icalendar
                ps.recurring-ical-events
              ])
            }/bin/python3 ${./files/.config/gcal/gcal-agenda.py} "$@"
          '';

          tmux-easy-motion = pkgs.tmuxPlugins.mkTmuxPlugin {
            pluginName = "tmux-easy-motion";
            version = "2025-07-11";
            src = pkgs.fetchFromGitHub {
              owner = "IngoMeyer441";
              repo = "tmux-easy-motion";
              rev = "8dfe8aee14c938ec170b3f98ca341055cc960d06";
              hash = "sha256-Nxo8fWwgX79CrhUrHhfv8+mz3aUvPAbGmQkY34PQzKo=";
            };
            rtpFilePath = "easy_motion.tmux";
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postInstall = ''
              for f in "$out/share/tmux-plugins/tmux-easy-motion"/*.tmux; do
                wrapProgram "$f" --prefix PATH : "${pkgs.python3}/bin"
              done
            '';
          };

          # Current tmux pane → read-only nvim popup (flash.nvim motions, ANSI
          # colours rendered by baleia).
          pane-nvim = pkgs.writeShellScript "tmux-pane-nvim" ''
            tmp=$(mktemp /tmp/tmux-nvim-XXXXXX)
            ${pkgs.tmux}/bin/tmux capture-pane -p -S - -E - -e > "$tmp"
            nvim -R "$tmp" \
              -c 'set noreadonly' \
              -c 'lua require("baleia").setup({ line_starts_at = 1, async = false }).once(vim.api.nvim_get_current_buf())' \
              -c 'normal G' \
              -c 'set readonly nonumber norelativenumber signcolumn=no nomodified' \
              -c 'nnoremap <buffer> q <cmd>set nomodified<bar>q!<cr>' \
              -c 'nnoremap <buffer> <Esc> <cmd>set nomodified<bar>q!<cr>'
            rm -f "$tmp"
          '';

          # Register an /Applications bundle as a Login Item (not a launchd
          # agent: TCC would attribute Microphone/Accessibility to launchd, not
          # the app) and start it if it isn't running. Idempotent.
          loginItem = name: process: ''
            if [ -d /Applications/${name}.app ]; then
              if ! /usr/bin/osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | grep -q "${name}"; then
                run /usr/bin/osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/${name}.app", hidden:true}' \
                  || warnEcho "could not add ${name} to Login Items; add it under System Settings > General > Login Items"
              fi
              if ! /usr/bin/pgrep -f ${process} >/dev/null 2>&1; then
                run /usr/bin/open -a ${name} || true
              fi
            else
              warnEcho "/Applications/${name}.app not found (installed by its Homebrew cask)"
            fi
          '';
        in
        lib.mkMerge [
          {
            home.username = identity.username;
            home.homeDirectory = "/Users/${identity.username}";
            home.stateVersion = "25.11";
            news.display = "silent";
            programs.home-manager.enable = true;

            # ── Packages ──
            # No C compiler: Apple clang from the Xcode Command Line Tools is what
            # nvim-treesitter picks up (`xcode-select --install`).
            home.packages = [
              # search / files
              pkgs.ripgrep
              pkgs.fd
              pkgs.bat
              pkgs.eza
              pkgs.zoxide
              pkgs.diskus
              pkgs.duf
              pkgs.dust
              pkgs.sd
              pkgs.jq
              pkgs.glow # markdown renderer; yazi's .md previewer
              pkgs.ffmpegthumbnailer # yazi video thumbnails
              # git
              pkgs.gh
              pkgs.tig
              pkgs.worktrunk # git worktree manager (wt)
              pkgs.git-lfs
              # shell / system
              pkgs.starship
              pkgs.zsh-patina # daemon-backed syntax highlighting
              pkgs.btop
              pkgs.fastfetch
              pkgs.gum
              pkgs.just
              pkgs.tokei
              pkgs.miniserve
              pkgs.speedtest-cli
              pkgs.cloudflared
              # languages / formatters
              pkgs.python3
              pkgs.uv
              pkgs.ruff
              pkgs.nodejs # neovim copilot plugin
              pkgs.tree-sitter
              pkgs.shfmt
              pkgs.nixfmt
              pkgs.statix
              pkgs.prettierd
              # media
              pkgs.ffmpeg
              pkgs.mpv
              pkgs.yt-dlp
              # notes / misc
              pkgs.basalt # TUI Obsidian viewer
              pkgs.yazi
              gcal-agenda
            ]
            ++ lib.optional (tryPackage != null) tryPackage # experiment dirs under ~/tries
            # AI agents
            ++ lib.optional (pkgs ? claude-code) pkgs.claude-code
            ++ lib.optional (pkgs ? mcp-nixos) pkgs.mcp-nixos
            ++ lib.optional (pkgs ? codex) pkgs.codex
            ++ lib.optional (pkgs ? herdr) pkgs.herdr # terminal workspace manager for agents
            ++ lib.optional (pkgs ? tuicr) pkgs.tuicr # review agent diffs with line comments
            ++ lib.optionals (pkgs ? github-copilot-cli) [
              pkgs.github-copilot-cli
              hcopilot
            ];

            home.file.".config/nix/nix.conf".text = ''
              experimental-features = nix-command flakes
            '';

            home.shellAliases = {
              ls = "eza --icons --group-directories-first";
              ll = "eza -l --icons --group-directories-first --git";
              la = "eza -la --icons --group-directories-first --git";
              lt = "eza --tree --level=2 --icons";
              tree = "eza --tree --icons";
              hm = "home-manager";
              jap = "just apply";
            };

            # ── Shell ──
            programs.zsh = {
              enable = true;
              enableCompletion = true;
              autosuggestion.enable = true;
              historySubstringSearch.enable = true;
              # Regenerate the compinit dump at most once a day.
              completionInit = ''
                autoload -Uz compinit
                if [[ -f "$HOME/.zcompdump" && $(date +'%j') == $(date -r "$HOME/.zcompdump" +'%j' 2>/dev/null) ]]; then
                  compinit -C
                else
                  compinit
                fi
              '';
              # macOS updates can reset /etc/zshrc and drop the Nix installer's
              # PATH setup; source it from the user's .zshenv too.
              envExtra = ''
                if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
                  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
                fi
              '';
              # `brew shellenv` prepends /opt/homebrew/bin, which would shadow
              # every flake-pinned tool Homebrew also ships. Put Nix back in
              # front. Entries are stripped before re-prepending so tmux's login
              # shells reorder PATH instead of growing it.
              profileExtra = ''
                if [ -x /opt/homebrew/bin/brew ]; then
                  eval "$(/opt/homebrew/bin/brew shellenv)"
                fi
                _nixbins=(
                  "$HOME/.nix-profile/bin"
                  "/etc/profiles/per-user/$USER/bin"
                  "/run/current-system/sw/bin"
                  "/nix/var/nix/profiles/default/bin"
                )
                PATH=":$PATH:"
                for _nixbin in "''${_nixbins[@]}"; do
                  PATH="''${PATH//":$_nixbin:"/:}"
                done
                for (( _i = ''${#_nixbins[@]}; _i > 0; _i-- )); do
                  _nixbin="''${_nixbins[_i]}"
                  [ -d "$_nixbin" ] && PATH=":$_nixbin$PATH"
                done
                PATH="''${PATH#:}"
                PATH="''${PATH%:}"
                unset _nixbin _nixbins _i
                export PATH
              '';
              initContent =
                builtins.readFile ./files/.config/shell/functions.sh
                + builtins.readFile ./files/.config/zsh/init.zsh;
            };

            programs.bash = {
              enable = true;
              initExtra =
                builtins.readFile ./files/.config/shell/functions.sh
                + builtins.readFile ./files/.config/bash/init.bash;
            };

            # launchd keeps the highlighting daemon alive across reboots/crashes;
            # the shell's cached `activate` never restarts it on its own.
            # $TMPDIR is resolved explicitly because launchd doesn't set it for
            # agents and the socket lives there.
            launchd.agents.zsh-patina = {
              enable = true;
              config = {
                ProgramArguments = [
                  "/bin/sh"
                  "-c"
                  ''TMPDIR="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)" exec ${pkgs.zsh-patina}/bin/zsh-patina start --no-daemon''
                ];
                RunAtLoad = true;
                # Restart on crash only: `start` exits 0 when a daemon is already up.
                KeepAlive.SuccessfulExit = false;
                ProcessType = "Interactive";
              };
            };

            programs.fzf.enable = true;

            # nix-direnv caches `use flake` environments. Shell hooks come from
            # init.zsh's _cached_init, so the module's own integration is off.
            programs.direnv = {
              enable = true;
              nix-direnv.enable = true;
              enableZshIntegration = false;
              enableBashIntegration = false;
            };

            # ── Git / jujutsu ──
            programs.git = {
              enable = true;
              lfs.enable = true;
              settings = {
                user = {
                  name = identity.gitName;
                  email = identity.gitEmail;
                };
                credential."https://github.com".helper = [
                  ""
                  "!gh auth git-credential"
                ];
                credential."https://gist.github.com".helper = [
                  ""
                  "!gh auth git-credential"
                ];
                push.default = "current";
                pull.rebase = true;
                fetch.prune = true;
                rebase.autoStash = true;
                rerere.enabled = true;
                merge.conflictStyle = "diff3";
                diff.algorithm = "patience";
                diff.colorMoved = "default";
                column.ui = "auto";
                branch.sort = "-committerdate";
              };
            };

            programs.jujutsu = {
              enable = true;
              settings = {
                user = {
                  name = identity.gitName;
                  email = identity.gitEmail;
                };
                ui.conflict-marker-style = "git"; # = git's diff3 markers
                ui.pager = "delta";
                ui.diff-formatter = ":git"; # delta only understands git diffs
              };
            };

            programs.delta = {
              enable = true;
              enableGitIntegration = true;
              options = {
                navigate = true;
                line-numbers = true;
                side-by-side = false;
              };
            };

            xdg.configFile."tig/config".source = ./files/.config/tig/config;

            # ── Neovim (LazyVim) ──
            programs.neovim = {
              enable = true;
              defaultEditor = true;
              viAlias = true;
              vimAlias = true;
              withPython3 = true;
              withRuby = false;
              # Native tools from Nix rather than mason (mason=false below).
              extraPackages = with pkgs; [
                marksman
                lua-language-server
                ruff
                stylua
                nil
              ];
            };

            xdg.configFile."nvim/init.lua".text = ''
              require("config.lazy")
            '';
            xdg.configFile."nvim/lua/config/keymaps.lua".source = ./files/.config/nvim/lua/config/keymaps.lua;
            xdg.configFile."nvim/lua/config/options.lua".source = ./files/.config/nvim/lua/config/options.lua;
            # lazy-lock.json is deliberately not deployed: lazy.nvim must be able
            # to write it. files/.config/nvim/lazy-lock.json is a snapshot only.
            xdg.configFile."nvim/lua/config/lazy.lua".text = ''
              local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
              if not (vim.uv or vim.loop).fs_stat(lazypath) then
                local out = vim.fn.system({
                  "git", "clone", "--filter=blob:none", "--branch=stable",
                  "https://github.com/folke/lazy.nvim.git", lazypath,
                })
                if vim.v.shell_error ~= 0 then
                  vim.api.nvim_echo({
                    { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
                    { out,                             "WarningMsg" },
                    { "\nPress any key to continue...", "" },
                  }, true, {})
                  vim.fn.getchar()
                  os.exit(1)
                end
              end
              vim.opt.rtp:prepend(lazypath)

              require("lazy").setup({
                spec = {
                  { "LazyVim/LazyVim", import = "lazyvim.plugins" },
                  { import = "lazyvim.plugins.extras.lang.python" },
                  { import = "lazyvim.plugins.extras.lang.yaml" },
                  { import = "lazyvim.plugins.extras.lang.nix" },
                  { import = "lazyvim.plugins.extras.lang.json" },
                  { import = "lazyvim.plugins.extras.lang.toml" },
                  { import = "lazyvim.plugins.extras.lang.markdown" },
                  {
                    "neovim/nvim-lspconfig",
                    opts = {
                      servers = {
                        marksman = { mason = false },
                        lua_ls = { mason = false },
                        ruff = { mason = false },
                        nil_ls = { mason = false },
                      },
                    },
                  },
                  {
                    "mason-org/mason.nvim",
                    opts = function(_, opts)
                      opts.ensure_installed = vim.tbl_filter(function(tool)
                        return tool ~= "stylua"
                      end, opts.ensure_installed or {})
                    end,
                  },
                  -- No markdownlint diagnostics
                  { "mfussenegger/nvim-lint", opts = { linters_by_ft = { markdown = {} } } },
                  { import = "lazyvim.plugins.extras.formatting.prettier" },
                  { import = "lazyvim.plugins.extras.ai.copilot" },
                  { import = "lazyvim.plugins.extras.ai.copilot-chat" },
                  { import = "lazyvim.plugins.extras.editor.dial" },
                  { "kylechui/nvim-surround", version = "*", event = "VeryLazy", opts = {} },
                  -- Render ANSI colours (tmux pane-nvim popup)
                  { "m00qek/baleia.nvim", lazy = false },
                  {
                    "axieax/urlview.nvim",
                    cmd = "UrlView",
                    keys = { { "<leader>su", "<cmd>UrlView<cr>", desc = "Search URLs" } },
                    opts = { default_action = "system" },
                  },
                  {
                    "MeanderingProgrammer/render-markdown.nvim",
                    ft = "markdown",
                    opts = {
                      pipe_table = { enabled = false },
                      checkbox = {
                        enabled = true,
                        custom = {
                          in_progress = { raw = "[/]", rendered = "󰥔 ", highlight = "RenderMarkdownWarn" },
                        },
                      },
                    },
                  },
                  {
                    "ice345/markdown-table-wrap.nvim",
                    ft = "markdown",
                    keys = {
                      { "<leader>mp", "<cmd>MarkdownTableFloatPreview<cr>", ft = "markdown", desc = "Preview wrapped table" },
                    },
                    opts = {
                      auto_preview = true,
                      preview_mode = "reader",
                      mappings = { reader = { insert = { "i", "a", "I", "A", "o", "O", "C", "S", "s" } } },
                    },
                  },
                  {
                    "bullets-vim/bullets.vim",
                    ft = "markdown",
                    init = function()
                      vim.g.bullets_checkbox_markers = " /x"
                    end,
                  },
                  {
                    "ziontee113/icon-picker.nvim",
                    keys = { { "<leader>si", "<cmd>IconPickerNormal<cr>", desc = "Icon/emoji picker" } },
                    opts = { disable_legacy_commands = true },
                  },
                  {
                    "shortcuts/no-neck-pain.nvim",
                    cmd = "NoNeckPain",
                    keys = { { "<leader>uc", "<cmd>NoNeckPain<cr>", desc = "Toggle centered layout" } },
                    opts = { width = 100 },
                  },
                },
                defaults = { lazy = false, version = false },
                install = { colorscheme = { "tokyonight", "habamax" } },
                checker = { enabled = true, notify = false },
                performance = {
                  rtp = { disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin" } },
                },
              })
            '';

            # ── tmux ──
            programs.tmux = {
              enable = true;
              plugins = [
                pkgs.tmuxPlugins.tmux-thumbs
                {
                  plugin = tmux-easy-motion;
                  extraConfig = ''
                    set -g @easy-motion-prefix "Space"
                    set -g @easy-motion-default-motion "bd-f"
                    set -g @easy-motion-default-key-bindings "off"
                  '';
                }
                {
                  plugin = pkgs.tmuxPlugins.tmux-sessionx;
                  extraConfig = ''
                    set -g @sessionx-bind 's'
                    set -g @sessionx-zoxide-mode 'on'
                    set -g @sessionx-preview-location 'right'
                    set -g @sessionx-preview-ratio '55%'
                  '';
                }
              ];
              extraConfig = ''
                # Nord theme, with a more prominent active window
                source-file ${pkgs.tmuxPlugins.nord}/share/tmux-plugins/nord/src/nord.conf
                source-file ${pkgs.tmuxPlugins.nord}/share/tmux-plugins/nord/src/nord-status-content.conf
                set -g window-status-current-format "#[fg=black,bg=#88c0d0,nobold,noitalics,nounderscore] #[fg=#2e3440,bg=#88c0d0,bold]#I #[fg=#2e3440,bg=#88c0d0,nobold,noitalics,nounderscore] #[fg=#2e3440,bg=#88c0d0,bold]#W #F #[fg=#88c0d0,bg=black,nobold,noitalics,nounderscore]"
                set -g window-status-format "#[fg=black,bg=#3b4252,nobold,noitalics,nounderscore] #[fg=#616e88,bg=#3b4252]#I #[fg=#616e88,bg=#3b4252,nobold,noitalics,nounderscore] #[fg=#616e88,bg=#3b4252]#W #F #[fg=#3b4252,bg=black,nobold,noitalics,nounderscore]"

                ##### tmux-thumbs #####
                set -g @thumbs-command 'tmux set-buffer -- {} && echo -n {} | pbcopy'
                set -g @thumbs-upcase-command 'tmux set-buffer -- {} && echo -n {} | pbcopy && tmux paste-buffer'
                bind -n M-t thumbs-pick

                ##### Core ergonomics #####
                set -g default-terminal "tmux-256color"
                set -ga terminal-features "*:RGB:hyperlinks:ccolour:cstyle:focus:title"
                set -s escape-time 10
                set -g allow-passthrough on
                setw -g mode-keys vi

                # Prefix
                unbind C-b
                set -g prefix C-a
                set -g prefix2 C-Space
                bind C-a send-prefix
                bind v next-layout # prefix Space is easy-motion's

                ##### Alt bindings: panes #####
                bind -n M-h select-pane -L
                bind -n M-j select-pane -D
                bind -n M-k select-pane -U
                bind -n M-l select-pane -R
                bind -n M-H resize-pane -L 5
                bind -n M-J resize-pane -D 5
                bind -n M-K resize-pane -U 5
                bind -n M-L resize-pane -R 5
                bind -n M-_ split-window -h
                bind -n M-- split-window -v
                bind -n M-x kill-pane
                bind -n M-z resize-pane -Z

                ##### Alt bindings: windows #####
                bind -n M-c new-window
                bind -n M-n next-window
                bind -n M-p previous-window
                bind -n M-1 select-window -t 1
                bind -n M-2 select-window -t 2
                bind -n M-3 select-window -t 3
                bind -n M-4 select-window -t 4
                bind -n M-5 select-window -t 5
                bind -n M-6 select-window -t 6
                bind -n M-r command-prompt -I "#W" "rename-window '%%'"

                ##### Alt bindings: sessions #####
                bind -n M-s run-shell "${pkgs.tmuxPlugins.tmux-sessionx}/share/tmux-plugins/sessionx/scripts/sessionx.sh"
                bind -n M-C new-session
                bind -n M-$ command-prompt -I "#S" "rename-session '%%'"
                bind -n M-B set-option status

                ##### Copy mode #####
                bind -n M-Space copy-mode
                bind -T copy-mode-vi v send-keys -X begin-selection
                bind -T copy-mode-vi V send-keys -X select-line
                bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
                bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'pbcopy'
                bind -T copy-mode-vi Escape send-keys -X cancel

                # Pane content → neovim popup
                bind -n M-e display-popup -w 100% -h 100% -E "${pane-nvim}"
                bind -n M-R source-file ~/.config/tmux/tmux.conf \; display-message "tmux reloaded"

                set -g set-clipboard on
                set -g history-limit 100000
                set -g mouse on
                set -g renumber-windows on
                set -g base-index 1
                setw -g pane-base-index 1
              '';
            };
            xdg.configFile."tmux/tmux.conf".force = true;

            # ── Small TUIs ──
            xdg.configFile = {
              "herdr/config.toml".source = ./files/.config/herdr/config.toml;
              "tuicr/config.toml".source = ./files/.config/tuicr/config.toml;
              "yazi/keymap.toml".source = ./files/.config/yazi/keymap.toml;
              "yazi/yazi.toml".source = ./files/.config/yazi/yazi.toml;
              "yazi/init.lua".source = ./files/.config/yazi/init.lua;
              "yazi/plugins/git.yazi".source = "${yazi-plugins}/git.yazi";
              "yazi/plugins/piper.yazi".source = "${yazi-plugins}/piper.yazi";
              "yazi/plugins/toggle-pane.yazi".source = "${yazi-plugins}/toggle-pane.yazi";
              "yazi/plugins/scp-clip.yazi".source = ./files/.config/yazi/plugins/scp-clip.yazi;
              "yazi/plugins/archive-zip.yazi".source = ./files/.config/yazi/plugins/archive-zip.yazi;
            };

            # lnks: fzf bookmark opener. The bookmark list is seeded once and then
            # left alone as local state — it fills up with internal URLs.
            home.file.".local/bin/lnks" = {
              source = ./files/.local/bin/lnks;
              executable = true;
            };
            home.activation.seedBookmarks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              if [ ! -e "$HOME/.config/lnks/bookmarks.txt" ]; then
                run mkdir -p "$HOME/.config/lnks"
                run install -m 0644 ${./files/.config/lnks/bookmarks.example.txt} "$HOME/.config/lnks/bookmarks.txt"
              fi
            '';

            # ── Terminal: Ghostty (cask) ──
            # Resident, windowless instance started as a Login Item so the global
            # Cmd+Shift+Enter keybind always has a process to receive it.
            xdg.configFile."ghostty/config".text =
              builtins.replaceStrings [ "@ZSH@" ] [ "${pkgs.zsh}/bin/zsh" ]
                (builtins.readFile ./files/.config/ghostty/config);
            home.activation.ghosttyLoginItem = lib.hm.dag.entryAfter [ "writeBoundary" ] (
              loginItem "Ghostty" "Ghostty.app/Contents/MacOS/ghostty"
            );

            # ── Window management: Hammerspoon (cask) ──
            # Launch-at-login is hs.autoLaunch(true) inside init.lua.
            home.file.".hammerspoon/init.lua".source = ./files/.hammerspoon/init.lua;

            # ── Agents: Claude Code / Codex / Copilot ──
            # nixpkgs defaults Claude Code to the OS cert store only; keep the
            # system/corporate roots and add Claude's bundled public roots.
            home.sessionVariables.CLAUDE_CODE_CERT_STORE = "bundled,system";
          }
          (lib.mkIf (agentfilesRepo != null) {
            # Shared agent config lives in its own repo, symlinked out-of-store so
            # edits apply without a rebuild. Clone failure only warns.
            home.activation.cloneAgentfiles = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
              if [ ! -e "${agentfiles}/.git" ]; then
                if ! PATH="${lib.makeBinPath [ pkgs.gh ]}:$PATH" GIT_TERMINAL_PROMPT=0 run ${pkgs.git}/bin/git clone \
                    ${agentfilesRepo} "${agentfiles}"; then
                  warnEcho "agentfiles clone failed; agent config symlinks dangle until it is cloned to ${agentfiles}"
                fi
              fi
            '';
            # Link every agentfiles/common/skills/*/SKILL.md dir into each agent's
            # skills dir, and prune links whose skill was removed.
            home.activation.linkAgentSkills = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
              skills_source="${agentfiles}/common/skills"
              if [ -d "$skills_source" ]; then
                for skills_dir in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.copilot/skills/custom"; do
                  run mkdir -p "$skills_dir" || continue
                  for skill in "$skills_source"/*; do
                    [ -f "$skill/SKILL.md" ] || continue
                    target="$skills_dir/$(basename "$skill")"
                    if [ -e "$target" ] && [ ! -L "$target" ]; then
                      warnEcho "cannot link $(basename "$skill"): $target exists and is not a symlink"
                      continue
                    fi
                    run ln -sfn "$skill" "$target" || warnEcho "failed to link $skill at $target"
                  done
                  for target in "$skills_dir"/*; do
                    [ -L "$target" ] || continue
                    case "$(readlink "$target")" in
                      "$skills_source"/*) [ -e "$target" ] || run rm -f "$target" ;;
                    esac
                  done
                done
              else
                warnEcho "agentfiles skills not found at $skills_source"
              fi
            '';
            home.file = {
              ".claude/CLAUDE.md".source = link "${agentfiles}/claude/CLAUDE.md";
              ".claude/settings.json".source = link "${agentfiles}/claude/settings.json";
              ".claude/statusline-command.sh".source = link "${agentfiles}/claude/statusline-command.sh";
              ".codex/instructions.md".source = link "${agentfiles}/codex/instructions.md";
            };
          })
          {
            # mpv as default video player. mpv comes from nixpkgs; Home Manager's
            # copyApps gives the bundle a stable path so the LaunchServices
            # binding survives upgrades. Bound per UTI because macOS resolves the
            # most specific type first (public.movie alone leaves .mp4 on
            # QuickTime).
            home.activation.mpvDefaultVideoPlayer = lib.hm.dag.entryAfter [ "copyApps" ] ''
              mpv_app="$HOME/${config.targets.darwin.copyApps.directory}/mpv.app"
              if [ -d "$mpv_app" ]; then
                run /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$mpv_app"
                for uti in \
                  public.movie public.video public.mpeg-4 public.mpeg public.mpeg-2-video \
                  public.mpeg-2-transport-stream public.avi public.3gpp public.3gpp2 \
                  public.dv-movie com.apple.quicktime-movie com.apple.m4v-video \
                  com.microsoft.windows-media-wmv org.matroska.mkv org.webmproject.webm \
                  org.xiph.ogg-video com.adobe.flash.video public.avchd-mpeg-2-transport-stream \
                  org.videolan.vob io.mpv.mk3d io.mpv.webm io.mpv.wmv io.mpv.mts io.mpv.vob; do
                  run ${pkgs.duti}/bin/duti -s io.mpv "$uti" all \
                    || warnEcho "could not make mpv the default for $uti"
                done
              else
                warnEcho "mpv.app not found at $mpv_app; skipping default video player setup"
              fi
            '';
          }
          # Voxtype: push-to-talk dictation (Fn). The cask ships a CLI; `voxtype
          # setup app-bundle` builds /Applications/Voxtype.app, which holds the
          # Microphone + Accessibility grants, and it runs as a Login Item.
          (lib.mkIf features.voxtype {
            home.file."Library/Application Support/voxtype/config.toml".source =
              (pkgs.formats.toml { }).generate "voxtype-config.toml"
                (
                  lib.recursiveUpdate (builtins.fromTOML (builtins.readFile (voxtypeDir + "/config.toml"))) (
                    builtins.fromTOML (builtins.readFile (voxtypeDir + "/vocabulary.toml"))
                  )
                );
            home.activation.voxtypeLoginItem = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              cli=/opt/homebrew/bin/voxtype
              bundled=/Applications/Voxtype.app/Contents/MacOS/voxtype-bin
              if [ -x "$cli" ] && [ "$("$bundled" --version 2>/dev/null)" != "$("$cli" --version 2>/dev/null)" ]; then
                /usr/bin/pkill -f voxtype-bin || true
                run "$cli" setup app-bundle </dev/null || true
              fi
              if [ -d /Applications/Voxtype.app ]; then
                if ! /usr/bin/osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | grep -q "Voxtype"; then
                  run /usr/bin/osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Voxtype.app", hidden:true}' \
                    || warnEcho "could not add Voxtype to Login Items"
                fi
                if ! /usr/bin/pgrep -f voxtype-bin >/dev/null 2>&1; then
                  run /usr/bin/open -a Voxtype || true
                fi
              fi
            '';
          })
        ];

      workMac = nix-darwin.lib.darwinSystem {
        modules = [
          darwinModule
          home-manager.darwinModules.home-manager
          {
            nixpkgs.pkgs = pkgs;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.users.${identity.username}.imports = [ homeModule ];
          }
        ];
      };
    in
    {
      darwinConfigurations.work-mac = workMac;

      # darwinConfigurations isn't a standard output, so `nix flake check` only
      # evaluates it through here.
      checks.${system}.work-mac = workMac.system;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.just
          pkgs.nixfmt
          pkgs.statix
        ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
