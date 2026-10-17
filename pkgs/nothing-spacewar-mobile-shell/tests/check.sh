#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
makepkg --force --nodeps
luac -p phone-device.lua
shell_root=${OMARCHY_QA_ROOT:?Set OMARCHY_QA_ROOT to extracted r7031 usr/share/omarchy}
lint_root=$(mktemp -d /tmp/spacewar-lint.XXXXXX)
trap 'rm -rf "$lint_root"' EXIT
mkdir -p "$lint_root/qs/services"
ln -s "$shell_root/shell/Commons" "$lint_root/qs/Commons"
ln -s "$shell_root/shell/Ui" "$lint_root/qs/Ui"
printf 'module qs.services\n' > "$lint_root/qs/services/qmldir"
for file in "$shell_root"/shell/services/*; do
  ln -s "$file" "$lint_root/qs/services/${file##*/}"
  if [[ $file == *.qml ]]; then
    name=${file##*/}
    printf '%s 1.0 %s\n' "${name%.qml}" "$name" >> "$lint_root/qs/services/qmldir"
  fi
done
mapfile -d '' qml_files < <(find plugins -name '*.qml' -print0)
/usr/lib/qt6/bin/qmllint --uncreatable-type disable --missing-property disable \
  --unqualified disable -I /usr/lib/qt6/qml -I "$lint_root" "${qml_files[@]}"
mapfile -t archives < <(makepkg --packagelist)
python tests/inspect_package.py "${archives[0]}"
