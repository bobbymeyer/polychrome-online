# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Camp and road events: offered to the GM, put to the table, settled" do
  let(:world) { base_world }
  let(:campaign) { base_campaign(gil: 100) }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let!(:crossing) { campaign.map_nodes.create!(name: "Crossing", kind: "field", x: 1, y: 1, visible: true) }
  let!(:hollin) do
    campaign.map_nodes.create!(name: "Hollin", kind: "town", x: 5, y: 5, visible: true, location: campaign.locations.create!(location_template: village, seed: 3))
  end
  let!(:road) { campaign.map_edges.create!(from_node: crossing, to_node: hollin) }
  let!(:rook) { create_character(campaign, name: "Rook") }
  let(:potion) { world.items.find_by!(slug: "potion") }

  before do
    world.generator_tables.where(kind: %w[events arrivals]).destroy_all
    campaign.update!(current_node: crossing)
  end

  def events(*rows)
    world.generator_tables.create!(name: "Events", slug: "events_#{SecureRandom.hex(2)}", kind: "events", entries: rows)
  end

  def offers = campaign.messages.where(scope: "gm").select { |m| m.data["offer"] }

  it "reads a choice's options, what each does and the flag it sets, and says what it can't read" do
    choices, problems = EventChoices.parse("Share the fire: give potion, rumour | Send her off: tick -> shared_fire")
    expect(problems).to be_empty
    expect(choices).to have_attributes(flag: "shared_fire", options: [ { "label" => "Share the fire", "does" => [ "give potion", "rumour" ] },
                                                                      { "label" => "Send her off", "does" => [ "tick" ] } ])
    expect(EventChoices.parse("A: rest | B: money 5").last).to eq([ "“A”: rest isn't something a choice can do (money, exp, abp, rumour, restore, reveal, give potion…)" ])
    table = world.generator_tables.new(name: "Bad", slug: "bad_events", kind: "events", entries: [ { "text" => "x", "choices" => "A: give unicorn | B: exp 5" } ])
    expect(table).not_to be_valid
    expect(table.errors.full_messages.to_sentence).to include("nothing in the Armory is called unicorn")
  end

  it "offers the GM what happens at camp, puts its choice to the table, and does what the option settled on says" do
    events({ "text" => "A stranger asks to share the fire.", "when" => "camp, !stranger_met", "sets" => "stranger_met",
             "choices" => "Let her sit: give potion, money 10 | Send her off: lose 20 -> shared_fire" },
           { "text" => "Somebody's at the inn.", "when" => "inn" })
    campaign.add_item!(potion, 2)
    campaign.sleep!(bed: false)

    note = offers.sole
    expect(note.body).to eq("An event, at camp: “A stranger asks to share the fire.” Let her sit: the party gives up a Potion, 10 gil for the party · " \
                            "Send her off: the party loses 20 gil")
    expect(campaign.open_choice).to be_nil

    campaign.say_offer!(note)
    choice = campaign.reload.open_choice
    expect(choice.options).to eq([ "Let her sit", "Send her off" ])
    expect(campaign.flags.find_by!(key: "stranger_met").value).to eq("yes")

    choice.settle!("Let her sit")
    expect(campaign.quantity_of(potion)).to eq(1)
    expect(campaign.reload.gil).to eq(110)
    expect(campaign.flags.find_by!(key: "shared_fire").value).to eq("Let her sit")
    expect(campaign.messages.where(scope: "table").last(3).map(&:body))
      .to eq([ "The party chose: Let her sit.", "The party gives up a Potion.", "The party: 10 gil." ])
  end

  it "drops what can't happen now, and offers nothing with fewer than two options left" do
    events({ "text" => "A beggar asks for a potion.", "choices" => "Give one: give potion | Walk past: exp 5" })
    campaign.sleep!(bed: false)
    expect(offers).to be_empty # nothing to give

    events({ "text" => "{hurt_one} can't keep up.", "when" => "road, hurt_one", "choices" => "Slow down: time 1 | Push on: hurt 10" })
    rook.update!(hp: rook.stats["max_hp"] / 3) # under half, with HP to lose
    campaign.travel!(road)
    expect(offers.last.body).to start_with("An event, on the road: “Rook can't keep up.”")
  end

  it "has no event on a road that had a fight on it" do
    events({ "text" => "Quiet road.", "when" => "road" })
    campaign.update!(pending_encounter: { "name" => "Goblins", "monsters" => { "goblin" => 1 } })
    expect(campaign.offer_event!("travel")).to be_nil
  end

  it "knows who of the party is tied to whom, and where they're from" do
    mara = campaign.npcs.create!(name: "Mara Vell")
    rook.update!(ties: [ { "npc_id" => mara.id, "text" => "Owes her." } ])
    rook.update_columns(origin: "highlands") # the Base World has no origins of its own
    expect(campaign.moment).to include("tied" => "Rook", "tied_to" => "Mara Vell", "from_highlands" => "Rook")
  end
end
