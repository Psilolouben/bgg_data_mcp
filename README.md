# BggData

A Ruby gem for interacting with the [BoardGameGeek XML API v2](https://boardgamegeek.com/wiki/page/BGG_XML_API2). Fetch user collections, game details, and auction bids — and expose them as [MCP tools](https://modelcontextprotocol.io) for use with Claude and other AI assistants.

## Features

- Fetch a user's BGG game collection with status and rating filters
- Retrieve detailed game info (mechanics, weight, player counts, rankings)
- Search games by title
- Parse auction bids from BGG geeklists
- MCP server with three ready-to-use tools for AI integration

## Installation

Add to your Gemfile:

```ruby
gem 'bgg_data'
```

Or install directly:

```bash
gem install bgg_data
```

## Usage

```ruby
require 'bgg_data'

# Fetch a user's owned games
BggData.collection('username')
# => [{ name: "Wingspan", bgg_id: "266192", plays: 12, rating: "9" }, ...]

# Filter by collection status
BggData.collection('username', status: 'fortrade')

# Filter by minimum BGG rating
BggData.collection('username', minbggrating: 7)

# Get detailed game info by BGG ID
BggData.games_info(['266192', '174430'])
# => [{ id: "266192", name: "Wingspan", mechs: [...], rank: 10, best_players: [2, 3, 4], weight: 2.45, minimum_age: 10 }, ...]

# Search for games by title
BggData.search_by_title('Catan')
# => [["Catan", "Catan", "13"], ...]

# Fetch auction bids from a BGG geeklist
BggData.fetch_auction_bids(geeklist_id, 'username')
```

### Collection status options

`own`, `fortrade`, `prevowned`, `want`, `wanttoplay`, `wanttobuy`, `wishlist`, `preordered`

### Interactive console

```bash
bin/console
```

## MCP Server

BggData includes an MCP server so Claude (and other MCP-compatible AI clients) can call BGG data lookups as tools.

```bash
bin/mcp_server
```

### Available tools

| Tool | Description | Arguments |
|------|-------------|-----------|
| `GetCollectionTool` | Fetch a user's game collection | `user_name` (required), `status` (optional, default: `"own"`) |
| `GetGamesInfoTool` | Get detailed info for one or more games | `game_ids` (required, array of strings) |
| `GetAuctionBidsTool` | Retrieve auction bids from a BGG geeklist | `geeklist_id` (required, integer), `username` (required) |

### Configuring Claude Desktop

Add the following to your Claude Desktop MCP config:

```json
{
  "mcpServers": {
    "bgg_data": {
      "command": "/path/to/bgg_data/bin/mcp_server"
    }
  }
}
```

## Development

```bash
bin/setup       # Install dependencies
bin/console     # Start an interactive console

rake spec       # Run tests
rake rubocop    # Run linter
rake            # Run both (default)
```

## License

Released under the [MIT License](LICENSE.txt).
