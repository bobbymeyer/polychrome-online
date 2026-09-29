# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A setting's fronts (WorldFront)", type: :request do
  let!(:world) { base_world_without_atlas } # draws its own map
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let!(:varn) { world.world_places.create!(name: "Varn", kind: "town", x: 200, y: 200, known: true, location_template: village) }
  let!(:mara) { world.world_figures.create!(name: "Mara Vell", world_place: varn) }

  def write_front
    post world_world_fronts_path(world), params: { world_front: {
      name: "The Syndicate's grab", description: "Mara wants the docks.",
      clocks: { "0" => { name: "The Syndicate takes the docks", segments: "4", public: "1", triggers: [ "rest" ], full_line: "Brass seals on every door.",
                         place_id: varn.id, mode_name: "Syndicate town", mode_line: "Varn belongs to Mara now.", mode_description: "Toll on every street." },
                "1" => { name: "" } },
      secrets: { "0" => { body: "Mara's ledger is fake.", figure_id: mara.id, place_id: varn.id }, "1" => { body: "" } }
    } }
    world.world_fronts.find_by!(name: "The Syndicate's grab")
  end

  it "is written once and dealt into a campaign, tied to what the campaign brought in" do
    front = write_front
    expect(front.clocks.sole).to have_attributes(name: "The Syndicate takes the docks", segments: 4, public: true, triggers: [ "rest" ], place: varn)
    expect(front.secrets.sole).to have_attributes(body: "Mara's ledger is fake.", place: varn, figure: mara)

    post world_campaigns_path(world), params: { campaign: { name: "Rust" } }
    campaign = world.campaigns.find_by!(name: "Rust")
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    get campaign_prep_path(campaign)
    expect(response.body).to include("Fronts from #{world.name}", "The Syndicate&#39;s grab")

    post campaign_front_deals_path(campaign), params: { front_id: front.id }
    town = campaign.locations.sole
    clock = campaign.clocks.sole
    expect(clock).to have_attributes(name: "The Syndicate takes the docks", location: town, location_mode: have_attributes(key: "syndicate_town"), world_front: front)
    expect(town.modes.sole).to have_attributes(name: "Syndicate town", line: "Varn belongs to Mara now.")
    expect(campaign.secrets.sole).to have_attributes(body: "Mara's ledger is fake.", npc: campaign.npcs.sole, location: town)

    clock.tick!(4)
    expect(town.reload.current_mode["name"]).to eq("Syndicate town")

    post campaign_front_deals_path(campaign), params: { front_id: front.id }
    expect(flash[:alert]).to include("already in Rust")
  end

  it "needs a clock or a secret, and goes with the world when it's copied" do
    post world_world_fronts_path(world), params: { world_front: { name: "Empty" } }
    expect(response.body).to include("A front needs a clock or a secret")
    write_front
    copy = World.create!(name: "Copy", slug: "copy", owner: @admin)
    copy.copy_books_from!(world)
    copied = copy.world_fronts.sole
    expect(copied.clocks.sole["place_id"]).to eq(copy.world_places.find_by!(name: "Varn").id)
    expect(copied.secrets.sole["figure_id"]).to eq(copy.world_figures.find_by!(name: "Mara Vell").id)
  end

  it "keeps its rows through a save that fails, and lets go of a place taken off the atlas" do
    front = write_front
    patch world_world_front_path(world, front), params: { world_front: { name: "" } }
    expect(front.reload.clocks.count).to eq(1)

    patch world_world_front_path(world, front), params: { world_front: { name: front.name, clocks: { "0" => { name: "" } },
                                                                          secrets: { "0" => { body: "Only this." } } } }
    expect([ front.reload.clocks.count, front.secrets.pluck(:body) ]).to eq([ 0, [ "Only this." ] ])

    write_front_again = world.world_fronts.create!(name: "Again", clocks: [ { "name" => "Tick", "place_id" => varn.id } ])
    varn.destroy!
    expect(write_front_again.clocks.sole.reload.place).to be_nil
  end
end
