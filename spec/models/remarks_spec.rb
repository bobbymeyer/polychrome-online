# frozen_string_literal: true

require "rails_helper"

RSpec.describe Campaign::Remarks do
  let(:world) { base_world }
  let(:campaign) { base_campaign }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:crossing) { campaign.map_nodes.create!(name: "Crossing", kind: "field", x: 1, y: 1, visible: true) }
  let(:hollin) do
    campaign.map_nodes.create!(name: "Hollin", kind: "town", x: 5, y: 5, location: campaign.locations.create!(location_template: village, seed: 3))
  end
  let(:road) { campaign.map_edges.create!(from_node: crossing, to_node: hollin) }
  let!(:vivi) { create_character(campaign, name: "Vivi", home_node: hollin) }

  before do
    world.generator_tables.where(kind: "arrivals").destroy_all
    campaign.update!(current_node: crossing, time_of_day: "night")
  end

  def arrivals(*rows)
    world.generator_tables.create!(name: "Arrivals", slug: "arrivals_#{SecureRandom.hex(2)}", kind: "arrivals", entries: rows)
  end

  def offers = campaign.messages.where(scope: "gm").select { |m| m.data["offer"] }

  it "knows the moment: where, when, how the party is, its clocks and flags" do
    campaign.flags.create!(key: "met_the_king", value: "yes")
    campaign.clocks.create!(name: "The wolves gather", segments: 6, filled: 2)
    facts = campaign.moment(at: hollin)
    expect(facts).to include("place" => "Hollin", "town" => true, "first_visit" => true, "visits" => 0, "time" => "night", "night" => true,
                             "dark" => true, "days" => 1, "party" => 1, "hurt" => 0, "down" => 0, "home" => "Vivi", "standing" => "strangers",
                             "reputation" => 0, "met_the_king" => "yes", "clock_the_wolves_gather" => 2)
  end

  it "keeps the light apart from the day count: a row for the day doesn't fit at night" do
    campaign.update!(time_of_day: "night", day: 3)
    facts = campaign.moment(at: hollin)
    expect(facts).to include("days" => 3, "night" => true)
    expect(facts).not_to have_key("day")
    expect(Story::Matcher.best([ { "text" => "By day.", "when" => "day" } ], facts, 1).last).to be_nil
  end

  it "offers the GM the line that fits the arrival best, and says nothing for them" do
    arrivals({ "text" => "{place}." }, { "text" => "{place}, and {home} home.", "when" => "town" },
             { "text" => "A dungeon.", "when" => "dungeon" })
    campaign.travel!(road)

    note = offers.sole
    expect(note.body).to eq("To say, arriving at Hollin: “Hollin, and Vivi home.”")
    expect(campaign.messages.where(scope: "table", kind: "say")).to be_empty
    expect(Message.visible_to(campaign, Seat.of(vivi))).not_to include(note)
    expect(campaign.reload.visits_to(hollin)).to eq(1)
  end

  it "says the line once the GM does, and remembers what its row sets, so the next arrival hears another" do
    arrivals({ "text" => "A lit window, watching.", "when" => "town, !watcher_seen", "sets" => "watcher_seen, sightings + 1" },
             { "text" => "The window again.", "when" => "town, watcher_seen" })
    campaign.travel!(road)
    campaign.say_offer!(offers.sole)

    expect(campaign.messages.where(scope: "table", kind: "say").pluck(:body)).to eq([ "A lit window, watching." ])
    expect(campaign.flags.pluck(:key, :value)).to contain_exactly([ "watcher_seen", "yes" ], [ "sightings", "1" ])
    expect { campaign.say_offer!(offers.sole.reload) }.to raise_error(Refusal, "Already said.")

    campaign.place_party!(crossing)
    campaign.place_party!(hollin)
    expect(offers.last.body).to end_with("“The window again.”")
  end

  it "offers nothing when no row fits, and never a row that names the table's lines or veils" do
    arrivals({ "text" => "Spiders on every wall.", "when" => "town" })
    campaign.draw_limit!("veil", "spiders")
    campaign.travel!(road)
    expect(offers).to be_empty
  end
end
