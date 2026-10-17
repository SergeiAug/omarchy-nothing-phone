#!/bin/bash
# Builds a small synthetic workdir (real DTB and modules.builtin from the local linux-sc7280 package)
# and checks that verify-image.sh passes it and names each injected defect.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
verify=$repo/tools/verify-image.sh
kernel_pkg=$(find "$repo/pkgs/linux-sc7280" -maxdepth 1 -name 'linux-sc7280-[0-9]*-aarch64.pkg.tar.zst' | sort -V | tail -n1)
[[ -n $kernel_pkg ]] || { echo 'build pkgs/linux-sc7280 first' >&2; exit 1; }
t=$(mktemp -d)
trap 'rm -rf -- "$t"' EXIT
uuid=$(uuidgen)

mkdir -p "$t/kpkg"
bsdtar -xf "$kernel_pkg" -C "$t/kpkg" boot/dtbs/qcom/sm7325-nothing-spacewar.dtb usr/share/kernel/linux-sc7280/kernel.release
kver=$(<"$t/kpkg/usr/share/kernel/linux-sc7280/kernel.release")
bsdtar -xf "$kernel_pkg" -C "$t/kpkg" "usr/lib/modules/$kver/modules.builtin"

r=$t/root
mkdir -p "$r"/{boot/dtbs/qcom,etc/kernel,etc/sddm.conf.d,etc/NetworkManager/system-connections,var/cache/pacman/pkg,var/tmp} \
  "$r/etc/systemd/system/multi-user.target.wants" "$r/home/user/.ssh" "$r/home/user/.local/state/omarchy/indicators" \
  "$r/usr/lib/firmware/updates/ath11k/WCN6750/hw1.0" "$r/usr/lib/firmware/qcom" "$r/usr/share/kernel/linux-sc7280" \
  "$r/usr/lib/modules/$kver"
cp "$t/kpkg/boot/dtbs/qcom/sm7325-nothing-spacewar.dtb" "$r/boot/dtbs/qcom/"
cp "$t/kpkg/usr/share/kernel/linux-sc7280/kernel.release" "$r/usr/share/kernel/linux-sc7280/"
cp "$t/kpkg/usr/lib/modules/$kver/modules.builtin" "$r/usr/lib/modules/$kver/"
printf 'root=UUID=%s rw rootwait\n' "$uuid" > "$r/etc/kernel/cmdline"
printf 'UUID=%s / ext4 defaults,x-systemd.growfs 0 1\n' "$uuid" > "$r/etc/fstab"
printf 'LANG=en_US.UTF-8\n' > "$r/etc/locale.conf"
printf 'spacewar\n' > "$r/etc/hostname"
printf '[Autologin]\nUser=user\nSession=omarchy.desktop\nRelogin=true\n' > "$r/etc/sddm.conf.d/zz-spacewar-autologin.conf"
printf 'root:x:0:0::/root:/bin/bash\nuser:x:%s:%s::/home/user:/bin/bash\n' "$(id -u)" "$(id -g)" > "$r/etc/passwd"
printf '[wifi]\nssid=test\n' > "$r/etc/NetworkManager/system-connections/home.nmconnection"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest test\n' > "$r/home/user/.ssh/authorized_keys"
: > "$r/home/user/.local/state/omarchy/indicators/stay-awake"
: > "$r/usr/lib/firmware/updates/ath11k/WCN6750/hw1.0/board-2.bin"
: > "$r/usr/lib/firmware/qcom/a660_sqe.fw.zst"
: > "$r/etc/machine-id"
chmod 644 "$r"/etc/{kernel/cmdline,fstab,locale.conf,hostname,sddm.conf.d/zz-spacewar-autologin.conf}
chmod 600 "$r/etc/NetworkManager/system-connections/home.nmconnection" "$r/home/user/.ssh/authorized_keys"
ln -s /dev/null "$r/etc/systemd/system/systemd-firstboot.service"
for unit in sshd NetworkManager systemd-networkd systemd-oomd avahi-daemon spacewar-audio-reprobe rmtfs tqftpserv msm-modem-uim-selection ModemManager 81voltd; do ln -s "/usr/lib/systemd/system/$unit.service" "$r/etc/systemd/system/multi-user.target.wants/"; done
ln -s /etc/systemd/system/spacewar-usb-gadget.service "$r/etc/systemd/system/multi-user.target.wants/"
ln -s /usr/lib/systemd/system/sddm.service "$r/etc/systemd/system/display-manager.service"

