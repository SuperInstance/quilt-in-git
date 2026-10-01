#!/usr/bin/env bash
# tests/pins_quiltgit.sh — FAIL-first pin harness for the quilt-in-git PoC.
#
# Plain bash + git + awk. No bats, no network. Every pin runs in its own
# scratch repo under /tmp (one mktemp -d root, one subdir per pin), so pins
# cannot leak state into each other.
#
#   P1  dial commit  -> .quilt/receipts/<short>.json exists (holds commit
#                       hash + alias) and .quilt/watch.log grows by EXACTLY
#                       one line.
#   P2  freeze       -> dial 15 = 0.8 commits; the NEXT commit touching that
#                       cell is rejected (exit 1, "frozen" in the error,
#                       file/HEAD unchanged).
#   P3  cascade      -> a.dials/1 = 0.9 and b's links say "a 0.5"; ticking a
#                       gives b.dials/14 == 0.45 and a "quilt: cascade after"
#                       commit.
#   P4  rewind       -> change a dial, commit, checkout the previous commit
#                       for cells/<alias>/ -> dial file back to old value.
#   P5  clone        -> in a fresh clone hooks do NOT fire (no receipt, no
#                       watch line); after quilt-init they do.
#   P6  non-cell     -> a README-only commit creates NO receipt and NO
#                       watch.log line.
#   P7  quilt head   -> a dial commit moves refs/quilt/HEAD to that commit;
#                       a non-cell commit does NOT move it.
#   P8  head travels -> refs/quilt/HEAD survives an explicit
#                       '+refs/quilt/*:refs/quilt/*' fetch; a DEFAULT clone
#                       drops it (non-head namespaces) — the limit is
#                       pinned as behavior, not hidden (hooks-vs-data law
#                       from P5, other side).
#   P9  head honest  -> in a repo with zero ticks, .quilt/bin/quilt-head
#                       exits non-zero and says why (never fabricates a
#                       position).
#
# Exit 0 iff all nine pin verdicts are PASS.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d /tmp/quilt-pins-XXXXXX)"

PASS=0
FAIL=0
FAILS=" "          # space-padded list of failed check ids, e.g. " P1a P2c "
KEEP_SCRATCH=0

say() { printf '%s\n' "$*"; }
ok()  { PASS=$((PASS + 1)); say "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); KEEP_SCRATCH=1; FAILS="$FAILS$1 "; say "FAIL $1"; }

count_lines() {    # count_lines <file>
  if [ -f "$1" ]; then wc -l < "$1" | tr -d '[:space:]'; else echo 0; fi
}
count_receipts() { # count_receipts <repo>
  ls -1 "$1/.quilt/receipts" 2>/dev/null | wc -l | tr -d '[:space:]'
}

# new_repo <name>: fresh git repo at $SCRATCH/<name> with the .quilt runtime
# from $SRC committed and activated via ./.quilt/bin/quilt-init.
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
# The commit fires the hooks once (one receipt, one watch line) — pins always
# snapshot baselines AFTER seeding.
seed_cell() {
  local repo=$1 alias=$2 i
  mkdir -p "$repo/cells/$alias/dials"
  echo "seed $alias" > "$repo/cells/$alias/body"
  for i in $(seq 0 15); do echo 0.0 > "$repo/cells/$alias/dials/$i"; done
  git -C "$repo" add cells
  git -C "$repo" commit -qm "cells: seed $alias"
}

# ---------------------------------------------------------------- P1
pin_p1() {
  local d
  if ! d=$(new_repo p1); then bad "P1-0 setup (quilt-init runnable?)"; return; fi
  seed_cell "$d" a
  local wl_before
  wl_before=$(count_lines "$d/.quilt/watch.log")

  if ( cd "$d" && echo 0.42 > cells/a/dials/0 && git add cells/a/dials/0 \
       && git commit -qm "tick: a dial0=0.42" ) >/dev/null 2>&1; then
    ok "P1a dial commit accepted"
  else
    bad "P1a dial commit failed"; return
  fi

  local full short R wl_after last
  full=$(git -C "$d" rev-parse HEAD)
  short=$(git -C "$d" rev-parse --short HEAD)
  R="$d/.quilt/receipts/$short.json"
  if [ -f "$R" ]; then ok "P1b receipt exists (.quilt/receipts/$short.json)"
  else bad "P1b receipt missing: $R"; fi
  if grep -qF "$full" "$R" 2>/dev/null; then ok "P1c receipt contains commit hash"
  else bad "P1c receipt lacks commit hash"; fi
  if grep -q '"a"' "$R" 2>/dev/null; then ok "P1d receipt contains alias a"
  else bad "P1d receipt lacks alias a"; fi
  wl_after=$(count_lines "$d/.quilt/watch.log")
  if [ "$((wl_after - wl_before))" -eq 1 ]; then
    ok "P1e watch.log grew by exactly one line ($wl_before->$wl_after)"
  else
    bad "P1e watch.log delta $wl_before->$wl_after (want +1)"
  fi
  last=$(tail -n 1 "$d/.quilt/watch.log" 2>/dev/null)
  case "$last" in
    tick\ *) ok "P1f watch line starts with 'tick' ($last)" ;;
    *)       bad "P1f malformed watch line: '$last'" ;;
  esac
}

