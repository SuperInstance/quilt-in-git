# quilt-in-git

PoC of the Git-native Quilt (sibling-agent design doc, downloads/*3211.md):
**dials are files, ticks are commits, rewind is checkout, hooks are the
runtime.** The repository itself is the living Sheet — clone = full Quilt,
bundle = air-gapped transport, branch/worktree = parallel exploration.

Status: skeleton. Lane 7 builds the hook runtime on branch `poc-hooks`.
