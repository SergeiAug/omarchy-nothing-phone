#!/usr/bin/python3
"""Run under dbus-run-session; use extracted packages, never the active desktop."""
import json
import os
from pathlib import Path
import signal
import socket
import threading
import subprocess
import tempfile
import time

BASE = Path(os.environ['OMARCHY_QA_ROOT']).resolve()
PACKAGE = Path(os.environ['MOBILE_QA_ROOT']).resolve()
LABWC = os.environ.get('LABWC', 'labwc')
RANDR = os.environ.get('WLR_RANDR', 'wlr-randr')
OUTPUT = Path(os.environ.get('QA_OUTPUT', '/tmp/spacewar-mobile-qa'))
OUTPUT.mkdir(parents=True, exist_ok=True)
processes = []


def start(argv, env, name):
    log = (OUTPUT / (name + '.log')).open('w')
    child = subprocess.Popen(argv, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    log.close()
    processes.append(child)
    return child


def wait_for(fn):
    deadline = time.monotonic() + 15
    while True:
        try:
            result = fn()
            if result:
                return result
        except (subprocess.SubprocessError, ValueError):
            pass
        if time.monotonic() > deadline:
            raise RuntimeError('QA timeout; inspect logs in ' + str(OUTPUT))
        time.sleep(0.1)


with tempfile.TemporaryDirectory(prefix='swq-', dir='/tmp') as temp:
    root = Path(temp)
    env = dict(os.environ, HOME=str(root / 'home'), XDG_CONFIG_HOME=str(root / 'home/.config'),
               XDG_STATE_HOME=str(root / 'state'), XDG_CACHE_HOME=str(root / 'cache'), XDG_DATA_HOME=str(root / 'data'),
               XDG_RUNTIME_DIR=str(root / 'r'), WAYLAND_DISPLAY='wayland-0',
               HYPRLAND_INSTANCE_SIGNATURE='spacewar-qa-no-hyprland',
               WLR_BACKENDS='headless', WLR_RENDERER='pixman', WLR_HEADLESS_OUTPUTS='1',
               QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software',
               OMARCHY_PATH=str(BASE), PATH=str(root / 'bin') + ':' + os.environ['PATH'])
    Path(env['XDG_RUNTIME_DIR']).mkdir(mode=0o700)
    # OverlayWindow requires Hyprland monitor metadata even on a labwc surface.
    hypr = Path(env['XDG_RUNTIME_DIR']) / 'hypr' / env['HYPRLAND_INSTANCE_SIGNATURE']
    hypr.mkdir(parents=True)
    monitor = dict(id=0, name='HEADLESS-1', description='QA headless', x=0, y=0,
                   width=540, height=1200, scale=1, transform=0, focused=True,
                   refreshRate=60, reserved=[0, 26, 0, 0], activeWorkspace=dict(id=1, name='1'),
                   specialWorkspace=dict(id=0, name=''), dpmsStatus=True, disabled=False)
    def serve_hyprland():
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(hypr / '.socket.sock'))
        server.listen()
        while True:
            connection, _ = server.accept()
            request = connection.recv(8192).decode()
            if request.endswith('/monitors') or request.endswith('/monitors all'):
                reply = [monitor]
            elif request.endswith('/activeworkspace'):
                reply = dict(id=1, name='1', monitor='HEADLESS-1', monitorID=0, windows=0)
            elif request.endswith('/activewindow'):
                reply = {}
            else:
                reply = []
            with connection:
                connection.sendall(json.dumps(reply).encode())
    threading.Thread(target=serve_hyprland, daemon=True).start()
    config = Path(env['XDG_CONFIG_HOME']) / 'omarchy'
    (config / 'plugins').mkdir(parents=True)
    disabled = []
    for manifest in (BASE / 'shell/plugins').rglob('*manifest.json'):
        data = json.loads(manifest.read_text())
        if set(data.get('kinds', [])) & {'service', 'overlay'} and data['id'] != 'omarchy.dock':
            disabled.append(data['id'])
    original = dict(version=1, idle=dict(lock=0, screensaver=0),
                    bar=dict(position='top', layout=dict(
                        left=[dict(id='omarchy.spacer', size=44), dict(id='omarchy.clock', format='HH:mm')],
                        center=[dict(id='phone-close', type='command', text='✕', onClick='true'),
                                dict(id='phone-keyboard', type='command', text='⌨', onClick='true'),
                                dict(id='phone-layout', type='command', text='RU', onClick='true')],
                        right=[dict(id='omarchy.' + name) for name in ['network', 'bluetooth', 'audio', 'power']])),
                    disabledPlugins=disabled)
    (config / 'shell.json').write_text(json.dumps(original))
    def setup(undo=False):
        code = ('import sys; from pathlib import Path; from importlib.machinery import SourceFileLoader; '
                f'm=SourceFileLoader("setup", {str(PACKAGE / "spacewar-mobile-setup")!r}).load_module(); '
                f'm.ROOT=Path({str(PACKAGE)!r}); sys.argv=["setup"]' + ('+["--undo"]' if undo else '') + '; m.main()')
        subprocess.run(['python3', '-c', code], env=env, check=True)
    (root / 'bin').mkdir()
    helper = root / 'bin/spacewar-mobile'
    helper.write_text('#!/bin/sh\nif [ "$1" = shade-state ]; then\ncat <<\'JSON\'\n' + json.dumps(dict(layout='RU', keyboard=False, rotated=False, dnd=False, brightness=65, flashAvailable=False, flash=False)) + "\nJSON\nelse\nexit 99\nfi\n")
    helper.chmod(0o755)
    (root / 'labwc').mkdir()
    (root / 'labwc/rc.xml').write_text('<labwc_config/>')
    fixture = root / 'fixture'
    fixture.mkdir()
    (fixture / 'shell.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
  FloatingWindow { visible: true; title: "QA One"; color: "#884433"; Text { text: "QA One" } }
  FloatingWindow { visible: true; title: "QA Two"; color: "#338844"; Text { text: "QA Two" } }
  FloatingWindow { visible: true; title: "QA Three"; color: "#443388"; Text { text: "QA Three" } }
}
''')
    def ipc(*args):
        return subprocess.check_output(['quickshell', 'ipc', '-p', str(BASE / 'shell'), 'call', 'shell', *args], env=env, text=True, stderr=subprocess.DEVNULL).strip()
    def snapshot(name):
        return json.loads(ipc('call', 'spacewar.' + name, 'snapshot', ''))
    def capture(name):
        time.sleep(0.4)
        subprocess.run(['grim', str(OUTPUT / (name + '.png'))], env=env, check=True)
    try:
        start([LABWC, '-C', str(root / 'labwc')], env, 'labwc')
        wait_for(lambda: (Path(env['XDG_RUNTIME_DIR']) / 'wayland-0').exists())
        subprocess.run([RANDR, '--output', 'HEADLESS-1', '--custom-mode', '540x1200'], env=env, check=True)
        host = start(['quickshell', '--no-color', '-p', str(BASE / 'shell')], env, 'host')
        wait_for(lambda: ipc('ping'))
        setup()
        ipc('rescanPlugins')
        wait_for(lambda: len([p for p in json.loads(ipc('listPlugins')) if p['id'].startswith('spacewar.') and p['enabled']]) == 2)
        wait_for(lambda: len(json.loads(ipc('debugBarGeometry'))) == 6 and all(row['height'] == 26 for row in json.loads(ipc('debugBarGeometry'))))
        capture('statusbar')
        subprocess.run(['quickshell', 'ipc', '-p', str(BASE / 'shell'), 'call', 'omarchy.dock', 'apps'], env=env, check=True)
        capture('home')
        subprocess.run(['quickshell', 'ipc', '-p', str(BASE / 'shell'), 'call', 'omarchy.dock', 'apps'], env=env, check=True)
        assert ipc('summon', 'spacewar.shade', '{}') == 'ok'
        wait_for(lambda: snapshot('shade')['opened'] and abs(snapshot('shade')['offset']) < 0.1)
        wait_for(lambda: snapshot('shade')['state'].get('layout') == 'RU')
        assert 500 <= snapshot('shade')['height'] <= 650, snapshot('shade')
        capture('shade')
        for _ in range(3):
            ipc('hide', 'spacewar.shade')
            wait_for(lambda: not snapshot('shade')['opened'])
            assert ipc('summon', 'spacewar.shade', '{}') == 'ok'
            wait_for(lambda: snapshot('shade')['opened'] and abs(snapshot('shade')['offset']) < 0.1)
        ipc('hide', 'spacewar.shade')
        os.killpg(host.pid, signal.SIGTERM)
        host.wait(timeout=3)
        start(['quickshell', '--no-color', '-p', str(BASE / 'shell')], env, 'host-restart')
        wait_for(lambda: ipc('ping'))
        wait_for(lambda: snapshot('shade'))
        start(['quickshell', '--no-color', '-p', str(fixture)], env, 'fixture')
        wait_for(lambda: snapshot('switcher')['windows'] == 3)
        assert ipc('summon', 'spacewar.switcher', '{}') == 'ok'
        capture('switcher')
        assert ipc('call', 'spacewar.switcher', 'activateCard', '0') == 'ok'
        assert not snapshot('switcher')['opened']
        assert snapshot('switcher')['windows'] == 3
        assert ipc('call', 'spacewar.switcher', 'closeCard', '1') == 'ok'
        wait_for(lambda: snapshot('switcher')['windows'] == 2)
        for panel in ['network', 'bluetooth', 'audio', 'power']:
            assert ipc('summon', 'omarchy.' + panel, '{}') == 'ok'
            time.sleep(0.3)
            capture('stock-' + panel)
            ipc('hide', 'omarchy.' + panel)
        setup(undo=True)
        ipc('rescanPlugins')
        wait_for(lambda: any(row['id'] == 'phone-close' for row in json.loads(ipc('debugBarGeometry'))))
        time.sleep(1)
        assert json.loads((config / 'shell.json').read_text()) == original
        errors = [line for name in ['host', 'host-restart'] for line in (OUTPUT / (name + '.log')).read_text().splitlines() if 'TypeError' in line or 'ReferenceError' in line]
        assert not errors, '\n'.join(errors)
        print('PASS: r7031 stock bar, shade, dock apps, cards, stock panels, live setup/undo; 0 TypeError/ReferenceError')

    finally:
        for process in reversed(processes):
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
        for process in processes:
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