# ---------------------------------------------------------------- P2
pin_p2() {
  local d
  if ! d=$(new_repo p2); then bad "P2-0 setup (quilt-init runnable?)"; return; fi
  seed_cell "$d" fz

  if ( cd "$d" && ./.quilt/bin/quilt-tick fz 15 0.8 ) >/dev/null 2>&1; then
    ok "P2a freeze commit (dial15=0.8) accepted"
  else
    bad "P2a freeze commit rejected"; return
  fi
  local head_frozen headv out rc
  head_frozen=$(git -C "$d" rev-parse HEAD)

  out=$( cd "$d" && ./.quilt/bin/quilt-tick fz 1 0.7 2>&1 ); rc=$?
  if [ "$rc" -ne 0 ]; then ok "P2b next commit touching cell rejected (rc=$rc)"
  else bad "P2b frozen-cell commit NOT rejected (rc=0)"; fi
  case "$out" in
    *frozen*) ok "P2c error mentions frozen" ;;
    *)        bad "P2c error lacks 'frozen': $out" ;;
  esac
  if [ "$(tr -d '[:space:]' < "$d/cells/fz/dials/1")" = "0.7" ]; then
    ok "P2d dial file unchanged by rejected commit (still 0.7 as written)"
  else
    bad "P2d dial file mangled: $(cat "$d/cells/fz/dials/1" 2>/dev/null)"
  fi
  headv=$(git -C "$d" show HEAD:cells/fz/dials/1 2>/dev/null | tr -d '[:space:]')
  if [ "$headv" = "0.0" ]; then ok "P2e committed dial1 still 0.0"
  else bad "P2e committed dial1 is '$headv' (want 0.0)"; fi
  if [ "$(git -C "$d" rev-parse HEAD)" = "$head_frozen" ]; then
    ok "P2f no new commit was created"
  else
    bad "P2f HEAD moved despite rejection"
  fi
}

# ---------------------------------------------------------------- P3
pin_p3() {
  local d v
  if ! d=$(new_repo p3); then bad "P3-0 setup (quilt-init runnable?)"; return; fi
  seed_cell "$d" a
  seed_cell "$d" b
  printf 'a 0.5\n' > "$d/cells/b/links"
  git -C "$d" add cells/b/links
  git -C "$d" commit -qm "cells: b links a 0.5" || { bad "P3a links commit failed"; return; }

  if ( cd "$d" && ./.quilt/bin/quilt-tick a 1 0.9 ) >/dev/null 2>&1; then
    ok "P3a tick a dial1=0.9 committed"
  else
    bad "P3a tick a dial1=0.9 failed"; return
  fi
  v=$(tr -d '[:space:]' < "$d/cells/b/dials/14")
  if awk -v x="$v" 'BEGIN{exit !(x+0 == 0.45)}'; then
    ok "P3b b.dials/14 == $v (== 0.45)"
  else
    bad "P3b b.dials/14 == '$v' (want 0.45)"
  fi
  if git -C "$d" log --format=%s | grep -q '^quilt: cascade after'; then
    ok "P3c 'quilt: cascade after' commit exists"
  else
    bad "P3c no 'quilt: cascade after' commit"
  fi
}

