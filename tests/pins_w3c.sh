#!/usr/bin/env bash
# tests/pins_w3c.sh — FAIL-first pin harness for wave 3c:
# bundle air-gap transport + sparse-checkout focus.
#
# Plain bash + git + awk. No bats, no network. Every pin runs in its own
# scratch repo under /tmp (one mktemp -d root, one subdir per pin), so pins
# cannot leak state into each other.
#
#   P13 bundle round-trip — a ticked repo is exported with quilt-export,
#       the original repo is then DESTROYED (the air gap: the bundle file is
#       the only surviving copy), the bundle is cloned and quilt-imported on
#       the far side. Asserts: bundle created; clone works; hooks re-armed
#       (core.hooksPath); the journal (receipts + watch.log) REGENERATED
#       from pure history is byte-identical to the journal carried in the
#       bundle; refs/quilt/* survive; and a fresh tick in the imported clone
#       passes the P1-style receipt + exactly-one-watch-line check.
#   P14 focus — quilt-focus <alias> leaves ONLY cells/<alias>/ + .quilt/ in
#       the worktree (the other cell's body and dials are absent); a focused
#       quilt-tick still commits and the cascade still fires; the OTHER
#       cell's dial 14 carries the new value IN THE INDEX while its worktree
#       file stays absent (git ls-files -s + git cat-file on the staged
#       blob) — the received guarantee that focus is worktree-only.
#   P15 focus --off — the full worktree is restored, values intact, status
#       clean.
#
# Exit 0 iff all three pin verdicts are PASS.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d /tmp/quilt-pins-w3c-XXXXXX)"

PASS=0
FAIL=0
FAILS=" "
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

