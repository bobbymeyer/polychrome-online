# frozen_string_literal: true

require "rails_helper"

# A campaign's art and music needs, as a baible skeleton (baible's SKELETON.md).
RSpec.describe BaibleSkeleton do
  let!(:world) { base_world }
  let(:campaign) { base_campaign }
  let(:picture) { file_fixture("goblin.png") }
  let(:starter) { [ "Character", "Character sprite", "Portrait", "Model sheet", "Costume", "Character design sheet", "Creature", "Item", "Emblem", "Location", "Scene", "Map", "Music" ] }

  def skeleton = described_class.new(campaign.reload).data
  def by_ref(data = skeleton) = data["assets"].index_by { |a| a["ref"] }
  def upload = Rack::Test::UploadedFile.new(picture, "image/png")

  it "writes format 1 for this campaign's project, every asset with a unique ref, a kind baible has, and a parent in the file" do
    data = skeleton
    expect(data).to include("baible_skeleton" => 1, "source" => "polychrome", "starter_kinds" => true)
    expect(data["project"]["name"]).to eq(campaign.name)
    refs = data["assets"].map { |a| a["ref"] }
    expect(refs).to eq(refs.uniq)
    kinds = starter + data["kinds"].map { |k| k["name"] }
    expect(data["assets"].map { |a| a["kind"] }.uniq - kinds).to be_empty
    expect(data["assets"].filter_map { |a| a["from"] }.uniq - refs).to be_empty
    data["assets"].group_by { |a| a["kind"] }.each_value { |list| expect(list.map { |a| a["name"] }).to eq(list.map { |a| a["name"] }.uniq) }
    expect(JSON.generate(data).bytesize).to be < 5.megabytes
  end

  it "asks for someone's design, a portrait in every expression they lack, and their sprite, and asks for less as art comes in" do
    cid = campaign.npcs.create!(name: "Cid", title: "Engineer", description: "Fixes airships, and talks to them.")
    assets = by_ref
    expect(assets["npc/#{cid.id}"]).to include("kind" => "Character", "name" => "Cid", "entry" => "Cid", "notes" => "Engineer")
    expect(assets["npc/#{cid.id}/portrait"]).to include("kind" => "Portrait", "from" => "npc/#{cid.id}")
    expect(assets["npc/#{cid.id}/portrait"]["variants"].map { |v| [ v["name"], v["ref"] ] })
      .to eq(%w[happy sad angry surprised worried determined].map { |e| [ e, "npc/#{cid.id}/portrait/#{e}" ] })
    expect(assets["npc/#{cid.id}/sprite"]).to include("kind" => "Character sprite", "from" => "npc/#{cid.id}")
    expect(skeleton["entries"]).to include("name" => "Cid", "lore" => "Engineer. Fixes airships, and talks to them.")

    cid.update_portraits!(uploads: { "neutral" => upload, "happy" => upload }, sprite_upload: upload)
    assets = by_ref
    expect(assets["npc/#{cid.id}/portrait"]["variants"].map { |v| v["name"] }).to eq(%w[sad angry surprised worried determined])
    expect(assets).not_to have_key("npc/#{cid.id}/sprite")

    cid.update_portraits!(uploads: %w[sad angry surprised worried determined].index_with { upload })
    expect(by_ref.keys.grep(%r{\Anpc/#{cid.id}})).to be_empty # nothing left to make, not even the design
  end

  it "asks for the party too, and tells a character apart from someone in the cast of the same name" do
    campaign.npcs.create!(name: "Bartz")
    bartz = base_character(campaign, name: "Bartz", player_name: "Ines")
    assets = by_ref
    expect(assets["character/#{bartz.id}"]).to include("entry" => "Bartz (Ines)", "notes" => bartz.job.name)
    expect(skeleton["entries"].map { |e| e["name"] }).to include("Bartz", "Bartz (Ines)")
    expect(assets["job/#{bartz.job.id}"]).to include("kind" => "Archetype", "name" => bartz.job.name)
  end

  it "asks for the books the campaign uses with no picture yet, and its music, a boss's own theme too" do
    boss = world.monsters.create!(slug: "lich_king", name: "Lich King", level: 20, boss: true, stats: world.monsters.first.stats, description: "Bones, a crown.")
    campaign.npcs.create!(name: "The King Below", monster: boss)
    campaign.set_out!(from_the_setting: true)
    node = campaign.map_nodes.where.not(location_id: nil).first
    assets = by_ref
    expect(assets["monster/#{boss.id}"]).to include("kind" => "Creature", "name" => "Lich King", "notes" => "Bones, a crown.")
    expect(assets["monster/#{boss.id}/theme"]).to include("kind" => "Music", "name" => "Lich King theme")
    expect(assets["template/#{node.location.location_template_id}"]).to include("kind" => "Location")
    expect(assets.keys).to include(*World::MUSIC.map { |scene| "world/#{world.id}/music/#{scene}" })

    boss.image.attach(io: picture.open, filename: "lich.png", content_type: "image/png")
    expect(by_ref).not_to have_key("monster/#{boss.id}")
  end
end
