#!/bin/bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/packages" "$work/meta"
package() {
  printf 'pkgname = %s\npkgver = %s\narch = %s\n' "$1" "$2" "$3" > "$work/meta/.PKGINFO"
  bsdtar -caf "$work/packages/$1-$2-$3.pkg.tar.${4:-zst}" -C "$work/meta" .PKGINFO
}
for name in linux-sc7280 firmware-nothing-spacewar nothing-spacewar-boot nothing-spacewar-ucm; do
  package "$name" 1-1 aarch64
done
for name in bootmac qrtr rmtfs tqftpserv hexagonrpcd 81voltd dummystreamhack q6voiced msm-modem; do
  package "$name" 1-1 aarch64 xz
done
package nothing-spacewar-boot 1-2 any
for version in 0.3.9-1 0.3.10-1 0.3.3-1; do
  package nothing-spacewar-mobile-shell "$version" any
done
for version in 0.3.4.r3.gc16f709-1 0.3.4.r4.g9d871c1-1 0.3.4.r4.gba346b0-1; do
  package omarchy-osk-spacewar "$version" any
done
package nothing-spacewar-mobile-ui 99-1 any
package hyprgrass 99-1 aarch64
package linux-sc7280-headers 99-1 aarch64
uuid=12345678-1234-4234-8234-123456789abc
run() { "$repo/tools/build-rootfs.sh" test-rootfs --uuid "$uuid" --pkg-dir "$work/packages" --dry-run "$@"; }
run > "$work/first"
run > "$work/second"
cmp "$work/first" "$work/second"
grep -q '^UUID: 12345678-1234-4234-8234-123456789abc$' "$work/first"
grep -q 'Local package nothing-spacewar-boot: .*/nothing-spacewar-boot-1-2-any.pkg.tar.zst$' "$work/first"
grep -q '^Workdir: /var/tmp/spacewar-build/test-rootfs$' "$work/first"
# shellcheck disable=SC2016
for name in /tmp/build ../build . .. "bad name" "bad'quote" 'bad$(id)' 'bad;cmd'; do
  if "$repo/tools/build-rootfs.sh" "$name" --dry-run > "$work/rejected" 2>&1; then
    echo "FAIL: unsafe build name accepted: $name" >&2; exit 1
  fi
  grep -q 'invalid build name' "$work/rejected"
done
if grep -qxE 'qcom-firmware-extract|systemd-ukify|superwhisper-bin|nvim|vi|limine|snapper' "$work/first"; then
  echo 'FAIL: excluded package included' >&2; exit 1
fi
if grep -q MISSING "$work/first"; then exit 1; fi
grep -q 'Local package rmtfs: .*pkg.tar.xz$' "$work/first"
for name in modemmanager libqmi python-pywayland blueman nm-connection-editor; do grep -qx "$name" "$work/first"; done
grep -q 'Local package nothing-spacewar-mobile-shell: .*/nothing-spacewar-mobile-shell-0.3.10-1-any.pkg.tar.zst$' "$work/first"
grep -q 'Local package omarchy-osk-spacewar: .*/omarchy-osk-spacewar-0.3.4.r4.gba346b0-1-any.pkg.tar.zst$' "$work/first"
if grep -Eq '^Local package (hyprgrass|nothing-spacewar-mobile-ui):' "$work/first"; then
  echo 'FAIL: legacy mobile package selected' >&2; exit 1
fi
grep -qx neovim "$work/first"
grep -qx ex-vi-compat "$work/first"
grep -qx zram-generator "$work/first"
grep -qx linux-firmware-qcom "$work/first"
grep -qx vulkan-freedreno "$work/first"
if run --uuid invalid >/dev/null 2>&1; then echo 'FAIL: malformed UUID accepted' >&2; exit 1; fi
package linux-sc7280 2-1 x86_64
run > "$work/mixed"
grep -q 'Local package linux-sc7280: .*/linux-sc7280-1-1-aarch64.pkg.tar.zst$' "$work/mixed"
rm "$work/packages/linux-sc7280-2-1-x86_64.pkg.tar.zst"
if ((EUID != 0)); then
  if "$repo/tools/build-rootfs.sh" test-rootfs --pkg-dir "$work/packages" >/dev/null 2>&1; then
    echo 'FAIL: unprivileged actual build accepted' >&2; exit 1
  fi
fi
printf 'Rootfs dry-run, package selection, UUID validation and safe build names, no writes: PASS\n'
