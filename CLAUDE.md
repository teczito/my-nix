# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The NixOS configuration in `/etc/nixos`, for two x86_64-linux machines:

- **`zbook`** — HP ZBook Fury 15.6" G8 / Xeon W-11955M, Intel iGPU + discrete NVIDIA RTX A2000 on PRIME
  offload. This is the live system the agent runs on, so edits here change the machine under it.
- **`server`** — local LLM (ollama), VM host (libvirt/KVM), containers, and compiling things. Mainly
  headless with a monitor attached occasionally. **The hardware does not exist yet**:
  `hosts/server/hardware-configuration.nix` is a loudly-marked placeholder, to be replaced wholesale by
  what `nixos-generate-config` writes on the real machine.

There is no test suite; correctness is checked by evaluating and building the configuration — and the
server config builds fine from the laptop, which is the point of keeping the placeholder evaluable.

## Commands

```bash
# Fast feedback loop — evaluate a single option without building anything.
# This is the primary way to verify a change; prefer it over a full rebuild.
nix eval .#nixosConfigurations.zbook.config.services.displayManager.defaultSession
nix eval --raw .#nixosConfigurations.zbook.config.home-manager.users.ruben.programs.bash.shellAliases.kicad

nixos-rebuild build --flake /etc/nixos#zbook    # build only, no sudo, leaves ./result
nixos-rebuild dry-build --flake /etc/nixos#zbook
sudo nixos-rebuild switch --flake /etc/nixos#zbook

# The other host builds from here too -- it needs no hardware to evaluate or build.
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
- `modules/desktop/` — one import for the whole graphical stack: `greetd.nix`, `hyprland.nix`,
  `audio.nix`, `portals.nix`, `fonts.nix`, `apps.nix`.
- `modules/hardware/` — GPU and firmware. `nvidia-prime.nix` is the only one.
- `modules/services/` — daemons and timers, imported one by one: `backup.nix`, `builder.nix`,
  `devices.nix`, `docker.nix`, `llm.nix`, `printing.nix`, `virtualisation.nix`, `caddy.nix`.

`users/`, `pkgs/`, `overlays/` and `config-files/` stay at the top level because they are not per-host.

A module owns the packages its concern needs, so `environment.systemPackages` is defined in six places and
merged: `btrbk` in `backup.nix`, `hyprland` in `hyprland.nix`, `android-tools` in `devices.nix`, and so
on. Adding a package means finding the module that owns the concern, not editing one central list.

**What each host actually opts into.** The two differ almost entirely by which modules they import, not by
overrides:

| | zbook | server |
| --- | --- | --- |
| `modules/common` | yes | yes |
| `modules/desktop` | yes | yes — Hyprland for the occasional monitor |
| `users/ruben/desktop.nix` | yes | **no** — vscode/kicad and the bench groups stay on the laptop |
| `modules/hardware/nvidia-prime.nix` | yes | no |
| `backup`, `devices`, `printing` | yes | no |
| `docker` | yes | yes |
| `builder`, `llm`, `virtualisation` | no | yes |
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
`default.nix` was an empty import list; that directory is gone.

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
(in `hyprland.lua`, `environment.variables`, …) — that remains true now that the driver is installed, and
is a different thing from what `nvidia-offload` does. Setting them globally makes libglvnd hand
`libGLX_nvidia.so` to every GLX client including those on the Intel screen, where `glXCreateNewContext`
fails with BadValue; `nvidia-offload` sets them for one process only.

Because the NVIDIA card now exposes its own DRM node, Hyprland is pinned to the iGPU with
`export AQ_DRM_DEVICES=/dev/dri/igpu`. This lives in **`config-files/uwsm/env-hyprland`**, *not* as an
`hl.env()` call in `hyprland.lua`: the session is started by uwsm, which exports its environment before
launching the compositor, whereas `hyprland.lua` is not read until Hyprland is already up — too late to
influence which DRM device aquamarine opens.

**The export is guarded by `[ -e /dev/dri/igpu ]`.** `~/.config/uwsm` is the same symlink into this repo
on every host, but the `/dev/dri/igpu` alias is created by the udev rule in
`modules/hardware/nvidia-prime.nix`, which `hosts/zbook` imports and `hosts/server` does not. An
unconditional export therefore points aquamarine at a path that is not there on the server: it finds no
GPU and aborts with `CBackend::create() failed!` — from the greeter, indistinguishable from the login
itself failing. That is exactly what happened on 2026-09-18, the first time `~/.config/uwsm` was linked
on the server. A single-GPU host needs no pin at all, so leaving the variable unset there is the correct
outcome rather than a fallback. Anything else added to this file is host-shared the same way.

**`AQ_DRM_DEVICES` is a colon-separated list, like `PATH`.** This rules out the `by-path` name that looks
like the obvious stable choice: `/dev/dri/by-path/pci-0000:00:02.0-card` contains two colons of its own,
so aquamarine splits it into three nonexistent paths and logs

```
drm: Failed to canonicalize path /dev/dri/by-path/pci-0000
drm: Failed to canonicalize path 00
drm: Failed to canonicalize path 02.0-card
drm: Found no gpus to use, cannot continue
```

then dies with `CBackend::create() failed!` — a *session* failure that looks identical to the uwsm one
above from the greeter, but is not: here the compositor really did run, so
`/run/user/1000/hypr/<instance>/` and a crash report under `~/.cache/hyprland/` both exist. Note the DRM
backend failure is not the last line; aquamarine falls through to the Wayland backend, which fails with
its own misleading `wl_display_connect failed (is a wayland compositor running?)`. Read past it to
`Cannot open backend: no allocator available`, and further up to the canonicalize errors, which name the
real cause.

`/dev/dri/cardN` parses fine but the numbering is not stable across boots, so **`/dev/dri/igpu` is a udev
symlink defined in `modules/hardware/nvidia-prime.nix`**, matched on the iGPU's PCI slot rather than on a card number:

```
KERNEL=="card*", SUBSYSTEM=="drm", DEVPATH=="*/0000:00:02.0/drm/card*", SYMLINK+="dri/igpu"
```

That is a second definition of `services.udev.extraRules` alongside the TI rules in
`modules/services/devices.nix`; the option is `types.lines`, so the two merge rather than collide. It is
wrapped in `lib.mkBefore` so this rule lands *above* the TI rules in the generated file: `lines` options
merge in module order, and module order is NOT the order of a host's `imports` list — splitting these two
definitions into separate modules silently reversed them until the `mkBefore` was added. Current enumeration, for reference —
**NVIDIA is `card0`, the iGPU is `card1`** (all four displays hang off `card1`), the opposite of what
earlier revisions of this file claimed:

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

`config-files/hypr/`, `waybar/`, `walker/`, `kitty/`, and `uwsm/` are the live
config. Each `~/.config/<name>` is a **directory symlink** pointing at the repo:

```bash
ls -ld ~/.config/hypr    # ~/.config/hypr -> /etc/nixos/config-files/hypr
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
`services.elephant.enable` in `modules/desktop/hyprland.nix` is what prevents that. And an unrecognised key in `config.toml` is *silently dropped*
(`Walker::new` logs the deserialize error and carries on with defaults), which is why the stale 0.13 file
sat here for months looking fine while doing nothing. Both theme files carry their own re-derive command
against `pkgs.walker.src`; run those after a walker update rather than editing them blind.

