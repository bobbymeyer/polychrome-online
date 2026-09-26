# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe QuickParty do
  let(:world) { Seeds::BaseWorld.run }

  it "builds engine unit specs from jobs, with derived stats and the job's best gear" do
    knight, mage = described_class.new(world).build([ { name: "Bartz", job: "knight" }, { name: "", job: "black_mage" } ])
    expect(knight).to include("id" => "bartz_1", "name" => "Bartz", "abilities" => %w[war_cry armor_break double_cut])
    # Knight: base str 12 x 120% = 14, plus the Power Ring's +5; atk from the Broadsword
    expect(knight["stats"]).to include("str" => 19, "atk" => 14)
    expect(mage).to include("id" => "black_mage_2", "name" => "Black Mage")
    expect(mage["stats"]["max_mp"]).to eq(45)
  end

  it "rejects unknown jobs" do
    expect { described_class.new(world).build([ { name: "X", job: "dancer" } ]) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
