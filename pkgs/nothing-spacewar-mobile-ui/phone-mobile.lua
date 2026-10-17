-- SPDX-License-Identifier: MIT
hl.config({ input = { kb_layout = "us,ru", touchdevice = { output = "DSI-1" } } })

local hg = hl.plugin.hyprgrass
if hg then
  hl.config({ plugin = { hyprgrass = { sensitivity = 2.0, edge_margin = 24, long_press_delay = 450 } } })
  hg.bind({ pattern = { kind = "edge", origin = "u", direction = "d" },
    action = hl.dsp.exec_cmd("spacewar-mobile shade") })
  -- Android-style Back from either side edge; the right edge is free once the Omarchy bar moves to the top.
  hg.bind({ pattern = { kind = "edge", origin = "l", direction = "r" },
    action = hl.dsp.exec_cmd("spacewar-mobile back") })
  hg.bind({ pattern = { kind = "edge", origin = "r", direction = "l" },
    action = hl.dsp.exec_cmd("spacewar-mobile back") })
end
-- The bottom strip (Navigation.qml) owns swipe/hold timing: hyprgrass's pinned
-- edge callback has no duration or begin/update events. No competing bottom bind.
