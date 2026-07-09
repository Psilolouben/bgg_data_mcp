# BGG Data MCP — Claude Context

## Project Overview

Ruby MCP server (fast-mcp gem) that provides Claude with live BoardGameGeek data.
Located at `~/Projects/bgg_data`.

### Available MCP Tools

| Tool | Description |
|------|-------------|
| `GetCollectionTool` | Fetches a user's BGG collection. Supports `status:` param: `own`, `fortrade`, `prevowned`, `want`, `wanttoplay`, `wanttobuy`, `wishlist`, `preordered`. BGG API quirk: items can have multiple statuses simultaneously (e.g. `own=1` AND `fortrade=1`) — pass `own=1&fortrade=1` to get currently-owned for-trade items. |
| `GetGamesInfoTool` | Fetches BGG game data by IDs (max 20 per call). Returns rank, mechanics, best player counts, weight. |
| `GetGeeklistTool` | Fetches all items from a BGG geeklist. Supports auto-pagination (150 items/page, 2s sleep between pages), 202 retry logic, and optional server-side filtering against a user's collection via `username:` + `mode:` ("want"/"have"/"all"). Returns token-optimised `{id, n, u}` tuples plus separate money entries. |

### BGG API Notes

- Geeklist endpoint: `https://boardgamegeek.com/xmlapi2/geeklist/{id}?comments=0&start={offset}&count=150`
- Collection endpoint: `https://boardgamegeek.com/xmlapi2/collection?username={u}&own=1`
- BGG returns HTTP 202 when data is being prepared — retry up to 5 times with 2s sleep
- BGG blocks web crawlers (robots.txt) but server-side API calls work fine
- Player count votes are the most reliable "best at N" signal — use the highest vote count

---

## Taste Scoring Model

A weighted scoring engine (0–100) for predicting how much the primary user (psilolouben / Marky) would enjoy a board game. Built iteratively across multiple sessions.

**Profile data lives in:** `scoring/profiles/marky.json`
**Scoring engine lives in:** `scoring/taste_model.py`

Run it:
```bash
python3 scoring/taste_model.py --game "Faiyum"
python3 scoring/taste_model.py --list games.txt
python3 scoring/taste_model.py --all  # scores everything in profile candidates
```

### The 10 Factors

