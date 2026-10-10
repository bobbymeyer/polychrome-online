# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/campaigns/just_seven")

# A GM's prep as a module: exported, carried to a world, made a campaign again.
RSpec.describe CampaignModule do
  before { World.where(slug: "oda").destroy_all }

  let(:gm) { User.create!(name: "Bobby", email_address: "gm@example.com", password: "a-long-enough-password") }
  let(:other_gm) { User.create!(name: "Ines", email_address: "ines@example.com", password: "a-long-enough-password") }
  let(:picture) { file_fixture("goblin.png").binread }

  # What a campaign's prep amounts to, for comparing one with its import.
  def prep(campaign)
    {
      places: campaign.map_nodes.order(:name).map { |n| [ n.name, n.kind, n.visible, n.notes, n.modes.map(&:name) ] },
      rooms: campaign.locations.select(&:dungeon?).map { |l| [ l.name, l.view["rooms"].map { |r| [ r["name"], r["decision"] ] } ] }.sort,
      towns: campaign.locations.select(&:town?).map { |l| [ l.name, l.view["services"].map { |s| s["kind"] } ] }.sort,
      roads: campaign.map_edges.map { |e| [ e.from_node.name, e.to_node.name, e.state ] }.sort,
      cast: campaign.npcs.order(:name).map { |n| [ n.name, n.title, n.monster&.slug, n.location&.name ] },
      clocks: campaign.clocks.order(:name).map { |c| [ c.name, c.segments, c.portents, c.mode&.name, c.map_node&.name ] },
      secrets: campaign.secrets.order(:key).map { |s| [ s.key, s.body, s.steps, s.npc&.name, s.location&.name ] },
      scenes: campaign.scenes.order(:name).map { |s| [ s.name, s.ending, s.encounter, s.map_node&.name, s.beats.map { |b| [ b.kind, b.speaker&.name, b.text ] } ] },
      flags: campaign.flags.order(:key).map { |f| [ f.key, f.value, f.note ] },
      start: campaign.current_node&.name
    }
  end

  describe "The Just Seven, out and back in" do
    let!(:original) { Seeds::JustSeven.run(gm: gm) }

    it "comes back as the same prep, in a world that had none of its books, which it brings" do
      zip = CampaignModule::Export.new(original).to_zip
      before = prep(original)
      World.where(slug: "oda").destroy_all
      world = Seeds::Oda.run # Oda as seeded: none of The Just Seven in its books
      expect(world.monsters.find_by(slug: "crab")).to be_nil

      campaign = CampaignModule::Import.new(zip, world: world, gm: other_gm).run!
      expect(prep(campaign)).to eq(before)
      expect(campaign.gm).to eq(other_gm)
      expect(world.monsters.find_by!(slug: "crab").phases.first["becomes"]).to eq("crab_frenzied")
      expect(world.items.masks.count).to eq(7)
      expect(campaign.map_nodes.find_by!(name: "Founders' Hill").location.resident_villain.name).to eq("Amethyst 7A")
      expect(campaign.rumours.pluck(:body)).to match_array(Seeds::JustSeven::RUMOURS)
      expect(campaign.gil).to eq(Campaign::STARTING_GIL)
    end

    it "adds nothing to a world that has its books already, and never changes an entry that's there" do
      original.world.monsters.find_by!(slug: "crab").update!(name: "The GM's Crab")
      zip = CampaignModule::Export.new(original).to_zip
      import = CampaignModule::Import.new(zip, world: original.world, gm: other_gm)
      expect(import.missing_books).to be_empty
      expect { import.run! }.not_to(change { [ Monster.count, Ability.count, Item.count ] })
      expect(original.world.monsters.find_by!(slug: "crab").name).to eq("The GM's Crab")
    end

    it "is refused, with what's missing, to someone who can't add to the world's books, and leaves nothing behind" do
      zip = CampaignModule::Export.new(original).to_zip
      World.where(slug: "oda").destroy_all
      world = Seeds::Oda.run
      import = CampaignModule::Import.new(zip, world: world, gm: other_gm, can_add_books: false)
      expect { import.run! }.to raise_error(Refusal, /needs \d+ entries Oda's books don't have \(.*Crab.*\), and only the world's editors can add them/)
      expect(world.campaigns.count).to eq(0)
      expect(world.monsters.find_by(slug: "crab")).to be_nil
    end

    it "carries none of the play: clocks empty, secrets kept, scenes unplayed, rooms unexplored, nobody defeated" do
      original.clocks.first.tick!(3)
      original.secrets.first.update!(revealed_at: Time.current, found: 1)
      original.scenes.first.play!
      dock = original.map_nodes.find_by!(name: "The Airship Dock")
      dock.location.update!(progress: { "current" => "room-0", "visited" => [ "room-0" ] })
      original.npcs.find_by!(name: "Mob Leader").update!(defeated_at: Time.current, escapes: 2)

      campaign = CampaignModule::Import.new(CampaignModule::Export.new(original).to_zip, world: original.world, gm: other_gm).run!
      expect(campaign.clocks.sum(:filled)).to eq(0)
      expect(campaign.secrets.revealed).to be_empty
      expect(campaign.scenes.where.not(played_at: nil)).to be_empty
      expect(campaign.locations.map(&:progress)).to all(eq({}))
      expect(campaign.npcs.find_by!(name: "Mob Leader")).to have_attributes(defeated_at: nil, escapes: 0)
      expect(campaign.characters).to be_empty
    end
  end

  it "carries its pictures: maps, portraits, sprites, panels and its entries' art" do
    campaign = Seeds::JustSeven.run(gm: gm)
    campaign.root_map.image.attach(io: StringIO.new(picture), filename: "island.png", content_type: "image/png")
    seer = campaign.npcs.find_by!(name: "The Seer")
    seer.portraits.create!(expression: "angry").image.attach(io: StringIO.new(picture), filename: "seer.png", content_type: "image/png")
    campaign.world.monsters.find_by!(slug: "crab").image.attach(io: StringIO.new(picture), filename: "crab.png", content_type: "image/png")

    zip = CampaignModule::Export.new(campaign).to_zip
    archive = PackageArchive.read(zip, format: CampaignModule::FORMAT)
    expect(archive.assets.size).to eq(1) # one picture, used three times, travels once
    World.where(slug: "oda").destroy_all
    world = Seeds::Oda.run
    imported = CampaignModule::Import.new(zip, world: world, gm: gm).run!
    expect(imported.root_map.image.download).to eq(picture)
    expect(imported.npcs.find_by!(name: "The Seer").own_portrait_image("angry").download).to eq(picture)
    expect(world.monsters.find_by!(slug: "crab").image.download).to eq(picture)
  end

  it "reads a tampered module's places as far as they make sense, and no further" do
    campaign = Seeds::JustSeven.run(gm: gm)
    data = CampaignModule::Export.new(campaign).data
    dock = data["places"].find { |place| place["name"] == "The Airship Dock" }
    dock["location"]["overrides"] = { "name" => "The Dock", "boss" => { "kraken_of_nowhere" => 9, "crab" => 99 }, "pins" => { "room-1" => "junk" },
                                      "added_rooms" => [ { "key" => "added-1", "connect" => "room-0", "decision" => { "kind" => "explode" } } ],
                                      "progress" => { "current" => "room-3" }, "tables" => { "rooms" => [] } }
    zip = PackageArchive.new(CampaignModule::FORMAT, data).to_zip
    imported = CampaignModule::Import.new(zip, world: campaign.world, gm: other_gm).run!
    location = imported.map_nodes.find_by!(name: "The Airship Dock").location
    expect(location.overrides).to eq("name" => "The Dock", "boss" => { "crab" => 8 })
    expect(location.view["rooms"]).to be_present
  end

  describe PackageArchive do
    def read(source) = described_class.read(source, format: CampaignModule::FORMAT)

    def zip(entries)
      Zip::OutputStream.write_buffer(StringIO.new) do |out|
        entries.each { |name, body| out.put_next_entry(name); out.write(body) }
      end.string
    end

    it "refuses what isn't a module" do
      expect { read("not a zip at all") }.to raise_error(Refusal, /isn't a campaign module/)
      expect { read(zip("notes.txt" => "hi")) }.to raise_error(Refusal, /has no module.json/)
      expect { read(zip("module.json" => { "format" => "something-else" }.to_json)) }.to raise_error(Refusal, /isn't a campaign module/)
      newer = { "format" => CampaignModule::FORMAT, "version" => CampaignModule::VERSION + 1 }.to_json
      expect { read(zip("module.json" => newer)) }.to raise_error(Refusal, /newer version/)
    end

    it "reads module.json and pictures under assets/, and nothing else" do
      body = { "format" => CampaignModule::FORMAT, "version" => 1 }.to_json
      archive = read(zip("module.json" => body, "assets/abc.png" => "png", "../evil.rb" => "puts 1", "assets/x.rb" => "nope"))
      expect(archive.assets.keys).to eq([ "assets/abc.png" ])
    end
  end
end
