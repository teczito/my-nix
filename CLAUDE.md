# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The NixOS configuration in `/etc/nixos`, for two x86_64-linux machines:

- **`zbook`** — HP ZBook Fury 15.6" G8 / Xeon W-11955M, Intel iGPU + discrete NVIDIA RTX A2000 on PRIME
  offload. This is the live system the agent runs on, so edits here change the machine under it.
- **`server`** — local LLM (ollama), VM host (libvirt/KVM), containers, and compiling things. Mainly
  headless with a monitor attached occasionally. AMD, installed and running at **192.168.68.105** on
  `enp11s0` (DHCP from the router at 192.168.68.1, so it needs a reservation there, since it is the LAN's
  DNS resolver). Reachable as `ssh 192.168.68.105`. `hosts/server/hardware-configuration.nix` is the
  real `nixos-generate-config` output. The server has its own clone of this repo in `/etc/nixos`: to
  deploy, push from here, then on the server `git pull && ./rebuild_switch.sh`, which needs the sudo
  password there.

There is no test suite; correctness is checked by evaluating and building the configuration. The server
config builds fine from the laptop, so build it here before deploying.

## Commands

```bash
# Fast feedback loop — evaluate a single option without building anything.
# This is the primary way to verify a change; prefer it over a full rebuild.
nix eval .#nixosConfigurations.zbook.config.services.displayManager.defaultSession
nix eval --raw .#nixosConfigurations.zbook.config.home-manager.users.ruben.programs.bash.shellAliases.kicad

nixos-rebuild build --flake /etc/nixos#zbook    # build only, no sudo, leaves ./result
nixos-rebuild dry-build --flake /etc/nixos#zbook
sudo nixos-rebuild switch --flake /etc/nixos#zbook

# The other host builds from here too -- build it here before pulling it on the server.
nix build .#nixosConfigurations.server.config.system.build.toplevel
sudo nixos-rebuild switch --rollback

# Always name the host explicitly. A bare `--flake /etc/nixos` resolves the attribute from the running
# `hostname`, which stays `nixos` until the rename above is actually switched in.

nixfmt --check users/ruben/default.nix          # formatter is `pkgs.nixfmt` (RFC style)
nixfmt users/ruben/default.nix

nix flake update                                # or: nix flake update nixpkgs
nix develop                                     # claude-code, nixd, nixfmt; direnv does this automatically
```

Custom packages live in `pkgs/` and are exposed through the overlay, not as a flake `packages` output
(the "nix build .#example" comment in `pkgs/default.nix` is stale). Build one with:

```bash
nix build .#nixosConfigurations.zbook.pkgs.my-saleae-logic-2
```

## Architecture

`flake.nix` builds every host through one `mkHost` helper, and `nixosConfigurations` is the only output
that matters. `mkHost "<name>"` composes `./users`, `./hosts/<name>`, the overlays and the home-manager
NixOS module with `useGlobalPkgs = true` (so home-manager shares the system nixpkgs and system-level
overlays), and sets `networking.hostName` from the directory name — so a host directory name *is* the
machine name and the two cannot drift. Adding a host is one new `hosts/<name>/` directory plus one line in
`nixosConfigurations`.

**Layout.** `hosts/<name>/` holds what is true of exactly one machine, including its own
`hardware-configuration.nix` — bootloader, `stateVersion`, filesystem-dependent settings, and the
overrides that make this machine different. `modules/` holds what a host opts into:

- `modules/common/` — wanted on every host: `nix.nix`, `locale.nix`, `networking.nix`, `ssh.nix` and
  `packages.nix` (the CLI package set), plus polkit and nix-ld in `default.nix`.
- `modules/desktop/` — one import for the whole graphical stack: `greetd.nix`, `niri.nix`,
  `audio.nix`, `portals.nix`, `fonts.nix`, `apps.nix`.
- `modules/hardware/` — GPU and firmware. `nvidia-prime.nix` is the only one.
- `modules/services/` — daemons and timers, imported one by one: `backup.nix`, `builder.nix`,
  `devices.nix`, `dns.nix`, `docker.nix`, `llm.nix`, `meal-planner.nix`, `printing.nix`,
  `virtualisation.nix`, `caddy.nix`.

