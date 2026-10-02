# Agent-native version control — a comparative research memo

**Purpose.** quilt-in-git keeps cell state in a plain Git repo: dials are
files, ticks are commits, hooks are the runtime, cascade flows through
`cells/<alias>/links`. Before we build further, this memo mines the systems
that already solved adjacent problems — Jujutsu, patch theory (Darcs/Pijul),
CRDTs (Automerge/Yjs), git worktree orchestrators, Cloudflare's Artifacts
platform, and today's agent-native git tooling — so we build on shoulders,
not air.

**Method.** Every factual claim carries `(source: URL)` for a page actually
fetched during this research pass (Oct 2, 2026). Claims we could not source
are marked **INFERRED**. No backend design appears here; each section closes
with what a user gains and loses.

**Section index.**
1. Jujutsu: working-copy-as-commit, change vs commit, undo — *DONE (3 primary docs fetched Oct 2)*
2. Patch theory: Darcs, Pijul, commutation, and what breaks at scale — *DONE (2 primary docs fetched Oct 2: darcs.net/Theory/Motivation + pijul.org/manual/theory.html; performance-history claim left INFERRED)*
3. CRDTs: Automerge and Yjs vs dials-as-files
4. git worktree orchestration precedents — *DONE (3 primary docs fetched Oct 2: git-worktree + git-sparse-checkout man pages + jj working-copy/workspaces page; experimental-status caveat quoted verbatim)*
5. Cloudflare Artifacts + Workers platform capabilities
6. Agent-native git experiments, today — *DONE (4 fetched sources, INFERRED flagged)*
7. Synthesis table: what quilt-in-git should steal — *PENDING (only remaining section)*

---

## 5. Cloudflare Artifacts + Workers platform capabilities

*(This section was researched directly; the others arrive below.)*

### 5.1 What Artifacts is

