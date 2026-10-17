#!/bin/bash
set -euo pipefail

fail() { printf 'build-rootfs: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'USAGE'
Usage: sudo tools/build-rootfs.sh <build-name> [--uuid UUID] [--pkg-dir DIR ...] [--ssh-key FILE] [--nm-connection FILE ...]
       tools/build-rootfs.sh <build-name> --dry-run [same options]
Default package directories: device/kernel/firmware, modem/*, omarchy-osk-spacewar, nothing-spacewar-mobile-shell under pkgs/.
--pkg-dir replaces the defaults; repeat for multiple directories. Highest pkgver-pkgrel per required pkgname wins.
Dry-run prints the plan and missing packages without downloads, writes, binfmt registration or chroot.
Build names contain only letters, digits, dots, underscores and hyphens (no . or ..).
The script creates a private root-owned workdir under /var/tmp/spacewar-build. Reruns rebuild rootfs and images from verified inputs, keeping the UUID.
USAGE
}
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
assets=$repo/tools/rootfs
dry_run=false
uuid=
ssh_key=$(getent passwd user | cut -d: -f6)/.ssh/id_ed25519_spacewar.pub
pkg_dirs=()
nm_connections=()
work=
while (($#)); do
  case $1 in
    --dry-run) dry_run=true; shift ;;
    --uuid|--pkg-dir|--ssh-key|--nm-connection)
      (($# >= 2)) || fail "missing value for $1"
      case $1 in
        --uuid) uuid=${2,,} ;; --pkg-dir) pkg_dirs+=("$2") ;; --ssh-key) ssh_key=$2 ;; --nm-connection) nm_connections+=("$2") ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) fail "unknown option $1" ;;
    *) [[ -z $work ]] || fail 'only one build name is accepted'; work=$1; shift ;;
  esac
done
[[ -n $work ]] || { usage >&2; exit 1; }
[[ -z $uuid || $uuid =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || fail 'invalid UUID'
[[ $work =~ ^[A-Za-z0-9._-]+$ && $work != . && $work != .. ]] || fail 'invalid build name'
parent=/var/tmp/spacewar-build
work=$parent/$work
canonical=$(realpath -m -- "$work")
[[ $canonical =~ ^[A-Za-z0-9/._-]+$ && $canonical == "$work" ]] || fail 'unsafe canonical workdir'
rootfs=$work/rootfs
if ((${#pkg_dirs[@]} == 0)); then
  for name in linux-sc7280 firmware-nothing-spacewar nothing-spacewar-boot nothing-spacewar-ucm modem/bootmac modem/qrtr modem/rmtfs modem/tqftpserv modem/hexagonrpcd modem/81voltd modem/dummystreamhack modem/q6voiced modem/msm-modem omarchy-osk-spacewar nothing-spacewar-mobile-shell; do
    pkg_dirs+=("$repo/pkgs/$name")
  done
fi
for tool in bsdtar realpath vercmp awk sed sort sha256sum; do
  command -v "$tool" >/dev/null || fail "missing host tool: $tool"
done
required=(linux-sc7280 firmware-nothing-spacewar nothing-spacewar-boot nothing-spacewar-ucm bootmac qrtr rmtfs tqftpserv hexagonrpcd 81voltd dummystreamhack q6voiced msm-modem omarchy-osk-spacewar nothing-spacewar-mobile-shell)
repo_packages=(modemmanager libqmi python-pywayland blueman nm-connection-editor)
declare -A selected=() versions=()
shopt -s nullglob
for dir in "${pkg_dirs[@]}"; do
  [[ -d $dir ]] || fail "package directory missing: $dir"
  for archive in "$dir"/*.pkg.tar.zst "$dir"/*.pkg.tar.xz; do
    metadata=$(bsdtar -xOf "$archive" .PKGINFO) || fail "bad package: $archive"
    name=$(awk -F ' = ' '$1=="pkgname" {print $2}' <<<"$metadata")
    [[ " ${required[*]} " == *" $name "* && -n $name ]] || continue
    arch=$(awk -F ' = ' '$1=="arch" {print $2}' <<<"$metadata")
    [[ $arch == any || $arch == aarch64 ]] || continue
    version=$(awk -F ' = ' '$1=="pkgver" {print $2}' <<<"$metadata")
    [[ -n $version ]] || fail "no pkgver: $archive"
    if [[ -z ${selected[$name]:-} ]] || (( $(vercmp "$version" "${versions[$name]}") > 0 )); then
      selected[$name]=$(realpath -- "$archive")
      versions[$name]=$version
    fi
  done
done
# shellcheck disable=SC1091
source "$assets/upstream/aarch64-package-filter.sh"
defaults_text=$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' \
  "$assets/upstream/install_omarchy-base.packages" \
  "$assets/upstream/install_omarchy-aarch64.packages" \
  "$assets/upstream/install_omarchy-aarch64-qualcomm.packages")
mapfile -t defaults <<< "$defaults_text"
filtered_text=$(filter_aarch64_packages linux-sc7280 "${defaults[@]}")
desktop_text=$(awk '!/^(qcom-firmware-extract|systemd-ukify|limine|limine-mkinitcpio-hook|limine-snapper-sync|efibootmgr|snapper)$/ && !seen[$0]++' <<< "$filtered_text")
[[ -n $desktop_text ]] || fail 'empty desktop package list'
mapfile -t desktop_packages <<< "$desktop_text"
if [[ -f $work/root.uuid ]]; then
  saved_uuid=$(<"$work/root.uuid")
  [[ -z $uuid || $uuid == "$saved_uuid" ]] || fail 'UUID differs from existing workdir'
  uuid=$saved_uuid
fi
[[ -z $uuid || $uuid =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || fail 'corrupt persisted UUID'
timezone=$(realpath /etc/localtime)
[[ $timezone == /usr/share/zoneinfo/* && -f $timezone ]] || fail 'host timezone must resolve into /usr/share/zoneinfo'
timezone=${timezone#/usr/share/zoneinfo/}
missing=false
for name in "${required[@]}"; do
  printf 'Local package %s: %s\n' "$name" "${selected[$name]:-MISSING}"
  [[ -n ${selected[$name]:-} ]] || missing=true
done
if $dry_run; then
  printf 'Workdir: %s\nUUID: %s\nTimezone: %s\nSSH public key: %s\n' "$work" "${uuid:-persisted or generated at build}" "$timezone" "$ssh_key"
  printf 'ALARM: signed latest from https://de3.mirror.archlinuxarm.org/os/\n'
  printf 'Omarchy: edge aarch64, omarchy-dev; packages (%s):\n' "${#desktop_packages[@]}"
  printf '%s\n' "${desktop_packages[@]}"
  printf 'Additional repository packages:\n'; printf '%s\n' "${repo_packages[@]}"
  printf 'Plan: verify ALARM -> extract -> arch-chroot setup + packages -> mkbootimg -> ext4 -> Android sparse -> SHA256SUMS\n'
  if $missing; then printf 'Build blocked until all required local packages exist.\n'; fi
  exit 0
fi
for path in "$parent" "$work"; do
  if [[ -e $path || -L $path ]]; then
    [[ -d $path && ! -L $path && $(stat -c '%u:%a' "$path") == 0:700 ]] || fail "expected root-owned mode 700 directory: $path"
  fi
done
((EUID == 0)) || fail 'run as root; use --dry-run for an unprivileged plan'
$missing && fail 'build the missing local packages first'
[[ -r $ssh_key ]] || fail "missing SSH public key: $ssh_key"
[[ $(<"$ssh_key") == ssh-ed25519\ * ]] || fail 'expected an Ed25519 public key'
for conn in "${nm_connections[@]}"; do
  [[ -r $conn && ${conn##*/} =~ ^[A-Za-z0-9._-]+\.nmconnection$ ]] || fail "bad NetworkManager profile: $conn"
  grep -qx 'type=wifi' "$conn" || fail "not a Wi-Fi profile: $conn"
