# frozen_string_literal: true

require "rails_helper"
require "vips"

# Flat art on white: a black ring with a white inside, drawn on a white
# ground. A removal model takes all the white, the inside with the ground.
RSpec.describe Comfy::BackgroundRemoval do
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

  it "keeps the rendered image alongside when removing, and tells the two apart" do
    images = [ { "filename" => "polychrome/goblin-1-plain_00001_.png" }, { "filename" => "polychrome/goblin-1_00001_.png" } ]
    expect(described_class.split(images)).to eq([ images.last, images.first ])
    expect(described_class.split([ images.last ])).to eq([ images.last, nil ])
  end
end