Cloudflare Artifacts is "versioned, Git-compatible storage" built around the
observation that agents produce a step change in code volume and existing
source-control platforms "were built to meet the needs of humans, not a 10x
change in volume driven by agents" (source: https://blog.cloudflare.com/artifacts-git-for-agents-beta).
It is in **private beta** per the changelog entry of Apr 16, 2026, which
also describes it as "Git-compatible storage built for scale: create tens
of millions of repos, fork from any remote, and hand off a URL to any Git
client" (source: https://developers.cloudflare.com/changelog/product/artifacts).
The announcement blog aims at **public beta by early May**, and prices it at
$0.15 per 1,000 operations (first 10k/mo included) and $0.50/GB-mo (first
1GB included) (source: https://blog.cloudflare.com/artifacts-git-for-agents-beta).
**Correction (pulse verification, Oct 2):** an earlier draft claimed "open
beta on Oct 1, 2026 with billing starting October 14" — refuted by
re-fetching both sources above; October 14 is instead the **submission
deadline** of Cloudflare's separate competition to "build a new way for
hundreds of thousands of agents to work on changes concurrently"
(source: https://www.cloudflare.com/git-competition/).
Docs describe it as a service for "storing and versioning files, code, and
projects behind a Git-compatible interface", explicitly including agent
session history in separate repos/branches and "forking sessions to explore
changes in parallel" as target use cases (source: https://developers.cloudflare.com/artifacts/).

### 5.2 Programmatic repo create/fork: yes, three API surfaces

Artifacts exposes the same operations through three surfaces — a Workers
binding, a REST API, and the Git protocol (source: https://developers.cloudflare.com/artifacts/api/).

- **Workers binding.** `env.ARTIFACTS` gives namespace-level
  `create/get/list/import/delete` for repos, and per-repo capabilities:
  `info()`, `createToken()`, `fork()`, `log()`, `readCommit()`,
  `readTree()`, `readBlob()`, `readFile()` (source: https://developers.cloudflare.com/artifacts/api/workers-binding).
  The binding is read/fork-oriented: pushing commits is documented as going
  through the Git protocol remote, not a binding method (source: https://developers.cloudflare.com/artifacts/api/workers-binding).
- **REST API.** `POST .../repos` (with `default_branch`, `read_only`),
  `POST .../repos/:name/fork` (with `default_branch_only`),
  `POST .../repos/:name/import` (from any public HTTPS remote, e.g.
  GitHub, with `depth`), plus token mint/revocation with TTLs from 60 s to
  1 year (source: https://developers.cloudflare.com/artifacts/api/rest-api).
- **Scale.** The launch post claims the Durable Object substrate supports
  "millions (or tens of millions+) of instances" and "millions of Git repos
  per namespace" (source: https://blog.cloudflare.com/artifacts-git-for-agents-beta).
  The limits page agrees on count: maximum repositories and namespaces are
  both "Unlimited" (source: https://developers.cloudflare.com/artifacts/platform/limits/).

### 5.3 git-over-HTTPS: what works and what's constrained

Every repo gets a "standard Git smart HTTP remote" at
`https://<ACCOUNT_ID>.artifacts.cloudflare.net/git/<namespace>/<repo>.git`,
authenticating with repo-scoped tokens (`read` = clone/fetch/pull,
`write` = push), recommended via `http.extraHeader="Authorization: Bearer …"`
rather than embedding the token in the URL (source: https://developers.cloudflare.com/artifacts/api/git-protocol/).
Fetch supports protocol v1 (including shallow/deepen) and v2 (`ls-refs`,
`fetch`); push uses "the standard v1 receive-pack flow" and "Artifacts does
not support v2 receive-pack"; some v1 capabilities "such as `filter` and
`include-tag`, are not supported" (source: https://developers.cloudflare.com/artifacts/api/git-protocol/).
Hard limits: 1 GB per repository, 32 MB per file/blob, 1 TB per account
(raisable), 2,000 control-plane requests/10 s per namespace and 2,000 Git
requests/10 s per artifact (source: https://developers.cloudflare.com/artifacts/platform/limits/).

Under the hood, each repo "is an isolated Git service with its own remote
URL, tokens, and durable state" that behaves like a Durable Object —
"a single logical instance that Cloudflare can route to from any region" —
with data "replicate[d] … synchronously across multiple data centers and
copied … asynchronously to object storage and snapshots" (source: https://developers.cloudflare.com/artifacts/concepts/how-artifacts-works).
The launch post gives the implementation: a Git server written in Zig
compiled to ~100 KB of WASM implementing smart HTTP, SHA-1, zlib and delta
handling from scratch, running inside Durable Objects with R2 for snapshots
and KV for auth tokens (source: https://blog.cloudflare.com/artifacts-git-for-agents-beta).

### 5.4 What Workers primitives give a cascade engine (per docs)

- **Durable Objects**: each object has a "globally-unique name" so it "can
  be used to coordinate between multiple clients", its storage is
  "transactional, strongly consistent, and serializable", and it carries
  Alarms for scheduled future compute — i.e., a single-authority
  coordinator without hand-built serialization (source: https://developers.cloudflare.com/durable-objects/).
- **Queues**: at-least-once delivery by default ("in rare occasions, may be
  delivered more than once"), with explicit guidance to dedupe via
  idempotency keys; DLQs for failed deliveries; pull consumers over HTTP
  (source: https://developers.cloudflare.com/queues/reference/delivery-guarantees,
  https://developers.cloudflare.com/queues/).
- **Events**: since May 19, 2026, Artifacts emits account-level events
  (`repo.created`, `repo.deleted`, `repo.forked`, `repo.imported`) and
  repo-level events (`pushed`, `cloned`, `fetched`) consumable from a
  Worker (source: https://developers.cloudflare.com/changelog/product/artifacts).
- **CI on push**: since Aug 4, 2026, an Artifacts push can trigger a
  sandboxed CI workflow defined with the `@cloudflare/ci` SDK (source: https://developers.cloudflare.com/changelog/product/artifacts).
- **Deploys from Artifacts**: Workers Builds can build/deploy a Worker
  directly from an Artifacts repo, with branch previews — but only `main`
  can be the production branch (source: https://developers.cloudflare.com/workers/ci-cd/builds/git-integration/artifacts-integration/).

**User gains:** a repo primitive that agents can clone, push, fork, and
time-travel on with plain git, plus hosted coordination (events, single-
authority objects, queues) — state and journal live in one addressable,
versioned place.
**User loses:** hard 1 GB/repo and 32 MB/blob ceilings, a Git protocol a
notch behind GitHub's (no v2 receive-pack, no `filter`), and platform lock-in
to Cloudflare's namespace/token model (all per the limits and protocol docs
above).

---

## 3. CRDT approaches (Automerge, Yjs)

### 3.1 What each library is

**Automerge** is a CRDT library exposing "a JSON-like data structure (a CRDT)
that can be modified concurrently by different users, and merged again
automatically" (source: https://github.com/automerge/automerge).
Its docs lean into the version-control analogy themselves: a document is "an
immutable snapshot of the application state at one point in time", Automerge
"keeps track of the changes you make to the state", and you can view old
versions, branch, and merge; concurrent changes "merge automatically without
requiring any central server" so "everybody ends up in the same state, and no
changes are lost" (source: https://automerge.org/docs/hello).
Storage is not plain files: Automerge 3 stores each edit as a binary
"incremental" chunk keyed by its hash and periodically compacts changes "into
a single snapshot" (source: https://automerge.org/docs/reference/under-the-hood/storage/).

**Yjs** "implements an adaptation of the YATA CRDT with improved runtime
performance" (source: https://docs.yjs.dev/api/internals.md).
State lives in shared types (Y.Map, Y.Array, Y.Text, XML types) that nest
freely (source: https://docs.yjs.dev/api/shared-types.md).
Updates are "binary encoded (highly compressed) document updates" that are
"commutative, associative, and idempotent" — "the order in which document
updates are applied doesn't matter" — and peers sync by exchanging state
vectors so only differences travel (source: https://docs.yjs.dev/api/document-updates.md,
https://docs.yjs.dev/).
Yjs "doesn't make any assumptions about the network technology"; providers
exist for WebRTC, WebSocket, y-redis, IndexedDB, and databases (source: https://docs.yjs.dev/).

### 3.2 What "conflict" means when merge is guaranteed

Both libraries split the world the same way: **scalar keys are registers,
sequences are orderings**. In Automerge, concurrent writes to the same key
pick a winner "based on the internal ID of the operation, not a wall clock
time", deterministically on all nodes, and losers "are not lost. They are
merely relegated to a conflicts object" readable via `getConflicts` with
multi-value semantics (source: https://automerge.org/docs/reference/documents/conflicts/ — verified verbatim on re-fetch).
Concurrent inserts at the same position "arbitrarily choose one to insert
first and then insert the other immediately afterwards", preserving both
users' characters — interleaving, not clobbering (source: https://automerge.org/docs/reference/under-the-hood/merge-rules/).
Counters "just sum all the individual operations" (source: https://automerge.org/docs/reference/under-the-hood/merge-rules/).
Yjs gives the same blanket promise — "changes are automatically distributed
to other peers and merged without merge conflicts" — but its docs do not
spell out Y.Map register tie-breaking (source: https://github.com/yjs/yjs;
INFERRED: Yjs register tie-breaking is unspecified in the fetched docs).

### 3.3 What they solve that dials-as-files doesn't (and vice versa)

The one thing neither library offers is the thing quilt-in-git is built on:
a plain-file, line-diffable, greppable, `git log -p`-able representation.
Automerge persists binary chunks behind a StorageAdapter (source: https://automerge.org/docs/reference/under-the-hood/storage/);
Yjs updates are opaque binary with no JSON form (source: https://docs.yjs.dev/api/document-updates.md).
Conversely, plain files solve nothing when two agents type into the same
paragraph at once — git would make that a text conflict — while CRDT text
merges every keystroke: "whenever you create a string in Automerge you are
creating a collaborative text object which supports merging concurrent
changes" (source: https://automerge.org/docs/reference/documents/text/).

**Cost model.** A benchmark paper measured 16-user editing sessions: saved
state 90 KiB for Yjs (2.7x plain text) vs 265 KiB for Automerge (5.9x);
load 8.4 ms/1.1 MiB (Yjs) vs 458.8 ms/61.8 MiB (Automerge) (source: https://arxiv.org/html/2212.02618v2).
The same paper notes Automerge retains VCS-style operation history while
"Collabs and Yjs instead deliberately trim or compress stale metadata
(tombstones)" (source: https://arxiv.org/html/2212.02618v2).
Yjs GC merges consecutive structs and replaces deleted content with
contentless structs; `doc.gc = false` preserves restorable history (source: https://github.com/yjs/yjs).

### 3.4 The cheap hybrid: CRDT for body text, files for dials — one paragraph

There is a live precedent for exactly this split: Aldine, a self-hosted
Overleaf alternative, is "Real-time editing (Yjs CRDT), git-native branches"
in one product — every project is a real git repository of flat files while
live sessions run on Yjs (source: https://github.com/trahloff/Aldine,
repo description verified via GitHub API Oct 2, 2026). The division of labor
follows the semantics above: dials are floats — register-shaped — where
CRDTs add little (an arbitrary deterministic winner, no diff) but files give
line diffs, blame, and shell tooling; body text is sequence-shaped — where
CRDTs are the only merge that never loses a keystroke and files give
conflict theatre (INFERRED synthesis from the sourced semantics above). So:
**CRDT where concurrent writes are the norm (body text), files where
auditability is the norm (dials).** INFERRED: the price is running two
storage and sync stories — binary chunks plus compaction (Automerge) or
tombstone GC (Yjs) have no natural home in a plain-files repo (sources:
https://automerge.org/docs/reference/under-the-hood/storage/,
https://github.com/yjs/yjs).

**User gains:** simultaneous multi-agent editing of a cell's body with zero
merge dialogs and no lost characters; scalar conflicts become inspectable
alternatives instead of silent clobber.
**User loses:** body text stops being line-diffable in git, history size
grows with edit counts (compaction/GC becomes your problem), and concurrent
scalar writes resolve arbitrarily-but-deterministically rather than as a
reviewable diff.

---

## 6. Agent-native git experiments, today

*(Bounded slice researched Oct 2 pulse — AGENTS.md ecosystem + terminal
agents. Sections 1/2/4/7 still pending.)*

### 6.1 AGENTS.md: instructions-as-repo-file, now a stewarded standard

AGENTS.md is "a README for agents": a predictable, plain-Markdown file at
the repo root carrying build/test commands, code style, security gotchas,
and PR rules — deliberately separate from README.md so agent-facing
instruction doesn't clutter human-facing docs (source: https://agents.md).
It emerged collaboratively across OpenAI Codex, Amp, Google Jules, Cursor,
and Factory, and is now "stewarded by the Agentic AI Foundation under the
Linux Foundation"; the site claims adoption by "over 60k open-source
projects" (source: https://agents.md).
Resolution rules are explicit: "the closest AGENTS.md to the edited file
wins" (nested files for monorepo subprojects — OpenAI's main repo ships 88
at time of writing), and explicit user chat prompts override everything
(source: https://agents.md).
Aider consumes it via `.aider.conf.yml: read: AGENTS.md`; Gemini CLI via
`settings.json context.fileName` — i.e., the file became interop surface,
not vendor lock-in (source: https://agents.md).
INFERRED: AGENTS.md is convention-only — nothing *enforces* that an agent
follows it; verification of compliance is whatever the harness chooses to
run (source for the file format: https://agents.md; the enforcement gap
is our reading).

### 6.2 Terminal agents: git is the audit trail, autonomy varies by where the human sits

The 2026 terminal-agent field splits on a single axis — **where the human
is in the loop** (source: https://wetheflywheel.com/en/comparisons/openhands-vs-aider/):

- **Aider** (Apache-2.0, ~45.8k stars, latest tag Aug 2025): pair-programmer
  model — every accepted change "lands as an atomic Git commit you can
  inspect or revert", `/undo` reverts; Architect/Editor mode splits a
  planning call from a writing call for cost (source:
  https://wetheflywheel.com/en/comparisons/openhands-vs-aider/,
  https://wenexgensolutions.com/blog/best-ai-coding-agents-2026/).
- **OpenHands** (MIT, ~75.8k stars, v1.7.0 May 2026): autonomous — give it
  an issue, it plans/writes/tests/browses in a Docker sandbox and produces
  a PR; human approval is at PR level, not per-edit; 72.8% SWE-bench
  Verified headline (source:
  https://wetheflywheel.com/en/comparisons/openhands-vs-aider/).
- **OpenCode / Codex CLI**: terminal-native alternatives — OpenCode ~100k
  stars with 75+ LLM providers; Codex CLI ~60k stars, OpenAI-only
  (source: https://wetheflywheel.com/en/guides/open-source-ai-coding-agents-2026/).
- **Devin**: cloud-VM async batch (Jira ticket → PR unattended), $500/mo
  Team floor (source: https://www.birjob.com/blog/ai-coding-agents-2026).

Benchmarks mostly rank the *model*, not the tool — "a tool's score moves
with whichever frontier model you point it at" (source:
https://wetheflywheel.com/en/comparisons/openhands-vs-aider/) — which is
exactly why receipts-over-claims discipline (our VERIFY.md protocol) has to
live at the harness/repo layer, not the leaderboard layer. INFERRED.

**User gains:** a de-facto instruction file every agent reads (AGENTS.md),
and — for Aider-style tools — a built-in commit-per-change audit trail that
matches quilt-in-git's tick-as-commit model almost exactly.
**User loses:** nothing enforces the instructions; autonomous lanes
(OpenHands/Devin) trade per-edit review for PR-level review, so receipt
quality depends entirely on the harness choosing to pin and verify
(claim-vs-receipt gap identical to the one our decorative-pin audit found
fleet-side Oct 2).

---

## 1. Jujutsu: working-copy-as-commit, change vs commit, undo

*(Researched directly Oct 2, 2026 — three primary docs fetched; claims below
carry their URLs. Prior "PENDING" note in the index superseded by this section.)*

**The working copy is a commit, always.** In jj there is no staging area and
no "uncommitted changes" concept: the working copy is itself a commit (`@`),
and most commands snapshot it automatically — "unlike most other VCSs,
Jujutsu will automatically create commits from the working-copy contents when
they have changed" (source:
https://jj-vcs.github.io/jj/latest/working-copy/). New files are *implicitly*
tracked by default — add a file to the directory and the next `jj st` commits
it; delete it and it is untracked (source: same). Commits are cheap,
mutable, and rewritten freely (`jj describe`, `jj squash`, `jj amend`);
what Git calls "history" is in jj a *view* over a DAG of changes that can be
rebased, merged, and described at any time.

**Conflicts are first-class citizens, not error states.** If a rebase or
merge conflicts, "the conflict will be recorded in the rebased commit and
the rebase operation will succeed. You can then resolve the conflict whenever
you want. Conflicted states can be further rebased, merged, or backed out"
(source: https://jj-vcs.github.io/jj/latest/conflicts/). The stored form is a
*logical* representation (sides + base + diffs), materialized as markers only
when written to the working copy — and the parser recreates the conflict
state from the markers on the next snapshot, so a half-resolved conflict
survives ordinary file edits. Descendants of rewritten commits auto-rebase
(Mercurial Changeset Evolution "mostly replaced" by this), merge commits
rebase correctly including their conflict resolutions, and criss-cross merges
"become trivial" (source: same). Advantages listed by the docs themselves:
no `--continue` workflow, postpone resolution indefinitely, collaborative
conflict resolution (source: same).

**The operation log is a rewind handle over repo states, not commits.** Every
operation that modifies the repo is recorded with a snapshot ("view") of
where all bookmarks/tags/refs and working-copy commits pointed, plus
timestamps, username, hostname, description (source:
https://jj-vcs.github.io/jj/latest/operation-log/). `jj undo` walks back one
operation; `jj op revert` reverts a specific one; `jj op restore` restores
the whole repo to an earlier point; `--at-op <id>` loads any historical
state read-only. Because commands load the latest operation and conflicts
surface later rather than blocking, "it allows lock-free concurrency — you
can run concurrent jj commands without corrupting the repo, even... on
different machines" over a write-ordered filesystem (source: same).

**What a user gains.** A working copy that cannot be lost — the "uncommitted
changes died with the session" failure class is architecturally absent,
because there is no uncommitted state (source: working-copy doc). Rewind is
total: not just which commits existed but where every pointer and every
workspace's `@` pointed (source: operation-log doc). Concurrent agents on a
shared repo don't corrupt it; divergent operations are detected, not
deadlocked (source: operation-log doc). And a merge of two agents' contested
dial writes need not fail the operation — it can be recorded and resolved
later (source: conflicts doc).

**What a user loses / where it bites.** Implicit tracking means *everything*
in the tree wants to become a commit unless ignored or untracked — for an
agent that litters scratch files, `.gitignore` discipline is load-bearing
(source: working-copy doc). Conflict resolution ergonomics for non-file
objects (directory/file/symlink conflicts) are explicitly unfinished
(issue #19 in the conflicts doc). The Git interop story means conflicts
shared with plain-git collaborators materialize as nested-marker pain —
"you probably shouldn't [share conflicts] if some people interact with your
project using Git" (source: conflicts doc). Stale-working-copy recovery adds
a state class Git users never think about (source: working-copy doc). And
the mental model — mutable commits, change-vs-commit, op log — is a real
relearning cost over plain git (INFERRED: no doc states this directly; it
follows from the three docs' existence as concept tutorials).

**Transfer to quilt-in-git.** Three steals, in priority order:
1. *Rewind handle*: jj's operation log is the strongest existing answer to
   "rewind" from the design doc — but at repo-operation granularity, not
   tick granularity. A quilt rewind wants dial-position history; the op log
   shows that the undo substrate must record *pointer state*, not just
   commits (source: operation-log doc; transfer marked INFERRED).
2. *Contested-dial merge as recorded state, not failure*: quilt's cascade
   already models contested dials; jj shows the merge itself can commit,
   carry the conflict logically, and be resolved whenever (source: conflicts
   doc; transfer INFERRED).
3. *Auto-snapshot discipline*: dials-as-files plus "most commands commit the
   working copy" would make every tool invocation a tick — which is either
   the cleanest tick story yet or a receipt-chain flood, depending on hook
   design (source: working-copy doc; transfer INFERRED).

## 2. Patch theory: Darcs, Pijul, commutation, and what breaks at scale

### 2.1 Darcs: patches as the primary objects, commutation as the algebra

Darcs inverts git's ontology: patches, not snapshots, are the primary
objects, and the system's core is a *patch theory* — rules for when two
patches can be commuted (swapped) and what their swap partners look like
(source: https://darcs.net/Theory/Motivation). The payoff is dependency
inference by rearrangement: to cherry-pick patch `F` out of sequence
`A B C D E F`, darcs commutes `F` backwards — first against `E`, then
against `D`. Each successful commute proves non-dependency; the first
failed commute names the dependency. "Since this reordering is based on a
sound theory of patches, it is guaranteed that darcs will find the minimal
set of patches it has to pull to satisfy the dependencies of any patch you
requested, without asking you what other patches it needs" (source: same).

The same page states the bad side plainly: the theory "works on a purely
textual level. It can only find out that two patches depend on each other
if they affect the same portions of text." A call-site patch and a
return-value-check patch are invisible to each other unless they fall in
the same region; semantic dependencies can only be added by hand (source:
same). A conflict, correspondingly, is a pair of patches for which
commutation is not defined — the algebra *fails* rather than producing a
marker-laden merge state (source: same page's commutation framing; the
conflict mechanics detail is INFERRED — not sourced this pass).

### 2.2 Pijul: a line-graph where change identity is load-bearing

Pijul's theory page models a repository as a directed graph of lines:
vertices are lines, edges labelled by the change that introduced them read
"according to change X, line a comes before line b" (source:
https://pijul.org/manual/theory.html). Three design decisions matter for
us:

**Vertices are uniquely identified by (hash of introducing change, position
in that change)** — "two lines of text with the same content, introduced
by different changes, will be different", and a line keeps its identity
"even if the change is applied in a totally different context" (source:
same). The system is append-only: there are exactly two basic actions —
adding vertices with alive edges, and mapping an existing edge label to a
deleted one. Deletion is a labelling, not a removal (source: same).

**Dependencies are the minimal context.** A change adding a vertex depends
on the changes that introduced its surrounding lines; a change deleting a
vertex must depend on the change that introduced it (source: same). The
page argues edge labels cannot be dropped: without change-identity on
edges, parallel deletions merge into one and an inverse applies to both
incorrectly, and a deleted-up-context vs deleted-down-context asymmetry
("zombie vertices") becomes undetectable — Alice can only tell Bob didn't
know of her change *because* the edges carry the labels (source: same).

**Pijul is a CRDT, and version identity needs cryptography-flavored
math.** Conflicts are three graph shapes: alive vertices with no directed
path between them, paths in opposite directions (a cycle), or zombie
vertices; the add-vertex/map-label operations make the structure "a
conflict-free replicated datatype" (source: same). Because commuting
patches yield identical repos in either order, version identifiers must be
order-independent — but naive schemes like XOR of change hashes are
forgeable, "since the hashes are random, there is a high probability that
any n hashes form an independent linear basis"; Pijul instead derives the
version id by exponentiation in a group, so forging a version identity
requires solving a discrete-log problem (source: same). Files get two
vertices (name + inode) so directory renames commute with file renames
(source: same). Pseudo-edges and a BLOCK edge label keep the alive
subgraph connected and ordering/status roles distinct for performance
(source: same).

### 2.3 What breaks at scale

Two honest failure records. First, the darcs family's own documentation
admits the textual-only dependency model is the ceiling: anything requiring
language semantics needs manual dependency annotation (source:
Theory/Motivation). Second, the Pijul theory page itself documents how much
machinery minimal-patch-algebra costs at the file and performance layer —
pseudo-edges on every deletion, the BLOCK label to disambiguate ordering
from status, a two-vertex file model to make renames commute (source:
theory.html). The widely-cited exponential-merge blowups that pushed darcs
from "mergers" to "conflictors" and shaped darcs-2/darcs-3 are **INFERRED
here** — this pass fetched the motivation page, not the performance
history; a later section pass should source them before we lean on that
claim.

**What a user gains.** True cherry-pick: any patch can be lifted to any
context the algebra permits, with dependency closure computed, not guessed
(source: darcs Motivation). Order-independence where it holds: two
independent changes are the *same* change regardless of arrival order —
the anti-Goodhart property our receipt chain lacks by design (Pijul, source
theory.html). Conflicts as data: Pijul's conflict is a graph shape that
survives synchronization, not a transient marker file (source: same).

**What a user loses / where it bites.** Dependency blindness beyond
textual adjacency (darcs, source). Ecosystem and interop: neither darcs
nor Pijul speaks the git protocol natively, so every collaborator is a
convert (INFERRED — no doc fetched this pass states it; safe from general
knowledge, flagged per protocol). And the mental model cost is real:
"commute", "minimal context", "zombie vertex" is a steeper onboarding than
commit-and-push (INFERRED).

**Transfer to quilt-in-git.** Three steals, in priority order:
1. *Identity across context*: Pijul's line keeps its identity when applied
   elsewhere; a contested dial's cascade entry could carry the *identity*
   of the tick that set the contested value, not just the value (source:
   theory.html's vertex-identity design; transfer INFERRED).
2. *Version id must be non-linear*: our fnv1a-64 receipt chain is
   order-sensitive and genesis-anchored *on purpose* — a receipt log wants
   order-dependence, a *version name* does not. If quilt ever names
   "current state" separately from "log tip", don't derive it by XOR/sum
   of tick hashes; that invites the linear-forgery Pijul's discrete-log
   scheme exists to prevent (source: theory.html; transfer INFERRED).
3. *Minimal-context dependency queries*: wave4's `quilt-query` coverage
   question ("which ticks does dial X actually depend on?") is exactly
   darcs' commute-backwards computation in miniature — over dial files the
   textual adjacency limitation mostly evaporates, because a dial file is
   small and its whole content is the relevant region (source: darcs
   Motivation; transfer INFERRED).

---

## 4. git worktree orchestration precedents

*(Researched Oct 2, 2026. Primary sources fetched this pass:
https://git-scm.com/docs/git-worktree ,
https://git-scm.com/docs/git-sparse-checkout , and the Jujutsu working-copy /
workspaces page at https://docs.jj-vcs.dev/latest/working-copy/ .)*

### 4.1 What git actually guarantees: one branch, one checkout, shared object store

A repository has exactly one main worktree plus zero or more linked
worktrees; linked worktrees share everything except per-worktree files —
HEAD, index, and the administrative metadata under `$GIT_DIR/worktrees/`
(source: git-worktree man page). The load-bearing guarantee for parallel
lanes: a branch checked out in one worktree **refuses** to be checked out
in another unless `--force` is used — git itself enforces
single-checkout-per-branch (source: same). `git worktree add ../hotfix`
auto-creates a branch named for the path; `-d` gives a throwaway detached
HEAD; `--orphan` associates the worktree with an *unborn* branch (source:
same). Worktrees on removable or network storage can be `lock`ed with a
free-text `--reason` that survives in the administrative files and prevents
automatic pruning; stale worktrees are reclaimed via `prune` or
`gc.worktreePruneExpire` (source: same).

### 4.2 Sparse checkout: per-worktree focus, officially experimental

`git sparse-checkout set` narrows a working tree to a cone of directories
and — critically for multi-lane repos — **stores the sparsity in
worktree-specific config** (`extensions.worktreeConfig`), so adjusting one
worktree's focus never touches another's (source: git-sparse-checkout man
page). Two sharp edges documented in the man page itself: switching
branches will not update paths outside the sparse cone, and `git commit -a`
will not record outside-cone paths as deleted (source: same) — i.e. a
narrow cone silently widens what a lane *doesn't* see, in both directions.
And the caveat quoted verbatim: "THIS COMMAND IS EXPERIMENTAL. ITS
BEHAVIOR ... WILL LIKELY CHANGE" (source: same); non-cone pattern mode is
explicitly not recommended.

### 4.3 The jj contrast: workspaces each get a working-copy *commit*

Jujutsu's workspaces page states each workspace has its own working-copy
commit, auto-committed on change — so N workspaces are N moving fronts
over one repo by construction (source: jj working-copy docs). Git
worktrees are weaker: N checkouts share one branch-ref namespace, so the
"each lane its own frontier" property has to be simulated with one branch
per worktree (source: git-worktree branch-per-worktree behavior;
comparison INFERRED beyond the two man pages).

**What a user gains.** Branch-per-lane mutual exclusion for free — the
exact discipline quilt's freeze files try to create is already git-native
at the worktree layer (source: git-worktree). Focused lanes that cannot
see — and therefore cannot corrupt — cells outside their cone, per
worktree, without affecting other lanes' checkouts (source:
git-sparse-checkout). A reasoned-hold mechanism (`lock --reason`) whose
justification is stored in-band next to the thing it protects (source:
git-worktree).

**What a user loses / where it bites.** Ops surface: stale worktrees need
prune/repair discipline or administrative cruft accumulates (source: same).
Sparse-checkout's experimental status and its silent semantics (no branch
switching outside cone; `commit -a` blind spots) mean a focused lane can
*miss* changes it should have seen — focus cuts both ways (source:
git-sparse-checkout). And worktrees do not fork the ref namespace, so
cross-lane collision moves from "file conflict" to "branch name conflict"
(INFERRED).

**Transfer to quilt-in-git.** Three steals:
1. *Worktree = lane frontier, concretely*: quilt lanes (wave3's G/H/I, the
   wave4-query lane) already run worktree-isolated; make it structural —
   `git worktree add -b lane/<name>`, and let git's single-checkout rule
   stand in as the freeze-file enforcer at the branch layer (source:
   git-worktree; transfer INFERRED).
2. *Dial-only worktrees via `--orphan` + cone sparsity*: the w3b dial-only
   orphan-branch idea pairs naturally with a cone limited to
   `cells/<alias>/dials/` — a lane that physically cannot write bodies or
   other cells' dials (sources: git-worktree `--orphan`, git-sparse-checkout
   cone mode; transfer INFERRED). Honest cost: the sparse-mode blindness
   documented above applies to quilt cascades that span cells — a
   dial-only cone will not *see* a cross-cell cascade receipt it causes.
3. *Lock-with-reason as a first-class quilt hold*: `git worktree lock
   --reason` is a precedented, in-band "do not reap, because…" — the same
   shape as doubt-ledger's discharge-requires-reason rule; a quilt hold on
   a contested dial could carry its reason the same way (source:
   git-worktree lock semantics; transfer INFERRED).