`config-files/mc/` is an ordinary directory, not linked — `~/.config/mc/` exists separately and holds only
`ini`/`panels.ini`, so `config-files/mc/mc.keymap` has no live counterpart at all. `config-files/vim/` and
`config-files/ti/` have no `~/.config` counterpart by design; they are the two wired into the build above.
A rebuild never deploys any of these.

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

**Hyprland is the only session.** GNOME and awesome both used to be installed alongside it on X11; both
are gone, so `defaultSession` is `hyprland-uwsm` and `wayland-sessions/` holds the only entries the
greeter offers. There is no X11 session left, and therefore no non-Wayland fallback if the compositor
will not start — the rescue path is the TTY and ssh, below.

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
(closest port), `services.hyprsunset` and `services.wlsunset`; `location` went too, and any of them would
need it back.

Session-specific environment variables set in `~/.config/hypr/hyprland.lua` are inherited by every client
including XWayland ones, so a bad `hl.env()` line there affects everything in the session.

**`hyprland.lua`'s KEYBINDINGS section is now the only definition of the keymap.** It was originally a
bind-for-bind translation of awesome's `rc.lua`, which is why the layout looks the way it does; with
awesome removed there is no sibling file to keep in sync, and the `GAPS` block listing binds awesome could
express and Hyprland could not has gone with it. Two argument shapes there could not be exercised without a live
Hyprland session and are the first suspects if a key misbehaves: `hl.dsp.window.cycle_next("prev")`
(string passthrough, assumed) and whether `hl.dsp.window.resize({ x = 40, y = 0 })` is a delta or an
absolute size. Also note `addmaster`/`removemaster`/`swapwithmaster` are `layoutmsg`s that only the
**master** layout implements, and `general.layout` here is still dwindle — those three keys are no-ops
until `Mod+space` toggles the layout over.

