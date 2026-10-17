#!/usr/bin/env python3
"""Exercise the actual mkbootimg with synthetic payloads; never accesses /boot."""
import gzip
import fnmatch
import os
import shlex
import shutil
import signal
import time
from pathlib import Path
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
script = root / 'pkgs/nothing-spacewar-boot/spacewar-mkbootimg'
info = root / 'pkgs/nothing-spacewar-boot/deviceinfo'

hook = (root / 'pkgs/nothing-spacewar-boot/99-spacewar-boot.hook').read_text()
triggers = []
for block in hook.split('[Trigger]')[1:]:
    values = {}
    for line in block.split('[Action]')[0].splitlines():
        if '=' in line:
            key, value = map(str.strip, line.split('=', 1))
            values.setdefault(key, []).append(value)
    triggers.append(values)

for operation in ('Install', 'Upgrade', 'Remove'):
    for path in ('usr/lib/initcpio/hooks/udev', 'usr/lib/initcpio/install/base',
                 'usr/lib/firmware/qcom/test.bin', 'usr/lib/modules/test/extramodules/',
                 'usr/src/test/dkms.conf', 'usr/lib/systemd/systemd',
                 'usr/lib/systemd/systemd-udevd', 'usr/bin/cryptsetup', 'usr/bin/lvm',
                 'usr/bin/mdadm', 'usr/bin/pdata_tools', 'usr/lib/libcryptsetup.so',
                 'usr/lib/libp11-kit.so', 'usr/lib/libpcsclite.so', 'usr/lib/modprobe.d/'):
        assert any(t['Type'] == ['Path'] and operation in t['Operation'] and
                   any(fnmatch.fnmatchcase(path, target) for target in t['Target'])
                   for t in triggers), (operation, path)
for operation in ('Install', 'Upgrade'):
    for kind, target in (('Path', 'usr/lib/modules/test/vmlinuz'),
                         ('Path', 'usr/bin/spacewar-mkbootimg'),
                         ('Path', 'etc/mkinitcpio.conf.d/spacewar.conf'),
                         ('Path', 'usr/share/nothing-spacewar/deviceinfo'),
                         ('Package', 'mkinitcpio'), ('Package', 'mkinitcpio-git')):
        assert any(t['Type'] == [kind] and operation in t['Operation'] and
                   any(fnmatch.fnmatchcase(target, pattern) for pattern in t['Target'])
                   for t in triggers), (operation, kind, target)
