#!/bin/sh
# pins_adsr.sh — pins for .quilt/bin/quilt-adsr (ADSR envelope evaluator).
# Canonical envelope: A=2 D=2 S=0.5 R=2 HOLD=4 PEAK=1  ->  total 10 ticks
# (value at tick t = envelope at the START of tick t; the release ramp
#  reaches 0 exactly at t=total, one past the last printed tick)
#   t: 0     1     2    3     4     5     6     7     8     9
#   v: 0   0.5     1  0.75   0.5   0.5   0.5   0.5   0.5  0.25
# FAIL-first culture: run this before the tool exists -> every check RED.
set -u
BIN=.quilt/bin/quilt-adsr
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; }

# P1 attack ramp midpoint
v=$($BIN 2 2 0.5 2 4 1.0 1 2>/dev/null)
[ "$v" = "0.5" ] && ok P1-attack-mid || bad "P1-attack-mid (got '$v')"

# P2 attack->decay boundary hits peak
v=$($BIN 2 2 0.5 2 4 1.0 2 2>/dev/null)
[ "$v" = "1" ] && ok P2-peak-boundary || bad "P2-peak-boundary (got '$v')"

# P3 decay midpoint (linear peak->sustain)
v=$($BIN 2 2 0.5 2 4 1.0 3 2>/dev/null)
[ "$v" = "0.75" ] && ok P3-decay-mid || bad "P3-decay-mid (got '$v')"

# P4 sustain flat across the whole hold window
flat=1
for t in 4 5 6 7; do
  v=$($BIN 2 2 0.5 2 4 1.0 $t 2>/dev/null)
  [ "$v" = "0.5" ] || { flat=0; bad "P4-sustain-flat t=$t (got '$v')"; }
done
[ "$flat" = 1 ] && ok P4-sustain-flat

# P5 release ramp start + ramp end; one-past-total is zero
v=$($BIN 2 2 0.5 2 4 1.0 8 2>/dev/null)
[ "$v" = "0.5" ] && ok P5-release-start || bad "P5-release-start (got '$v')"
v=$($BIN 2 2 0.5 2 4 1.0 9 2>/dev/null)
[ "$v" = "0.25" ] && ok P5-release-end || bad "P5-release-end (got '$v')"
v=$($BIN 2 2 0.5 2 4 1.0 10 2>/dev/null)
[ "$v" = "0" ] && ok P5-past-end-zero || bad "P5-past-end-zero (got '$v')"

# P6 whole-curve mode: exactly `total` lines, first/last values
# (last printed tick t=9 = release ramp at u=1 -> S*PEAK*(1-1/2) = 0.25)
curve=$($BIN 2 2 0.5 2 4 1.0 2>/dev/null)
n=$(printf '%s\n' "$curve" | wc -l)
first=$(printf '%s\n' "$curve" | sed -n 1p)
last=$(printf '%s\n' "$curve" | sed -n 10p)
[ "$n" = 10 ] && [ "$first" = "0" ] && [ "$last" = "0.25" ] \
  && ok P6-curve-shape || bad "P6-curve-shape (n=$n first=$first last=$last)"

# P7 zero-length attack is skipped, not an error (A=0, PEAK=2)
v=$($BIN 0 2 0.5 1 1 2 0 2>/dev/null)
[ "$v" = "2" ] && ok P7-zero-attack || bad "P7-zero-attack (got '$v')"

# P8 refusal: sustain level outside [0,1] is REFUSED with a reason, exit 2
msg=$($BIN 2 2 1.5 2 4 1.0 0 2>&1); rc=$?
[ $rc -eq 2 ] && printf '%s' "$msg" | grep -q "sustain level" \
  && ok P8-refuse-bad-sustain || bad "P8-refuse-bad-sustain (rc=$rc msg='$msg')"

# P9 CANARY (RED states demonstrated in pins/failfirst-adsr.log and
# pins-adsr-final.log): the suite can fail — wrong expectations must FAIL.
v=$($BIN 2 2 0.5 2 4 1.0 1 2>/dev/null)
[ "$v" = "0.6" ] && bad "P9-canary (wrong expectation passed!)" || ok P9-canary-red-demonstrated

echo "pins_adsr: $pass pass / $fail fail"
[ $fail -eq 0 ]
