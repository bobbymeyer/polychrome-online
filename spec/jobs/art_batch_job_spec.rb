# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArtBatchJob, type: :job do
  include ActiveJob::TestHelper

  let!(:world) { base_world }
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
    expect(batch.candidates.map(&:transparent)).to all(be(true)) # the goblin's type removes its background, and the images have alpha
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

  it "fails the batch with ComfyUI's reason when ComfyUI refuses it" do
    batch = ArtBatch.start!(goblin, count: 2)
    allow(comfy).to receive(:submit).and_raise(Comfy::Error, "CheckpointLoaderSimple: model not found")
    run(batch)
    expect(batch.reload).to have_attributes(status: "failed", error: "CheckpointLoaderSimple: model not found")
    expect(batch.candidates.map(&:status).uniq).to eq([ "failed" ])
  end

  describe "when ComfyUI can't be reached" do
    let(:down) { "ComfyUI isn't reachable at http://comfy.test (OpenTimeout: execution expired)" }

    def retries = enqueued_jobs.select { |j| j["job_class"] == "ArtBatchJob" && j["arguments"].last.is_a?(Hash) && j["arguments"].last.key?("unreachable_since") }

    it "waits and tries again later, less often the longer it's down, then carries on when it's back" do
      batch = ArtBatch.start!(goblin, count: 2)
      clear_enqueued_jobs
      allow(comfy).to receive(:submit).and_raise(Comfy::Unreachable, down)
      run(batch)
      expect(batch.reload).to have_attributes(status: "waiting", error: down)
      expect(batch.candidates.map(&:status).uniq).to eq([ "queued" ]) # nothing lost
      expect(retries.size).to eq(1)
      expect(retries.first["scheduled_at"].to_time).to be_within(2.seconds).of(30.seconds.from_now)

      expect(described_class.retry_in(20.minutes)).to eq(10.minutes)
      expect(described_class.retry_in(4.minutes)).to eq(2.minutes)

      allow(comfy).to receive(:submit).and_call_original
      described_class.new.perform(batch.reload, client: comfy, unreachable_since: 5.minutes.ago)
      expect(batch.reload).to have_attributes(status: "running", error: nil)
      expect(comfy.submitted.size).to eq(2)
      comfy.finish!("prompt-1", "prompt-2")
      run(batch)
      expect(batch.reload.status).to eq("done")
    end

    it "keeps what's rendering when ComfyUI drops out mid-batch" do
      batch = ArtBatch.start!(goblin, count: 2)
      run(batch)
      allow(comfy).to receive(:result).and_raise(Comfy::Unreachable, down)
      run(batch)
      expect(batch.reload.status).to eq("waiting")
      expect(batch.candidates.map(&:status).uniq).to eq([ "running" ])

      allow(comfy).to receive(:result).and_call_original
      comfy.finish!("prompt-1", "prompt-2")
      run(batch)
      expect(batch.reload.status).to eq("done")
      expect(comfy.submitted.size).to eq(2) # nothing resubmitted
    end

    it "gives up after a day" do
      batch = ArtBatch.start!(goblin, count: 1)
      allow(comfy).to receive(:submit).and_raise(Comfy::Unreachable, down)
      described_class.new.perform(batch, client: comfy, unreachable_since: 25.hours.ago)
      expect(batch.reload.status).to eq("failed")
      expect(batch.error).to include("Tried for a day")
    end
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
