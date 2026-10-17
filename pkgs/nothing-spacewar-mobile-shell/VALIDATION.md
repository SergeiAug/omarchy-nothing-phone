# Laptop validation and phone acceptance

## Checked

Three independently built stages: 0.1.0, 0.2.0, 0.3.0 (`makepkg --force --nodeps`).
Dependency installation was deliberately skipped; no pacman, sudo, phone access,
PAM edits or active desktop configuration writes occurred.

Final `tests/check.sh`:
- Seven Python tests: setup/repeat/undo, preserving unrelated/lock fields and
  symlinks, invalid JSON, interruption recovery, user plugin collision, OSK
  geometry and Qt touch events. QtTest: five passes including lifecycle cases.
- Upstream Bluetooth-agent pure-helper checks pass without a BlueZ connection.
- Node motion tests: short, slow, fast, paused, canceled, stale velocity,
  reversal, diagonal rejection, continuous motion, card distance + velocity.
- All 105 original OWL files match the pinned SHA256 index and compile with the
  shipped compiler. Home defaults include the two offline OWL widgets.
- All QML linted against extracted r7031. No syntax/import failures; remaining
  warnings concern upstream block-scoped `var` and Quickshell's missing static
  BluetoothAdapter type metadata. `luac -p phone-device.lua`: PASS.
- Real .pkg.tar.zst extracted and inspected: any, expected conflict, no replaces,
  RU OSK dependency, all plugin/widget bytes match source, executable helpers,
  no PAM/hyprgrass/Navigation payload. namcap and shellcheck unavailable on PATH.

Actual Quickshell r7031 host under isolated labwc, 540×1200:
step1 bar; step2 partial shade, cancel, open shade and recents;
step3 OWL analog clock/calendar, favorites/pages, four-column drawer, search,
scroll to end, close three fixture windows, bottom cancel, OSK top changing to
811 (not a fixed 360px assumption), shell restart and exact setup undo: PASS.
Screenshots: `research/shell-v5/step{1,2,3}/`.
Final host/restart logs have zero TypeError/ReferenceError. The harness has no
phone: OSK status/geometry and Hyprland IPC are fixtures. labwc cannot provide
Hyprland per-window preview textures; blank recents previews are expected there.
Missing theme/default translations, PipeWire and portal warnings are documented
harness limits, not measured phone behavior. No FPS or touch latency claim.

Reproduce with extracted labwc/wlr-randr (no host installation):

```sh
OMARCHY_QA_ROOT="$PWD/research/omamobile-compat/r7031/usr/share/omarchy" \
  pkgs/nothing-spacewar-mobile-shell/tests/check.sh
LABWC=/path/to/labwc WLR_RANDR=/path/to/wlr-randr \
OMARCHY_QA_ROOT="$PWD/research/omamobile-compat/r7031/usr/share/omarchy" \
MOBILE_QA_ROOT="$PWD/pkgs/nothing-spacewar-mobile-shell" \
QA_OUTPUT="$PWD/research/shell-v5/step3" GSETTINGS_BACKEND=memory \
  dbus-run-session -- python pkgs/nothing-spacewar-mobile-shell/tests/headless.py
```

The headless test uses the staged package payload, compares the real archive
with it, mocks OSK explicitly, and restores its isolated home. QtTest supplies
synthetic touch events; it does not prove real wl_touch delivery on Hyprland.

## Claude: phone checklist

1. Install the conflicting replacement, run setup twice, reload Hyprland,
   inspect configerrors and rescan plugins. No old dock, Navigation, old shade,
   old switcher or hyprgrass edge owner should remain active. Check `hyprctl
   layers`, OSK `status`, and `spacewar-shell-geometry`. Device Lua keeps scale 2,
   scrolling/column_width and hide_on_touch. No lock/PAM migration is performed.
2. Touch every key in the bottom OSK row (123, RU, Space, Enter), in both RU/EN.
   Test show/hide, narrow/floating, focus changes. The entire bottom input band
   disappears while OSK is shown; side regions stop above its actual top.
   Sampling interval is 150ms; measure behavior during keyboard transitions.
