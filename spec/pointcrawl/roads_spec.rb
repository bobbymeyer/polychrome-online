# frozen_string_literal: true

RSpec.describe Pointcrawl::Roads do
  # 1 — 2 — 3, with 1 — 4 blocked, and 5 on its own.
  let(:roads) do
    [ { "from" => 1, "to" => 2, "state" => "open" }, { "from" => 3, "to" => 2, "state" => "dangerous" },
      { "from" => 1, "to" => 4, "state" => "blocked" } ]
  end

  it "walks roads both ways" do
    expect(described_class.neighbours(roads, 2)).to contain_exactly(1, 3)
  end

  it "finds the nearest wanted place by road, counting where you are" do
    expect(described_class.nearest(roads, 1, [ 3, 4 ])).to eq(4)
    expect(described_class.nearest(described_class.passable(roads), 1, [ 3, 4 ])).to eq(3)
    expect(described_class.nearest(roads, 3, [ 3 ])).to eq(3)
    expect(described_class.nearest(roads, 1, [ 5 ])).to be_nil
  end

  it "breaks a tie by the lowest id, whatever order the roads come in" do
    ring = [ { "from" => 1, "to" => 9, "state" => "open" }, { "from" => 1, "to" => 7, "state" => "open" } ]
    expect(described_class.nearest(ring, 1, [ 9, 7 ])).to eq(7)
    expect(described_class.nearest(ring.reverse, 1, [ 9, 7 ])).to eq(7)
  end

  describe ".route" do
    let(:roads) do
      [ { "id" => 1, "from" => 1, "to" => 2, "state" => "open", "duration" => 1 },
        { "id" => 2, "from" => 2, "to" => 3, "state" => "open", "duration" => 1 },
        { "id" => 3, "from" => 1, "to" => 3, "state" => "open", "duration" => 3 },
        { "id" => 4, "from" => 3, "to" => 4, "state" => "blocked", "duration" => 1 },
        { "id" => 5, "from" => 1, "to" => 5, "state" => "dangerous" } ]
    end

    it "walks the fewest parts of a day, then the fewest roads, never a blocked one" do
      expect(described_class.route(roads, 1, 3).map { |r| r["id"] }).to eq([ 1, 2 ]) # two days, not three
      expect(described_class.route(roads, 3, 1).map { |r| r["id"] }).to eq([ 2, 1 ]) # either way round
      expect(described_class.route(roads, 1, 4)).to be_nil
      expect(described_class.route(roads, 1, 5).map { |r| r["id"] }).to eq([ 5 ]) # a road with no duration counts a day
      expect(described_class.route(roads, 2, 2)).to eq([])
    end
  end
end
