# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe "The asset pipeline (§8)", type: :request do
  include ActiveJob::TestHelper

  let!(:world) { Seeds::BaseWorld.run }
  let(:goblin) { world.monsters.find_by!(slug: "goblin") }
  let(:comfy) { FakeComfy.new }

  def generate(count: 2, notes: "a rusty knife", loras: { "0" => { "name" => "goblin.safetensors", "strength" => "0.6" } })
    post world_art_batches_path(world), params: { entry_type: "monster", entry_slug: "goblin", count: count,
                                                  entry: { art_notes: notes, art_loras: loras } }
  end

  def finish(batch)
    ArtBatchJob.new.perform(batch.reload, client: comfy)
    comfy.finish!(*comfy.submitted.each_index.map { |i| "prompt-#{i + 1}" })
    ArtBatchJob.new.perform(batch.reload, client: comfy)
  end

  it "shows the layers and the composed prompt on the entry's page" do
    world.update!(art_style: "16-bit pixel art")
    get world_bestiary_monster_path(world, goblin)
    expect(response.body).to include("The prompt, in layers", "16-bit pixel art", world.art_type("monster").prompt,
                                      "turbo-cable-stream-source", 'name="turbo-refresh-method" content="morph"')
  end

  it "saves the entry's own layer, then queues a batch of candidates" do
    expect { generate }.to have_enqueued_job(ArtBatchJob)
    expect(response).to redirect_to(world_bestiary_monster_path(world, goblin, anchor: "art"))
    goblin.reload
    expect(goblin.art_notes).to eq("a rusty knife")
    expect(goblin.art_loras).to eq([ { "name" => "goblin.safetensors", "strength" => 0.6 } ])
    batch = goblin.art_batch
    expect(batch.candidates.size).to eq(2)
    expect(batch.recipe["positive"]).to end_with("Goblin, a rusty knife")
    expect(batch.recipe["loras"]).to eq([ { "name" => "goblin.safetensors", "strength" => 0.6 } ])
  end

  it "shows candidates as they land, and picking one makes it the image with its seed and recipe" do
    generate
    batch = goblin.art_batch
    finish(batch)
    get world_bestiary_monster_path(world, goblin)
    expect(response.body).to include("Candidates", "Use this", "Seed #{batch.candidates.first.seed}")

    winner = batch.candidates.last
    post pick_world_art_candidate_path(world, winner)
    goblin.reload
    expect(goblin.image).to be_attached
    expect(goblin.image_seed).to eq(winner.seed)
    expect(goblin.image_prompt).to eq(batch.recipe["positive"])
    expect(goblin.image_recipe).to eq(batch.recipe)
    expect(ArtBatch.exists?(batch.id)).to be(false)

    follow_redirect!
    expect(response.body).to include("Generated, seed <strong>#{winner.seed}</strong>")
  end

  it "replaces the previous batch when generating again, and can discard one" do
    generate
    first = goblin.art_batch
    generate
    expect(ArtBatch.exists?(first.id)).to be(false)

    delete world_art_batch_path(world, goblin.reload.art_batch)
    expect(goblin.reload.art_batch).to be_nil
  end

  it "won't pick a candidate that isn't finished" do
    generate
    post pick_world_art_candidate_path(world, goblin.art_batch.candidates.first)
    expect(flash[:alert]).to eq("That candidate has no image")
    expect(goblin.reload.image).not_to be_attached
  end

  it "forgets the seed and recipe when an image is uploaded by hand" do
    generate
    finish(goblin.art_batch)
    post pick_world_art_candidate_path(world, goblin.art_batch.candidates.first)
    expect(goblin.reload.image_seed).to be_present

    upload = Rack::Test::UploadedFile.new(StringIO.new(FakeComfy.png), "image/png", original_filename: "goblin.png")
    patch world_bestiary_monster_path(world, goblin), params: { monster: { image: upload } }
    expect(goblin.reload).to have_attributes(image_seed: nil, image_prompt: nil, image_recipe: nil)
    expect(goblin.image).to be_attached
  end

  it "edits the world and type layers on the art direction page" do
    get world_art_direction_path(world)
    expect(response.body).to include("house style", "Monsters", "Locations")

    patch world_art_direction_path(world), params: {
      world: { art_style: "ink wash", art_negative: "photo", art_checkpoint: "", art_loras: { "0" => { "name" => "ink", "strength" => "0.9" } } },
      types: { monster: { prompt: "profile view, full body", width: "768", height: "768", transparent: "0",
                          loras: { "0" => { "name" => "sprites", "strength" => "" } } },
               nope: { prompt: "ignored" } }
    }
    expect(response).to redirect_to(world_art_direction_path(world))
    expect(world.reload).to have_attributes(art_style: "ink wash", art_loras: [ { "name" => "ink", "strength" => 0.9 } ])
    expect(world.art_type("monster")).to have_attributes(prompt: "profile view, full body", width: 768, transparent: false,
                                                          loras: [ { "name" => "sprites", "strength" => 1.0 } ])
    expect(goblin.art_recipe["positive"]).to start_with("ink wash, profile view, full body, Goblin")
  end

  it "rejects a size ComfyUI can't use" do
    patch world_art_direction_path(world), params: { world: { art_style: "x" }, types: { monster: { width: "10" } } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Width must be in 256..2048")
  end
end
