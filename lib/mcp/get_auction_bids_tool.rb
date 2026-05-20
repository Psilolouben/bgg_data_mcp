class GetAuctionBidsTool < FastMcp::Tool
  description <<~DESC
    Retrieves auction bids from a BoardGameGeek geeklist.

    Treat each numeric comment as a bid.
    For each item, only the last numeric comment from a user other
    than the provided username is considered a valid bid.
    Ignore all non-numeric comments.
  DESC
  # These arguments will generate the needed JSON to be presented to the MCP Client
  # And they will be validated at run time.
  # The validation is based off Dry-Schema, with the addition of the description.
  arguments do
    required(:geeklist_id)
      .value(:integer)
      .description("Numeric ID of the geeklist")

    required(:username)
      .value(:string)
      .description("Username of whom we need the bids")
  end

  def call(geeklist_id:, username:)
    BggData.fetch_auction_bids(geeklist_id, username)
  end
end
