# notes2feed — the git-native witness stream

w3a attaches every tick receipt to its commit as a git note
(`refs/notes/quilt/receipts`) so receipts ride fetch/push/clone with the
branch. This lane makes that stream CONSUMABLE:

- `tools/notes2feed.py [repo] [out.json]` — reads the notes ref, emits the
  quilt-overhead feed.v1 dialect (`{cells, meta}`; lattice coords; kind ∈
  the five fleet verbs; `meta.wal_ref = "notes:<chain-head>"` — the notes
  head IS the stream identity, the same role wal_ref plays for WAL files).
- `tools/pin_notes2feed.py [repo]` — 11 FAIL-first pins. N0 is the
  load-bearing one: a fresh clone has NO notes (git never auto-fetches
  `refs/notes/*`), so the seam's first run on fresh metal refuses with a
  named reason — never a fake-empty feed.

## The missing wire (documented, not fixed here)

Notes never auto-fetch and never auto-push. A consumer needs:

```
git fetch origin 'refs/notes/*:refs/notes/*'
```

and a producer must push `refs/notes/quilt/receipts` explicitly. Until a
push step exists in the tick flow, the notes stream is local-only — this
tool pins the CONSUMPTION contract so the production wire can be added
without dialect drift.

REDs captured 2026-10-02: N0 on a fresh clone; pin-suite dev caught a
JSON-concat bug (two docs on one stdout). Both fixed; suite GREEN 11/11.
