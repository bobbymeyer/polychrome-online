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

  def refresh_the_table
    have_broadcasted_to(stream(campaign, :table_refresh)).with(a_string_including('action="refresh"'))
  end

  def enqueue_a_table_refresh
    have_enqueued_job(Turbo::Streams::BroadcastStreamJob).with(stream(campaign, :table_refresh), content: a_string_including("refresh"))
  end

  it "refreshes the players' table when a secret comes out, and the log carries what it was" do
    secret = campaign.secrets.create!(body: "The king is a fake.")
    expect { refreshing_the_table { secret.reveal! } }.to refresh_the_table
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

  it "refreshes the table once for a burst of changes, from the models' own commits" do
    node = campaign.map_nodes.create!(name: "Tule", kind: "town", x: 1, y: 1, visible: true)
    clear_enqueued_jobs
    expect { campaign.update!(current_node: node) }.to enqueue_a_table_refresh
    expect { campaign.update!(name: "Renamed") }.not_to enqueue_a_table_refresh
    # One refresh, with nothing in it: each table fetches its own page, as its own seat.
    streams = capture_turbo_stream_broadcasts([ campaign, :table_refresh ]) { perform_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob) }
    expect(streams.map { |s| s["action"] }).to eq([ "refresh" ])
    expect(streams.first.inner_html.strip).to be_empty
  end

  it "still refreshes the table when the campaign is saved again in the same transaction, after the change that matters" do
    campaign.set_out!(from_the_setting: true)
    campaign.update!(time_of_day: "night")
    clear_enqueued_jobs
    # A new day rolls the world on (Campaign::Night), saving the RNG state after the time: the time still reaches the table.
    expect { campaign.pass_time!(1) }.to enqueue_a_table_refresh
    expect(campaign.reload.day).to eq(2)

    clear_enqueued_jobs
    expect { campaign.transaction { campaign.update!(gil: campaign.gil + 10); campaign.update!(name: "Renamed") } }
      .to enqueue_a_table_refresh
    clear_enqueued_jobs
    expect { campaign.transaction { campaign.update!(name: "Renamed again"); raise ActiveRecord::Rollback } }.not_to enqueue_a_table_refresh
    expect { campaign.update!(name: "And again") }.not_to enqueue_a_table_refresh
  end
end
