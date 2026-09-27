# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper do
  it "gives a name the same palette colour every time, with ink that reads on it" do
    expect(helper.plate_style("goblin")).to eq(helper.plate_style("Goblin"))
    hex = helper.plate_style("goblin")[/--plate: (#\h{6})/, 1]
    expect(Palette::COLOURS.values.map(&:first)).to include(hex)
    expect(helper.plate_style("goblin", "pink")).to eq("--plate: #F6BCD0; --plate-ink: #111;")
    expect(%w[goblin wolf ogre knight white_mage black_mage].map { |n| helper.plate_style(n) }.uniq.size).to be > 1
  end

  it "colours a page by its book" do
    allow(helper).to receive(:controller_path).and_return("bestiary/monsters")
    expect(helper.accent_style).to eq("--accent: #13955F; --accent-ink: #fff;")
    allow(helper).to receive(:controller_path).and_return("campaigns")
    expect(helper.accent_style).to include("#4153A1")
    expect(helper.accent_style("armory")).to eq("--accent: #F4971B; --accent-ink: #111;") # a light colour takes ink
  end
end
