# RESULT — wave-4 verifiable-coverage query layer

Lane: wave4-query (resumed instance). Branch `wave4-query` off
`origin/main` @ 6a1ae48. All new files; zero overlap with open PRs #1–#7
(none touch `.quilt/bin/quilt-query`, `tests/pins_query.sh`, `LEDGER.md`,
`pins/failfirst-w4q.log`, `pins/pins-w4q-final.log`, or this file).
`README.md` deliberately untouched for the same reason.

## What this answers

cf-native-backend README open design question #3: *"What does 'show me
everything currently trusted-but-unaudited' look like as an API? (doubt-
ledger is the seed.)"* — answered natively in quilt-in-git: the repo is
the API. Four subcommands in `.quilt/bin/quilt-query` (POSIX sh, no deps):

| subcommand | semantics | rc |
|---|---|---|
| `trusted-but-unaudited [--ref R] [--anchor A]` | receipted commits at R that no attested audit position covers; coverage = is-ancestor order; anchors from `refs/quilt/audit/*` or `--anchor`; output in rev-list receipt order | 0 results / 1 none |
| `coverage <needle> [--ref R]` | `LEDGER.md` (committed tree only) entries matching `<needle>`, crossed with receipted commits touching it, annotated `covered-by:<id>` / `uncovered` | 0 entries / 1 none / 2 no LEDGER.md |
| `divergence <refA> <refB>` | diff of committed dial files (`cells/<alias>/dials/<N>` only) between any two refs — branches, hashes, or `refs/quilt/dials` snapshots | 1 differences / 0 identity |
| `attest <agent> [ref]` | the ONLY write: parentless receipt commit at `refs/quilt/audit/<agent>` carrying `.quilt/audit/<agent>.json`; dates pinned to the position's commit times → idempotent per position | 0 ok / 2 usage |

"Trusted" throughout = **receipted-in-tree**: a commit counts iff a
hook-format receipt naming it is committed at the queried ref and the
commit is reachable from it.

`LEDGER.md` at repo root defines the doubt-ledger convention this layer
queries (markdown grammar borrowed from SuperInstance/doubt-ledger's JSON
store).

## FAIL-first evidence

- RED against pristine main (no `.quilt/bin/quilt-query`): `0/3 pins,
  3 checks fail` — `pins/failfirst-w4q.log`.
- GREEN after implementation: `3/3 pins, 24/24 checks` —
  `pins/pins-w4q-final.log`.
- No regression: `tests/pins_quiltgit.sh` still `6/6 pins, 23/23 checks`.

## Honest limits (7)

1. This layer audits which receipts **exist** and which positions an
   auditor **claimed** to cover — never whether the receipted claims are
   true.
2. Receipts are visible only once **committed**; working-tree journal is
   invisible (deliberate — "trusted" means receipted-in-tree).
3. Attestations are **claims by whoever can write refs locally** — no
   signature or identity verification (signature work belongs to other
   lanes; format-level trust only).
4. Anchor semantics are ancestor-based: a **rebased history silently
   invalidates old audit positions** (they become unreachable → everything
   reads unaudited — fails loud, not silently stale).
5. `coverage` path matching is **substring, either direction** — no path-
   component algebra; `cells/a` matches `cells/ab`. Use precise paths.
6. The layer trusts the **receipt format**, not its provenance: a
   hand-written receipt JSON committed to the tree is indistinguishable
   from a hook-written one.
7. **No wall-clock semantics**: `ts` fields are commit times of positions;
   the layer cannot express "audited within the last week" — by doctrine.

## Deliberately not built

- No ranking/severity for ledger entries (doubt-ledger honest limit #1
  applies verbatim).
- No signature verification on attestations (waits on the signature
  lane; limits #3/#6 state the exposure plainly).
- No server/daemon — the CLI is the whole API; composition happens
  through git itself.
