class GetGeeklistTool < FastMcp::Tool
  description <<~DESC
    Retrieves items from a BoardGameGeek geeklist (e.g. a "for trade"/marketplace listing).

    For each item, returns the game's BGG ID and name, the username offering it,
    a best-effort condition extracted from the listing text (recognizes phrases like
    "like new", "very good", "good", "played", and the Greek "κατάσταση"), and the
    listing's comment text trimmed to 200 characters.
  DESC
  # These arguments will generate the needed JSON to be presented to the MCP Client
  # And they will be validated at run time.
  # The validation is based off Dry-Schema, with the addition of the description.
  arguments do
    required(:geeklist_id)
      .value(:integer)
      .description("Numeric ID of the geeklist")
  end

  def call(geeklist_id:)
    BggData.geeklist(geeklist_id)
  end
end
