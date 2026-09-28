# frozen_string_literal: true

require "rails_helper"

RSpec.describe Campaign::Broadcasts do
  let(:campaign) { create_campaign }

  def refresh_pages
    have_enqueued_job(Turbo::Streams::BroadcastStreamJob).with(stream(campaign, :pages), content: a_string_including("refresh")).at_least(:once)
  end

  it "tells the players' table what the party knows when a flag goes public" do
    flag = campaign.flags.create!(key: "met_the_king", value: "yes")
    expect { flag.update!(public: true) }
      .to have_broadcasted_to(stream(campaign, :players)).with(a_string_including("party_knows", "Met the king"))
  end

  it "refreshes the campaign's documents when something on them changes" do
    clock = campaign.clocks.create!(name: "The docks fall", segments: 4)
    expect { clock.tick! }.to refresh_pages
    expect { campaign.flags.create!(key: "crystals", value: "2") }.to refresh_pages
    expect { campaign.update!(gil: 500) }.to refresh_pages
  end

  it "refreshes them when a battle starts or ends, and not for every move in it" do
    battle = nil
    expect { battle = start_battle(campaign: campaign) }.to refresh_pages
    goblin = battle.state["units"].find { |u| u["side"] == "enemy" }
    expect { battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => goblin["id"], "value" => 1 }, actor: "gm") }
      .not_to have_enqueued_job(Turbo::Streams::BroadcastStreamJob).with(stream(campaign, :pages), anything)
    expect { battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm") }.to refresh_pages
  end
end
