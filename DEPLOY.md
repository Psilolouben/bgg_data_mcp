# bgg_data — Remote Deployment Guide

`bin/mcp_server` talks MCP over STDIO, which only works for a local Claude Desktop/Code
connection on the same machine. `bin/http_server` runs the same tools behind a
single-endpoint "Streamable HTTP" transport instead, so a hosting platform can expose
them at a URL anyone can point their own Claude at — the same shape as
`gamerules/gr-scraper-mcp` on Render. It's hand-rolled rather than using fast-mcp's own
bundled Rack transport: fast-mcp 1.6.0 only implements the older two-endpoint HTTP+SSE
handshake, which isn't what Claude's remote connectors speak — see the note in
`bin/http_server`'s header comment for the full story of why.

This is meant to be public: it runs with **no authentication by default**, the same way
`gr-scraper-mcp`'s `/mcp` route does, so anyone can add it as a connector and use the
BGG tools without asking you for anything first. Everyone shares the one BGG bearer
token baked into `lib/bgg_data.rb` though - there's no per-user BGG identity - so a
heavy or automated caller could burn through BGG's own rate limit for everyone,
including you. Per BGG's own docs, sustained abuse is "grounds for having your license
suspended," not just a temporary slowdown - see the note on `MCP_RATE_LIMIT_PER_MINUTE`
below for how this server defends against that without requiring a token from normal
users. If public access ever needs shutting off entirely, see "Restricting access"
below.

**`bin/http_server` rate-limits the `/mcp` endpoints per caller IP** (30
requests/minute by default, `/health` is never limited) specifically to blunt a bot or
runaway script hammering it, while staying invisible to normal, occasional tool calls
from a real conversation. Tune it with `MCP_RATE_LIMIT_PER_MINUTE` in Render's
dashboard (set to `0` to disable it). It's intentionally simple - in-process memory, no
Redis or similar - so it resets on every deploy/restart and only works correctly with
a single running instance; it's not a defense against a distributed attack, just
against the much more likely "one client in a bad loop" case.

## 1. Deploy to Render

1. Push `bgg_data/` to a GitHub repo (it can be a subfolder of a larger repo)
2. In the [Render dashboard](https://render.com) → **New → Web Service**
3. Connect your GitHub repo → if `bgg_data` isn't the repo root, set **Root directory**
   to `bgg_data`
4. Render detects `Dockerfile` and `render.yaml` automatically
5. Deploy — first build takes a few minutes (installs gems fresh for Linux, see note
   below). No environment variables are required for public access.

Render's free plan spins down after inactivity, so the first request after a quiet
period takes ~30–50s to wake up; upgrade to **Starter** ($7/mo) in `render.yaml` if that
cold start is annoying for people trying it out.

## 2. Point Claude at it

Give people this URL to add as a custom/remote MCP connector - no auth needed:

```
https://your-service.onrender.com/mcp
```

The exact place to enter this depends on which Claude surface someone's using
(Desktop/Code settings vs. a `mcpServers` config block) — if it asks for a JSON block
instead of a UI field, it looks like:

```json
{
  "mcpServers": {
    "bgg-data": {
      "url": "https://your-service.onrender.com/mcp"
    }
  }
}
```

**Why a hand-rolled transport instead of fast-mcp's built-in one:** fast-mcp 1.6.0 (the version this gem is pinned to) only ships the
older two-endpoint HTTP+SSE transport - `GET` a stream URL first to open a session,
then `POST` JSON-RPC to a second URL tied to that session. Claude's remote connectors
(and the modern MCP spec generally) speak the newer *single-endpoint* Streamable HTTP
transport: POST JSON-RPC straight to one URL, no separate handshake. Pointing a
Streamable-HTTP client at fast-mcp's old-style endpoint without ever opening the SSE
session first left every request without one, which fast-mcp rejected in a way Claude's
client misread as "this server needs OAuth sign-in" - the actual error reported back
was `Couldn't register with BGG Data Online's sign-in service`, i.e. a failed OAuth
dynamic-client-registration attempt, not a real auth requirement.

`bin/http_server` now sidesteps fast-mcp's Rack transport entirely for the HTTP layer:
it still uses `FastMcp::Tool` for argument schemas/validation and
`FastMcp::Server#handle_request` for the actual JSON-RPC dispatch (`initialize`,
`tools/list`, `tools/call`, ...), but a small hand-rolled Rack app owns the single
`/mcp` endpoint - the same shape as gr-scraper's `/mcp` route via the official JS SDK's
`StreamableHTTPServerTransport`. See the comment block at the top of `bin/http_server`
for exactly how the two are wired together.

I still haven't been able to test this end-to-end myself against a live Claude
connector (no way to run one from where I was working), so this is a considered fix
for a diagnosed root cause rather than something I've watched work - if `/mcp` still
doesn't connect cleanly, the Render service logs (the `warn` line `bin/http_server`
prints on any unhandled error) are the next place to look.

## Restricting access (optional)

If usage ever needs limiting, set `MCP_AUTH_TOKEN` in Render's dashboard - no code
change or redeploy needed, `bin/http_server` picks it up on next boot:

```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
```

Once set, the server requires `Authorization: Bearer <token>` on every request, and
whoever you want to keep using it needs that header added to their connector config:

```json
{
  "mcpServers": {
    "bgg-data": {
      "url": "https://your-service.onrender.com/mcp",
      "headers": { "Authorization": "Bearer <token>" }
    }
  }
}
```

This is all-or-nothing (one shared token, not per-user accounts) - fine for cutting off
public access entirely or sharing with a specific group, not for anything finer-grained.

## Notes

- **Why the Dockerfile re-locks the Gemfile before installing:** `Gemfile.lock` was
  generated on macOS (`arm64-darwin`) and has no Linux platform entry. A plain `bundle
  install` on Render's Linux build machine would fail with "Your bundle only supports
  platforms [...]"; the Dockerfile runs `bundle lock --add-platform` first to fix that.
- Local dev keeps using `bin/mcp_server` (STDIO) — nothing about your existing local
  Claude Desktop/Code setup changes.
- To run the HTTP server locally: `bin/http_server`, then check
  `curl http://localhost:8080/health`.
- I could not actually run `docker build` / deploy this myself (no Docker or network
  access to Render/RubyGems from where I was working) — the Ruby code, Dockerfile, and
  the `FastMcp::Server`/`FastMcp::Tool` API calls `bin/http_server` relies on are all
  verified against fast-mcp 1.6.0's real source on GitHub, but a local `docker build .`
  before pushing to Render is worth doing as a sanity check.
