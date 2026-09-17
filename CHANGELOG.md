# Changelog

- 2026-01-21: Make wrapper autonomous by default (disable contract injection + tier gates unless enabled, always full-auto, force sandbox, allow protected branches).
- 2026-01-21: Remove obsolete scripts weztmux-notify and ai-dev.sh from bin.
- 2026-01-21: Remove obsolete aic alias (ai-dev.sh removed).
- 2026-01-21: Guard env sourcing for mcp_bootstrap and local env files in shell startup scripts.
- 2026-01-21: Document github-mcp-server source/version/checksum; align pw-mcpctl port range with pw-mcp-lease.
- 2026-01-21: Remove hardcoded GH/Keycloak secrets; add secret-env loader using gh + optional secret managers.
- 2026-01-22: Add with-secrets wrapper to load auth passwords from pass using parameters.
- 2026-01-22: Add --env option to with-secrets for custom secret env var names.
- 2026-01-22: Add load-pass-from-tsv script to import pass entries from tab-delimited files.
- 2026-01-22: Make load-pass-from-tsv verbose by default; add --quiet flag.
- 2026-01-22: Wrapper adds default --add-dir for /home/clevere and /project/users/clevere; block CHANGELOG/TESTS outside /project/users/clevere.
- 2026-01-22: Wrapper loads default add-dir list from $HOME/.codex/add_dirs.txt (or CODEX_DEFAULT_ADD_DIRS_FILE).
- 2026-01-22: Add template $HOME/.codex/add_dirs.txt for default add-dir list.
- 2026-01-22: Wrapper records per-run changed files list; add codex-copy-changes helper to copy only changed files.
- 2026-01-22: Add codex-deploy-sync helper and deploy->repo map template for aws-tm-### branch naming.
- 2026-01-22: Add codex-repo-sync helper for repo->deploy TDD workflow using changed-files list.
