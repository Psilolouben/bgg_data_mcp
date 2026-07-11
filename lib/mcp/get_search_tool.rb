class GetSearchTool < FastMcp::Tool
  description "Search BoardGameGeek for board games and expansions by title"
  # These arguments will generate the needed JSON to be presented to the MCP Client
  # And they will be validated at run time.
  # The validation is based off Dry-Schema, with the addition of the description.
  arguments do
    required(:query).filled(:string).description("Search term to look up on BoardGameGeek")
  end

  def call(query:)
    BggData.search(query)
  end
end