# ---------------------------------------------------------------- P4
pin_p4() {
  local d prev
  if ! d=$(new_repo p4); then bad "P4-0 setup (quilt-init runnable?)"; return; fi
  seed_cell "$d" a

  ( cd "$d" && ./.quilt/bin/quilt-tick a 7 0.11 ) >/dev/null 2>&1 \
    || { bad "P4a first tick failed"; return; }
  prev=$(git -C "$d" rev-parse HEAD)
  ( cd "$d" && ./.quilt/bin/quilt-tick a 7 0.99 ) >/dev/null 2>&1 \
    || { bad "P4b second tick failed"; return; }
  if [ "$(tr -d '[:space:]' < "$d/cells/a/dials/7")" = "0.99" ]; then
    ok "P4c new dial value 0.99 committed"
  else
    bad "P4c dial not at 0.99"; return
  fi

  git -C "$d" checkout -q "$prev" -- cells/a/
  if [ "$(tr -d '[:space:]' < "$d/cells/a/dials/7")" = "0.11" ]; then
    ok "P4d rewind (checkout prev -- cells/a/) restores 0.11"
  else
    bad "P4d rewind got '$(cat "$d/cells/a/dials/7" 2>/dev/null)' (want 0.11)"
  fi
}

# ---------------------------------------------------------------- P5
pin_p5() {
  local d c wl0 rc0 s1 s2
  if ! d=$(new_repo p5); then bad "P5-0 setup (quilt-init runnable?)"; return; fi
  seed_cell "$d" a
  # fold the journal into history so the clone carries receipts + watch.log
  git -C "$d" add .quilt && git -C "$d" commit -qm "journal" >/dev/null 2>&1

  c="$SCRATCH/p5-clone"
  git clone -q "$d" "$c" || { bad "P5a clone failed"; return; }
  git -C "$c" config user.email pins@quilt.local
  git -C "$c" config user.name  quilt-pins
  git -C "$c" config commit.gpgsign false

  wl0=$(count_lines "$c/.quilt/watch.log")
  rc0=$(count_receipts "$c")

  ( cd "$c" && echo 0.5 > cells/a/dials/2 && git add cells/a/dials/2 \
    && git commit -qm "tick: clone pre-init" ) >/dev/null 2>&1 \
    || { bad "P5b pre-init commit failed"; return; }
  s1=$(git -C "$c" rev-parse --short HEAD)
  if [ ! -f "$c/.quilt/receipts/$s1.json" ] \
     && [ "$(count_receipts "$c")" = "$rc0" ] \
     && [ "$(count_lines "$c/.quilt/watch.log")" = "$wl0" ]; then
    ok "P5c fresh clone: no receipt, no watch line (hooks inert)"
  else
    bad "P5c hooks fired in fresh clone before quilt-init"
  fi

  ( cd "$c" && ./.quilt/bin/quilt-init ) >/dev/null 2>&1 \
    || { bad "P5d quilt-init failed in clone"; return; }
  if [ "$(git -C "$c" config core.hooksPath)" = ".quilt/hooks" ]; then
    ok "P5e quilt-init set core.hooksPath=.quilt/hooks"
  else
    bad "P5e core.hooksPath is '$(git -C "$c" config core.hooksPath)'"
  fi

  ( cd "$c" && echo 0.6 > cells/a/dials/3 && git add cells/a/dials/3 \
    && git commit -qm "tick: clone post-init" ) >/dev/null 2>&1 \
    || { bad "P5f post-init commit failed"; return; }
  s2=$(git -C "$c" rev-parse --short HEAD)
  if [ -f "$c/.quilt/receipts/$s2.json" ]; then
    ok "P5g receipt appears after quilt-init ($s2.json)"
  else
    bad "P5g no receipt after quilt-init"
  fi
  if [ "$(count_lines "$c/.quilt/watch.log")" -gt "$wl0" ]; then
    ok "P5h watch.log grew after quilt-init"
  else
    bad "P5h watch.log did not grow after quilt-init"
  fi
}

