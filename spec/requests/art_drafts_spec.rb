# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Drafts first, then made properly (§8)", type: :request do
  include ActiveJob::TestHelper

  let!(:world) { base_world }
  let(:goblin) { world.monsters.find_by!(slug: "goblin") }
  let(:comfy) { FakeComfy.new }
  let(:cutout) { FakeCutout.new }

  def run(batch) = ArtBatchJob.new.perform(batch.reload, client: comfy, cutout: cutout)
  def node(graph, type) = graph.values.find { |n| n["class_type"] == type }

  it "drafts small and quick, then makes the chosen one properly from the draft" do
    post world_art_batches_path(world), params: { entry_type: "monster", entry_slug: "goblin", count: 2, draft: "1", transparent: "1" }
    drafts = goblin.art_batch
    expect(drafts).to be_draft
    expect(drafts.recipe).to include("steps" => 16, "width" => 512, "height" => 512, "transparent" => true)
    expect(drafts.recipe["full"]).to include("width" => 1024, "height" => 1024, "transparent" => true)

    run(drafts)
    graph = comfy.submitted.first
    expect(node(graph, "KSampler")["inputs"]).to include("steps" => 16, "denoise" => 1)
    expect(node(graph, "EmptyLatentImage")["inputs"]).to include("width" => 512, "height" => 512)
    comfy.finish!("prompt-1", "prompt-2")
    run(drafts)
    expect(cutout.sent.size).to eq(2) # a draft is cut out too: it can be used as it is
    expect(drafts.candidates.map(&:transparent)).to all(be(true))
    chosen = drafts.candidates.reload.second
    expect(chosen.run_seconds).to eq(42.5)

    get world_bestiary_monster_path(world, goblin)
    expect(response.body).to include("Drafts", "Make this one properly", "Use the draft", "43s")

    post world_art_candidate_refinements_path(world, chosen)
    refinement = goblin.reload.art_batch
    expect(refinement.recipe).to include("width" => 1024, "height" => 1024, "transparent" => true, "denoise" => 0.6)
    expect(refinement.candidates.sole.seed).to eq(chosen.seed)
    expect(refinement.drafts).to eq(drafts)

    run(refinement)
    expect(comfy.uploads.sole.first).to eq("polychrome-draft-#{chosen.id}-#{chosen.seed}.png")
    expect(Cutout.png_alpha?(comfy.uploads.sole.last)).to be(false) # redrawn from the render on its ground, not the cut-out
    graph = comfy.submitted.last
    expect(node(graph, "LoadImage")["inputs"]).to eq("image" => "polychrome-draft-#{chosen.id}-#{chosen.seed}.png")
    expect(node(graph, "ImageScale")["inputs"]).to include("width" => 1024, "height" => 1024)
    expect(node(graph, "KSampler")["inputs"]).to include("steps" => 30, "denoise" => 0.6, "seed" => chosen.seed)
    expect(node(graph, "EmptyLatentImage")).to be_nil

    get world_bestiary_monster_path(world, goblin)
    expect(response.body).to include("Made properly", "Drafts")

    comfy.finish!("prompt-3")
    run(refinement)
    expect(cutout.sent.size).to eq(3)
    expect(refinement.candidates.sole.transparent).to be(true)
    post world_art_candidate_pick_path(world, refinement.candidates.sole)
    expect(goblin.reload.image).to be_attached
    expect(goblin.art_batches).to be_empty # drafts and all
  end

  it "only makes a finished draft properly" do
    post world_art_batches_path(world), params: { entry_type: "monster", entry_slug: "goblin", count: 1, draft: "0" }
    batch = goblin.art_batch
    run(batch)
    comfy.finish!("prompt-1")
    run(batch)
    post world_art_candidate_refinements_path(world, batch.candidates.sole)
    expect(flash[:alert]).to eq("Only a draft can be made properly")
  end
end