(root / '.work').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='bootimg-test-', dir=root / '.work') as tmp:
    work = Path(tmp)
    image = bytearray(128)
    struct.pack_into('<Q', image, 16, 256)
    image[56:60] = b'ARM\x64'
    (work / 'Image').write_bytes(image)
    (work / 'dtb').write_bytes(b'\xd0\x0d\xfe\xedtest-dtb')
    (work / 'ramdisk').write_bytes(b'test-initramfs')
    (work / 'cmdline').write_text('root=UUID=test-root rw rootwait\n')
    args = [str(script), '--image', str(work / 'Image'), '--dtb', str(work / 'dtb'),
            '--initramfs', str(work / 'ramdisk'), '--cmdline', str(work / 'cmdline'),
            '--deviceinfo', str(info), '--output', str(work / 'boot.img')]
    subprocess.run(args, check=True)
    boot = (work / 'boot.img').read_bytes()
    assert boot[:8] == b'ANDROID!'
    ksize, kaddr, rsize, raddr, ssize, saddr, tags, page, version = struct.unpack_from('<9I', boot, 8)
    assert (kaddr, raddr, saddr, tags, page, version) == (0x8000, 0x1000000, 0, 0x100, 4096, 2)
    assert ssize == 0 and rsize == len(b'test-initramfs')
    assert boot[64:64 + 512].split(b'\0')[0] == b'root=UUID=test-root rw rootwait'
    dtb_size, dtb_addr = struct.unpack_from('<IQ', boot, 1648)
    assert dtb_addr == 0x1f00000
    dtb = (work / 'dtb').read_bytes()
    assert dtb_size == len(dtb)
    payload = boot[page:page + ksize]
    assert payload.endswith(dtb)
    assert gzip.decompress(payload[:-len(dtb)]) == bytes(image) + bytes(128)
    align = lambda n: (n + page - 1) // page * page
    ramdisk_start = page + align(ksize)
    assert boot[ramdisk_start:ramdisk_start + rsize] == b'test-initramfs'
    dtb_start = ramdisk_start + align(rsize)
    assert boot[dtb_start:dtb_start + dtb_size] == dtb
    unpacked = work / 'unpacked'
    subprocess.run(['unpack_bootimg', '--boot_img', str(work / 'boot.img'),
                    '--out', str(unpacked)], check=True, stdout=subprocess.DEVNULL)
    assert (unpacked / 'kernel').read_bytes() == payload
    assert (unpacked / 'dtb').read_bytes() == dtb
    tools = work / 'bin'
    tools.mkdir()
    events = work / 'events'
    env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}", EVENTS=str(events))
    for name in ('sync', 'mv'):
        executable = shutil.which(name)
        (tools / name).write_text(
            '#!/bin/bash\nset -eu\n'
            f'printf "%s\\n" "{name} $*" >> "$EVENTS"\n'
            f'if [[ {name} == sync ]] && [[ ${{FAIL_SYNC:-}} == file && $1 != -f || '
            '${FAIL_SYNC:-} == directory && $1 == -f ]]; then exit 73; fi\n'
            f'exec {shlex.quote(executable)} "$@"\n')
        (tools / name).chmod(0o755)
    subprocess.run(args, check=True, env=env)
    calls = events.read_text().splitlines()
    assert len(calls) == 3, calls
    assert calls[0].startswith('sync -- '), calls
    temporary = calls[0].removeprefix('sync -- ')
    assert Path(temporary).parent.parent == work and Path(temporary).name == 'boot.img'
    assert calls[1] == f'mv -f -- {temporary} {work / "boot.img"}'
    assert calls[2] == f'sync -f -- {work}', calls
    (work / 'ramdisk').write_bytes(b'next-initramfs')
    for failure in ('file', 'directory'):
        events.write_text('')
        result = subprocess.run(args, env=dict(env, FAIL_SYNC=failure), capture_output=True)
        assert result.returncode != 0 and b'Created' not in result.stdout
        calls = events.read_text().splitlines()
        assert len(calls) == (1 if failure == 'file' else 3), calls
        result_boot = (work / 'boot.img').read_bytes()
        if failure == 'file':
            assert result_boot == boot
        else:
            assert result_boot[ramdisk_start:ramdisk_start + rsize] == b'next-initramfs'
        assert not list(work.glob('.spacewar-mkbootimg.*'))
    (work / 'ramdisk').write_bytes(b'test-initramfs')
    subprocess.run(args, check=True)
    assert (work / 'boot.img').read_bytes() == boot
    mkbootimg = tools / 'mkbootimg'
    mkbootimg.write_text('#!/bin/bash\nkill -KILL "$PPID"\nexit 73\n')
    mkbootimg.chmod(0o755)
    assert subprocess.run(args, env=env, capture_output=True).returncode == -signal.SIGKILL
    stale = list(work.glob('.spacewar-mkbootimg.*'))
    assert len(stale) == 1 and stale[0].is_dir()
    assert (work / 'boot.img').read_bytes() == boot
    elsewhere = work / 'elsewhere'
    elsewhere.mkdir()
    outside = elsewhere / '.spacewar-mkbootimg.OLD123'
    outside.mkdir()
    (outside / 'keep').write_text('keep')
    link = work / '.spacewar-mkbootimg.LINK01'
    link.symlink_to(outside, target_is_directory=True)
    unrelated = work / '.spacewar-mkbootimg.keep'
    unrelated.mkdir()
    regular = work / '.spacewar-mkbootimg.FILE01'
    regular.write_text('keep')
    mkbootimg.unlink()
    for _ in range(2):
        subprocess.run(args, env=env, check=True)
        assert not stale[0].exists()
        assert link.is_symlink() and (outside / 'keep').read_text() == 'keep'
        assert unrelated.is_dir() and regular.read_text() == 'keep'
        assert (work / 'boot.img').read_bytes() == boot
    link.unlink()
    regular.unlink()
    unrelated.rmdir()

    ready = work / 'ready'
    gate = work / 'gate'
    os.mkfifo(gate)
    mkbootimg.write_text(
        '#!/bin/bash\nset -eu\n'
        'if [[ -n ${HOLD:-} ]]; then\n'
        f'  touch {shlex.quote(str(ready))}\n'
        f'  read -r _ < {shlex.quote(str(gate))}\n'
        'fi\n'
        f'exec {shlex.quote(shutil.which("mkbootimg"))} "$@"\n')
    mkbootimg.chmod(0o755)
    with subprocess.Popen(args, env=dict(env, HOLD='1'), start_new_session=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE) as first:
        second = None
        try:
            deadline = time.monotonic() + 10
            while not ready.exists():
                assert first.poll() is None, first.communicate()
                assert time.monotonic() < deadline, 'mkbootimg did not start'
                time.sleep(0.01)
            active = list(work.glob('.spacewar-mkbootimg.*'))
            assert len(active) == 1
            second = subprocess.Popen(args, env=env, start_new_session=True,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                second.communicate(timeout=0.3)
            except subprocess.TimeoutExpired:
                pass
            else:
                raise AssertionError('parallel build did not wait for the active build')
            assert active[0].is_dir()
            with gate.open('w') as stream:
                stream.write('continue\n')
            first.communicate(timeout=10)
            second.communicate(timeout=10)
            assert first.returncode == second.returncode == 0
        finally:
            for process in (first, second):
                if process is not None and process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.communicate()
    assert (work / 'boot.img').read_bytes() == boot
    assert not list(work.glob('.spacewar-mkbootimg.*'))
    for invalid in ('', 'quiet\n', 'root=UUID=x\nquiet\n'):
        (work / 'cmdline').write_text(invalid)
        assert subprocess.run(args, capture_output=True).returncode != 0
        assert (work / 'boot.img').read_bytes() == boot
    (work / 'cmdline').write_text('root=UUID=test-root rw\n')
    (work / 'Image').write_bytes(b'not an ARM64 image')
    assert subprocess.run(args, capture_output=True).returncode != 0
    assert (work / 'boot.img').read_bytes() == boot
    assert not list(work.glob('.spacewar-mkbootimg.*'))
print('boot.img payload, hook triggers, sync failures, SIGKILL recovery and concurrent builds: PASS')
