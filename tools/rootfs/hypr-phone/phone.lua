-- DRAFT: Nothing Phone (1) overrides for Omarchy 4.0.4 (Hyprland 0.56.2 Lua).
-- Install as ~/.config/hypr/phone.lua and add require("hypr.phone") to
-- ~/.config/hypr/hyprland.lua after require("hypr.autostart"). Sources: README.md.
-- Parts marked UNVERIFIED have no confirming source or were not run on the phone.

local panel = "DSI-1" -- UNVERIFIED: connector name; check `hyprctl monitors all`

-- 2.5: 402 ppi / 2.5 = 161 ppi per logical px (Android's 160 dp baseline);
-- 1080/2.5 and 2400/2.5 are whole (432x960) and 2.5 = 300/120 for fractional-scale-v1.
hl.monitor({ output = panel, mode = "preferred", position = "0x0", scale = 2.5, transform = 0 })

hl.config({
  input = {
    touchdevice = { output = panel },
  },
  cursor = { invisible = true, hide_on_touch = true },
  gestures = { workspace_swipe_touch = true, workspace_swipe_cancel_ratio = 0.15 },
})

-- Phone width is 432 logical px: tiled or desktop-sized floating windows are unusable.
-- From derekross/omarchy-mobile packages/omamobile-shell/hypr/phone.lua:9-10 (MIT).
hl.window_rule({ match = { class = ".*" }, tag = "-floating-window" })
hl.window_rule({ match = { class = ".*" }, maximize = true })

-- squeekboard reads this GSettings key before it shows itself
-- (omamobile-setup-user:102, omamobile-shell/hypr/phone.lua:55).
if o.cmd_present("squeekboard") then
  o.launch_on_start("gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true")
  o.launch_on_start("squeekboard")
end

local osk_show = "busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b true"

local function next_window()
  hl.dispatch(hl.dsp.window.cycle_next())
  hl.dispatch(hl.dsp.window.bring_to_top())
end

-- hyprgrass is not packaged (ALARM/omarchy repo); without it only the built-in
-- edge workspace swipe above and the bar work. UNVERIFIED: whether
-- hl.plugin.hyprgrass exists on the first config pass when hyprpm loads it later.
o.exec_on_start("hyprpm reload -n")

if hl.plugin.hyprgrass then
  hl.config({
    plugin = {
      hyprgrass = {
        sensitivity = 4.0,
        long_press_delay = 400,
        edge_margin = 30, -- UNVERIFIED: physical or logical px
      },
    },
  })

  local hg = hl.plugin.hyprgrass
  hg.bind({ pattern = { kind = "edge", origin = "down", direction = "up" }, action = hl.dsp.exec_cmd("omarchy-menu toggle apps") })
  hg.bind({ pattern = { kind = "edge", origin = "up", direction = "down" }, action = hl.dsp.exec_cmd("omarchy-menu toggle") })
  hg.bind({ pattern = { kind = "edge", origin = "right", direction = "left" }, action = hl.dsp.exec_cmd(osk_show) })
  hg.bind({ pattern = { kind = "swipe", fingers = 3, direction = "left" }, action = next_window })
  hg.bind({ pattern = { kind = "swipe", fingers = 3, direction = "right" }, action = next_window })
  hg.bind({ pattern = { kind = "swipe", fingers = 3, direction = "down" }, action = hl.dsp.window.close() })
end