for entry in bluetooth.target:bluetooth graphical.target:power-profiles-daemon sysinit.target:systemd-resolved; do
  target=${entry%:*} unit=${entry#*:}
  mkdir -p "$r/etc/systemd/system/$target.wants"
  ln -s "/usr/lib/systemd/system/$unit.service" "$r/etc/systemd/system/$target.wants/"
done
mkdir -p "$r/usr/lib/systemd/system" "$r/home/user/.local/state/omarchy/toggles"
printf '[Service]\nExecStart=/usr/bin/rmtfs -r -P -s\n' > "$r/usr/lib/systemd/system/rmtfs.service"
: > "$r/home/user/.local/state/omarchy/toggles/screensaver-off"
install -Dm644 "$repo/tools/rootfs/30-spacewar-wifi-mac.conf" "$r/etc/NetworkManager/conf.d/30-spacewar-wifi-mac.conf"
python3 - "$repo" "$r" <<'SETUP'
import importlib.machinery
import os
from pathlib import Path
import sys
repo, root = map(Path, sys.argv[1:])
import subprocess
import shlex
# Use the builder's actual selection, then exercise the setup shipped in that archive.
plan = subprocess.check_output([str(repo / 'tools/build-rootfs.sh'), 'verify-test', '--dry-run'], text=True)
for name in ['nothing-spacewar-mobile-shell', 'omarchy-osk-spacewar']:
    archive = next(line.split(': ', 1)[1] for line in plan.splitlines()
                   if line.startswith(f'Local package {name}: '))
    subprocess.run(['bsdtar', '-xf', archive, '-C', str(root)], check=True)
mobile = root / 'usr/share/nothing-spacewar/mobile-shell'
home = root / 'home/user'
os.environ.update(HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'), XDG_STATE_HOME=str(home / '.local/state'))
m = importlib.machinery.SourceFileLoader('setup', str(root / 'usr/bin/spacewar-shell-setup')).load_module()
m.configure(home / '.config', home / '.local/state/spacewar-shell', mobile)
# Execute the OSK seed commands from the builder in this isolated HOME.
builder = (repo / 'tools/build-rootfs.sh').read_text()
seed = builder.split('  spacewar-shell-setup\n', 1)[1].split("\n# No keyboard", 1)[0]
subprocess.run(['bash', '-ec', shlex.split("'" + seed)[0]], check=True)

lua = home / '.config/hypr/hyprland.lua'
lua.write_text(lua.read_text().replace(str(root), ''))
for link in (home / '.config/omarchy/plugins').iterdir():
    target = '/' + str(link.readlink().relative_to(root))
    link.unlink()
    link.symlink_to(target)
SETUP

i=$t/initrd
mkdir -p "$i/hooks" "$i/usr/lib/systemd" "$i/usr/lib/modules/$kver/kernel/drivers"
: > "$i/init"; : > "$i/hooks/udev"; : > "$i/usr/lib/systemd/systemd-udevd"
for module in fsa4480 panel-visionox-rm692e5 spi-geni-qcom fts_tp; do : > "$i/usr/lib/modules/$kver/kernel/drivers/$module.ko.zst"; done
bsdtar --format newc -cf - -C "$i" . | zstd -q > "$t/initramfs.img"

printf '\0%.0s' {1..128} > "$t/Image"
printf '\x00\x01' | dd of="$t/Image" bs=1 seek=16 conv=notrunc status=none
printf 'ARM\x64' | dd of="$t/Image" bs=1 seek=56 conv=notrunc status=none
"$repo/pkgs/nothing-spacewar-boot/spacewar-mkbootimg" --image "$t/Image" --dtb "$r/boot/dtbs/qcom/sm7325-nothing-spacewar.dtb" \
  --initramfs "$t/initramfs.img" --cmdline "$r/etc/kernel/cmdline" \
  --deviceinfo "$repo/pkgs/nothing-spacewar-boot/deviceinfo" --output "$r/boot/boot.img" >/dev/null

w=$t/work
mkdir "$w"
cp "$r/boot/boot.img" "$w/boot.img"
truncate -s 32M "$w/spacewar-rootfs.img"
mkfs.ext4 -q -F -U "$uuid" -L spacewar-root -m 0 -d "$r" "$w/spacewar-rootfs.img"
own_root=(etc/kernel/cmdline etc/fstab etc/locale.conf etc/hostname etc/sddm.conf.d/zz-spacewar-autologin.conf
  etc/NetworkManager/system-connections/home.nmconnection)
for path in "${own_root[@]}"; do printf 'sif /%s uid 0\nsif /%s gid 0\n' "$path" "$path"; done > "$t/chown.debugfs"
debugfs -w -f "$t/chown.debugfs" "$w/spacewar-rootfs.img" >/dev/null 2>&1
printf '%s\n' "$uuid" > "$w/root.uuid"
printf '%s\n' 'firmware-nothing-spacewar 3-2' 'limine-entry-tool 1-1' "linux-sc7280 ${kver%-sc7280}" \
  'nothing-spacewar-boot 1-4' 'nothing-spacewar-ucm 1-1' 'omarchy-dev 4.0.0.r7031.gcce8b1c-1' > "$w/packages.txt"
for name in bootmac qrtr rmtfs tqftpserv hexagonrpcd 81voltd dummystreamhack q6voiced msm-modem omarchy-osk-spacewar nothing-spacewar-mobile-shell modemmanager libqmi python-pywayland blueman nm-connection-editor; do
  printf '%s 1-1\n' "$name" >> "$w/packages.txt"
done

seal() { img2simg "$1/spacewar-rootfs.img" "$1/spacewar-rootfs.sparse.img"
  (cd "$1" && sha256sum boot.img spacewar-rootfs.img packages.txt root.uuid spacewar-rootfs.sparse.img > SHA256SUMS); }
seal "$w"

run() { set +e; "$verify" "$1" > "$t/out" 2>&1; rc=$?; set -e; }
expect_ok() {
  run "$w"
  if ((rc != 0)) || grep -q '^FAIL' "$t/out"; then cat "$t/out"; echo "TEST FAIL: clean image rejected"; exit 1; fi
  if ! cmp -s <(cd "$w" && sha256sum ./*) "$t/before"; then echo 'TEST FAIL: workdir modified'; exit 1; fi
  echo "ok: clean image ($(grep -c '^PASS' "$t/out") PASS)"
}
expect_fail() {
  local name=$1 pattern=$2 copy=$t/case
  rm -rf "$copy"; cp -a "$w" "$copy"
  local mutate=$3
  shift 3; "$mutate" "$copy" "$@"
  run "$copy"
  if ((rc == 0)) || ! grep -Eq "^FAIL  $pattern" "$t/out"; then
    cat "$t/out"; echo "TEST FAIL: $name"; exit 1
  fi
  echo "ok: $name -> $(grep '^FAIL' "$t/out" | cut -c7-80 | paste -sd'|')"
}
(cd "$w" && sha256sum ./*) > "$t/before"
expect_ok
flip_boot() { printf 'X' | dd of="$1/boot.img" bs=1 seek=5000 conv=notrunc status=none; }
expect_fail 'tampered boot.img' 'sha256sum -c' flip_boot
add_limine() { echo 'limine 9.0-1' >> "$1/packages.txt"; seal "$1"; }
expect_fail 'limine installed' 'installed: limine' add_limine
umask_bug() { debugfs -w -R 'sif /etc/fstab mode 0100600' "$1/spacewar-rootfs.img" >/dev/null 2>&1; seal "$1"; }
expect_fail 'fstab 0600' '/etc/fstab 0644' umask_bug
leftover() { printf 'abc\n' > "$t/mid"; debugfs -w -R "write $t/mid /var/tmp/spacewar-packages" "$1/spacewar-rootfs.img" >/dev/null 2>&1; seal "$1"; }
expect_fail 'leftover /var/tmp/spacewar-*' '/var/tmp leftovers: spacewar-packages' leftover
remove_mask() { debugfs -w -R 'rm /home/user/.config/systemd/user/omarchy-fcitx5.service' "$1/spacewar-rootfs.img" >/dev/null 2>&1; seal "$1"; }
expect_fail 'missing fcitx5 mask' 'fcitx5 user mask' remove_mask
enable_voice() { debugfs -w -R 'symlink /etc/systemd/system/multi-user.target.wants/q6voiced.service /usr/lib/systemd/system/q6voiced.service' "$1/spacewar-rootfs.img" >/dev/null 2>&1; seal "$1"; }
expect_fail 'q6voiced enabled' 'q6voiced enabled' enable_voice
bad_osk() { printf '{"autoShow":"never"}\n' > "$t/bad-json"; debugfs -w -R 'rm /home/user/.config/omarchy/onscreen-keyboard.json' "$1/spacewar-rootfs.img" >/dev/null 2>&1; debugfs -w -R "write $t/bad-json /home/user/.config/omarchy/onscreen-keyboard.json" "$1/spacewar-rootfs.img" >/dev/null 2>&1; seal "$1"; }
expect_fail 'OSK disabled' 'mobile-shell JSON or Lua profile invalid' bad_osk
old_osk() { printf 'hl.exec_once("squeekboard")\n' > "$t/old-osk"; debugfs -w -R "write $t/old-osk /home/user/.config/hypr/autostart.lua" "$1/spacewar-rootfs.img" >/dev/null 2>&1; seal "$1"; }
expect_fail 'squeekboard autostart' 'squeekboard autostart present' old_osk

for legacy in hyprgrass nothing-spacewar-mobile-ui; do
  add_legacy() { printf '%s 99-1\n' "$legacy" >> "$1/packages.txt"; seal "$1"; }
  expect_fail "$legacy installed" "installed: $legacy" add_legacy
done
remove_shell() { sed -i '/^nothing-spacewar-mobile-shell /d' "$1/packages.txt"; seal "$1"; }
expect_fail 'missing mobile-shell' 'packages.txt lacks nothing-spacewar-mobile-shell' remove_shell
remove_torch() { debugfs -w -R 'rm /usr/lib/udev/rules.d/90-spacewar-torch.rules' "$1/spacewar-rootfs.img" >/dev/null 2>&1; seal "$1"; }
expect_fail 'missing torch rule' 'torch udev add rule' remove_torch
bad_device() { sed 's/kb_layout = "us,ru"/kb_layout = "us"/' "$r/usr/share/nothing-spacewar/mobile-shell/phone-device.lua" > "$t/bad-device"
  debugfs -w -R 'rm /usr/share/nothing-spacewar/mobile-shell/phone-device.lua' "$1/spacewar-rootfs.img" >/dev/null 2>&1
  debugfs -w -R "write $t/bad-device /usr/share/nothing-spacewar/mobile-shell/phone-device.lua" "$1/spacewar-rootfs.img" >/dev/null 2>&1; seal "$1"; }
expect_fail 'missing Russian layout' 'kb_layout is not us,ru' bad_device
bad_profile() {
  local defect=$2
  python3 - "$r/home/user/.config" "$t/profile" "$defect" <<'PROFILE'
import json
from pathlib import Path
import sys
config, dest = map(Path, sys.argv[1:3])
defect = sys.argv[3]
if defect == 'lua':
    text = '-- missing device include\n'
elif defect == 'legacy':
    text = (config / 'hypr/hyprland.lua').read_text() + 'hl.plugin.load("/usr/lib/hyprgrass/libhyprgrass.so")\n'
else:
    shell = json.loads((config / 'omarchy/shell.json').read_text())
    if defect == 'dock':
        shell['plugins'].append({'id': 'omarchy.dock'})
    else:
        shell['plugins'] = [p for p in shell['plugins'] if p['id'] != 'spacewar.gestures']
    text = json.dumps(shell)
dest.write_text(text)
PROFILE
  local path=/home/user/.config/omarchy/shell.json
  [[ $defect != lua && $defect != legacy ]] || path=/home/user/.config/hypr/hyprland.lua
  debugfs -w -R "rm $path" "$1/spacewar-rootfs.img" >/dev/null 2>&1
  debugfs -w -R "write $t/profile $path" "$1/spacewar-rootfs.img" >/dev/null 2>&1; seal "$1"
}
for defect in lua legacy dock gestures; do
  expect_fail "invalid profile: $defect" 'mobile-shell JSON or Lua profile invalid' bad_profile "$defect"
done

other_uuid() { uuidgen > "$1/root.uuid"; seal "$1"; }
rm -rf "$t/case"; cp -a "$w" "$t/case"; other_uuid "$t/case"; run "$t/case"
if ((rc == 0)) || ! grep -q '^FAIL  cmdline lacks root=UUID' "$t/out" || ! grep -q '^FAIL  blkid UUID' "$t/out"; then
  cat "$t/out"; echo 'TEST FAIL: wrong root.uuid not caught'; exit 1
fi
echo "ok: wrong root.uuid -> $(grep -c '^FAIL' "$t/out") FAIL (cmdline, fstab, blkid, ...)"
echo 'verify-image: PASS'
