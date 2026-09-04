-------------------------------
---- TEMPORARY: FREEZE DEBUG --
-------------------------------
--
-- Added 2026-09-03 while chasing a session freeze under the Lua config: the
-- desktop stayed drawn (waybar visible on all four outputs) but neither
-- keyboard nor mouse responded, and the only way out was the power button.
--
-- The freeze left no evidence the first time, because Hyprland's own log goes
-- to $XDG_RUNTIME_DIR/hypr/<instance>/hyprland.log -- which lives on tmpfs and
-- is destroyed by a power cut -- and because debug:disable_logs suppresses
-- almost everything by default.
--
-- These two lines fix that:
--   disable_logs       = false  -- actually emit the logs
--   enable_stdout_logs = true   -- send them to stdout, which under uwsm is
--                                  journald. journald here is Storage=persistent
--                                  (/var/log/journal), so the log survives a
--                                  hard power-off and is readable afterwards with
--                                      journalctl -b -1 -t uwsm_hyprland.desktop
--
-- This block MUST stay at the top of the file: it only affects logging emitted
-- after it is parsed, so anything above it is still lost.
--
-- Cost: this is genuinely verbose. Expect journald to rate-limit it
-- (RateLimitBurst defaults to 10000 messages / 30s) and a few MB per session in
-- /var/log/journal. DELETE THIS WHOLE BLOCK once the freeze is understood.

hl.config({
    debug = {
        disable_logs       = false,
        enable_stdout_logs = true,
    },
})


------------------
---- MONITORS ----
------------------

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
hl.monitor({ output = "desc:Iiyama North America PL2796QS 1179915302805", mode = "preferred", position = "0x0",    scale = 1 })
hl.monitor({ output = "desc:Iiyama North America PL2796QS 1179911801568", mode = "preferred", position = "2560x0", scale = 1 })
hl.monitor({ output = "desc:Chimei Innolux Corporation 0x15F6",           mode = "preferred", position = "5120x0", scale = 1 })
hl.monitor({ output = "",                                                mode = "preferred", position = "auto",   scale = 1 })

hl.workspace_rule({ workspace = "1", monitor = "desc:Iiyama North America PL2796QS 1179915302805", default = true })
hl.workspace_rule({ workspace = "2", monitor = "desc:Iiyama North America PL2796QS 1179911801568", default = true })
hl.workspace_rule({ workspace = "3", monitor = "desc:Chimei Innolux Corporation 0x15F6",           default = true })


---------------------
---- MY PROGRAMS ----
---------------------

-- Set programs that you use
local terminal    = "kitty"
local fileManager = "thunar"
local webbrowser  = "brave"
-- local menu     = "wofi --show drun"
local menu        = "walker"
local tmux        = "kitty bash -c 'tmux new-session -A -s main'"
local mc          = "kitty mc"


-------------------
---- AUTOSTART ----
-------------------

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:

hl.on("hyprland.start", function()
    hl.exec_cmd("waybar")
    -- hl.exec_cmd(terminal)
    -- hl.exec_cmd("nm-applet")
end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- NOTE: AQ_DRM_DEVICES is deliberately NOT set here. It lives in
-- config-files/uwsm/env-hyprland (= ~/.config/uwsm/env-hyprland) instead.
--
-- The session is started by uwsm (programs.hyprland.withUWSM), and uwsm exports
-- its environment before it launches the compositor. An hl.env() call in this
-- file is only read once Hyprland is already up, which is too late to affect
-- which DRM device aquamarine opens -- so the iGPU pin has to be set in the
-- uwsm environment, not here.

-- NOTE: do NOT set LIBVA_DRIVER_NAME or __GLX_VENDOR_LIBRARY_NAME to "nvidia"
-- here -- not even now that the NVIDIA driver is installed. Setting them
-- session-wide makes libglvnd hand libGLX_nvidia.so to *every* GLX client,
-- including the ones running on the Intel screen, where glXCreateNewContext
-- fails with BadValue. XWayland apps using GLX (KiCad's OpenGL/GAL canvas) then
-- silently drop to the software Cairo canvas.
--
-- The supported way to reach the NVIDIA card is per-process, via the
-- `nvidia-offload` wrapper, which sets those variables for one command only.


-----------------------
----- PERMISSIONS -----
-----------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
-- Please note permission changes here require a Hyprland restart and are not applied on-the-fly
-- for security reasons

-- hl.config({
--   ecosystem = {
--     enforce_permissions = true,
--   },
-- })

-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")


-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 2,
        gaps_out = 2,

        border_size = 2,

        col = {
            active_border   = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        -- layout = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = "rgba(1a1a1aee)",
        },

        blur = {
            enabled  = true,
            size     = 3,
            passes   = 1,

            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint",   { type = "bezier", points = { { 0.23, 1 },    { 0.32, 1 }   } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 }   } })
hl.curve("linear",         { type = "bezier", points = { { 0, 0 },       { 1, 1 }      } })
hl.curve("almostLinear",   { type = "bezier", points = { { 0.5, 0.5 },   { 0.75, 1.0 } } })
hl.curve("quick",          { type = "bezier", points = { { 0.15, 0 },    { 0.1, 1 }    } })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint",  style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",        style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint",  style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",        style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear",  style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear",  style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear",  style = "fade" })

-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
    dwindle = {
        preserve_split = true, -- You probably want this
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

hl.config({
    misc = {
        force_default_wallpaper = -1,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = false, -- If true disables the random hyprland logo / anime girl background. :(
    },
})


---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "se,us",
        kb_options = "grp:ctrls_toggle",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = true,
        },
    },
})

-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})


---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- My Programs
hl.bind(mainMod .. " + return",         hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + SHIFT + return", hl.dsp.exec_cmd(tmux))
hl.bind(mainMod .. " + W",              hl.dsp.exec_cmd(webbrowser))
hl.bind(mainMod .. " + M",              hl.dsp.exec_cmd(mc))
hl.bind(mainMod .. " + E",              hl.dsp.exec_cmd(fileManager))

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exit())
hl.bind(mainMod .. " + V",         hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P",         hl.dsp.exec_cmd(menu))
-- hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())        -- dwindle
-- hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))  -- dwindle

-- Move focus with mainMod + HJKL
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Move to next/previous workspace
hl.bind(mainMod .. " + O", hl.dsp.window.move({ workspace = "+1" }))
hl.bind(mainMod .. " + I", hl.dsp.window.move({ workspace = "-1" }))

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging.
-- These are the old `bindm` lines. There is no `bindm` equivalent in the Lua
-- API: hl.bind() never sets the keybind's `mouse` flag, so the `{ mouse = true }`
-- opt that upstream's example/hyprland.lua passes here is silently ignored
-- (unknown bind opts are not validated). The held-drag behaviour comes from the
-- dispatcher instead -- hl.dsp.window.drag()/resize() dispatch movewindow /
-- resizewindow in mouse mode and set releasePending -- which is exactly what
-- `bindm` did. Do NOT "fix" this with { drag = true }: that is an unrelated
-- click-vs-drag opt that also forces release = true.
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize())

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example windowrule
-- hl.window_rule({
--     name  = "float-kitty",
--     match = { class = "^(kitty)$", title = "^(kitty)$" },
--     float = true,
-- })
