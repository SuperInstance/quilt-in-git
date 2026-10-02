#!/usr/bin/env python3
"""notes2feed — refs/notes/quilt/receipts -> quilt-overhead feed.v1.

The git-native witness stream. quilt-in-git's post-commit hook attaches
every tick receipt to its commit as a git note (ref: quilt/receipts), so
receipts ride fetch/push/clone with the branch while .quilt/receipts/
files never leave the working tree. This tool reads the notes ref and
emits the SAME feed dialect quilt-overhead renders, with the notes head
as the stream identity (wal_ref := "notes:<head>").

Usage: python3 tools/notes2feed.py [repo_dir] [out.json]
Requires: refs/notes/quilt/receipts present (git fetch origin
'refs/notes/*:refs/notes/*' on a fresh clone — notes never auto-fetch).
"""
import json
import math
import subprocess
import sys
from pathlib import Path

KINDS = {"edit", "commit", "pin", "receipt", "note"}
NOTES_REF = "refs/notes/quilt/receipts"


def git(repo, *args):
    out = subprocess.run(["git", "-C", str(repo), *args],
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"git {' '.join(args)}: {out.stderr.strip()}")
    return out.stdout


def main():
    repo = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else None

    head = git(repo, "rev-parse", NOTES_REF).strip()
    # notes list: "<note_sha> <annotated_sha>" per line, oldest first
    listing = git(repo, "notes", "--ref=quilt/receipts", "list").strip().splitlines()

    cells, n_deltas, orphans = {}, 0, 0
    for line in listing:
        note_sha, commit_sha = line.split()
        body = git(repo, "notes", "--ref=quilt/receipts", "show", commit_sha)
        try:
            receipt = json.loads(body)
        except json.JSONDecodeError:
            orphans += 1
            continue
        ts = int(receipt["ts"])
        for alias in receipt.get("changed_cells", []):
            cid = f"cell:{alias}"
            if cid not in cells:
                ang = (len(cells) / 8) * 6.28318
                cells[cid] = {"id": cid, "name": alias, "agent": "cell",
                              "x": round(0.5 + 0.35 * math.cos(ang), 4),
                              "y": round(0.5 + 0.35 * math.sin(ang), 4),
                              "doc": f"cells/{alias}", "deltas": []}
            cells[cid]["deltas"].append({"t": ts, "kind": "receipt",
                                         "size": len(body)})
            n_deltas += 1

    for c in cells.values():
        c["deltas"].sort(key=lambda d: d["t"])
        for d in c["deltas"]:
            assert d["kind"] in KINDS

    feed = {"cells": sorted(cells.values(), key=lambda c: c["id"]),
            "meta": {"wal_ref": f"notes:{head[:16]}", "chain_head": head,
                     "source": f"{repo.name}@{NOTES_REF}", "tag": "REAL",
                     "orphan_notes": orphans}}
    text = json.dumps(feed, indent=1)
    if out_path:
        out_path.write_text(text + "\n", encoding="utf-8")
    print(json.dumps({"cells": len(feed["cells"]), "deltas": n_deltas,
                      "wal_ref": feed["meta"]["wal_ref"],
                      "orphans": orphans}))


if __name__ == "__main__":
    main()