| # | Factor | Max pts | Notes |
|---|--------|---------|-------|
| 1 | **Taste fit** | 25 | Mechanic overlap with confirmed sweet-spot list |
| 2 | **Anchor similarity** | 20 | Overlap with mechanics of 9+ rated games |
| 3 | **BGG rank** | 15 | Confidence-adjusted (see below) |
| 4 | **Collection gap** | 15 | New mechanics not yet in collection |
| 5 | **Designer pedigree** | 10 | Proportional: `(avg_rating/10) × min(n_owned/3, 1.0) × 10` |
| 6 | **Weight alignment** | 7 | Sweet spot 3.0–4.5; peaks at 3.5 |
| 7 | **Player count fit** | 5 | Bonus for covering 4 and/or 5 players |
| 8 | **Prior play experience** | 10 | Played externally (BGA, friend's copy) and liked it |
| 9 | **Discount / value** | 2 | Discount percentage (tiebreaker only) |
| 10 | **Recency confidence** | 1 | Year ≥ 2018 and sufficient BGG votes |

**Total: 110 points max** (prior play experience added as bonus, can exceed 100)

**Modifiers (subtracted):**
- `aesthetic_penalty`: –3 to –15 for games visually/thematically similar to a rejected game
- Example: Age of Innovation inherits Terra Mystica's aesthetic penalty because same hex map / wooden disc design

### Factor Details

#### 1. Taste Fit (25 pts)
Games matching ≥4 of the sweet-spot mechanics score full 25.

Sweet-spot mechanics:
`worker placement, network building, card driven, asymmetric, heavy euro, engine building, economic, political, area control, semi-coop, hidden roles, traitor, campaign, deck building, industrial, rondel, action retrieval, tech tree`

#### 2. Anchor Similarity (20 pts)
For each anchor game, compute `(rating/10) × (mechanic_overlap / anchor_mechanic_count) × 8`.
Cap total at 20. Only count anchors where overlap ≥ 2 mechanics.

#### 3. BGG Rank — Confidence Adjusted (15 pts)

| Effective rank | Points |
|---------------|--------|
| ≤ 10 | 15 |
| ≤ 50 | 13 |
| ≤ 100 | 11 |
| ≤ 200 | 9 |
| ≤ 500 | 6 |
| ≤ 1000 | 3 |
| > 1000 | 1 |

**Confidence adjustment:** If a game has fewer than 100 BGG votes, use publisher prior instead of actual rank.
- 0–49 votes: use prior entirely
- 50–99 votes: linear blend between actual rank and prior
- 100+ votes: trust actual rank fully

Known publisher priors:
- GMT Games card-driven historical: ~500
- Splotter Spellen: ~300
- New/unknown: no prior, use actual rank

#### 4. Collection Gap (15 pts)
`min(new_mechanics × 3 + gap_mechanic_hits × 3, 15)`

Gap mechanics (especially novel for this collection):
`polyomino, industrial, stock market, action retrieval, tech tree, commodity speculation`

Note: A game scoring 0 on gap ("all mechanics already owned") is not penalised for being in a favourite genre — it just doesn't get a bonus. Consider adjusting interpretation for "depth collector" vs "breadth collector" profiles.

#### 5. Designer Pedigree (10 pts)
`(avg_rating_of_owned_games / 10) × min(n_games_owned / 3, 1.0) × 10`

- 1 game owned = max 33% of score
- 2 games owned = max 66%
- 3+ games owned = max 100%
- Unrated owned games contribute to ownership count but not to avg (use 7.5 prior)
- Previously owned games count (e.g. sold/traded copies)

#### 6. Weight Alignment (7 pts)
| BGG weight | Points |
|-----------|--------|
| 3.0–4.5 | 7 (sweet spot) |
| 2.5–2.9 | 4 |
| < 2.5 | 1 |
| > 4.5 | 5 (doable but niche) |

#### 7. Player Count Fit (5 pts)
| Best players | Points |
|-------------|--------|
| Includes both 4 and 5 | 5 |
| Includes 4 or 5 | 3 |
| Best at 3 | 2 |
| Other | 1 |

#### 8. Prior Play Experience (10 pts) ⭐
The strongest signal available — overrides most model uncertainty.

| Experience | Points |
|-----------|--------|
| Played externally, loved it (8+) | +10 |
| Played externally, liked it (7–7.9) | +7 |
| Played externally, lukewarm (6–6.9) | –5 |
| Played externally, disliked it (<6) | –10 |
| Never played (no signal) | 0 |

**Important:** Only applies to games played externally (BGA, friend's copy, convention). Games already in the collection are handled via anchor similarity using the actual rating. Do not double-count.

#### 9. Discount / Value (2 pts)
| Discount | Points |
|---------|--------|
| ≥ 50% | 2.0 |
| ≥ 30% | 1.5 |
| ≥ 20% | 1.0 |
| < 20% | 0.5 |

Tiebreaker only. A bad game at 80% off is still a bad game.

#### 10. Recency Confidence (1 pt)
Full point if: year ≥ 2018 AND BGG rank < 5000.
Half point otherwise (old design, or insufficient community data).

### Aesthetic Penalty

Applied when a game shares the visual/thematic identity of a game the user is selling or rated negatively:

| Situation | Penalty |
|-----------|---------|
| Direct spiritual successor of rejected game (same map, same pieces) | –12 |
| Similar aesthetic/theme, different mechanics | –5 |
| Slightly dated visual design | –3 |

**Current active penalties:**
- Age of Innovation: –12 (same hex map + wooden discs as Terra Mystica which user is selling for aesthetic reasons)

### Expansion Scoring

Expansions use a separate sub-formula (not comparable to standalone scores):

```
score = (parent_rating/10 × 40)     # how much you love the base game
      + (min(plays/10, 1.0) × 20)   # how often you table it
      + (25 if adds_new_mechanics else 12)  # content depth
      + 10                            # value baseline
```

Max ≈ 85. Compare expansion scores only against each other, not against standalone scores.

**Cosmetic expansions** (holographic cards, art variants, upgraded components with no gameplay change): score = N/A, flag separately.

---

## Known Model Limitations & Decisions

1. **Gap score paradox**: Faiyum scores 0/15 on gap because all its mechanics (network building, economic, card driven) are already in the collection. But being "more of what you love" is arguably a positive. The model treats this as neutral (no bonus) rather than negative — which is correct but may undervalue depth-first purchases.

2. **BGG mechanics tags are imperfect**: SETI's BGG mechanics don't fully capture its engine-building / tech-tree nature. When BGG tags are clearly incomplete, supplement with known mechanics from reviews.

3. **Expansion double-scoring risk**: If a base game is already in anchors (e.g. TtA rated 9.5), its expansion gets anchor score from similarity to itself. This slightly inflates expansion scores — acceptable for now.

4. **Terra Mystica status**: Currently owned, rated 7.8, being sold for aesthetic reasons (feels outdated, utilitarian design). All games inheriting TM's aesthetic should receive the aesthetic penalty regardless of mechanical quality.

5. **Prior play experience not retroactive**: If a game in the collection was played on BGA before purchase, the actual rating now supersedes the prior play signal — don't add both.

---

## Primary User Profile

**BGG username:** psilolouben
**Name:** Marky
**Location:** Athens, Greece
**Gaming context:** 300+ game collection, heavy euro focus, regular 4–5 player sessions

See `scoring/profiles/marky.json` for full anchor list, designer pedigree, and prior play experiences.
