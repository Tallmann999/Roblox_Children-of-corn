"""Run actual generated Harvest installer in the read-only Lune scene adapter."""
from pathlib import Path
import json
import subprocess
ROOT=Path(__file__).resolve().parents[1]
result=subprocess.run([str(ROOT/".tools/lune/lune.exe"),"run",str(ROOT/"tests/harvest-installer.luau")],cwd=ROOT,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
report=json.loads(result.stdout)
assert report["passed"] and report["negative_cases"] >= 30
print(json.dumps(report))
