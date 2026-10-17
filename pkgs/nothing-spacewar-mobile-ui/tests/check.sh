#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

shellcheck_bin=${SHELLCHECK:-shellcheck}
qmllint_bin=${QMLLINT:-/usr/lib/qt6/bin/qmllint}
omarchy_root=${OMARCHY_QA_ROOT:-/usr/share/omarchy}
"$shellcheck_bin" -s bash -e SC2034,SC2154 PKGBUILD tests/check.sh poster.sh
luac -p phone-device.lua
luac -p phone-mobile.lua
luac -p phone-lock.lua
makepkg --nodeps --force --noconfirm
artifact="$PWD/pkg/nothing-spacewar-mobile-ui/usr/share/nothing-spacewar/mobile"
MOBILE_ACTIONS="$artifact/spacewar-mobile" MOBILE_SETUP="$artifact/spacewar-mobile-setup" python3 -m unittest discover -s tests -p 'test_*.py'

if [[ -x $qmllint_bin ]]; then
  lint_root=$(mktemp -d /tmp/swm-lint.XXXXXX)
  trap 'rm -rf -- "$lint_root"' EXIT
  mkdir -p "$lint_root/qs"
  ln -s "$omarchy_root/shell/Commons" "$lint_root/qs/Commons"
  ln -s "$omarchy_root/shell/Ui" "$lint_root/qs/Ui"
  "$qmllint_bin" --uncreatable-type disable --missing-property disable -I /usr/lib/qt6/qml -I "$lint_root" \
    "$artifact"/plugins/*/*.qml "$artifact"/ui/*.qml
fi
printf '%s\n' 'PASS: build, archive setup/undo, actions, Lua, shellcheck, QML lint (when available)'
