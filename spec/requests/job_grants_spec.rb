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

  it "awakens one character: the job opens, they take it up, and the table stops for it" do
    campaign = start(%w[freelancer])
    yui = create_character(campaign, name: "Yui", job: world.jobs.find_by!(slug: "freelancer"))
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    get campaign_table_path(campaign)
    expect(response.body).to include("Awaken someone", 'class="awakening-stage"', "awakening#arrive")

    post campaign_awakenings_path(campaign), params: { character_id: yui.id, job: "monk", line: "I am thou, thou art I." }
    expect(yui.reload.job.slug).to eq("monk")
    expect(campaign.reload.available_jobs.map(&:slug)).to include("monk")
    line = campaign.messages.last
    expect(line).to have_attributes(body: "I am thou, thou art I. Yui awakens: Monk.", cue: "awakening")
    expect(line.data).to include("character" => yui.id, "name" => "Yui", "job" => "Monk", "line" => "I am thou, thou art I.")

    get campaign_table_path(campaign)
    card = JSON.parse(CGI.unescapeHTML(response.body[/data-chat-line-card-value="([^"]+)"/, 1]))
    expect(card).to include("name" => "Yui", "job" => "Monk", "portrait" => "")
    expect(card["plate"]).to start_with("--plate:")

    post campaign_awakenings_path(campaign), params: { character_id: yui.id, job: "monk" }
    expect(flash[:alert]).to eq("Yui is a Monk already")
  end
end