done
for tool in curl gpg md5sum arch-chroot mkfs.ext4 e2fsck blkid uuidgen flock findmnt mountpoint; do
  command -v "$tool" >/dev/null || fail "missing host tool: $tool"
done
[[ -x /usr/bin/qemu-aarch64-static && -x /usr/lib/systemd/systemd-binfmt ]] || fail 'install qemu-user-static and systemd-binfmt'
[[ -r /usr/lib/binfmt.d/qemu-aarch64-static.conf ]] || fail 'aarch64 binfmt config missing'
[[ ! -L $work ]] || fail 'workdir must not be a symlink'
umask 077
[[ -d $parent ]] || mkdir -m700 "$parent"
[[ -d $work ]] || mkdir -m700 "$work"
for path in "$parent" "$work"; do
  [[ -d $path && ! -L $path && $(stat -c '%u:%a' "$path") == 0:700 ]] || fail "expected root-owned mode 700 directory: $path"
done
# The 700 workdir keeps the build private; files inside the target rootfs need normal system modes.
umask 022
exec {build_lock}< "$work"
flock -n "$build_lock" || fail 'another build is using this workdir'
[[ ! -L $work/.spacewar-builder && ! -L $work/.spacewar-builder.partial ]] || fail 'symlink workdir marker'
if [[ ! -f $work/.spacewar-builder ]]; then
  [[ -z $(find "$work" -mindepth 1 -maxdepth 1 ! -name .spacewar-builder.partial -print -quit) ]] || fail 'new workdir must be empty'
  printf 'spacewar-rootfs-v1\n' > "$work/.spacewar-builder.partial"
  mv -f "$work/.spacewar-builder.partial" "$work/.spacewar-builder"
