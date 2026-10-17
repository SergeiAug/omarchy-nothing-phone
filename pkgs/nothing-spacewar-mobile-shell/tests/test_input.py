import os
from pathlib import Path
import subprocess
import unittest
class InputTests(unittest.TestCase):
    def test_qt_touch(self):
        result=subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-input',str(Path(__file__).with_name('tst_edges.qml'))],
            env=dict(os.environ, GSETTINGS_BACKEND='memory', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software'),
            capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('5 passed, 0 failed',result.stdout)
