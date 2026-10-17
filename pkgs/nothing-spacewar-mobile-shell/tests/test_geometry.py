import runpy
from pathlib import Path
import unittest
geometry = runpy.run_path(str(Path(__file__).resolve().parents[1]/'spacewar-shell-geometry'))['geometry']
class GeometryTests(unittest.TestCase):
    def test_height_from_layer(self):
        layers={'DSI-1':{'levels':{'3':[dict(namespace='omarchy-onscreen-keyboard',y=811,h=389)]}}}
        self.assertEqual(geometry(dict(shown=True),layers)['top'],811)
        self.assertFalse(geometry(dict(shown=False),layers)['shown'])
    def test_missing_layer_fails_closed(self):
        with self.assertRaises(ValueError): geometry(dict(shown=True),{})
        with self.assertRaises(ValueError): geometry({}, {})
