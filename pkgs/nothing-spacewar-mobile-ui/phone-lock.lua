-- SPDX-License-Identifier: MIT
hl.config({ misc = { key_press_enables_dpms = false, mouse_move_enables_dpms = false } })
o.rebind("XF86PowerOff", "Power press", "omarchy-shell lock powerPress", { locked = true })
o.bind("XF86PowerOff", "Power release", "omarchy-shell lock powerRelease",
  { locked = true, release = true, ignore_mods = true, transparent = true, non_consuming = true })
