#!/bin/bash
# Copy a verified build out of the root-owned workdir so fastboot can flash it as user.
set -euo pipefail
name=${1:?usage: export-image.sh <build-name>}
[[ $name =~ ^[A-Za-z0-9._-]+$ && $name != . && $name != .. ]] || { echo 'invalid build name' >&2; exit 1; }
src=/var/tmp/spacewar-build/$name
dst=/home/user/Projects/omarchy-spacewar/rollback/$name
for f in boot.img spacewar-rootfs.sparse.img SHA256SUMS; do [[ -f $src/$f && ! -L $src/$f ]] || { echo "missing $src/$f" >&2; exit 1; }; done
install -d -m755 -o user -g user "$dst"
install -m644 -o user -g user "$src/boot.img" "$src/spacewar-rootfs.sparse.img" "$src/SHA256SUMS" "$dst/"
cd "$dst" && grep -E ' (boot.img|spacewar-rootfs.sparse.img)$' SHA256SUMS | sha256sum -c
