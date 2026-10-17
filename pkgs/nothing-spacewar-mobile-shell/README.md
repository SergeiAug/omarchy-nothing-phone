# Spacewar mobile shell

Stock Omarchy r7031 plugins, Nothing Phone (1), DSI-1 scale 2 (540×1200).
This package conflicts with `nothing-spacewar-mobile-ui`; it does not replace
Omarchy, install a compositor plugin, change hardware services or configure PAM.
RU/EN input remains `omarchy-osk-spacewar`.

Claude installs the built package on the phone and runs `spacewar-shell-setup`
as the session user. It archives `hypr` and `omarchy` under
`~/.local/state/spacewar-shell/backup-<UTC timestamp>.tar`, preserves unrelated
shell.json fields, disables the old dock/shade/switcher, links the plugins and
loads the preserved device Lua. Then run `hyprctl reload`, check
`hyprctl configerrors`, and run `omarchy-shell shell rescanPlugins`.
`spacewar-shell-setup --undo` restores that configuration archive. Repeated
setup/undo is a no-op. An interrupted setup resumes from its saved plan.
Undo restores those two configuration directories, including edits since setup.

Navigation:
- Pull anywhere across the status bar; release to settle; pull its header to
  dismiss or expand. The handle also expands; the pencil edits tiles.
- Up from the bottom 30 logical px: home. Pause after upward motion, or drag
  at least 38% of screen height slowly and release (at most 650 px/s): recents.
- Side edge: back, with a moving indicator. Shell panels and OSK close first;
  child dialogs receive Escape; browsers/file managers receive Alt+Left;
  other apps stay in recents while an empty home workspace is focused.
- In recents, tap to activate; swipe upward or tap × to close.
  “Закрыть все” closes all cards; the close hint remains visible.
- Home has pages, favorites, a four-column layout, and original OWL widgets.
  Hold home to edit. “Приложения” opens the scrollable, searchable drawer.
- The keyboard glyph in the status bar toggles OSK without opening the shade.
  Keyboard and RU/EN tiles call the existing OSK IPC.

`~/.config/omarchy/spacewar-shell.json`: `{ "backEnabled": false }` disables
both side bands live. `{"gestureLogging": false}` disables gesture begin/finish
logging live; enabled by default. Filter the shell journal for `spacewar-gesture`;
records include kind, distance (logical px), velocity (px/s), held and result. `plugins/spacewar.runtime/Device.js` derives camera clearance from the LineageOS
Spacewar cutout at scale 2: left 79, top 56 logical px. `bar.safeLeft` can
increase the left clearance. The visible bar stays 44 px high; its reservation
extends below the camera.
Gesture parameters live in `plugins/spacewar.runtime/Motion.js` (logical px).
Every new top-level application window gets an empty workspace, tiles and maximizes
between the bar and OSK, including notification-launched Omarchy terminals. Native parent/fixed-size
windows, X11 modals and portal/polkit/file chooser classes stay floating on
the existing workspace. Their maximum size follows bar/OSK reservations;
small dialogs retain their client size. See VALIDATION.md for compositor limits.
Home unmaps on occupied workspaces. Terminal focus shows OSK; leaving it hides
OSK. Manual dismissal persists until focus changes. The shade takes no keyboard
focus, hides OSK and restores its previous state after dismissal.

The torch helper discovers flash/torch LEDs by capability and writes only
`brightness`, using one quarter of the driver range (63/255 on Spacewar).
The packaged udev rule gives the image user’s existing `wheel` group write
permission only on that attribute. The package install/upgrade hook reloads udev rules and triggers LED add
events, so existing LEDs receive permissions without rebooting. Unavailable tile backends are omitted from the grid.

The actual OSK top comes from its status IPC and compositor layer geometry,
polled every 150 ms. Missing or inconsistent geometry disables input regions.
The bottom band unmaps from input while OSK is shown. Side bands stop above it.

The 105 checked OWL widgets are bundled from Simon's pinned b63886b store,
using Derek's compiler/host and SHA256 index. New home layouts contain offline
analog-clock and calendar widgets. Widgets needing commands or network keep
Derek's explicit approval UI; local clock/calendar sources need neither.
No runtime store download or mandatory Pixel dependency is introduced.

Build: `makepkg --force --nodeps` on the laptop (no install).
Run `tests/check.sh` with `OMARCHY_QA_ROOT` pointing to the extracted r7031
`usr/share/omarchy`. See VALIDATION.md for reproducible headless checks and
phone acceptance. License and source provenance: ATTRIBUTION.md and LICENSE.*.
