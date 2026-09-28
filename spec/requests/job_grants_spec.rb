# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Jobs as story rewards", type: :request do
  let!(:world) { base_world }

  def start(open)
    post world_campaigns_path(world), params: { campaign: { name: "Shards", open_jobs: open } }
    Campaign.find_by!(name: "Shards")
  end

  it "opens a campaign with the jobs its GM picks, or every one" do
    campaign = start(%w[freelancer knight])
    expect(campaign.available_jobs.map(&:slug)).to eq(%w[freelancer knight])
    post world_campaigns_path(world), params: { campaign: { name: "All", every_job: "1", open_jobs: %w[knight] } }
    expect(Campaign.find_by!(name: "All").open_jobs).to be_nil
  end

  it "only lets characters take open jobs" do
    campaign = start(%w[freelancer])
    get new_campaign_character_path(campaign)
    expect(response.body).to include("Freelancer")
    expect(response.body).not_to include(">Knight<")

    post campaign_characters_path(campaign), params: { character: { name: "Butz", job_id: world.jobs.find_by!(slug: "knight").id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Knight isn&#39;t open in Shards yet")

    butz = campaign.characters.create!(name: "Butz", job: world.jobs.find_by!(slug: "freelancer"))
    expect { butz.change_job!(world.jobs.find_by!(slug: "monk")) }.to raise_error(ActiveRecord::RecordInvalid, /isn't open/)
  end

  it "lets the GM grant jobs at the table, with a line and a card for each" do
    campaign = start(%w[freelancer])
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    get campaign_table_path(campaign)
    expect(response.body).to include("Grant jobs", "Knight")

    post campaign_job_grants_path(campaign), params: { jobs: %w[knight monk], line: "The Wind Crystal shatters." }
    expect(campaign.reload.available_jobs.map(&:slug)).to eq(%w[freelancer knight monk])
    line = campaign.messages.last
    expect(line.body).to eq("The Wind Crystal shatters. New jobs: Knight and Monk.")
    get campaign_table_path(campaign)
    expect(response.body).to include("New job!", "Heavy armor, a long sword")

    post campaign_job_grants_path(campaign), params: { jobs: %w[knight] }
    expect(flash[:alert]).to eq("Pick a job that isn't open yet")
  end
end
