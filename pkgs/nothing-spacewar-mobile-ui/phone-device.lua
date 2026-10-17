-- SPDX-License-Identifier: MIT
hl.monitor({ output = "DSI-1", scale = 2 })
hl.config({ cursor = { hide_on_touch = true }, general = { layout = "scrolling" },
  scrolling = { column_width = 1.0 } })
hl.plugin.load("/usr/lib/hyprgrass/libhyprgrass.so")
