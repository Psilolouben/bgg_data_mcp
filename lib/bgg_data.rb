# frozen_string_literal: true

require_relative "bgg_data/version"

module BggData
  require "active_support/core_ext/hash"
  require 'httparty'

  COLLECTION_BASE_URL = "https://www.boardgamegeek.com/xmlapi2/collection"
  BOARDGAME_BASE_URL = "https://www.boardgamegeek.com/xmlapi2/thing"
  BEARER_TOKEN = 'Bearer c2d66922-196d-43e5-a1cb-56043f13eebd'

  class Error < StandardError; end

  def self.search_by_title(title)
    uri = Addressable::URI.parse("https://www.boardgamegeek.com/xmlapi2/search")
    uri.query_values = { query: title, type: "boardgame" }

    bgg_response = HTTParty.get(uri.normalize.to_s)
    [bgg_response.to_h.with_indifferent_access.dig("items", "item")]&.flatten&.map do |x|
      [title, x&.dig("name", "value"), x&.dig("id")]
    end
  end

  def self.fetch_auction_bids(geeklist_id, username)
    response = HTTParty.get("https://www.boardgamegeek.com/xmlapi2/geeklist/#{geeklist_id}?comments=1", headers: { Authorization: BEARER_TOKEN })

    while response.include?('Your request for this geeklist has been accepted and will be processed')
      response = HTTParty.get("https://www.boardgamegeek.com/xmlapi2/geeklist/#{geeklist_id}?comments=1", headers: { Authorization: BEARER_TOKEN })
      sleep(1)
    end

    response['geeklist']['item'].
      select{|x| x['username'] == username}.
      map{|y| { y['objectname'] => y&.dig('comment')}}.compact
  end

  def self.games_info(game_ids)
    bgg_response = HTTParty.get(BOARDGAME_BASE_URL + "?id=#{game_ids.join(",")}&stats=1", headers: { Authorization: BEARER_TOKEN })

    while bgg_response.code == 202
      sleep(2)
      bgg_response = HTTParty.get(BOARDGAME_BASE_URL + "?id=#{game_ids.join(",")}&stats=1", headers: { Authorization: BEARER_TOKEN })
    end
    [bgg_response.to_h["items"]["item"]].flatten.map do |thing|
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
        #players: thing["poll"].first["results"].map { |x| { x["numplayers"] => recommended_players(x["result"]) } },
        best_players: thing['poll']&.find{|x| x['name'] == 'suggested_numplayers'}&.dig('results')&.map do |f|
                  {
                    f['numplayers'] => f['result']&.find{|y| y['value'] == 'Best'}&.dig('numvotes')
                  }
                end,
        weight: thing["statistics"]["ratings"]["averageweight"]["value"].to_f,
        minimum_age: thing.dig('minage','value')

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

  COLLECTION_STATUSES = %w[own fortrade prevowned want wanttoplay wanttobuy wishlist preordered].freeze

  def self.collection(username, params = {})
    status = params.fetch(:status, "own")
    raise ArgumentError, "Invalid status: #{status}" unless COLLECTION_STATUSES.include?(status)

    collection_url = COLLECTION_BASE_URL + "?username=#{username}&stats=1"
    collection_url += "&minbggrating=#{params[:minbggrating]}" if params[:minbggrating]
    bgg_response = ::HTTParty.get(collection_url, headers: { Authorization: BEARER_TOKEN })

    while bgg_response.code == 202
      sleep(2)
      bgg_response = ::HTTParty.get(collection_url, headers: { Authorization: BEARER_TOKEN })
    end

    return unless bgg_response

    bgg_response.to_h["items"]["item"]&.select do |game|
      game.dig("status", status) == "1"
    end&.map do |game|
      {
        name: game["name"]["__content__"],
        bgg_id: game["objectid"],
        plays: game["numplays"].to_i,
        rating: game.dig('stats', 'rating', 'value')
      }
    end
  end
end
