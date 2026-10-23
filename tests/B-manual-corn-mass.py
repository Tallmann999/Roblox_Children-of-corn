"""Analytic mass/inertia fixtures independent of any saved candidate mesh."""
import importlib.util
import itertools
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('corn_mass_fixture', ROOT / 'scripts/verify-B-manual-corn.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
checks = 0

def close(actual, expected, tolerance=2e-6):
    global checks
    assert len(actual) == len(expected)
    assert all(abs(a-b) <= tolerance for a,b in zip(actual, expected)), (actual, expected)
    checks += 1

cube = list(itertools.product((-1, 1), repeat=3))
result = m.convex_mass_metadata(cube)
close(result['InitialSize'], [2, 2, 2])
close([result['UnscaledVolume']], [8])
close(result['UnscaledCofm'], [0, 0, 0])
close(result['UnscaledVolInertiaDiags'], [16/3]*3)
close(result['UnscaledVolInertiaOffDiags'], [0, 0, 0])

shifted = [[x+3, y-2, z+5] for x,y,z in cube]
result = m.convex_mass_metadata(shifted + shifted[:3])
close([result['UnscaledVolume']], [8])
close(result['UnscaledCofm'], [3, -2, 5])
close(result['UnscaledVolInertiaDiags'], [16/3]*3)

box = list(itertools.product((-1, 1), (-2, 2), (-3, 3)))
result = m.convex_mass_metadata(box)
close(result['InitialSize'], [2, 4, 6])
close([result['UnscaledVolume']], [48])
close(result['UnscaledVolInertiaDiags'], [208, 160, 80])

c = math.sqrt(.5)
rotated = [[c*x+c*z, y, -c*x+c*z] for x,y,z in box]
result = m.convex_mass_metadata(rotated)
close(result['UnscaledVolInertiaDiags'], [144, 160, 144], 3e-5)
close(result['UnscaledVolInertiaOffDiags'], [0, -64, 0], 3e-5)
print(f'manual corn convex mass: {checks} analytic checks PASS')