The useful discovery trick for this API: the Lua bindings validate lazily, so `hl.dsp.*(...)` accepts
almost anything at construction time and `Hyprland --verify-config` will not catch a wrong option key.
The accepted keys are in the binary's own error strings instead.
`which Hyprland` is a setuid wrapper you cannot read, so go through the store path:

```bash
strings "$(nix eval --raw /etc/nixos#nixosConfigurations.zbook.config.programs.hyprland.package)/bin/.Hyprland-wrapped" \
  | grep -E '^hl\.[a-z_.]+:'
```

That prints lines like
`hl.window.move: unrecognized arguments. Expected one of: direction, x+y(+relative), workspace,
into_group, out_of_group`, which is how the missing `monitor` key (and so the need for the
`move_to_monitor` helper) was found. To check that every bind parsed and that none collide, prepend a
wrapper that shadows `hl.bind`, logs `kb.modmask`/`kb.key`, and run `--verify-config` on that copy.

Hyprland env changes need a full logout/login; `hyprctl reload` does not re-export them.

**Hyprland's config is Lua now (`config-files/hypr/hyprland.lua`), not `.conf`.** 0.56 shows
"You are using the .conf config format, support for which will be removed in Hyprland 0.57." on every
start; the fix is the Lua format, not a setting to silence it. Discovery is `hyprland.lua` first, then
`hyprland.conf` (`Jeremy::getMainConfigPath`) — with both present the `.conf` is simply dead weight, and
when *neither* exists Hyprland now writes a default `hyprland.lua`.

Validate any edit **without logging out**:

```bash
Hyprland --verify-config -c ~/.config/hypr/hyprland.lua
```

It is strict about `hl.config` keys, `hl.monitor`/`hl.workspace_rule` fields, unresolved `hl.curve` names
and nil dispatchers — but it does **not** validate `hl.bind`'s options table, where unknown keys are
silently ignored. To exercise the config for real, run a nested instance against the outer session
(`Hyprland -c <file>`, it opens a window) and query it with `hyprctl -i <instance> binds|getoption`;
diffing that against the live instance is how this file's conversion was checked.

Two conversion traps, both from upstream's own `share/hypr/hyprland.lua` example:

- There is **no `bindm` in Lua.** `hl.bind()` never sets the keybind's `mouse` flag, so the
  `{ mouse = true }` the example passes for `mouse:272`/`273` does nothing. Held-drag comes from the
  *dispatcher* — `hl.dsp.window.drag()`/`.resize()` issue `movewindow`/`resizewindow` in mouse mode and
  set `releasePending`. `{ drag = true }` is **not** the fix: it is an unrelated click-vs-drag option that
  also forces `release = true`. `hyprctl binds` prints these as `bind`, not `bindm`; that is cosmetic.
- `.conf` flag suffixes map to options, not syntax: `bindel` → `{ locked = true, repeating = true }`,
  `bindl` → `{ locked = true }`.

**`hl.get_monitors()` returns an empty list while the config is being parsed.** The backend enumerates
monitors *after* the Lua config is read, so anything in `hyprland.lua` that branches on the monitors
actually present cannot be written as a top-level `if`. The natural implementation of "disable the laptop
panel only when docked" —

```lua
if #hl.get_monitors() > 1 then hl.monitor({ output = LAPTOP, disabled = true }) end   -- never fires
```

— sees zero monitors on every start and silently does nothing. Verified with a probe config in a nested
instance (`Hyprland -c probe.lua`) that prints the list at each stage:

```
PROBE parse-time: 0 {}
PROBE monitor.added(WAYLAND-1): 1 {WAYLAND-1[]}
PROBE hyprland.start: 1 {WAYLAND-1[]}
```

