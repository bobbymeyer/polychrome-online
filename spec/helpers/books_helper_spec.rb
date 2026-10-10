# frozen_string_literal: true

require "rails_helper"

RSpec.describe BooksHelper do
  it "describes every primitive in words, never as raw data" do
    Battle::PRIMITIVES.each do |primitive|
      text = helper.describe_effect("primitive" => primitive, "power" => 10, "element" => "fire", "kind" => "poison",
                                    "stat" => "str", "amount" => 10)
      expect(text).not_to include("{", "=>"), primitive
    end
    expect(helper.describe_effect("primitive" => "steal", "chance" => 50)).to eq("Steal one of its drops, or from the party's bag when a monster steals (50% + speed)")
    expect(helper.describe_effect("primitive" => "grab", "duration" => 3, "breaks" => "hit", "tear" => 10))
      .to eq("Hold fast for 3 turns; any blow on the user breaks it, and tears 10% HP")
    expect(helper.describe_effect("primitive" => "physical", "power" => 120, "stumble" => 1)).to end_with("a miss leaves the user down for 1 turn")
    expect(helper.describe_effect("primitive" => "away", "who" => "self", "duration" => 2, "aloft" => 1)).to start_with("Up out of reach of blows (not of spells)")
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
