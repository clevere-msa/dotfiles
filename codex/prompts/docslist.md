# /docslist

Run the repo docs list and report any front-matter issues.

Steps:
- If `bin/docs-list` exists, run it.
- Else if `scripts/docs-list.ts` exists, run it with `bun` or `tsx` (no installs).
- If output includes missing front matter / summary errors, report exact files.
- If no docs list exists, say so and suggest adding one.
