# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A story table's coverage (StoryCoverage)", type: :request do
  let!(:world) { base_world }
  let!(:table) do
    world.generator_tables.create!(name: "Night lines", slug: "night_lines", kind: "arrivals",
                                   entries: [ { "text" => "A town.", "when" => "town" },
                                              { "text" => "A town by night.", "when" => "town, night" },
                                              { "text" => "Never at all.", "when" => "town, dungeon" },
                                              { "text" => "The smoke again.", "when" => "town, smoke_seen" } ])
  end

  it "shows where a table is thin, which rows never come up, and a moment to try" do
    get world_generation_generator_table_path(world, table)
    expect(response.body).to include("Coverage: where it&#39;s thin")

    get world_generation_generator_table_coverage_path(world, table)
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at("h2:contains('Where it')").parent.text.squish).to match(/Nothing fits \d+% of the moments/)
    expect(page.css("tr.is-thin td:first-child").map(&:text)).to include(a_string_starting_with("Dungeon"), "3. Never at all.")
    never = page.css("tr").find { |tr| tr.text.include?("3. Never at all.") }
    expect(never.css("td.num").map(&:text)).to eq(%w[never never])
    smoke = page.css("tr").find { |tr| tr.text.include?("4. The smoke again.") }
    expect(smoke.css("td.num").map(&:text)).not_to include("never") # a flag the rows ask about is set in some moments

    get world_generation_generator_table_coverage_path(world, table, place: "town", period: "night", facts: "smoke_seen")
    tried = Nokogiri::HTML(response.body).css(".coverage-try li").map { |li| li.text.squish }
    expect(tried.first).to start_with("A town by night.").or start_with("The smoke again.")
    expect(tried.size).to eq(3)
    expect(response.body).to include("The first 2 tie")

    get world_generation_generator_table_coverage_path(world, table, place: "dungeon")
    expect(response.body).to include("Nothing fits. This is a line nobody has written yet.")
  end

  it "covers the seeded settings' story tables, whatever they ask about" do
    world.generator_tables.where(kind: GeneratorTable::STORY_KINDS).find_each do |story|
      get world_generation_generator_table_coverage_path(world, story)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Where it's thin", "Try a moment")
    end
  end

  it "is only for story tables" do
    names = world.generator_tables.find_by!(kind: "town_names")
    get world_generation_generator_table_coverage_path(world, names)
    expect(response).to have_http_status(:not_found)
  end
end