fi
[[ $(<"$work/.spacewar-builder") == spacewar-rootfs-v1 ]] || fail 'unknown workdir marker'
for path in rootfs rootfs.new cache root.uuid boot.img packages.txt spacewar-rootfs.img spacewar-rootfs.sparse.img SHA256SUMS; do
  [[ ! -L $work/$path && ! -L $work/$path.partial ]] || fail "symlink in workdir: $path"
done
# Never delete a tree with chroot mounts left behind by an interrupted process.
mount_targets=$(findmnt -rn --raw -o TARGET)
while IFS= read -r target; do
  [[ $target != "$rootfs" && $target != "$rootfs/"* && $target != "$work/rootfs.new" && $target != "$work/rootfs.new/"* ]] || fail "stale mount: $target (unmount before retry)"
done <<< "$mount_targets"
if [[ -f $work/root.uuid ]]; then
  saved_uuid=$(<"$work/root.uuid")
  [[ -z $uuid || $uuid == "$saved_uuid" ]] || fail 'UUID differs from existing workdir'
  uuid=$saved_uuid
else
  uuid=${uuid:-$(uuidgen)}
  printf '%s\n' "$uuid" > "$work/root.uuid.partial"
  mv -f "$work/root.uuid.partial" "$work/root.uuid"
fi
[[ $uuid =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || fail 'corrupt persisted UUID'
if [[ ! -r /proc/sys/fs/binfmt_misc/status ]]; then
  mountpoint -q /proc/sys/fs/binfmt_misc || mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
fi
registration=/proc/sys/fs/binfmt_misc/qemu-aarch64
if [[ ! -e $registration ]]; then
  /usr/lib/systemd/systemd-binfmt /usr/lib/binfmt.d/qemu-aarch64-static.conf
fi
[[ -r $registration ]] || fail 'aarch64 binfmt registration failed'
if ! grep -qx enabled "$registration" || ! grep -q '^flags:.*F' "$registration" || \
  ! grep -qx 'interpreter /usr/bin/qemu-aarch64-static' "$registration"; then
  fail 'existing aarch64 binfmt must be enabled, static, with F flag'
fi
rm -f "$work/SHA256SUMS"
mkdir -p "$work/cache" "$work/cache/gnupg"
chmod 700 "$work/cache/gnupg"
base=https://de3.mirror.archlinuxarm.org/os
filename=ArchLinuxARM-aarch64-latest.tar.gz
fetch() { curl --fail --location --retry 3 --output "$2" "$1"; }
fetch "$base/$filename.md5" "$work/cache/$filename.md5.partial"
fetch "$base/$filename.sig" "$work/cache/$filename.sig.partial"
expected=$(awk -v name="$filename" '$2==name && $1 ~ /^[0-9a-f]+$/ && length($1)==32 {print $1}' "$work/cache/$filename.md5.partial")
[[ $expected =~ ^[0-9a-f]{32}$ ]] || fail 'invalid official MD5 file'
tarball=$work/cache/$filename
if [[ ! -f $tarball || $(md5sum "$tarball" | cut -d' ' -f1) != "$expected" ]]; then
  fetch "$base/$filename" "$tarball.partial"
  [[ $(md5sum "$tarball.partial" | cut -d' ' -f1) == "$expected" ]] || fail 'ALARM MD5 mismatch (mirror may have rotated latest; retry)'
else
  cp --reflink=auto "$tarball" "$tarball.partial"
fi
alarm_key=68B3537F39A313B3E574D06777193F152BDBE6A6
gpg --homedir "$work/cache/gnupg" --batch --keyserver hkps://keyserver.ubuntu.com \
  --keyserver-options timeout=30 --recv-keys "$alarm_key"
gpg --homedir "$work/cache/gnupg" --batch --status-fd 1 --verify \
  "$work/cache/$filename.sig.partial" "$tarball.partial" > "$work/cache/signature-status.partial"
awk -v key="$alarm_key" '$2=="VALIDSIG" && ($3==key || $NF==key) {ok=1} END {exit !ok}' \
  "$work/cache/signature-status.partial" || fail 'signature is not from the official ALARM key'
for file in "$filename" "$filename.md5" "$filename.sig" signature-status; do
  mv -f "$work/cache/$file.partial" "$work/cache/$file"
done
rm -rf -- "$work/rootfs.new"
mkdir "$work/rootfs.new"
bsdtar --acls --xattrs --numeric-owner -xpf "$tarball" -C "$work/rootfs.new"
rm -rf -- "$rootfs"
mv "$work/rootfs.new" "$rootfs"
for path in etc etc/kernel etc/mkinitcpio.conf.d etc/pacman.d etc/pacman.d/hooks \
  etc/systemd/system etc/systemd/network etc/NetworkManager/conf.d var/tmp \
  var/tmp/spacewar-packages usr/local/libexec var/cache/pacman/pkg boot; do
  [[ $(realpath -m -- "$rootfs/$path") == "$rootfs/$path" ]] || fail "unsafe rootfs path: $path"
done
for path in etc/kernel/cmdline etc/fstab etc/pacman.conf etc/pacman.d/mirrorlist \
  etc/mkinitcpio.conf.d/zz-spacewar-root.conf usr/local/libexec/spacewar-usb-gadget \
  etc/systemd/system/spacewar-usb-gadget.service etc/systemd/network/20-spacewar-usb.network \
  etc/NetworkManager/conf.d/20-spacewar-usb.conf etc/NetworkManager/conf.d/30-spacewar-wifi-mac.conf var/tmp/spacewar-authorized_keys \
  var/tmp/spacewar-omarchy.gpg var/tmp/spacewar-desktop.packages; do
  [[ ! -L $rootfs/$path ]] || fail "symlink rootfs destination: $path"
done
mkdir -p "$rootfs/etc/kernel" "$rootfs/etc/mkinitcpio.conf.d" "$rootfs/etc/pacman.d/hooks" \
  "$rootfs/var/tmp/spacewar-packages" "$rootfs/usr/local/libexec"
printf 'root=UUID=%s rw rootwait\n' "$uuid" > "$rootfs/etc/kernel/cmdline"
printf 'UUID=%s / ext4 defaults,x-systemd.growfs 0 1\n' "$uuid" > "$rootfs/etc/fstab"
install -m644 "$assets/upstream/pacman.conf" "$rootfs/etc/pacman.conf"
install -m644 "$assets/upstream/mirrorlist" "$rootfs/etc/pacman.d/mirrorlist"
install -m644 "$assets/zz-spacewar-root.conf" "$rootfs/etc/mkinitcpio.conf.d/zz-spacewar-root.conf"
install -m755 "$assets/spacewar-usb-gadget" "$rootfs/usr/local/libexec/spacewar-usb-gadget"
install -Dm644 "$assets/spacewar-usb-gadget.service" "$rootfs/etc/systemd/system/spacewar-usb-gadget.service"
install -Dm644 "$assets/20-spacewar-usb.network" "$rootfs/etc/systemd/network/20-spacewar-usb.network"
install -Dm644 "$assets/spacewar-usb-nm.conf" "$rootfs/etc/NetworkManager/conf.d/20-spacewar-usb.conf"
install -Dm644 "$assets/30-spacewar-wifi-mac.conf" "$rootfs/etc/NetworkManager/conf.d/30-spacewar-wifi-mac.conf"
# The generic ALARM rootfs enables networkd for all Ethernet; only USB belongs to it here.
find "$rootfs/etc/systemd/network" -maxdepth 1 -type f ! -name 20-spacewar-usb.network -delete
for name in "${required[@]}"; do
  install -m644 "${selected[$name]}" "$rootfs/var/tmp/spacewar-packages/${selected[$name]##*/}"
done
install -m644 "$ssh_key" "$rootfs/var/tmp/spacewar-authorized_keys"
# Backup access if USB fails; the interface name differs from the pmOS profile, so drop the binding.
install -d -m700 "$rootfs/etc/NetworkManager/system-connections"
[[ $(realpath -m -- "$rootfs/etc/NetworkManager/system-connections") == "$rootfs/etc/NetworkManager/system-connections" ]] || fail 'unsafe NetworkManager path'
for conn in "${nm_connections[@]}"; do
  grep -v '^interface-name=' "$conn" > "$rootfs/etc/NetworkManager/system-connections/${conn##*/}"
  chmod 600 "$rootfs/etc/NetworkManager/system-connections/${conn##*/}"
done
install -m644 "$assets/upstream/omarchy.gpg" "$rootfs/var/tmp/spacewar-omarchy.gpg"
printf '%s\n' "${desktop_packages[@]}" "${repo_packages[@]}" > "$rootfs/var/tmp/spacewar-desktop.packages"
# Do not let package hooks build a ramdisk against the host before every target module is present.
for hook in 90-mkinitcpio-install.hook 99-spacewar-boot.hook; do
  ln -sfn /dev/null "$rootfs/etc/pacman.d/hooks/$hook"
done
# Packages survive reruns outside the rootfs, which every run re-extracts.
mkdir -p "$work/cache/pkg"
cp -a --reflink=auto "$work/cache/pkg/." "$rootfs/var/cache/pacman/pkg/"
# pacman's CheckSpace needs the root to be a mountpoint.
mount --bind "$rootfs" "$rootfs"
trap 'mountpoint -q "$rootfs" && umount -R "$rootfs"' EXIT
arch-chroot "$rootfs" /bin/bash -s -- "$timezone" <<'CHROOT'
set -euo pipefail
# qemu-user cannot provide Landlock or the alpm sandbox user switch; the shipped pacman.conf keeps the sandbox.
pacman() { command pacman --disable-sandbox "$@"; }
pacman-key --init
pacman-key --populate archlinuxarm
pacman-key --add /var/tmp/spacewar-omarchy.gpg
pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571
pacman -Syu --noconfirm
pacman -S --needed --noconfirm omarchy-keyring archlinuxarm-keyring
pacman-key --populate omarchy archlinuxarm
if pacman -Q linux-aarch64 >/dev/null 2>&1; then pacman -R --noconfirm linux-aarch64; fi
# Keep the upstream LuaRocks/Neovim transaction order.
pacman -S --needed --noconfirm lua51 luarocks
# Audio and toolkit pieces the official installer takes from omarchy-other.packages; pipewire-jack first
# so later "jack" dependencies do not pull jack2.
pacman -S --needed --noconfirm pipewire pipewire-alsa pipewire-jack pipewire-pulse gst-plugin-pipewire libpulse \
  qt6-wayland gtk4-layer-shell webp-pixbuf-loader
pacman -U --noconfirm /var/tmp/spacewar-packages/*.pkg.tar.*
mapfile -t desktop < /var/tmp/spacewar-desktop.packages
# omarchy 4.0.4 predates omarchy#14553: with Qt 6.12 its shell palette (Color) is shadowed and the bar is empty.
pacman -S --needed --noconfirm omarchy-dev omarchy-settings-dev "${desktop[@]}" openssh sudo
grep -q 'Commons.Color' /usr/share/omarchy/shell/plugins/bar/Bar.qml
getent passwd user >/dev/null || useradd -m -G wheel -s /bin/bash user
usermod -aG wheel user
printf 'user:147258\n' | chpasswd
passwd -l root
if getent passwd alarm >/dev/null; then userdel -r alarm; fi
install -d -m700 -o user -g user /home/user/.ssh
install -m600 -o user -g user /var/tmp/spacewar-authorized_keys /home/user/.ssh/authorized_keys
install -d -m750 /etc/sudoers.d
printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-spacewar-wheel
chmod 440 /etc/sudoers.d/10-spacewar-wheel
visudo -cf /etc/sudoers.d/10-spacewar-wheel
printf 'spacewar\n' > /etc/hostname
ln -sfn "/usr/share/zoneinfo/$1" /etc/localtime
printf 'en_US.UTF-8 UTF-8\nru_RU.UTF-8 UTF-8\n' > /etc/locale.gen
locale-gen
printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf
printf 'KEYMAP=us\n' > /etc/vconsole.conf
# Same steps as omarchy install/user/theme.sh in iso-chroot context; OMARCHY_PATH comes from env-bootstrap.
runuser -u user -- env -i HOME=/home/user USER=user PATH=/usr/bin bash -c \
  '. /usr/share/omarchy/default/bash/env-bootstrap && mkdir -p ~/.config/omarchy/themes &&
   OMARCHY_THEME_HEADLESS=1 omarchy-theme-set "Tokyo Night" && omarchy-theme-set-pi --activate &&
   mkdir -p ~/.config/btop/themes &&
   ln -snf "$HOME/.local/state/omarchy/current/theme/btop.theme" ~/.config/btop/themes/current.theme'
[[ -s /home/user/.local/state/omarchy/current/theme.name ]]
# Idle lock needs a keyboard to unlock; Omarchy's own stay-awake switch (omarchy-toggle-idle) disables it.
runuser -u user -- install -D -m644 /dev/null /home/user/.local/state/omarchy/indicators/stay-awake
runuser -u user -- install -D -m644 /dev/null /home/user/.local/state/omarchy/toggles/screensaver-off
# Seed any missing stock configuration before applying device overrides.
runuser -u user -- env -i HOME=/home/user USER=user PATH=/usr/bin bash -ec '
  cp -an /usr/share/omarchy/config/. "$HOME/.config/"
  spacewar-shell-setup
  mkdir -p "$HOME/.config/systemd/user"
  ln -snf /dev/null "$HOME/.config/systemd/user/omarchy-fcitx5.service"
  printf "%s\n" '\''{"autoShow":"always","extraRow":true}'\'' > "$HOME/.config/omarchy/onscreen-keyboard.json"'
# No keyboard on the phone: the SDDM password field is unusable, so log straight into the Omarchy session.
install -d /etc/sddm.conf.d
printf '[Autologin]\nUser=user\nSession=omarchy.desktop\nRelogin=true\n' > /etc/sddm.conf.d/zz-spacewar-autologin.conf
systemctl enable sshd NetworkManager systemd-networkd systemd-resolved spacewar-usb-gadget sddm
# Generic services the official installer enables (install/ in omarchy); ufw stays off until USB/SSH rules exist.
systemctl enable bluetooth power-profiles-daemon systemd-oomd avahi-daemon spacewar-audio-reprobe
systemctl enable rmtfs tqftpserv msm-modem-uim-selection ModemManager 81voltd
systemctl disable q6voiced.service
systemctl --global enable gcr-ssh-agent.socket
systemctl set-default graphical.target
# Belt and braces: no console on the phone, so nothing may prompt there at first boot.
systemctl mask systemd-firstboot.service
rm -f /etc/ssh/ssh_host_* /var/lib/systemd/random-seed
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id
rm -f /etc/pacman.d/hooks/90-mkinitcpio-install.hook /etc/pacman.d/hooks/99-spacewar-boot.hook
spacewar-mkbootimg --rebuild-initramfs
pacman -Q > /var/tmp/spacewar-package-manifest
CHROOT
umount "$rootfs"
trap - EXIT
# arch-chroot's teardown does not report umount failures; a leftover bind would leak into the image.
while IFS= read -r target; do
  [[ $target != "$rootfs" && $target != "$rootfs/"* ]] || fail "mount left after chroot: $target"
done < <(findmnt -rn --raw -o TARGET)
ln -sfn ../run/systemd/resolve/stub-resolv.conf "$rootfs/etc/resolv.conf"
cp "$rootfs/var/tmp/spacewar-package-manifest" "$work/packages.txt.partial"
cp "$rootfs/boot/boot.img" "$work/boot.img.partial"
rm -rf "$rootfs/var/tmp/spacewar-packages"
rm -f "$rootfs/var/tmp/spacewar-authorized_keys" "$rootfs/var/tmp/spacewar-desktop.packages" "$rootfs/var/tmp/spacewar-package-manifest" "$rootfs/var/tmp/spacewar-omarchy.gpg"
mv -f "$rootfs/var/cache/pacman/pkg/"*.pkg.tar.* "$work/cache/pkg/" 2>/dev/null || true
used_mib=$(du --apparent-size -sm "$rootfs" | cut -f1)
# 25% growth plus 2 GiB for ext4 metadata/free space; floor 8 GiB for the desktop.
size_mib=$((used_mib + used_mib / 4 + 2048))
((size_mib >= 8192)) || size_mib=8192
printf 'rootfs apparent size: %s MiB; ext4 image: %s MiB\n' "$used_mib" "$size_mib"
image=$work/spacewar-rootfs.img
rm -f "$image.partial"
truncate -s "${size_mib}M" "$image.partial"
# libext2fs copies numeric owners, modes, hardlinks, symlinks and xattrs (including ACLs) without a loop mount.
mkfs.ext4 -F -U "$uuid" -L spacewar-root -m 0 -d "$rootfs" "$image.partial"
e2fsck -fn "$image.partial"
[[ $(blkid -p -s UUID -o value "$image.partial") == "$uuid" ]] || fail 'image UUID mismatch'
if command -v img2simg >/dev/null; then
  img2simg "$image.partial" "$work/spacewar-rootfs.sparse.img.partial"
  mv -f "$work/spacewar-rootfs.sparse.img.partial" "$work/spacewar-rootfs.sparse.img"
else
  rm -f "$work/spacewar-rootfs.sparse.img"
  printf 'img2simg not installed: raw ext4 retained. Install Android libsparse tools and run:\n'
  printf '  img2simg %q %q\n' "$image" "$work/spacewar-rootfs.sparse.img"
  printf 'Alternatively Android fastboot can auto-sparsify a raw ext4 image with its -S option; flashing is outside this builder.\n'
fi
mv -f "$image.partial" "$image"
mv -f "$work/boot.img.partial" "$work/boot.img"
mv -f "$work/packages.txt.partial" "$work/packages.txt"
(
  cd "$work"
  artifacts=(boot.img spacewar-rootfs.img packages.txt root.uuid)
  [[ ! -f spacewar-rootfs.sparse.img ]] || artifacts+=(spacewar-rootfs.sparse.img)
  sha256sum "${artifacts[@]}" "cache/$filename" "cache/$filename.md5" "cache/$filename.sig" > SHA256SUMS.partial
  mv -f SHA256SUMS.partial SHA256SUMS
  cat SHA256SUMS
)
