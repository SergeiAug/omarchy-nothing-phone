import json
import runpy
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

BASE = Path(__file__).resolve().parents[1]
BACK = runpy.run_path(str(BASE/'spacewar-shell-back'))


class Fix2Tests(unittest.TestCase):
    def test_window_policy(self):
        subprocess.run(['lua', str(BASE/'tests/window-policy.lua'), str(BASE/'phone-device.lua')], check=True)

    def test_back_dispatch_and_home(self):
        cases = [({'class': c}, ('ALT', 'Left')) for c in
                 ['chromium', 'firefox', 'org.mozilla.firefox', 'org.gnome.Nautilus', 'dolphin', 'thunar']]
        cases += [({'class': 'soffice', 'tags': ['spacewar-dialog*']}, ('', 'Escape')),
                  ({'class': 'firefox', 'tags': ['spacewar-dialog']}, ('', 'Escape')),
                  ({'class': 'foot', 'tags': ['spacewar-dialog*']}, ('', 'Escape'))]
        cases += [({'class': c}, None) for c in ['foot', 'org.omarchy.terminal', 'vim', 'soffice']]
        for window, expected in cases:
            with self.subTest(window=window):
                self.assertEqual(BACK['action'](window), expected)
                window['address'] = '0x123'
                with patch('subprocess.check_output', return_value=json.dumps(window)), patch('subprocess.run') as run:
                    BACK['main']()
                    commands = [c.args[0] for c in run.call_args_list]
                    if expected:
                        self.assertEqual(len(commands), 1)
                        self.assertIn('hl.dsp.send_shortcut(', commands[0][-1])
                        self.assertIn('key="%s"' % expected[1], commands[0][-1])
                        self.assertIn('address:0x123', commands[0][-1])
                    else:
                        self.assertIn('goHome', commands[0])
                        self.assertIn('workspace="empty"', commands[1][-1])
                        self.assertEqual(commands[2][-1], 'hide')

    def test_back_rejects_invalid_address(self):
        with patch('subprocess.check_output', return_value='{"class":"firefox","address":"0x1;evil"}'), patch('subprocess.run') as run:
            with self.assertRaises(ValueError): BACK['main']()
            run.assert_not_called()

    def test_install_upgrade_retrigger_leds(self):
        with tempfile.TemporaryDirectory() as temp:
            log = Path(temp)/'log'
            # Shell function intercepts udev; no host rules or devices are touched.
            script = 'udevadm() { printf "%s\\n" "$*" >> "' + str(log) + '"; }; . "$1"; post_install; post_upgrade'
            subprocess.run(['bash', '-c', script, 'qa', str(BASE/'mobile-shell.install')], check=True)
            self.assertEqual(log.read_text().splitlines(),
                             ['control --reload-rules', 'trigger --action=add --subsystem-match=leds'] * 2)