`users/`, `pkgs/`, `overlays/` and `config-files/` stay at the top level because they are not per-host.

A module owns the packages its concern needs, so `environment.systemPackages` is defined in six places and
merged: `btrbk` in `backup.nix`, `xwayland-satellite` in `niri.nix`, `android-tools` in `devices.nix`, and so
on. Adding a package means finding the module that owns the concern, not editing one central list.

**What each host actually opts into.** The two differ almost entirely by which modules they import, not by
overrides:

| | zbook | server |
| --- | --- | --- |
| `modules/common` | yes | yes |
| `modules/desktop` | yes | yes — niri for the occasional monitor |
| `users/ruben/desktop.nix` | yes | **no** — vscode/kicad and the bench groups stay on the laptop |
| `modules/hardware/nvidia-prime.nix` | yes | no |
| `backup`, `devices`, `printing` | yes | no |
| `docker` | yes | yes |
| `builder`, `dns`, `llm`, `meal-planner`, `virtualisation` | no | yes |
| sshd started at boot | **no** (`wantedBy = mkForce []`) | yes (stock) |
| `services.xserver.enable` | `true` (for the NVIDIA kernel modules) | `false` |

That last row is the split working as intended: `xserver.enable` is defined only in the NVIDIA module, so
a host with no GPU module gets no X server at all, while both still get a console keymap because
`services.xserver.xkb.*` lives in `modules/common/locale.nix`. Closures come out at 11.27 GiB (zbook) and
7.40 GiB (server), sharing 1383 of their store paths.

**Overlays** (`overlays/default.nix`) return a list applied in order. Only one is load-bearing now:

- `additions` — imports `pkgs/`, which is why `pkgs.my-saleae-logic-2` resolves in `modules/services/devices.nix`.
- `modifications` — an empty placeholder. It used to rebuild `awesome` with `gtk3Support = true`.

A third overlay, `patch01`, was a `builtins.fetchGit` of `stefano-m/nix-stefano-m-nix-overlays` pinned by
rev and outside the flake lock. It existed solely to supply the `extraLuaPackages.*` attributes that
awesome's `luaModules` wanted, and went with awesome. Do not reintroduce it without that need: being
outside the lock, `nix flake update` never moved it and the rev had to be bumped by hand.

**Per-user config** lives under `users/`, split the same way the modules are. `users/ruben/default.nix`
is the CLI base — the system user, and a `home-manager.users.ruben` block with bash, git, tmux, vim and
lazygit — and is imported unconditionally by `users/default.nix`. `users/ruben/desktop.nix` is the
graphical-workstation layer on top: GUI packages, the bench-only groups (`adb`, `dialout`, `input`,
`nm-openvpn`), the `kicad` alias and the `xpdf` insecure-package allowance. A host that wants it imports
it; `hosts/zbook/default.nix` does. Both halves define `home-manager.users.ruben`, and the module system
merges them, so `home.packages`, `extraGroups` and `shellAliases` accumulate across the two files.

`home.stateVersion` deliberately does *not* live in either: like `system.stateVersion` it is a per-machine
compatibility marker, so the host sets it. `users/teczito.nix` exists but is not imported.

**Backups** are mechanism and policy, in two files. `modules/services/backup.nix` declares
`local.btrbk.jobs`, an `attrsOf submodule` where each entry generates all three pieces from one name:
`/etc/btrbk/btrbk-<name>.conf` from its `settings`, a oneshot `<name>.service` running btrbk against that
exact path, and a `<name>.timer` from `onBootSec`/`onUnitActiveSec` (null means run once per boot).
`hosts/zbook/backup-jobs.nix` is the policy — which subvolumes, how often, how much history.

This replaced two files that had to be edited together, where the config path was written in one and named
again in the other, so renaming a config silently orphaned its unit. That failure mode is now unreachable:
the name is written once.

