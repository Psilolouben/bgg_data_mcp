# frozen_string_literal: true

require_relative "bgg_data/version"

module BggData
  require 'httparty'

  COLLECTION_BASE_URL = 'https://www.boardgamegeek.com/xmlapi2/collection'.freeze
  BOARDGAME_BASE_URL = 'https://www.boardgamegeek.com/xmlapi2/thing'.freeze

  class Error < StandardError; end

  def self.collection(username)
    ::HTTParty.get(COLLECTION_BASE_URL + "?username=#{username}&own=1")
    sleep(2)
    bgg_response = ::HTTParty.get(COLLECTION_BASE_URL + "?username=#{username}&own=1")
    bgg_response.to_h['items']['item'].map do |game|
      {
        name: game['name']['__content__'],
        bgg_id: game['objectid'],
        plays: game['numplays'].to_i
      }
    end
  end

  def self.thing(thing_id)
    bgg_response = HTTParty.get(BOARDGAME_BASE_URL + "?id=#{thing_id}&stats=1")
    thing = bgg_response.to_h['items']['item']
    {
      id: thing['id'],
      name: thing['name'].is_a?(Array) ? thing['name'].select{|g| g['type'] == 'primary'}.first['value'] : thing['name']['value'],
      mechs: thing['link'].select { |t| t['type'] == "boardgamemechanic" }.map{ |b| b['value'] },
      rank: thing['statistics']['ratings']['ranks'].any? ? thing['statistics']['ratings']['ranks'] : 888888888888,
      players: thing['poll'].first['results']
    }
  end
end
