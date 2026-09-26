# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe ArtBatchJob, type: :job do
  include ActiveJob::TestHelper

  let!(:world) { Seeds::BaseWorld.run }
  let(:goblin) { world.monsters.find_by!(slug: "goblin") }
  let(:comfy) { FakeComfy.new }

  def run(batch) = described_class.new.perform(batch.reload, client: comfy)

  it "submits one prompt per candidate, each with its own seed, then collects the images as they land" do
    batch = ArtBatch.start!(goblin, count: 3)
    seeds = batch.candidates.map(&:seed)
    expect(seeds.uniq.size).to eq(3)

    run(batch)
    expect(comfy.submitted.map { |g| g.values.find { |n| n["class_type"] == "KSampler" }["inputs"]["seed"] }).to eq(seeds)
    expect(comfy.submitted.first.values.find { |n| n["class_type"] == "CLIPTextEncode" }["inputs"]["text"]).to eq(goblin.art_recipe["positive"])
    expect(batch.reload.status).to eq("running")
    expect(enqueued_jobs.count { |j| j["job_class"] == "ArtBatchJob" }).to be >= 2 # the start, then a check-back

    comfy.finish!("prompt-1")
    run(batch)
    expect(batch.candidates.map { |c| [ c.status, c.image.attached? ] }).to eq([ [ "done", true ], [ "running", false ], [ "running", false ] ])

    comfy.finish!("prompt-2", "prompt-3")
    run(batch)
    expect(batch.reload.status).to eq("done")
    expect(comfy.submitted.size).to eq(3) # nothing resubmitted
  end

  it "keeps the good candidates when one fails, and fails the batch when all do" do
    batch = ArtBatch.start!(goblin, count: 2)
    run(batch)
    comfy.finish!("prompt-1")
    comfy.fail!("prompt-2", "KSampler: out of memory")
    run(batch)
    expect(batch.reload.status).to eq("done")
    expect(batch.candidates.last).to have_attributes(status: "failed", error: "KSampler: out of memory")

    other = ArtBatch.start!(goblin, count: 1)
    run(other)
    comfy.fail!("prompt-3", "LoraLoader: missing file")
    run(other)
    expect(other.reload).to have_attributes(status: "failed", error: "LoraLoader: missing file")
  end

  it "fails the batch with ComfyUI's reason when it can't submit" do
    batch = ArtBatch.start!(goblin, count: 2)
    allow(comfy).to receive(:submit).and_raise(Comfy::Error, "ComfyUI isn't reachable at http://comfy.test")
    run(batch)
    expect(batch.reload).to have_attributes(status: "failed", error: "ComfyUI isn't reachable at http://comfy.test")
    expect(batch.candidates.map(&:status).uniq).to eq([ "failed" ])
  end

  it "gives up after the timeout" do
    batch = ArtBatch.start!(goblin, count: 1)
    run(batch)
    travel(Comfy.config[:timeout].to_i.seconds + 1) { run(batch) }
    expect(batch.reload.status).to eq("failed")
    expect(batch.error).to match(/didn't finish/)
  end

  it "does nothing for a batch that was discarded" do
    batch = ArtBatch.start!(goblin, count: 1) # enqueues the job
    batch.destroy!
    expect { perform_enqueued_jobs(only: described_class) }.not_to raise_error
  end
end
