# Apply the system + user config. The first run bootstraps darwin-rebuild via
# `nix run`, since nothing has installed it yet.
apply:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v darwin-rebuild >/dev/null 2>&1; then
      sudo darwin-rebuild switch --flake .#work-mac
    else
      sudo nix --extra-experimental-features "nix-command flakes" run \
        github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake .#work-mac
    fi

# Build the system closure without activating it.
build:
    nix build .#darwinConfigurations.work-mac.system --no-link

# Evaluate and build everything `nix flake check` covers.
check:
    nix flake check

# Update all flake inputs (does not apply them).
update:
    nix flake update

# Format all Nix files.
fmt:
    nix fmt flake.nix
