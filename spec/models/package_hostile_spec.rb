# frozen_string_literal: true

require "rails_helper"

# A package is someone else's file (PackageArchive, PackageReading): one made
# to do harm is refused, or comes in as far as it makes sense, and never
# crashes, eats the server's memory or changes books it may not.
RSpec.describe "A package made to do harm" do
  let(:world) { create_world.tap { |w| create_monster(w) && create_monster(w, slug: "wolf", name: "Wolf") } }
  let(:gm) { User.create!(name: "Mallory", email_address: "mallory@example.com", password: "a-long-enough-password") }
  let(:png) { file_fixture("goblin.png").binread }

  def module_zip(data = {}, assets = {}) = PackageArchive.new(CampaignModule::FORMAT, { "format" => CampaignModule::FORMAT, "version" => 1, "name" => "Trouble" }.merge(data), assets).to_zip
  def world_zip(data = {}, assets = {}) = PackageArchive.new(WorldPackage::FORMAT, { "format" => WorldPackage::FORMAT, "version" => 1, "name" => "Trouble" }.merge(data), assets).to_zip
  def import_module(zip, can_add_books: true) = CampaignModule::Import.new(zip, world: world, gm: gm, can_add_books: can_add_books).run!
  def import_world(zip) = WorldPackage::Import.new(zip, owner: gm).run!

  # Comes in, or is refused: nothing else.
  def calmly
    yield
  rescue Refusal
    :refused
  end

  it "is refused when it unpacks to more than a package may hold, however small the zip" do
    zeros = "\0" * 14.megabytes
    zip = module_zip({}, (1..5).to_h { |n| [ "assets/zeros_#{n}.png", zeros ] })
    expect(zip.bytesize).to be < 1.megabyte
    expect { PackageArchive.read(zip, format: CampaignModule::FORMAT) }.to raise_error(Refusal, /unpacks to more than 60 MB/)
  end

  it "adds nothing to the books of a world its importer can't change, an archetype or a nameless entry included" do
    books = { "jobs" => [ { "slug" => "usurper", "name" => "Usurper" } ], "monsters" => [ { "slug" => "  ", "name" => "Sneaky", "level" => 1 } ] }
    expect { import_module(module_zip("books" => books), can_add_books: false) }.not_to(change { [ world.jobs.count, world.monsters.count ] })
    expect(world.campaigns.find_by!(name: "Trouble").gm).to eq(gm)
  end

  it "takes a module's fields only in their shapes: anything else is refused or left out, never a crash" do
    [
      { "books" => "x" }, { "books" => [ 1 ] }, { "books" => { "monsters" => "x" } }, { "maps" => [ 1, "x", nil ] }, { "flags" => [ nil ] },
      { "places" => [ { "ref" => "m", "name" => "Hill", "kind" => "landmark", "modes" => [ 1 ] } ], "rumours" => [ { "body" => "Psst", "at" => "m", "about" => 7 } ] },
      { "maps" => [ { "ref" => "a-map", "name" => "Map" } ], "rumours" => [ { "body" => "Psst", "at" => "a-map" } ] },
      { "scenes" => [ { "name" => "Ambush", "ending" => "battle", "encounter" => { "goblin" => "3", "wolf" => "lots", "dragon" => 2 }, "beats" => [ nil ] } ] },
      { "cast" => [ { "name" => "Ana", "portraits" => "x" } ], "clocks" => [ "x" ], "secrets" => [ 1 ], "roads" => [ [] ] }
    ].each do |data|
      expect { calmly { import_module(module_zip(data)) } }.not_to raise_error, "crashed on #{data.inspect}"
    end
    scene = Scene.find_by!(name: "Ambush")
    expect(scene.encounter).to eq("goblin" => 3) # a count that isn't one, and a monster the world hasn't got, left out
  end

  it "takes a world's setting only in its shapes, and the rest of the world the same way" do
    [
      { "world" => { "calendar" => "x", "terms" => "x", "battle_rules" => [ 1 ], "damage_types" => "x", "voice" => 7 } },
      { "world" => "x", "books" => { "monsters" => [ 1 ] }, "tracks" => [ nil ] },
      { "maps" => [ 1 ], "places" => [ "x" ], "routes" => [ nil ], "figures" => [ 1 ], "codex" => [ nil ] },
      { "fronts" => [ { "name" => "Pressure", "clocks" => [ 1, nil ], "secrets" => [ "x" ] } ] }
    ].each do |data|
      expect { calmly { import_world(world_zip(data)) } }.not_to raise_error, "crashed on #{data.inspect}"
    end
  end

  it "is refused when it holds more of something than any real prep does" do
    flags = Array.new(PackageReading::MAX_ROWS + 1) { |n| { "key" => "flag_#{n}", "value" => "1" } }
    expect { import_module(module_zip("flags" => flags)) }.to raise_error(Refusal, /more than any real one has/)
  end

  it "takes pictures by what their bytes are: an SVG named .png stays out" do
    svg = %(<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>)
    cast = [ { "ref" => "ana", "name" => "Ana", "portraits" => { "neutral" => "assets/ana.png" } },
             { "ref" => "bo", "name" => "Bo", "portraits" => { "neutral" => "assets/bo.png" } } ]
    campaign = import_module(module_zip({ "cast" => cast }, { "assets/ana.png" => svg, "assets/bo.png" => png }))
    portraits = campaign.npcs.to_h { |npc| [ npc.name, npc.portraits.first&.image&.attached? ] }
    expect(portraits).to eq("Ana" => false, "Bo" => true)
  end
end