`modules/services/caddy.nix` is complete but imported by nobody. It used to live in `apps/`, whose
`default.nix` was an empty import list; that directory is gone. Caddy *does* run on the server anyway:
the meal-planner flake's module enables `services.caddy` for its `teczito.duckdns.org` vhost and opens
80/443/8080. Check there before assuming Caddy is off.

**DNS on the server** is AdGuard Home, in `modules/services/dns.nix`. It listens on `127.0.0.1` and
the LAN IP explicitly, never `0.0.0.0`. libvirt's default network runs a dnsmasq on
`192.168.122.1:53` whenever a VM network is up, and with a wildcard bind whichever of the two starts
second fails with `address already in use`. Because the settings are declared in Nix, AdGuard skips its
setup wizard, so the admin login has to be declared too: `settings.users` holds a bcrypt hash from
`htpasswd -nB ruben`. **Never remove that entry while the UI is on the LAN.** Without it the UI
has no login at all. The UI is at `http://192.168.68.105:3000`, plain HTTP, with port 3000 opened by
the module's `openFirewall`.

## Gotchas

**`hosts/zbook/hardware-configuration.nix` is hand-edited despite its "Do not modify this file!" banner.** It carries
the GPU/graphics settings, `hardware.bluetooth.enable`, and the extra btrfs mounts. Never regenerate it
with `nixos-generate-config`; that would silently drop all of it.