3. Test short/long/fast/reversed/swipe+pause gestures, release outside the initial
   band, a second finger, cancel and shell restart. No full input region may
   remain after cancellation. A canceled preview releases input immediately,
   while its visual return animation finishes. Check ownership via
   `omarchy-shell spacewar.gestures snapshot`.
4. Pull shade from both ends and center of the bar; partial position follows
   without easing. Release chooses return/settle. Test expanded pages, tile
   editor, Wi-Fi/BT sheets, brightness/volume, keyboard and RU/EN tiles.
5. Bottom up goes home; pause after motion opens recents. Test live preview
   textures, selecting cards, slow/fast dismissal and cancel/second touch.
   Side back closes drawer/shade/recents/OSK first; application Alt+Left support
   varies. Set `~/.config/omarchy/spacewar-shell.json` to
   `{"backEnabled":false}` and verify both side bands are gone.
6. Check camera clearance and corners against fix1 below. The cutout source
   is now measured in physical pixels and converted at scale 2.
   Check battery %, long/Russian labels in four columns, drawer scrolling,
   collapse/search, home page editing, favorites, OWL clock/calendar and Store.
7. Exercise stock lock separately. Finally verify `spacewar-shell-setup --undo`
   restores the latest backup. It restores both whole archived configuration
   directories, so later edits within them are reverted too. Keep Claude's
   rollback packages/tag for package rollback.

## Principles applied

Prove It Works: execute the packaged plugins in r7031 and inspect the real
archive. Sequence Verifiable Units: build/test each of the three commits.
Laziness Protocol: reuse Derek's plugin and OWL implementation, one motion
parameter module, no shell fork. Fix Root Causes: remove dock input ownership
and mask all surfaces using actual OSK geometry rather than changing the OSK.


## Fix1 — 0.3.1-1

Root causes (line references refer to the fixed sources; removed behavior is
visible in the commit diff):