# ---------------------------------------------------------------- P6
pin_p6() {
  local d wl0 rc0
  if ! d=$(new_repo p6); then bad "P6-0 setup (quilt-init runnable?)"; return; fi
  seed_cell "$d" a
  wl0=$(count_lines "$d/.quilt/watch.log")
  rc0=$(count_receipts "$d")

  ( cd "$d" && echo "# scratch readme" > README.md && git add README.md \
    && git commit -qm "docs: readme" ) >/dev/null 2>&1 \
    || { bad "P6a readme commit failed"; return; }

  if [ "$(count_receipts "$d")" = "$rc0" ]; then
    ok "P6b non-cell commit created NO receipt"
  else
    bad "P6b receipt created by non-cell commit"
  fi
  if [ "$(count_lines "$d/.quilt/watch.log")" = "$wl0" ]; then
    ok "P6c non-cell commit added NO watch.log line"
  else
    bad "P6c watch.log grew on non-cell commit"
  fi
}

# ---------------------------------------------------------------- P7
pin_p7() {
  local d tick1 tick2
  if ! d=$(new_repo p7); then bad "P7-0 setup (quilt-init runnable?)"; return; fi
  seed_cell "$d" a

  ( cd "$d" && ./.quilt/bin/quilt-tick a 0 0.42 ) >/dev/null 2>&1 \
    || { bad "P7a tick failed"; return; }
  tick1=$(git -C "$d" rev-parse HEAD)
  if [ "$(git -C "$d" rev-parse --verify -q refs/quilt/HEAD)" = "$tick1" ]; then
    ok "P7b refs/quilt/HEAD == tick commit"
  else
    bad "P7b refs/quilt/HEAD does not match tick commit"
  fi

  ( cd "$d" && echo "# docs" > README.md && git add README.md \
      && git commit -qm "docs: readme" ) >/dev/null 2>&1 \
    || { bad "P7c docs commit failed"; return; }
  if [ "$(git -C "$d" rev-parse --verify -q refs/quilt/HEAD)" = "$tick1" ]; then
    ok "P7d non-cell commit did NOT move the quilt head"
  else
    bad "P7d non-cell commit moved refs/quilt/HEAD"
  fi

  tick2=$(git -C "$d" rev-parse HEAD)
  if [ "$tick2" != "$tick1" ]; then
    ok "P7e sanity: HEAD advanced on docs commit"
  else
    bad "P7e sanity: HEAD did not advance"
  fi

  out=$(cd "$d" && ./.quilt/bin/quilt-head 2>&1) \
    || { bad "P7f quilt-head exited non-zero on ticked repo: $out"; return; }
  case "$out" in
    "$(git -C "$d" rev-parse --short "$tick1")"*) ok "P7g quilt-head reports the tick ($out)";;
    *) bad "P7g quilt-head output wrong: $out";;
  esac
}

# ---------------------------------------------------------------- P8
pin_p8() {
  local d c ref_main
  if ! d=$(new_repo p8); then bad "P8-0 setup (quilt-init runnable?)"; return; fi
  seed_cell "$d" a
  ( cd "$d" && ./.quilt/bin/quilt-tick a 3 0.7 ) >/dev/null 2>&1 \
    || { bad "P8a tick failed"; return; }
  ref_main=$(git -C "$d" rev-parse --verify -q refs/quilt/HEAD) \
    || { bad "P8b no refs/quilt/HEAD after tick"; return; }

  git clone -q "$d" "$SCRATCH/p8clone" 2>/dev/null \
    || { bad "P8c clone failed"; return; }
  # Honest limit (stated in README): a DEFAULT clone fetches only
  # refs/heads/* + tags — non-head namespaces like refs/quilt/* are
  # dropped. The pointer travels via explicit refspec or git-bundle.
  if ! git -C "$SCRATCH/p8clone" rev-parse --verify -q refs/quilt/HEAD >/dev/null; then
    ok "P8d default clone drops non-head namespaces (limit is real, not hidden)"
  else
    bad "P8d default clone unexpectedly kept refs/quilt/HEAD"
  fi
  git -C "$SCRATCH/p8clone" fetch -q origin '+refs/quilt/*:refs/quilt/*' 2>/dev/null \
    || { bad "P8e refspec fetch failed"; return; }
  if [ "$(git -C "$SCRATCH/p8clone" rev-parse --verify -q refs/quilt/HEAD)" = "$ref_main" ]; then
    ok "P8f explicit refspec restores the quilt head, byte-equal"
  else
    bad "P8f quilt head wrong/absent after refspec fetch"
  fi
}

