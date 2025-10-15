# frozen_string_literal: true

require_relative "bgg_data/version"

module BggData
  require "active_support/core_ext/hash"
  require 'httparty'

  COLLECTION_BASE_URL = "https://www.boardgamegeek.com/xmlapi2/collection"
  BOARDGAME_BASE_URL = "https://www.boardgamegeek.com/xmlapi2/thing"

  class Error < StandardError; end

  def self.search_by_title(title)
    uri = Addressable::URI.parse("https://www.boardgamegeek.com/xmlapi2/search")
    uri.query_values = { query: title, type: "boardgame" }

    bgg_response = HTTParty.get(uri.normalize.to_s)
    [bgg_response.to_h.with_indifferent_access.dig("items", "item")]&.flatten&.map do |x|
      [title, x&.dig("name", "value"), x&.dig("id")]
    end
  end

  def self.games_info(game_ids)
    bgg_response = HTTParty.get(BOARDGAME_BASE_URL + "?id=#{game_ids.join(",")}&stats=1")
    bgg_response.to_h["items"]["item"].map do |thing|
      {
        id: thing["id"],
        name: if thing["name"].is_a?(Array)
                thing["name"].select do |g|
                  g["type"] == "primary"
                end.first["value"]
              else
                thing["name"]["value"]
              end,
        mechs: thing["link"].select { |t| t["type"] == "boardgamemechanic" }.map { |b| b["value"] },
        rank: thing["statistics"]["ratings"]["ranks"].any? ? thing["statistics"]["ratings"]["ranks"] : 888_888_888_888,
        players: thing["poll"].first["results"].map { |x| { x["numplayers"] => recommended_players(x["result"]) } },
        weight: thing["statistics"]["ratings"]["averageweight"]["value"].to_f
      }
    end
  end

  def self.filter(username, params)
    bgg_collection = collection(username, params)
    thing_ids = bgg_collection.map { |x| x[:bgg_id] }

    games = things(thing_ids)

    # filter by number of players
    binding.pry
  end

  def self.recommended_players(players_hash)
    {
      recommended: (players_hash[0]["numvotes"].to_i + players_hash[1]["numvotes"].to_i) / players_hash.sum do |x|
                                                                                             x["numvotes"].to_f
                                                                                           end,
      not_recommended: players_hash[2]["numvotes"].to_i / players_hash.sum { |x| x["numvotes"].to_f }
    }
  end

  def self.collection(username, params = {})
    collection_url = COLLECTION_BASE_URL + "?username=#{username}&own=1"
    collection_url += "&minbggrating=#{params[:minbggrating]}" if params[:minbggrating]
    ::HTTParty.get(collection_url)
    sleep(6)
    bgg_response = ::HTTParty.get(collection_url)
    return unless bgg_response

    bgg_response.to_h["items"]["item"]&.map do |game|
      {
        name: game["name"]["__content__"],
        bgg_id: game["objectid"],
        plays: game["numplays"].to_i
      }
    end
  end
end
