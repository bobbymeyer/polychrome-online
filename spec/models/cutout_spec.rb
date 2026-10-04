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

  # On a ground of its own colour: a figure with a white belly whose white
  # runs out to the edge of the picture (a white cape against the ground),
  # and a green gap closed in by the figure (an arm on a hip).
  def on_green
    rows = Array.new(SIZE) do |y|
      Array.new(SIZE) do |x|
        if (10..30).cover?(x) && (10..30).cover?(y) then (x.between?(14, 18) && y.between?(14, 18)) ? [ 40, 200, 40 ] : [ 255, 255, 255 ] # white figure, green gap inside
        elsif x > 30 && y.between?(18, 22) then [ 255, 255, 255 ] # a white strip from the figure to the right edge
        else [ 40, 200, 40 ]
        end
      end
    end
    bands = (0..2).map { |band| Vips::Image.new_from_array(rows.map { |row| row.map { |pixel| pixel[band] } }).cast(:uchar) }
    bands[0].bandjoin(bands[1..]).copy(interpretation: :srgb)
  end

  it "on a coloured ground, puts back whatever the model cleared that isn't the ground, even white reaching the edge, and leaves a ground-coloured gap clear" do
    plain = on_green
    # A model that took the ground and, keyed on light, every white pixel with it, and kept the green gap inside as "subject".
    alpha = Vips::Image.new_from_array(Array.new(SIZE) { |y| Array.new(SIZE) { |x| x.between?(14, 18) && y.between?(14, 18) ? 255 : 0 } }).cast(:uchar)
    mended = described_class.keep_interior(plain.bandjoin(alpha).pngsave_buffer, plain.pngsave_buffer)
    expect(alpha_at(mended, 20, 25)).to eq(255) # the white figure
    expect(alpha_at(mended, 36, 20)).to eq(255) # the white strip out to the edge
    expect(alpha_at(mended, 16, 16)).to eq(255) # the green gap: the model kept it, so it stays (a gap is the model's call)
    expect(alpha_at(mended, 2, 2)).to eq(0)     # the ground
    expect(alpha_at(mended, 36, 30)).to eq(0)

    # A model that cleared the gap too: ground-coloured, so it stays clear, closed in or not.
    alpha = Vips::Image.new_from_array(Array.new(SIZE) { |y| Array.new(SIZE) { |x| plain.getpoint(x, y) == [ 255, 255, 255 ] || (x.between?(14, 18) && y.between?(14, 18)) ? 0 : 255 } }).cast(:uchar)
    mended = described_class.keep_interior(plain.bandjoin(alpha).pngsave_buffer, plain.pngsave_buffer)
    expect(alpha_at(mended, 16, 16)).to eq(0)
    expect(alpha_at(mended, 20, 25)).to eq(255)
  end

  it "renders a cut-out picture on the ground instead of white, and asks against white" do
    recipe = { "parts" => { "prefix" => "masterpiece", "style" => "ink", "framing" => "a single monster, full body, plain white background", "subject" => "Goblin", "detail" => "" },
               "positive" => "x", "negative" => "worst quality" }
    on = described_class.on_ground(recipe)
    expect(on["parts"]["framing"]).to eq("a single monster, full body, plain flat green background, no shadow")
    expect(on["positive"]).to eq("masterpiece, ink, a single monster, full body, plain flat green background, no shadow, Goblin")
    expect(on["negative"]).to eq("worst quality, white background")
    expect(on["ground"]).to eq("green")

    added = described_class.on_ground(recipe.merge("parts" => recipe["parts"].merge("framing" => "a head and shoulders portrait"), "negative" => ""))
    expect(added["parts"]["framing"]).to eq("a head and shoulders portrait, plain flat green background, no shadow")
    expect(added["negative"]).to eq("")

    allow(described_class).to receive(:config).and_return(Rails.configuration.x.cutout.merge(ground: ""))
    expect(described_class.on_ground(recipe)).to equal(recipe)
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

    it "cuts out each picture ComfyUI renders, rendered on the ground, and names the model on the recipe" do
      cutout = FakeCutout.new
      batch = render(cutout)
      expect(cutout.sent).to eq([ FakeComfy.png ])
      expect(batch.recipe["cutout"]).to eq("isnet-anime")
      expect(batch.recipe["positive"]).to include("plain flat green background, no shadow")
      expect(batch.recipe["positive"]).not_to include("white background")
      expect(batch.recipe["negative"]).to end_with("white background")
      expect(batch.candidates.sole).to have_attributes(status: "done", transparent: true, error: nil)

      kept = ArtBatch.start!(goblin, count: 1, transparent: false)
      expect(kept.recipe["positive"]).to include("plain white background")
      expect(kept.recipe).not_to have_key("ground")
    end

    it "keeps the picture, background and all, when the remover turns it down" do
      batch = render(FakeCutout.new(raises: Cutout::Error.new("The background remover answered 500: out of memory")))
      expect(batch.status).to eq("done")
      expect(batch.candidates.sole).to have_attributes(status: "done", error: /out of memory/)
      expect(batch.candidates.sole.image).to be_attached
    end

    it "waits when the remover can't be reached, and carries on once it's back" do
      allow(Comfy).to receive(:client).and_return(comfy)
      allow(Cutout).to receive(:client).and_return(FakeCutout.new(raises: Cutout::Unreachable.new("The background remover isn't reachable at http://cutout.test")))
      batch = ArtBatch.start!(goblin, count: 1, transparent: true)
      ArtBatchJob.perform_now(batch)
      comfy.finish!("prompt-1")
      ArtBatchJob.perform_now(batch.reload)
      expect(batch.reload).to have_attributes(status: "waiting", error: /background remover isn't reachable/)
      ArtBatchJob.new.perform(batch.reload, client: comfy, cutout: FakeCutout.new)
      expect(batch.reload.status).to eq("done")
      expect(batch.candidates.sole.transparent).to be(true)
    end
  end
end
