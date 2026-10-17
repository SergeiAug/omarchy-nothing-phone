import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

BASE = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('setup', str(BASE / 'spacewar-shell-setup'))
spec = importlib.util.spec_from_loader(loader.name, loader)
setup = importlib.util.module_from_spec(spec)
loader.exec_module(setup)

class SetupTests(unittest.TestCase):
    def test_apply_repeat_undo(self):
        with tempfile.TemporaryDirectory() as temp:
            config, state = Path(temp)/'config', Path(temp)/'state'
            (config/'hypr').mkdir(parents=True)
            (config/'omarchy').mkdir()
            lua = 'require("defaults")\ndofile("old") -- spacewar-mobile\n'
            shell = dict(custom=42, plugins=[dict(id='spacewar.shade'), dict(id='mine')], lock=dict(enabled=True))
            (config/'hypr/hyprland.lua').write_text(lua)
            (config/'omarchy/shell.json').write_text(json.dumps(shell))
            (config/'omarchy/keep').symlink_to('/tmp/example')
            fixture=Path(temp)/'installed/mobile-shell'
            fixture.parent.mkdir(exist_ok=True)
            fixture.symlink_to(BASE, target_is_directory=True)
            (fixture.parent/'osk').mkdir(exist_ok=True)
            (fixture.parent/'osk/manifest.json').write_text('{}')
            setup.configure(config, state, fixture)
            first = (config/'omarchy/shell.json').read_bytes()
            applied = json.loads(first)
            self.assertEqual(applied['custom'], 42)
            self.assertEqual(applied['lock'], shell['lock'])
            self.assertIn('omarchy.dock', applied['disabledPlugins'])
            self.assertNotIn('-- spacewar-mobile', (config/'hypr/hyprland.lua').read_text())
            setup.configure(config, state, fixture)
            self.assertEqual(first, (config/'omarchy/shell.json').read_bytes())
            self.assertEqual(len(list(state.glob('backup-*.tar'))), 1)
            setup.configure(config, state, fixture, True)
            self.assertEqual(json.loads((config/'omarchy/shell.json').read_text()), shell)
            self.assertEqual((config/'hypr/hyprland.lua').read_text(), lua)
            self.assertTrue((config/'omarchy/keep').is_symlink())
            setup.configure(config, state, fixture, True)

    def test_invalid_config_untouched(self):
        with tempfile.TemporaryDirectory() as temp:
            config, state = Path(temp)/'config', Path(temp)/'state'
            (config/'omarchy').mkdir(parents=True)
            (config/'omarchy/shell.json').write_text('[]')
            with self.assertRaises(ValueError): setup.configure(config, state, BASE)
            self.assertFalse(list(state.glob('backup-*.tar')))

    def test_interrupted_apply_recovers_one_backup(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temp:
            base=Path(temp)
            config,state=base/'config',base/'state'
            fixture=base/'installed/mobile-shell'
            fixture.parent.mkdir()
            fixture.symlink_to(BASE,target_is_directory=True)
            (fixture.parent/'osk').mkdir()
            (fixture.parent/'osk/manifest.json').write_text('{}')
            original=setup.atomic
            def fail_shell(path,text):
                if path.name=='shell.json': raise OSError('simulated interrupted apply')
                original(path,text)
            with patch.object(setup,'atomic',fail_shell):
                with self.assertRaises(OSError): setup.configure(config,state,fixture)
            self.assertFalse(json.loads((state/'setup.json').read_text())['complete'])
            setup.configure(config,state,fixture)
            self.assertTrue(json.loads((state/'setup.json').read_text())['complete'])
            self.assertEqual(len(list(state.glob('backup-*.tar'))),1)
            setup.configure(config,state,fixture,True)
            self.assertFalse((config/'hypr').exists())
            self.assertFalse((config/'omarchy').exists())

    def test_user_plugin_directory_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as temp:
            config,state=Path(temp)/'config',Path(temp)/'state'
            owned=config/'omarchy/plugins/omamobile.bar'
            owned.mkdir(parents=True)
            (owned/'mine').write_text('keep')
            with self.assertRaises(ValueError): setup.configure(config,state,BASE)
            self.assertEqual((owned/'mine').read_text(),'keep')
            self.assertFalse(list(state.glob('backup-*.tar')))
