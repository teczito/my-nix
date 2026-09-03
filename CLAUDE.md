# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The live NixOS system configuration for a single machine (`/etc/nixos`, hostname `nixos`, x86_64-linux,
Tiger Lake laptop with the discrete NVIDIA GPU disabled). Edits here change the machine the agent is
running on. There is no test suite; correctness is checked by evaluating and building the configuration.

## Commands

```bash
# Fast feedback loop — evaluate a single option without building anything.
# This is the primary way to verify a change; prefer it over a full rebuild.
nix eval .#nixosConfigurations.nixos.config.services.displayManager.defaultSession
nix eval --raw .#nixosConfigurations.nixos.config.home-manager.users.ruben.programs.bash.shellAliases.kicad

nixos-rebuild build --flake /etc/nixos#nixos    # build only, no sudo, leaves ./result
nixos-rebuild dry-build --flake /etc/nixos#nixos
sudo nixos-rebuild switch --flake /etc/nixos#nixos
sudo nixos-rebuild switch --rollback

nixfmt --check users/ruben.nix                  # formatter is `pkgs.nixfmt` (RFC style)
nixfmt users/ruben.nix

nix flake update                                # or: nix flake update nixpkgs
nix develop                                     # claude-code, nixd, nixfmt; direnv does this automatically
```

Custom packages live in `pkgs/` and are exposed through the overlay, not as a flake `packages` output
(the "nix build .#example" comment in `pkgs/default.nix` is stale). Build one with:

```bash
nix build .#nixosConfigurations.nixos.pkgs.my-saleae-logic-2
```

## Architecture

`flake.nix` defines exactly one output that matters: `nixosConfigurations.nixos`, composed from
`./users`, `./apps`, `./configuration.nix`, plus the home-manager NixOS module with
`useGlobalPkgs = true` (so home-manager shares the system nixpkgs and system-level overlays).

**Overlays** (`overlays/default.nix`) return a list applied in order, and two of the three are load-bearing:

- `additions` — imports `pkgs/`, which is why `pkgs.my-saleae-logic-2` resolves in `configuration.nix`.
- `modifications` — rebuilds `awesome` with `gtk3Support = true`.
- `patch01` — a `builtins.fetchGit` pinned by rev to `stefano-m/nix-stefano-m-nix-overlays`. This is the
  only source of the `extraLuaPackages.*` attributes that `services.xserver.windowManager.awesome.luaModules`
  depends on. It is outside the flake lock, so `nix flake update` does not move it; bump the `rev` by hand.

**Per-user config** lives under `users/`. `users/default.nix` imports only `ruben.nix`; `teczito.nix`
exists but is not imported. Each file defines both the system user and its `home-manager.users.<name>` block.

**Backups** are a coupled pair that must be edited together: `backup-configurations.nix` writes three btrbk
configs into `/etc/btrbk/`, and `timer-configuration.nix` defines the systemd timers/services that invoke
btrbk against those exact paths. Renaming a config file there breaks the units here.

`apps/` currently imports nothing — `apps/caddy.nix` is complete but commented out in `apps/default.nix`.

## Gotchas

**`hardware-configuration.nix` is hand-edited despite its "Do not modify this file!" banner.** It carries
the NVIDIA block, `hardware.bluetooth.enable`, `hardware.graphics.enable`, and the extra btrfs mounts.
Never regenerate it with `nixos-generate-config`; that would silently drop all of it.

**The NVIDIA GPU is fully disabled.** `hardware.nvidiaOptimus.disable = true` blacklists `nvidia`,
`nvidia-drm`, `nvidia-modeset`, and `nvidia-uvm` at the modprobe level, so only the Intel iGPU exists at
runtime (`/dev/dri/card1`) — even though `services.xserver.videoDrivers` still lists `"nvidia"` and the
whole `hardware.nvidia` block (PRIME offload, `open = true`) is still present and inert. Do not set
`__GLX_VENDOR_LIBRARY_NAME`, `LIBVA_DRIVER_NAME`, or similar to `nvidia` anywhere; forcing the NVIDIA
GLX vendor makes `glXCreateNewContext` fail with BadValue for every GLX client on the machine.

**Most files in `config-files/` are unmanaged copies, not the deployed config.** Only two are actually
wired into the build:

- `config-files/vim/.vimrc` → `programs.vim.extraConfig` in `users/ruben.nix`
- `config-files/ti/71-ti-permissions.rules` → `services.udev.extraRules` in `configuration.nix`

`config-files/hypr/`, `awesome/`, `waybar/`, `walker/`, `mc/`, and `autorandr/` are hand-kept mirrors of
files under `~/.config/`. Nothing symlinks or copies them. When changing one of these, write **both** the
repo copy and the live `~/.config/` file, and verify with `diff` — a rebuild will not deploy them.

**Three desktop sessions coexist and diverge.** GNOME and awesome run on X11 (`defaultSession` is
`none+awesome`), Hyprland runs on Wayland. Session-specific environment variables set in
`~/.config/hypr/hyprland.conf` are inherited by every client including XWayland ones, so a bad `env =`
line there produces symptoms that appear only under Hyprland and not under awesome.

Hyprland env changes need a full logout/login; `hyprctl reload` does not re-export them.