So the decision has to be re-made from events — `hl.on("monitor.added"/"monitor.removed", …)`, with
`hl.on("hyprland.start", …)` as the reconciliation once every monitor is in, and `hl.on("config.reloaded",
…)` because a reload re-runs the static rules. That is how the MONITORS block in `hyprland.lua` now does
it, and the shape matters: the panel deliberately gets **no static rule of its own**, falling through to
the `output = ""` catch-all, so *enabled* is the state it holds whenever the handler has not run yet. An
undocked machine is then never left with no display at all. Do not "simplify" it back to a static
`disabled = true`.

Two related notes on this API. `hl.get_monitors()` lists only **enabled** monitors — the same split as
`hyprctl monitors` vs `hyprctl monitors all` — so a disabled panel is invisible to it and the reliable
test is to count the monitors that are *not* the panel. And guard the handler with a
"state already matches" early return: it calls `hl.monitor()`, which re-enters through the very events
that invoked it.

**Pin monitor modes explicitly; do not rely on `mode = "preferred"` when anything calls `hl.monitor()` at
runtime.** That call re-creates the outputs — their IDs visibly shift, `1,2,3` → `2,3,4` in
`hyprctl monitors` — and on re-creation `"preferred"` re-resolved all three 2560×1440 Iiyamas to
**1920×1080** and left them there. The failure is silent and points the wrong way: positions stay correct,
so the layout looks right while the resolution is wrong. `mode = "2560x1440@59.951"` survives it. The
full-resolution check after any monitor-rule change is:

```bash
hyprctl monitors | grep -E '^Monitor|^\s+[0-9]+x[0-9]+@'
```

**`hyprctl dispatch` changes syntax under a Lua config.** The argument is parsed as Lua rather than as a
dispatcher name plus arguments, so every classic invocation becomes a syntax error:

```
$ hyprctl dispatch exec kitty
error: [string "return hl.dispatch(exec kitty)"]:1: ')' expected near 'kitty'

 → Note: dispatch in lua is a shorthand for hl.dispatch(...), your syntax might need to be updated.
```

Write the Lua form instead — `hyprctl dispatch 'hl.dsp.exec_cmd("kitty")'`, `hyprctl dispatch
'hl.dsp.exit()'`. Nothing in this repo shells out to `hyprctl dispatch` (waybar's only `on-click` is a
bare `pavucontrol`), but ad-hoc commands and muscle memory break the moment `hyprland.lua` is the active
config. Note this cuts both ways when debugging: the same command has to change form depending on whether
the instance you are talking to was started from the `.lua` or the `.conf`.

**Do not delete `hyprland.conf` while a Hyprland session that loaded it is running.** The inotify watcher
(`CConfigWatcher::onInotifyEvent`) ignores the event mask and reloads on *any* event for a watched wd,
including the `IN_IGNORED` a deletion produces — and `reload()` reuses the `static`-cached config path, so
it re-parses a path that no longer exists and drops the live session to defaults. Creating `hyprland.lua`
is safe for the same reason: only config *files* are watched, never the directory, and the cached path
keeps the running session on `.conf` until the next login.

**A frozen Hyprland session leaves no usable log by default — fix that *before* reproducing one.** The
compositor writes to `/run/user/1000/hypr/<instance>/hyprland.log`, which is tmpfs, so a forced power-off
destroys the only record; and `debug:disable_logs` defaults on, so that file is nearly empty anyway. Put
this at the **top** of `hyprland.lua` — it only affects logging emitted after it is parsed:

```lua
hl.config({ debug = { disable_logs = false, enable_stdout_logs = true } })
```

`enable_stdout_logs` is the half that matters: under uwsm the compositor's stdout is journald, and
journald here is `Storage=persistent` (`/var/log/journal`), so the log survives the power cut. Read it
back with `journalctl -b -1 -t uwsm_hyprland.desktop`. It is verbose enough to hit journald's rate limit
(`RateLimitBurst` 10000 / 30 s), so keep it on only while chasing something.

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

A working TTY means only the compositor is stuck, and `loginctl terminate-session <id>` drops you back to
the greeter — copy `/run/user/1000/hypr/*/hyprland.log` onto `/home` first, it dies with the session. In
the dead-input-devices failure below, no key reaches anything whichever VT you aim at: the compositor has
no evdev devices to see the chord on, and Hyprland puts the VT keyboard in `K_OFF`, so the kernel will not
switch VTs either. The power button is ACPI rather than evdev and still works — logind handles a short
press and shuts down cleanly, which is why boot `dd8f587c` has a
complete journal despite feeling like a forced power-off. Start sshd first (below) so there is a real way
in. `kernel.sysrq` is `16` (sync only), so `Alt+SysRq+S` flushes but REISUB does not work unless you raise
it to `1`.

