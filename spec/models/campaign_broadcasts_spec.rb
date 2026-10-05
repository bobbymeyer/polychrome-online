# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

RSpec.describe Campaign::Broadcasts do
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper
  let(:campaign) { create_campaign }

  def refresh_pages
    have_enqueued_job(Turbo::Streams::BroadcastStreamJob).with(stream(campaign, :pages), content: a_string_including("refresh")).at_least(:once)
  end

  it "refreshes the players' table when a secret comes out, and the log carries what it was" do
    secret = campaign.secrets.create!(body: "The king is a fake.")
    expect { refreshing_the_table { secret.reveal! } }
      .to have_broadcasted_to(stream(campaign, :players)).with(a_string_including("party_knows"))
    expect(campaign.messages.last.body).to eq("The party learns: The king is a fake.")
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

  it "renders the table's panels once for a burst of changes, from the models' own commits" do
    node = campaign.map_nodes.create!(name: "Tule", kind: "town", x: 1, y: 1, visible: true)
    clear_enqueued_jobs
    expect { campaign.update!(current_node: node) }.to have_enqueued_job(TableRefreshJob).with(campaign)
    expect { campaign.update!(name: "Renamed") }.not_to have_enqueued_job(TableRefreshJob)
    streams = capture_turbo_stream_broadcasts([ campaign, :players ]) { campaign.broadcast_table }
    expect(streams.map { |s| s["target"] }).to match_array(Campaign::TABLE_PANELS.keys)
  end

  it "still refreshes the table when the campaign is saved again in the same transaction, after the change that matters" do
    campaign.set_out!(from_the_setting: true)
    campaign.update!(time_of_day: "night")
    clear_enqueued_jobs
    # A new day rolls the world on (Campaign#overnight!), saving the RNG state after the time: the time still reaches the table.
    expect { campaign.pass_time!(1) }.to have_enqueued_job(TableRefreshJob).with(campaign)
    expect(campaign.reload.day).to eq(2)

    clear_enqueued_jobs
    expect { campaign.transaction { campaign.update!(gil: campaign.gil + 10); campaign.update!(name: "Renamed") } }
      .to have_enqueued_job(TableRefreshJob).with(campaign)
    clear_enqueued_jobs
    expect { campaign.transaction { campaign.update!(name: "Renamed again"); raise ActiveRecord::Rollback } }.not_to have_enqueued_job(TableRefreshJob)
    expect { campaign.update!(name: "And again") }.not_to have_enqueued_job(TableRefreshJob)
  end
end
