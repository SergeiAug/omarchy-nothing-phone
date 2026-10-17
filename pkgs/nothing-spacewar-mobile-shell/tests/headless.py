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
    artifact = PACKAGE / 'pkg/nothing-spacewar-mobile-shell/usr/share/nothing-spacewar/mobile-shell'
    installed = root / 'installed/mobile-shell'
    installed.parent.mkdir()
    installed.symlink_to(artifact, target_is_directory=True)
    osk = installed.parent / 'osk'
    osk.mkdir()
    (osk/'manifest.json').write_text(json.dumps(dict(schemaVersion=1,id='io.github.yeutterg.onscreen-keyboard',name='QA keyboard stub',version='1.0.0',kinds=['service'],entryPoints=dict(service='Service.qml'))))
    (osk/'Service.qml').write_text('import QtQuick\nimport Quickshell.Io\nItem {\n id: root\n property var shell:null; property var manifest:null\n property bool shown:false\n IpcHandler {\n  target: "onscreen-keyboard"\n  function status(): string { return JSON.stringify({shown:root.shown}) }\n  function show(): string { root.shown=true; return "ok" }\n  function hide(): string { root.shown=false; return "ok" }\n  function toggle(): string { root.shown=!root.shown; return "ok" }\n }\n}\n')
    env.update(OMAMOBILE_OWL_STORE=str(installed/'owl-widgets'), OMAMOBILE_SHELL_SHARE=str(installed),
               PATH=env['PATH']+':'+str(PACKAGE/'pkg/nothing-spacewar-mobile-shell/usr/bin'))
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
                        center=[],
                        right=[dict(id='omarchy.' + name) for name in ['network', 'bluetooth', 'audio', 'power']])),
                    disabledPlugins=disabled)
    (config / 'shell.json').write_text(json.dumps(original))
    def setup(undo=False):
        subprocess.run(['python3', '-c', "import runpy; from pathlib import Path; m=runpy.run_path(" + repr(str(PACKAGE / 'spacewar-shell-setup')) + " ); m['configure'](Path(" + repr(env['XDG_CONFIG_HOME']) + "), Path(" + repr(env['XDG_STATE_HOME']) + ")/'spacewar-shell', Path(" + repr(str(installed)) + "), " + repr(undo) + ")"], env=env, check=True)
    (root / 'bin').mkdir()
    (OUTPUT/'ipc.log').write_text('')
    (root / 'bin/omarchy-shell').write_text('#!/bin/sh\necho "$@" >> '+str(OUTPUT/'ipc.log')+'\nexec quickshell ipc -p "' + str(BASE / 'shell') + '" call -- "$@"\n')
    (root / 'bin/omarchy-shell').chmod(0o755)
    context_file = root/'context.json'
    context_file.write_text('{}')
    probe_script = '#!/usr/bin/python3\nimport json,subprocess\nv=json.loads(subprocess.check_output(["omarchy-shell","onscreen-keyboard","status"],text=True))\nv.update(ready=True,top=811)\nv.update(json.load(open(' + repr(str(context_file)) + ')))\nprint(json.dumps(v))\n'
    (root / 'bin/spacewar-shell-geometry').write_text(probe_script)
    (root / 'bin/spacewar-shell-geometry').chmod(0o755)
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
    protocol = PACKAGE/'tests/virtual-pointer.xml'
    subprocess.run(['wayland-scanner','client-header',str(protocol),str(root/'virtual-pointer-client.h')],check=True)
    subprocess.run(['wayland-scanner','private-code',str(protocol),str(root/'virtual-pointer.c')],check=True)
    subprocess.run(['cc','-I'+str(root),str(PACKAGE/'tests/pointer.c'),str(root/'virtual-pointer.c'),'-lwayland-client','-o',str(root/'pointer')],check=True)
    def click(x,y):
        subprocess.run([str(root/'pointer'),str(x),str(y)],env=env,check=True)
    def gesture(*args):
        return json.loads(subprocess.check_output(['quickshell','ipc','-p',str(BASE/'shell'),'call','spacewar.gestures',*args],env=env,text=True))
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
        wait_for(lambda: any(p['id'] == 'omamobile.bar' and p['enabled'] for p in json.loads(ipc('listPlugins'))))
        capture('step2-bar')
        marker = root/'cutout-marker'
        marker.mkdir()
        (marker/'shell.qml').write_text('import QtQuick\nimport Quickshell\nimport Quickshell.Wayland\nimport "' + str(artifact/'plugins/spacewar.runtime/Device.js') + '" as Device\n' + 'ShellRoot {\n PanelWindow {\n  anchors {top:true;bottom:true;left:true;right:true}\n  exclusionMode:ExclusionMode.Ignore; color:"transparent"\n  WlrLayershell.layer:WlrLayer.Overlay\n  WlrLayershell.keyboardFocus:WlrKeyboardFocus.None\n  mask:Region {width:0;height:0}\n  Rectangle {x:Device.cutout.x;y:Device.cutout.y;width:Device.cutout.diameter;height:width;radius:width/2;color:"#4400ffff";border.color:"#ff00ff";border.width:1}\n  Rectangle {y:Device.safeTop;width:parent.width;height:1;color:"#ff00ff"}\n  Text {x:Device.safeLeft;y:Device.safeTop+8;color:"#ff00ff";text:"Cutout / scale 2; safeLeft="+Device.safeLeft+", safeTop="+Device.safeTop;font.pixelSize:12}\n }\n}\n')
        marker_proc=start(['quickshell','--no-color','-p',str(marker)],env,'cutout-marker')
        capture('bar-cutout')
        os.killpg(marker_proc.pid,signal.SIGTERM); marker_proc.wait(timeout=3)
        def osk_status():
            return json.loads(subprocess.check_output(['omarchy-shell','onscreen-keyboard','status'],env=env,text=True))['shown']
        def context(**value):
            context_file.write_text(json.dumps(value))
        # A migration terminal mapped outside the launcher still gets OSK.
        context(focus={'address':'0x123','class':'org.omarchy.terminal'}, occupied=True)
        wait_for(osk_status)
        wait_for(lambda: not json.loads(ipc('call','omamobile.home','state',''))['visible'])
        ipc('summon','omamobile.quicksettings','{}')
        wait_for(lambda: not osk_status())
        capture('fix1-shade-terminal')
        ipc('hide','omamobile.quicksettings')
        wait_for(osk_status)
        # Manual bar button hides/shows without opening the shade.
        def tap_keyboard():
            ipc('call','omamobile.quicksettings','dragTest','{"phase":"begin","x":270,"y":20}')
            ipc('call','omamobile.quicksettings','dragTest','{"phase":"end"}')
        tap_keyboard(); wait_for(lambda: not osk_status())
        time.sleep(0.4); assert not osk_status()
        ipc('summon','omamobile.quicksettings','{}'); time.sleep(0.3)
        assert not osk_status()
        ipc('hide','omamobile.quicksettings'); time.sleep(0.5)
        assert not osk_status()
        tap_keyboard(); wait_for(osk_status)
        tap_keyboard(); wait_for(lambda: not osk_status())
        ipc('summon','omamobile.quicksettings','{}')
        wait_for(lambda: any(t['id']=='keyboard' and t['available'] and not t['enabled'] for t in json.loads(ipc('call','omamobile.quicksettings','tiles',''))))
        ipc('call','omamobile.quicksettings','toggleTile','keyboard')
        wait_for(osk_status)
        context(focus={'address':'0x456','class':'org.gnome.Nautilus'}, occupied=True)
        wait_for(lambda: not osk_status())
        context(occupied=False)
        wait_for(lambda: json.loads(ipc('call','omamobile.home','state',''))['visible'])
        wait_for(lambda: json.loads(subprocess.check_output(['quickshell','ipc','-p',str(BASE/'shell'),'call','spacewar.gestures','snapshot'],env=env,text=True))['ready'])
        for phase,y in [('begin',10),('move',160)]:
            state=json.loads(ipc('call','omamobile.quicksettings','dragTest',json.dumps(dict(phase=phase,x=270,y=y))))
        assert state['dragging'] and 0 < state['reveal'] < 1, state
        capture('step2-shade-drag')
        ipc('call','omamobile.quicksettings','dragTest','{"phase":"cancel"}')
        wait_for(lambda: not json.loads(ipc('call','omamobile.quicksettings','state',''))['opened'])
        ipc('summon','omamobile.quicksettings','{}')
        wait_for(lambda: json.loads(ipc('call','omamobile.quicksettings','state',''))['reveal'] > 0.99)
        capture('step2-shade')
        ipc('hide','omamobile.quicksettings')
        fixture_proc=start(['quickshell', '--no-color', '-p', str(fixture)], env, 'fixture')
        # Start in the expanded 30px band, outside the former 16px band.
        gesture('feed','{"phase":"begin","x":270,"y":1175}')
        gesture('feed','{"phase":"move","x":270,"y":935}')
        capture('fix3-recents-preview')
        gesture('feed','{"phase":"cancel"}')
        gesture('feed','{"phase":"begin","x":270,"y":1175}')
        for i in range(1,13):
            time.sleep(.09)
            gesture('feed',json.dumps(dict(phase='move',x=270,y=1175-i*40)))
        gesture('feed','{"phase":"end"}')
        wait_for(lambda: json.loads(ipc('call','omamobile.switcher','snapshot',''))['opened'])
        capture('step2-recents')
        gesture_logs=[json.loads(line.split('spacewar-gesture ',1)[1]) for line in (OUTPUT/'host.log').read_text().splitlines() if 'spacewar-gesture ' in line]
        assert any(e['result']=='recents' and not e['held'] for e in gesture_logs), gesture_logs
        wait_for(lambda: json.loads(ipc('call','omamobile.switcher','snapshot',''))['windows']==3)
        # Real Wayland pointer clicks on the visible × and Закрыть все.
        click(443,199)
        wait_for(lambda: json.loads(ipc('call','omamobile.switcher','snapshot',''))['windows']==2)
        capture('fix3-close-one')
        click(204,1132)
        wait_for(lambda: json.loads(ipc('call','omamobile.switcher','snapshot',''))['windows']==0)
        ipc('hide','omamobile.switcher')
        os.killpg(fixture_proc.pid,signal.SIGTERM)
        fixture_proc.wait(timeout=3)
        assert gesture('feed','{"phase":"begin","x":270,"y":1195}')['dragging']
        assert gesture('feed','{"phase":"move","x":270,"y":1050}')['dragging']
        canceled=gesture('feed','{"phase":"cancel"}')
        assert not canceled['dragging'] and canceled['owner']=='',canceled
        # The home drawer stays above the bottom band and receives its tap.
        click(270,1146)
        wait_for(lambda: json.loads(ipc('call','omamobile.launcher','state',''))['opened'])
        ipc('hide','omamobile.launcher')
        log_options=config/'spacewar-shell.json'
        log_options.write_text('{"gestureLogging":false}')
        time.sleep(.5)
        log_before=(OUTPUT/'host.log').read_text().count('spacewar-gesture ')
        gesture('feed','{"phase":"begin","x":270,"y":1175}')
        gesture('feed','{"phase":"cancel"}')
        time.sleep(.2)
        assert (OUTPUT/'host.log').read_text().count('spacewar-gesture ')==log_before
        log_options.write_text('{"gestureLogging":true}')
        time.sleep(.5)
        gesture('feed','{"phase":"begin","x":270,"y":1175}')
        gesture('feed','{"phase":"cancel"}')
        time.sleep(.2)
        assert (OUTPUT/'host.log').read_text().count('spacewar-gesture ')>log_before
        wait_for(lambda: json.loads(ipc('call','omamobile.home','state',''))['loaded'])
        widgets=json.loads(ipc('call','omamobile.home','builtinStatus',''))
        assert all(w['state']=='ok' for w in widgets),widgets
        capture('step3-home')
        ipc('summon','omamobile.launcher','{}')
        wait_for(lambda: json.loads(ipc('call','omamobile.launcher','state',''))['apps']>0)
        drawer=json.loads(ipc('call','omamobile.launcher','state',''))
        assert drawer['columns']==4 and drawer['contentHeight']>drawer['viewport'],drawer
        capture('step3-drawer')
        ipc('call','omamobile.launcher','scrollToEnd','')
        assert json.loads(ipc('call','omamobile.launcher','state',''))['contentY']>0
        capture('step3-drawer-scrolled')
        ipc('call','omamobile.launcher','search','Terminal')
        capture('step3-search')
        ipc('hide','omamobile.launcher')
        # A dynamic keyboard layer at a deliberately non-default height.
        probe=root/'bin/spacewar-shell-geometry'
        probe.write_text('#!/bin/sh\necho \'{"ready":true,"shown":true,"top":811}\'\n')
        wait_for(lambda: gesture('snapshot')['available']==811)
        probe.write_text('#!/bin/sh\necho \'{"ready":true,"shown":false,"top":0}\'\n')
        wait_for(lambda: gesture('snapshot')['available']==1200)
        os.killpg(host.pid,signal.SIGTERM); host.wait(timeout=3)
        host=start(['quickshell','--no-color','-p',str(BASE/'shell')],env,'host-restart')
        wait_for(lambda: ipc('ping'))
        wait_for(lambda: gesture('snapshot')['ready'])
        restarted=gesture('snapshot')
        assert not restarted['dragging'] and restarted['owner']=='',restarted
        setup(undo=True)
        ipc('rescanPlugins')
        assert json.loads((config/'shell.json').read_text())==original
        errors = [line for log in ['host.log','host-restart.log'] for line in (OUTPUT / log).read_text().splitlines() if 'TypeError' in line or 'ReferenceError' in line or 'Failed to load' in line]
        assert not errors, '\n'.join(errors)
        print('PASS: real × / Закрыть все clicks, home drawer separation, long slow recents release + preview, live gesture log switch; r7031 540x1200; terminal focus OSK; shade hide/restore; manual bar toggle; occupied home unmapped; drawer, gestures, restart, undo; no QML runtime errors')

    finally:
        for process in reversed(processes):
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
        for process in processes:
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
