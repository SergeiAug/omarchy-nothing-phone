#!/usr/bin/python3
from importlib.machinery import SourceFileLoader
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

MOBILE = SourceFileLoader('mobile', os.environ.get('MOBILE_ACTIONS', str(Path(__file__).resolve().parents[1] / 'spacewar-mobile'))).load_module()


class ActionsTest(unittest.TestCase):
    def test_back_closes_own_panel_before_sending_keys(self):
        def ipc(*args):
            if args[:2] == ('shell', 'call'):
                return json.dumps({'opened': args[2] == 'spacewar.shade'})
        with patch.object(MOBILE, 'ipc', side_effect=ipc) as calls, patch.object(MOBILE, 'run') as commands:
            MOBILE.back()
            calls.assert_any_call('shell', 'hide', 'spacewar.shade')
            commands.assert_not_called()

    def back_commands(self, app, address='0x1234'):
        def run(*args):
            if args == ('hyprctl', '-j', 'activewindow'):
                return json.dumps({'class': app, 'address': address})
            return 'ok'
        with patch.object(MOBILE, 'ipc', return_value='{}'), patch.object(MOBILE, 'unlocked'), patch.object(MOBILE, 'run', side_effect=run) as commands:
            MOBILE.back()
            return [call.args for call in commands.call_args_list if call.args[1:2] == ('dispatch',)]

    def test_browser_back_targets_window_and_releases_key(self):
        calls = self.back_commands('firefox')
        self.assertEqual(len(calls), 2)
        self.assertIn('mods="ALT",key="Left",state="down",window="address:0x1234"', calls[0][2])
        self.assertIn('state="up"', calls[1][2])

    def test_settings_escape_and_terminal_no_action(self):
        self.assertIn('mods="",key="Escape"', self.back_commands('nm-connection-editor')[0][2])
        self.assertEqual(self.back_commands('Alacritty'), [])

    def test_bad_address_not_interpolated(self):
        with self.assertRaises(ValueError):
            self.back_commands('firefox', '0x1"); os.execute("bad")')

    def test_locked_prevents_action(self):
        with patch.object(sys, 'argv', ['spacewar-mobile', 'shade']), patch.object(MOBILE, 'ipc', return_value='true'), patch.object(MOBILE, 'run') as commands:
            with self.assertRaises(ValueError): MOBILE.main()
            commands.assert_not_called()

    def test_webapps_files_and_terminals(self):
        for app in ['chrome-mail.example__-Default', 'org.gnome.Nautilus', 'nemo', 'pcmanfm-qt']:
            self.assertIn('mods="ALT",key="Left"', self.back_commands(app)[0][2])
        for app in ['foot', 'footclient', 'Ghostty', 'com.mitchellh.ghostty', 'unknown']:
            self.assertEqual(self.back_commands(app), [])

    def test_home_uses_stock_grid(self):
        with patch.object(sys, 'argv', ['spacewar-mobile', 'home']), patch.object(MOBILE, 'unlocked'), patch.object(MOBILE, 'ipc') as calls:
            MOBILE.main()
            calls.assert_any_call('omarchy.dock', 'apps')

    def test_shade_routes_to_stock_panels(self):
        for panel in ['network', 'bluetooth', 'audio', 'power']:
            with patch.object(sys, 'argv', ['spacewar-mobile', panel]), patch.object(MOBILE, 'unlocked'), patch.object(MOBILE, 'ipc', return_value='ok') as calls:
                MOBILE.main()
                calls.assert_any_call('shell', 'summon', 'omarchy.' + panel, '{}')

    def test_brightness_validates_before_stock_write(self):
        for value in ['0', '101', 'NaN', '50%;bad']:
            with patch.object(sys, 'argv', ['spacewar-mobile', 'brightness', value]), patch.object(MOBILE, 'unlocked'), patch.object(MOBILE, 'run') as commands:
                with self.assertRaises(ValueError): MOBILE.main()
                commands.assert_not_called()
        with patch.object(sys, 'argv', ['spacewar-mobile', 'brightness', '43']), patch.object(MOBILE, 'unlocked'), patch.object(MOBILE, 'run') as commands:
            MOBILE.main()
            commands.assert_called_once_with('omarchy-brightness-display', '--no-osd', '--monitor', 'DSI-1', '43%')

    def test_state_uses_real_sources_and_unavailable_is_not_off(self):
        def run(*args):
            if args[:2] == ('omarchy-shell', 'onscreen-keyboard'): return '{"shown": false, "language": "ru"}'
            if args[0] == 'hyprctl': return '[{"name":"DSI-1","transform":1}]'
            raise OSError('not installed')
        with patch.object(MOBILE, 'run', side_effect=run):
            state = MOBILE.shade_state()
            self.assertEqual(state['layout'], 'RU')
            self.assertIs(state['keyboard'], False)
            self.assertTrue(state['rotated'])
            for key in ['dnd', 'brightness']:
                self.assertIsNone(state[key])

    def test_dnd_uses_stock_ipc(self):
        with patch.object(sys, 'argv', ['spacewar-mobile', 'dnd']), patch.object(MOBILE, 'unlocked'), patch.object(MOBILE, 'ipc') as calls:
            MOBILE.main()
            calls.assert_called_once_with('notifications', 'toggleDnd')

    def test_keyboard_toggles_the_omarchy_osk(self):
        with patch.object(sys, 'argv', ['spacewar-mobile', 'keyboard']), patch.object(MOBILE, 'unlocked'), patch.object(MOBILE, 'hide_panels'), patch.object(MOBILE, 'run') as calls:
            MOBILE.main()
            self.assertEqual(calls.call_args.args, ('omarchy-shell', 'onscreen-keyboard', 'toggle'))

    def test_layout_switches_osk_language_and_shows_it(self):
        with patch.object(sys, 'argv', ['spacewar-mobile', 'layout']), patch.object(MOBILE, 'unlocked'), patch.object(MOBILE, 'hide_panels'), patch.object(MOBILE, 'run') as calls:
            MOBILE.main()
            self.assertEqual([c.args for c in calls.call_args_list][-2:],
                             [('omarchy-shell', 'onscreen-keyboard', 'switchLanguage'), ('omarchy-shell', 'onscreen-keyboard', 'show')])

    def test_flash_is_optional_and_never_escalates(self):
        with tempfile.TemporaryDirectory() as temp:
            flash = Path(temp) / 'brightness'
            with patch.object(MOBILE, 'FLASH', flash), patch.object(MOBILE, 'unlocked'), patch.object(sys, 'argv', ['spacewar-mobile', 'flash']), patch.object(MOBILE, 'run') as commands:
                with self.assertRaises(ValueError): MOBILE.main()
                flash.write_text('0')
                MOBILE.main()
                self.assertEqual(flash.read_text(), '1')
                MOBILE.main()
                self.assertEqual(flash.read_text(), '0')
                commands.assert_not_called()


if __name__ == '__main__':
    unittest.main()
