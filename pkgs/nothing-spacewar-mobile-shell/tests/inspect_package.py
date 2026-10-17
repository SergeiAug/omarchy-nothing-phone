#!/usr/bin/python3
# SPDX-License-Identifier: MIT
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile

base=Path(__file__).resolve().parents[1]
archive=Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='spacewar-archive-') as temp:
    root=Path(temp)
    subprocess.run(['bsdtar','-xf',str(archive),'-C',str(root)],check=True)
    info=(root/'.PKGINFO').read_text()
    assert 'arch = any\n' in info and 'conflict = nothing-spacewar-mobile-ui\n' in info
    assert '\nreplaces = ' not in info
    assert 'depend = omarchy-osk-spacewar\n' in info
    assert not any(word in info for word in ['squeekboard','omamobile-omarchy','fingerprint'])
    assert (root/'.INSTALL').read_bytes() == (base/'mobile-shell.install').read_bytes()
    assert 'pkgver = 0.3.3-1\n' in info
    share=root/'usr/share/nothing-spacewar/mobile-shell'
    assert (share/'phone-device.lua').read_bytes() == (base/'phone-device.lua').read_bytes()
    for folder in ['plugins','owl-widgets']:
        for file in (base/folder).rglob('*'):
            if file.is_file() and '__pycache__' not in file.parts:
                staged=share/file.relative_to(base)
                assert staged.read_bytes()==file.read_bytes(),str(file)
    assert (share/'widget-template/manifest.json').is_file()
    assert (share/'widget-examples').is_dir()
    assert (root/'usr/bin/omamobile-bt-agent').is_file()
    assert (root/'usr/bin/spacewar-shell-torch').read_bytes() == (base/'bin/spacewar-shell-torch').read_bytes()
    assert (root/'usr/lib/udev/rules.d/90-spacewar-torch.rules').read_bytes() == (base/'90-spacewar-torch.rules').read_bytes()
    assert not list(root.glob('etc/pam.d/*'))
    assert not list(root.glob('usr/lib/hyprgrass/*'))
    assert not list(share.rglob('Navigation.qml'))
    for name in ['spacewar-shell-setup','spacewar-shell-geometry','spacewar-shell-back']:
        assert (root/'usr/bin'/name).stat().st_mode & 0o111
        assert (root/'usr/bin'/name).read_bytes()==(base/name).read_bytes()
print('PASS: real archive metadata, all plugin/widget bytes, executables and exclusions')
print(hashlib.sha256(archive.read_bytes()).hexdigest()+'  '+archive.name)
