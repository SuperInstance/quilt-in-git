# Harvest / Verify Protocol (quilt-in-git)

Receipts over claims. A lane's output is a claim until re-run on a
**fresh clone** by the harvester. Deviation sealed 2026-10-02: lane w3c
placed its pins in `tests/pins_w3c.sh`, not the assumed
`tests/pins_quiltgit.sh` — the protocol now enumerates test files
instead of assuming one.

## Protocol

1. `git clone` (or `git worktree add`) a FRESH copy at the branch tip.
   Never verify in the lane's own worktree.
2. **Enumerate** every executable under `tests/` (`ls tests/pins_*.sh`),
   then run each one. Do not assume a single canonical pins file.
3. Every pin must exit 0. A single RED pin = FAIL for the whole branch,
   regardless of how many green pins surround it.
4. Record: pin file name, pass count, and any output hashes the pin
   prints (fnv1a-64 receipts). Claims without re-run receipts stay
   claims.
5. Only then: merge / push / open PR.

## Standing notes

- Merge order (wave-3): PR #2 (orphan dials branch + refs/quilt/HEAD)
  supersedes PR #1's HEAD portion — both touch the post-commit path.
  Merge #2, close #1 as superseded.
- FAIL-first culture: a branch whose pins were never RED on a pristine
  tip has not demonstrated its pins test anything.
