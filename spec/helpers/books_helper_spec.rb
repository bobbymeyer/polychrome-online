# frozen_string_literal: true

require "rails_helper"

RSpec.describe BooksHelper do
  it "describes every primitive in words, never as raw data" do
    Battle::PRIMITIVES.each do |primitive|
      text = helper.describe_effect("primitive" => primitive, "power" => 10, "element" => "fire", "kind" => "poison",
                                    "stat" => "str", "amount" => 10)
      expect(text).not_to include("{", "=>"), primitive
    end
    expect(helper.describe_effect("primitive" => "steal", "chance" => 50)).to eq("Steal one of its drops (50% + speed)")
  end

  it "draws a character as their own portrait, else as their job (a lettered plate without art)" do
    bartz = create_character(create_campaign)
    expect(helper.character_portrait(bartz, size: :small)).to include("portrait--empty", ">K<") # the Knight's plate
    bartz.update_portraits!(uploads: { "neutral" => Rack::Test::UploadedFile.new(file_fixture("goblin.png"), "image/png") })
    html = helper.character_portrait(bartz.reload, size: :small)
    expect(html).to include("portrait--small", "<img", 'alt="Bartz"')
    expect(html).not_to include("portrait--empty")
  end
end
