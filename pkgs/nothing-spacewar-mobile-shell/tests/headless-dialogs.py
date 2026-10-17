#!/usr/bin/python3
"""Native GTK/Qt input/render smoke tests on labwc; not a Hyprland policy test."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

BASE = Path(__file__).resolve().parents[1]
OUTPUT = Path(os.environ['QA_OUTPUT']).resolve()
OUTPUT.mkdir(parents=True, exist_ok=True)
GTK = '''import gi, os
from pathlib import Path
gi.require_version('Gtk','3.0')
from gi.repository import Gtk, GLib
parent=Gtk.Window(title='GTK application parent')
parent.set_default_size(516, 1080)
parent.add(Gtk.Label(label='GTK parent remains open'))
parent.show_all()
def show():
 dialog=Gtk.Dialog(title='GTK child dialog', transient_for=parent, modal=True)
 dialog.add_button('Cancel', Gtk.ResponseType.CANCEL)
 dialog.add_button('OK', Gtk.ResponseType.OK)
 dialog.get_content_area().add(Gtk.Label(label='GTK transient + modal\\nEscape closes only this dialog'))
 dialog.set_default_size(420,260)
 def response(*args):
  Path(os.environ['QA_RESULT']).write_text('closed')
  dialog.destroy()
  Gtk.main_quit()
 def key(w,e):
  if e.keyval == 65307:
   w.response(Gtk.ResponseType.CANCEL)
   return True
  return False
 dialog.connect('key-press-event', key)
 dialog.connect('response', response)
 dialog.show_all()
 return False
GLib.timeout_add(300,show)
Gtk.main()
'''
with tempfile.TemporaryDirectory(prefix='sw-dialogs-') as temp:
    root = Path(temp)
    runtime = root/'runtime'; runtime.mkdir(mode=0o700)
    config = root/'config'; config.mkdir()
    (config/'rc.xml').write_text('''<labwc_config><core><decoration>server</decoration></core>
<keyboard><default/></keyboard><windowRules><windowRule type="normal"><action name="Maximize"/></windowRule>
<windowRule type="dialog"><action name="AutoPlace" policy="center"/><action name="Focus"/></windowRule></windowRules>
</labwc_config>''')
    env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(config), XDG_CACHE_HOME=str(root/'cache'),
               XDG_RUNTIME_DIR=str(runtime), WAYLAND_DISPLAY='wayland-0', WLR_BACKENDS='headless',
               WLR_RENDERER='pixman', WLR_HEADLESS_OUTPUTS='1', QT_QPA_PLATFORM='wayland',
               GDK_BACKEND='wayland', GSETTINGS_BACKEND='memory', QT_QUICK_BACKEND='software')
    subprocess.run(['g++', '-fPIC', '-pie', str(BASE/'tests/dialog-fixture.cpp'), '-o', str(root/'qt-dialog')]
                   + subprocess.check_output(['pkg-config','--cflags','--libs','Qt6Widgets'],text=True).split(),check=True)
    children=[]
    def start(command, name):
        with (OUTPUT/(name+'.log')).open('w') as log:
            child=subprocess.Popen(command,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        children.append(child)
        return child
    try:
        start([os.environ['LABWC'],'-C',str(config)],'dialogs-labwc')
        for _ in range(100):
            if (runtime/'wayland-0').exists(): break
            time.sleep(.1)
        subprocess.run([os.environ['WLR_RANDR'],'--output','HEADLESS-1','--custom-mode','540x1200'],env=env,check=True)
        for name, command in [('gtk-parent-dialog',['python','-c',GTK]),
                              ('qt-parent-dialog',[str(root/'qt-dialog'),'dialog']),
                              ('top-level-float',[str(root/'qt-dialog')])]:
            result=root/(name+'.result'); env['QA_RESULT']=str(result)
            child=start(command,name)
            time.sleep(1.2)
            assert child.poll() is None, name
            subprocess.run(['grim',str(OUTPUT/(name+'.png'))],env=env,check=True)
            if name != 'top-level-float':
                subprocess.run(['wtype','-s','300','-k','Escape','-s','300'],env=env,check=True)
                child.wait(timeout=5)
                assert result.read_text()=='closed', name
            else:
                os.killpg(child.pid, signal.SIGTERM); child.wait(timeout=5)
        print('PASS: native GTK parent/modal, Qt parent/modal, top-level 875x600 request; Escape reaches both dialogs. labwc placement only.')
    finally:
        for child in reversed(children):
            if child.poll() is None: os.killpg(child.pid,signal.SIGTERM)
        for child in children: child.wait(timeout=5)
