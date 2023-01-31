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
end
