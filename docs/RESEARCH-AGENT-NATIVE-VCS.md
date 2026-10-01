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
1. Jujutsu: working-copy-as-commit, change vs commit, undo
2. Patch theory: Darcs, Pijul, commutation, and what breaks at scale
3. CRDTs: Automerge and Yjs vs dials-as-files
4. git worktree orchestration precedents
5. Cloudflare Artifacts + Workers platform capabilities
6. Agent-native git experiments, today
7. Synthesis table: what quilt-in-git should steal

---

## 5. Cloudflare Artifacts + Workers platform capabilities

*(This section was researched directly; the others arrive below.)*

### 5.1 What Artifacts is

Cloudflare Artifacts is "versioned, Git-compatible storage" built around the
observation that agents produce a step change in code volume and existing
source-control platforms "were built to meet the needs of humans, not a 10x
change in volume driven by agents" (source: https://blog.cloudflare.com/artifacts-git-for-agents-beta).
It reached **open beta on Oct 1, 2026** — the same changelog entry that
announces a competition to "Build the next GitHub on Cloudflare" — with
billing starting October 14, 2026 (source: https://developers.cloudflare.com/changelog/product/artifacts).
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
