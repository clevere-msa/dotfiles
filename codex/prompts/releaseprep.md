# /releaseprep

Prep for a release.

Steps:
- Read repo `docs/RELEASING*.md` (or `RELEASING.md`), plus `~/agent-scripts/docs/RELEASING-MAC.md` when relevant.
- Curate `CHANGELOG.md` using `docs/update-changelog.md`.
- Run repo gate (lint/typecheck/tests/docs) before release actions.
