# frozen_string_literal: true

require "rails_helper"

RSpec.describe MapsHelper, type: :helper do
  it "runs a name inward on a phone when centred it would leave the map" do
    node = ->(name, x) { MapNode.new(name: name, x: x, y: 100) }
    expect(helper.map_label_side(node.("Kōgen High School", 120))).to eq("is-left")
    expect(helper.map_label_side(node.("Kōgen High School", MapNode::WIDTH - 120))).to eq("is-right")
    expect(helper.map_label_side(node.("Kōgen High School", MapNode::WIDTH / 2))).to be_nil
    expect(helper.map_label_side(node.("Varn", 60))).to be_nil
  end
end
