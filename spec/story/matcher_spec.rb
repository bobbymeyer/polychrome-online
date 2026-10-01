# frozen_string_literal: true

require "spec_helper"

RSpec.describe Story::Matcher do
  let(:facts) { { "town" => true, "night" => true, "place" => "Hollin", "hurt" => 2, "smoke_seen" => "no" } }

  def best(rows, moment = facts, state = 7, avoid: [])
    described_class.best(rows, moment, state, avoid: avoid).last
  end

  it "picks the row that asks the most of the moment, and falls back to one that asks nothing" do
    rows = [ { "text" => "Quiet." }, { "text" => "A town.", "when" => "town" }, { "text" => "A town by night.", "when" => "town, night" },
             { "text" => "A dungeon by night.", "when" => "dungeon, night, town" } ]
    expect(best(rows)).to include("text" => "A town by night.", "score" => 2)
    expect(best(rows, { "town" => true })["text"]).to eq("A town.")
    expect(best(rows, {})["text"]).to eq("Quiet.")
    expect(best(rows.last(1), {})).to be_nil
  end

  it "reads conditions: negation, numbers and words, with flags that say no as false" do
    fits = ->(w) { !best([ { "text" => "x", "when" => w } ]).nil? }
    expect(fits.("!smoke_seen")).to be(true)
    expect(fits.("not dungeon")).to be(true)
    expect(fits.("hurt >= 2, hurt < 3, hurt != 1")).to be(true)
    expect(fits.("hurt > 2")).to be(false)
    expect(fits.("place = hollin")).to be(true)
    expect(fits.("place != Hollin")).to be(false)
    expect(fits.("town, nonsense here")).to be(false) # a row that can't be read never comes up
  end

  it "says facts and picks words, and a row whose fact isn't there doesn't fit" do
    rows = [ { "text" => "{home} is home." }, { "text" => "Smoke over {place}, {dry|cold|still}." } ]
    line = best(rows)
    expect(line["text"]).to match(/\ASmoke over Hollin, (dry|cold|still)\.\z/)
    expect(best(rows, facts.merge("home" => "Vivi"))["text"]).to eq("Vivi is home.").or match(/Smoke/)
  end

  it "breaks ties with the seeded dice, the same way every time from the same state" do
    rows = %w[A B C D].map { |t| { "text" => t, "when" => "town" } }
    picks = (1..40).map { |seed| best(rows, facts, seed)["text"] }
    expect(picks.uniq.sort).to eq(%w[A B C D])
    expect((1..40).map { |seed| best(rows, facts, seed)["text"] }).to eq(picks)
    expect(described_class.best(rows, facts, 7).first).not_to eq(7)
    expect(described_class.best(rows.first(1), facts, 7).first).to eq(7) # nothing to break, nothing drawn
  end

  it "never offers a row that names one of the table's lines or veils" do
    rows = [ { "text" => "Webs, and a spider the size of a dog.", "when" => "town, night" }, { "text" => "Quiet." } ]
    expect(best(rows, avoid: [ "spiders" ])["text"]).to eq("Quiet.")
    expect(best(rows, avoid: [ "harm to children" ])["text"]).to start_with("Webs")
  end

  it "hands back what the row remembers, and rows rule each other out through it" do
    rows = [ { "text" => "First sight of the smoke.", "when" => "town, !smoke_seen", "sets" => "smoke_seen, sightings + 1, mood = grim" },
             { "text" => "The smoke again.", "when" => "town, smoke_seen" } ]
    line = best(rows)
    expect(line["sets"]).to eq([ { "key" => "smoke_seen", "op" => "=", "value" => "yes" }, { "key" => "sightings", "op" => "+", "value" => 1 },
                                 { "key" => "mood", "op" => "=", "value" => "grim" } ])
    remembered = line["sets"].to_h { |w| [ w["key"], Story::Criteria.written(w, facts[w["key"]]) ] }
    expect(remembered).to eq("smoke_seen" => "yes", "sightings" => "1", "mood" => "grim")
    expect(best(rows, facts.merge(remembered))["text"]).to eq("The smoke again.")
  end
end

RSpec.describe Story::Criteria do
  it "says what it can't read" do
    expect(described_class.parse("town, hurt >= lots").last).to eq([ "“hurt >= lots” isn't something a row can ask: try town, !night, hurt >= 2 or place = Hollin" ])
    expect(described_class.parse_writes("seen, +3").last.size).to eq(1)
    expect(described_class.written({ "op" => "-", "value" => 2 }, "x")).to eq("-2")
  end
end

RSpec.describe Story::Words do
  it "finds a limit only when every word that matters in it is there" do
    expect(described_class.clash("The flies and the spiders.", [ "fly" ])).to eq("fly")
    expect(described_class.clash("Children laugh in the square.", [ "harm to children" ])).to be_nil
    expect(described_class.clash("No harm comes to the children.", [ "harm to children" ])).to eq("harm to children")
    expect(described_class.clash("A glass of water.", [ "to" ])).to be_nil
  end
end
