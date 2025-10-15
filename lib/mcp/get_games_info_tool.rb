class GetGamesInfoTool < FastMcp::Tool
  description "Get board games info from boardgamegeek "
  # These arguments will generate the needed JSON to be presented to the MCP Client
  # And they will be validated at run time.
  # The validation is based off Dry-Schema, with the addition of the description.
  arguments do
    required(:game_ids)
      .value(:array)
      .each(:str?)
      .description("Array of BoardGameGeek game IDs")
  end

  def call(game_ids:)
    BggData.games_info(game_ids)
  end
end
