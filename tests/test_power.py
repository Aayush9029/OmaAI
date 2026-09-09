"""Exercise the real controller against a stateful systemctl substitute."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class PowerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        (self.directory / 'key').write_text('test-key')
        config = self.directory / 'env'
        config.write_text(f'OMAAI_API_KEY_FILE={self.directory}/key\n')
        controller = (REPO / 'bin/omaai').read_text().replace(
            'config_path="${HOME}/.config/omaai/env"', f'config_path="{config}"')
        self.controller = self.directory / 'omaai'
        self.controller.write_text(controller)
        fake = self.directory / 'systemctl'
        fake.write_text('''#!/usr/bin/env python3
import os, pathlib, sys
p = pathlib.Path(os.environ['POWER_TEST_DIR'])
a = sys.argv[1:]
with (p / 'calls').open('a') as f: f.write(' '.join(a) + '\\n')
cmd = a[1]
if cmd == 'is-active': sys.exit(0 if (p / 'active').exists() else 3)
if os.environ.get('POWER_TEST_FAIL') == cmd: sys.exit(1)
if cmd == 'enable': (p / 'enabled').touch()
if cmd == 'disable': (p / 'enabled').unlink(missing_ok=True)
if cmd == 'restart' or (cmd == 'enable' and '--now' in a): (p / 'active').touch()
if cmd == 'disable' and '--now' in a: (p / 'active').unlink(missing_ok=True)
''')
        fake.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{self.directory}:{os.environ["PATH"]}',
                        POWER_TEST_DIR=str(self.directory))

    def run_action(self, action, fail=''):
        return subprocess.run(['bash', str(self.controller), action],
                              env=dict(self.env, POWER_TEST_FAIL=fail), capture_output=True)

    def assert_power(self, enabled):
        for flag in ('active', 'enabled'):
            self.assertEqual((self.directory / flag).exists(), enabled)

    def test_stop_persists_across_controller_relaunch(self):
        self.assertEqual(self.run_action('start').returncode, 0)
        self.assert_power(True)
        self.assertEqual(self.run_action('stop').returncode, 0)
        self.assert_power(False)
        self.assertEqual(self.run_action('unload').returncode, 0)
        self.assert_power(False)

    def test_toggle_both_directions(self):
        for enabled in (True, False, True, False):
            self.assertEqual(self.run_action('toggle').returncode, 0)
            self.assert_power(enabled)

    def test_failed_stop_never_falls_back_to_start(self):
        self.run_action('load')
        (self.directory / 'calls').write_text('')
        self.assertNotEqual(self.run_action('toggle', fail='disable').returncode, 0)
        calls = (self.directory / 'calls').read_text().splitlines()
        self.assertEqual(len(calls), 2)
        self.assertNotIn('enable', '\n'.join(calls))

    def test_restart_explicitly_enables_login(self):
        self.assertEqual(self.run_action('restart').returncode, 0)
        self.assert_power(True)

    def test_enable_failure_does_not_restart(self):
        self.assertNotEqual(self.run_action('restart', fail='enable').returncode, 0)
        self.assert_power(False)
        self.assertNotIn('restart', (self.directory / 'calls').read_text())


if __name__ == '__main__':
    unittest.main()
