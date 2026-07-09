#!/usr/bin/env python3
"""
BGG Taste Scoring Model
=======================
Scores board games 0-100+ based on predicted enjoyment for a given user profile.
See CLAUDE.md for full documentation of the model and its factors.

Usage:
    python3 scoring/taste_model.py --game "Faiyum"
    python3 scoring/taste_model.py --score-all candidates.json
    python3 scoring/taste_model.py --profile scoring/profiles/marky.json --game "Faiyum"
"""

import json
import argparse
import sys
from pathlib import Path


# ─────────────────────────────────────────────────────────────
# LOAD PROFILE
# ─────────────────────────────────────────────────────────────

def load_profile(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


# ─────────────────────────────────────────────────────────────
# FACTOR 1: TASTE FIT (25 pts)
# ─────────────────────────────────────────────────────────────

def score_taste_fit(mechanics: list, sweet_spot: list) -> float:
    """
    Score based on mechanic overlap with the user's sweet-spot list.
    Capped at 25 — hitting 4+ sweet spot mechanics gets full score.
    """
    hits = sum(1 for m in mechanics if m in sweet_spot)
    return round(min(hits / 4, 1.0) * 25, 1)


# ─────────────────────────────────────────────────────────────
# FACTOR 2: ANCHOR SIMILARITY (20 pts)
# ─────────────────────────────────────────────────────────────

def score_anchor_similarity(mechanics: list, anchors: dict) -> float:
    """
    For each anchor game, compute contribution based on mechanic overlap
    weighted by the anchor's rating. Cap total at 20.
    Only count anchors with >= 2 mechanic overlaps.
    """
    total = 0.0
    for game_name, anchor in anchors.items():
        rating = anchor["rating"]
        anchor_mechanics = anchor["mechanics"]
        overlap = len(set(mechanics) & set(anchor_mechanics))
        if overlap >= 2:
            contribution = (rating / 10) * (overlap / len(anchor_mechanics)) * 8
            total += contribution
    return round(min(total, 20), 1)


# ─────────────────────────────────────────────────────────────
# FACTOR 3: BGG RANK — CONFIDENCE ADJUSTED (15 pts)
# ─────────────────────────────────────────────────────────────

def rank_to_points(rank: int) -> int:
    if rank <= 10:    return 15
    elif rank <= 50:  return 13
    elif rank <= 100: return 11
    elif rank <= 200: return 9
    elif rank <= 500: return 6
    elif rank <= 1000: return 3
    else:             return 1


def score_bgg_rank(bgg_rank: int, bgg_votes: int,
                   publisher: str = None,
                   publisher_priors: dict = None,
                   confidence_threshold: int = 100) -> tuple:
    """
    Returns (points, effective_rank, note).

    If votes < threshold and a publisher prior exists, blend or replace
    the actual rank with the publisher's historical average rank.

    - 0–49 votes: use prior entirely
    - 50–99 votes: linear blend between actual and prior
    - 100+ votes: trust actual rank fully
    """
    prior = None
    if publisher and publisher_priors:
        prior = publisher_priors.get(publisher)

    if prior is None or bgg_votes >= confidence_threshold:
        eff_rank = bgg_rank
        note = ""
    elif bgg_votes < 50:
        eff_rank = prior
        note = f"prior only ({bgg_votes} votes)"
    else:
        blend = (bgg_votes - 50) / 50
        eff_rank = int(bgg_rank * blend + prior * (1 - blend))
        note = f"blended ({bgg_votes} votes)"

    return rank_to_points(eff_rank), eff_rank, note


# ─────────────────────────────────────────────────────────────
# FACTOR 4: COLLECTION GAP (15 pts)
# ─────────────────────────────────────────────────────────────

def score_collection_gap(mechanics: list,
                         owned_mechanics: list,
                         gap_mechanics: list) -> float:
    """
    Score based on how many new mechanics this game introduces.
    Gap mechanics (especially novel) contribute more.
    """
    new_mechanics = [m for m in mechanics if m not in owned_mechanics]
    gap_hits = sum(1 for m in mechanics if m in gap_mechanics)
    raw = len(new_mechanics) * 3 + gap_hits * 3
    return round(min(raw, 15), 1)


# ─────────────────────────────────────────────────────────────
# FACTOR 5: DESIGNER PEDIGREE (10 pts)
# ─────────────────────────────────────────────────────────────

def score_pedigree(designer: str, designer_data: dict,
                   max_score: float = 10.0,
                   unrated_prior: float = 7.5) -> tuple:
    """
    Proportional pedigree:
      score = (avg_rating / 10) × min(n_owned / 3, 1.0) × max_score

    Unrated games count toward ownership count but not rating average.
    Returns (score, n_owned, avg_rating).
    """
    data = designer_data.get(designer, {})
    games = data.get("games", [])

    if not games:
        return 0.0, 0, None

    n_owned = len(games)
    rated = [g for g in games if g.get("rating") is not None]
    n_rated = len(rated)

    if n_rated == 0:
        avg = unrated_prior
    else:
        avg = sum(g["rating"] for g in rated) / n_rated

    ownership_factor = min(n_owned / 3, 1.0)
    score = (avg / 10) * ownership_factor * max_score
    return round(score, 1), n_owned, round(avg, 2)


# ─────────────────────────────────────────────────────────────
# FACTOR 6: WEIGHT ALIGNMENT (7 pts)
# ─────────────────────────────────────────────────────────────

def score_weight(weight: float, sweet_min: float = 3.0, sweet_max: float = 4.5) -> int:
    if sweet_min <= weight <= sweet_max:  return 7
    elif 2.5 <= weight < sweet_min:       return 4
    elif weight < 2.5:                    return 1
    else:                                 return 5  # above sweet spot: still possible


# ─────────────────────────────────────────────────────────────
# FACTOR 7: PLAYER COUNT FIT (5 pts)
# ─────────────────────────────────────────────────────────────

def score_player_count(best_players: list, preferred: list = None) -> int:
    preferred = preferred or [4, 5]
    covers_preferred = [p for p in preferred if p in best_players]
    if len(covers_preferred) == len(preferred):  return 5   # covers all preferred counts
    elif len(covers_preferred) >= 1:             return 3   # covers at least one
    elif 3 in best_players:                      return 2
    else:                                        return 1


# ─────────────────────────────────────────────────────────────
# FACTOR 8: PRIOR PLAY EXPERIENCE (10 pts)
# ─────────────────────────────────────────────────────────────

def score_prior_play(game_name: str, prior_plays: dict) -> int:
    """
    Only for games played externally (BGA, friend's copy, convention).
    Games already in the collection use their actual rating via anchors.
    """
    return prior_plays.get(game_name, {}).get("score", 0)


# ─────────────────────────────────────────────────────────────
# FACTOR 9: DISCOUNT / VALUE (2 pts)
# ─────────────────────────────────────────────────────────────

def score_discount(retail: float = None, sale: float = None,
                   discount_pct: float = None) -> float:
    """
    Pass either (retail, sale) or discount_pct directly.
    Tiebreaker only — a bad game at 80% off is still a bad game.
    """
    if discount_pct is None:
        if retail and sale and retail > 0:
            discount_pct = (retail - sale) / retail
        else:
            return 1.0  # neutral if no price data

    if discount_pct >= 0.50:   return 2.0
    elif discount_pct >= 0.30: return 1.5
    elif discount_pct >= 0.20: return 1.0
    else:                      return 0.5


# ─────────────────────────────────────────────────────────────
# FACTOR 10: RECENCY CONFIDENCE (1 pt)
# ─────────────────────────────────────────────────────────────

def score_recency(year: int, bgg_rank: int) -> float:
    if year >= 2018 and bgg_rank < 5000:
        return 1.0
    elif year < 2015:
        return 0.5
    else:
        return 0.8


# ─────────────────────────────────────────────────────────────
# AESTHETIC PENALTY
# ─────────────────────────────────────────────────────────────

def get_aesthetic_penalty(game_name: str, penalties: dict) -> int:
    entry = penalties.get(game_name, {})
    return entry.get("penalty", 0)


# ─────────────────────────────────────────────────────────────
# EXPANSION SCORING (separate sub-scale, max ~85)
# ─────────────────────────────────────────────────────────────

def score_expansion(parent_rating: float, parent_plays: int,
                    adds_new_mechanics: bool,
                    is_cosmetic: bool = False) -> float:
    """
    Expansion scores are NOT comparable to standalone scores.
    Compare expansion scores only against other expansion scores.

    Cosmetic expansions (art variants, holographic cards, upgraded
    components with no gameplay change) return 0 and should be
    flagged separately.
    """
    if is_cosmetic:
        return 0.0

    # Use conservative prior if parent is unrated
    rating = parent_rating if parent_rating is not None else 7.0

    base     = (rating / 10) * 40
    play_fac = min(parent_plays / 10, 1.0) * 20
    content  = 25 if adds_new_mechanics else 12
    value    = 10

    return round(base + play_fac + content + value, 1)


# ─────────────────────────────────────────────────────────────
# MAIN SCORER
# ─────────────────────────────────────────────────────────────

def score_game(game: dict, profile: dict) -> dict:
    """
    Score a standalone game against a user profile.

    game dict keys:
      name, bgg_rank, bgg_votes, weight, mechanics, designer,
      best_players, year,
      publisher (optional, for confidence adjustment),
      retail (optional), sale (optional), discount_pct (optional)

    Returns dict with total score and factor breakdown.
    """
    name        = game["name"]
    bgg_rank    = game["bgg_rank"]
    bgg_votes   = game.get("bgg_votes", 500)
    weight      = game["weight"]
    mechanics   = game["mechanics"]
    designer    = game.get("designer", "")
    publisher   = game.get("publisher", designer)
    best_p      = game.get("best_players", [3, 4])
    year        = game.get("year", 2020)

    taste = score_taste_fit(
        mechanics,
        profile["taste"]["sweet_spot_mechanics"]
    )

    anchor = score_anchor_similarity(
        mechanics,
        profile["anchors"]
    )

    bgg, eff_rank, bgg_note = score_bgg_rank(
        bgg_rank, bgg_votes,
        publisher=publisher,
        publisher_priors=profile.get("publisher_priors", {}),
    )

    gap = score_collection_gap(
        mechanics,
        profile["collection_mechanics_owned"],
        profile["taste"]["gap_mechanics"]
    )

    ped, n_owned, avg_rating = score_pedigree(
        designer,
        profile["designer_pedigree"]
    )

    wt = score_weight(
        weight,
        sweet_min=profile["taste"]["weight_sweet_spot"][0],
        sweet_max=profile["taste"]["weight_sweet_spot"][1]
    )

    pc = score_player_count(
        best_p,
        preferred=profile["taste"].get("preferred_player_counts", [4, 5])
    )

    prior = score_prior_play(
        name,
        profile.get("prior_play_experience", {})
    )

    val = score_discount(
        retail=game.get("retail"),
        sale=game.get("sale"),
        discount_pct=game.get("discount_pct")
    )

    rec = score_recency(year, bgg_rank)

    aes = get_aesthetic_penalty(
        name,
        profile.get("aesthetic_penalties", {})
    )

    total = taste + anchor + bgg + gap + ped + wt + pc + prior + val + rec - aes

    return {
        "name":          name,
        "total":         round(total, 1),
        "taste":         taste,
        "anchor":        anchor,
        "bgg":           bgg,
        "bgg_rank":      bgg_rank,
        "eff_rank":      eff_rank,
        "bgg_note":      bgg_note,
        "gap":           gap,
        "pedigree":      ped,
        "pedigree_n":    n_owned,
        "pedigree_avg":  avg_rating,
        "weight":        wt,
        "player_count":  pc,
        "prior_play":    prior,
        "value":         val,
        "recency":       rec,
        "aesthetic_pen": aes,
    }


def print_breakdown(result: dict) -> None:
    print(f"\n{'='*60}")
    print(f"  {result['name']} — {result['total']}/100")
    print(f"{'='*60}")
    print(f"  Taste fit:          {result['taste']:>5}/25")
    print(f"  Anchor similarity:  {result['anchor']:>5}/20")
    print(f"  BGG rank:           {result['bgg']:>5}/15  "
          f"(#{result['bgg_rank']} → eff #{result['eff_rank']}"
          f"{' '+result['bgg_note'] if result['bgg_note'] else ''})")
    print(f"  Collection gap:     {result['gap']:>5}/15")
    print(f"  Designer pedigree:  {result['pedigree']:>5}/10  "
          f"({result['pedigree_n']} games, avg {result['pedigree_avg']})")
    print(f"  Weight alignment:   {result['weight']:>5}/7")
    print(f"  Player count:       {result['player_count']:>5}/5")
    print(f"  Prior play:         {result['prior_play']:>5}/10")
    print(f"  Discount/value:     {result['value']:>5}/2")
    print(f"  Recency:            {result['recency']:>5}/1")
    if result['aesthetic_pen']:
        print(f"  Aesthetic penalty: -{result['aesthetic_pen']:>4}")
    print(f"{'='*60}")
    print(f"  TOTAL:              {result['total']:>5}")
    print(f"{'='*60}\n")


def print_ranking(results: list) -> None:
    results_sorted = sorted(results, key=lambda x: -x["total"])
    print(f"\n{'#':<3} {'Game':<32} {'Score':>6} {'Taste':>5} "
          f"{'Anc':>4} {'BGG':>4} {'Gap':>4} {'Ped':>4} {'Wt':>3} "
          f"{'PC':>3} {'Pri':>4} {'Val':>4}")
    print("─" * 90)
    for i, r in enumerate(results_sorted, 1):
        print(f"{i:<3} {r['name']:<32} {r['total']:>6} {r['taste']:>5} "
              f"{r['anchor']:>4} {r['bgg']:>4} {r['gap']:>4} {r['pedigree']:>4} "
              f"{r['weight']:>3} {r['player_count']:>3} {r['prior_play']:>4} "
              f"{r['value']:>4}")


# ─────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Score board games against a user taste profile"
    )
    parser.add_argument(
        "--profile",
        default="scoring/profiles/marky.json",
        help="Path to user profile JSON"
    )
    parser.add_argument(
        "--game",
        help="Score a single game interactively (prompts for details)"
    )
    parser.add_argument(
        "--score-all",
        metavar="FILE",
        help="Score all games in a JSON candidates file and rank them"
    )
    parser.add_argument(
        "--breakdown",
        action="store_true",
        help="Show full factor breakdown (used with --score-all)"
    )

    args = parser.parse_args()

    # Load profile
    profile_path = Path(args.profile)
    if not profile_path.exists():
        print(f"Error: profile not found at {profile_path}", file=sys.stderr)
        sys.exit(1)

    profile = load_profile(profile_path)

    if args.score_all:
        candidates_path = Path(args.score_all)
        if not candidates_path.exists():
            print(f"Error: candidates file not found at {candidates_path}", file=sys.stderr)
            sys.exit(1)

        with open(candidates_path) as f:
            candidates = json.load(f)

        results = []
        for game in candidates:
            result = score_game(game, profile)
            results.append(result)
            if args.breakdown:
                print_breakdown(result)

        print_ranking(results)

    elif args.game:
        print(f"\nScoring: {args.game}")
        print("Enter game details (press Enter to use defaults):")

        bgg_rank  = int(input("  BGG rank [999]: ") or 999)
        bgg_votes = int(input("  BGG votes [500]: ") or 500)
        weight    = float(input("  BGG weight [3.0]: ") or 3.0)
        mechanics_raw = input("  Mechanics (comma-separated): ")
        mechanics = [m.strip() for m in mechanics_raw.split(",") if m.strip()]
        designer  = input("  Designer: ").strip()
        best_p_raw = input("  Best players (comma-separated) [3,4]: ") or "3,4"
        best_p    = [int(x.strip()) for x in best_p_raw.split(",")]
        year      = int(input("  Year [2022]: ") or 2022)
        retail    = input("  Retail price (optional): ").strip()
        sale      = input("  Sale price (optional): ").strip()

        game = {
            "name":         args.game,
            "bgg_rank":     bgg_rank,
            "bgg_votes":    bgg_votes,
            "weight":       weight,
            "mechanics":    mechanics,
            "designer":     designer,
            "best_players": best_p,
            "year":         year,
        }
        if retail and sale:
            game["retail"] = float(retail)
            game["sale"]   = float(sale)

        result = score_game(game, profile)
        print_breakdown(result)

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
