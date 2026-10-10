# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/greenware")
require Rails.root.join("db/seeds/campaigns/dead_calm")

# A whole world in one file: exported, and made a new world again.
RSpec.describe WorldPackage do
  let(:author) { User.create!(name: "Ines", email_address: "ines@example.com", password: "a-long-enough-password") }
  let(:picture) { file_fixture("goblin.png").binread }
  # A tenth of a second of silence: a WAV the Music book takes.
  let(:sound) do
    samples = "\x00".b * 800
    "RIFF".b + [ 36 + samples.size ].pack("V") + "WAVEfmt ".b + [ 16, 1, 1, 8000, 8000, 1, 8 ].pack("VvvVVvv") + "data".b + [ samples.size ].pack("V") + samples
  end

  def import(world, **options) = described_class::Import.new(described_class::Export.new(world).to_zip, owner: author, **options).run!

  def books(world)
    PackageBooks::KINDS.to_h { |kind, scope| [ kind, world.public_send(scope).order(:slug).map { |entry| PackageBooks.attributes(entry).except("image") } ] }
  end

  describe "Oda, with Dead Calm's books, its music and its pictures" do
    before { World.where(slug: "oda").destroy_all }

    let!(:campaign) { Seeds::DeadCalm.run }
    let(:oda) { campaign.world }

    it "comes back as a new world, the same book for book, its own, with nothing of its campaigns" do
      track = oda.tracks.create!(name: "Noon theme", source: "upload")
      track.audio.attach(io: StringIO.new(sound), filename: "noon.wav", content_type: "audio/wav")
      oda.monsters.find_by!(slug: "seam_giant").update!(music: "track:#{track.id}")
      oda.monsters.find_by!(slug: "crab").image.attach(io: StringIO.new(picture), filename: "crab.png", content_type: "image/png")
      oda.world_figures.find_by!(name: "Silas Crane").portraits.create!(expression: "happy").image
         .attach(io: StringIO.new(picture), filename: "silas.png", content_type: "image/png")

      copy = import(oda)
      expect(copy).to have_attributes(name: "Oda", slug: "oda_2", owner: author)
      expect(copy.attributes.slice(*WorldPackage::SETTING)).to eq(oda.attributes.slice(*WorldPackage::SETTING))
      original = books(oda)
      copied = books(copy)
      expect(copied.keys).to eq(original.keys)
      original.each_key { |kind| expect(copied[kind].map { |e| e.except("music") }).to eq(original[kind].map { |e| e.except("music") }), kind }
      expect(copy.jobs.find_by!(slug: "bodyguard").abilities.pluck(:slug)).to include("guard", "unbreakable")

      new_track = copy.tracks.sole
      expect(new_track.audio.download).to eq(sound)
      expect(copy.monsters.find_by!(slug: "seam_giant").music).to eq("track:#{new_track.id}")
      expect(copy.monsters.find_by!(slug: "crab").image.download).to eq(picture)
      expect(copy.world_figures.find_by!(name: "Silas Crane").own_portrait_image("happy").download).to eq(picture)

      expect(copy.world_places.pluck(:name)).to match_array(oda.world_places.pluck(:name))
      expect(copy.world_routes.count).to eq(oda.world_routes.count)
      expect(copy.world_figures.find_by!(name: "Silas Crane").monster.world).to eq(copy)
      front = copy.world_fronts.find_by!(name: "What the seam woke")
      expect(front.clocks.first.place.world).to eq(copy)
      expect(copy.codex_entries.pluck(:title)).to match_array(oda.codex_entries.pluck(:title))
      expect(copy.campaigns).to be_empty
    end

    it "starts campaigns of its own, from its atlas and its fronts" do
      copy = import(oda, name: "Oda, again", slug: "oda_again")
      expect(copy.slug).to eq("oda_again")
      played = copy.campaigns.create!(name: "High Noon", gm: author)
      played.set_out!(from_the_setting: true)
      expect(played.current_node.name).to eq("Noonbell")
      expect(played.clocks.pluck(:name)).to include("The seam goes deeper")
      expect(played.npcs.find_by!(name: "Silas Crane").monster.world).to eq(copy)
    end
  end

  describe "Greenware, whose history names its places" do
    before(:all) do
      World.where(slug: "greenware").destroy_all
      Seeds::Greenware.run
    end

    after(:all) { World.where(slug: %w[greenware greenware_2]).destroy_all }

    it "points its history and its history's pages at its own places" do
      greenware = World.find_by!(slug: "greenware")
      copy = import(greenware)
      keys = copy.history.to_json.scan(/place-\d+/).uniq
      expect(keys).not_to be_empty
      expect(keys.map { |key| key.delete_prefix("place-").to_i }).to all(satisfy { |id| copy.world_places.exists?(id) })
      chronicle = Chronicle.new(copy)
      expect(keys.map { |key| chronicle.place_for(key) }).to all(be_present)
      expect(copy.codex_entries.count).to eq(greenware.codex_entries.count)
    end
  end

  it "won't take a campaign module, or anything else, as a world" do
    module_zip = PackageArchive.new(CampaignModule::FORMAT, { "format" => CampaignModule::FORMAT, "version" => 1 }).to_zip
    expect { described_class::Import.new(module_zip, owner: author) }.to raise_error(Refusal, /isn't a world: it has no world.json/)
    expect { described_class::Import.new("junk", owner: author) }.to raise_error(Refusal, /isn't a world/)
  end
end
