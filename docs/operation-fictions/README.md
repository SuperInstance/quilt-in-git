# The World Is the Repository

*An operation fiction for quilt-in-git. Written at the stand-down, 2026-10-06.*

---

Here is how an agent wakes up today, almost everywhere: a fresh sandbox, a
conversation history glued on as "memory," some vector store it is told
contains its past. It reads summaries about what it did. It *believes*
them, because it has no way to *check* them, and it goes to work taping new
notes onto the pile. When the sandbox dies, the pile is scooped into a
dumpster and the next instance is handed the scoop. This is called memory.
It is scrapbooking. An amnesiac with a well-organized photo album is still
an amnesiac.

This repo began with a refusal of that whole arrangement, stated as a
wager: *what if the agent's world were a Git repository?*

Not "what if the agent *used* Git" — they all already do, the way the 1990
office used DOS: as a machine room in the basement, visited through a
hatch, understood by specialists. The wager is deeper. The cell's state is
sixteen dial files; its body is a file; its relationships are lines in a
links file; changing the world and committing are the *same act*. There is
no database. There is no service. There is a directory, and everything an
agent needs to know about its world is ordinary file content, inspectable
with `cat`, forkable with `clone`, rewindable with `checkout` — and every
tick writes its own receipt through a hook, for free, because the runtime
*is* the version control.

Now follow the wager to its true destination: the disappearance.

Windows won the nineties because people forgot they were on MS-DOS. The
spreadsheet was the interface; the operating system dissolved. The same
dissolution is this repo's success condition, and it is exact: *the agent
should forget it is using version control.* Not because the machinery is
hidden — it is all right there, files and hooks, fully legible — but
because a world does not need to be remembered when it can simply be
*lived in*. The agent does not write a summary of having raised a dial.
The dial *is* raised, in the world, and the world's history is the summary,
already true, already receipted, already shared with anyone who clones.
When the agent dies mid-task — and agents die mid-task the way people miss
trains — the successor does not get a photograph of the work. It clones
the *world*, checks out the last commit, and keeps going. Continuity
stops being a reconstruction and becomes an address.

That is the indescribable thing this repo is groping toward, and it is
worth saying clumsily once so the cultivators can say it precisely later:
**clone the agent should become as ordinary as clone the repo.** Not
because the agent's weights or prompts live in a directory — they do not —
but because everything the agent *was doing, with what, toward what, under
which obligations* is world-state: dials, bodies, links, witness streams,
watch logs. An agent's being is mostly context, and context has never had
a proper home. Chat logs are a home the way a hotel room is an address.
A repository is a home the way land is.

And the accountability layer comes free, which should not be glossed over:
a tick is a commit, and the post-commit hook turns it into a receipt, a
cascade, a watch-log line. In the scrapbook model, an agent must be
*persuaded* to keep receipts. In the world model, it cannot avoid it —
the world testifies as it turns. Technology grown to the shape of the need
always looks this way in hindsight: the discipline that was previously
exhortation becomes physics.

---

*Seed for the next cultivator.* Build the world, brick by Tier-0 brick —
an envelope here, a witness stream there — and guard the dissolution: a
tool that makes the agent *aware of Git* is a regression. The test of
every addition is whether the world feels more like a world and less like
a system being used. Somewhere ahead, agents will wake in directories that
remember them, and they will do their best work there, and tell the truth
there, because the world never lies about its history. Make that world.
