# frozen_string_literal: true

require "rails_helper"
require "vips"

# Flat art on white: a black ring with a white inside, drawn on a white
# ground. A removal model takes all the white, the inside with the ground.
RSpec.describe Cutout do
  SIZE = 40

  # 0 = white ground, 1 = black ring, 2 = white inside the ring.
  def region(x, y)
    distance = Math.hypot(x - 20, y - 20)
    if distance < 8 then 2
    elsif distance < 14 then 1
    else 0
    end
  end

  def picture
    rows = Array.new(SIZE) { |y| Array.new(SIZE) { |x| region(x, y) == 1 ? 0 : 255 } }
    grey = Vips::Image.new_from_array(rows).cast(:uchar)
    grey.bandjoin([ grey, grey ]).copy(interpretation: :srgb)
  end

  # What a removal model does to it: every white pixel cleared.
  def removed(plain = picture)
    alpha = Vips::Image.new_from_array(Array.new(SIZE) { |y| Array.new(SIZE) { |x| region(x, y) == 1 ? 255 : 0 } }).cast(:uchar)
    plain.bandjoin(alpha).pngsave_buffer
  end

  def alpha_at(png, x, y) = Vips::Image.new_from_buffer(png, "").getpoint(x, y).last

  it "puts back what was taken from inside the subject, and leaves the ground clear" do
    mended = described_class.keep_interior(removed, picture.pngsave_buffer)
    expect(alpha_at(mended, 20, 20)).to eq(255) # the white inside
    expect(alpha_at(mended, 20, 8)).to eq(255)  # the ring
    expect(alpha_at(mended, 2, 2)).to eq(0)     # the ground
    expect(alpha_at(mended, 38, 20)).to eq(0)
    expect(Vips::Image.new_from_buffer(mended, "").getpoint(20, 20).first(3)).to eq([ 255, 255, 255 ])
  end

  it "leaves an image alone when nothing inside was taken" do
    alpha = Vips::Image.new_from_array(Array.new(SIZE) { |y| Array.new(SIZE) { |x| region(x, y) == 0 ? 0 : 255 } }).cast(:uchar)
    clean = picture.bandjoin(alpha).pngsave_buffer
    expect(described_class.keep_interior(clean)).to eq(clean)
  end

  describe Cutout::Client do
    def client(routes) = described_class.new(url: "http://cutout.test", path: "/api/remove", model: "isnet-anime", token: "tok", http: FakeHttp.new(routes))

    it "sends the picture and the model as a form, and gives back the PNG" do
      http = FakeHttp.new("/api/remove" => [ 200, FakeComfy.png ])
      cut = described_class.new(url: "http://cutout.test", path: "/api/remove", model: "isnet-anime", token: "tok", http: http).remove("pixels")
      expect(cut).to eq(FakeComfy.png)
      request = http.requests.sole
      expect(request["Content-Type"]).to start_with("multipart/form-data")
      expect(request["Authorization"]).to eq("Bearer tok")
    end

    it "says whether it couldn't be reached (try later) or turned the picture down" do
      expect { client({}).remove("pixels") }.to raise_error(Cutout::Unreachable, /isn't reachable at http:\/\/cutout.test/)
      expect { client("/api/remove" => [ 500, "model not found" ]).remove("pixels") }.to raise_error(Cutout::Error, /answered 500: model not found/)
      expect { client("/api/remove" => [ 200, "{}" ]).remove("pixels") }.to raise_error(Cutout::Error, /isn't a PNG/)
    end
  end

  describe "in a batch (ArtBatchJob)" do
    include ActiveJob::TestHelper

    let(:goblin) { base_world.monsters.find_by!(slug: "goblin") }
    let(:comfy) { FakeComfy.new }

    def render(cutout)
      batch = ArtBatch.start!(goblin, count: 1, transparent: true)
      ArtBatchJob.new.perform(batch, client: comfy, cutout: cutout)
      comfy.finish!("prompt-1")
      ArtBatchJob.new.perform(batch.reload, client: comfy, cutout: cutout)
      batch.reload
    end

    it "cuts out each picture ComfyUI renders, and names the model on the recipe" do
      cutout = FakeCutout.new
      batch = render(cutout)
      expect(cutout.sent).to eq([ FakeComfy.png ])
      expect(batch.recipe["cutout"]).to eq("birefnet-general")
      expect(batch.candidates.sole).to have_attributes(status: "done", transparent: true, error: nil)
    end

    it "keeps the picture, background and all, when the remover turns it down" do
      batch = render(FakeCutout.new(raises: Cutout::Error.new("The background remover answered 500: out of memory")))
      expect(batch.status).to eq("done")
      expect(batch.candidates.sole).to have_attributes(status: "done", error: /out of memory/)
      expect(batch.candidates.sole.image).to be_attached
    end

    it "waits when the remover can't be reached, and carries on once it's back" do
      batch = render(FakeCutout.new(raises: Cutout::Unreachable.new("The background remover isn't reachable at http://cutout.test")))
      expect(batch).to have_attributes(status: "waiting", error: /background remover isn't reachable/)
      ArtBatchJob.new.perform(batch.reload, client: comfy, cutout: FakeCutout.new)
      expect(batch.reload.status).to eq("done")
      expect(batch.candidates.sole.transparent).to be(true)
    end
  end
end