**sshd is installed but deliberately not started at boot.** `modules/common/ssh.nix` sets
`services.openssh.enable = true`, and `hosts/zbook/default.nix` then sets
`systemd.services.sshd.wantedBy = lib.mkForce [ ]`, so the unit
exists, reads as `linked`, and sits `inactive` with nothing listening on 22. That is intentional — it is
started on demand with `sudo systemctl start sshd`. Do not "fix" the inactive unit. Starting it *before*
reproducing a compositor freeze is worth doing anyway: it gives you a second machine to debug from.

**These "freezes" are dead input devices, not a wedged compositor.** Three sessions have failed this way
(boot `505ccbe8`, compositor started 21:42:59; boot `dd8f587c`, started 22:11:41; boot `165360be`, started
2026-09-04 06:55:36): the desktop stays drawn — waybar keeps rendering — but keyboard and mouse are both
completely dead, which reads as a total lockup. It is not one. The compositor's event loop is alive
throughout: on 2026-09-04 `hyprctl version`, `monitors` and `clients` all answered instantly over ssh.
What actually happened is that the compositor came up having opened few or **no usable input devices**:

```
[libinput] event0 … event28  - not using input device '/dev/input/eventN'     ← all 29 of them
```

| session | devices rejected | devices used |
| --- | --- | --- |
| clean enumeration (`~/.cache/hyprland/hyprlandCrashReport212.txt`) | 0 | 11 |
| frozen (PID 6519, boot `dd8f587c`) | 29 | 0 |
| frozen (PID 2309, boot `165360be`, 2026-09-04) | 17 | 6 |
| healthy greetd boot (2026-09-11) | 10 (all non-input) | 37 |

Report 212 is **not** a healthy session, whatever an earlier revision of this file claimed: it ends in
`Cannot open backend: no allocator available`, the `AQ_DRM_DEVICES` abort above. Only its *input
enumeration* is clean, which is the one thing it is good for. And a partial rejection is still a total
failure in practice — see the 2026-09-04 row and the second bug below.

Counting those two lines is the first thing to run after any freeze:

```bash
journalctl -b -1 -t uwsm_hyprland.desktop | grep -c 'not using input device'
journalctl -b -1 -t uwsm_hyprland.desktop | grep -cE 'libinput\] event[0-9]+ +- .*(is tagged by udev|device is a)'
```

The raw count is not by itself the diagnosis, though, because **a healthy boot rejects devices too**. The
2026-09-11 boot reports 10 rejected and 37 accepted, and all ten rejections are things libinput is right
to refuse: `ST LIS3LV02DL Accelerometer` and nine ALSA jack-detection nodes (`HDA NVidia HDMI/DP,pcm=*`,
`sof-hda-dsp Mic/Headphone/HDMI`). What matters is whether a *real* input device is in the rejected set,
so map the event numbers back before concluding anything:

```bash
awk -v ev="event14" 'BEGIN{RS="";FS="\n"} $0 ~ "Handlers=.*"ev"( |$)" {for(i=1;i<=NF;i++) if($i ~ /^N: Name=/) print $i}' /proc/bus/input/devices
```

Use `-b` rather than `-b -1` when you caught it live over ssh. If the session ran the `.conf` its `debug`
block is absent, stdout logs are off and the journal stops early — the full enumeration is then only in
`/run/user/1000/hypr/<instance>/hyprland.log`, whose tail is also buffered and can lag the live process.

`hyprctl devices` over ssh says the same thing while it is still happening: empty `mice` and `keyboards`.

**Root cause, established 2026-09-04: the greeter still owns seat0 while the compositor enumerates input.**
The 2026-09-04 failure (boot `165360be`, PID 2309) was caught live over ssh instead of being power-cycled,
and the journal is conclusive:

| time | event |
| --- | --- |
| 06:45:37.07 | greeter session `c1` (x11, seat0) created |
| 06:55:35.22 | session `6` (wayland) created — user logs in |
| 06:55:36.03 | Hyprland starts |
| ~06:55:36.3 | aquamarine enumerates input: 17 devices fail, the last 6 succeed |
| 06:55:36.5 | `Session is not active, waiting for 5s` → `[libseat] Enabling seat` |
| 06:55:36.86 | systemd *only now* sends SIGTERM to `session-c1.scope` |
| 06:57:06.97 | `session-c1.scope: Stopping timed out. Killing.` — the full 90 s, then SIGKILL |

