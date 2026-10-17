#!/usr/bin/env python3
"""Verify the builder's mke2fs -d copy contract on a real unprivileged image."""
import os
from pathlib import Path
import re
import subprocess
import struct
import tempfile


def run(*args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as error:
        print(error.output)
        raise


with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[2]) as directory:
    work = Path(directory)
    root = work / 'root'
    root.mkdir()
    payload = root / 'payload'
    payload.write_bytes(b'spacewar\n')
    payload.chmod(0o750)
    os.link(payload, root / 'hardlink')
    (root / 'symlink').symlink_to('payload')
    os.setxattr(payload, 'user.spacewar', b'xattr-preserved')
    run('setfacl', '-m', f'u:{os.getuid()}:r--', str(payload))
    image = work / 'rootfs.img'
    with image.open('wb') as stream:
        stream.truncate(64 * 1024 * 1024)
    uuid = '12345678-1234-4234-8234-123456789abc'
    run('mkfs.ext4', '-F', '-U', uuid, '-L', 'spacewar-root', '-m', '0', '-d', str(root), str(image))
    run('e2fsck', '-fn', str(image))
    assert run('blkid', '-p', '-s', 'UUID', '-o', 'value', str(image)).strip() == uuid

    def debug(command):
        return run('debugfs', '-R', command, str(image))

    stat = debug('stat /payload')
    assert re.search(r'Mode:\s+0750', stat), stat
    assert re.search(rf'User:\s+{os.getuid()}\s+Group:\s+{os.getgid()}', stat), stat
    assert re.search(r'Links:\s+2', stat), stat
    assert re.search(r'Inode:\s+(\d+)', stat)[1] == re.search(r'Inode:\s+(\d+)', debug('stat /hardlink'))[1]
    assert 'Fast link dest: "payload"' in debug('stat /symlink')
    dumped = work / 'dumped'
    debug(f'dump /payload {dumped}')
    assert dumped.read_bytes() == payload.read_bytes()
    for attribute in ('user.spacewar', 'system.posix_acl_access'):
        value = work / attribute
        debug(f'ea_get -f {value} /payload {attribute}')
        actual, expected = value.read_bytes(), os.getxattr(payload, attribute)
        if attribute == 'system.posix_acl_access':
            def acl_entries(data):
                assert struct.unpack_from('<I', data)[0] == 2
                # Only named user/group entries have meaningful IDs; debugfs normalizes the other IDs.
                return [(tag, perm, uid if tag in (2, 8) else None)
                        for tag, perm, uid in struct.iter_unpack('<HHI', data[4:])]
            assert acl_entries(actual) == acl_entries(expected)
        else:
            assert actual == expected
    run('img2simg', str(image), str(work / 'sparse.img'))
    run('simg2img', str(work / 'sparse.img'), str(work / 'roundtrip.img'))
    assert image.read_bytes() == (work / 'roundtrip.img').read_bytes()
print('Real ext4: UUID, data, owner/group, mode, hardlinks, symlinks, xattr, ACL; sparse roundtrip: PASS')
