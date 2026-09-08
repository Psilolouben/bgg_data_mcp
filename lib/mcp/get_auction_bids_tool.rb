class GetAuctionBidsTool < FastMcp::Tool
  description <<~DESC
    Retrieves the bid breakdown for every item in a BoardGameGeek auction geeklist.

    For each item, treats each numeric comment as a bid, ignores comments from the
    item's own seller and any non-numeric replies, and keeps only the last numeric
    bid from each remaining bidder.
  DESC
  # These arguments will generate the needed JSON to be presented to the MCP Client
  # And they will be validated at run time.
  # The validation is based off Dry-Schema, with the addition of the description.
  arguments do
    required(:geeklist_id)
      .value(:integer)
      .description("Numeric ID of the auction geeklist")
  end

  def call(geeklist_id:)
    BggData.fetch_auction_bids(geeklist_id)
  end
end
