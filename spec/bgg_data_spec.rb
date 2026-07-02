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
      response = instance_double(HTTParty::Response, code: 200, body: "", to_h: response_hash)
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
end
