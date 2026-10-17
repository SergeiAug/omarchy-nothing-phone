-- SPDX-License-Identifier: MIT
hl.monitor({ output = "DSI-1", scale = 2 })
hl.config({ input = { kb_layout = "us,ru", touchdevice = { output = "DSI-1" } }, cursor = { hide_on_touch = true }, general = { layout = "scrolling" },
  scrolling = { column_width = 1.0 } })

-- Static placement must not depend on dynamic tags: v0.56.2 applies
-- setStaticProps between readStaticRules and the tag-dependent recheck.
hl.window_rule({ match = { float = false }, tag = "-floating-window",
  float = false, maximize = true, workspace = "empty" })
for _, match in ipairs({ { float = true }, { modal = true },
  { xdg_tag = ".*[Dd]ialog.*" },
  { class = ".*(xdg-desktop-portal|[Pp]olkit|[Pp]olicykit|[Ff]ile[Cc]hooser|gcr-prompter).*" } }) do
  hl.window_rule({ match = match, tag = "+spacewar-dialog", float = true,
    maximize = false, fullscreen = false, workspace = "unset", size = "", center = true })
end
hl.window_rule({ match = { class = "^org.omarchy.screensaver$" }, maximize = false, fullscreen = true })

function spacewar_fit_dialogs()
  for _, w in ipairs(hl.get_windows()) do
    local dialog = false
    for _, tag in ipairs(w.tags) do
      if tag == "spacewar-dialog" or tag == "spacewar-dialog*" then dialog = true end
    end
    if dialog and w.mapped and w.floating and w.monitor then
      local m, win = w.monitor, "address:" .. w.address
      local r = m.reserved
      -- Four logical pixels per side keep the window border inside the work area.
      local width = math.max(1, m.size.width / m.scale - r.left - r.right - 8)
      local height = math.max(1, m.size.height / m.scale - r.top - r.bottom - 8)
      hl.dsp.window.set_prop({ window = win, prop = "min_size", value = "1 1" })()
      hl.dsp.window.set_prop({ window = win, prop = "max_size", value = width .. " " .. height })()
      local s = w.size
      hl.dsp.window.move({ window = win,
        x = m.position.x + r.left + 4 + (width - s.x) / 2,
        y = m.position.y + r.top + 4 + (height - s.y) / 2 })()
    end
  end
end
hl.on("window.open", spacewar_fit_dialogs)
hl.on("layer.opened", spacewar_fit_dialogs)
hl.on("layer.closed", spacewar_fit_dialogs)
