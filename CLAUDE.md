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
(in `hyprland.lua`, `environment.variables`, …) — that remains true now that the driver is installed, and
is a different thing from what `nvidia-offload` does. Setting them globally makes libglvnd hand
`libGLX_nvidia.so` to every GLX client including those on the Intel screen, where `glXCreateNewContext`
fails with BadValue; `nvidia-offload` sets them for one process only.

Because the NVIDIA card now exposes its own DRM node, Hyprland is pinned to the iGPU with
`export AQ_DRM_DEVICES=/dev/dri/igpu`. This lives in **`config-files/uwsm/env-hyprland`**, *not* as an
`hl.env()` call in `hyprland.lua`: the session is started by uwsm, which exports its environment before
launching the compositor, whereas `hyprland.lua` is not read until Hyprland is already up — too late to
influence which DRM device aquamarine opens.

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
symlink defined in `nvidia-prime.nix`**, matched on the iGPU's PCI slot rather than on a card number:

```
KERNEL=="card*", SUBSYSTEM=="drm", DEVPATH=="*/0000:00:02.0/drm/card*", SYMLINK+="dri/igpu"
```

That is a second definition of `services.udev.extraRules` alongside the TI rules in `configuration.nix`;
the option is `types.lines`, so the two merge rather than collide. Current enumeration, for reference —
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

- `config-files/vim/.vimrc` → `programs.vim.extraConfig` in `users/ruben.nix`
- `config-files/ti/71-ti-permissions.rules` → `services.udev.extraRules` in `configuration.nix`

`config-files/hypr/`, `awesome/`, `waybar/`, `walker/`, `autorandr/`, `kitty/`, and `uwsm/` are the live
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
`configuration.nix` is what prevents that. And an unrecognised key in `config.toml` is *silently dropped*
(`Walker::new` logs the deserialize error and carries on with defaults), which is why the stale 0.13 file
sat here for months looking fine while doing nothing. Both theme files carry their own re-derive command
against `pkgs.walker.src`; run those after a walker update rather than editing them blind.

`config-files/mc/` is an ordinary directory, not linked — `~/.config/mc/` exists separately and holds only
`ini`/`panels.ini`, so `config-files/mc/mc.keymap` has no live counterpart at all. `config-files/vim/` and
`config-files/ti/` have no `~/.config` counterpart by design; they are the two wired into the build above.
A rebuild never deploys any of these.

**Three desktop sessions coexist and diverge.** GNOME and awesome run on X11 (`defaultSession` is
`none+awesome`), Hyprland runs on Wayland. Session-specific environment variables set in
`~/.config/hypr/hyprland.lua` are inherited by every client including XWayland ones, so a bad `hl.env()`
line there produces symptoms that appear only under Hyprland and not under awesome.

**The Hyprland keybinds are a deliberate translation of the awesome ones, and the two drift apart if
edited alone.** `hyprland.lua`'s KEYBINDINGS section mirrors `rc.lua`'s `globalkeys`/`clientkeys`/tag
loop bind for bind, and each line names the awesome key it came from; the section ends in a `GAPS`
comment listing the rc.lua binds that Hyprland's model cannot express (`incncol`, `client.restore`,
the Lua eval prompt, viewing or tagging a client onto several tags at once). Change a binding in one
file and change it in the other. Two argument shapes there could not be exercised without a live
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
strings "$(nix eval --raw /etc/nixos#nixosConfigurations.nixos.config.programs.hyprland.package)/bin/.Hyprland-wrapped" \
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

**The rescue console is `Ctrl+Alt+F1`, not `F2` — the session itself is on VT2.** lightdm allocates VTs
upward from `minimum-vt = 1`, which is hardcoded in the nixpkgs lightdm module (`services.xserver.tty` was
removed upstream as "ineffective", so there is no option to change it). The greeter therefore takes VT1 and
the user session lands on VT2 — `loginctl show-session <id> -p VTNr` confirms `VTNr=2` — and `agetty` runs
on tty2 as well, so the two overlap. `Ctrl+Alt+F2` switches to the VT the compositor already owns: a silent
no-op, not a dead TTY. Earlier revisions of this file recommended F2 and read its silence as evidence of a
kernel or GPU hang; that inference was wrong.

A working TTY means only the compositor is stuck, and `loginctl terminate-session <id>` drops you back to
the greeter — copy `/run/user/1000/hypr/*/hyprland.log` onto `/home` first, it dies with the session. In
the dead-input-devices failure below, no key reaches anything whichever VT you aim at: the compositor has
no evdev devices to see the chord on, and Hyprland puts the VT keyboard in `K_OFF`, so the kernel will not
switch VTs either. The power button is ACPI rather than evdev and still works — logind handles a short
press and shuts down cleanly, which is why boot `dd8f587c` has a
complete journal despite feeling like a forced power-off. Start sshd first (below) so there is a real way
in. `kernel.sysrq` is `16` (sync only), so `Alt+SysRq+S` flushes but REISUB does not work unless you raise
it to `1`.

**sshd is installed but deliberately not started at boot.** `configuration.nix` sets
`services.openssh.enable = true` and then `systemd.services.sshd.wantedBy = lib.mkForce [ ]`, so the unit
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

Report 212 is **not** a healthy session, whatever an earlier revision of this file claimed: it ends in
`Cannot open backend: no allocator available`, the `AQ_DRM_DEVICES` abort above. Only its *input
enumeration* is clean, which is the one thing it is good for. And a partial rejection is still a total
failure in practice — see the 2026-09-04 row and the second bug below.

Counting those two lines *is* the diagnosis, and it is the first thing to run after any freeze:

```bash
journalctl -b -1 -t uwsm_hyprland.desktop | grep -c 'not using input device'
journalctl -b -1 -t uwsm_hyprland.desktop | grep -cE 'libinput\] event[0-9]+ +- .*(is tagged by udev|device is a)'
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
strings "$(nix eval --raw /etc/nixos#nixosConfigurations.nixos.config.programs.hyprland.package)/bin/start-hyprland" | grep -ci uwsm   # 0
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

Corroborate with `pgrep -x start-hyprland` (any hit means no uwsm: under uwsm the compositor has no such
parent), and with `journalctl -b | grep -c uwsm` (zero for a whole boot means the non-uwsm entry ran). The
journal identifier differs too: uwsm sessions log as `uwsm_hyprland.desktop`, which is what every log-reading
recipe in this file assumes.

`services.greetd` in `configuration.nix` therefore does not hand tuigreet
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
