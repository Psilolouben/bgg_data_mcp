# bgg_data — Remote Deployment Guide

`bin/mcp_server` talks MCP over STDIO, which only works for a local Claude Desktop/Code
connection on the same machine. `bin/http_server` runs the same tools behind fast-mcp's
HTTP/SSE Rack transport instead, so a hosting platform can expose them at a URL Claude
can call from anywhere — the same shape as `gamerules/gr-scraper-mcp` on Render.

## 1. Generate an auth token

This server has no per-user login, so a single shared bearer token is what stops anyone
who finds the URL from calling your BGG tools:

```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
```

Save that value — you'll set it as `MCP_AUTH_TOKEN` in Render and hand it to Claude when
you add the connector. If you skip this, the server logs a warning and runs with no
authentication at all — anyone with the URL can call your tools.

## 2. Deploy to Render

1. Push `bgg_data/` to a GitHub repo (it can be a subfolder of a larger repo)
2. In the [Render dashboard](https://render.com) → **New → Web Service**
3. Connect your GitHub repo → if `bgg_data` isn't the repo root, set **Root directory**
   to `bgg_data`
4. Render detects `Dockerfile` and `render.yaml` automatically
5. Under **Environment**, set `MCP_AUTH_TOKEN` to the value from step 1
6. Deploy — first build takes a few minutes (installs gems fresh for Linux, see note
   below)

Render's free plan spins down after inactivity, so the first request after a quiet
period takes ~30–50s to wake up; upgrade to **Starter** ($7/mo) in `render.yaml` if that
cold start is annoying for something you'll poke at often.

## 3. Connect to Claude

Add it as a custom/remote MCP connector pointing at:

```
https://your-service.onrender.com/mcp/messages
```

with the bearer token from step 1 as its authentication (`Authorization: Bearer
<token>`). The exact place to enter this depends on which Claude surface you're using
(Desktop/Code settings vs. a `mcpServers` config block) — if it asks for a JSON block
instead of a UI field, it looks like:

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

## Notes

- **Why the Dockerfile re-locks the Gemfile before installing:** `Gemfile.lock` was
  generated on macOS (`arm64-darwin`) and has no Linux platform entry. A plain `bundle
  install` on Render's Linux build machine would fail with "Your bundle only supports
  platforms [...]"; the Dockerfile runs `bundle lock --add-platform` first to fix that.
- Local dev keeps using `bin/mcp_server` (STDIO) — nothing about your existing local
  Claude Desktop/Code setup changes.
- To run the HTTP server locally: `MCP_AUTH_TOKEN=test bin/http_server`, then check
  `curl http://localhost:8080/health`.
- I could not actually run `docker build` / deploy this myself (no Docker or network
  access to Render/RubyGems from where I was working) — the Ruby code, Dockerfile, and
  fast-mcp API calls are all verified against fast-mcp's real source on GitHub, but a
  local `docker build .` before pushing to Render is worth doing as a sanity check.
