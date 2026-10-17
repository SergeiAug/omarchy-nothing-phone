# How it was done

Short notes on the problems we hit and how each was solved. Useful if you bring up Omarchy, or any Arch Linux ARM desktop, on this phone or a similar Qualcomm one.

## Boot and kernel

- **Back up EFS first.** Before writing anything, the modem partitions (`modemst1`, `modemst2`, `fsg`, `fsc`, `persist`) were copied from a RAM-booted debug image. They hold IMEI and RF calibration and cannot be recreated.
- **ABL needs `dtbo` and `vendor_boot` erased**, or it reports a load error. `boot.img` is header v2 with the DTB appended.
- **Kernel:** sc7280-mainline 7.2.9 plus the Spacewar series (DTS, audio, voice, Bluetooth offload, cameras). It is cross-built on the laptop with clang (`LLVM=1`). The package was accepted only after its contents were checked, not because `makepkg` succeeded.
- **ADSP heap:** one DTB line (`reusable` → `no-map`) fixed ADSP instead of a kernel rebuild.
- **pacman 7 sandbox** needs Landlock, so `CONFIG_SECURITY_LANDLOCK=y`. Inside the qemu chroot pacman runs with `--disable-sandbox`.

## Hardware

- **USB networking:** the dwc3 controller comes up wrong after the bootloader. A service reprobes it, and the laptop side uses a static `172.16.42.2`.
- **Wi-Fi (WCN6750)** reports MAC 0, so NetworkManager uses `cloned-mac-address=stable`.
- **Bluetooth** has no address, so `bootmac` from postmarketOS was ported.
- **Audio:** PipeWire needs the ALSA SPA packages, and the TFA9873 amplifiers stay silent at S24, so WirePlumber forces S16LE. A boot race (`va_macro` -110 before ADSP is ready) is fixed by a reprobe service.
- **Modem:** qrtr, rmtfs (read-only, `-r`), tqftpserv, hexagonrpcd, msm-modem and 81voltd were packaged from Alpine and postmarketOS. `q6voiced` stays off because it conflicts with `dummystreamhack`, which the UCM VoiceCall profile uses. ModemManager sees the modem. Calls still need a live SIM test.
- **Torch:** the PMIC flash LED is `white:flash`. A udev rule gives its `brightness` to the session user.

## Omarchy

- **`omarchy-dev`, not 4.0.4:** stable 4.0.4 breaks on Qt 6.12 (an empty bar, #14553).
- **Screen:** scale 2 gives 540x1200 logical px. The punch-hole position comes from the LineageOS `config_mainBuiltInDisplayCutout`, and the bar keeps clear of it.
- **Keyboard:** a fork of omarchy-on-screen-keyboard with a Russian layout and an IPC to switch language. It uploads one static US/RU keymap. A dynamic "one keycode per new symbol" keymap pushed letters into media keycodes, so some letters took screenshots or changed volume.

## Mobile shell

Instead of writing a new shell, the best parts of existing ones run as plugins of Omarchy's own Quickshell shell:

| Part | Source |
|---|---|
| home screens, app drawer, status bar, quick settings | derekross/omarchy-mobile |
| widgets | SimonSchubert/omarchy-widgets |
| shade that follows the finger, edge masks, back edge | SimonSchubert/omarchy-mobile |
| swipe up for home, long swipe for recents, card dismissal by speed | Cube-Oakley/omarchy-mobile |
| keyboard | our fork of yeutterg/omarchy-on-screen-keyboard |

Lessons:

- Gestures bound in the compositor fire only on release. For a native feel, track the finger in QML layers and decide on release by distance and speed.
- Every layer's input region must stop above the on-screen keyboard. An invisible dock and a gesture strip over the bottom key row were why typing "missed".
- Dialogs must stay floating on their parent's workspace. Forcing them fullscreen stretches the buffer and breaks touch coordinates.
- When a Hyprland plugin is removed, restart the session, not just `hyprctl reload`. The old plugin stays loaded and crashes on the next touch.
