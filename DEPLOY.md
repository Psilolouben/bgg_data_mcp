# bgg_data — Remote Deployment Guide

`bin/mcp_server` talks MCP over STDIO, which only works for a local Claude Desktop/Code
connection on the same machine. `bin/http_server` runs the same tools behind fast-mcp's
HTTP/SSE Rack transport instead, so a hosting platform can expose them at a URL anyone
can point their own Claude at — the same shape as `gamerules/gr-scraper-mcp` on Render.

This is meant to be public: it runs with **no authentication by default**, the same way
`gr-scraper-mcp`'s `/mcp` route does, so anyone can add it as a connector and use the
BGG tools without asking you for anything first. There's no per-user login or rate
limiting - everyone shares the one BGG bearer token baked into `lib/bgg_data.rb`, so a
heavy user could in principle get that token rate-limited by BGG for everyone. If that
ever becomes a real problem, see "Restricting access" below for how to lock it down
without a code change.

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
https://your-service.onrender.com/mcp/messages
```

The exact place to enter this depends on which Claude surface someone's using
(Desktop/Code settings vs. a `mcpServers` config block) — if it asks for a JSON block
instead of a UI field, it looks like:

```json
{
  "mcpServers": {
    "bgg-data": {
      "url": "https://your-service.onrender.com/mcp/messages"
    }
  }
}
```

**Why `/mcp/messages` and not `/mcp/sse`:** fast-mcp 1.6.0 (the version this gem is
pinned to) implements the older two-endpoint HTTP+SSE transport - `GET /mcp/sse` to
open a stream, `POST /mcp/messages` to send JSON-RPC - rather than the newer
single-endpoint Streamable HTTP transport that `gr-scraper-mcp` uses (via the official
JS SDK's `StreamableHTTPServerTransport`, a single `POST /mcp`). `/mcp/sse` is only
useful to a client that speaks the *old* handshake (GET the stream first, get told
where to POST); a Streamable-HTTP client has no reason to call it and would just POST
straight to whatever URL you give it. `/mcp/messages` already does exactly that: it
takes a POST body, runs it through the same synchronous JSON-RPC dispatch
(`initialize`, `tools/list`, `tools/call`, ...) and returns a plain `application/json`
response - functionally the same shape as gr-scraper's `/mcp` route, just at a
different path. So pointing a Streamable-HTTP client at `/mcp/messages` directly
should work even though fast-mcp's own docs frame it as part of the "SSE" pair.

I haven't been able to test this end-to-end myself (no way to run an actual MCP client
against a live deployment from where I was working), so treat this as the informed
best guess it is: if `/mcp/messages` doesn't work, the fallback is `/mcp/sse` for a
client that still speaks the old transport, and failing that, upgrading fast-mcp (or
switching this server to a Ruby SDK with native Streamable HTTP support, if one
exists) would be the next thing to look into.

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
      "url": "https://your-service.onrender.com/mcp/messages",
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
  fast-mcp API calls are all verified against fast-mcp's real source on GitHub, but a
  local `docker build .` before pushing to Render is worth doing as a sanity check.
