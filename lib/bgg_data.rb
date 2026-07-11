# frozen_string_literal: true

require_relative "bgg_data/version"

module BggData
  require "active_support/core_ext/hash"
  require 'httparty'
  require 'erb'

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

  GEEKLIST_BASE_URL = "https://www.boardgamegeek.com/xmlapi2/geeklist"

  # Ordered from most to least specific so "very good" isn't reported as "good",
  # and "like new" isn't swallowed by a looser match.
  CONDITION_KEYWORDS = ["like new", "very good", "good", "played", "κατάσταση"].freeze

  GEEKLIST_PENDING_MESSAGE = "Your request for this geeklist has been accepted and will be processed"

  def self.geeklist(id)
    url = "#{GEEKLIST_BASE_URL}/#{id}?comments=0"
    bgg_response = HTTParty.get(url, headers: { Authorization: BEARER_TOKEN })

    while bgg_response.code == 202 || bgg_response.body.to_s.include?(GEEKLIST_PENDING_MESSAGE)
      sleep(1)
      bgg_response = HTTParty.get(url, headers: { Authorization: BEARER_TOKEN })
    end

    items = [bgg_response.to_h.dig("geeklist", "item")].flatten.compact

    items.map do |item|
      body = item["body"]
      {
        bgg_id: item["objectid"],
        name: item["objectname"],
        username: item["username"],
        condition: extract_condition(body),
        comment: body.to_s.strip[0, 200]
      }
    end
  end

  # Best-effort extraction of a condition mention from a geeklist item's body text.
  # Returns the line/sentence containing the first matching keyword, or nil if none found.
  def self.extract_condition(body)
    return nil if body.nil?

    text = body.to_s
    downcased = text.downcase

    CONDITION_KEYWORDS.each do |keyword|
      index = downcased.index(keyword)
      next unless index

      snippet = text[index..].to_s[/\A.*?(?=[\n\r]|\.(?:\s|$)|$)/m].to_s.strip
      return snippet.empty? ? keyword : snippet
    end

    nil
  end
  private_class_method :extract_condition

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

  PLAYS_BASE_URL = "https://www.boardgamegeek.com/xmlapi2/plays"

  def self.plays_by_month(username, year: nil)
    plays = []
    page = 1

    loop do
      url = "#{PLAYS_BASE_URL}?username=#{username}&page=#{page}"
      url += "&mindate=#{year}-01-01&maxdate=#{year}-12-31" if year

      response = HTTParty.get(url, headers: { Authorization: BEARER_TOKEN })
      break unless response.code == 200

      items = response.to_h.dig("plays", "play")
      break if items.nil? || items.empty?

      items = [items] unless items.is_a?(Array)
      plays.concat(items)

      total = response.to_h.dig("plays", "total").to_i
      break if plays.size >= total

      page += 1
    end

    # Group by month, then aggregate games within each month
    grouped = plays.group_by { |p| p["date"]&.slice(0, 7) }.sort.to_h

    grouped.transform_values do |month_plays|
      game_counts = Hash.new(0)
      month_plays.each do |play|
        items = play.dig("item")
        items = [items] unless items.is_a?(Array)
        items.each do |item|
          name = item&.dig("name") || "Unknown"
          quantity = play["quantity"]&.to_i || 1
          game_counts[name] += quantity
        end
      end

      {
        total_plays: month_plays.sum { |p| p["quantity"]&.to_i || 1 },
        games: game_counts.sort_by { |_, v| -v }.map { |name, count| { name: name, plays: count } }
      }
    end
  end

  SEARCH_BASE_URL = "https://www.boardgamegeek.com/xmlapi2/search"
  SEARCHABLE_TYPES = %w[boardgame boardgameexpansion].freeze

  def self.search(query)
    url = SEARCH_BASE_URL + "?query=#{ERB::Util.url_encode(query)}&type=#{SEARCHABLE_TYPES.join(",")}"
    bgg_response = HTTParty.get(url, headers: { Authorization: BEARER_TOKEN })

    retries = 0
    while bgg_response.code == 202 && retries < 5
      sleep(2)
      bgg_response = HTTParty.get(url, headers: { Authorization: BEARER_TOKEN })
      retries += 1
    end

    items = [bgg_response.to_h.dig("items", "item")].flatten.compact

    items.select { |item| SEARCHABLE_TYPES.include?(item["type"]) }
         .map do |item|
           {
             id: item["id"],
             name: item.dig("name", "value"),
             year: item.dig("yearpublished", "value")&.to_i
           }
         end
         .sort_by { |game| -(game[:year] || 0) }
         .first(20)
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