**Both GPUs are live, as PRIME render offload.** All graphics config is in `modules/hardware/nvidia-prime.nix`; the
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
(in `config.kdl`'s `environment {}`, `environment.variables`, …) — that remains true now that the driver is installed, and
is a different thing from what `nvidia-offload` does. Setting them globally makes libglvnd hand
`libGLX_nvidia.so` to every GLX client including those on the Intel screen, where `glXCreateNewContext`
fails with BadValue; `nvidia-offload` sets them for one process only.

Because the NVIDIA card exposes its own DRM node, niri is pinned to the iGPU by the `debug` block at the
top of `config-files/niri/config.kdl`:

```kdl
debug {
    render-drm-device "/dev/dri/igpu"
    ignore-drm-device "/dev/dri/dgpu"
}
```

`ignore-drm-device` is what keeps the card in D3cold: niri never opens it, so only `nvidia-offload` wakes
it. Both paths are **udev symlinks defined in `modules/hardware/nvidia-prime.nix`**, matched on PCI slot,
because `/dev/dri/cardN` numbering is not stable across boots (it has been card0/card1 and card1/card2 on
different boots of the same hardware):

```
KERNEL=="card*", SUBSYSTEM=="drm", DEVPATH=="*/0000:00:02.0/drm/card*", SYMLINK+="dri/igpu"
KERNEL=="card*", SUBSYSTEM=="drm", DEVPATH=="*/0000:01:00.0/drm/card*", SYMLINK+="dri/dgpu"
```

**The same `config.kdl` is used on the server, where neither symlink exists — and that is safe.** niri's
`primary_node_from_config` returns `None` when the path cannot be opened (logging `error opening
"/dev/dri/igpu" as DRM node`), and the caller falls back to udev's primary GPU; an unopenable ignore entry
is simply skipped. Contrast Hyprland, removed 2026-10-06, whose `AQ_DRM_DEVICES` pin aborted the whole
session on a missing path (the 2026-09-18 server outage). Do not "fix" the warning on the server.

The udev rules are a second definition of `services.udev.extraRules` alongside the TI rules in
`modules/services/devices.nix`; the option is `types.lines`, so the two merge rather than collide. They are
wrapped in `lib.mkBefore` so they land *above* the TI rules in the generated file: `lines` options merge in
module order, and module order is NOT the order of a host's `imports` list — splitting these two
definitions into separate modules silently reversed them until the `mkBefore` was added. Which card is which
right now:

```bash
for c in /sys/class/drm/card[0-9]; do echo "$c -> $(basename $(readlink -f $c/device/driver))"; done
```

Two standing risks worth knowing: the out-of-tree driver is coupled to `boot.kernelPackages =
linuxPackages_latest`, so a `nix flake update` can land a kernel NVIDIA has not caught up to and block the
rebuild (595.99.02 builds against 7.2.2 — verified); and `finegrained` runtime-D3 idles a little hotter
than the old ACPI cut, roughly 1–2 W.

**Most files in `config-files/` are unmanaged copies, not the deployed config.** Only two are actually
wired into the build:

- `config-files/vim/.vimrc` → `programs.vim.extraConfig` in `users/ruben/default.nix`
- `config-files/ti/71-ti-permissions.rules` → `services.udev.extraRules` in `modules/services/devices.nix`

`config-files/niri/`, `waybar/`, `walker/` and `kitty/` are the live
config. Each `~/.config/<name>` is a **directory symlink** pointing at the repo:

```bash
ls -ld ~/.config/niri    # ~/.config/niri -> /etc/nixos/config-files/niri
```

So editing the repo copy *is* editing the live file, and there is no copy step and no link to break — a
rename-based write creates a new inode inside the symlinked directory, which the symlink still resolves
to. Any editor or tool is safe. To wire up a new one, `ln -s /etc/nixos/config-files/<name>
~/.config/<name>`.

> Earlier revisions of this file claimed these were **hardlinks** checked with `stat -c %i`, and warned
> that atomic writes silently break them. That was wrong on both counts. Hardlinks between the two paths
> are in fact impossible: `/` is btrfs subvolume `nixos-root` (subvolid 357) and `/home` is `nixos-home`
> (subvolid 375), so `ln` across them fails with `Invalid cross-device link`. The `stat -c %i` check did
> pass, which is why the error survived — but only because the symlink resolves to the same file. Do not
> reintroduce inode-preserving contortions such as `cat new > repo/file` to "protect the link"; that
> redirect truncates the target before the source is read, and destroys the file if the source is missing.

`config-files/walker/` is **walker 2.x format** (migrated 2026-09-04 from 0.13, which shared none of the
schema). Two things about it are easy to get wrong. walker is only a frontend: with no `elephant` daemon
on `$XDG_RUNTIME_DIR/elephant/elephant.sock` it starts, fails to connect and exits without mapping a
surface, so a bind firing `walker` looks like a broken keybind — `services.elephant.enable` in
`modules/desktop/niri.nix` is what prevents that. And an unrecognised key in `config.toml` is
*silently dropped* (`Walker::new` logs the deserialize error and carries on with defaults), which is why
the stale 0.13 file sat here for months looking fine while doing nothing. Both theme files carry their own
re-derive command against `pkgs.walker.src`; run those after a walker update rather than editing them
blind.

`config-files/mc/` is an ordinary directory, not linked — `~/.config/mc/` exists separately and holds only
`ini`/`panels.ini`, so `config-files/mc/mc.keymap` has no live counterpart at all. `config-files/vim/` and
`config-files/ti/` have no `~/.config` counterpart by design; they are the two wired into the build above.
A rebuild never deploys any of these.

**elephant needs a PATH the stock NixOS unit does not give it, or the launcher lists every application
and starts none of them.** elephant activates a `.desktop` entry by handing its `Exec` line to `sh -c`,
so launching anything needs a shell *and* the session's bin directories. The unit had neither, and
`Mod+P` → any application did nothing at all. Fixed 2026-09-19, now in `modules/desktop/niri.nix`:

```nix
systemd.user.services.elephant.environment.PATH = lib.mkForce null;
```

NixOS gives every systemd service a default `path` of coreutils/findutils/gnugrep/gnused/systemd and
writes it into the unit as an explicit `Environment=PATH=...`. That override **replaces** the PATH the
user manager would otherwise pass down, which is the whole bug: elephant inherits `XDG_DATA_DIRS`
covering the full session, so walker lists every application, while its PATH holds no `sh` and none of
the binaries. Setting `PATH` to null drops the `Environment=PATH=` line entirely and elephant falls back
to the manager's own PATH — `/run/wrappers/bin` plus the per-user and system profiles, i.e. what an app
started from a terminal gets. elephant's own wrapper prefixes (fd, libqalculate, wl-clipboard, …) are
unaffected; the wrapper prepends them to whatever it inherits.

**Do not "fix" this by adding `pkgs.bash` to `path` instead.** That satisfies `sh -c` and moves the
failure one level deeper, to `thunar: command not found`, because **23 of the 27** entries on this host
spell `Exec` as a bare command name (`thunar %U`, `kitty`, `code`, `nm-connection-editor`, …) rather
than an absolute store path. Count them before assuming a shell is enough — the inner `grep -m1` matters,
since `thunar.desktop` and several others carry further `Exec` lines for their desktop *actions*, which
are not launcher entries of their own and inflate the count to a tidy-looking 27 of 27:

```bash
for d in $(tr '\0' '\n' < /proc/$(systemctl --user show -p MainPID --value elephant.service)/environ \
             | grep '^XDG_DATA_DIRS=' | cut -d= -f2- | tr ':' ' '); do
  for f in "$d"/applications/*.desktop; do [ -e "$f" ] && grep -m1 '^Exec=' "$f"; done
done | sed 's/^Exec=//' | awk '{print $1}' | awk '{t++} !/^\//{b++} END{print b" bare of "t}'
```

The failure is invisible from the frontend — walker simply closes, exactly as if the keybind were broken,
which sends you to the keybinds in `config.kdl` and the `config.toml` above rather than to the daemon. **The daemon log
is the only place the real error appears**, so check it first whenever an entry does not start:

```bash
journalctl --user -u elephant -b | grep -i error
# ERROR desktopapplications activate=thunar.desktop
#   error="exec: \"sh\": executable file not found in $PATH"
```

The general shape is worth remembering for any user unit that launches user-chosen programs: a mismatch
between `XDG_DATA_DIRS` (inherited, full) and `PATH` (overridden, minimal) presents as "it can see
everything and run nothing". Compare the two directly on the running process:

```bash
tr '\0' '\n' < /proc/$(systemctl --user show -p MainPID --value elephant.service)/environ \
  | grep -E '^(PATH|XDG_DATA_DIRS)='
```

**`programs.git` in home-manager generates `~/.config/git/config`, and it is the only git config now.**
For a long time the block read `programs.git.settings = { enable = true; ... }` —
`enable` one level too deep, so `programs.git.enable` was false and no config was written at all. Two
things were wrong under it as well: `settings` is the renamed `extraConfig`, i.e. the gitconfig itself, so
its keys are git *sections*; and `userName`, `userEmail` and `aliases` were home-manager option names with
their own renames to `user.name`, `user.email` and `alias`. All three are fixed.

The hand-written `~/.gitconfig` that predated it has been folded in and moved aside to
`~/.gitconfig.replaced-by-home-manager`. It contributed `core.whitespace = cr-at-eol` and two
`safe.directory` entries; both of those are inert as things stand — `/etc/nixos` is owned by `ruben:users`
so git needs no exception for it, and `/home/ci/zt600-firmware` does not exist — but they were carried
over rather than dropped.

Note the ordering hazard this creates: home-manager only writes `~/.config/git/config` on a **switch**, so
between moving the old file aside and the next `nixos-rebuild switch` there is no global git config at all
and commits fail with "Author identity unknown". Switch, or move the file back.

**niri is the only session, on both hosts.** It replaced Hyprland on 2026-10-06 (GNOME and awesome had gone
earlier), so `defaultSession` is `niri` and `niri.desktop` is the only entry in `wayland-sessions/`. There
is no X11 session left, and therefore no non-Wayland fallback if the compositor will not start — the
rescue path is the TTY and ssh, below. The Hyprland config, its uwsm env files, and the long list of
Hyprland/aquamarine gotchas that used to fill this file are in git history
(`git log -- config-files/hypr modules/desktop/hyprland.nix`) if it ever comes back.

`services.xserver.enable` is nevertheless still `true`, and must stay that way. It lives in
`modules/hardware/nvidia-prime.nix` rather than in any desktop module, because it no longer has anything
to do with running an X session: `nixos/modules/hardware/video/nvidia.nix` gates
`boot.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_drm" ]` on it, so turning it off stops the
driver's kernel modules loading at boot and breaks PRIME offload. `services.xserver.videoDrivers` is read
independently of the flag (`lib.elem "nvidia" ...`), so it is the list, not `enable`, that turns the driver
on. Everything else under `services.xserver` that only shaped an X session has been removed
(`xrandrHeads`, `autoRepeatDelay`/`autoRepeatInterval`, `displayManager.startx`). What is left besides
`enable` is `videoDrivers` and `xkb.*` — and the `xkb.*` block stays because `console.useXkbConfig` reads
it, independently of whether X runs.

**There is deliberately no colour-temperature (night-light) service.** `services.redshift` used to run here
and was removed with the rest of the X11 leftovers: redshift talks RANDR/vidmode only. Under Hyprland it
failed twice at session start (`RANDR Query Version` returned error -1, then `XOpenDisplay` failed, exit 1)
and only survived because systemd's third restart landed after XWayland was up, so it attached to XWayland
and set gamma there rather than on the real Wayland outputs — healthy-looking logs, no effect. Do not
re-add it. The Wayland equivalents, all available as home-manager user services, are `services.gammastep`
(closest port) and `services.wlsunset`; `location` went too, and any of them would
need it back.

**niri: config, session startup, logs.** All of it is in `modules/desktop/niri.nix` and
`config-files/niri/config.kdl`.

- **Startup chain.** `niri.desktop` → `niri-session` → the `niri.service` *user* unit, which binds
  `graphical-session.target`. That target is what starts `waybar.service` and `elephant.service`, so if
  the bar is missing or walker sits on "waiting for elephant", check it first — it should be `active`:
  `systemctl --user is-active graphical-session.target niri.service`. No uwsm is involved any more.
- **Do not `spawn-at-startup "waybar"`** in `config.kdl`. `programs.waybar.enable` ships `waybar.service`,
  `WantedBy=graphical-session.target`, so that would stack a second bar on the unit's. `pgrep -a waybar`
  and the parent PID tell the two apart (PPID `systemd --user` is the unit).
- **Editing the config.** niri watches `config.kdl` and reloads on save; a broken file keeps the previous
  config and shows an error banner. Validate first, without touching the session:
  `niri validate -c ~/.config/niri/config.kdl`. Talk to the running compositor with `niri msg` (e.g.
  `niri msg outputs`, `niri msg action load-config-file`).
- **Session-wide environment** goes in an `environment {}` block in `config.kdl`; it is inherited by
  every client including XWayland ones, so a bad entry affects everything.
- **XWayland** is `xwayland-satellite`, spawned on demand by niri when it is on PATH. The package bakes in
  its own store path to Xwayland, which is why `programs.xwayland.enable` is false and nothing breaks.
- **Logs.** niri runs as a user unit, and journald is `Storage=persistent` here, so a session's full log
  survives a power cut: `journalctl --user -u niri -b -1`. There is no separate tmpfs log to rescue.
- **The tmux server outlives a logout**, so `users/ruben/default.nix` adds `NIRI_SOCKET` to
  `update-environment`; otherwise `niri msg` in old panes fails with "error connecting to the niri socket".
  Only panes created after a re-attach get the new value.
- **The laptop panel stays on when docked.** niri's config has no conditionals, and a static `off` would
  leave an undocked laptop with no display. Toggle it with `niri msg output eDP-1 off|on`.

**The rescue console is `Ctrl+Alt+F2` (or F3-F6) — the session itself is on VT1.** This inverted when
greetd replaced lightdm, and the old advice has become exactly the trap it was written to warn about.

lightdm allocated VTs upward from a hardcoded `minimum-vt = 1`, so the greeter took VT1 and the session
landed on VT2. greetd instead runs the greeter and then the session on the *same* VT. Measured on the
2026-09-11 boot:

```
$ loginctl show-session 3 -p VTNr -p Service   ->  VTNr=1, Service=greetd
$ systemctl list-units --all "getty@*"         ->  getty@tty1.service  inactive (dead)
```

`getty@tty1.service` is dead precisely because the session owns that terminal, so pressing `Ctrl+Alt+F1`
switches to the VT the compositor already holds: a silent no-op, not a dead TTY. No getty runs anywhere at
boot; `autovt@.service` is aliased to `getty@.service` and logind spawns one on demand on the first
unallocated VT, up to systemd's default `NAutoVTs=6`. Earlier revisions of this file recommended F1 for
the same reason a still earlier one recommended F2, and read the silence as evidence of a kernel or GPU
hang; both inferences were wrong, and the VT number has to be re-checked whenever the greeter changes.
Still true under niri: on 2026-10-06 the niri session was on `tty1`.

A working TTY means only the compositor is stuck, and `loginctl terminate-session <id>` drops you back to
the greeter (niri's log is in the persistent journal, so there is nothing to copy off first). In the
dead-input-devices failure below, no key reaches anything whichever VT you aim at: the compositor has no
evdev devices to see the chord on, and the compositor puts the VT keyboard in `K_OFF`, so the kernel will
not switch VTs either. The power button is ACPI rather than evdev and still works — logind handles a
short press and shuts down cleanly, which is why boot `dd8f587c` has a complete journal despite feeling
like a forced power-off. Start sshd first (below) so there is a real way in. `kernel.sysrq` is `16`
(sync only), so `Alt+SysRq+S` flushes but REISUB does not work unless you raise it to `1`.

**sshd is installed but deliberately not started at boot.** `modules/common/ssh.nix` sets
`services.openssh.enable = true`, and `hosts/zbook/default.nix` then sets
`systemd.services.sshd.wantedBy = lib.mkForce [ ]`, so the unit
exists, reads as `linked`, and sits `inactive` with nothing listening on 22. That is intentional — it is
started on demand with `sudo systemctl start sshd`. Do not "fix" the inactive unit. Starting it *before*
reproducing a compositor freeze is worth doing anyway: it gives you a second machine to debug from.

**History: the September 2026 "freezes" were dead input devices, not a wedged compositor.** Three Hyprland
sessions (boots `505ccbe8`, `dd8f587c`, `165360be`) came up drawn but with keyboard and mouse completely
dead. The compositor was alive throughout — it answered IPC over ssh instantly. Root cause, established
2026-09-04 from a live capture: **lightdm** started the new session's compositor *before* tearing the
greeter down, and the greeter then ignored SIGTERM for 90 s. While the greeter session was still active on
seat0, every `TakeDevice` fd logind handed the new session came back revoked, libinput rejected those
devices ("not using input device"), and it never re-enumerates. greetd fixes this by construction (the
greeter exits before the session starts) — see the comment in `modules/desktop/greetd.nix`. Login timing,
the lid, the GPU and the compositor config were all ruled out with evidence; do not re-chase them.

If a session ever comes up input-dead again, the first two checks are whether a greeter session is still
active on seat0 (`loginctl list-sessions`) and how many *real* input devices libinput rejected — a healthy
boot rejects some too (the accelerometer, ALSA jack-detection nodes), so map event numbers back to names:

```bash
awk -v ev="event14" 'BEGIN{RS="";FS="\n"} $0 ~ "Handlers=.*"ev"( |$)" {for(i=1;i<=NF;i++) if($i ~ /^N: Name=/) print $i}' /proc/bus/input/devices
```

Recovery over ssh that worked under Hyprland (untested under niri, but it is libinput/udev, not compositor,
behaviour): `sudo udevadm trigger --action=add --subsystem-match=input` re-adds rejected devices. A VT
bounce (`sudo sh -c 'chvt 2; sleep 2; chvt 1'`) destroys and re-creates every input device, which is also
why holding `Ctrl+Alt` across two VT switches fails on the third chord — the keyboard you return to is a
new object with no modifiers held. Release and re-press between bounces.

There is no gdb in the system profile; get a backtrace from a core without installing one:

```bash
nix shell nixpkgs#gdb --command coredumpctl debug <pid> --debugger-arguments='-batch -ex bt'
```