1. `plugins/omamobile.bar/Bar.qml` used `max(44, safeLeft)` and setup wrote 44;
   neither represented the cutout's right/bottom edges. `spacewar.runtime/Device.js`
   is the one geometry source: LineageOS Spacewar's `config_mainBuiltInDisplayCutout`
   physical circle / scale 2, plus 8 px clearance gives left 79, top 56. The bar
   reserves 56 while drawing 44; Normal surfaces (home/drawer/Wi-Fi/BT/record)
   inherit it. The Ignore-mode shade explicitly starts below that reservation;
   centered recents cards stay below it. Syntax checked against the
   [current Lua window-rule documentation](https://wiki.hypr.land/Configuring/Basics/Window-Rules/).
2. `phone-device.lua` previously configured only scrolling. Stock
   `default/hypr/apps/system.lua:2-11` tags org.omarchy.terminal and fixes it at
   875×600; `:29-31` floats About directly. Now all app windows drop the tag,
   tile, maximize and open on empty workspaces, preserving screensaver fullscreen.
   `Runtime.qml` previously polled only OSK geometry; OSK `Service.qml:182-190`
   auto-shows only on input-method activation. There was no class/focus fallback
   for a migration/sudo terminal. All launch paths now get that fallback;
   an earlier foot success proves IM/manual visibility, not a common policy.
3. QuickSettings' main layer requested keyboard focus despite containing no
   text field, and Runtime never suspended the OSK while it was open. The layer
   now uses None. Runtime snapshots actual OSK status on entry, hides through
   drag/open/closing animation and restores on close, including the fast-focus
   race found by the headless test. Phone IM-event tracing remains Claude's
   check; the laptop fixture does not establish which phone event activated IM.
4. `QuickSettings.qml` hard-coded `brightnessctl --device=white:torch`; Spacewar
   has `white:flash`. Discovery accepts flash_* capabilities or torch/flash
   names, uses brightness for torch and never touches flash_strobe/current.
   udev grants wheel 0664 on brightness alone, following Derek's explicit sysfs
   chgrp/chmod pattern (`20-omamobile-display.rules:5`). The image already adds
   user to wheel (`tools/build-rootfs.sh:279-280`). All unavailable tile
   backends are filtered without deleting the saved layout.
5. `Home.qml` only paused OWL when an app existed; its Bottom surface stayed
   mapped, so translucent apps exposed it and its input mask remained active.
   It now unmaps using activeworkspace.windows, including windows not represented
   by a foreign-toplevel handle.
6. Home/drawer already called omamobile-launch, whose process-token and
   pre-launch empty-workspace policy covered those paths only. Notifications and
   xdg-terminal-exec bypassed it. The compositor's mapping rule now applies the
   same empty-workspace policy to all new app windows.

New checks: Node cutout/focus/manual/shade cases; Python simulated sysfs LEDs
(named white:flash, capability-only, torch, unrelated LED), untouched strobe;
executed Lua rule recorder for terminal/Nautilus/About/dialog mapping; actual
r7031 plugin host with OSK IPC fixture verifies rapid terminal focus → shade →
restore, hidden-state preservation, status-bar toggle, focus loss and home
unmapping/remapping. Existing tests, widget hashes/compiler, Qt touch tests,
QML lint, package-byte inspection and makepkg run together. udevadm verify
checks the packaged rule syntax. Hyprland mapping and physical LED permissions
still require the phone acceptance below; no phone was contacted.

Claude — install/check 0.3.1:

- Install package; rules are in `/usr/lib/udev/rules.d/90-spacewar-torch.rules`.
  Reload udev rules and trigger an add event on white:flash (as installation
  administrator), or reboot. Verify user's wheel membership and that user
  can run `spacewar-shell-torch on`, `status`, `off` without sudo. Check that
  flash_strobe/current attributes retain their original permissions/values.
- Existing setup need not be undone: plugins and device Lua are package-linked.
  Reload Hyprland, inspect configerrors, restart/rescan shell. Check a new
  migration terminal from the real Pending migrations notification, sudo input,
  foot/Alacritty/ghostty/kitty and org.omarchy.about. Each must fit between
  bar and keyboard, also while keyboard height changes. Check clients floating,
  fullscreen and workspace fields; new windows should each own a workspace.
- Tap the keyboard glyph in the center of the bar twice. No shade should open;
  a downward pull beginning there should still open the shade. Hide manually,
  retain terminal focus, wait: OSK must stay hidden. Change focus away/back:
  it should show again. Repeat with OSK initially visible/hidden while opening,
  dragging, canceling and closing the shade. No OSK in the main shade. Wi-Fi/BT
  text-entry pages remain separate, keyboard-capable surfaces.
- Compare `research/shell-v5/fix1/bar-cutout.png` at 540×1200 with the camera.
  Clock starts x=79; circle ends y≈47.35, all Normal content starts below 56.
  Check home widgets, drawer, shade headers, Wi-Fi/BT and recents.
- On an occupied workspace, home must be absent from hyprctl layers, invisible
  through a themed translucent foot and unable to receive touches. Close the
  last window or go home: widgets and drawer button return.
- Launch Nautilus/foot from home, drawer, terminal command and notification;
  verify distinct workspaces. Verify restart and setup/undo as before.

Principles: Prove It Works — real archive and real r7031 host; Sequence Verifiable
Units — run focused checks before package/host validation; Laziness Protocol —
one cutout source and compositor policy for every launch path; Fix Root Causes —
remove desktop floating rules and Pixel LED assumption at their source.

## Fix2 — 0.3.2-1 (2026-10-18)

Root causes and changes:

- The 0.3.1 unconditional rules at `phone-device.lua:7-8` applied desktop
  top-level policy to transient clients too. `phone-device.lua:8-16` now tags
  native floating/dialog candidates before removing desktop floating tags.
  Only untagged app windows maximize and get an empty workspace. Dialog rules
  clear inherited workspace/size overrides, retain floating and center.
  `phone-device.lua:19-42` caps client dimensions using actual monitor scale and
  reserved edges, then centers in that rectangle. Four pixels per edge leave
  border clearance; a small dialog is not enlarged. Runtime.qml:84 reapplies
  this after OSK geometry changes, including an already-open dialog.
- `spacewar-shell-back` previously sent Alt+Left to every class. The class
  table at `spacewar-shell-back:8` now gates history navigation. Tagged dialogs
  receive Escape first; other apps go home through empty-workspace focus and
  remain open. `Runtime.qml:65` preserves shell-panel/OSK precedence. No global
  Escape is sent to terminals/vim. Address validation precedes IPC dispatch.
- `90-spacewar-torch.rules:2` handles add only. `mobile-shell.install:1-8`
  reloads rules, then triggers LED add events on install AND upgrade.
  The real package contains that exact `.INSTALL` payload.

### API audit: exact v0.56.2, not current wiki

Sources fetched read-only using `gh api ...?ref=v0.56.2`; installed compositor
reports efb50993780079460b0cbed1363e2166a2de1d9f.

- [Rule.cpp:28-45](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/desktop/rule/Rule.cpp#L28):
  matchers include `float`, `modal`, `xdg_tag`. No `parent` or `initial_float`.
- [Window.cpp:2129](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/desktop/view/Window.cpp#L2129),
  [XWaylandManager.cpp:110-146](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/managers/XWaylandManager.cpp#L110):
  native floating classification runs before map-time static rules. It covers
  Wayland parents/fixed dimensions and X11 transient/parent/modal/window types.
  Omarchy's rule-generated 875x600 float is not this native floating state.
- [WindowRule.cpp:437](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/desktop/rule/windowRule/WindowRule.cpp#L437),
  [Window.cpp:1681](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/desktop/view/Window.cpp#L1681):
  **`modal` tests X11 only.** `xdg_tag` is application-provided metadata,
  not the xdg-dialog protocol flag. Parent-bearing xdg-dialog clients are
  covered by native floating; a parentless xdg-dialog flag alone cannot be
  detected through these Lua matchers/Window properties. Do not claim otherwise.
- [LuaBindingsDispatchers.cpp:402-453](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/config/lua/bindings/LuaBindingsDispatchers.cpp#L402):
  `hl.dsp.send_shortcut({mods="ALT",key="Left",window="address:0x..."})`.
  Explicit event callbacks invoke the returned dispatcher closure with `()`;
  `hyprctl dispatch` invokes it itself. ConfigActions.cpp:1530-1598 sends
  press/release for the default action state, restores modifiers and focus.
- LuaWindow.cpp:68-166 exposes tags, geometry, workspace and monitor, but no
  parent/min/max/modal fields. LuaMonitor.cpp:115-180 exposes monitor pixel size,
  scale, position and named reserved edges. ConfigActions.cpp:732-759 implements
  `set_prop` min/max size as a geometry/configure operation, without raster scaling.

### Verified and limits

`tests/check.sh`: PASS, including makepkg, 13 Python tests, back priority Node
checks, motion/fix1/widget checks, Qt touch tests, Lua syntax, QML lint, exact
archive-byte inspection and install-hook assertions. Hyprland 0.56.2
`--verify-config` reports `config ok` for the shipped Lua.

`tests/window-policy.lua` executes the shipped policy through a recorded API:
normal app and desktop-rule float (including org.omarchy.terminal), native
parent/fixed floats, modal/portal exceptions, small size preservation, oversized
clamping and recentering as OSK reservations change. This is a model of the API,
not proof of actual Hyprland client configure/commit behavior.

Real r7031 shell on labwc, 540x1200: existing home/OSK/shade/gestures/restart/undo
suite passes with the new package. `tests/headless-dialogs.py` renders native
GTK3 transient/modal, Qt Widgets QDialog with parent, and a top-level
org.omarchy.terminal 875x600 request. Native virtual-keyboard Escape reaches
both dialog fixtures and closes them. GTK fixture explicitly handles Escape;
this does not establish that every application's dialog handles that key.
Screenshots/logs are in `research/shell-v5/fix2/`. Labwc's test placement rules
are explicit stand-ins, not execution of Hyprland Lua rules.

**Not established on the laptop:** real Hyprland mapping/input alignment or
physical LED permissions. Hyprland fails backend creation without `/dev/dri`
(the attempt/log is retained). Also, Window.cpp:2743-2747 reapplies client
Wayland min/max hints on commit independently of rule overrides: a genuinely
fixed oversized client may resist the size cap. A config cannot force a client
to redraw a smaller buffer. This case and a parentless xdg-dialog-only client
need a compositor/client change if encountered; the package does not patch
Hyprland. Workspace `unset` removes our override; there is no parent workspace
selector in this API, so background-parent association remains compositor-owned.

Reproduce native fixture smoke tests with the same extracted labwc libraries:

```sh
LABWC=/path/to/labwc WLR_RANDR=/path/to/wlr-randr \
QA_OUTPUT="$PWD/research/shell-v5/fix2" \
  dbus-run-session -- python pkgs/nothing-spacewar-mobile-shell/tests/headless-dialogs.py
```

Claude phone acceptance (no phone contacted here):

1. Install/upgrade 0.3.2-1 without reboot/manual trigger. As user, run torch
   on/status/off; check only LED brightness permissions changed.
2. Reload Hyprland, inspect configerrors. Open Writer's Tip of the Day, GTK
   file chooser, Qt dialog and polkit. Check parent workspace, floating=true,
   fullscreen=0, bounds between bar/OSK, sharp text, and taps on actual buttons.
   Repeat show/hide OSK with the dialog open. Check a deliberately oversized
   resizable and fixed-size dialog separately; record any client minimum limit.
3. Launch the migration terminal through Pending migrations: independent
   workspace, tiled/maximized, 875x600 desktop size removed, OSK visible.
4. Back closes shell/OSK before app action; then a child dialog via Escape.
   Browser/file manager history gets Alt+Left. Root/non-history app goes home,
   remains in recents and resumes. Terminal/vim must receive no Escape/Alt+Left.
5. Test a dialog from a background parent and a parentless xdg-dialog protocol
   client separately; these API limitations above must not be marked passed
   from the labwc fixtures.

Principles: Fix Root Causes — discriminate clients before workspace/maximize;
Laziness Protocol — reuse native floating classification and one history table;
Sequence Verifiable Units — targeted tests before package and host checks;
Prove It Works — inspect actual archive and native fixtures, explicitly separate
Hyprland evidence from fixtures and unverified compositor limitations.

## Fix3 — 0.3.3-1 / OSK 0.3.4.r4.gba346b0-1

### Changes and roots

- `phone-device.lua:8-14`: placement now matches native float/modal/xdg tags
  and known classes directly; no placement rule matches a dynamic shell tag.
  `gcr-prompter` was absent from the old class exception. Empty titles are
  irrelevant. Input layout and touchscreen output are restored at line 3.
- Exact Hyprland v0.56.2 audit: Engine.cpp:14-15 keeps registration order.
  WindowRuleApplicator.cpp:483-521 applies static and dynamic effects together;
  tag is dynamic (:161-165), not a separate classification phase. Window.cpp:
  2277-2282 applies static state, rechecks tag/content-dependent rules, then
  applies static state again. Recheck (:526-544) does not reset previous static
  effects. Thus tag-dependent placement crosses a state-changing boundary;
  direct exceptions avoid it. **The reported portal failure is not reproduced
  on a live Hyprland here; the source audit alone does not establish its exact
  runtime cause.** The prior Lua model passed despite the phone failure.
  Source links and remaining limits: `research/shell-v5/fix3/source-audit.md`.
- OSK old `c16f709/helper/osk-helper.py:197-225` assigned `index+8`, including
  standard multimedia positions, and reuploaded for new characters. In commit
  ba346b0, `helper/osk-helper.py:42-96` builds one bounded map: ASCII at US
  positions, RU in group 2 at the same positions, five extra symbols in group 3
  on number codes. No Print/XF86 positions. Active IM text commits atomically
  using the done-event serial; legacy input and shortcuts use fixed codes.
  Hyprland KeybindManager.cpp:369 independently resolves bind keysyms through
  its translation state by default, explaining why the OSK map alone was
  insufficient. Changing the actual codes addresses that boundary.
- `Motion.js:4-7,31`: bottom edge 30 logical px; recents also on release after
  38% of current height, with mean and release speed <=650 logical px/s.
  At 1200px that is 456px and at least ~702ms; at 960px it is ~365px/~561ms.
  The existing 72px/180ms hold path and fast-swipe home remain.
  Home.qml:1050 positions the drawer button above Motion.P.bottomEdge;
  panel masks reserve the same bottom band. Side bands retain 16px.
- Switcher.qml:260,286,337,355 adds a 44px × target, enables preview capture
  while dragging, shows gesture/close guidance and labels “Закрыть все”.
  Guidance remains visible each time, rather than adding persistent hint state.
- Gestures.qml:40-49 logs begin/finish kind, distance, last sampled velocity,
  held and result through console.warn (shell log / journal). Runtime.qml:56,77
  watches `~/.config/omarchy/spacewar-shell.json`; `gestureLogging:false`
  disables it live. Defaults to enabled; no per-move journal flood.

### Evidence

- Both real packages built with `makepkg --force --nodeps`; source checksums
  pass. `tests/check.sh`: 13 Python tests, Node motion/fix1/fix2/fix3/widget
  behavior, Lua config/model, Qt touch lifecycle, QML lint and byte-for-byte
  archive inspection pass. Existing upstream lint warnings remain.
- OSK packaged-source check(): actual uploaded XKB bytes compile in
  libxkbcommon; all 33 RU lower/uppercase letters, ASCII and extra symbols
  produce exact text with one upload. Every supported code resolves under the
  independent standard keymap without Print/XF86. IM serial/atomic commit and
  unsupported legacy text tests pass. Layout/state tests pass.
- Real r7031 shell, isolated labwc 540x1200: begin at y=1175 (outside the old
  16px band); 480px slow swipe ends in recents with **held=false**. Preview
  captured separately so taking a screenshot cannot create the pause gate.
  Real virtual-pointer clicks on × change 3 windows to 2; “Закрыть все” changes
  2 to 0; tapping the home drawer at y=1146 opens it. Live logging disable/enable
  checked by observing shell logs. Restart/undo, shade, OSK and drawer suite
  passes with no QML TypeError/ReferenceError. GTK/Qt parent-dialog fixtures
  render and Escape closes both. Labwc's placement is a stand-in, not Hyprland.
- Hyprland 0.56.2 --verify-config: config ok. Actual isolated start fails with
  CBackend::create() failed; /dev/dri is absent. No live Hyprland bind delivery,
  client buffer/input alignment, Chromium/Obsidian IM behavior or physical
  touch has been proven. Parentless xdg-dialog-only and oversized fixed-hint
  client limits described under fix2 still apply.
- Logs and inspected screenshots: `research/shell-v5/fix3/`. Virtual-pointer XML
  is the MIT wlr-protocols protocol; header/private C are generated in /tmp by
  headless.py. No system package installation or phone access occurred.

Reproduce shell/fixture runs using the commands above with QA_OUTPUT pointing
at `research/shell-v5/fix3`. Build OSK from its directory with makepkg; its
check() needs nodejs and system libxkbcommon. See SHA256SUMS for final archives.

### Claude: phone checklist

1. Install both new packages, run setup, reload Hyprland, inspect configerrors
   and rescan/restart shell/helper. Check `kb_layout=us,ru` and touch DSI-1.
2. Open portal “Open Video File”, gcr-prompter with empty title, Writer Tip,
   GTK/Qt parent dialogs. Verify floating=true, parent/current workspace,
   sharp buffer and aligned taps, small size preservation and OSK bounds.
   Open org.omarchy.terminal separately: new workspace, tiled/maximized.
3. Type every EN/RU key and uppercase, numbers, symbols in shell search,
   Obsidian and Chromium. No screenshots, volume changes, XF86 or maximum
   keycode warnings. Check text-input commits, legacy input, Ctrl+C/Alt keys.
4. Slow continuous 38–40% swipe/release opens recents without waiting; fast
   swipe goes home; hold still opens recents. Test both resolutions, corners,
   cancellation, reversal, second finger, OSK and “Приложения” separation.
5. Inspect live previews during drag; tap ×, swipe a card up, tap “Закрыть все”.
   Unsaved applications may display their normal confirmation dialogs.
6. Filter shell journal for `spacewar-gesture`. Check begin/finish fields;
   set gestureLogging=false and true without restart and observe the switch.

Principles: Prove It Works drove actual archive, XKB and pointer-click checks;
Sequence Verifiable Units checked OSK before packaging and shell behavior
before final verification; Laziness Protocol reuses the existing closeAll and
shared edge constant; Fix Root Causes removes the code-position collision and
placement dependency instead of hiding multimedia binds or fixing dialogs
only after they have already moved to another workspace.
