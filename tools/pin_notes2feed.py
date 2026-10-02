#!/usr/bin/env python3
"""FAIL-first pins for the notes2feed seam (w3a witness stream).

Run: python3 tools/pin_notes2feed.py [repo_dir]
Every pin names its falsification. The suite must be able to trip RED on
the unfixed reality — pins that cannot fail are decorations.

N1 is the load-bearing honest pin: a fresh clone has NO notes (git never
auto-fetches refs/notes/*), so the seam's first run on fresh metal MUST
refuse with a named reason, not fake an empty feed.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
REPO = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT
NOTES_REF = "refs/notes/quilt/receipts"
KINDS = {"edit", "commit", "pin", "receipt", "note"}


def git(*args, check=True):
    out = subprocess.run(["git", "-C", str(REPO), *args],
                         capture_output=True, text=True)
    if check and out.returncode != 0:
        raise SystemExit(f"git {' '.args}: {out.stderr.strip()}")
    return out


fails = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (f" - {detail}" if detail else ""))
    if not cond:
        fails.append(name)


head_r = git("rev-parse", "--verify", NOTES_REF, check=False)
if head_r.returncode != 0:
    print(f"FAIL N0 notes ref {NOTES_REF} absent — fetch it: "
          f"git fetch origin 'refs/notes/*:refs/notes/*' (notes never auto-fetch)")
    sys.exit(1)
head = head_r.stdout.strip()

out = subprocess.run([sys.executable, str(ROOT / "tools/notes2feed.py"),
                      str(REPO)], capture_output=True, text=True)
check("N1 adapter runs clean on the live notes ref (stdout summary)",
      out.returncode == 0, out.stderr.strip()[:120])
import tempfile
with tempfile.NamedTemporaryFile("r", suffix=".json", delete=False) as tf:
    tmp = tf.name
run = subprocess.run([sys.executable, str(ROOT / "tools/notes2feed.py"),
                      str(REPO), tmp], capture_output=True, text=True)
check("N1b adapter writes a parseable snapshot file", run.returncode == 0,
      run.stderr.strip()[:120])
try:
    feed = json.loads(Path(tmp).read_text())
except (json.JSONDecodeError, FileNotFoundError) as e:
    feed = {}
    print(f"FAIL N1b snapshot is valid JSON - {e}")
    fails.append("N1b-json")

cells = feed.get("cells", [])
check("N2 snapshot has cells", len(cells) >= 1, f"{len(cells)} cells")

ok_fields = all(all(f in c for f in ("id", "name", "agent", "x", "y", "doc", "deltas"))
                for c in cells)
check("N3 every cell carries the 7 contract fields", ok_fields)

ok_coords = all(0.0 <= float(c["x"]) <= 1.0 and 0.0 <= float(c["y"]) <= 1.0
                for c in cells)
check("N4 x,y are lattice coords in [0,1]", ok_coords)

ok_kinds = all(d["kind"] in KINDS for c in cells for d in c["deltas"])
check("N5 deltas use only the five fleet verbs", ok_kinds)

ok_order = all([d["t"] for d in c["deltas"]] == sorted(d["t"] for d in c["deltas"])
               for c in cells)
check("N6 deltas time-ordered per cell", ok_order)

n_notes = len(git("notes", "--ref=quilt/receipts", "list").stdout.strip().splitlines())
n_deltas = sum(len(c["deltas"]) for c in cells)
check("N7 every note became a delta somewhere", n_deltas >= n_notes,
      f"{n_deltas} deltas / {n_notes} notes")

meta = feed.get("meta", {})
check("N8 meta.wal_ref binds the notes head", meta.get("wal_ref") == f"notes:{head[:16]}",
      f"wal_ref={meta.get('wal_ref')} head={head[:16]}")
check("N9 tagged REAL, not SIMULATED", "REAL" in str(meta.get("tag", "")))
check("N10 meta names a source notes ref", "quilt/receipts" in str(meta.get("source", "")))

print("GREEN: notes2feed conforms (git-native witness stream)" if not fails
      else f"RED: {len(fails)} pin(s) tripped")
sys.exit(1 if fails else 0)
