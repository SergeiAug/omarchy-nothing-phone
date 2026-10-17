#!/bin/bash
# pass/fail always succeed, so `a && pass || fail` is an if/else; deviceinfo variables come from source.
# shellcheck disable=SC2015,SC2154
set -euo pipefail

usage() { echo 'Usage: pkexec tools/verify-image.sh /var/tmp/spacewar-build/<build-name>'; }
(($# == 1)) || { usage >&2; exit 2; }
[[ $1 != -h && $1 != --help ]] || { usage; exit 0; }
work=$(realpath -e -- "$1")
[[ -d $work ]] || { echo "not a directory: $work" >&2; exit 2; }
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
dtc=${DTC:-$repo/.work/review-kernel/scripts/dtc/dtc}
[[ -x $dtc ]] || dtc=$(command -v dtc) || { echo "dtc not found (set DTC=)" >&2; exit 2; }
for tool in unpack_bootimg debugfs e2fsck blkid bsdtar lsinitcpio gzip sha256sum awk python3; do
  command -v "$tool" >/dev/null || { echo "missing host tool: $tool" >&2; exit 2; }
done

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
failures=0
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; failures=$((failures + 1)); }
check() { local what=$1; shift; if "$@"; then pass "$what"; else fail "$what"; fi; }

boot=$work/boot.img
img=$work/spacewar-rootfs.img
uuid=$(<"$work/root.uuid") || uuid=
[[ $uuid =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || fail "root.uuid malformed: '$uuid'"

echo "== 1. SHA256SUMS"
if sums=$(cd "$work" && sha256sum -c SHA256SUMS 2>&1); then
  pass "sha256sum -c: $(grep -c ': OK$' <<<"$sums") files OK"
else
  fail "sha256sum -c: $(grep -v ': OK$' <<<"$sums" | tr '\n' ';')"
fi
[[ -f $work/spacewar-rootfs.sparse.img ]] && grep -q ' spacewar-rootfs.sparse.img$' "$work/SHA256SUMS" 2>/dev/null \
  && pass 'sparse image present and listed' || fail 'spacewar-rootfs.sparse.img missing or not in SHA256SUMS'

echo "== 2. boot.img"
declare -A arg=()
if mapfile -d '' -t fields < <(unpack_bootimg --boot_img "$boot" --out "$tmp/boot" --format mkbootimg -0) && ((${#fields[@]})); then
  for ((i = 0; i + 1 < ${#fields[@]}; i += 2)); do arg[${fields[i]}]=${fields[i + 1]}; done
fi
# shellcheck disable=SC1091
source "$repo/pkgs/nothing-spacewar-boot/deviceinfo"
same() { [[ ${arg[$1]:-} =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]] && (( ${arg[$1]} == $2 )); }
for pair in "--header_version $deviceinfo_header_version" "--pagesize $deviceinfo_flash_pagesize" \
  "--base $deviceinfo_flash_offset_base" "--kernel_offset $deviceinfo_flash_offset_kernel" \
  "--ramdisk_offset $deviceinfo_flash_offset_ramdisk" "--tags_offset $deviceinfo_flash_offset_tags" \
  "--dtb_offset $deviceinfo_flash_offset_dtb"; do
  read -r key want <<<"$pair"
  check "$key ${arg[$key]:-<none>} == deviceinfo $want" same "$key" "$want"
done
[[ ${arg[--pagesize]:-0} == 0x00001000 ]] && pass 'pagesize 0x1000' || fail "pagesize ${arg[--pagesize]:-<none>}"
cmdline=${arg[--cmdline]:-}
[[ " $cmdline " == *" root=UUID=$uuid "* ]] && pass "cmdline: $cmdline" || fail "cmdline lacks root=UUID=$uuid: '$cmdline'"
kernel=$tmp/boot/kernel dtb=$tmp/boot/dtb
if [[ -s $kernel && -s $dtb ]]; then
  ksize=$(stat -c %s "$kernel") dsize=$(stat -c %s "$dtb")
  if ((ksize > dsize)) && cmp -s -i "$((ksize - dsize)):0" "$kernel" "$dtb"; then
    pass "kernel blob ends with the $dsize-byte DTB section"
  else
    fail 'kernel blob does not end with the DTB section'
  fi
  if head -c "$((ksize - dsize))" "$kernel" | gzip -dc > "$tmp/Image" 2>/dev/null &&
    [[ $(od -An -tx1 -j56 -N4 "$tmp/Image" | tr -d ' ') == 41524d64 ]]; then
    pass "kernel = gzip ARM64 Image ($(stat -c %s "$tmp/Image") bytes) + DTB"
  else
    fail 'kernel blob prefix is not a gzip ARM64 Image'
  fi
  if "$dtc" -I dtb -O dts -q -o "$tmp/dts" "$dtb"; then
    pass 'DTB decompiles with dtc'
    awk '/adsp-rpc-remote-heap[@ ]*\{/ {n=1} n && /no-map;/ {ok=1} n && /\};/ {n=0} END {exit !ok}' "$tmp/dts" \
      && pass 'adsp-rpc-remote-heap has no-map' || fail 'adsp-rpc-remote-heap without no-map'
    grep -Eq '^	compatible = .*"nothing,spacewar"' "$tmp/dts" \
      && pass 'root compatible contains nothing,spacewar' || fail 'root compatible lacks nothing,spacewar'
  else
    fail 'dtc cannot decompile the DTB'
  fi
else
  fail 'unpack_bootimg produced no kernel/dtb'
fi

echo "== 3. initramfs"
ramdisk=$tmp/boot/ramdisk
case $(od -An -tx1 -N4 "$ramdisk" 2>/dev/null | tr -d ' ') in
  28b52ffd) format=zstd ;; 1f8b*) format=gzip ;; 30373037) format=cpio ;; *) format=unknown ;;
esac
# mkinitcpio prepends an uncompressed early cpio; bsdtar would list only that first segment.
if [[ $format != unknown ]] && lsinitcpio "$ramdisk" > "$tmp/initramfs.list" 2>/dev/null; then
  pass "initramfs $format cpio, $(wc -l < "$tmp/initramfs.list") entries"
else
  fail "initramfs unreadable (format $format)"
  : > "$tmp/initramfs.list"
fi
sed -i 's|^\./||' "$tmp/initramfs.list"
for entry in init hooks/udev usr/lib/systemd/systemd-udevd; do
  grep -qx "$entry" "$tmp/initramfs.list" && pass "initramfs has /$entry" || fail "initramfs lacks /$entry"
done

echo "== 4. rootfs ext4"
dfs() { debugfs -R "$1" "$img" 2>/dev/null; }
# Prints: type mode uid size [link-target]; empty when the path is missing.
inode() {
  dfs "stat \"$1\"" | awk '/^Inode:/ {t=$4; m=$6} /^User:/ {u=$2; s=$NF}
    /^Fast link dest:/ {sub(/^Fast link dest: "/, ""); sub(/"$/, ""); l=$0}
    END {if (t != "") print t, m, u, s, l}'
}
exists() { [[ -n $(inode "$1") ]]; }
mode_is() { local t m u s; read -r t m u s _ <<<"$(inode "$1")"; [[ $t == regular && $m == "$2" && $u == "$3" ]]; }
link_to() { local t l; read -r t _ _ _ l <<<"$(inode "$1")"; [[ $t == symlink ]] || return 1;
  [[ -n $l ]] || l=$(dfs "cat \"$1\"");
  [[ $l == "$2" ]]; }
describe() { inode "$1" | awk '{printf "%s mode %s uid %s size %s%s", $1, $2, $3, $4, ($5 ? " -> " $5 : "")}'; }

if [[ $(blkid -p -s UUID -o value "$img" 2>/dev/null) == "$uuid" ]]; then pass "blkid UUID $uuid"
else fail "blkid UUID '$(blkid -p -s UUID -o value "$img" 2>/dev/null || true)' != root.uuid"; fi
if out=$(e2fsck -fn "$img" 2>&1); then pass "e2fsck -fn clean: $(tail -n1 <<<"$out")"
else fail "e2fsck -fn: $(tail -n3 <<<"$out" | tr '\n' ';')"; fi

grep -Eq "^UUID=${uuid}[[:space:]]+/[[:space:]]+ext4[[:space:]]+[^[:space:]]*x-systemd\.growfs" <<<"$(dfs 'cat /etc/fstab')" \
  && pass '/etc/fstab: root by UUID with x-systemd.growfs' || fail "/etc/fstab: $(dfs 'cat /etc/fstab' | tr '\n' ';')"
[[ " $(dfs 'cat /etc/kernel/cmdline' | tr '\n' ' ') " == *" root=UUID=$uuid "* ]] \
  && pass '/etc/kernel/cmdline has root=UUID' || fail "/etc/kernel/cmdline: $(dfs 'cat /etc/kernel/cmdline')"
autologin=$(dfs 'cat /etc/sddm.conf.d/zz-spacewar-autologin.conf')
grep -qx 'User=user' <<<"$autologin" && grep -qx 'Session=omarchy.desktop' <<<"$autologin" \
  && pass 'SDDM autologin user/omarchy.desktop' || fail "SDDM autologin: $(tr '\n' ';' <<<"$autologin")"

user_uid=$(dfs 'cat /etc/passwd' | awk -F: '$1=="user" {print $3}')
[[ $user_uid =~ ^[0-9]+$ ]] && pass "user user uid $user_uid" || { fail 'no user in /etc/passwd'; user_uid=x; }
check "stay-awake indicator: $(describe /home/user/.local/state/omarchy/indicators/stay-awake)" \
  exists /home/user/.local/state/omarchy/indicators/stay-awake
keys=/home/user/.ssh/authorized_keys
check "authorized_keys 0600 owned by user: $(describe "$keys")" mode_is "$keys" 0600 "$user_uid"
[[ $(dfs "cat $keys") == ssh-ed25519\ * ]] && pass 'authorized_keys is ssh-ed25519' || fail 'authorized_keys is not ssh-ed25519'

nm_dir=/etc/NetworkManager/system-connections
mapfile -t profiles < <(dfs "ls -p $nm_dir" | awk -F/ '$6 ~ /\.nmconnection$/ {print $6}')
((${#profiles[@]})) || echo "WARN  no NetworkManager profiles in $nm_dir (builder --nm-connection is optional)"
for name in "${profiles[@]}"; do
  check "$name 0600 root: $(describe "$nm_dir/$name")" mode_is "$nm_dir/$name" 0600 0
  ! grep -q '^interface-name=' <<<"$(dfs "cat \"$nm_dir/$name\"")" \
    && pass "$name has no interface-name" || fail "$name binds interface-name"
done

board=/usr/lib/firmware/updates/ath11k/WCN6750/hw1.0/board-2.bin
check "$board: $(describe "$board")" exists "$board"
if exists /usr/lib/firmware/qcom/a660_sqe.fw; then pass 'a660_sqe.fw present'
elif exists /usr/lib/firmware/qcom/a660_sqe.fw.zst; then pass 'a660_sqe.fw.zst present'
else fail 'a660_sqe.fw(.zst) missing'; fi

read -r t _ _ s _ <<<"$(inode /etc/machine-id)"
[[ $t == regular && $s == 0 ]] && pass '/etc/machine-id exists and is empty' || fail "/etc/machine-id: $(describe /etc/machine-id)"
check 'systemd-firstboot masked' link_to /etc/systemd/system/systemd-firstboot.service /dev/null
wants=/etc/systemd/system/multi-user.target.wants
for unit in sshd NetworkManager spacewar-usb-gadget systemd-networkd systemd-oomd avahi-daemon spacewar-audio-reprobe rmtfs tqftpserv msm-modem-uim-selection ModemManager 81voltd; do
  read -r t _ _ _ l <<<"$(inode "$wants/$unit.service")"
  [[ $t == symlink && ${l##*/} == "$unit.service" ]] && pass "$unit enabled -> $l" || fail "$unit not enabled ($wants)"
done
for entry in bluetooth.target:bluetooth graphical.target:power-profiles-daemon sysinit.target:systemd-resolved; do
  target=${entry%:*} unit=${entry#*:}
  check "$unit enabled" link_to "/etc/systemd/system/$target.wants/$unit.service" "/usr/lib/systemd/system/$unit.service"
done
for target in multi-user.target graphical.target sysinit.target; do
  ! exists "/etc/systemd/system/$target.wants/q6voiced.service" && pass "q6voiced disabled in $target" || fail "q6voiced enabled in $target"
done
rmtfs=$(dfs 'cat /usr/lib/systemd/system/rmtfs.service')
grep -Eq '^ExecStart=[^ ]*/rmtfs([[:space:]]+[^[:space:]]+)*[[:space:]]+-r([[:space:]]|$)' <<<"$rmtfs" \
  && pass 'rmtfs read-only (-r)' || fail 'rmtfs lacks read-only -r'
user_config=/home/user/.config
check 'fcitx5 user mask' link_to "$user_config/systemd/user/omarchy-fcitx5.service" /dev/null
check 'screensaver-off toggle' exists /home/user/.local/state/omarchy/toggles/screensaver-off
for ident in omamobile.bar omamobile.quicksettings omamobile.switcher omamobile.home omamobile.launcher spacewar.gestures spacewar.runtime io.github.yeutterg.onscreen-keyboard; do
  dest=/usr/share/nothing-spacewar/mobile-shell/plugins/$ident
  [[ $ident != io.github.yeutterg.onscreen-keyboard ]] || dest=/usr/share/nothing-spacewar/osk
  check "$ident plugin link" link_to "$user_config/omarchy/plugins/$ident" "$dest"
  [[ $ident == spacewar.runtime ]] || check "$ident manifest installed" exists "$dest/manifest.json"
done
for path in /usr/share/nothing-spacewar/osk/helper/osk-helper.py \
  /usr/share/nothing-spacewar/osk/Layouts.js /usr/share/nothing-spacewar/mobile-shell/phone-device.lua \
  /etc/NetworkManager/conf.d/30-spacewar-wifi-mac.conf; do
  check "$path installed" exists "$path"
done
dfs 'cat /usr/share/nothing-spacewar/mobile-shell/phone-device.lua' > "$tmp/phone-device.lua"
check 'phone-device.lua matches packaged device profile' cmp -s "$tmp/phone-device.lua" "$repo/pkgs/nothing-spacewar-mobile-shell/phone-device.lua"
grep -Eq 'kb_layout[[:space:]]*=[[:space:]]*"us,ru"' "$tmp/phone-device.lua" \
  && pass 'kb_layout us,ru' || fail 'kb_layout is not us,ru'
dfs 'cat /usr/lib/udev/rules.d/90-spacewar-torch.rules' > "$tmp/torch.rules"
check 'torch udev add rule matches package' cmp -s "$tmp/torch.rules" "$repo/pkgs/nothing-spacewar-mobile-shell/90-spacewar-torch.rules"
for entry in shell:omarchy/shell.json osk:omarchy/onscreen-keyboard.json lua:hypr/hyprland.lua phone:hypr/phone.lua; do
  dfs "cat $user_config/${entry#*:}" > "$tmp/${entry%:*}"
done
if python3 - "$tmp" <<'MOBILE'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
shell = json.loads((root / 'shell').read_text())
osk = json.loads((root / 'osk').read_text())
ids = {'omamobile.bar', 'omamobile.quicksettings', 'omamobile.switcher',
       'omamobile.home', 'omamobile.launcher', 'spacewar.gestures',
       'io.github.yeutterg.onscreen-keyboard'}
active = {p['id'] for p in shell['plugins']}
assert shell['bar']['id'] == 'omamobile.bar' and shell['bar']['position'] == 'top'
assert ids <= active
assert not ids.intersection(shell.get('disabledPlugins', []))
assert not {'omarchy.dock', 'spacewar.dock', 'spacewar.shade', 'spacewar.switcher', 'spacewar.lock'} & active
assert 'omarchy.dock' in shell.get('disabledPlugins', [])
assert 'omarchy.lock' not in shell.get('disabledPlugins', [])
assert osk['autoShow'] == 'always' and osk['extraRow'] is True
lua = (root / 'lua').read_text()
assert lua.count('dofile("/usr/share/nothing-spacewar/mobile-shell/phone-device.lua")') == 1
for text in [lua, (root / 'phone').read_text()]:
    assert 'hyprgrass' not in text and 'phone-mobile.lua' not in text
    assert '/nothing-spacewar/mobile/' not in text
MOBILE
then pass 'mobile-shell JSON and Lua profile enabled without optional lock'
else fail 'mobile-shell JSON or Lua profile invalid'; fi
# Inspect all autostart and user-unit files, including nested wants directories.
mkdir "$tmp/autostart"
dfs "rdump $user_config/hypr $tmp/autostart" >/dev/null
dfs "rdump $user_config/autostart $tmp/autostart" >/dev/null
dfs "rdump $user_config/systemd $tmp/autostart" >/dev/null
dfs "rdump /etc/xdg/autostart $tmp/autostart" >/dev/null
if grep -rIE '^[[:space:]]*[^#-].*squeekboard' "$tmp/autostart" >/dev/null; then
  fail 'squeekboard autostart present'
else pass 'no squeekboard autostart'; fi

read -r t _ _ _ l <<<"$(inode /etc/systemd/system/display-manager.service)"
[[ $t == symlink && ${l##*/} == sddm.service ]] && pass "display-manager -> $l" || fail 'sddm not enabled as display-manager'

inner=$(dfs 'cat /boot/boot.img' | sha256sum | cut -d' ' -f1)
outer=$(sha256sum "$boot" | cut -d' ' -f1)
[[ $inner == "$outer" ]] && pass "/boot/boot.img == workdir boot.img ($outer)" || fail "/boot/boot.img sha256 $inner != $outer"
inner_dtb=$(dfs 'cat /boot/dtbs/qcom/sm7325-nothing-spacewar.dtb' | sha256sum | cut -d' ' -f1)
[[ -s $dtb && $inner_dtb == $(sha256sum "$dtb" | cut -d' ' -f1) ]] \
  && pass 'boot.img DTB == rootfs /boot/dtbs/qcom/sm7325-nothing-spacewar.dtb' || fail 'boot.img DTB differs from rootfs DTB'

cached=$(dfs 'ls -p /var/cache/pacman/pkg' | awk -F/ '$6 != "." && $6 != ".." && NF > 1 {print $6}' | tr '\n' ' ')
[[ -z $cached ]] && pass '/var/cache/pacman/pkg empty' || fail "/var/cache/pacman/pkg: $cached"
leftovers=$(dfs 'ls -p /var/tmp' | awk -F/ '$6 ~ /^spacewar-/ {print $6}' | tr '\n' ' ')
[[ -z $leftovers ]] && pass 'no /var/tmp/spacewar-*' || fail "/var/tmp leftovers: $leftovers"

configs=(/etc/locale.conf /etc/hostname /etc/fstab /etc/kernel/cmdline)
mapfile -t -O "${#configs[@]}" configs < <(dfs 'ls -p /etc/sddm.conf.d' | awk -F/ '$6 ~ /\.conf$/ {print "/etc/sddm.conf.d/" $6}')
for path in "${configs[@]}"; do
  check "$path 0644 root: $(describe "$path")" mode_is "$path" 0644 0
done

kver=$(awk -F/ '$1=="usr" && $2=="lib" && $3=="modules" && $4 != "" {print $4; exit}' "$tmp/initramfs.list")
release=$(dfs 'cat /usr/share/kernel/linux-sc7280/kernel.release')
[[ -n $kver && $kver == "$release" ]] && pass "initramfs modules $kver == rootfs kernel.release" \
  || fail "initramfs modules '$kver' != rootfs kernel.release '$release'"
builtin=$(dfs "cat /usr/lib/modules/$release/modules.builtin" | awk -F/ '{sub(/\.ko$/, "", $NF); gsub(/-/, "_", $NF); print $NF}')
[[ -n $builtin ]] || fail "rootfs /usr/lib/modules/$release/modules.builtin missing"
shipped=$(awk -F/ '$NF ~ /\.ko(\.(zst|xz|gz))?$/ {sub(/\.ko(\.(zst|xz|gz))?$/, "", $NF); gsub(/-/, "_", $NF); print $NF}' "$tmp/initramfs.list")
modules=$(sed -n 's/^MODULES+=(\(.*\))/\1/p' "$repo/pkgs/nothing-spacewar-boot/spacewar.conf" "$repo/tools/rootfs/zz-spacewar-root.conf")
for module in $modules; do
  name=${module//-/_}
  if grep -qx "$name" <<<"$shipped"; then pass "module $module in initramfs"
  elif grep -qx "$name" <<<"$builtin"; then pass "module $module builtin"
  else fail "module $module neither in initramfs nor builtin"; fi
done

echo "== 5. packages.txt"
pkgs=$(<"$work/packages.txt") || pkgs=
for want in 'omarchy-dev .*' 'linux-sc7280 .*' 'firmware-nothing-spacewar .*' 'nothing-spacewar-boot .*' 'nothing-spacewar-ucm .*' 'bootmac .*' 'qrtr .*' 'rmtfs .*' 'tqftpserv .*' 'hexagonrpcd .*' '81voltd .*' 'dummystreamhack .*' 'q6voiced .*' 'msm-modem .*' 'omarchy-osk-spacewar .*' 'nothing-spacewar-mobile-shell .*' 'modemmanager .*' 'libqmi .*' 'python-pywayland .*' 'blueman .*' 'nm-connection-editor .*'; do
  line=$(grep -x "$want" <<<"$pkgs" || true)
  [[ -n $line ]] && pass "installed: $line" || fail "packages.txt lacks ${want//\\/}"
done
for banned in linux-aarch64 limine squeekboard nothing-spacewar-mobile-ui hyprgrass; do
  ! grep -q "^$banned " <<<"$pkgs" && pass "not installed: $banned" || fail "installed: $(grep "^$banned " <<<"$pkgs")"
done

echo
if ((failures)); then echo "RESULT: $failures FAIL"; exit 1; fi
echo 'RESULT: all checks PASS'
