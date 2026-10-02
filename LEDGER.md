# LEDGER.md — doubt ledger (quilt-in-git convention)

Append-only, git-backed record of relocated trust: what stopped being
checked, why, what covers it, and what event brings it back. This is the
quilt-in-git markdown convention answering cf-native-backend design
question #3 (SuperInstance/doubt-ledger is the JSON store this borrows its
grammar from).

## Entry grammar

One entry per line, all six fields required, ` | `-separated, in order:

```
- doubt <id> | path: <path> | stopped: <what stopped being checked> | covered_by: <what now covers it> | revisit: <event that reopens it> | status: open
```

- `id` — short unique slug `[0-9a-f]{6,}` (prefix of anything unique).
- `path` — the repo path the doubt hangs off (a cell, a dir, a file).
- `stopped` / `covered_by` / `revisit` — free text, no ` | ` inside.
- `status` — `open` | `due` | `discharged`. Discharge requires a written
  reason on a follow-up line; an unreasoned discharge is just blindness
  again.

`quilt-query coverage <needle>` matches entries by substring against the
whole line and cross-references receipted commits whose touched paths
intersect `path:` (substring, either direction — use precise paths).

Comment lines start with `#`; blank lines are ignored. The file is read
from the COMMITTED tree at the queried ref: uncommitted edits are
invisible to the query layer, by design.