lightdm starts the new session's compositor *before* it begins tearing the greeter down, and the greeter
then ignores SIGTERM for 90 s. While `c1` is still the active session on seat0, every `TakeDevice` fd
logind hands session 6 comes back revoked, the libevdev ioctls behind `evdev_configure_device` fail, and
libinput marks those devices unusable. **It never re-enumerates.** The rejection order in the log shows the
race directly — a clean cutover from failing to succeeding partway through enumeration:

```
event8,11,12,9,10,16,13,14,15,18..22,17,7,5   not using input device     (17, seat not yet active)
event4,3,2,0,1,6                              tagged by udev, accepted   (6, seat now active)
```

Note `Session is not active, waiting for 5s` appears in clean startups too, so its presence is *not* the
discriminator — the rejection count is.

**A second, independent bug turns a partial failure into a total one.** The 6 devices libinput *did*
create were created inside `CBackend::create()`, before Hyprland registers its `newInput` listener, so the
compositor never receives them either. That is why `hyprctl devices` was completely empty on 2026-09-04
even though libinput was holding 6 devices — including the built-in `AT Translated Set 2 keyboard`. Both
halves of the device set get lost, by two different routes.

**Corrected: how long you sat at the greeter is irrelevant.** An earlier revision of this file blamed
"logging back in too fast after the greeter respawns", inferred from an 11–14 s vs 21–73 s split across a
handful of sessions. The 2026-09-04 login came **10 minutes** after the greeter session appeared and failed
anyway. The variable is not the delay before logging in; it is whether lightdm's asynchronous,
sometimes-90-second greeter teardown happens to finish before the compositor enumerates input. Do not
re-chase login timing.

**Recovering a live session over ssh — no power-off needed. Verified end to end on 2026-09-04.** The
compositor is not hung: `hyprctl version`, `monitors` and `clients` all answer instantly and it keeps
rendering. Once the greeter is finally dead and the session owns seat0, run all three steps in order:

```bash
sudo udevadm trigger --action=add --subsystem-match=input     # 1. re-add the rejected devices
sudo sh -c 'chvt 1; sleep 2; chvt 2'                          # 2. flush the ones Hyprland cannot see
sudo udevadm trigger --action=add --subsystem-match=input     # 3. re-add them where Hyprland will see them
```

Step 1 recovers everything libinput rejected — on 2026-09-04 it brought back the touchpad, Intel HID and
video-bus keys, confirmed by real `event14` gesture and tap traffic in the log. It is a **no-op for the
devices libinput already holds**, so it cannot recover the built-in keyboard: those device objects exist,
they are just invisible to Hyprland (the `CBackend::create()` bug above).

Step 2 destroys them. A VT switch removes every input device and re-creates it — the log shows 13×
`device removed` → `Disabling seat` → `Enabling seat` → 13× `New device` on each bounce. **Do not stop
here**: on 2026-09-04 the resume repopulated nothing and left `hyprctl devices` completely empty, worse
than before. That is specific to the broken state — once the session is healthy, a bounce re-creates all
13 devices cleanly, which is why the gotcha below is a nuisance rather than a hazard. Note VT1, not VT2,
per the rescue-console entry above.

Step 3 is what finishes it, because the stale device objects are gone and Hyprland's `newInput` listener
has been registered since startup. Result was 12 devices in `hyprctl devices`: all three `elan074f`
touchpad nodes, `at-translated-set-2-keyboard`, and the hotkey and button devices — a fully usable desktop
with no reboot.

If it still fails, `loginctl terminate-session <id>` and a fresh login cost nothing when `hyprctl clients`
reports no open windows — but that re-runs the same race.

**Holding `Ctrl+Alt` across two VT switches does not work, and this is expected.** Bouncing
`Ctrl+Alt+F3` → `Ctrl+Alt+F2` → `Ctrl+Alt+F3` without releasing the modifiers fails on the third chord.
Because a VT switch destroys and re-creates every input device (above), the keyboard you return to is a
new object with fresh xkb state holding no modifiers — the physical `Ctrl+Alt` keydown landed on a device
that no longer exists. `F3` then arrives as a plain `F3` rather than `XF86Switch_VT_3`. Release and
re-press the modifiers between bounces. The middle hop is unaffected because the kernel's VT keyboard
handler keeps its own modifier state; only hops originating from the compositor's VT lose it.

