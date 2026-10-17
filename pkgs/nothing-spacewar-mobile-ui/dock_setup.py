import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def prepare(root, state):
    upstream = Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy')) / 'shell/plugins/dock'
    expected = json.loads((root / 'dock-upstream.json').read_text())
    sources = {}
    for name, digest in expected.items():
        path = upstream / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f'dock drift from r7031: {path}; review/rebase before setup')
        sources[name] = path.read_bytes()
    destination = state / 'dock'
    if destination.exists():
        raise ValueError(f'dock cache already exists: {destination}; undo or review before setup')
    with tempfile.TemporaryDirectory(dir=state, prefix='.dock-') as temp:
        staging = Path(temp) / 'dock'
        staging.mkdir()
        for name, data in sources.items():
            (staging / name).write_bytes(data)
        subprocess.run(['patch', '--batch', '--fuzz=0', '-p0', '-i', str(root / 'dock-mobile.patch')], cwd=staging, check=True, capture_output=True)
        manifest = json.loads((staging / 'manifest.json').read_text())
        manifest.update(id='spacewar.dock', name='Spacewar mobile app grid')
        (staging / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        os.replace(staging, destination)