# ---------------------------------------------------------------- P9
pin_p9() {
  local d rc out
  if ! d=$(new_repo p9); then bad "P9-0 setup (quilt-init runnable?)"; return; fi
  # seed_cell commits a cells/ path -> that IS a tick. For the zero-tick
  # honesty pin, use a repo whose only commit is the runtime skeleton.
  rc=0
  out=$(cd "$d" && ./.quilt/bin/quilt-head 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    ok "P9a quilt-head refuses on zero-tick repo (exit $rc)"
  else
    bad "P9a quilt-head succeeded on zero-tick repo: $out"
  fi
  case "$out" in
    *"no ticks"*) ok "P9b refusal names the reason: $out";;
    *) bad "P9b refusal does not name the reason: $out";;
  esac
}

# ---------------------------------------------------------------- main
main() {
  say "# quilt-in-git pins  src=$SRC"
  say "# scratch=$SCRATCH  git=$(git --version | cut -d' ' -f3)"
  say ""
  pin_p1
  pin_p2
  pin_p3
  pin_p4
  pin_p5
  pin_p6
  pin_p7
  pin_p8
  pin_p9
  say ""
  say "# ---- per-pin verdicts ----"
  local v1 v2 v3 v4 v5 v6 v7 v8 v9 n
  case "$FAILS" in *" P1"*) v1=FAIL;; *) v1=PASS;; esac
  case "$FAILS" in *" P2"*) v2=FAIL;; *) v2=PASS;; esac
  case "$FAILS" in *" P3"*) v3=FAIL;; *) v3=PASS;; esac
  case "$FAILS" in *" P4"*) v4=FAIL;; *) v4=PASS;; esac
  case "$FAILS" in *" P5"*) v5=FAIL;; *) v5=PASS;; esac
  case "$FAILS" in *" P6"*) v6=FAIL;; *) v6=PASS;; esac
  case "$FAILS" in *" P7"*) v7=FAIL;; *) v7=PASS;; esac
  case "$FAILS" in *" P8"*) v8=FAIL;; *) v8=PASS;; esac
  case "$FAILS" in *" P9"*) v9=FAIL;; *) v9=PASS;; esac
  say "P1 receipt+watch on dial commit : $v1"
  say "P2 freeze enforcement          : $v2"
  say "P3 cascade                      : $v3"
  say "P4 rewind                       : $v4"
  say "P5 clone needs quilt-init       : $v5"
  say "P6 non-cell commit silent       : $v6"
  say "P7 refs/quilt/HEAD tracks ticks : $v7"
  say "P8 quilt head travels with clone: $v8"
  say "P9 zero-tick head is honest     : $v9"
  n=0
  for v in "$v1" "$v2" "$v3" "$v4" "$v5" "$v6" "$v7" "$v8" "$v9"; do [ "$v" = PASS ] && n=$((n+1)); done
  say ""
  say "PINS: $n/9 pins pass ($PASS checks pass, $FAIL checks fail)"
  if [ "$n" -eq 9 ]; then
    say "PINS: ALL PASS"
    rm -rf "$SCRATCH"
    exit 0
  fi
  say "PINS: FAILURES PRESENT (scratch kept for inspection: $SCRATCH)"
  exit 1
}

main "$@"
