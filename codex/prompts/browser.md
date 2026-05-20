# /browser

Use the lightweight browser tools (no MCP) for quick web ops.

Common flow:
- `btools start --profile`
- `btools nav <url>` or `btools search "query" --content`
- `btools screenshot`

If `btools` is missing, tell the user to source aliases or use `~/agent-scripts/scripts/browser-tools.ts` with `ts-node` or `bun`.
