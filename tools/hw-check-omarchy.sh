#!/bin/bash
# Read-only hardware check of Nothing Phone (1) after the first Omarchy boot.
# Usage: tools/hw-check-omarchy.sh [host]            (default 172.16.42.1)
#        tools/hw-check-omarchy.sh --from-file <saved-output>
# PIN=<sudo password> enables sudo for journal reads; without it the journal is read as user (wheel).
# HW_CHECK_SSH and HW_CHECK_LOGDIR override the ssh binary and the log directory (tests).
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
PIN=${PIN:-}

usage() { sed -n '3,6s/^# \{0,1\}//p' "$0"; }
die() { printf 'hw-check-omarchy: %s\n' "$1" >&2; exit 2; }

# Runs on the phone (sent via `declare -f`); stdin is /dev/null so no command can eat the script.
remote_probe() {
  local uid rt sig d wl sudo_ok=no u p r g src
  uid=$(id -u)
  rt=/run/user/$uid
  if [[ -n ${PIN:-} ]] && printf '%s\n' "$PIN" | sudo -S -p '' true 2>/dev/null; then sudo_ok=yes; fi
  sj() {
    if [[ $sudo_ok == yes ]]; then printf '%s\n' "$PIN" | sudo -S -p '' journalctl --no-pager "$@"
    else journalctl --no-pager "$@"; fi
  }
  sig=none
  for d in "$rt"/hypr/*/; do
    [[ -S ${d}.socket.sock ]] || continue
    if [[ $sig == none || $d -nt $rt/hypr/$sig ]]; then sig=$(basename -- "$d"); fi
  done
  wl=none
  for d in "$rt"/wayland-[0-9]; do [[ -S $d ]] && wl=${d##*/} && break; done
  hc() { XDG_RUNTIME_DIR=$rt HYPRLAND_INSTANCE_SIGNATURE=$sig timeout 10 hyprctl "$@" 2>&1; }

  echo '== meta'
  echo "sudo $sudo_ok"
  echo "journal_lines $(sj -k -b -q -o cat -n 5 2>/dev/null | wc -l)"
  echo '== versions'
  uname -r
  pacman -Q omarchy linux-sc7280 hyprland mesa 2>&1
  echo '== failed'
  systemctl --failed --no-legend --plain --no-pager 2>&1
  echo '== remoteproc'
  for r in /sys/class/remoteproc/remoteproc*; do
    [[ -r $r/name ]] && echo "$(<"$r/name") $(<"$r/state")"
  done
  echo '== gpu'
  for p in /sys/class/drm/card*-*/status; do
    [[ -r $p ]] && echo "connector $(basename -- "${p%/status}") $(<"$p")"
  done
  sj -k -b 2>&1 | grep -iE 'adreno|a660|a6xx|gmu|zap|msm_dpu|freedreno' | tail -n 25
  echo '== renderer'
  if command -v eglinfo >/dev/null; then
    XDG_RUNTIME_DIR=$rt WAYLAND_DISPLAY=$wl timeout 15 eglinfo -B 2>&1 | grep -iE 'renderer|driver|vendor' | head -n 12
  else
    echo 'eglinfo: not installed'
  fi
  [[ -r $rt/hypr/$sig/hyprland.log ]] &&
    grep -m 4 -E ' Renderer: |GL_RENDERER|llvmpipe' "$rt/hypr/$sig/hyprland.log"
  echo '== hyprland'
  pgrep -a -i hyprland || echo 'no hyprland process'
  echo "signature $sig"
  echo "wayland $wl"
  echo '== hypr-monitors'
  hc monitors -j
  echo '== hypr-devices'
  hc devices -j
  echo '== input'
  grep -E '^N: Name=' /proc/bus/input/devices
  echo '== asound'
  cat /proc/asound/cards
  echo '== wpctl'
  XDG_RUNTIME_DIR=$rt timeout 10 wpctl status 2>&1
  echo '== ucm'
  timeout 10 alsaucm -c hw:0 list _verbs 2>&1
  echo '== modem'
  timeout 15 mmcli -L 2>&1
  timeout 15 mmcli -m any -K 2>&1 | grep -E '^modem\.(generic\.(state|state-failed-reason|model|revision|signal-quality\.value|access-technologies\.value\[1\])|3gpp\.(operator-name|registration-state)) '
  echo '== wifi'
  nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>&1
  echo "radio $(nmcli radio wifi 2>&1)"
  echo '== bluetooth'
  timeout 10 bluetoothctl show 2>&1 | grep -E 'Controller|Powered|Name:|No default'
  echo '== usb'
  for u in /sys/class/udc/*; do
    [[ -r $u/state ]] && echo "udc ${u##*/} state=$(<"$u/state") speed=$(<"$u/current_speed")"
  done
  for p in /sys/class/typec/port[0-9]; do
    [[ -r $p/data_role ]] && echo "typec ${p##*/} data_role=$(<"$p/data_role") power_role=$(<"$p/power_role")"
  done
  for r in /sys/class/usb_role/*/role; do [[ -r $r ]] && echo "usb_role $(<"$r")"; done
  for g in /sys/kernel/config/usb_gadget/*/UDC; do [[ -r $g ]] && echo "gadget $(basename -- "${g%/UDC}") UDC=$(<"$g")"; done
  for u in spacewar-usb-reprobe spacewar-usb-gadget; do echo "unit $u $(systemctl is-active "$u" 2>&1)"; done
  echo '== usb-journal'
  sj -b -u spacewar-usb-reprobe -u spacewar-usb-gadget 2>&1 | tail -n 15
  echo '== battery'
  for p in capacity status health voltage_now current_now temp; do
    [[ -r /sys/class/power_supply/qcom-battmgr-bat/$p ]] && echo "$p=$(</sys/class/power_supply/qcom-battmgr-bat/"$p")"
  done
  echo '== thermal'
  for p in /sys/class/thermal/thermal_zone*; do
    [[ -r $p/temp ]] && echo "$(<"$p/type")=$(cat "$p/temp" 2>/dev/null)"
  done
  echo '== kernel-errors'
  sj -k -b -p err -q 2>&1
  echo '== storage'
  df -h /
  src=$(findmnt -nvo SOURCE /)
  echo "rootdev $src $(lsblk -no PARTLABEL "$src" 2>/dev/null)"
  echo "fs_bytes $(df -B1 --output=size / | tail -n 1 | tr -d ' ')"
  echo "part_bytes $(lsblk -bndo SIZE "$src" 2>/dev/null)"
  echo '== time'
  echo "phone_epoch $(date +%s)"
  [[ -r /sys/class/rtc/rtc0/since_epoch ]] && echo "rtc_epoch $(</sys/class/rtc/rtc0/since_epoch)"
  timedatectl show -p NTPSynchronized -p Timezone 2>&1
  echo '== end'
}

