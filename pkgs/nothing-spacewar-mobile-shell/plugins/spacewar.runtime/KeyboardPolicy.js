// SPDX-License-Identifier: MIT
function create() { return {focus:"", terminal:false, suspended:false, restore:false} }
function terminal(app) {
  return /^(foot(?:client)?|alacritty|kitty|(?:com\.mitchellh\.)?ghostty|org\.codeberg\.dnkl\.foot|org\.omarchy\.(?:terminal|bash|btop)|org\.wezfurlong\.wezterm|wezterm|org\.gnome\.(?:terminal|console)|konsole)$/i.test(app || "")
}
function update(state, app, shade, shown) {
  var key = app.address || ""
  var isTerminal = terminal(app.class)
  if (shade) {
    if (!state.suspended) { state.restore = shown; state.suspended = true }
    return shown ? "hide" : ""
  }
  if (state.suspended) {
    state.suspended = false
    // Layer focus may temporarily clear activewindow. Keep the application's identity.
    if (!key || key === state.focus) return state.restore ? "show" : "hide"
  }
  if (key === state.focus) return ""
  var wasTerminal = state.terminal
  state.focus = key; state.terminal = isTerminal
  return isTerminal ? "show" : wasTerminal ? "hide" : ""
}
if (typeof module !== "undefined") module.exports = {create:create, terminal:terminal, update:update}
