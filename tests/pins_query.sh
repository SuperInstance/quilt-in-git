#!/usr/bin/env bash
# tests/pins_query.sh — FAIL-first pin harness for the wave-4 query layer.
#
# Plain bash + git + awk + sed. No bats, no network. Mirrors
# tests/pins_quiltgit.sh: every pin runs in its own scratch repo under /tmp
# so pins cannot leak state into each other.
#
#   Q1  trusted-but-unaudited — lists receipted commits not covered by any
#       auditor attestation (refs/quilt/audit/*), is-ancestor order,
#       rev-list position order; attest writes a parentless, idempotent
#       receipt commit; --anchor <rev> scopes the audit position; rc=1 when
#       nothing is unaudited; queries never write refs.
#   Q2  coverage — intersects a doubt-ledger needle with receipted commits;
#       reads LEDGER.md from the COMMITTED tree only (dirty working copy is
#       invisible); rc=1 no entries, rc=2 no LEDGER.md at ref.
#   Q3  divergence — diffs the committed dial files between any two refs
#       (branch, hash, or refs/quilt/dials snapshot); rc=1 on differences,
#       rc=0 on identity; body/links/dial-0..15-only filter.
#
# Exit 0 iff all three pin verdicts are PASS.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d /tmp/quilt-qpins-XXXXXX)"
QQ="$SRC/.quilt/bin/quilt-query"

PASS=0
FAIL=0
FAILS=" "          # space-padded list of failed check ids, e.g. " Q1a Q2c "
KEEP_SCRATCH=0

