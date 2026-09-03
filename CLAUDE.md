# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The live NixOS system configuration for a single machine (`/etc/nixos`, hostname `nixos`, x86_64-linux,
HP ZBook Fury 15.6" G8 / Xeon W-11955M, Intel iGPU + discrete NVIDIA RTX A2000 on PRIME offload). Edits
here change the machine the agent is running on. There is no test suite; correctness is checked by
evaluating and building the configuration.

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
the GPU/graphics settings, `hardware.bluetooth.enable`, and the extra btrfs mounts. Never regenerate it
with `nixos-generate-config`; that would silently drop all of it.

**Both GPUs are live, as PRIME render offload.** All graphics config is in `nvidia-prime.nix`; the
`hardware.nvidiaOptimus.disable` + `bbswitch` setup that used to power the card off is **gone**.

- iGPU `8086:9a70`, Tiger Lake-H **GT1 / 32 EU UHD Graphics** at `PCI:0:2:0`. It owns every display
  (3× 2560×1440 external + 1920×1080 eDP) and does all compositing. This is the weakest TGL graphics
  tier — not the 96-EU Iris Xe of the U-series — which is why offloading real 3D work matters here.
- dGPU `10de:25b8`, **NVIDIA RTX A2000 Mobile (GA107GLM, Ampere, 4 GB)** at `PCI:1:0:0`. Idles at
  D3cold via `powerManagement.finegrained` (`NVreg_DynamicPowerManagement=0x02`) and wakes on demand.

Run something on the NVIDIA card with the **`nvidia-offload` wrapper** (`prime.offload.enableOffloadCmd`),
e.g. `nvidia-offload blender`. That is the only supported path.

`services.xserver.videoDrivers` must list **`"nvidia"` only**. The PRIME module injects its own
`modesetting` driver entry carrying `BusID "PCI:0:2:0"` (`nixos/modules/hardware/video/nvidia.nix`,
`services.xserver.drivers`); adding `"modesetting"` by hand emits a *second*, BusID-less
`Device-modesetting[0]`/`Screen-modesetting[0]` pair into the generated `xorg.conf`.

`hardware.nvidia.open` must be set **explicitly** to `true`. It defaults to `null` on driver ≥ 560 and
`null` fails an assertion. Ampere is fully supported by the open kernel modules.

Still do **not** set `__GLX_VENDOR_LIBRARY_NAME`, `LIBVA_DRIVER_NAME`, or similar to `nvidia` session-wide
(in `hyprland.conf`, `environment.variables`, …) — that remains true now that the driver is installed, and
is a different thing from what `nvidia-offload` does. Setting them globally makes libglvnd hand
`libGLX_nvidia.so` to every GLX client including those on the Intel screen, where `glXCreateNewContext`
fails with BadValue; `nvidia-offload` sets them for one process only.

Because the NVIDIA card now exposes its own DRM node, Hyprland is pinned to the iGPU with
`env = AQ_DRM_DEVICES,/dev/dri/by-path/pci-0000:00:02.0-card` in `hyprland.conf`. Use the `by-path`
symlink; `/dev/dri/cardN` numbering is not stable.

Two standing risks worth knowing: the out-of-tree driver is coupled to `boot.kernelPackages =
linuxPackages_latest`, so a `nix flake update` can land a kernel NVIDIA has not caught up to and block the
rebuild (595.99.02 builds against 7.2.2 — verified); and `finegrained` runtime-D3 idles a little hotter
than the old ACPI cut, roughly 1–2 W.

**Most files in `config-files/` are unmanaged copies, not the deployed config.** Only two are actually
wired into the build:

- `config-files/vim/.vimrc` → `programs.vim.extraConfig` in `users/ruben.nix`
- `config-files/ti/71-ti-permissions.rules` → `services.udev.extraRules` in `configuration.nix`

`config-files/hypr/`, `awesome/`, `waybar/`, `walker/`, and `autorandr/` are **hardlinked** to their
counterparts under `~/.config/` — same inode, verified with `stat -c %i`. Editing the repo copy in place
therefore *is* editing the live file; no copy step is needed. The catch is that any tool which replaces a
file by writing a new inode (atomic rename-based writes) silently **breaks the hardlink**, after which the
two drift apart. After editing one of these, confirm the link survived:

```bash
stat -c %i config-files/hypr/hyprland.conf ~/.config/hypr/hyprland.conf   # must match
```

If it broke, `cp` the repo copy over the live path and re-link. `config-files/mc/mc.keymap` has no live
counterpart at all. A rebuild never deploys any of these.

**Three desktop sessions coexist and diverge.** GNOME and awesome run on X11 (`defaultSession` is
`none+awesome`), Hyprland runs on Wayland. Session-specific environment variables set in
`~/.config/hypr/hyprland.conf` are inherited by every client including XWayland ones, so a bad `env =`
line there produces symptoms that appear only under Hyprland and not under awesome.

Hyprland env changes need a full logout/login; `hyprctl reload` does not re-export them.
