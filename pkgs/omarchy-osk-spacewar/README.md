Snapshot of work/omarchy-osk at ba346b0 (0.3.4.r4), with Russian layout,
switchLanguage IPC, one static keymap and text-input-v3 commits. Upstream:
https://github.com/yeutterg/omarchy-on-screen-keyboard, MIT, copyright yeutterg.
The source is a git archive of that commit, independent of the ignored work/
checkout. LICENSE is installed. Build with `makepkg --force --nodeps`.

ASCII uses physical US positions, Cyrillic uses the same positions in group 2.
€ £ ¥ • ° use ordinary number positions in group 3. All codes stay below 256;
none resolve to Print/XF86 through the standard bind keymap. The keymap uploads
once. Active input methods receive commit_string/commit with the done serial;
legacy clients receive virtual key presses. Unsupported legacy Unicode is
rejected before sending a partial string. Shortcut keys still use virtual input.

check() compiles the real uploaded keymap with libxkbcommon, checks all RU/EN
letters/case/symbols and standard-keymap bind translations, atomic IM commits,
layout geometry and state persistence. It does not prove Chromium/Obsidian IM
behavior or delivery on the phone. Enable/undo through spacewar-shell-setup;
no package script changes users' homes.