Ruled out with evidence, so do not re-chase: **the Lua config** (the first freeze in boot `dd8f587c` ran
the `.conf`, and so did the whole 2026-09-04 failure — `hyprland.lua` was missing from the worktree at the
time, so Hyprland fell back to the legacy config and failed identically; the two were also diffed in a
nested instance and are equivalent — the same 51 binds with the
same modmasks and keys, identical `hyprctl workspacerules`, identical resolved values across ~50 options,
`getoption` printing Lua-set booleans as `bool: true` where hyprlang prints `int: 1`); **a GPU or kernel
hang** (no `i915` error, no hung task, no reset in any of these boots); **an event-loop wedge** (the render
loop demonstrably kept running throughout); and **the lid** — an earlier revision of this file chased "the
only session ever started with the lid closed", but the second freeze had the lid open and looks identical.

**Every clean Hyprland exit ends in a SIGSEGV; ignore it.** `coredumpctl` fills up with
`.Hyprland-wrapped` SIGSEGV entries whose backtrace is identical every time and lands entirely *after*
`main()` has returned:

```
__libc_start_call_main → exit → _dl_fini → __do_global_dtors_aux (libaquamarine)
  → ~CBackend → ~CDRMBackend → SDRMConnector::disconnect()
  → cancelAsyncOutput() → flushAsyncCommitEvents()        ← null deref
```

That is a teardown bug in aquamarine 0.15.0's static destructors, reached only once
`Hyprland has reached the end` has been logged. It cannot freeze or kill a live session; it just makes
every normal logout look like a crash. Both 2026-09-03 SIGSEGV cores (21:37:37 and 22:11:18) are this and
nothing else. Distinguish it from the genuine startup failure, which is a **SIGABRT** in
`CCompositor::initServer` → `throwError` — the `AQ_DRM_DEVICES` case above. A third shape exists too: a
SIGSEGV whose `main` sits under `systemInfoRequest` is the `hyprctl` client crashing, not the compositor.

There is no gdb in the system profile; get a backtrace without installing one:

```bash
nix shell nixpkgs#gdb --command coredumpctl debug <pid> --debugger-arguments='-batch -ex bt'
```

`~/.cache/hyprland/hyprlandCrashReport*.txt` is *not* written for every core — the SIGABRTs got reports,
these SIGSEGVs did not — so `coredumpctl list` is the reliable index of what actually crashed, not that
directory. Those reports do carry a ~50-line log tail, which is the only surviving record of a session
whose `/run/user/1000/hypr/<instance>/hyprland.log` died with the reboot.

Do not try to test keybinds by injecting keys into a nested instance. `wtype` reaches the seat but never
triggers the bind handler, and a `.conf` control instance fails identically — the result is void either
way, so it proves nothing about the Lua binds.

**Hyprland is started by uwsm, and this is not optional.** uwsm needs its own systemd *user* units
(`wayland-session-bindpid@`, `wayland-wm@`, `wayland-wm-env@`, …), and those only exist because
`programs.hyprland.withUWSM = true` pulls in the uwsm module, which adds the package to
`systemd.packages`. Without it the session dies straight back to the greeter, with the compositor never
exec'd at all:

```
systemctl[…]: Failed to start wayland-session-bindpid@<pid>.service: Unit … not found.
uwsm[<pid>]: Command '['systemctl','--user','start','wayland-session-bindpid@<pid>.service']'
             returned non-zero exit status 5.
```

When diagnosing that one, note that `uwsm start` execs in place, so the PID keeps its identity and shows
up in the journal as `python3.x` — and a genuine Hyprland failure would instead leave log lines under
`/run/user/1000/hypr/<instance>/`; if that directory does not exist, the compositor never ran.

**The hyprland package registers two session entries and only one of them uses uwsm.** An earlier revision
of this file claimed both route through uwsm and that `start-hyprland` "unconditionally execs into uwsm".
Both claims are wrong, and believing them costs a working session:

| entry | `Exec` | uwsm? |
| --- | --- | --- |
| `hyprland.desktop` | `…/bin/start-hyprland` | **no** |
| `hyprland-uwsm.desktop` | `…/bin/uwsm start -e -D Hyprland hyprland.desktop` | yes |

