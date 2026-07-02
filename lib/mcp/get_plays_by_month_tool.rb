class GetPlaysByMonthTool < FastMcp::Tool
  description "Get BoardGameGeek plays grouped by month for a user, including games played and play counts per month"

  arguments do
    required(:user_name).filled(:string).description("BoardGameGeek username")
    optional(:year).filled(:integer).description("Filter to a specific year (e.g. 2024). Omit to fetch all plays.")
  end

  def call(user_name:, year: nil)
    BggData.plays_by_month(user_name, year: year)
  end
end
