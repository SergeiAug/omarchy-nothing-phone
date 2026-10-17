#!/usr/bin/python3
import importlib.machinery
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]
SETUP = Path(os.environ.get('MOBILE_SETUP', SOURCE / 'spacewar-mobile-setup'))


class SetupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config = self.home / '.config'
        self.shell = self.config / 'omarchy/shell.json'
        self.lua = self.config / 'hypr/hyprland.lua'
        self.shell.parent.mkdir(parents=True)
        self.lua.parent.mkdir(parents=True)
        self.original = '{"bar":{"position":"right","layout":{"left":[{"id":"omarchy.clock"}]}},"idle":{"lock":123},"plugins":[{"id":"user.test"}]}\n'
        self.shell.write_text(self.original)
        self.lua.write_text('-- original without newline')
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.config),
                        XDG_STATE_HOME=str(self.home / '.local/state'))
        self.package = self.home / 'mobile'
        osk = self.home / 'osk'
        osk.mkdir()
        (osk / 'manifest.json').write_text('{}')
        for ident in ['statusbar', 'shade', 'home', 'switcher', 'lock']:
            dest = self.package / 'plugins' / ('spacewar.' + ident)
            dest.mkdir(parents=True)
            (dest / 'manifest.json').write_text('{}')

    def lock_fixture(self):
        import shutil
        base = Path(os.environ.get('OMARCHY_QA_ROOT', '/usr/share/omarchy'))
        upstream = self.home / 'upstream/shell/plugins/lock'
        shutil.copytree(base / 'shell/plugins/lock', upstream)
        shutil.copy2(SETUP.parent / 'lock-upstream.json', self.package)
        self.env['OMARCHY_PATH'] = str(self.home / 'upstream')
        return upstream

    def test_lock_roundtrip_and_repeat(self):
        self.lock_fixture()
        self.run_setup()
        before = self.shell.read_bytes(), self.lua.read_bytes()
        marker = self.home / '.local/state/omarchy/indicators/stay-awake'
        marker.parent.mkdir(parents=True)
        marker.write_text('original')
        self.run_setup('--lock')
        self.assertFalse(marker.exists())
        data = json.loads(self.shell.read_text())
        self.assertEqual(data['idle'], {'lock': 60, 'screensaver': 0})
        self.assertIn('omarchy.lock', data['disabledPlugins'])
        self.assertIn({'id': 'spacewar.lock'}, data['plugins'])
        applied = self.shell.read_bytes(), self.lua.read_bytes()
        self.run_setup('--lock')
        self.assertEqual(applied, (self.shell.read_bytes(), self.lua.read_bytes()))
        self.run_setup('--undo')
        self.assertEqual(marker.read_text(), 'original')
        self.assertEqual(self.shell.read_text(), self.original)
        self.assertEqual(self.lua.read_text(), '-- original without newline')

    def test_lock_drift_rejected_without_mutations(self):
        upstream = self.lock_fixture()
        (upstream / 'Service.qml').write_text('drift')
        before = self.shell.read_bytes(), self.lua.read_bytes()
        self.run_setup('--lock', ok=False)
        self.assertEqual(before, (self.shell.read_bytes(), self.lua.read_bytes()))
        self.assertFalse((self.home / '.local/state/spacewar-mobile/lock-setup.json').exists())

    def test_lock_only_undo_preserves_later_changes(self):
        self.lock_fixture()
        self.run_setup('--lock')
        data = json.loads(self.shell.read_text())
        data['idle']['lock'] = 90
        data['plugins'].append({'id': 'user.later'})
        self.shell.write_text(json.dumps(data))
        self.lua.write_text(self.lua.read_text() + '-- later\n')
        self.run_setup('--undo')
        restored = json.loads(self.shell.read_text())
        self.assertEqual(restored['idle'], {'lock': 90})
        self.assertIn({'id': 'user.later'}, restored['plugins'])
        self.assertNotIn('phone-lock.lua', self.lua.read_text())
        self.assertIn('-- later', self.lua.read_text())
        self.assertTrue((self.home / '.local/state/omarchy/indicators/stay-awake').exists())

    def run_setup(self, *args, ok=True):
        script = (f'import sys; from pathlib import Path; from importlib.machinery import SourceFileLoader; '
                  f'm=SourceFileLoader("setup", {str(SETUP)!r}).load_module(); '
                  f'm.ROOT=Path({str(self.package)!r}); sys.argv=["setup"]+{list(args)!r}; m.main()')
        result = subprocess.run(['python3', '-c', script], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stderr)

    def test_roundtrip_and_repeat(self):
        self.run_setup()
        after = self.shell.read_bytes(), self.lua.read_bytes()
        self.run_setup()
        self.assertEqual(after, (self.shell.read_bytes(), self.lua.read_bytes()))
        profile = json.loads(self.shell.read_text())
        self.assertNotIn('id', profile['bar'])
        self.assertEqual(profile['bar']['position'], 'top')
        self.assertEqual(profile['idle'], {'lock': 123})
        self.assertEqual(profile['bar']['layout']['left'][0], {'id': 'omarchy.spacer', 'size': 44})
        backup = self.home / '.local/state/spacewar-mobile/setup.json'
        self.assertEqual(json.loads(backup.read_text())['shell'], self.original)
        self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
        self.run_setup('--undo')
        self.assertEqual(self.shell.read_text(), self.original)
        self.assertEqual(self.lua.read_text(), '-- original without newline')
        self.assertFalse(list((self.config / 'omarchy/plugins').iterdir()))
        self.run_setup('--undo')

    def test_osk_device_and_mask_roundtrip(self):
        osk = self.config / 'omarchy/onscreen-keyboard.json'
        osk.write_text('{"custom":123}')
        mask = self.config / 'systemd/user/omarchy-fcitx5.service'
        mask.parent.mkdir(parents=True)
        mask.symlink_to('/previous/unit')
        self.run_setup()
        self.assertEqual(json.loads(osk.read_text()), dict(custom=123, autoShow='always', extraRow=True))
        self.assertEqual(os.readlink(mask), '/dev/null')
        self.assertIn({'id': 'io.github.yeutterg.onscreen-keyboard'}, json.loads(self.shell.read_text())['plugins'])
        self.assertIn('phone-device.lua', (self.config / 'hypr/phone.lua').read_text())
        self.assertLess(self.lua.read_text().index('hypr.phone'), self.lua.read_text().index('phone-mobile.lua'))
        self.run_setup('--undo')
        self.assertEqual(osk.read_text(), '{"custom":123}')
        self.assertEqual(os.readlink(mask), '/previous/unit')
        self.assertFalse((self.config / 'hypr/phone.lua').exists())

    def test_resume_interrupted_setup(self):
        self.run_setup()
        journal = self.home / '.local/state/spacewar-mobile/setup.json'
        saved = json.loads(journal.read_text())
        saved.pop('complete')
        journal.write_text(json.dumps(saved))
        self.shell.write_text(self.original)
        (self.config / 'systemd/user/omarchy-fcitx5.service').unlink()
        self.run_setup()
        self.assertEqual(json.loads(self.shell.read_text()), saved['applied'])
        self.assertEqual(os.readlink(self.config / 'systemd/user/omarchy-fcitx5.service'), '/dev/null')
        self.run_setup('--undo')
        self.assertEqual(self.shell.read_text(), self.original)

    def test_preserve_later_changes(self):
        self.run_setup()
        data = json.loads(self.shell.read_text())
        data['idle']['lock'] = 456
        data['plugins'].append({'id': 'user.later'})
        self.shell.write_text(json.dumps(data))
        self.lua.write_text(self.lua.read_text() + '-- later\n')
        self.run_setup('--undo')
        data = json.loads(self.shell.read_text())
        self.assertEqual(data['idle']['lock'], 456)
        self.assertEqual(data['bar']['position'], 'right')
        self.assertEqual(data['plugins'], [{'id': 'user.test'}, {'id': 'user.later'}])
        self.assertNotIn('spacewar-mobile', self.lua.read_text())
        self.assertIn('-- later', self.lua.read_text())

    def test_invalid_json_and_conflict_change_nothing(self):
        self.shell.write_text('{bad')
        self.run_setup(ok=False)
        self.assertEqual(self.shell.read_text(), '{bad')
        self.assertFalse((self.home / '.local/state/spacewar-mobile/setup.json').exists())
        self.shell.write_text(self.original)
        conflict = self.config / 'omarchy/plugins/spacewar.shade'
        conflict.mkdir(parents=True)
        self.run_setup(ok=False)
        self.assertEqual(self.shell.read_text(), self.original)
        self.assertTrue(conflict.is_dir())

    def test_phone_gestures_migrate_and_restore(self):
        phone = self.config / 'hypr/phone.lua'
        original = "local hg = hl.plugin.hyprgrass\nhg.bind({ pattern={kind='edge', origin='u', direction='d'},\n action=hl.dsp.exec_cmd('omarchy-menu toggle root') })\n-- keep monitor config\n"
        phone.write_text(original)
        self.run_setup()
        self.assertNotIn('hg.bind(', phone.read_text())
        self.assertIn('-- keep monitor config', phone.read_text())
        self.run_setup()
        phone.write_text(phone.read_text() + '-- later\n')
        self.run_setup('--undo')
        self.assertEqual(phone.read_text(), original + '-- later\n')

    def test_only_profile_fields_change_and_later_layout_is_preserved(self):
        original = json.loads(self.original)
        original['bar']['id'] = 'omarchy.bar'
        original['bar']['customOption'] = 99
        original['dock'] = {'position': 'bottom'}
        original['disabledPlugins'] = ['user.disabled']
        self.shell.write_text(json.dumps(original))
        self.run_setup()
        data = json.loads(self.shell.read_text())
        self.assertEqual(data['bar']['id'], 'omarchy.bar')
        self.assertEqual(data['bar']['customOption'], 99)
        self.assertEqual(data['dock'], original['dock'])
        self.assertEqual(data['disabledPlugins'], original['disabledPlugins'])
        self.assertEqual(data['bar']['layout']['center'], [])
        data['bar']['layout']['right'].append({'id': 'user.new'})
        self.shell.write_text(json.dumps(data))
        self.run_setup('--undo')
        restored = json.loads(self.shell.read_text())
        self.assertEqual(restored['bar']['layout']['left'], original['bar']['layout']['left'])
        self.assertEqual(restored['bar']['layout']['right'][-1], {'id': 'user.new'})
        self.assertEqual(restored['bar']['position'], 'right')
        self.assertFalse(list(self.home.rglob('bar-off')))

    def test_missing_configs(self):
        self.shell.unlink()
        self.lua.unlink()
        self.run_setup()
        self.run_setup('--undo')
        self.assertFalse(self.shell.exists())
        self.assertFalse(self.lua.exists())

    def test_partial_install_undo(self):
        self.run_setup()
        self.shell.write_text(self.original)
        self.run_setup('--undo')
        self.assertEqual(json.loads(self.shell.read_text()), json.loads(self.original))
        self.assertFalse(list((self.config / 'omarchy/plugins').iterdir()))


if __name__ == '__main__':
    unittest.main()
