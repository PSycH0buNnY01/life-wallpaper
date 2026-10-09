"""Contract checks between README and Sources/main.swift.

The app is a single macOS-only Swift file (Cocoa, top-level code), so it cannot be
imported or compiled here. These tests read the source and check that the settings
ranges documented in the README are what `Settings.clamp` enforces, and that the
Life rule is the standard B3/S23 on a torus.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = (ROOT / "Sources" / "main.swift").read_text()
README = (ROOT / "README.md").read_text()


def clamp_body():
    m = re.search(r"static func clamp\(.*?\n    \}\n", SRC, re.S)
    assert m, "Settings.clamp not found"
    return m.group(0)


class ClampMatchesReadme(unittest.TestCase):
    def test_documented_keys(self):
        for key, rng in [("cell", "3–80"), ("fps", "0.5–30"),
                         ("density", "0.02–0.9"), ("trail", "0–60")]:
            self.assertIn(f"`{key}` ({rng}", README)

    def test_cell(self):
        self.assertIn("c.cell = max(3, min(80, c.cell))", clamp_body())

    def test_fps(self):
        self.assertIn("c.fps = min(30, max(0.5, c.fps))", clamp_body())

    def test_density(self):
        self.assertIn("c.density = min(0.9, max(0.02, c.density))", clamp_body())

    def test_trail(self):
        self.assertIn("c.trail = max(0, min(60, c.trail))", clamp_body())

    def test_negative_fade_means_auto(self):
        self.assertIn("c.fade < 0 ? -1", clamp_body())


class LifeRules(unittest.TestCase):
    def test_standard_rule(self):
        self.assertIn("(s == 3 || (alive && s == 2)) ? 1 : 0", SRC)

    def test_all_eight_neighbours_wrap(self):
        step = SRC[SRC.index("func step()"):]
        step = step[:step.index("swap(&cur, &nxt)")]
        for expr in ["c[up + xl]", "c[up + x]", "c[up + xr]", "c[md + xl]",
                     "c[md + xr]", "c[dn + xl]", "c[dn + x]", "c[dn + xr]"]:
            self.assertIn(expr, step)
        self.assertIn("(y - 1 + H) % H", step)
        self.assertIn("(x - 1 + W) % W", step)

    def test_reseeds_when_dead_or_looping(self):
        self.assertIn("if pop == 0 { seedAll(); return }", SRC)
        self.assertIn("if seen.contains(hv) { sprinkle(); return }", SRC)


if __name__ == "__main__":
    unittest.main()
