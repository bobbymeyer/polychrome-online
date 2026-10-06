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
    post world_campaigns_path(world), params: { campaign: { name: "All", open_jobs: world.jobs.pluck(:slug) } }
    expect(Campaign.find_by!(name: "All").open_jobs).to be_nil

    # The boxes say it: some unticked is those jobs, even with "Every job" left ticked.
    post world_campaigns_path(world), params: { campaign: { name: "Some", every_job: "1", open_jobs: %w[knight freelancer] } }
    expect(Campaign.find_by!(name: "Some").open_jobs).to eq(%w[knight freelancer])
  end

  it "only lets characters take open jobs" do
    campaign = start(%w[freelancer])
    get new_campaign_character_path(campaign)
    expect(response.body).to include("Freelancer")
    expect(response.body).not_to include(">Knight<")

    post campaign_characters_path(campaign), params: { character: { name: "Butz", job_id: world.jobs.find_by!(slug: "knight").id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Knight isn&#39;t open in Shards yet")

    butz = base_character(campaign, name: "Butz", job: "freelancer")
    expect { butz.change_job!(world.jobs.find_by!(slug: "monk")) }.to raise_error(ActiveRecord::RecordInvalid, /isn't open/)
  end

  it "lets the GM grant an archetype to the party at the table, with a line and a card" do
    campaign = start(%w[freelancer])
    sit(campaign, "gm")
    campaign.call_controls!("tools") # GM tools is a control on the strip
    get campaign_table_path(campaign)
    expect(response.body).to include("Grant an archetype", "Knight", "Freelancer (open)")

    post campaign_job_grants_path(campaign), params: { job: "knight", character_id: "", line: "The Wind Crystal shatters." }
    expect(campaign.reload.available_jobs.map(&:slug)).to eq(%w[freelancer knight])
    line = campaign.messages.last
    expect(line.body).to eq("The Wind Crystal shatters. New archetype: Knight.")
    get campaign_table_path(campaign)
    expect(response.body).to include("New archetype!", "Heavy armor, a long sword")

    post campaign_job_grants_path(campaign), params: { job: "knight" }
    expect(flash[:alert]).to eq("Knight is open already")
  end

  it "awakens one character: the job opens, they take it up, and the table stops for it" do
    campaign = start(%w[freelancer])
    yui = create_character(campaign, name: "Yui", job: world.jobs.find_by!(slug: "freelancer"))
    sit(campaign, "gm")
    campaign.call_controls!("tools") # GM tools is a control on the strip
    get campaign_table_path(campaign)
    expect(response.body).to include("Grant an archetype", "moment#arrive")
    expect(page.at(".awakening-stage")["data-moment-cue"]).to eq("awakening")

    post campaign_job_grants_path(campaign), params: { character_id: yui.id, job: "monk", line: "I am thou, thou art I." }
    expect(yui.reload.job.slug).to eq("monk")
    expect(campaign.reload.available_jobs.map(&:slug)).to include("monk")
    line = campaign.messages.last
    expect(line).to have_attributes(body: "I am thou, thou art I. Yui awakens: Monk.", cue: "awakening")
    expect(line.data).to include("character" => yui.id, "name" => "Yui", "job" => "Monk", "line" => "I am thou, thou art I.")

    get campaign_table_path(campaign)
    card = JSON.parse(page.at("[data-chat-line-card-value]")["data-chat-line-card-value"])
    expect(card).to include("name" => "Yui", "job" => "Monk", "portrait" => "")
    expect(card["plate"]).to start_with("--plate:")

    post campaign_job_grants_path(campaign), params: { character_id: yui.id, job: "monk" }
    expect(flash[:alert]).to eq("Yui is a Monk already")
  end
end