say() { printf '%s\n' "$*"; }
ok()  { PASS=$((PASS + 1)); say "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); KEEP_SCRATCH=1; FAILS="$FAILS$1 "; say "FAIL $1"; }

count_lines() {    # count_lines <file>
  if [ -f "$1" ]; then wc -l < "$1" | tr -d '[:space:]'; else echo 0; fi
}

# run_qq <repo> <args...>: invoke quilt-query inside <repo>.
run_qq() { # returns rc; stdout captured by caller
  local d=$1; shift
  ( cd "$d" && "$QQ" "$@" )
}

# listed <output> <short>: true iff <short> appears in column 1 of a
# non-comment data line.
listed() {
  printf '%s\n' "$1" | grep -v '^#' | awk '{print $1}' | grep -qxF "$2"
}

# data_lines <output>: number of non-comment, non-blank output lines.
data_lines() {
  printf '%s\n' "$1" | grep -v '^#' | grep -c .
}

# new_repo <name>: fresh git repo with the .quilt runtime committed and
# activated — identical to the pins_quiltgit.sh fixture.
new_repo() {
  local d="$SCRATCH/$1"
  git init -q "$d"                                                || return 1
  git -C "$d" config user.email pins@quilt.local                  || return 1
  git -C "$d" config user.name  quilt-pins                        || return 1
  git -C "$d" config commit.gpgsign false                         || return 1
  cp -R "$SRC/.quilt" "$d/.quilt"                                 || return 1
  git -C "$d" add -A                                              || return 1
  git -C "$d" commit -qm "skeleton: quilt runtime"                || return 1
  ( cd "$d" && ./.quilt/bin/quilt-init ) >/dev/null 2>&1          || return 1
  echo "$d"
}

# seed_cell <repo> <alias>: full dials/{0..15} (all 0.0) + body, committed.
seed_cell() {
  local repo=$1 alias=$2 i
  mkdir -p "$repo/cells/$alias/dials"
  echo "seed $alias" > "$repo/cells/$alias/body"
  for i in $(seq 0 15); do echo 0.0 > "$repo/cells/$alias/dials/$i"; done
  git -C "$repo" add cells
  git -C "$repo" commit -qm "cells: seed $alias"
}

# fold_journal <repo>: commit the .quilt journal so receipts land in history.
fold_journal() {
  git -C "$1" add .quilt && git -C "$1" commit -qm "journal"
}

# build_dials_ref <repo> <srcref>: orphan commit holding only the
# cells/<alias>/dials/<N> blobs of <srcref>; parked at refs/quilt/dials.
build_dials_ref() { # build_dials_ref <repo> <srcref>
  local d=$1 src=$2 GD IDX f sha T C
  GD=$(cd "$d/.git" && pwd)
  IDX=$(mktemp "$GD/q3idx.XXXXXX")
  GIT_INDEX_FILE=$IDX git -C "$d" read-tree --empty
  for f in $(git -C "$d" ls-tree -r --name-only "$src" -- cells/ \
             | awk '/\/dials\/[0-9]+$/'); do
    sha=$(git -C "$d" rev-parse "$src:$f")
    GIT_INDEX_FILE=$IDX git -C "$d" update-index --add \
      --cacheinfo "100644,$sha,$f"
  done
  T=$(GIT_INDEX_FILE=$IDX git -C "$d" write-tree)
  rm -f "$IDX"
  C=$(printf 'dials snapshot %s\n' "$src" | git -C "$d" commit-tree "$T")
  git -C "$d" update-ref refs/quilt/dials "$C"
}

# ---------------------------------------------------------------- Q1
pin_q1() {
  local d out rc seed_short tick_short refs_before refs_after tip1 tip2
  if ! d=$(new_repo q1); then bad "Q1-0 setup (quilt-init runnable?)"; return; fi
  [ -x "$QQ" ] || { bad "Q1-0 quilt-query missing/not executable"; return; }

  seed_cell "$d" a
  seed_short=$(git -C "$d" rev-parse --short HEAD)
  fold_journal "$d"
  ( cd "$d" && ./.quilt/bin/quilt-tick a 1 0.9 ) >/dev/null 2>&1 \
    || { bad "Q1-0 tick failed"; return; }
  tick_short=$(git -C "$d" rev-parse --short HEAD)
  fold_journal "$d"   # C4: HEAD — receipts for seed + tick committed

  out=$(run_qq "$d" trusted-but-unaudited); rc=$?
  if [ "$rc" -eq 0 ]; then ok "Q1a trusted-but-unaudited rc=0 (unaudited results exist)"
  else bad "Q1a rc=$rc (want 0): $out"; fi
  if listed "$out" "$seed_short"; then ok "Q1b seed commit listed"
  else bad "Q1b seed commit $seed_short not listed: $out"; fi
  if listed "$out" "$tick_short"; then ok "Q1c tick commit listed"
  else bad "Q1c tick commit $tick_short not listed: $out"; fi
  if [ "$(data_lines "$out")" -eq 2 ]; then ok "Q1d exactly 2 data lines"
  else bad "Q1d data lines = $(data_lines "$out") (want 2): $out"; fi

  if out=$(run_qq "$d" attest auditor1 HEAD~2); rc=$?; [ "$rc" -eq 0 ]; then
    ok "Q1e attest auditor1 HEAD~2 rc=0"
  else
    bad "Q1e attest rc=$rc: $out"
  fi
  if git -C "$d" rev-parse --verify --quiet refs/quilt/audit/auditor1 >/dev/null; then
    ok "Q1f refs/quilt/audit/auditor1 resolves"
  else
    bad "Q1f audit ref missing"
  fi

  out=$(run_qq "$d" trusted-but-unaudited); rc=$?
  if listed "$out" "$tick_short" && ! listed "$out" "$seed_short"; then
    ok "Q1g post-attest: tick listed, seed covered"
  else
    bad "Q1g post-attest listing wrong (rc=$rc): $out"
  fi

  out=$(run_qq "$d" trusted-but-unaudited --anchor HEAD); rc=$?
  if [ "$rc" -eq 1 ] && [ "$(data_lines "$out")" -eq 0 ]; then
    ok "Q1h --anchor HEAD rc=1, zero data lines (all audited)"
  else
    bad "Q1h --anchor HEAD rc=$rc lines=$(data_lines "$out"): $out"
  fi

  refs_before=$(git -C "$d" for-each-ref)
  out=$(run_qq "$d" trusted-but-unaudited); rc=$?
  refs_after=$(git -C "$d" for-each-ref)
  if [ "$refs_before" = "$refs_after" ]; then
    ok "Q1i queries are read-only (for-each-ref unchanged)"
  else
    bad "Q1i a query mutated refs"
  fi

  tip1=$(git -C "$d" rev-parse refs/quilt/audit/auditor1)
  out=$(run_qq "$d" attest auditor1 HEAD~2); rc=$?
  tip2=$(git -C "$d" rev-parse refs/quilt/audit/auditor1)
  if [ "$rc" -eq 0 ] && [ "$tip1" = "$tip2" ]; then
    ok "Q1j re-attest same position is idempotent (same tip $tip1)"
  else
    bad "Q1j re-attest moved the tip ($tip1 -> $tip2, rc=$rc)"
  fi
}

# ---------------------------------------------------------------- Q2
pin_q2() {
  local d out rc tick_short
  if ! d=$(new_repo q2); then bad "Q2-0 setup (quilt-init runnable?)"; return; fi
  [ -x "$QQ" ] || { bad "Q2-0 quilt-query missing/not executable"; return; }

  seed_cell "$d" a
  fold_journal "$d"
  ( cd "$d" && ./.quilt/bin/quilt-tick a 4 0.3 ) >/dev/null 2>&1 \
    || { bad "Q2-0 tick failed"; return; }
  tick_short=$(git -C "$d" rev-parse --short HEAD)
  fold_journal "$d"

  cat > "$d/LEDGER.md" <<EOF
# doubt ledger (quilt-in-git convention)

- doubt a1b2c3 | path: cells/a | stopped: watch.log line delta | covered_by: receipt $tick_short | revisit: casey-merge | status: open
- doubt d4e5f6 | path: infra/ci | stopped: runner audit | covered_by: ci logs | revisit: incident | status: open
EOF
  git -C "$d" add LEDGER.md && git -C "$d" commit -qm "ledger: seed" \
    || { bad "Q2-0 ledger commit failed"; return; }

  out=$(run_qq "$d" coverage cells/a); rc=$?
  if [ "$rc" -eq 0 ]; then ok "Q2a coverage cells/a rc=0"
  else bad "Q2a rc=$rc: $out"; fi
  if printf '%s\n' "$out" | grep -qF "a1b2c3"; then ok "Q2b entry a1b2c3 reported"
  else bad "Q2b no a1b2c3 in: $out"; fi
  if ! printf '%s\n' "$out" | grep -qF "d4e5f6"; then ok "Q2c entry d4e5f6 (other path) absent"
  else bad "Q2c d4e5f6 leaked into cells/a coverage: $out"; fi
  if printf '%s\n' "$out" | grep -qF "covered-by:a1b2c3"; then
    ok "Q2d receipted commit marked covered-by:a1b2c3"
  else
    bad "Q2d no covered-by:a1b2c3 in: $out"
  fi

  out=$(run_qq "$d" coverage cells/zzz); rc=$?
  if [ "$rc" -eq 1 ]; then ok "Q2e coverage cells/zzz rc=1 (no entries)"
  else bad "Q2e rc=$rc (want 1): $out"; fi

  printf '%s\n' "- doubt ffffff | path: cells/a | stopped: dirty | covered_by: none | revisit: never | status: open" >> "$d/LEDGER.md"
  out=$(run_qq "$d" coverage cells/a); rc=$?
  if [ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -qF "ffffff"; then
    ok "Q2f dirty working-tree LEDGER.md invisible (no ffffff)"
  else
    bad "Q2f dirty ledger leaked (rc=$rc): $out"
  fi

  out=$(run_qq "$d" coverage cells/a --ref HEAD~1); rc=$?
  if [ "$rc" -eq 2 ]; then ok "Q2g --ref HEAD~1 (no LEDGER.md) rc=2"
  else bad "Q2g rc=$rc (want 2): $out"; fi
}

# ---------------------------------------------------------------- Q3
pin_q3() {
  local d out rc qA qB pa pb
  if ! d=$(new_repo q3); then bad "Q3-0 setup (quilt-init runnable?)"; return; fi
  [ -x "$QQ" ] || { bad "Q3-0 quilt-query missing/not executable"; return; }

  seed_cell "$d" a
  seed_cell "$d" b
  fold_journal "$d"
  qA=$(git -C "$d" rev-parse HEAD)
  ( cd "$d" && ./.quilt/bin/quilt-tick a 3 0.7 ) >/dev/null 2>&1 \
    || { bad "Q3-0 tick a failed"; return; }
  ( cd "$d" && ./.quilt/bin/quilt-tick b 9 0.3 ) >/dev/null 2>&1 \
    || { bad "Q3-0 tick b failed"; return; }
  fold_journal "$d"
  qB=$(git -C "$d" rev-parse HEAD)

  out=$(run_qq "$d" divergence "$qA" "$qB"); rc=$?
  if [ "$rc" -eq 1 ]; then ok "Q3a divergence qA qB rc=1 (differences found)"
  else bad "Q3a rc=$rc (want 1): $out"; fi
  if printf '%s\n' "$out" | grep -qF "cells/a/dials/3:"; then ok "Q3b cells/a/dials/3 reported"
  else bad "Q3b no cells/a/dials/3 in: $out"; fi
  if printf '%s\n' "$out" | grep -qF "cells/b/dials/9:"; then ok "Q3c cells/b/dials/9 reported"
  else bad "Q3c no cells/b/dials/9 in: $out"; fi
  if ! printf '%s\n' "$out" | grep -qF "cells/a/dials/0:"; then ok "Q3d unchanged dial 0 not reported"
  else bad "Q3d unchanged dial reported: $out"; fi
  if printf '%s\n' "$out" | grep -qF "cells/a/dials/3: 0.0 -> 0.7"; then
    ok "Q3e value transition 0.0 -> 0.7 shown"
  else
    bad "Q3e no '0.0 -> 0.7' line in: $out"
  fi

  out=$(run_qq "$d" divergence "$qB" "$qB"); rc=$?
  if [ "$rc" -eq 0 ]; then ok "Q3f divergence qB qB rc=0 (identical)"
  else bad "Q3f rc=$rc (want 0): $out"; fi

  build_dials_ref "$d" "$qB"
  pa=$(run_qq "$d" divergence "$qA" "$qB" | grep -v '^#' | cut -d: -f1 | sort)
  pb=$(run_qq "$d" divergence "$qA" refs/quilt/dials | grep -v '^#' | cut -d: -f1 | sort)
  if [ "$pa" = "$pb" ] && [ -n "$pa" ]; then
    ok "Q3g refs/quilt/dials snapshot gives identical dial path set"
  else
    bad "Q3g snapshot path set differs: [$pa] vs [$pb]"
  fi
}

# ---------------------------------------------------------------- main
main() {
  say "# quilt-in-git wave-4 query pins  src=$SRC"
  say "# scratch=$SCRATCH  git=$(git --version | cut -d' ' -f3)"
  say ""
  pin_q1
  pin_q2
  pin_q3
  say ""
  say "# ---- per-pin verdicts ----"
  local v1 v2 v3 n
  case "$FAILS" in *" Q1"*) v1=FAIL;; *) v1=PASS;; esac
  case "$FAILS" in *" Q2"*) v2=FAIL;; *) v2=PASS;; esac
  case "$FAILS" in *" Q3"*) v3=FAIL;; *) v3=PASS;; esac
  say "Q1 trusted-but-unaudited + attest : $v1"
  say "Q2 coverage (LEDGER intersection) : $v2"
  say "Q3 divergence (dial diff)         : $v3"
  n=0
  for v in "$v1" "$v2" "$v3"; do [ "$v" = PASS ] && n=$((n+1)); done
  say ""
  say "PINS: $n/3 pins pass ($PASS checks pass, $FAIL checks fail)"
  if [ "$n" -eq 3 ]; then
    say "PINS: ALL PASS"
    rm -rf "$SCRATCH"
    exit 0
  fi
  say "PINS: FAILURES PRESENT (scratch kept for inspection: $SCRATCH)"
  exit 1
}

main "$@"