declare -A S=()
parse() {
  local line cur=''
  while IFS= read -r line; do
    if [[ $line == '== '* ]]; then cur=${line#== }; S[$cur]=''
    elif [[ -n $cur ]]; then S[$cur]+=$line$'\n'; fi
  done < "$1"
}
sec() { printf '%s' "${S[$1]-}"; }
kv() { sec "$1" | sed -n "s/^$2[ =]//p" | head -n 1; }

fails=0 warns=0
res() {
  printf '%-4s  %-13s %s\n' "$1" "$2" "$3"
  case $1 in FAIL) fails=$((fails + 1)) ;; WARN) warns=$((warns + 1)) ;; esac
}
need() {
  [[ -v S[$1] ]] && return 0
  res FAIL "$2" "нет секции '$1' в выводе (проверка оборвалась?)"
  return 1
}

chk_versions() {
  need versions versions || return 0
  local v miss=() p
  v=$(sec versions)
  for p in omarchy linux-sc7280 hyprland mesa; do grep -qE "^$p [^ ]+$" <<<"$v" || miss+=("$p"); done
  if ((${#miss[@]})); then res FAIL versions "нет пакетов: ${miss[*]}"
  elif ! grep -q '^omarchy 4\.0\.4-' <<<"$v"; then res WARN versions "omarchy не 4.0.4: $(grep '^omarchy ' <<<"$v")"
  else res PASS versions "ядро $(head -n 1 <<<"$v"); $(grep -E '^(omarchy|linux-sc7280|hyprland|mesa) ' <<<"$v" | paste -sd ';')"
  fi
}

chk_failed() {
  need failed failed-units || return 0
  local units crit
  units=$(sec failed | awk 'NF {print $1}' | paste -sd ' ')
  crit=$(tr ' ' '\n' <<<"$units" | grep -E '^(sddm|sshd|NetworkManager|systemd-networkd|spacewar-usb-gadget|spacewar-usb-reprobe|ModemManager)\.service$' | paste -sd ' ' || true)
  if [[ -n $crit ]]; then res FAIL failed-units "критичные: $crit (все: $units)"
  elif [[ -n $units ]]; then res WARN failed-units "$units"
  else res PASS failed-units 'нет'
  fi
}

chk_remoteproc() {
  need remoteproc remoteproc || return 0
  local n bad=() ok=()
  for n in modem adsp cdsp wpss; do
    if sec remoteproc | grep -qx "$n running"; then ok+=("$n"); else bad+=("$n:$(sec remoteproc | awk -v n="$n" '$1 == n {print $2}')"); fi
  done
  if ((${#bad[@]})); then res FAIL remoteproc "не running: ${bad[*]}"; else res PASS remoteproc "${ok[*]} running"; fi
}

chk_gpu() {
  need gpu gpu || return 0
  local g conn errs
  g=$(sec gpu)
  conn=$(grep -E '^connector .* connected$' <<<"$g" | awk '{print $2}' | paste -sd ' ' || true)
  errs=$(grep -iE 'zap.*(fail|error)|hangcheck|gpu fault|gmu.*(fail|timeout|error)|\*ERROR\*|failed' <<<"$g" |
    grep -vE 'Direct firmware load for qcom/a660_(sqe|gmu)|failed to load a660_(sqe\.fw|gmu\.bin)' | grep -c . || true)
  if [[ -z $conn ]]; then res FAIL gpu 'нет connected-коннектора в /sys/class/drm'
  elif ! grep -qE 'loaded qcom/a660_sqe\.fw' <<<"$g"; then res FAIL gpu "$conn; в журнале нет 'loaded qcom/a660_sqe.fw'"
  elif ! grep -qE 'Loaded GMU firmware|loaded qcom/a660_gmu\.bin' <<<"$g"; then res FAIL gpu "$conn; GMU firmware не загружена"
  elif ((errs)); then res WARN gpu "$conn; sqe+gmu загружены, но $errs строк(и) ошибок adreno/zap/gmu"
  else res PASS gpu "$conn; sqe+gmu загружены, ошибок adreno нет"
  fi
}

chk_renderer() {
  need renderer mesa || return 0
  local r
  r=$(sec renderer)
  if grep -qiE 'llvmpipe|softpipe|swrast' <<<"$r"; then res FAIL mesa "программный рендеринг: $(grep -m 1 -iE 'llvmpipe|softpipe|swrast' <<<"$r")"
  elif grep -qiE 'FD6[0-9]{2}|adreno|freedreno|turnip' <<<"$r"; then res PASS mesa "$(grep -m 1 -iE 'FD6[0-9]{2}|adreno|freedreno|turnip' <<<"$r" | sed 's/^ *//')"
  else res WARN mesa "рендерер не опознан: $(grep -m 1 -iE 'renderer' <<<"$r" || echo 'нет данных (eglinfo нет, в hyprland.log не найдено)')"
  fi
}

chk_hyprland() {
  need hyprland hyprland || return 0
  local h sig mons name
  h=$(sec hyprland)
  sig=$(kv hyprland signature)
  mons=$(sec hypr-monitors | grep -c '"make":' || true)
  name=$(sec hypr-monitors | grep -m 1 -oE '"name": ?"[^"]*"' | sed -E 's/.*"([^"]*)"$/\1/' || true)
  if ! grep -qE '^[0-9]+ .*[Hh]yprland' <<<"$h"; then res FAIL hyprland 'процесс Hyprland не найден'
  elif [[ -z $sig || $sig == none ]]; then res FAIL hyprland "нет сокета в /run/user/<uid>/hypr/"
  elif ((mons == 0)); then res FAIL hyprland "hyprctl monitors пуст: $(sec hypr-monitors | head -n 1)"
  else res PASS hyprland "мониторов: $mons ($name), signature ${sig:0:12}…"
  fi
}

chk_touch() {
  need input touch || return 0
  if ! sec input | grep -qE 'Name="fts_(ts|tp)"'; then res FAIL touch 'fts_ts/fts_tp нет в /proc/bus/input/devices'
  elif ! sec hypr-devices | grep -q 'fts_'; then res WARN touch 'fts в ядре есть, но hyprctl devices его не показывает'
  else res PASS touch "$(sec input | grep -m 1 -oE 'fts_(ts|tp)') виден ядру и Hyprland"
  fi
}

chk_audio() {
  need asound audio || return 0
  local card sinks verbs
  card=$(sec asound | grep -m 1 -E '^ *[0-9]+ \[' | sed -E 's/ +/ /g; s/^ //' || true)
  sinks=$(sec wpctl | awk '/^Audio/{a=1} /^Video/{a=0} a && /Sinks:/{s=1; next} a && s && /(Sources|Filters|Streams|Devices):/{s=0} a && s && /[0-9]+\./ && !/Dummy Output/{n++} END{print n+0}')
  verbs=$(sec ucm | grep -E '^ *[0-9]+: ' | awk '{print $2}' | paste -sd ',' || true)
  if [[ -z $card ]]; then res FAIL audio 'нет звуковых карт в /proc/asound/cards'
  elif ((sinks == 0)); then res FAIL audio "карта: $card; wpctl Sinks пуст"
  elif [[ -z $verbs ]]; then res WARN audio "карта: $card; sinks: $sinks; UCM verbs нет"
  else res PASS audio "карта: $card; sinks: $sinks; UCM verbs: $verbs"
  fi
}

chk_modem() {
  need modem modem || return 0
  local state reason op
  state=$(sec modem | sed -n 's/^modem\.generic\.state *: *//p' | head -n 1)
  reason=$(sec modem | sed -n 's/^modem\.generic\.state-failed-reason *: *//p' | head -n 1)
  op=$(sec modem | sed -n 's/^modem\.3gpp\.operator-name *: *//p' | head -n 1)
  if ! sec modem | grep -q '/Modem/'; then res FAIL modem "mmcli -L: $(sec modem | head -n 1)"
  elif [[ $state == failed ]]; then res FAIL modem "state failed: $reason"
  elif [[ $state == locked || -z $state ]]; then res WARN modem "state: ${state:-неизвестно}"
  else res PASS modem "state: $state${op:+, оператор $op}"
  fi
}

chk_wifi() {
  need wifi wifi || return 0
  local line
  line=$(sec wifi | grep -m 1 -E '^[^:]+:wifi:' || true)
  if [[ -z $line ]]; then res FAIL wifi "нет Wi-Fi устройства в nmcli ($(kv wifi radio))"
  elif [[ $(cut -d: -f3 <<<"$line") == connected ]]; then res PASS wifi "$(cut -d: -f1 <<<"$line") → $(cut -d: -f4- <<<"$line")"
  else res WARN wifi "$(cut -d: -f1,3 <<<"$line"), radio $(kv wifi radio)"
  fi
}

chk_bluetooth() {
  need bluetooth bluetooth || return 0
  local ctl
  ctl=$(sec bluetooth | grep -m 1 -oE 'Controller [0-9A-F:]{17}' || true)
  if [[ -z $ctl ]]; then res FAIL bluetooth "нет контроллера: $(sec bluetooth | head -n 1)"
  elif sec bluetooth | grep -qE 'Powered: yes'; then res PASS bluetooth "$ctl, powered"
  else res WARN bluetooth "$ctl, не включён"
  fi
}

chk_usb() {
  need usb usb || return 0
  local udc gadget reprobe unit
  udc=$(sec usb | grep -m 1 '^udc ' || true)
  gadget=$(sec usb | grep -m 1 -E '^gadget .* UDC=a600000\.usb$' || true)
  unit=$(sec usb | awk '$1 == "unit" && $2 == "spacewar-usb-gadget" {print $3}')
  reprobe=$(sec usb | awk '$1 == "unit" && $2 == "spacewar-usb-reprobe" {print $3}')
  local roles
  roles=$(sec usb | grep -E '^(typec|usb_role) ' | paste -sd ';' || true)
  if [[ -z $udc ]]; then res FAIL usb 'нет UDC в /sys/class/udc'
  elif [[ $unit != active || $reprobe == failed ]]; then res FAIL usb "gadget=$unit reprobe=$reprobe; ${udc#udc }"
  elif [[ -z $gadget ]]; then res FAIL usb "gadget не привязан к a600000.usb; ${udc#udc }"
  elif [[ $udc != *'state=configured'* ]]; then res WARN usb "${udc#udc } (не configured — кабель/хост?); $roles"
  else res PASS usb "${udc#udc }; $roles"
  fi
}

chk_battery() {
  need battery battery || return 0
  local cap status t
  cap=$(kv battery capacity)
  status=$(kv battery status)
  t=$(kv battery temp)
  if [[ ! $cap =~ ^[0-9]+$ ]]; then res FAIL battery 'qcom-battmgr-bat/capacity не читается'
  elif ((cap < 15)) && [[ $status != Charging ]]; then res WARN battery "$cap% $status"
  else res PASS battery "$cap% $status${t:+, $((t / 10)).$((t % 10))°C}"
  fi
}

chk_thermal() {
  need thermal thermal || return 0
  local max zone
  read -r max zone < <(sec thermal | awk -F= '$2 ~ /^-?[0-9]+$/ && $2 > m || NR == 1 {m = $2; z = $1} END {print m + 0, z}')
  if [[ -z $zone ]]; then res WARN thermal 'нет thermal_zone'
  elif ((max >= 85000)); then res FAIL thermal "макс. $((max / 1000))°C ($zone)"
  elif ((max >= 70000)); then res WARN thermal "макс. $((max / 1000))°C ($zone)"
  else res PASS thermal "макс. $((max / 1000))°C ($zone)"
  fi
}

# Benign at boot per logs/hw-check-stage1.txt (pmOS stage 1 on the same kernel line).
known_kerr='failed to send synthetic uevent|Failed to create device link|unable to open an initial console|a660_sqe\.fw|s5kjn1|Frame reassembly failed|unexpected event for opcode 0xfc48|Unknown cmd 0x100f6'
chk_kernel() {
  need kernel-errors kernel-errors || return 0
  local lines total unknown crash
  lines=$(sec kernel-errors | grep -v '^-- ' | grep . || true)
  total=$(grep -c . <<<"$lines" || true)
  unknown=$(grep -vE "$known_kerr" <<<"$lines" | grep . || true)
  crash=$(grep -m 1 -E 'Oops|BUG:|Kernel panic|Internal error|Call trace' <<<"$lines" || true)
  if [[ $(kv meta journal_lines) == 0 ]]; then res WARN kernel-errors 'журнал ядра не читается (задай PIN=…)'
  elif [[ -n $crash ]]; then res FAIL kernel-errors "$crash"
  elif [[ -n $unknown ]]; then res WARN kernel-errors "$total строк err, новых $(grep -c . <<<"$unknown"): $(head -n 1 <<<"$unknown" | cut -c1-140)"
  else res PASS kernel-errors "$total строк err, все известные по этапу 1"
  fi
}

chk_storage() {
  need storage growfs || return 0
  local fs part pct
  fs=$(kv storage fs_bytes)
  part=$(kv storage part_bytes)
  if [[ ! $fs =~ ^[0-9]+$ || ! $part =~ ^[0-9]+$ || $part == 0 ]]; then res FAIL growfs "размеры не прочитаны: fs=$fs part=$part"; return 0; fi
  pct=$((fs * 100 / part))
  # df size excludes ext4 metadata (inode tables, journal), so ~97-98% is a fully grown fs.
  if ((pct >= 90)); then res PASS growfs "/ = $((fs >> 30)) GiB из раздела $((part >> 30)) GiB ($pct%)"
  else res FAIL growfs "/ = $((fs >> 30)) GiB из раздела $((part >> 30)) GiB ($pct%) — growfs не сработал"
  fi
}

chk_time() {
  need time time || return 0
  local phone laptop diff ntp
  phone=$(kv time phone_epoch)
  laptop=$(kv local laptop_epoch)
  ntp=$(sec time | sed -n 's/^NTPSynchronized=//p')
  if [[ ! $phone =~ ^[0-9]+$ || ! $laptop =~ ^[0-9]+$ ]]; then res WARN time "нет меток времени (phone=$phone laptop=$laptop)"; return 0; fi
  diff=$((phone - laptop))
  diff=${diff#-}
  if ((diff > 86400)); then res FAIL time "часы расходятся с ноутбуком на ${diff}s, NTP=$ntp"
  elif ((diff > 120)) || [[ $ntp != yes ]]; then res WARN time "расхождение ${diff}s, NTP=$ntp"
  else res PASS time "расхождение ${diff}s, NTP=$ntp"
  fi
}

summary() {
  parse "$1"
  chk_versions; chk_failed; chk_remoteproc; chk_gpu; chk_renderer; chk_hyprland; chk_touch
  chk_audio; chk_modem; chk_wifi; chk_bluetooth; chk_usb; chk_battery; chk_thermal
  chk_kernel; chk_storage; chk_time
  [[ -v S[end] ]] || res FAIL probe 'вывод оборван до "== end"'
  printf 'ИТОГ: FAIL=%d WARN=%d\n' "$fails" "$warns"
}

case ${1:-} in
  -h | --help) usage; exit 0 ;;
  --from-file)
    [[ -r ${2:-} ]] || die "нет файла: ${2:-}"
    summary "$2"
    exit $((fails ? 1 : 0)) ;;
  -*) die "неизвестный аргумент: $1" ;;
esac
host=${1:-172.16.42.1}
[[ $host =~ ^[A-Za-z0-9.:-]+$ ]] || die "плохой host: $host"
logdir=${HW_CHECK_LOGDIR:-$repo/logs}
mkdir -p "$logdir"
log=$logdir/hw-check-omarchy-$(date +%Y%m%d-%H%M%S).txt
{
  echo '== local'
  echo "host $host"
  echo "date $(date -Is)"
  echo "laptop_epoch $(date +%s)"
} > "$log"
rc=0
{ printf 'PIN=%q\n' "$PIN"; declare -f remote_probe; echo 'remote_probe </dev/null'; } |
  "${HW_CHECK_SSH:-ssh}" -i "$HOME/.ssh/id_ed25519_spacewar" -o IdentitiesOnly=yes \
    -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$HOME/.ssh/known_hosts_spacewar" "user@$host" 'bash -s' >> "$log" 2>&1 || rc=$?
if ! grep -q '^== meta$' "$log"; then
  printf 'FAIL  ssh           user@%s недоступен (ssh rc=%d): %s\n' "$host" "$rc" "$(tail -n 1 "$log")"
  printf 'Лог: %s\n' "$log"
  exit 2
fi
out=$(summary "$log") || true
printf '== summary\n%s\n' "$out" >> "$log"
printf '%s\nЛог: %s\n' "$out" "$log"
grep -q '^ИТОГ: FAIL=0 ' <<<"$out"
