# Agent guide

See `README.md` and `PRD.md`.

## Merging

"Merge" means the work is on `main` both locally and on `origin`: merge and push, or, with a pull
request, merge it and pull. It is one step: never stop halfway, and never ask whether to do the
second half. `main` and `origin/main` are always the same commit, whoever moved them: check before
reporting a merge as done, and if you find them apart, sync them. A push refused because `origin`
moved: rebase and push again, never force-push. Other branches are pushed only when asked.
