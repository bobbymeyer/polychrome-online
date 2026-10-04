# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

RSpec.describe "The asset pipeline (§8)", type: :request do
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  let!(:world) { base_world }
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

  it "only offers Generate while ComfyUI answers" do
    allow(Comfy).to receive(:capabilities).and_return(Comfy::Capabilities.unreachable)
    get world_bestiary_monster_path(world, goblin)
    expect(response.body).to match(/<input[^>]*value="Generate"[^>]*disabled/).and include("Nothing can be generated")

    allow(Comfy).to receive(:capabilities).and_return(FakeComfy.capabilities)
    get world_bestiary_monster_path(world, goblin)
    expect(response.body).not_to match(/<input[^>]*value="Generate"[^>]*disabled/)
  end

  it "shows the layers and the composed prompt on the entry's page" do
    world.update!(art_style: "16-bit pixel art")
    get world_bestiary_monster_path(world, goblin)
    expect(response.body).to include("The prompt, in layers", "16-bit pixel art", world.art_type("monster").prompt,
                                      "turbo-cable-stream-source")
    expect(response.body).to match(/<turbo-frame [^>]*id="art_panel"/)
  end

  it "serves the art section alone for its frame to reload, and tells watchers to reload it as images land" do
    get world_art_panel_path(world, entry_type: "monster", entry_slug: "goblin")
    expect(response.body).to match(/\A<turbo-frame [^>]*id="art_panel"/)
    expect(response.body).not_to include("<html")

    generate
    streams = capture_turbo_stream_broadcasts([ goblin, :art ]) { goblin.art_batch.update!(status: "running") }
    expect(streams.map { |s| [ s["action"], s["target"] ] }).to eq([ %w[reload_frame art_panel] ])
  end

  it "saves the entry's own layer, then queues a batch of candidates" do
    expect { generate }.to have_enqueued_job(ArtBatchJob)
    expect(response).to redirect_to(world_bestiary_monster_path(world, goblin, anchor: "art"))
    goblin.reload
    expect(goblin.art_notes).to eq("a rusty knife")
    expect(goblin.art_loras).to eq([ { "name" => "goblin.safetensors", "strength" => 0.6, "on" => true } ])
    batch = goblin.art_batch
    expect(batch.candidates.size).to eq(2)
    expect(batch.recipe["positive"]).to end_with("Goblin, a rusty knife")
    expect(batch.recipe["loras"]).to eq([ { "name" => "goblin.safetensors", "strength" => 0.6, "on" => true } ])
  end

  it "shows candidates as they land, and picking one makes it the image with its seed and recipe" do
    generate
    batch = goblin.art_batch
    finish(batch)
    get world_bestiary_monster_path(world, goblin)
    expect(response.body).to include("Candidates", "Use this", "Seed #{batch.candidates.first.seed}")

    winner = batch.candidates.last
    post world_art_candidate_pick_path(world, winner)
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
    post world_art_candidate_pick_path(world, goblin.art_batch.candidates.first)
    expect(flash[:alert]).to eq("That candidate has no image")
    expect(goblin.reload.image).not_to be_attached
  end

  it "forgets the seed and recipe when an image is uploaded by hand" do
    generate
    finish(goblin.art_batch)
    post world_art_candidate_pick_path(world, goblin.art_batch.candidates.first)
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
      world: { art_style: "ink wash", art_negative: "photo", art_model: "", art_loras: { "0" => { "name" => "ink", "strength" => "0.9", "on" => "1" } } },
      types: { monster: { prompt: "profile view, full body", width: "768", height: "768", transparent: "0",
                          model: "krea2_turbo_bf16.safetensors", loras: { "0" => { "name" => "sprites", "strength" => "" }, "1" => { "name" => "ink", "strength" => "0.9", "on" => "0" } } },
               nope: { prompt: "ignored" } }
    }
    expect(response).to redirect_to(world_art_direction_path(world))
    expect(world.reload).to have_attributes(art_style: "ink wash", art_loras: [ { "name" => "ink", "strength" => 0.9, "on" => true } ])
    expect(world.art_type("monster")).to have_attributes(
      prompt: "profile view, full body", width: 768, transparent: false, model: "krea2_turbo_bf16.safetensors",
      loras: [ { "name" => "sprites", "strength" => 1.0, "on" => true }, { "name" => "ink", "strength" => 0.9, "on" => false } ]
    )
    recipe = goblin.art_recipe
    expect(recipe["positive"]).to start_with("ink wash, profile view, full body, Goblin")
    expect(recipe).to include("model" => "krea2_turbo_bf16.safetensors", "family" => "krea2", "negative" => "")
    expect(recipe["loras"].map { |l| [ l["name"], l["on"] ] }).to eq([ [ "ink", false ], [ "sprites", true ] ])

    get world_art_direction_path(world)
    expect(response.body).to include("Krea 2 Turbo · 8 steps · CFG 1 · no negative prompt", "From the layers above")
  end

  it "picks models and LoRAs from what ComfyUI has, models grouped by family, keeping a name it no longer has" do
    allow(Comfy).to receive(:capabilities).and_return(FakeComfy.capabilities(
      checkpoints: [ "ponyDiffusionV6XL.safetensors", "sd_xl_base_1.0.safetensors" ],
      diffusion_models: [ "anima-preview.safetensors", "krea2_turbo_bf16.safetensors" ],
      loras: [ "ink.safetensors", "SDXL/pony_sprites.safetensors" ]
    ))
    world.update!(art_model: "retired.safetensors")
    get world_art_direction_path(world)
    page = Nokogiri::HTML(response.body)
    picker = page.at_css("select#world_art_model")
    groups = picker.css("optgroup").to_h { |g| [ g["label"], g.css("option").map(&:text) ] }
    expect(groups).to eq("Anima" => [ "anima-preview.safetensors" ], "Krea 2 Turbo" => [ "krea2_turbo_bf16.safetensors" ],
                         "Pony" => [ "ponyDiffusionV6XL.safetensors" ], "SDXL" => [ "sd_xl_base_1.0.safetensors" ],
                         "Not on ComfyUI" => [ "retired.safetensors" ])
    expect(picker.at_css("option[selected]")["value"]).to eq("retired.safetensors")
    expect(picker.at_css("option").text).to eq("Inherit: #{Comfy.config[:model]}")
    expect(page.at_css("select#types_monster_model option[selected]")).to be_nil # inherits

    loras = page.at_css("select#world_art_loras_0_name").css("optgroup").to_h { |g| [ g["label"], g.css("option").map(&:text) ] }
    expect(loras).to eq("LoRAs" => [ "ink.safetensors" ], "SDXL" => [ "SDXL/pony_sprites.safetensors" ])

    allow(Comfy).to receive(:capabilities).and_return(Comfy::Capabilities.unreachable)
    get world_art_direction_path(world)
    expect(Nokogiri::HTML(response.body).at_css("input#world_art_model")["value"]).to eq("retired.safetensors")
  end

  it "rejects a size ComfyUI can't use" do
    patch world_art_direction_path(world), params: { world: { art_style: "x" }, types: { monster: { width: "10" } } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Width must be in 256..2048")
  end
end

RSpec.describe "Generated portraits (§8)", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let(:cid) { campaign.npcs.create!(name: "Cid", title: "Engineer", description: "An old airship engineer") }
  let(:bartz) { campaign.characters.create!(name: "Bartz", job: world.jobs.find_by!(slug: "knight")) }
  let(:comfy) { FakeComfy.new }

  def generate(owner, expression, notes: "white beard, goggles")
    post world_art_batches_path(world), params: { entry_type: "portrait", owner_type: owner.model_name.singular, owner_id: owner.id,
                                                  expression: expression, count: 2, entry: { art_notes: notes } }
    ArtBatch.last
  end

  def finish(batch)
    ArtBatchJob.new.perform(batch.reload, client: comfy)
    comfy.finish!(*comfy.submitted.each_index.map { |i| "prompt-#{i + 1}" })
    ArtBatchJob.new.perform(batch.reload, client: comfy)
  end

  it "composes world, portrait framing, the speaker, then the expression" do
    batch = generate(cid, "happy")
    expect(response).to redirect_to(edit_npc_path(cid, anchor: "art"))
    expect(cid.reload.art_notes).to eq("white beard, goggles")
    expect(batch.recipe["positive"]).to end_with("Cid, Engineer, white beard, goggles, smiling happily")
    expect(batch.entry).to have_attributes(owner: cid, expression: "happy")

    bartz_batch = generate(bartz, "angry", notes: "")
    expect(bartz_batch.recipe["positive"]).to end_with("Bartz, a Knight, angry expression, furrowed brow")
  end

  it "never puts an NPC's private notes into a prompt" do
    cid.update!(description: "Secretly working for the Empire")
    batch = generate(cid, "neutral", notes: "")
    expect(batch.recipe["positive"]).not_to include("Empire")
    expect(batch.recipe["positive"]).to end_with("Cid, Engineer, calm neutral expression")
  end

  it "picks into the expression's portrait, which then speaks at the table" do
    batch = generate(cid, "neutral")
    finish(batch)
    get edit_npc_path(cid)
    expect(response.body).to include("Make their look", "Candidates for Neutral", "Use this")

    post world_art_candidate_pick_path(world, batch.candidates.first)
    expect(response).to redirect_to(edit_npc_path(cid, anchor: "art"))
    neutral = cid.portraits.find_by!(expression: "neutral")
    expect(neutral.image).to be_attached
    expect(neutral.image_seed).to eq(batch.candidates.first.seed)
    expect(cid.portrait_image("happy").blob).to eq(neutral.image.blob) # falls back to neutral, as before
  end

  it "starts other expressions from the neutral portrait's seed" do
    batch = generate(cid, "neutral")
    finish(batch)
    post world_art_candidate_pick_path(world, batch.candidates.last)
    seed = cid.portraits.find_by!(expression: "neutral").image_seed

    sad = generate(cid, "sad")
    expect(sad.candidates.first.seed).to eq(seed)
    expect(sad.candidates.second.seed).not_to eq(seed)
  end

  it "keeps one strip per expression, and only for speakers in this world" do
    first = generate(cid, "happy")
    generate(cid, "sad")
    expect(ArtBatch.exists?(first.id)).to be(true) # each expression its own strip, for the chain's last link
    expect(generate(cid, "happy")).not_to eq(first)
    expect(ArtBatch.exists?(first.id)).to be(false)

    other = World.create!(name: "Elsewhere", slug: "elsewhere")
    post world_art_batches_path(other), params: { entry_type: "portrait", owner_type: "npc", owner_id: cid.id, expression: "happy" }
    expect(response).to have_http_status(:not_found)
  end

  it "makes a full-body sprite the same way, same face, cut out, and the stage stands it in a beat" do
    neutral = generate(cid, "neutral")
    finish(neutral)
    post world_art_candidate_pick_path(world, neutral.candidates.first)
    seed = cid.portraits.find_by!(expression: "neutral").image_seed

    post world_art_batches_path(world), params: { entry_type: "sprite", owner_type: "npc", owner_id: cid.id, count: 2 }
    expect(response).to redirect_to(edit_npc_path(cid, anchor: "art"))
    sprite = cid.reload.sprite
    batch = sprite.art_batch
    expect(batch.recipe["positive"]).to include("full body", "Cid, Engineer, white beard, goggles")
    expect(batch.recipe["positive"]).not_to include("expression")
    expect(batch.recipe["transparent"]).to be(true)
    expect(batch.recipe["height"]).to be > batch.recipe["width"]
    expect(batch.candidates.first.seed).to eq(seed)
    expect(ArtBatch.exists?(neutral.id)).to be(false) # one strip a speaker

    get edit_npc_path(cid)
    expect(response.body).to include("1. The sprite: full body, for the stage", "Candidates for the sprite", "Full-body sprite, for the stage")

    finish(batch)
    post world_art_candidate_pick_path(world, batch.candidates.last)
    expect(sprite.reload.image).to be_attached
    expect(cid.sprite_image.blob).to eq(sprite.image.blob)

    # On the stage, the sprite stands where the portrait would; a character without one stands as their archetype.
    scene = campaign.scenes.create!(name: "The quay", script: "Cid: Ready?")
    scene.beats.create!(kind: "sprite", action: "enter", figures: [ { type: "Character", id: bartz.id, side: "left" } ], position: 0)
    scene.beats.first.update_columns(position: 1)
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    scene.start!
    get campaign_table_path(campaign)
    expect(response.body).to include("beat-stage__figure--sprite is-speaking", "beat-stage__sprite")
    expect(response.body).to include("beat-stage__figure--portrait") # Bartz: the Knight has no image in the base world
    expect(bartz.sprite_image).to be_nil
  end

  it "covers the Encounter and Generator tables too" do
    table = world.encounter_tables.first
    get world_encounters_encounter_table_path(world, table)
    expect(response.body).to include("The prompt, in layers", "Encounter tables")

    post world_art_batches_path(world), params: { entry_type: "encounter_table", entry_slug: table.slug, count: 1 }
    expect(table.reload.art_batch.recipe["positive"]).to include("a scene of what waits on the road", table.name)
  end
end

RSpec.describe "A player's look, in a chain (§8)", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road", gm: make_user("GM")) }
  let(:player) { make_user("Lenna's player") }
  let(:lenna) { campaign.characters.create!(name: "Lenna", job: world.jobs.find_by!(slug: "knight"), user: player) }
  let(:comfy) { FakeComfy.new }

  before { sign_in_as(player) }

  def finish(batch)
    ArtBatchJob.new.perform(batch.reload, client: comfy)
    comfy.finish!(*comfy.submitted.each_index.map { |i| "prompt-#{i + 1}" })
    ArtBatchJob.new.perform(batch.reload, client: comfy)
  end

  def speaker(owner) = { owner_type: owner.model_name.singular, owner_id: owner.id }

  it "is theirs to make: the sprite, the portrait from its head, then every expression from the portrait" do
    get edit_character_path(lenna)
    expect(response.body).to include("Make their look", "1. The sprite", "2. The Neutral portrait, from the sprite", "3. Every other expression")
    expect(response.body).not_to include("entry_art_model") # the model and LoRAs are the GM's

    # 1. The sprite, from the prompt; the player's specifics go in, a model they name doesn't.
    post world_art_batches_path(world), params: { entry_type: "sprite", **speaker(lenna), count: 1, entry: { art_notes: "pink hair, white tunic", art_model: "other.safetensors" } }
    expect(response).to redirect_to(edit_character_path(lenna, anchor: "art"))
    expect(lenna.reload).to have_attributes(art_notes: "pink hair, white tunic", art_model: nil)
    sprite_batch = lenna.sprite.art_batch
    expect(sprite_batch.recipe["positive"]).to include("full body", "Lenna, a Knight, pink hair, white tunic")
    finish(sprite_batch)
    post world_art_candidate_pick_path(world, sprite_batch.candidates.first)
    sprite = lenna.sprite.reload
    expect(sprite.image).to be_attached

    # 2. The Neutral portrait, redrawn from the sprite's head with the sprite's seed.
    post world_art_batches_path(world), params: { entry_type: "portrait", **speaker(lenna), expression: "neutral", from: "sprite", count: 2 }
    neutral = lenna.portraits.find_by!(expression: "neutral")
    batch = neutral.art_batch
    expect(batch.recipe).to include("source" => { "kind" => "sprite", "id" => sprite.id }, "denoise" => 0.55)
    expect(batch.recipe["positive"]).to include("head and shoulders portrait", "calm neutral expression")
    expect(batch.candidates.first.seed).to eq(sprite.image_seed)
    finish(batch)
    expect(comfy.uploads.map(&:first)).to eq([ "polychrome-head-#{sprite.id}-#{sprite.image_seed}.png" ])
    expect(comfy.uploads.first.last).to start_with("\x89PNG".b) # the head crop, a real image
    expect(batch.reload.recipe["workflow"]).to include("LoadImage", "VAEEncode")
    expect(comfy.submitted.last.values.find { |n| n["class_type"] == "KSampler" }["inputs"]["denoise"]).to eq(0.55)
    get edit_character_path(lenna)
    expect(response.body).to include("Candidates for Neutral, from the sprite")
    post world_art_candidate_pick_path(world, batch.candidates.last)
    expect(neutral.reload.image).to be_attached

    # 3. Every other expression at once, each from the Neutral portrait, each its own strip.
    post world_art_batches_path(world), params: { entry_type: "portrait", **speaker(lenna), expression: "happy", from: "neutral", every: "1", count: 1 }
    expect(response).to redirect_to(edit_character_path(lenna, anchor: "art"))
    strips = ArtBatch.where(entry: lenna.portraits.reload).to_a
    expect(strips.map { |b| b.entry.expression }).to match_array(Portrait::EXPRESSIONS - [ "neutral" ])
    expect(strips.map { |b| b.recipe["source"] }.uniq).to eq([ { "kind" => "portrait", "id" => neutral.id } ])
    expect(strips.map { |b| b.recipe["denoise"] }.uniq).to eq([ 0.45 ])
    expect(strips.map { |b| b.candidates.first.seed }.uniq).to eq([ neutral.image_seed ])
    expect(strips.find { |b| b.entry.expression == "angry" }.recipe["positive"]).to end_with("angry expression, furrowed brow")
    get edit_character_path(lenna)
    expect(response.body).to include("Candidates for Happy, from the Neutral portrait", "Candidates for Angry, from the Neutral portrait")
  end

  it "needs the link before: no sprite, no portrait from it" do
    post world_art_batches_path(world), params: { entry_type: "portrait", **speaker(lenna), expression: "neutral", from: "sprite" }
    expect(response).to redirect_to(root_path) # back where they came from; the message says why
    expect(flash[:alert]).to eq("There's no sprite to draw the portrait from yet")
    expect(ArtBatch.count).to eq(0)
  end

  it "is only theirs: not another player's character, nor the cast" do
    other = campaign.characters.create!(name: "Faris", job: world.jobs.find_by!(slug: "knight"), user: make_user("Other"))
    post world_art_batches_path(world), params: { entry_type: "sprite", **speaker(other), count: 1 }
    expect(ArtBatch.count).to eq(0)
    cid = campaign.npcs.create!(name: "Cid", title: "Engineer")
    post world_art_batches_path(world), params: { entry_type: "portrait", **speaker(cid), expression: "neutral" }
    expect(ArtBatch.count).to eq(0)
    get world_art_panel_path(world, entry_type: "portrait", **speaker(cid))
    expect(response).to have_http_status(:forbidden)
    get edit_character_path(other)
    expect(response).to redirect_to(root_path)
  end
end
