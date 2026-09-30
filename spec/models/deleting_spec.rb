# frozen_string_literal: true

require "rails_helper"

# A campaign, and a whole world, can be deleted: everything that belongs to
# them goes with them (the models' `dependent:`, since the foreign keys are
# plain), and nothing else. Built out as far as play takes it, then deleted,
# every table is back to what it held before.
RSpec.describe "Deleting" do
  include ActiveJob::TestHelper

  # Rows in every table the app keeps (stored files are purged later, by a job).
  def rows
    connection = ActiveRecord::Base.connection
    (connection.tables - %w[schema_migrations ar_internal_metadata active_storage_blobs active_storage_variant_records])
      .to_h { |table| [ table, connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(table)}") ] }
  end

  let(:world) { World.create!(name: "Doomed", slug: "doomed").tap { |w| w.copy_books_from!(base_world) } }

  def play(campaign)
    hero = create_character(campaign, name: "Rook", job: world.jobs.find_by!(slug: "knight"))
    town = campaign.locations.create!(location_template: world.location_templates.find_by!(slug: "village"), seed: 3)
    home = campaign.map_nodes.create!(name: "Varn", x: 10, y: 10, visible: true, location: town)
    away = campaign.map_nodes.create!(name: "Tule", x: 90, y: 10)
    campaign.map_edges.create!(from_node: home, to_node: away)
    campaign.update!(current_node: home)
    mode = town.map_node.modes.create!(name: "Burning", line: "Smoke.")
    campaign.clocks.create!(name: "The fire spreads", segments: 3, mode: mode)
    npc = campaign.npcs.create!(name: "Cid", location: town)
    npc.portraits.create!(expression: "neutral")
    campaign.secrets.create!(body: "Cid lit it.", location: town, npc: npc)
    campaign.flags.create!(key: "met_cid", value: "yes")
    campaign.scenes.create!(name: "Smoke", script: "Narrator: The town burns.", map_node: home, mode: mode, ending: "mode")
    campaign.record_deed!("Rook put out the fire.", sway: 2)
    campaign.start_rumour!("The mill grinds at night.", at: away)
    campaign.add_item!(world.items.find_by!(slug: "potion"))
    Message.choice(campaign, options: %w[Stay Go]).tap(&:save!).picks.create!(character: hero, option: "Go")
    battle = start_battle(campaign: campaign, goblins: 1)
    battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
    ArtBatch.start!(world.monsters.find_by!(slug: "goblin"), count: 1)
    campaign
  end

  it "takes a campaign and everything in it, and leaves its world" do
    world
    before = rows
    campaign = play(world.campaigns.create!(name: "Doomed Road"))
    expect(campaign.messages.where.not(battle_id: nil)).to exist

    campaign.destroy!
    world_art = %w[art_batches art_candidates art_types] # the goblin's art is the world's
    expect(rows.except(*world_art)).to eq(before.except(*world_art))
  end

  it "takes a world: its books, canon, history, campaigns and art" do
    before = rows
    Chronicle.new(world).write!
    play(world.campaigns.create!(name: "Doomed Road"))

    world.destroy!
    expect(rows).to eq(before)
  end
end
