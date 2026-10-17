import runpy
import subprocess
import tempfile
import unittest
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
torch = runpy.run_path(str(BASE/'bin/spacewar-shell-torch'))

class FixTests(unittest.TestCase):
    def test_torch_capabilities_and_continuous_mode(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def led(name, capability=False):
                path = root/name; path.mkdir()
                (path/'brightness').write_text('0')
                (path/'max_brightness').write_text('255')
                if capability:
                    (path/'flash_brightness').write_text('99')
                    (path/'flash_strobe').write_text('0')
                return path
            led('blue:indicator')
            self.assertFalse(torch['operate']('status', root)['available'])
            for name in ['white:flash', 'vendor:rear', 'white:torch']:
                with self.subTest(name=name):
                    path = led(name, name != 'white:torch')
                    self.assertTrue(torch['operate']('on', root)['enabled'])
                    self.assertEqual((path/'brightness').read_text(), '63')
                    if (path/'flash_strobe').exists():
                        self.assertEqual((path/'flash_strobe').read_text(), '0')
                        self.assertEqual((path/'flash_brightness').read_text(), '99')
                    self.assertFalse(torch['operate']('off', root)['enabled'])
                    for entry in path.iterdir(): entry.unlink()
                    path.rmdir()

    def test_udev_rule_syntax(self):
        subprocess.run(['udevadm','verify',str(BASE/'90-spacewar-torch.rules')],check=True,capture_output=True)
