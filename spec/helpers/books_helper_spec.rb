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
end
