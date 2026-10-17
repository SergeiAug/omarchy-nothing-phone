# Pinned official inputs (2026-10-17)

These files are unmodified copies fetched using `gh api repos/OWNER/REPO/contents/PATH?ref=COMMIT --jq .content | base64 -d`.

Omarchy commit: [`cce8b1c971df64a7610b818ff8819e4bea04584a`](https://github.com/omacom/omarchy/tree/cce8b1c971df64a7610b818ff8819e4bea04584a), branch `quattro`.

| Local file | Upstream path |
| --- | --- |
| pacman.conf | default/pacman/aarch64/pacman-edge.conf |
| mirrorlist | default/pacman/aarch64/mirrorlist-edge |
| install_omarchy-base.packages | install/omarchy-base.packages |
| install_omarchy-aarch64.packages | install/omarchy-aarch64.packages |
| install_omarchy-aarch64-qualcomm.packages | install/omarchy-aarch64-qualcomm.packages |

ISO commit: [`db483455f4a107b737134f7443ce0eff97f34756`](https://github.com/omacom/omarchy-iso/tree/db483455f4a107b737134f7443ce0eff97f34756), branch `quattro`.

| Local file | Upstream path |
| --- | --- |
| aarch64-package-filter.sh | builder/aarch64-package-filter.sh |
| omarchy.gpg | builder/omarchy.gpg |

Both upstream projects use the MIT license; see their LICENSE files. The bootstrap key's primary fingerprint is `40DFB630FF42BCFFB047046CF0134EE680CAC571`. Package lists/configuration are pinned for review; the ALARM tarball and package repositories are rolling. Omarchy itself is constrained to `4.0.4`, not the development build corresponding to these manifests. Refresh these inputs together after reviewing upstream changes.