# new_repo <name>: fresh git repo (branch main) at $SCRATCH/<name> with the
# .quilt runtime from $SRC committed and activated via quilt-init.
new_repo() {
  local d="$SCRATCH/$1"
  git init -q -b main "$d"                                          || return 1
  git -C "$d" config user.email pins@quilt.local                    || return 1
  git -C "$d" config user.name  quilt-pins                          || return 1
  git -C "$d" config commit.gpgsign false                           || return 1
  cp -R "$SRC/.quilt" "$d/.quilt"                                   || return 1
  git -C "$d" add -A                                                || return 1
  git -C "$d" commit -qm "skeleton: quilt runtime"                  || return 1
  ( cd "$d" && ./.quilt/bin/quilt-init ) >/dev/null 2>&1            || return 1
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

# link_cells <repo> <dst> <src> <weight>: dst links src, committed.
link_cells() {
  printf '%s %s\n' "$3" "$4" > "$1/cells/$2/links"
  git -C "$1" add "cells/$2/links"
  git -C "$1" commit -qm "cells: $2 links $3 $4"
}

# ---------------------------------------------------------------- P13
pin_p13() {
  local d bundle imp snap wl full short R st wl0 wl1 sha
  if ! d=$(new_repo p13); then bad "P13-0 setup (quilt-init runnable?)"; return; fi
  seed_cell "$d" a
  seed_cell "$d" b
  link_cells "$d" b a 0.5
  ( cd "$d" && ./.quilt/bin/quilt-tick a 1 0.9 ) >/dev/null 2>&1 \
    || { bad "P13-0 pre-tick a failed"; return; }
  ( cd "$d" && ./.quilt/bin/quilt-tick b 3 0.33 ) >/dev/null 2>&1 \
    || { bad "P13-0 pre-tick b failed"; return; }
  git -C "$d" add .quilt
  git -C "$d" commit -qm "journal" >/dev/null 2>&1
  git -C "$d" update-ref refs/quilt/snap HEAD
  snap=$(git -C "$d" rev-parse HEAD)
  wl=$(count_lines "$d/.quilt/watch.log")
  [ "$wl" -ge 3 ] || { bad "P13-0 expected a ticked watch.log, got $wl lines"; return; }

  bundle="$SCRATCH/p13.bundle"
  if ( cd "$d" && ./.quilt/bin/quilt-export "$bundle" ) >/dev/null 2>&1 \
     && [ -s "$bundle" ]; then
    ok "P13a quilt-export created a bundle"
  else
    bad "P13a quilt-export failed (or empty bundle)"; return
  fi

  rm -rf "$d"
  if [ ! -d "$d" ]; then
    ok "P13b source repo destroyed — the bundle is the only copy (air gap)"
  else
    bad "P13b source repo survived rm -rf"; return
  fi

  imp="$SCRATCH/p13-imported"
  if git clone -q "$bundle" "$imp" >/dev/null 2>&1; then
    ok "P13c far side: git clone from the bundle works"
  else
    bad "P13c clone from bundle failed"; return
  fi
  git -C "$imp" config user.email pins@quilt.local
  git -C "$imp" config user.name  quilt-pins
  git -C "$imp" config commit.gpgsign false

  if ( cd "$imp" && ./.quilt/bin/quilt-import "$bundle" ) >/dev/null 2>&1; then
    ok "P13d quilt-import landed (verify + fetch refs + init + regenerate)"
  else
    bad "P13d quilt-import failed"; return
  fi

  if [ "$(git -C "$imp" config core.hooksPath)" = ".quilt/hooks" ]; then
    ok "P13e hooks re-armed in the imported clone (core.hooksPath)"
  else
    bad "P13e core.hooksPath is '$(git -C "$imp" config core.hooksPath)'"
  fi

  st=$(git -C "$imp" status --porcelain -- .quilt/receipts .quilt/watch.log)
  if [ -z "$st" ]; then
    ok "P13f regenerated journal byte-identical to the carried one (status clean)"
  else
    bad "P13f journal mismatch after regeneration: $st"
  fi
  if [ "$(count_lines "$imp/.quilt/watch.log")" = "$wl" ]; then
    ok "P13g watch.log regenerated with all $wl tick lines"
  else
    bad "P13g watch.log has $(count_lines "$imp/.quilt/watch.log") lines (want $wl)"
  fi
  if [ "$(git -C "$imp" rev-parse refs/quilt/snap 2>/dev/null)" = "$snap" ]; then
    ok "P13h refs/quilt/snap survived the air gap"
  else
    bad "P13h refs/quilt/snap lost or wrong: $(git -C "$imp" rev-parse refs/quilt/snap 2>&1)"
  fi

  wl0=$(count_lines "$imp/.quilt/watch.log")
  if ( cd "$imp" && ./.quilt/bin/quilt-tick a 0 0.42 ) >/dev/null 2>&1; then
    ok "P13i fresh tick commits in the imported clone"
  else
    bad "P13i fresh tick failed in imported clone"; return
  fi
  full=$(git -C "$imp" rev-parse HEAD)
  short=$(git -C "$imp" rev-parse --short HEAD)
  R="$imp/.quilt/receipts/$short.json"
  if [ -f "$R" ] && grep -qF "$full" "$R" && grep -q '"a"' "$R"; then
    ok "P13j P1-style receipt for the fresh tick (full hash + alias)"
  else
    bad "P13j receipt wrong or missing: $R"
  fi
  wl1=$(count_lines "$imp/.quilt/watch.log")
  if [ "$((wl1 - wl0))" -eq 1 ]; then
    ok "P13k watch.log grew by exactly one line ($wl0->$wl1)"
  else
    bad "P13k watch.log delta $wl0->$wl1 (want +1)"
  fi
}

# ---------------------------------------------------------------- P14
pin_p14() {
  local d line sha
  if ! d=$(new_repo p14); then bad "P14-0 setup (quilt-init runnable?)"; return; fi
  seed_cell "$d" a
  seed_cell "$d" b
  link_cells "$d" b a 0.5

  if ( cd "$d" && ./.quilt/bin/quilt-focus a ) >/dev/null 2>&1; then
    ok "P14a quilt-focus a succeeded"
  else
    bad "P14a quilt-focus a failed"; return
  fi

  if [ -f "$d/cells/a/body" ] && [ -f "$d/cells/a/dials/1" ]; then
    ok "P14b focused cell materialized (body + dials)"
  else
    bad "P14b focused cell missing its own files"
  fi
  if [ ! -e "$d/cells/b/body" ]; then
    ok "P14c other cell's body absent from worktree"
  else
    bad "P14c cells/b/body still materialized"
  fi
  if [ ! -e "$d/cells/b/dials/14" ]; then
    ok "P14d other cell's dials absent from worktree"
  else
    bad "P14d cells/b/dials/14 still materialized"
  fi

  if ( cd "$d" && ./.quilt/bin/quilt-tick a 1 0.5 ) >/dev/null 2>&1 \
     && [ "$(git -C "$d" show HEAD:cells/a/dials/1 2>/dev/null | tr -d '[:space:]')" = "0.5" ]; then
    ok "P14e focused quilt-tick commits (dial1=0.5 in HEAD)"
  else
    bad "P14e focused tick failed or value not committed"; return
  fi

  if git -C "$d" log --format=%s | grep -q '^quilt: cascade after'; then
    ok "P14f cascade commit exists (fired under focus)"
  else
    bad "P14f no cascade commit under focus"
  fi

  line=$(git -C "$d" ls-files -s -- cells/b/dials/14)
  sha=$(printf '%s\n' "$line" | awk '{print $2}')
  if [ -n "$sha" ] && [ "$sha" != "" ]; then
    ok "P14g other cell's dial 14 present IN THE INDEX (ls-files -s: $sha)"
  else
    bad "P14g cells/b/dials/14 not in index: '$line'"; return
  fi
  if [ "$(git -C "$d" cat-file -p "$sha" 2>/dev/null | tr -d '[:space:]')" = "0.2500" ]; then
    ok "P14h index blob carries the cascaded value 0.2500 (cat-file)"
  else
    bad "P14h index blob is '$(git -C "$d" cat-file -p "$sha" 2>/dev/null)' (want 0.2500)"
  fi
  if [ ! -e "$d/cells/b/body" ]; then
    ok "P14i focus held: other cell's body still absent after the cascade"
  else
    bad "P14i focus lost: cells/b/body reappeared"
  fi
}

# ---------------------------------------------------------------- P15
pin_p15() {
  local d
  if ! d=$(new_repo p15); then bad "P15-0 setup (quilt-init runnable?)"; return; fi
  seed_cell "$d" a
  seed_cell "$d" b
  link_cells "$d" b a 0.5
  ( cd "$d" && ./.quilt/bin/quilt-tick a 1 0.8 ) >/dev/null 2>&1 \
    || { bad "P15-0 pre-tick failed"; return; }
  [ "$(tr -d '[:space:]' < "$d/cells/b/dials/14")" = "0.4000" ] \
    || { bad "P15-0 cascade did not settle to 0.4000"; return; }

  ( cd "$d" && ./.quilt/bin/quilt-focus a ) >/dev/null 2>&1
  if [ ! -e "$d/cells/b/body" ]; then
    ok "P15a focused: other cell's body absent"
  else
    bad "P15a focus did not remove cells/b/body"; return
  fi

  if ( cd "$d" && ./.quilt/bin/quilt-focus --off ) >/dev/null 2>&1; then
    ok "P15b quilt-focus --off succeeded"
  else
    bad "P15b quilt-focus --off failed"; return
  fi

  if [ -f "$d/cells/b/body" ]; then
    ok "P15c other cell's body restored"
  else
    bad "P15c cells/b/body missing after --off"
  fi
  if [ -f "$d/cells/a/dials/1" ] \
     && [ "$(tr -d '[:space:]' < "$d/cells/a/dials/1")" = "0.8" ]; then
    ok "P15d focused cell intact (dial1=0.8)"
  else
    bad "P15d focused cell damaged by --off"
  fi
  if [ -f "$d/cells/b/dials/14" ] \
     && [ "$(tr -d '[:space:]' < "$d/cells/b/dials/14")" = "0.4000" ]; then
    ok "P15e other cell's cascaded dial restored (0.4000)"
  else
    bad "P15e cells/b/dials/14 not restored to 0.4000"
  fi
  if [ -z "$(git -C "$d" status --porcelain -- cells/)" ]; then
    ok "P15f cells/ clean after --off (no organ lost or altered)"
  else
    bad "P15f cells/ dirty after --off: $(git -C "$d" status --porcelain -- cells/)"
  fi
}

# ---------------------------------------------------------------- main
main() {
  say "# quilt-in-git w3c pins  src=$SRC"
  say "# scratch=$SCRATCH  git=$(git --version | cut -d' ' -f3)"
  say ""
  pin_p13
  pin_p14
  pin_p15
  say ""
  say "# ---- per-pin verdicts ----"
  local v13 v14 v15 n
  case "$FAILS" in *" P13"*) v13=FAIL;; *) v13=PASS;; esac
  case "$FAILS" in *" P14"*) v14=FAIL;; *) v14=PASS;; esac
  case "$FAILS" in *" P15"*) v15=FAIL;; *) v15=PASS;; esac
  say "P13 bundle air-gap round-trip   : $v13"
  say "P14 sparse focus isolates organ : $v14"
  say "P15 focus --off restores body   : $v15"
  n=0
  for v in "$v13" "$v14" "$v15"; do [ "$v" = PASS ] && n=$((n+1)); done
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
