#!/bin/bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
script=$repo/tools/hw-check-omarchy.sh
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export HW_CHECK_LOGDIR=$work/logs HW_CHECK_SSH=$work/ssh
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

now=$(date +%s)
cat > "$work/good" <<EOF
== meta
sudo yes
journal_lines 5
== versions
7.2.9-sc7280
omarchy 4.0.4-1
linux-sc7280 7.2.9-1
hyprland 0.52.1-1
mesa 1:26.0.0-1
== failed
plymouth-start.service loaded failed failed Show Plymouth Boot Screen
== remoteproc
modem running
adsp running
wpss running
cdsp running
== gpu
connector card0-DSI-1 connected
Oct 18 09:00:01 spacewar kernel: msm_dpu ae01000.display-controller: Direct firmware load for qcom/a660_sqe.fw failed with error -2
Oct 18 09:00:01 spacewar kernel: msm_dpu ae01000.display-controller: [drm:adreno_request_fw] *ERROR* failed to load a660_sqe.fw
Oct 18 09:00:06 spacewar kernel: msm_dpu ae01000.display-controller: [drm:adreno_request_fw] loaded qcom/a660_sqe.fw from new location
Oct 18 09:00:06 spacewar kernel: msm_dpu ae01000.display-controller: [drm:adreno_request_fw] loaded qcom/a660_gmu.bin from new location
Oct 18 09:00:06 spacewar kernel: [drm] Loaded GMU firmware v3.1.10
== renderer
eglinfo: not installed
DEBUG from aquamarine ]: Renderer: FD660
== hyprland
812 Hyprland
signature abcdef0123456789_1760000000_1
wayland wayland-1
== hypr-monitors
[{
    "id": 0,
    "name": "DSI-1",
    "make": "Nothing",
    "activeWorkspace": { "id": 1, "name": "1" }
}]
== hypr-devices
{ "touch": [ { "address": "0x1", "name": "fts_ts" } ] }
== input
N: Name="pmic_pwrkey"
N: Name="gpio-keys"
N: Name="fts_ts"
== asound
 0 [NP1            ]: sm8250 - NP1
                      NP1
== wpctl
PipeWire 'pipewire-0' [1.4.9, user@spacewar, cookie:1]
 └─ Clients:
        33. WirePlumber

Audio
 ├─ Devices:
 │      45. NP1                                 [alsa]
 │
 ├─ Sinks:
 │  *   50. NP1 Speaker                         [vol: 0.40]
 │
 ├─ Sources:
 │  *   51. NP1 Mic                             [vol: 1.00]
 │
 └─ Streams:

Video
 ├─ Devices:
 │      60. qcom-camss                          [v4l2]
== ucm
  0: HiFi
    Play HiFi quality Music
  1: Voice Call
    Call
== modem
    /org/freedesktop/ModemManager1/Modem/0 [QUALCOMM INCORPORATED] 0
modem.generic.state                              : registered
modem.3gpp.operator-name                         : TestCarrier
== wifi
wlan0:wifi:connected:Home
p2p-dev-wlan0:wifi-p2p:disconnected:
usb0:ethernet:unmanaged:
radio enabled
== bluetooth
Controller 02:00:00:00:00:01 (public)
	Name: spacewar
	Powered: yes
== usb
udc a600000.usb state=configured speed=high-speed
typec port0 data_role=host [device] power_role=[sink] source
usb_role device
gadget spacewar UDC=a600000.usb
unit spacewar-usb-reprobe inactive
unit spacewar-usb-gadget active
== usb-journal
Oct 18 09:00:03 spacewar systemd[1]: Finished Spacewar USB NCM gadget.
== battery
capacity=87
status=Discharging
temp=312
== thermal
aoss0-thermal=36400
cpu7-thermal=41200
gpuss0-thermal=38000
== kernel-errors
Oct 18 09:00:01 spacewar kernel: power_supply qcom-battmgr-bat: uevent: failed to send synthetic uevent: -11
Oct 18 09:00:03 spacewar kernel: s5kjn1 18-002d: probe with driver s5kjn1 failed with error -22
== storage
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda17      108G   14G   90G  14% /
rootdev /dev/sda17 userdata
fs_bytes 115000000000
part_bytes 118000000000
== time
phone_epoch $((now + 3))
NTPSynchronized=yes
Timezone=Etc/UTC
== end
EOF

