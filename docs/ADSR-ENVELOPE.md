# ADSR envelope patch — Tier-0 brick (abstraction ladder)

`quilt-adsr A D S R HOLD PEAK [t]` evaluates a piecewise-linear ADSR
envelope over `N = A+D+HOLD+R` ticks — the DAW read of a quilt dial:
attack ramp `0→PEAK` over A ticks, decay ramp `PEAK→S·PEAK` over D
ticks (S = sustain **level** in [0,1]), sustain at `S·PEAK` for HOLD
ticks, release ramp `S·PEAK→0` over R ticks.

Conventions (pinned, not assumed):

- Value at tick `t` = envelope at the **start** of the tick. The release
  ramp reaches 0 exactly at `t = N` (one past the last printed curve
  line). Verified: canonical `2 2 0.5 2 4 1.0` curve is
  `0, 0.5, 1, 0.75, 0.5, 0.5, 0.5, 0.5, 0.5, 0.25`.
- Zero-length segments are **skipped, not errors** (`A=0` starts at
  peak). Pinned by P7.
- Invalid args are **REFUSED with a reason**, exit 2 (refusal policy).
  Pinned by P8.
- Whole-curve mode (no `t`) prints `N` lines, one value per tick —
  feed it into `quilt-tick` to play a dial through the envelope.

Honest limits: linear segments only (no exponential/curve shapes);
envelope is a function of tick index, not wall time (no tempo map);
floats via awk double precision; no receipt integration yet — this is a
pure evaluator, the witness stream comes from the hooks when a caller
ticks a cell with its output.

Pins: `tests/pins_adsr.sh` (11 pins; P9 canary RED states demonstrated
in `pins/failfirst-adsr.log` tool-absent 12/12 RED and
`pins/pins-adsr-final.log` tampered-expectation 1/1 FAIL).
