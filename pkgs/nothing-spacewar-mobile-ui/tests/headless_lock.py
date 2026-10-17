#!/usr/bin/python3
"""Run under dbus-run-session; use extracted packages, never the active desktop."""
import shutil
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
(OUTPUT / 'commands.log').write_text('')
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
    host_root = root / 'host'
    host_root.mkdir()
    for name in ['shell', 'bin']:
        (host_root / name).symlink_to(BASE / name)
    if os.environ.get('QA_ENGLISH_CATALOG'):
        catalog = host_root / 'default/i18n/en/shell.json'
        catalog.parent.mkdir(parents=True)
        shutil.copy2(os.environ['QA_ENGLISH_CATALOG'], catalog)
    env = dict(os.environ, HOME=str(root / 'home'), XDG_CONFIG_HOME=str(root / 'home/.config'),
               XDG_STATE_HOME=str(root / 'state'), XDG_CACHE_HOME=str(root / 'cache'), XDG_DATA_HOME=str(root / 'data'),
               XDG_RUNTIME_DIR=str(root / 'r'), WAYLAND_DISPLAY='wayland-0',
               HYPRLAND_INSTANCE_SIGNATURE='spacewar-qa-no-hyprland',
               WLR_BACKENDS='headless', WLR_RENDERER='pixman', WLR_HEADLESS_OUTPUTS='1',
               QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software',
               OMARCHY_PATH=str(host_root), PATH=str(root / 'bin') + ':' + os.environ['PATH'])
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
    package = root / 'package'
    shutil.copytree(PACKAGE, package, symlinks=True)
    service = package / 'plugins/spacewar.lock/Service.qml'
    source = service.read_text().replace('import QtQuick\n', 'import QtQuick\nimport QtTest\n', 1)
    source = source.replace('/usr/share/nothing-spacewar/mobile/lock_setup.py', str(package / 'lock_setup.py'))
    # QA-only mock replaces PAM, never the session-lock protocol or its surfaces.
    source = source.replace('  PamContext {\n    id: passwordPam\n    config: "omarchy-lock-password"\n    user: root.userName', '''  Item {
    id: passwordPam
    property bool active: false
    property bool responseRequired: false
    signal completed(int result)
    signal error(int code)
    signal pamMessage(string message)
    function start() { active = true; responseRequired = true; return true }
    function abort() { active = false; responseRequired = false }
    function respond(value) {
      responseRequired = false
      resultTimer.correct = value === "2468"
      resultTimer.start()
    }
    Timer {
      id: resultTimer
      property bool correct: false
      interval: 80
      onTriggered: {
        passwordPam.active = false
        passwordPam.completed(correct ? PamResult.Success : PamResult.Success + 1)
      }
    }''')
    source = source.replace('path: "/etc/pam.d/omarchy-lock-password"', 'path: "' + str(root / 'mock-pam') + '"')
    (root / 'mock-pam').write_text('QA mock only')
    source = source.replace('  property bool powerHeld:', '  property var qaView: null\n  TestCase { id: qaTouch; when: false }\n  property bool powerHeld:')
    source = source.replace('        id: lockView', '        id: lockView\n        Component.onCompleted: root.qaView = this')
    source = source.replace('    function isLocked(): string', '''    function qaFind(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; item.children && i < item.children.length; i++) {
        var found = qaFind(item.children[i], name)
        if (found) return found
      }
      return null
    }
    function qaKey(key: string): string {
      if (!root.qaView) return "no-view"
      var button = qaFind(root.qaView, "pinKey" + key)
      if (!button || button.width < 56 || button.height < 56) return "invalid-target"
      qaTouch.mouseClick(button, button.width / 2, button.height / 2)
      return "ok"
    }
    function qaState(): string {
      return JSON.stringify({length: root.enteredPassword.length, failures: root.failedAttempts,
        message: root.failureMessage, busy: root.authenticatingPassword,
        blank: root.displaysBlank, pendingMenu: root.powerMenuPending,
        view: !!root.qaView})
    }
    function isLocked(): string''')
    service.write_text(source)
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
                f'm=SourceFileLoader("setup", {str(package / "spacewar-mobile-setup")!r}).load_module(); '
                f'm.ROOT=Path({str(package)!r}); sys.argv=["setup"]' + ('+["--undo"]' if undo else '+["--lock"]') + '; m.main()')
        subprocess.run(['python3', '-c', code], env=env, check=True)
    (root / 'bin').mkdir()
    for name in ['omarchy-system-wake', 'omarchy-brightness-keyboard', 'omarchy-brightness-display', 'omarchy-menu', 'omarchy-lock-recover']:
        command = root / 'bin' / name
        command.write_text('#!/bin/sh\nprintf "%s\\n" "' + name + ' $*" >> "' + str(OUTPUT / 'commands.log') + '"\n')
        command.chmod(0o755)
    hyprctl = root / 'bin/hyprctl'
    dpms = root / 'dpms.json'
    dpms.write_text('[{"name":"DSI-1","dpmsStatus":true}]')
    hyprctl.write_text('#!/bin/sh\ncat "' + str(dpms) + '"\n')
    hyprctl.chmod(0o755)
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
    def lock_ipc(*args):
        return subprocess.check_output(['quickshell', 'ipc', '-p', str(BASE / 'shell'), 'call', 'lock', *args], env=env, text=True, stderr=subprocess.DEVNULL).strip()
    def status(): return json.loads(lock_ipc('status'))
    def state(): return json.loads(lock_ipc('qaState'))
    def keys(value):
        for digit in value: assert lock_ipc('qaKey', digit) == 'ok'
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
        wait_for(lambda: any(p['id'] == 'spacewar.lock' and p['enabled'] for p in json.loads(ipc('listPlugins'))))
        wait_for(lambda: status()['passwordPam'] and status()['upstreamVerified'])
        assert lock_ipc('lock') == 'ok'
        wait_for(lambda: status()['secure'] and state()['view'])
        capture('lock-v1')
        keys('0123456789')
        assert state()['length'] == 10
        keys('⌫' * 10)
        keys('19⌫')
        assert state()['length'] == 1
        keys('↵')
        wait_for(lambda: state()['failures'] == 1)
        assert status()['secure'] and state()['message']
        keys('2468↵')
        wait_for(lambda: not status()['locked'])
        for _ in range(3):
            assert lock_ipc('lock') == 'ok'
            wait_for(lambda: status()['secure'])
            keys('2468↵')
            wait_for(lambda: not status()['locked'])
        # Press autorepeat is ignored; >=600ms fires once without a release.
        assert lock_ipc('powerPress') == 'ok'
        assert lock_ipc('powerPress') == 'ok'
        time.sleep(0.7)
        lock_ipc('powerRelease')
        commands = (OUTPUT / 'commands.log').read_text()
        assert commands.count('omarchy-menu toggle system') == 1, commands
        assert not status()['locked']
        lock_ipc('powerPress')
        time.sleep(0.1)
        lock_ipc('powerRelease')
        wait_for(lambda: status()['secure'] and state()['blank'])
        dpms.write_text('[{"name":"DSI-1","dpmsStatus":false}]')
        lock_ipc('powerPress')
        time.sleep(0.1)
        lock_ipc('powerRelease')
        wait_for(lambda: status()['secure'] and not state()['blank'])
        lock_ipc('powerPress')
        time.sleep(0.7)
        lock_ipc('powerRelease')
        assert status()['secure'] and state()['pendingMenu']
        keys('2468↵')
        wait_for(lambda: not status()['locked'])
        wait_for(lambda: (OUTPUT / 'commands.log').read_text().count('omarchy-menu toggle system') == 2)
        lock_ipc('lock')
        wait_for(lambda: status()['secure'])
        recovery_env = dict(env)
        recovery_env.pop('WAYLAND_DISPLAY', None)
        assert subprocess.check_output([str(BASE / 'bin/omarchy-shell'), 'lock', 'unlock'], env=recovery_env, text=True).strip() == 'ok'
        wait_for(lambda: not status()['locked'])
        assert not state()['pendingMenu']
        setup(undo=True)
        ipc('rescanPlugins')
        time.sleep(1)
        assert json.loads((config / 'shell.json').read_text()) == original
        errors = [line for line in (OUTPUT / 'host.log').read_text().splitlines() if 'TypeError' in line or 'ReferenceError' in line]
        assert not errors, '\n'.join(errors)
        print('PASS: r7031 540x1200 secure lock, mock PAM wrong/correct PIN, erase, 3 lock/unlock cycles, short/long power, SSH recovery IPC, live undo; 0 TypeError/ReferenceError')

    finally:
        for process in reversed(processes):
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
        for process in processes:
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