sed -e 's/^modem running$/modem offline/' \
  -e '/NP1 Speaker/d' \
  -e 's/^fs_bytes .*/fs_bytes 9000000000/' \
  -e 's/FD660/llvmpipe (LLVM 20.1, 128 bits)/' \
  -e 's/^unit spacewar-usb-gadget active$/unit spacewar-usb-gadget failed/' \
  -e 's/^plymouth-start.service/sddm.service/' \
  -e '/^== time$/,$d' "$work/good" > "$work/bad"

cat > "$work/ssh" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$HW_CHECK_STUB_DIR/argv"
cat > "$HW_CHECK_STUB_DIR/stdin"
case $HW_CHECK_STUB_MODE in
  down) echo 'ssh: connect to host 172.16.42.1 port 22: No route to host' >&2; exit 255 ;;
  local) exec bash -s < "$HW_CHECK_STUB_DIR/stdin" ;;
  *) cat "$HW_CHECK_STUB_DIR/$HW_CHECK_STUB_MODE" ;;
esac
EOF
chmod +x "$work/ssh"
export HW_CHECK_STUB_DIR=$work
run() { HW_CHECK_STUB_MODE=$1 PIN=${PIN-} "$script" "${@:2}" > "$work/out" 2>&1; }

run good && rc=0 || rc=$?
((rc == 0)) || { cat "$work/out"; fail "good fixture exit $rc"; }
grep -q '^ИТОГ: FAIL=0 WARN=1$' "$work/out" || { cat "$work/out"; fail 'good fixture: expected exactly the plymouth WARN'; }
for item in versions remoteproc gpu mesa hyprland touch audio modem wifi bluetooth usb battery thermal kernel-errors growfs time; do
  grep -qE "^PASS  $item " "$work/out" || { cat "$work/out"; fail "good fixture: $item not PASS"; }
done
for opt in BatchMode=yes ConnectTimeout=8 StrictHostKeyChecking=accept-new user@172.16.42.1 \
  "UserKnownHostsFile=$HOME/.ssh/known_hosts_spacewar"; do
  grep -qxF "$opt" "$work/argv" || fail "ssh option $opt"
done
log=$(sed -n 's/^Лог: //p' "$work/out")
[[ -f $log && $log == "$HW_CHECK_LOGDIR"/hw-check-omarchy-*.txt ]] || fail "log not saved: $log"
grep -q '^== summary$' "$log" || fail 'summary missing from log'

"$script" --from-file "$log" > "$work/again" || fail '--from-file on saved good log'
diff <(sed -n '/^== summary$/,$p' "$log" | tail -n +2) "$work/again" || fail '--from-file summary differs from live run'

PIN="12 34\$x" run good 10.0.0.5 || fail 'wifi host run'
grep -qx 'user@10.0.0.5' "$work/argv" || fail 'host argument ignored'
! grep -qF '12 34' "$work/argv" || fail 'PIN leaked into ssh argv'
grep -qxF "PIN=12\\ 34\\\$x" "$work/stdin" || fail 'PIN not passed on stdin'

run bad && rc=0 || rc=$?
((rc == 1)) || { cat "$work/out"; fail "bad fixture exit $rc"; }
for item in failed-units remoteproc mesa audio usb growfs probe; do
  grep -qE "^FAIL  $item " "$work/out" || { cat "$work/out"; fail "bad fixture: $item not FAIL"; }
done
grep -qE '^FAIL  time .*нет секции' "$work/out" || fail 'bad fixture: truncated output not reported'

run down && rc=0 || rc=$?
if ((rc != 2)) || ! grep -q '^FAIL  ssh ' "$work/out"; then cat "$work/out"; fail "unreachable host exit $rc"; fi

# The real probe on this laptop through bash -s: every section is emitted and parsed.
PIN='' run local && rc=0 || rc=$?
log=$(sed -n 's/^Лог: //p' "$work/out")
for s in meta versions failed remoteproc gpu renderer hyprland hypr-monitors hypr-devices input asound wpctl ucm \
  modem wifi bluetooth usb usb-journal battery thermal kernel-errors storage time end; do
  grep -qx "== $s" "$log" || { cat "$work/out"; fail "local probe: section $s missing"; }
done
if lsblk -bndo SIZE "$(findmnt -nvo SOURCE /)" >/dev/null 2>&1; then
  grep -qE '^PASS  growfs ' "$work/out" || { cat "$work/out"; fail 'local probe: growfs sizes not parsed'; }
else
  grep -qE '^FAIL  growfs .*размеры не прочитаны' "$work/out" || { cat "$work/out"; fail 'local probe: unavailable root device not reported'; }
fi

printf 'hw-check-omarchy summary, ssh options, PIN via stdin, --from-file, unreachable host, local probe run: PASS\n'