`start-hyprland` is not a uwsm shim. It is a small ELF watchdog that forks `Hyprland --watchdog-fd N`
directly — `strings` on it contains no `uwsm` at all, only `fork`/`waitpid`/`prctl`/`execvp`:

```bash
strings "$(nix eval --raw /etc/nixos#nixosConfigurations.zbook.config.programs.hyprland.package)/bin/start-hyprland" | grep -ci uwsm   # 0
```

`programs.hyprland.withUWSM` does **not** change this — it only sets `programs.uwsm.enable`, while the
module's `services.displayManager.sessionPackages = [ cfg.package ]` picks up *both* `.desktop` files. So
"Hyprland" and "Hyprland (uwsm-managed)" both appear in the greeter, and choosing the first one starts the
compositor as a bare process in `session-N.scope`.

**That failure is silent and does not look like a session problem.** The desktop comes up and works. What
is missing is everything uwsm was responsible for:

- `graphical-session.target` is never reached, so every user unit bound to it stays dead. `elephant.service`
  is `WantedBy=graphical-session.target`, so walker opens and sits on **"waiting for elephant"** — which
  reads as a walker or keybind bug, not a session-manager one.
- `config-files/uwsm/env{,-hyprland}` is never sourced, so `AQ_DRM_DEVICES=/dev/dri/igpu` is not exported
  and aquamarine picks a DRM device on its own.

Diagnose it in one line — under uwsm this is `active`, otherwise `inactive`:

```bash
systemctl --user is-active graphical-session.target
```

Do **not** corroborate with `pgrep -x start-hyprland`. An earlier revision of this file claimed any hit
means no uwsm, and that is backwards: `hyprland-uwsm.desktop` runs `uwsm start -e -D Hyprland
hyprland.desktop`, i.e. it hands uwsm *the other entry*, whose `Exec` is `start-hyprland`. So in a
correctly uwsm-managed session `start-hyprland` is the compositor process. What separates the two cases is
its parent and cgroup — from the healthy 2026-09-11 boot:

```
$ ps -o ppid= -p $(pgrep -x start-hyprland)    ->  systemd --user
$ cat /proc/$(pgrep -x start-hyprland)/cgroup
0::/user.slice/user-1000.slice/user@1000.service/session.slice/wayland-wm@hyprland.desktop.service
```

A non-uwsm session leaves it in a bare `session-N.scope` instead. Corroborate with `journalctl -b | grep -c
uwsm` (zero for a whole boot means the non-uwsm entry ran). The
journal identifier differs too: uwsm sessions log as `uwsm_hyprland.desktop`, which is what every log-reading
recipe in this file assumes.

`services.greetd` in `modules/desktop/greetd.nix` therefore does not hand tuigreet
`displayManager.sessionData.desktops` directly. It passes a filtered copy — a `runCommand` that deletes
`wayland-sessions/hyprland.desktop` — so the trap entry cannot be selected at all. lightdm hid the problem
only because it happened to be pointed at the uwsm entry; tuigreet lists whatever is in the directory and
`--remember-session` then pins the wrong choice across reboots.

Environment for the session belongs in `config-files/uwsm/env` (all compositors) or
`config-files/uwsm/env-hyprland` (Hyprland only, matched by lowercased `XDG_CURRENT_DESKTOP`). These are
sourced as POSIX shell — variables need `export`, unlike the `hl.env(K, V)` syntax of `hyprland.lua` — and
they are applied *before* the compositor starts, which is why anything affecting device or backend
selection has to go there rather than in `hyprland.lua`.

**Do not autostart waybar from `hyprland.lua`.** `programs.waybar.enable` puts the package into
`systemd.packages`, and the package ships its own `waybar.service` with `WantedBy=graphical-session.target`
— a target only uwsm reaches. So under the uwsm session the unit already runs the bar, and the
`hl.exec_cmd("waybar")` that used to sit in the `hyprland.start` hook produced a *second* one stacked on the
first. Diagnose with `pgrep -a waybar` and check the parents: PPID `systemd --user` is the unit, PPID the
compositor is the config. The unit is the one to keep (`Restart=on-failure`, `ExecReload` sends SIGUSR2,
dies with the session). Note `hyprland.conf` still carries `exec-once = waybar`; that is deliberate, since a
non-uwsm session never reaches `graphical-session.target` and so never starts the unit.
