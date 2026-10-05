# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A world's skills", type: :request do
  let(:campaign) { create_campaign }
  let(:world) { campaign.world }
  let!(:bartz) { create_character(campaign, name: "Bartz") }

  before { world.jobs.find_by!(slug: "knight").update!(skills: %w[athletics]) }

  def rows(skills = world.reload.skills)
    skills.each_with_index.to_h { |s, i| [ i.to_s, s ] }
  end

  it "lists the world's skills and the jobs good at each" do
    get world_skills_path(world)
    expect(response.body).to include("Athletics", "Stealth", "Knight")
  end

  it "rolls a GM's skill check on its stat, with the job's bonus" do
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    campaign.call_controls!("check") # the form comes to the table once Check is called
    get campaign_table_path(campaign)
    expect(response.body).to include("Athletics (Str)", 'value="skill:athletics"')

    post campaign_checks_path(campaign), params: { check: { characters: [ bartz.id ], stat: "skill:athletics", difficulty: "normal" } }
    line = campaign.messages.where(cue: "check").last
    expect(line.body).to match(/\ABartz: Athletics check \(normal, \+15 Knight\)\. needed 51 or over · rolled \d+( [+−]\d+ Str)? \+15 Knight = -?\d+ · (Success!|Failure\.)/)
    expect(line.data["modifiers"].last).to eq("label" => "Knight", "amount" => 15)
    expect(line.data).to include("skill" => "Athletics", "stat" => "str", "bonus" => 15)
    chance = Stats::Check.chance(stat_value: bartz.stats["str"], stat: "str", level: bartz.level, difficulty: "normal", bonus: 15)
    expect(line.data["chance"]).to eq(chance)
  end

  it "renames, adds and removes skills, taking removed ones off the jobs" do
    edited = world.skills.map { |s| s["slug"] == "athletics" ? s.merge("remove" => "1") : s }
    edited = edited.map { |s| s["slug"] == "lore" ? s.merge("name" => "Arcana") : s }
    patch world_skills_path(world), params: { skills: rows(edited).merge("99" => { name: "Hacking", stat: "mag", description: "Getting in." }) }
    expect(response).to redirect_to(world_skills_path(world))
    expect(world.reload.skills.map { |s| s["name"] }).to include("Arcana", "Hacking")
    expect(world.skill("athletics")).to be_nil
    expect(world.jobs.find_by!(slug: "knight").skills).to eq([])

    patch world_skills_path(world), params: { skills: rows(world.skills.map { |s| s.merge("remove" => "1") }) }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("need at least one")
  end

  it "shows a character's skills, and the chance of a normal check with each" do
    get character_path(bartz)
    expect(response.body).to include("Skills", "Athletics", "+15", "Chance")
  end
end
