# frozen_string_literal: true

RSpec.describe BggData do
  it "has a version number" do
    expect(BggData::VERSION).not_to be nil
  end

  describe ".extract_condition" do
    def extract_condition(body)
      described_class.send(:extract_condition, body)
    end

    it "returns nil when body is nil" do
      expect(extract_condition(nil)).to be_nil
    end

    it "returns nil when no condition keyword is present" do
      expect(extract_condition("Great game, shipping worldwide.")).to be_nil
    end

    it "matches 'like new' without being swallowed by 'good'" do
      expect(extract_condition("Condition: like new, never played.")).to eq("like new, never played")
    end

    it "prefers 'very good' over the looser 'good' match" do
      expect(extract_condition("It's in very good shape overall.")).to eq("very good shape overall")
    end

    it "matches plain 'good'" do
      expect(extract_condition("Box is good, minor shelf wear.")).to eq("good, minor shelf wear")
    end

    it "matches 'played'" do
      expect(extract_condition("Lightly played cards, box is fine.")).to eq("played cards, box is fine")
    end

    it "matches the Greek keyword κατάσταση" do
      expect(extract_condition("Κατάσταση: πολύ καλή")).to eq("Κατάσταση: πολύ καλή")
    end

    it "stops at the next sentence" do
      expect(extract_condition("Good. Ships tomorrow.")).to eq("Good")
    end
  end

  describe ".geeklist" do
    let(:response_hash) do
      {
        "geeklist" => {
          "item" => [
            {
              "objectid" => "266192",
              "objectname" => "Wingspan",
              "username" => "alice",
              "body" => "Very good condition, box has minor shelf wear."
            },
            {
              "objectid" => "174430",
              "objectname" => "Gloomhaven",
              "username" => "bob",
              "body" => ("x" * 250)
            }
          ]
        }
      }
    end

    before do
      # A plain double, not instance_double: HTTParty::Response exposes `to_h` via
      # dynamic delegation to the parsed body rather than as a real instance method
      # (see the same note on stub_geeklist_response below), so it isn't safe to
      # verify against the class.
      response = double("response", code: 200, body: "", to_h: response_hash)
      allow(HTTParty).to receive(:get).and_return(response)
    end

    it "returns bgg_id, name, username, condition, and a 200-char comment for each item" do
      result = described_class.geeklist(12_345)

      expect(result).to eq(
        [
          {
            bgg_id: "266192",
            name: "Wingspan",
            username: "alice",
            condition: "Very good condition, box has minor shelf wear",
            comment: "Very good condition, box has minor shelf wear."
          },
          {
            bgg_id: "174430",
            name: "Gloomhaven",
            username: "bob",
            condition: nil,
            comment: "x" * 200
          }
        ]
      )
    end
  end

  describe ".fetch_auction_bids" do
    def stub_geeklist_response(response_hash)
      # A plain double, not instance_double: fetch_auction_bids calls `.include?`
      # directly on the HTTParty::Response object (to detect BGG's "still processing"
      # placeholder body) rather than on `.body`, and that method only exists via
      # HTTParty::Response's dynamic delegation to the parsed body, not as a real
      # instance method, so it isn't safe to verify against the class.
      response = double("response", to_h: response_hash, include?: false)
      allow(HTTParty).to receive(:get).and_return(response)
    end

    # Comment shape matches BGG's real xmlapi2/geeklist response with comments=1: each
    # is a Hash with "__content__" (the text) and "username" (who posted it), among
    # other fields (date, postdate, editdate, thumbs) that fetch_auction_bids ignores.
    def comment(username, content)
      { "__content__" => content, "username" => username }
    end

    it "keeps a bidder's last numeric comment and ignores the seller and non-numeric replies" do
      stub_geeklist_response(
        "geeklist" => {
          "item" => [
            {
              "objectname" => "Far Away",
              "username" => "kgkan",
              "comment" => [
                comment("Stelan", "\nIs this the '20 or '22 edition??\n"),
                comment("kgkan", "\nIt's the '20 edition\n"),
                comment("Stelan", "\n20.\n")
              ]
            }
          ]
        }
      )

      expect(described_class.fetch_auction_bids(12_345)).to eq([{ "Far Away" => { "Stelan" => 20 } }])
    end

    it "tracks each bidder's own last bid across multiple bidders on the same item" do
      stub_geeklist_response(
        "geeklist" => {
          "item" => [
            {
              "objectname" => "Meadow",
              "username" => "kgkan",
              "comment" => [
                comment("bill6261", "\n25\n"),
                comment("PANAOS1125", "\n26\n"),
                comment("bill6261", "\n27\n"),
                comment("PANAOS1125", "\n28\n")
              ]
            }
          ]
        }
      )

      expect(described_class.fetch_auction_bids(12_345)).to eq(
        [{ "Meadow" => { "bill6261" => 27, "PANAOS1125" => 28 } }]
      )
    end

    it "returns an empty breakdown for an item with no bids yet" do
      stub_geeklist_response(
        "geeklist" => {
          "item" => [
            { "objectname" => "Brazil: Imperial", "username" => "kgkan", "comment" => nil }
          ]
        }
      )

      expect(described_class.fetch_auction_bids(12_345)).to eq([{ "Brazil: Imperial" => {} }])
    end

    it "handles a single reply that BGG collapses from an Array to a bare Hash" do
      stub_geeklist_response(
        "geeklist" => {
          "item" => [
            {
              "objectname" => "Neanderthal",
              "username" => "kgkan",
              "comment" => comment("PANAOS1125", "\n20\n")
            }
          ]
        }
      )

      expect(described_class.fetch_auction_bids(12_345)).to eq([{ "Neanderthal" => { "PANAOS1125" => 20 } }])
    end

    it "returns an empty array instead of raising when BGG's response has no geeklist/item data" do
      # Regression test: BGG's geeklist-comments generation is asynchronous, and an
      # in-between response whose body doesn't match the pending-message text can slip
      # past the retry loop, leaving response['geeklist'] nil. This used to raise
      # `undefined method '[]' for nil:NilClass` instead of returning [].
      stub_geeklist_response({})

      expect(described_class.fetch_auction_bids(12_345)).to eq([])
    end

    it "does not raise when a single-item geeklist collapses 'item' from an Array to a Hash" do
      stub_geeklist_response(
        "geeklist" => {
          "item" => {
            "objectname" => "Wingspan",
            "username" => "kgkan",
            "comment" => comment("alice", "45")
          }
        }
      )

      expect(described_class.fetch_auction_bids(12_345)).to eq([{ "Wingspan" => { "alice" => 45 } }])
    end
  end
end
