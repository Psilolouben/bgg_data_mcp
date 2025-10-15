class GetCollectionTool < FastMcp::Tool
  description "Get Board game geek game collection of a user given his user name"
  # These arguments will generate the needed JSON to be presented to the MCP Client
  # And they will be validated at run time.
  # The validation is based off Dry-Schema, with the addition of the description.
  arguments do
    required(:user_name).filled(:string).description("Boardgamegeek user name of the user")
  end

  def call(user_name:)
    BggData.collection(user_name)
  end
end
