# ONBOARDING — quilt-in-git

> Seed doc (fleet handoff 2026-10-06). Read with `README.md` (layout, dial
> map, minimal loop) and `docs/RESEARCH-AGENT-NATIVE-VCS.md` (the memo).
> Mesh context: `SuperInstance/fleet-seeds` →
> `docs/handoff-2026-10-06/ORG-MESH.md`.

## 1. What this repo is now

**The entire simplified Quilt lives inside a plain Git repository:** dials are
files, ticks are commits, rewind is checkout, Git hooks are the runtime. A
cell is a directory (`cells/<alias>/dials/0..15`, one float per file, plus
`body`); changing a dial and committing is a *tick*; the post-commit hook
turns the tick into a receipt, an entanglement cascade, and a watch-log line.
The repo is simultaneously the Sheet, the journal, and the collaboration bus
— clone, push, bundle, branch, and time travel come free.

State at handoff: w3 union landed (notes receipts + sparse index-vs-HEAD
detection + dial-only orphan branch `refs/quilt/*`), the wave4-query layer
shipped (verifiable-coverage query CLI + LEDGER conventions), notes2feed
w3a shipped (#11 — git-native witness stream → feed.v1), the agent-native
VCS memo is in flight (9c memo sections 2/4/7 landed: patch theory, worktree
orchestration, sparse-index), and **PR #12 (adsr)** is open — a piecewise
ADSR envelope evaluator as a quilt tool, the Tier-0 abstraction-ladder next
brick (11 pins, conventions pinned, canary RED states demonstrated).

## 2. How it got here (the momentum)

- **Radical git-native hypothesis first.** Where jev-quilt put the quilt in a
  Python kernel and MicroMoth put it in quantum circuits, this repo asked:
  what if Git itself were the substrate? The bet: agents already speak git;
  make the world-model the version control and you get persistence,
  collaboration, and time travel for free.
- **Wave discipline with receipts.** w3a/w3b/w3c (witness streams, orphan
  refs, index detection) → w3 union → wave4-query (the ledger becomes
  queryable) → research memo (the *why* written down as sections land).
  Every wave keeps pins honest: tool-absent = all RED, tampered expectations
  = named FAIL.
- **Tools as Tier-0 bricks.** adsr (#12) is deliberately tiny — one dial
  driven by attack/decay/sustain/release ramps, feedable into quilt-tick.
  The abstraction ladder accretes one verifiable brick at a time rather than
  building a framework.

## 3. The vision

**Agent-native version control.** Today's agents bolt memory onto chat
logs; this repo's bet is that an agent's *world* should be a repository —
inspectable, forkable, rewindable, with receipts as commits. The 16-dial cell
is the sensory-motor sketch; entanglement (dial 14 from linked obstruction)
is the social sketch; the witness stream is the accountability sketch. If the
hypothesis pays, "clone the agent" becomes as ordinary as "clone the repo."

## 4. Roadmaps (several directions)

**Going now:** merge #12 (adsr); continue the research memo (sections in
flight: CRDT + Cloudflare — marked PARTIAL, quoted rather than asserted).

**Sketched futures (from the memo + queue):**
- **Abstraction-ladder bricks.** Next Tier-0 tools after adsr: envelope-driven
  sequencers, witness-stream aggregators (w3a consumers), dial-diff
  summarizers. Each ~an evening, each pinned.
- **Patch theory & worktree orchestration** (memo §2/§7): formal tick algebra
  + multi-agent worktree lanes — the path to concurrent agents sharing one
  quilt repo without corruption.
- **CRDT convergence** (memo, pending section): dials as CRDTs would make
  cross-host quilt sync merge-safe — the Cloudflare piece likely lands via
  consume-don't-rival adoption (Workers Durable Objects), not a rival build.
- **stone-v1 / zero-msg-test adjacency.** If Casey's git-native agent lane
  opens, quilt-in-git is the natural world-model substrate for its harness
  (harness event-ledger ↔ watch-log; receipts ↔ post-commit hooks).

## 5. How it meshes

- **Same quilt, three substrates:** this repo (git files) ↔ `jev-quilt`
  (Python kernel + JEV oracle) ↔ `MicroMoth-quilt` (quantum circuits as cell
  ledgers). The five-opcode algebra and fnv1a-64 receipts are the shared
  idiom across all three — a tick, a cell record, and a gate application are
  the same act in different materials.
- **Witness streams feed** fleet-witness / quilt-tools graph lanes (w3a
  notes2feed is already a feed.v1 producer).
- **Referral graph:** the graph's view includes this repo; edges land in
  `quilt-tools` per the weight law.
- Org state: `fleet-seeds` → `docs/handoff-2026-10-06/HANDOFF.md`.
