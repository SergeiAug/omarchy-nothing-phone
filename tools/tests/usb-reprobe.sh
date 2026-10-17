#!/bin/bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export SPACEWAR_SYSFS_ROOT=$work/sys
driver=$SPACEWAR_SYSFS_ROOT/bus/platform/drivers/dwc3-qcom
mkdir -p "$driver" "$SPACEWAR_SYSFS_ROOT/bus/platform/devices/a600000.usb" \
  "$SPACEWAR_SYSFS_ROOT/class/usb_role/a600000.usb-role-switch" \
  "$SPACEWAR_SYSFS_ROOT/class/udc/a600000.usb"
ln -s "$driver" "$SPACEWAR_SYSFS_ROOT/bus/platform/devices/a600000.usb/driver"
role=$SPACEWAR_SYSFS_ROOT/class/usb_role/a600000.usb-role-switch/role
state=$SPACEWAR_SYSFS_ROOT/class/udc/a600000.usb/state
run() { bash "$repo/pkgs/nothing-spacewar-boot/spacewar-usb-reprobe"; }
printf 'host\n' > "$role"
printf 'not attached\n' > "$state"
run
[[ ! -e $driver/unbind ]]
printf 'device\n' > "$role"
printf 'configured\n' > "$state"
run
[[ ! -e $driver/unbind ]]
printf 'not attached\n' > "$state"
run
[[ $(<"$driver/unbind") == a600000.usb && $(<"$driver/bind") == a600000.usb ]]
run
[[ $(<"$driver/bind") == a600000.usb ]]
mkdir -p "$SPACEWAR_SYSFS_ROOT/kernel/config/usb_gadget/foreign"
printf 'a600000.usb\n' > "$SPACEWAR_SYSFS_ROOT/kernel/config/usb_gadget/foreign/UDC"
if run; then echo 'FAIL: bound gadget was accepted' >&2; exit 1; fi
printf 'USB reprobe guards and repeat invocation: PASS (fake sysfs only)\n'
