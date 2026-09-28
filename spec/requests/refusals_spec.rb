# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Refusals", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Rust", gm: @admin) }

  before { post campaign_table_seat_path(campaign), params: { seat: "gm" } }

  it "tells whoever asked why the game said no, back where they were" do
    post campaign_checks_path(campaign), params: { check: { stat: "str", difficulty: "hard", characters: [ "" ] } },
                                         headers: { "HTTP_REFERER" => campaign_table_url(campaign) }
    expect(response).to redirect_to(campaign_table_url(campaign))
    expect(flash[:alert]).to eq("Pick who's trying")
  end

  it "lets a programmer's mistake crash instead of reading it as a refusal" do
    allow_any_instance_of(Campaign).to receive(:check!).and_raise(ArgumentError, "wrong number of arguments")
    expect do
      post campaign_checks_path(campaign), params: { check: { stat: "str", difficulty: "hard", characters: [ "" ] } }
    end.to raise_error(ArgumentError)
  end
end
